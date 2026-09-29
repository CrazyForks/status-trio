import CoreAudio

@MainActor
protocol VolumeControlling: AnyObject {
    func setVolume(_ scalar: Double)
    func toggleMute()
    func selectOutputDevice(_ deviceID: AudioDeviceID)
    func flushPendingVolume()
}

extension VolumeControlling {
    func flushPendingVolume() {}
}
