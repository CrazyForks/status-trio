import CoreAudio
import Foundation

/// One CoreAudio output endpoint that could be the playback endpoint of a
/// HUAWEI device. `uid` is kept because macOS names a Bluetooth endpoint
/// `<address>:output`, which is the only trusted address evidence available
/// without an IOBluetooth round trip.
struct HuaweiAudioEndpoint: Equatable, Sendable {
    let id: AudioDeviceID
    let uid: String?
    let name: String?
}

enum HuaweiAudioEndpointMatcher {
    /// Resolves a Bluetooth device to one output endpoint.
    ///
    /// Address evidence wins, exactly as it does for AirPods. Name matching is
    /// only the fallback for an endpoint whose UID does not carry the address,
    /// and it must be exact after trimming and case-folding; a partial name can
    /// select a different pair of buds and send the tap to the wrong hardware.
    static func endpointID(
        forAddress address: String,
        deviceName: String,
        in endpoints: [HuaweiAudioEndpoint]
    ) -> AudioDeviceID? {
        let target = BluetoothBatteryReader.normalizedAddress(address)
        guard !target.isEmpty else { return nil }

        let addressMatches = endpoints.filter { endpoint in
            guard let uid = endpoint.uid,
                  let prefix = uid.split(separator: ":", maxSplits: 1).first else {
                return false
            }
            return BluetoothBatteryReader.normalizedAddress(String(prefix)) == target
        }
        if addressMatches.count == 1 { return addressMatches[0].id }
        if addressMatches.count > 1 { return nil }

        let wantedName = normalizedName(deviceName)
        guard !wantedName.isEmpty else { return nil }
        let nameMatches = endpoints.filter { normalizedName($0.name) == wantedName }
        return nameMatches.count == 1 ? nameMatches[0].id : nil
    }

    private static func normalizedName(_ name: String?) -> String {
        (name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

protocol HuaweiAudioEndpointProviding: Sendable {
    /// The output endpoint the device is currently playing through, or `nil`
    /// when identity is ambiguous. Called once per panel-visible refresh.
    func endpointID(for device: BluetoothDevice) -> AudioDeviceID?
}

/// Enumerates CoreAudio output devices and resolves the one whose UID carries
/// the device's Bluetooth address.
struct CoreAudioHuaweiAudioEndpointProvider: HuaweiAudioEndpointProviding {
    func endpointID(for device: BluetoothDevice) -> AudioDeviceID? {
        HuaweiAudioEndpointMatcher.endpointID(
            forAddress: device.id,
            deviceName: device.name,
            in: Self.outputEndpoints()
        )
    }

    private static func outputEndpoints() -> [HuaweiAudioEndpoint] {
        deviceIDs()
            .filter(hasOutputStream)
            .map { id in
                HuaweiAudioEndpoint(
                    id: id,
                    uid: stringProperty(for: id, selector: kAudioDevicePropertyDeviceUID),
                    name: stringProperty(for: id, selector: kAudioObjectPropertyName)
                )
            }
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var ids = Array(repeating: AudioDeviceID(kAudioObjectUnknown), count: count)
        var mutableSize = size
        let status = ids.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address, 0, nil, &mutableSize, buffer.baseAddress!
            )
        }
        guard status == noErr else { return [] }
        return ids.filter { $0 != AudioDeviceID(kAudioObjectUnknown) }
    }

    private static func hasOutputStream(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeOutput),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else {
            return false
        }
        return size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private static func stringProperty(
        for deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID, &address, 0, nil, &size, &value
        )
        guard status == noErr, let value else { return nil }
        let string = value.takeRetainedValue() as String
        return string.isEmpty ? nil : string
    }
}
