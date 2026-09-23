import AudioToolbox
import CoreAudio

protocol AudioInputPropertyClient: Sendable {
  func devices() throws -> [AudioDeviceID]
  func defaultInput() throws -> AudioDeviceID?
  func isDevice(_ id: AudioDeviceID) -> Bool
  func isAlive(_ id: AudioDeviceID) -> Bool?
  func isHidden(_ id: AudioDeviceID) -> Bool?
  func canBeDefaultInput(_ id: AudioDeviceID) -> Bool?
  func inputChannels(_ id: AudioDeviceID) -> Int
  func name(_ id: AudioDeviceID) -> String?
  func uid(_ id: AudioDeviceID) -> String?
  func hasProperty(
    _ id: AudioDeviceID,
    _ selector: AudioObjectPropertySelector,
    _ element: AudioObjectPropertyElement
  ) -> Bool
  func isSettable(
    _ id: AudioDeviceID,
    _ selector: AudioObjectPropertySelector,
    _ element: AudioObjectPropertyElement
  ) -> Bool
  func readScalar(_ id: AudioDeviceID, _ element: AudioObjectPropertyElement) -> Float32?
  func readMute(_ id: AudioDeviceID, _ element: AudioObjectPropertyElement) -> Bool?
  func writeScalar(
    _ value: Float32,
    on id: AudioDeviceID,
    element: AudioObjectPropertyElement
  ) throws
  func writeMute(
    _ value: Bool,
    on id: AudioDeviceID,
    element: AudioObjectPropertyElement
  ) throws
  func writeDefaultInput(_ id: AudioDeviceID) throws
}

protocol AudioInputHardware: Sendable {
  func read(includeDevices: Bool) throws -> AudioInputReading
  func selectDefault(_ id: AudioDeviceID) throws
  func setScalar(_ scalar: Double, on id: AudioDeviceID) throws
  func setMuted(_ muted: Bool, on id: AudioDeviceID) throws
}
