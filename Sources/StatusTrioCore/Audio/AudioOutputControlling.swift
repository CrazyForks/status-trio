import CoreAudio

@MainActor
protocol AudioOutputControlling: AnyObject {
    @discardableResult func setVolume(_ scalar: Double) -> Bool
    @discardableResult func toggleMute() -> Bool
    @discardableResult func selectOutputDevice(_ deviceID: AudioDeviceID) -> Bool
}
