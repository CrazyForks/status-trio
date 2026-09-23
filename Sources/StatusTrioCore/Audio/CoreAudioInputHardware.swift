import AudioToolbox
import CoreAudio
import CoreFoundation
import Darwin
import Foundation

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

    let volume = client.volume(selectedID)
    let mute = client.mute(selectedID)
    let validScalar = volume.scalar.flatMap { scalar -> Double? in
      scalar.isFinite && (0...1).contains(scalar) ? scalar : nil
    }
    let validMuteState: AudioInputMuteState? =
      switch mute.state {
      case .unmuted, .muted, .partial: mute.state
      case nil: nil
      }

    return AudioInputReading(
      devices: devices,
      defaultDeviceID: selectedID,
      deviceName: normalized(client.name(selectedID)),
      scalar: validScalar,
      canSetVolume: validScalar != nil && volume.canSet,
      muteState: validMuteState,
      canSetMute: validMuteState != nil && mute.canSet
    )
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

  func volume(_ id: AudioDeviceID) -> AudioInputVolumeReadback {
    let mainAddress = propertyAddress(
      selector: kAudioDevicePropertyVolumeScalar,
      scope: kAudioObjectPropertyScopeInput,
      element: kAudioObjectPropertyElementMain
    )
    if let scalar = readScalar(objectID: id, address: mainAddress),
      isSettable(objectID: id, address: mainAddress)
    {
      return AudioInputVolumeReadback(scalar: scalar, canSet: true)
    }

    let elements = inputChannelElements(id)
    guard !elements.isEmpty else { return .unsupported }
    let channelAddresses = elements.map {
      propertyAddress(
        selector: kAudioDevicePropertyVolumeScalar,
        scope: kAudioObjectPropertyScopeInput,
        element: $0
      )
    }
    let values = channelAddresses.compactMap { readScalar(objectID: id, address: $0) }
    guard values.count == channelAddresses.count,
      channelAddresses.allSatisfy({ isSettable(objectID: id, address: $0) })
    else {
      return .unsupported
    }
    return AudioInputVolumeReadback(
      scalar: values.reduce(0, +) / Double(values.count),
      canSet: true
    )
  }

  func mute(_ id: AudioDeviceID) -> AudioInputMuteReadback {
    let mainAddress = propertyAddress(
      selector: kAudioDevicePropertyMute,
      scope: kAudioObjectPropertyScopeInput,
      element: kAudioObjectPropertyElementMain
    )
    if let muted = readMute(objectID: id, address: mainAddress),
      isSettable(objectID: id, address: mainAddress)
    {
      return AudioInputMuteReadback(state: muted ? .muted : .unmuted, canSet: true)
    }

    let elements = inputChannelElements(id)
    guard !elements.isEmpty else { return .unsupported }
    let channelAddresses = elements.map {
      propertyAddress(
        selector: kAudioDevicePropertyMute,
        scope: kAudioObjectPropertyScopeInput,
        element: $0
      )
    }
    let values = channelAddresses.compactMap { readMute(objectID: id, address: $0) }
    guard values.count == channelAddresses.count,
      channelAddresses.allSatisfy({ isSettable(objectID: id, address: $0) })
    else {
      return .unsupported
    }

    let state: AudioInputMuteState
    if values.allSatisfy({ $0 }) {
      state = .muted
    } else if values.allSatisfy({ !$0 }) {
      state = .unmuted
    } else {
      state = .partial
    }
    return AudioInputMuteReadback(state: state, canSet: true)
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
    guard let value else { return nil }
    let string = value.takeRetainedValue() as String
    guard status == noErr, returnedSize == size else { return nil }
    return string
  }

  private func readScalar(
    objectID: AudioObjectID,
    address: AudioObjectPropertyAddress
  ) -> Double? {
    guard let value: Float32 = readValue(objectID: objectID, address: address),
      value.isFinite,
      (0...1).contains(value)
    else { return nil }
    return Double(value)
  }

  private func readMute(
    objectID: AudioObjectID,
    address: AudioObjectPropertyAddress
  ) -> Bool? {
    guard let value: UInt32 = readValue(objectID: objectID, address: address),
      value <= 1
    else { return nil }
    return value == 1
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

  private func inputChannelElements(_ id: AudioDeviceID) -> [AudioObjectPropertyElement] {
    let count = inputChannels(id)
    guard count > 0 else { return [] }
    return (1...count).map(AudioObjectPropertyElement.init)
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
