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
  func volume(_ id: AudioDeviceID) -> AudioInputVolumeReadback
  func mute(_ id: AudioDeviceID) -> AudioInputMuteReadback
}

protocol AudioInputHardware: Sendable {
  func read(includeDevices: Bool) throws -> AudioInputReading
}
