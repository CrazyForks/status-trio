import CoreAudio

struct AudioOutputDevice: Identifiable, Equatable, Sendable {
    let id: AudioDeviceID
    let name: String?
    let uid: String?
    let isCurrent: Bool
    let volume: Double?

    init(
        id: AudioDeviceID,
        name: String?,
        uid: String? = nil,
        isCurrent: Bool,
        volume: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.uid = uid
        self.isCurrent = isCurrent
        self.volume = volume
    }
}
