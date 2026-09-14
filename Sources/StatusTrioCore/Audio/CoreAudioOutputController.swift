import AudioToolbox
import CoreAudio
import Darwin
import Foundation

@MainActor
final class CoreAudioOutputController: AudioOutputControlling {
    private let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

    func outputDevices() -> [AudioOutputDevice] {
        guard let deviceIDs = audioObjectIDs(
            objectID: systemObjectID,
            selector: kAudioHardwarePropertyDevices
        ) else {
            return []
        }

        let currentDeviceID = defaultOutputDeviceID()
        return deviceIDs
            .filter(isOutputDevice)
            .compactMap { deviceID -> AudioOutputDevice? in
                guard !isHidden(deviceID) else { return nil }

                return AudioOutputDevice(
                    id: deviceID,
                    name: deviceName(for: deviceID),
                    uid: deviceUID(for: deviceID),
                    isCurrent: deviceID == currentDeviceID,
                    volume: volume(for: deviceID)
                )
            }
            .sorted { lhs, rhs in
                if lhs.isCurrent != rhs.isCurrent {
                    return lhs.isCurrent
                }
                return (lhs.name ?? "").localizedStandardCompare(rhs.name ?? "") == .orderedAscending
            }
    }

    @discardableResult
    func setVolume(_ scalar: Double) -> Bool {
        guard let deviceID = defaultOutputDeviceID() else { return false }

        let volume = Float32(min(1, max(0, scalar)))
        var didSetVolume = setScalarProperty(
            volume,
            objectID: deviceID,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        )

        if !didSetVolume {
            for element in audioVolumeChannelElements(deviceID: deviceID) {
                if setScalarProperty(
                    volume,
                    objectID: deviceID,
                    selector: kAudioDevicePropertyVolumeScalar,
                    scope: kAudioObjectPropertyScopeOutput,
                    element: element
                ) {
                    didSetVolume = true
                }
            }
        }

        guard didSetVolume else { return false }

        if isMuted(for: deviceID) {
            _ = setMuted(false, for: deviceID)
        }
        return true
    }

    @discardableResult
    func toggleMute() -> Bool {
        guard let deviceID = defaultOutputDeviceID() else { return false }
        return setMuted(!isMuted(for: deviceID), for: deviceID)
    }

    @discardableResult
    func selectOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        guard deviceID != kAudioObjectUnknown,
              canBeDefaultOutputDevice(deviceID) else {
            return false
        }

        if #available(macOS 15.0, *) {
            let device = AudioHardwareDevice(id: deviceID)
            do {
                try AudioHardwareSystem.shared.setDefaultOutputDevice(device)
                try AudioHardwareSystem.shared.setDefaultSoundEffectsDevice(device)
                return true
            } catch {
                return setLegacyDefaultOutputDevice(deviceID)
            }
        }

        return setLegacyDefaultOutputDevice(deviceID)
    }

    private func setMuted(_ isMuted: Bool, for deviceID: AudioDeviceID) -> Bool {
        let value: UInt32 = isMuted ? 1 : 0
        var didSetMute = setUInt32Property(
            value,
            objectID: deviceID,
            selector: kAudioDevicePropertyMute,
            scope: kAudioObjectPropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        )

        if !didSetMute {
            for element in audioVolumeChannelElements(deviceID: deviceID) {
                if setUInt32Property(
                    value,
                    objectID: deviceID,
                    selector: kAudioDevicePropertyMute,
                    scope: kAudioObjectPropertyScopeOutput,
                    element: element
                ) {
                    didSetMute = true
                }
            }
        }

        return didSetMute
    }

    private func isMuted(for deviceID: AudioDeviceID) -> Bool {
        for element in [kAudioObjectPropertyElementMain] + audioVolumeChannelElements(deviceID: deviceID) {
            guard let value = readUInt32Property(
                objectID: deviceID,
                selector: kAudioDevicePropertyMute,
                scope: kAudioObjectPropertyScopeOutput,
                element: element
            ) else {
                continue
            }
            return value != 0
        }
        return false
    }

    private func isOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        hasOutputStreams(deviceID: deviceID) && canBeDefaultOutputDevice(deviceID)
    }

    private func hasOutputStreams(deviceID: AudioDeviceID) -> Bool {
        var address = propertyAddress(
            selector: kAudioDevicePropertyStreams,
            scope: kAudioObjectPropertyScopeOutput
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        return status == noErr && dataSize >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private func canBeDefaultOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        if #available(macOS 15.0, *) {
            let device = AudioHardwareDevice(id: deviceID)
            return (try? device.canBeDefaultOutputDevice) == true
        }

        return audioDeviceCanBeDefault(deviceID)
    }

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = propertyAddress(selector: kAudioHardwarePropertyDefaultOutputDevice)
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            systemObjectID,
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private func isHidden(_ deviceID: AudioDeviceID) -> Bool {
        var address = propertyAddress(selector: kAudioDevicePropertyIsHidden)
        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var value = UInt32(0)
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &value)
        return status == noErr && value != 0
    }

    private func deviceName(for deviceID: AudioDeviceID) -> String? {
        stringProperty(
            for: deviceID,
            selector: kAudioObjectPropertyName
        )
    }

    private func deviceUID(for deviceID: AudioDeviceID) -> String? {
        stringProperty(
            for: deviceID,
            selector: kAudioDevicePropertyDeviceUID
        )
    }

    private func stringProperty(
        for deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = propertyAddress(selector: selector)
        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &name
        )

        guard status == noErr, let name else { return nil }
        let value = name.takeRetainedValue() as String
        return value.isEmpty ? nil : value
    }

    private func audioObjectIDs(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> [AudioObjectID]? {
        var address = propertyAddress(selector: selector)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize) == noErr else {
            return nil
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var deviceIDs = Array(repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        var mutableDataSize = dataSize
        let status = deviceIDs.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &mutableDataSize,
                buffer.baseAddress!
            )
        }

        guard status == noErr else { return nil }
        return deviceIDs.filter { $0 != kAudioObjectUnknown }
    }

    private func volume(for deviceID: AudioDeviceID) -> Double? {
        if let masterVolume = readFloat32Property(
            objectID: deviceID,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ) {
            return Double(masterVolume)
        }

        let channelVolumes = audioVolumeChannelElements(deviceID: deviceID).compactMap { element in
            readFloat32Property(
                objectID: deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeOutput,
                element: element
            )
        }

        guard !channelVolumes.isEmpty else { return nil }
        let total = channelVolumes.reduce(Float32(0), +)
        return Double(total / Float32(channelVolumes.count))
    }

    private func readFloat32Property(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Float32? {
        var address = propertyAddress(selector: selector, scope: scope, element: element)
        guard AudioObjectHasProperty(objectID, &address) else { return nil }

        var value = Float32(0)
        var dataSize = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value)
        return status == noErr ? value : nil
    }

    private func readUInt32Property(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> UInt32? {
        var address = propertyAddress(selector: selector, scope: scope, element: element)
        guard AudioObjectHasProperty(objectID, &address) else { return nil }

        var value = UInt32(0)
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value)
        return status == noErr ? value : nil
    }

    private func setScalarProperty(
        _ value: Float32,
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Bool {
        var address = propertyAddress(selector: selector, scope: scope, element: element)
        guard isSettable(objectID: objectID, address: &address) else { return false }

        var mutableValue = value
        return AudioObjectSetPropertyData(
            objectID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &mutableValue
        ) == noErr
    }

    private func setUInt32Property(
        _ value: UInt32,
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Bool {
        var address = propertyAddress(selector: selector, scope: scope, element: element)
        guard isSettable(objectID: objectID, address: &address) else { return false }

        var mutableValue = value
        return AudioObjectSetPropertyData(
            objectID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &mutableValue
        ) == noErr
    }

    private func isSettable(
        objectID: AudioObjectID,
        address: inout AudioObjectPropertyAddress
    ) -> Bool {
        guard AudioObjectHasProperty(objectID, &address) else { return false }

        var isSettable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(objectID, &address, &isSettable) == noErr
            && isSettable.boolValue
    }

    private func audioVolumeChannelElements(deviceID: AudioDeviceID) -> [AudioObjectPropertyElement] {
        for _ in 0..<3 {
            var address = propertyAddress(
                selector: kAudioDevicePropertyStreamConfiguration,
                scope: kAudioObjectPropertyScopeOutput
            )
            var requestedSize: UInt32 = 0

            guard AudioObjectGetPropertyDataSize(
                deviceID,
                &address,
                0,
                nil,
                &requestedSize
            ) == noErr,
                  requestedSize >= UInt32(MemoryLayout<AudioBufferList>.size) else {
                continue
            }

            let storage = UnsafeMutableRawPointer.allocate(
                byteCount: Int(requestedSize),
                alignment: MemoryLayout<AudioBufferList>.alignment
            )
            defer { storage.deallocate() }

            let bufferList = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
            var returnedSize = requestedSize
            guard AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &returnedSize,
                bufferList
            ) == noErr,
                  returnedSize <= requestedSize else {
                continue
            }

            let channelCount = UnsafeMutableAudioBufferListPointer(bufferList).reduce(0) { count, buffer in
                count + Int(buffer.mNumberChannels)
            }
            guard channelCount > 0 else { return [1, 2] }

            return (1...channelCount).map(AudioObjectPropertyElement.init)
        }

        return [1, 2]
    }

    private func audioDeviceCanBeDefault(_ deviceID: AudioDeviceID) -> Bool {
        var address = propertyAddress(
            selector: kAudioDevicePropertyDeviceCanBeDefaultDevice,
            scope: kAudioObjectPropertyScopeOutput
        )
        var canBeDefault = UInt32(0)
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &canBeDefault
        )
        return status == noErr && canBeDefault != 0
    }

    private func setLegacyDefaultOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        setDefaultAudioDevice(deviceID, selector: kAudioHardwarePropertyDefaultOutputDevice)
            && setDefaultAudioDevice(deviceID, selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
    }

    private func setDefaultAudioDevice(
        _ deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> Bool {
        var address = propertyAddress(selector: selector)
        var mutableDeviceID = deviceID
        return AudioObjectSetPropertyData(
            systemObjectID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &mutableDeviceID
        ) == noErr
    }

    private func propertyAddress(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
    }
}
