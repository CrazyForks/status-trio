import CoreAudio

struct AudioOutputDevice: Identifiable, Equatable, Sendable {
    let id: AudioDeviceID
    let name: String?
    let uid: String?
    let isCurrent: Bool
    let volume: Double?
    /// The hardware family of the device, read from
    /// `kAudioDevicePropertyTransportType`.
    let transport: AudioOutputTransport?
    /// The live output data source, read from `kAudioDevicePropertyDataSource`.
    let dataSource: AudioOutputDataSource?

    init(
        id: AudioDeviceID,
        name: String?,
        uid: String? = nil,
        isCurrent: Bool,
        volume: Double? = nil,
        transport: AudioOutputTransport? = nil,
        dataSource: AudioOutputDataSource? = nil
    ) {
        self.id = id
        self.name = name
        self.uid = uid
        self.isCurrent = isCurrent
        self.volume = volume
        self.transport = transport
        self.dataSource = dataSource
    }
}
