import AudioToolbox
import CoreAudio
import XCTest

@testable import StatusTrioCore

final class AudioInputHardwareTests: XCTestCase {
  func testFiltersIneligibleDevicesAndPreservesDuplicateNamesAndMissingUID() throws {
    let hardware = CoreAudioInputHardware(client: makeClient())

    let reading = try hardware.read(includeDevices: true)

    XCTAssertEqual(reading.devices?.map(\.id), [11, 15])
    XCTAssertEqual(reading.defaultDeviceID, 11)
    XCTAssertEqual(reading.devices?.map(\.name), ["Shared microphone", "Shared microphone"])
    XCTAssertNotEqual(reading.devices?[0].id, reading.devices?[1].id)
    XCTAssertNil(reading.devices?[1].uid, "A missing UID must not be synthesized from the name")
  }

  func testDoesNotEnumerateWhenDeviceListIsNotRequested() throws {
    let hardware = CoreAudioInputHardware(
      client: makeClient(devicesError: .unavailable)
    )

    let reading = try hardware.read(includeDevices: false)

    XCTAssertNil(reading.devices, "nil distinguishes skipped enumeration from an empty list")
    XCTAssertEqual(reading.defaultDeviceID, 11)
    XCTAssertEqual(reading.deviceName, "Shared microphone")
    XCTAssertEqual(reading.scalar, 0.42)
    XCTAssertTrue(reading.canSetVolume)
    XCTAssertEqual(reading.muteState, .muted)
    XCTAssertTrue(reading.canSetMute)
  }

  func testNoDefaultInputStillReturnsEligibleDevices() throws {
    let hardware = CoreAudioInputHardware(
      client: makeClient(defaultID: nil, deviceIDs: [15])
    )

    let reading = try hardware.read(includeDevices: true)

    XCTAssertEqual(reading.devices?.map(\.id), [15])
    XCTAssertNil(reading.defaultDeviceID)
    XCTAssertNil(reading.deviceName)
    XCTAssertNil(reading.scalar)
    XCTAssertFalse(reading.canSetVolume)
    XCTAssertNil(reading.muteState)
    XCTAssertFalse(reading.canSetMute)
  }

  func testEmptyHardwareReturnsAnEmptyEnumeratedList() throws {
    let hardware = CoreAudioInputHardware(
      client: makeClient(defaultID: nil, deviceIDs: [])
    )

    let reading = try hardware.read(includeDevices: true)

    XCTAssertEqual(reading.devices, [])
    XCTAssertNil(reading.defaultDeviceID)
    XCTAssertNil(reading.deviceName)
  }

  func testInvalidDefaultIsNotSelectedButEligibleDevicesRemainAvailable() throws {
    let hardware = CoreAudioInputHardware(
      client: makeClient(defaultID: 99, deviceIDs: [11, 12])
    )

    let reading = try hardware.read(includeDevices: true)

    XCTAssertEqual(reading.devices?.map(\.id), [11])
    XCTAssertNil(reading.defaultDeviceID)
    XCTAssertNil(reading.deviceName)
    XCTAssertNil(reading.scalar)
    XCTAssertFalse(reading.canSetVolume)
  }

  func testBlankDeviceNamesBecomeNilWithoutRemovingDevices() throws {
    let hardware = CoreAudioInputHardware(
      client: makeClient(
        defaultID: 15,
        deviceIDs: [15],
        overrides: [15: .eligible(name: "   ", uid: nil)]
      )
    )

    let reading = try hardware.read(includeDevices: true)

    XCTAssertEqual(reading.devices?.map(\.id), [15])
    XCTAssertNil(reading.devices?.first?.name)
    XCTAssertNil(reading.deviceName)
  }

  func testUnreportedEligibilityPropertiesFailClosed() throws {
    let hardware = CoreAudioInputHardware(
      client: makeClient(
        defaultID: 11,
        deviceIDs: [11],
        overrides: [11: .eligible(name: "Microphone", uid: "mic", alive: nil)]
      )
    )

    let reading = try hardware.read(includeDevices: true)

    XCTAssertEqual(reading.devices, [])
    XCTAssertNil(reading.defaultDeviceID)
    XCTAssertNil(reading.deviceName)
  }

  func testInvalidControlReadbackIsNotPresentedAsSupported() throws {
    let hardware = CoreAudioInputHardware(
      client: makeClient(
        defaultID: 11,
        deviceIDs: [11],
        overrides: [
          11: .eligible(
            name: "Microphone",
            uid: "mic",
            volume: AudioInputVolumeReadback(scalar: .infinity, canSet: true),
            mute: AudioInputMuteReadback(state: nil, canSet: true)
          )
        ]
      )
    )

    let reading = try hardware.read(includeDevices: true)

    XCTAssertNil(reading.scalar)
    XCTAssertFalse(reading.canSetVolume)
    XCTAssertNil(reading.muteState)
    XCTAssertFalse(reading.canSetMute)
  }

  private func makeClient(
    defaultID: AudioDeviceID? = 11,
    deviceIDs: [AudioDeviceID] = [11, 12, 13, 14, 15, AudioDeviceID(kAudioObjectUnknown)],
    devicesError: AudioInputHardwareError? = nil,
    overrides: [AudioDeviceID: FakeDevice] = [:]
  ) -> FakeAudioInputPropertyClient {
    var devices: [AudioDeviceID: FakeDevice] = [
      11: FakeDevice.eligible(
        name: "Shared microphone",
        uid: "com.example.mic.internal",
        volume: AudioInputVolumeReadback(scalar: 0.42, canSet: true),
        mute: AudioInputMuteReadback(state: .muted, canSet: true)
      ),
      12: FakeDevice.eligible(name: "Hidden microphone", uid: "hidden", hidden: true),
      13: FakeDevice.eligible(name: "No input channels", uid: "no-input", channels: 0),
      14: FakeDevice.eligible(name: "Cannot be default", uid: "not-default", canBeDefault: false),
      15: FakeDevice.eligible(name: "Shared microphone", uid: nil),
    ]
    devices.merge(overrides) { _, replacement in replacement }
    return FakeAudioInputPropertyClient(
      deviceIDs: deviceIDs,
      defaultID: defaultID,
      devicesError: devicesError,
      devices: devices
    )
  }
}

private struct FakeAudioInputPropertyClient: AudioInputPropertyClient {
  let deviceIDs: [AudioDeviceID]
  let defaultID: AudioDeviceID?
  let devicesError: AudioInputHardwareError?
  let devicesByID: [AudioDeviceID: FakeDevice]

  init(
    deviceIDs: [AudioDeviceID],
    defaultID: AudioDeviceID?,
    devicesError: AudioInputHardwareError?,
    devices: [AudioDeviceID: FakeDevice]
  ) {
    self.deviceIDs = deviceIDs
    self.defaultID = defaultID
    self.devicesError = devicesError
    self.devicesByID = devices
  }

  func devices() throws -> [AudioDeviceID] {
    if let devicesError { throw devicesError }
    return deviceIDs
  }

  func defaultInput() throws -> AudioDeviceID? { defaultID }
  func isDevice(_ id: AudioDeviceID) -> Bool { devicesByID[id]?.isDevice ?? false }
  func isAlive(_ id: AudioDeviceID) -> Bool? { devicesByID[id]?.isAlive }
  func isHidden(_ id: AudioDeviceID) -> Bool? { devicesByID[id]?.isHidden }
  func canBeDefaultInput(_ id: AudioDeviceID) -> Bool? { devicesByID[id]?.canBeDefault }
  func inputChannels(_ id: AudioDeviceID) -> Int { devicesByID[id]?.channels ?? 0 }
  func name(_ id: AudioDeviceID) -> String? { devicesByID[id]?.name }
  func uid(_ id: AudioDeviceID) -> String? { devicesByID[id]?.uid }
  func volume(_ id: AudioDeviceID) -> AudioInputVolumeReadback {
    devicesByID[id]?.volume ?? .unsupported
  }
  func mute(_ id: AudioDeviceID) -> AudioInputMuteReadback { devicesByID[id]?.mute ?? .unsupported }
}

private struct FakeDevice {
  let isDevice: Bool
  let isAlive: Bool?
  let isHidden: Bool?
  let canBeDefault: Bool?
  let channels: Int
  let name: String?
  let uid: String?
  let volume: AudioInputVolumeReadback
  let mute: AudioInputMuteReadback

  static func eligible(
    name: String?,
    uid: String?,
    hidden: Bool? = false,
    canBeDefault: Bool? = true,
    channels: Int = 1,
    alive: Bool? = true,
    volume: AudioInputVolumeReadback = .unsupported,
    mute: AudioInputMuteReadback = .unsupported
  ) -> FakeDevice {
    FakeDevice(
      isDevice: true,
      isAlive: alive,
      isHidden: hidden,
      canBeDefault: canBeDefault,
      channels: channels,
      name: name,
      uid: uid,
      volume: volume,
      mute: mute
    )
  }
}
