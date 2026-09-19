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

    /// The device-enumeration policy of the production read, split out so it can
    /// be exercised without audio hardware: the device list is read only when it
    /// was requested and only when a default output device exists, and `nil`
    /// keeps meaning "not requested".
    nonisolated static func assemble(
        includeOutputDevices: Bool,
        readVolume: @Sendable () -> VolumeReading?,
        readDevices: @Sendable () -> [AudioOutputDevice]
    ) -> AudioStatusReading {
        let volume = readVolume()
        let devices = includeOutputDevices && volume != nil ? readDevices() : nil
        return AudioStatusReading(volume: volume, outputDevices: devices)
    }

    init(readSystem: @escaping @Sendable (Bool) -> AudioStatusReading = { includeOutputDevices in
        CoreAudioStatusReader.assemble(
            includeOutputDevices: includeOutputDevices,
            readVolume: { CoreAudioVolumeReader().read() },
            readDevices: { CoreAudioOutputController().outputDevices() }
        )
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
