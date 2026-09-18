import Foundation

struct AudioStatusReading: Sendable {
    let volume: VolumeReading?
    /// `nil` means enumeration was not requested; an empty array is a valid result.
    let outputDevices: [AudioOutputDevice]?
}

@MainActor
protocol AudioStatusReadingProviding: AnyObject {
    func read(
        includeOutputDevices: Bool,
        completion: @escaping @MainActor @Sendable (AudioStatusReading) -> Void
    )
}

/// CoreAudio property reads may wait for an audio service or device driver.
/// Use one serial queue, outside both MainActor and the cooperative executor.
@MainActor
final class CoreAudioStatusReader: AudioStatusReadingProviding {
    private let queue = DispatchQueue(label: "StatusTrio.AudioStatusReader", qos: .utility)
    private let readSystem: @Sendable (Bool) -> AudioStatusReading

    init(readSystem: @escaping @Sendable (Bool) -> AudioStatusReading = { includeOutputDevices in
        let volume = CoreAudioVolumeReader().read()
        let devices = includeOutputDevices && volume != nil
            ? CoreAudioOutputController().outputDevices() : nil
        return AudioStatusReading(volume: volume, outputDevices: devices)
    }) {
        self.readSystem = readSystem
    }

    func read(
        includeOutputDevices: Bool,
        completion: @escaping @MainActor @Sendable (AudioStatusReading) -> Void
    ) {
        let readSystem = readSystem
        queue.async {
            let reading = readSystem(includeOutputDevices)
            Task { @MainActor in completion(reading) }
        }
    }
}
