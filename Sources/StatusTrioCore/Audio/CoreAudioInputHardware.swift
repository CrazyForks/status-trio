import AudioToolbox
import CoreAudio
import CoreFoundation
import Darwin
import Foundation

func withValidatedCoreAudioPropertyData<Value>(
  status: OSStatus,
  returnedSize: UInt32,
  expectedSize: UInt32,
  consume: () -> Value?
) -> Value? {
  guard status == noErr, returnedSize == expectedSize else { return nil }
  return consume()
}

enum CoreAudioInputControlReadback {
  static func volume(
    mainScalar: Double?,
    mainCanSet: Bool,
    channelScalars: [Double?],
    channelCanSet: [Bool]
  ) -> AudioInputVolumeReadback {
    let validMain = mainScalar.flatMap(validScalar)
    let validChannels = channelScalars.map { $0.flatMap(validScalar) }
    let allChannelsReadable = !validChannels.isEmpty && validChannels.allSatisfy { $0 != nil }
    let allChannelsSettable =
      channelCanSet.count == validChannels.count && channelCanSet.allSatisfy { $0 }

    if let validMain, mainCanSet {
      return AudioInputVolumeReadback(scalar: validMain, canSet: true)
    }
    if allChannelsReadable, allChannelsSettable {
      return AudioInputVolumeReadback(scalar: average(validChannels), canSet: true)
    }
    if let validMain {
      return AudioInputVolumeReadback(scalar: validMain, canSet: false)
    }
    guard allChannelsReadable else { return .unsupported }
    return AudioInputVolumeReadback(scalar: average(validChannels), canSet: false)
  }

  static func mute(
    mainValue: Bool?,
    mainCanSet: Bool,
    channelValues: [Bool?],
    channelCanSet: [Bool]
  ) -> AudioInputMuteReadback {
    let allChannelsReadable = !channelValues.isEmpty && channelValues.allSatisfy { $0 != nil }
    let allChannelsSettable =
      channelCanSet.count == channelValues.count && channelCanSet.allSatisfy { $0 }

    if let mainValue, mainCanSet {
      return AudioInputMuteReadback(state: mainValue ? .muted : .unmuted, canSet: true)
    }
    if allChannelsReadable, allChannelsSettable {
      return AudioInputMuteReadback(state: muteState(channelValues.compactMap { $0 }), canSet: true)
    }
    if let mainValue {
      return AudioInputMuteReadback(state: mainValue ? .muted : .unmuted, canSet: false)
    }
    guard allChannelsReadable else { return .unsupported }
    return AudioInputMuteReadback(state: muteState(channelValues.compactMap { $0 }), canSet: false)
  }

  private static func validScalar(_ scalar: Double) -> Double? {
    scalar.isFinite && (0...1).contains(scalar) ? scalar : nil
  }

  private static func average(_ values: [Double?]) -> Double {
    let scalars = values.compactMap { $0 }
    return scalars.reduce(0, +) / Double(scalars.count)
  }

  private static func muteState(_ values: [Bool]) -> AudioInputMuteState {
    if values.allSatisfy({ $0 }) { return .muted }
    if values.allSatisfy({ !$0 }) { return .unmuted }
    return .partial
  }
}

struct CoreAudioInputHardware: AudioInputHardware {
  private let client: any AudioInputPropertyClient

  init(client: any AudioInputPropertyClient = CoreAudioInputPropertyClient()) {
    self.client = client
  }

  func read(includeDevices: Bool) throws -> AudioInputReading {
    let systemDefaultID = try client.defaultInput()
      .flatMap { $0 == AudioDeviceID(kAudioObjectUnknown) ? nil : $0 }

    let candidateIDs: [AudioDeviceID]
    if includeDevices {
      candidateIDs = try client.devices()
    } else {
      candidateIDs = systemDefaultID.map { [$0] } ?? []
    }

    let eligibleIDs = candidateIDs.reduce(into: [AudioDeviceID]()) { result, id in
      guard !result.contains(id), isEligibleInput(id) else { return }
      result.append(id)
    }
    let selectedID = systemDefaultID.flatMap { eligibleIDs.contains($0) ? $0 : nil }

    let devices =
      includeDevices
      ? eligibleIDs.map { id in
        AudioInputDevice(
          id: id,
          uid: normalized(client.uid(id)),
          name: normalized(client.name(id))
        )
      }
      : nil

    guard let selectedID else {
      return AudioInputReading(
        devices: devices,
        defaultDeviceID: nil,
        deviceName: nil,
        scalar: nil,
        canSetVolume: false,
        muteState: nil,
        canSetMute: false
      )
    }

    let volume = readVolume(selectedID)
    let mute = readMute(selectedID)

    return AudioInputReading(
      devices: devices,
      defaultDeviceID: selectedID,
      deviceName: normalized(client.name(selectedID)),
      scalar: volume.scalar,
      canSetVolume: volume.scalar != nil && volume.canSet,
      muteState: mute.state,
      canSetMute: mute.state != nil && mute.canSet
    )
  }

  func selectDefault(_ id: AudioDeviceID) throws {
    guard isEligibleInput(id) else { throw AudioInputHardwareError.unavailable }
    try client.writeDefaultInput(id)
  }

  func setScalar(_ scalar: Double, on id: AudioDeviceID) throws {
    guard scalar.isFinite else { throw AudioInputHardwareError.invalidValue }
    let value = Float32(min(max(scalar, 0), 1))
    let elements = try writableElements(
      for: id,
      selector: kAudioDevicePropertyVolumeScalar
    )
    for element in elements {
      try revalidateWritableProperty(id, selector: kAudioDevicePropertyVolumeScalar, element: element)
      try client.writeScalar(value, on: id, element: element)
    }
  }

  func setMuted(_ muted: Bool, on id: AudioDeviceID) throws {
    let elements = try writableElements(for: id, selector: kAudioDevicePropertyMute)
    for element in elements {
      try revalidateWritableProperty(id, selector: kAudioDevicePropertyMute, element: element)
      try client.writeMute(muted, on: id, element: element)
    }
  }

  private func readVolume(_ id: AudioDeviceID) -> AudioInputVolumeReadback {
    let selector = kAudioDevicePropertyVolumeScalar
    let main = kAudioObjectPropertyElementMain
    let mainValue = client.hasProperty(id, selector, main)
      ? client.readScalar(id, main).map(Double.init)
      : nil
    let channelElements = inputChannelElements(for: id)
    let channelValues = channelElements.map { element in
      client.hasProperty(id, selector, element)
        ? client.readScalar(id, element).map(Double.init)
        : nil
    }
    return CoreAudioInputControlReadback.volume(
      mainScalar: mainValue,
      mainCanSet: isPropertySettable(id, selector: selector, element: main),
      channelScalars: channelValues,
      channelCanSet: channelElements.map {
        isPropertySettable(id, selector: selector, element: $0)
      }
    )
  }

  private func readMute(_ id: AudioDeviceID) -> AudioInputMuteReadback {
    let selector = kAudioDevicePropertyMute
    let main = kAudioObjectPropertyElementMain
    let mainValue = client.hasProperty(id, selector, main)
      ? client.readMute(id, main)
      : nil
    let channelElements = inputChannelElements(for: id)
    let channelValues = channelElements.map { element in
      client.hasProperty(id, selector, element) ? client.readMute(id, element) : nil
    }
    return CoreAudioInputControlReadback.mute(
      mainValue: mainValue,
      mainCanSet: isPropertySettable(id, selector: selector, element: main),
      channelValues: channelValues,
      channelCanSet: channelElements.map {
        isPropertySettable(id, selector: selector, element: $0)
      }
    )
  }

  private func writableElements(
    for id: AudioDeviceID,
    selector: AudioObjectPropertySelector
  ) throws -> [AudioObjectPropertyElement] {
    guard isEligibleInput(id) else { throw AudioInputHardwareError.unavailable }
    let channels = inputChannelElements(for: id)

    func usable(_ element: AudioObjectPropertyElement) -> Bool {
      guard isPropertySettable(id, selector: selector, element: element) else { return false }
      if selector == kAudioDevicePropertyVolumeScalar {
        guard let scalar = client.readScalar(id, element) else { return false }
        return scalar.isFinite && (0...1).contains(scalar)
      }
      return client.readMute(id, element) != nil
    }

    let main = kAudioObjectPropertyElementMain
    if usable(main) { return [main] }
    guard !channels.isEmpty, channels.allSatisfy(usable) else {
      throw AudioInputHardwareError.unsupported
    }
    return channels
  }

  private func revalidateWritableProperty(
    _ id: AudioDeviceID,
    selector: AudioObjectPropertySelector,
    element: AudioObjectPropertyElement
  ) throws {
    guard isEligibleInput(id) else { throw AudioInputHardwareError.unavailable }
    guard isPropertySettable(id, selector: selector, element: element) else {
      throw AudioInputHardwareError.unsupported
    }
    if selector == kAudioDevicePropertyVolumeScalar {
      guard let scalar = client.readScalar(id, element), scalar.isFinite, (0...1).contains(scalar) else {
        throw AudioInputHardwareError.unsupported
      }
    } else if client.readMute(id, element) == nil {
      throw AudioInputHardwareError.unsupported
    }
  }

  private func isPropertySettable(
    _ id: AudioDeviceID,
    selector: AudioObjectPropertySelector,
    element: AudioObjectPropertyElement
  ) -> Bool {
    client.hasProperty(id, selector, element) && client.isSettable(id, selector, element)
  }

  private func inputChannelElements(for id: AudioDeviceID) -> [AudioObjectPropertyElement] {
    let count = client.inputChannels(id)
    guard count > 0 else { return [] }
    return (1...count).map(AudioObjectPropertyElement.init)
  }

  private func isEligibleInput(_ id: AudioDeviceID) -> Bool {
    id != AudioDeviceID(kAudioObjectUnknown)
      && client.isDevice(id)
      && client.isAlive(id) == true
      && client.isHidden(id) == false
      && client.canBeDefaultInput(id) == true
      && client.inputChannels(id) > 0
  }

  private func normalized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

private struct CoreAudioInputPropertyClient: AudioInputPropertyClient {
  private let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

  func devices() throws -> [AudioDeviceID] {
    var address = propertyAddress(selector: kAudioHardwarePropertyDevices)
    let requestedSize = try propertyDataSize(systemObjectID, address: &address)
    let deviceSize = MemoryLayout<AudioDeviceID>.size
    guard Int(requestedSize) % deviceSize == 0 else {
      throw AudioInputHardwareError.invalidValue
    }

    let count = Int(requestedSize) / deviceSize
    guard count > 0 else { return [] }
    var values = Array(repeating: AudioDeviceID(kAudioObjectUnknown), count: count)
    var returnedSize = requestedSize
    let status = values.withUnsafeMutableBytes { buffer in
      AudioObjectGetPropertyData(
        systemObjectID,
        &address,
        0,
        nil,
        &returnedSize,
        buffer.baseAddress!
      )
    }
    guard status == noErr else { throw AudioInputHardwareError.osStatus(status) }
    guard returnedSize == requestedSize, Int(returnedSize) % deviceSize == 0 else {
      throw AudioInputHardwareError.invalidValue
    }
    return values.filter { $0 != AudioDeviceID(kAudioObjectUnknown) }
  }

  func defaultInput() throws -> AudioDeviceID? {
    var address = propertyAddress(selector: kAudioHardwarePropertyDefaultInputDevice)
    let expectedSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    let reportedSize = try propertyDataSize(systemObjectID, address: &address)
    guard reportedSize == expectedSize else { throw AudioInputHardwareError.invalidValue }

    var deviceID = AudioDeviceID(kAudioObjectUnknown)
    var returnedSize = reportedSize
    let status = AudioObjectGetPropertyData(
      systemObjectID,
      &address,
      0,
      nil,
      &returnedSize,
      &deviceID
    )
    guard status == noErr else { throw AudioInputHardwareError.osStatus(status) }
    guard returnedSize == expectedSize else { throw AudioInputHardwareError.invalidValue }
    return deviceID == AudioDeviceID(kAudioObjectUnknown) ? nil : deviceID
  }

  func isDevice(_ id: AudioDeviceID) -> Bool {
    guard
      let objectClass: AudioClassID = readValue(
        objectID: id,
        selector: kAudioObjectPropertyClass
      )
    else {
      return false
    }
    return objectClass == kAudioDeviceClassID
  }

  func isAlive(_ id: AudioDeviceID) -> Bool? {
    readBoolean(
      objectID: id,
      selector: kAudioDevicePropertyDeviceIsAlive,
      scope: kAudioObjectPropertyScopeInput
    )
  }

  func isHidden(_ id: AudioDeviceID) -> Bool? {
    readBoolean(
      objectID: id,
      selector: kAudioDevicePropertyIsHidden,
      scope: kAudioObjectPropertyScopeInput
    )
  }

  func canBeDefaultInput(_ id: AudioDeviceID) -> Bool? {
    readBoolean(
      objectID: id,
      selector: kAudioDevicePropertyDeviceCanBeDefaultDevice,
      scope: kAudioObjectPropertyScopeInput
    )
  }

  func inputChannels(_ id: AudioDeviceID) -> Int {
    let address = propertyAddress(
      selector: kAudioDevicePropertyStreamConfiguration,
      scope: kAudioObjectPropertyScopeInput
    )
    return (try? streamChannelCount(objectID: id, address: address)) ?? 0
  }

  func name(_ id: AudioDeviceID) -> String? {
    readString(objectID: id, selector: kAudioObjectPropertyName)
  }

  func uid(_ id: AudioDeviceID) -> String? {
    readString(objectID: id, selector: kAudioDevicePropertyDeviceUID)
  }

  func hasProperty(
    _ id: AudioDeviceID,
    _ selector: AudioObjectPropertySelector,
    _ element: AudioObjectPropertyElement
  ) -> Bool {
    var address = propertyAddress(
      selector: selector,
      scope: kAudioObjectPropertyScopeInput,
      element: element
    )
    return AudioObjectHasProperty(id, &address)
  }

  func isSettable(
    _ id: AudioDeviceID,
    _ selector: AudioObjectPropertySelector,
    _ element: AudioObjectPropertyElement
  ) -> Bool {
    var address = propertyAddress(
      selector: selector,
      scope: kAudioObjectPropertyScopeInput,
      element: element
    )
    guard AudioObjectHasProperty(id, &address) else { return false }
    var settable = DarwinBoolean(false)
    return AudioObjectIsPropertySettable(id, &address, &settable) == noErr && settable.boolValue
  }

  func readScalar(_ id: AudioDeviceID, _ element: AudioObjectPropertyElement) -> Float32? {
    guard hasProperty(id, kAudioDevicePropertyVolumeScalar, element) else { return nil }
    return readValue(
      objectID: id,
      address: propertyAddress(
        selector: kAudioDevicePropertyVolumeScalar,
        scope: kAudioObjectPropertyScopeInput,
        element: element
      )
    )
  }

  func readMute(_ id: AudioDeviceID, _ element: AudioObjectPropertyElement) -> Bool? {
    guard hasProperty(id, kAudioDevicePropertyMute, element),
      let value: UInt32 = readValue(
        objectID: id,
        address: propertyAddress(
          selector: kAudioDevicePropertyMute,
          scope: kAudioObjectPropertyScopeInput,
          element: element
        )
      ), value <= 1
    else { return nil }
    return value == 1
  }

  func writeScalar(
    _ value: Float32,
    on id: AudioDeviceID,
    element: AudioObjectPropertyElement
  ) throws {
    guard value.isFinite, (0...1).contains(value) else {
      throw AudioInputHardwareError.invalidValue
    }
    guard isSettable(id, kAudioDevicePropertyVolumeScalar, element) else {
      throw AudioInputHardwareError.unsupported
    }
    var address = propertyAddress(
      selector: kAudioDevicePropertyVolumeScalar,
      scope: kAudioObjectPropertyScopeInput,
      element: element
    )
    var mutableValue = value
    let status = AudioObjectSetPropertyData(
      id,
      &address,
      0,
      nil,
      UInt32(MemoryLayout<Float32>.size),
      &mutableValue
    )
    guard status == noErr else { throw AudioInputHardwareError.osStatus(status) }
  }

  func writeMute(
    _ value: Bool,
    on id: AudioDeviceID,
    element: AudioObjectPropertyElement
  ) throws {
    guard isSettable(id, kAudioDevicePropertyMute, element) else {
      throw AudioInputHardwareError.unsupported
    }
    var address = propertyAddress(
      selector: kAudioDevicePropertyMute,
      scope: kAudioObjectPropertyScopeInput,
      element: element
    )
    var mutableValue: UInt32 = value ? 1 : 0
    let status = AudioObjectSetPropertyData(
      id,
      &address,
      0,
      nil,
      UInt32(MemoryLayout<UInt32>.size),
      &mutableValue
    )
    guard status == noErr else { throw AudioInputHardwareError.osStatus(status) }
  }

  func writeDefaultInput(_ id: AudioDeviceID) throws {
    var address = propertyAddress(selector: kAudioHardwarePropertyDefaultInputDevice)
    var mutableID = id
    let status = AudioObjectSetPropertyData(
      systemObjectID,
      &address,
      0,
      nil,
      UInt32(MemoryLayout<AudioDeviceID>.size),
      &mutableID
    )
    guard status == noErr else { throw AudioInputHardwareError.osStatus(status) }
  }

  private func readBoolean(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope
  ) -> Bool? {
    guard
      let value: UInt32 = readValue(
        objectID: objectID,
        selector: selector,
        scope: scope
      ), value <= 1
    else { return nil }
    return value == 1
  }

  private func readString(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector
  ) -> String? {
    var address = propertyAddress(selector: selector)
    guard let size = try? propertyDataSize(objectID, address: &address),
      size == UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    else { return nil }

    var value: Unmanaged<CFString>?
    var returnedSize = size
    let status = AudioObjectGetPropertyData(
      objectID,
      &address,
      0,
      nil,
      &returnedSize,
      &value
    )
    return withValidatedCoreAudioPropertyData(
      status: status,
      returnedSize: returnedSize,
      expectedSize: size
    ) {
      guard let value else { return nil }
      return value.takeRetainedValue() as String
    }
  }


  private func readValue<Value>(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> Value? {
    readValue(
      objectID: objectID,
      address: propertyAddress(selector: selector, scope: scope)
    )
  }

  private func readValue<Value>(
    objectID: AudioObjectID,
    address sourceAddress: AudioObjectPropertyAddress
  ) -> Value? {
    var address = sourceAddress
    guard let size = try? propertyDataSize(objectID, address: &address),
      size == UInt32(MemoryLayout<Value>.size)
    else { return nil }
    // This helper is only used for fixed-size CoreAudio scalar types.
    let storage = UnsafeMutableRawPointer.allocate(
      byteCount: MemoryLayout<Value>.size,
      alignment: MemoryLayout<Value>.alignment
    )
    defer { storage.deallocate() }

    var returnedSize = size
    let status = AudioObjectGetPropertyData(
      objectID,
      &address,
      0,
      nil,
      &returnedSize,
      storage
    )
    guard status == noErr, returnedSize == size else { return nil }
    return storage.load(as: Value.self)
  }

  private func isSettable(
    objectID: AudioObjectID,
    address sourceAddress: AudioObjectPropertyAddress
  ) -> Bool {
    var address = sourceAddress
    guard AudioObjectHasProperty(objectID, &address) else { return false }
    var settable = DarwinBoolean(false)
    return AudioObjectIsPropertySettable(objectID, &address, &settable) == noErr
      && settable.boolValue
  }


  private func streamChannelCount(
    objectID: AudioObjectID,
    address sourceAddress: AudioObjectPropertyAddress
  ) throws -> Int {
    var address = sourceAddress
    let requestedSize = try propertyDataSize(objectID, address: &address)
    guard requestedSize >= UInt32(MemoryLayout<AudioBufferList>.size) else {
      throw AudioInputHardwareError.invalidValue
    }

    let storage = UnsafeMutableRawPointer.allocate(
      byteCount: Int(requestedSize),
      alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { storage.deallocate() }

    let bufferList = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
    var returnedSize = requestedSize
    let status = AudioObjectGetPropertyData(
      objectID,
      &address,
      0,
      nil,
      &returnedSize,
      bufferList
    )
    guard status == noErr else { throw AudioInputHardwareError.osStatus(status) }
    guard returnedSize >= UInt32(MemoryLayout<AudioBufferList>.size),
      returnedSize <= requestedSize
    else { throw AudioInputHardwareError.invalidValue }

    let bufferCount = Int(bufferList.pointee.mNumberBuffers)
    let headerSize = MemoryLayout<AudioBufferList>.size
    let trailingBufferCount = max(0, bufferCount - 1)
    let (requiredTail, overflow) = trailingBufferCount.multipliedReportingOverflow(
      by: MemoryLayout<AudioBuffer>.stride
    )
    guard !overflow,
      headerSize <= Int(returnedSize),
      requiredTail <= Int(returnedSize) - headerSize
    else {
      throw AudioInputHardwareError.invalidValue
    }

    return UnsafeMutableAudioBufferListPointer(bufferList).reduce(0) { total, buffer in
      total + Int(buffer.mNumberChannels)
    }
  }

  private func propertyDataSize(
    _ objectID: AudioObjectID,
    address: inout AudioObjectPropertyAddress
  ) throws -> UInt32 {
    guard AudioObjectHasProperty(objectID, &address) else {
      throw AudioInputHardwareError.unsupported
    }
    var size: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size)
    guard status == noErr else { throw AudioInputHardwareError.osStatus(status) }
    return size
  }

  private func propertyAddress(
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
  }
}
