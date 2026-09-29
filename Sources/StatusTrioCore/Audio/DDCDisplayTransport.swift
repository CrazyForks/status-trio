import DDCPrivateAPI
import Foundation
import IOKit

// IORegistry and I2C details adapted from AppleSiliconDDC revision
// 67ff964ab8123d9d35fadf7d8e1a7c677d31da14, Copyright © 2021 Istvan T. (MIT).

/// An IOKit service retained for use and release on the serial DDC worker only.
/// This type intentionally does not conform to Sendable.
final class DDCDisplayTarget {
    let uid: String
    let service: IOAVService?

    init(uid: String, service: IOAVService?) {
        self.uid = uid
        self.service = service
    }
}

protocol DDCVolumeTransport: AnyObject {
    func resolve(uid: String) -> DDCDisplayTarget?
    func read(_ target: DDCDisplayTarget) -> DDCVolumeReply?
    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool
}

/// Direct DDC access for external Apple Silicon displays.
/// Construct and call this transport on its owning serial worker queue.
final class DDCDisplayTransport: DDCVolumeTransport {
    private static let chipAddress: UInt32 = 0x37
    private static let dataAddress: UInt32 = 0x51
    private static let volumeVCP: UInt8 = 0x62

    static func uniqueMatch<Handle>(
        uid: String,
        services: [(edidUUID: String, handle: Handle)]
    ) -> (edidUUID: String, handle: Handle)? {
        guard !uid.isEmpty else { return nil }
        let matches = services.filter { $0.edidUUID == uid }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Selects identity before calling the opener, so a failed open cannot hide
    /// a second registry entry with the same UID.
    static func uniqueOpenedMatch<Identity, Handle>(
        uid: String,
        services: [(edidUUID: String, handle: Identity)],
        open: (Identity) -> Handle?
    ) -> (edidUUID: String, handle: Handle)? {
        guard let candidate = uniqueMatch(uid: uid, services: services),
              let opened = open(candidate.handle) else { return nil }
        return (edidUUID: candidate.edidUUID, handle: opened)
    }

    /// The current Apple Silicon registry exposes the display EDID UUID on a
    /// framebuffer branch separate from its DDC proxy. Until a stable direct
    /// relation is available, accept only the unambiguous one-framebuffer,
    /// one-external-service topology.
    static func uniqueFramebufferServiceMatch<Identity, Handle>(
        uid: String,
        externalFramebufferUUIDs: [String?],
        externalServices: [Identity],
        open: (Identity) -> Handle?
    ) -> (edidUUID: String, handle: Handle)? {
        guard !uid.isEmpty,
              externalFramebufferUUIDs.count == 1,
              let framebufferUUID = externalFramebufferUUIDs[0],
              framebufferUUID == uid,
              externalServices.count == 1,
              let opened = open(externalServices[0]) else { return nil }
        return (edidUUID: framebufferUUID, handle: opened)
    }

    static func isConnectedExternalFramebuffer(
        ioNameMatched: String?,
        displayWidth: Int?,
        displayHeight: Int?
    ) -> Bool {
        guard let ioNameMatched,
              ioNameMatched.hasPrefix("dispext"),
              let displayWidth,
              let displayHeight else { return false }
        return displayWidth > 0 && displayHeight > 0
    }

    func resolve(uid: String) -> DDCDisplayTarget? {
        #if arch(arm64)
        guard !uid.isEmpty else { return nil }
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(root) }

        var iterator: io_iterator_t = IO_OBJECT_NULL
        guard IORegistryEntryCreateIterator(root, "IOService", IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var framebufferUUIDs: [String?] = []
        var externalServices: [io_service_t] = []
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL else { break }
            switch Self.registryName(entry) {
            case "IOMobileFramebufferShim":
                let ioNameMatched = Self.stringProperty("IONameMatched", entry: entry)
                let displayWidth = Self.integerProperty("DisplayWidth", entry: entry)
                let displayHeight = Self.integerProperty("DisplayHeight", entry: entry)
                if Self.isConnectedExternalFramebuffer(
                    ioNameMatched: ioNameMatched,
                    displayWidth: displayWidth,
                    displayHeight: displayHeight
                ) {
                    framebufferUUIDs.append(Self.stringProperty("EDID UUID", entry: entry, recursive: true))
                }
                IOObjectRelease(entry)
            case "DCPAVServiceProxy" where Self.stringProperty("Location", entry: entry) == "External":
                externalServices.append(entry)
            default:
                IOObjectRelease(entry)
            }
        }
        defer { externalServices.forEach { _ = IOObjectRelease($0) } }

        guard let candidate = Self.uniqueFramebufferServiceMatch(
            uid: uid,
            externalFramebufferUUIDs: framebufferUUIDs,
            externalServices: externalServices,
            open: { entry in
                IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue()
            }
        ) else { return nil }
        return DDCDisplayTarget(uid: uid, service: candidate.handle)
        #else
        return nil
        #endif
    }

    func read(_ target: DDCDisplayTarget) -> DDCVolumeReply? {
        #if arch(arm64)
        guard let service = target.service else { return nil }
        let request: [UInt8] = [Self.volumeVCP]
        for attempt in 0..<5 {
            usleep(attempt == 0 ? 10_000 : 20_000)
            var packet = Self.packet(for: request, includeDataAddressInChecksum: false)
            let writeResult = packet.withUnsafeMutableBytes {
                IOAVServiceWriteI2C(service, Self.chipAddress, Self.dataAddress, $0.baseAddress, UInt32($0.count))
            }
            guard writeResult == kIOReturnSuccess else { continue }
            usleep(50_000)
            var reply = [UInt8](repeating: 0, count: 11)
            let readResult = reply.withUnsafeMutableBytes {
                IOAVServiceReadI2C(service, Self.chipAddress, Self.dataAddress, $0.baseAddress, UInt32($0.count))
            }
            if readResult == kIOReturnSuccess, let decoded = DDCVolumeReply.decode(reply) {
                return decoded
            }
        }
        return nil
        #else
        return nil
        #endif
    }

    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool {
        #if arch(arm64)
        guard let service = target.service else { return false }
        let command: [UInt8] = [Self.volumeVCP, UInt8(value >> 8), UInt8(value & 0xff)]
        var succeeded = false
        for attempt in 0..<5 {
            for _ in 0..<2 {
                usleep(attempt == 0 ? 10_000 : 20_000)
                var packet = Self.packet(for: command, includeDataAddressInChecksum: true)
                succeeded = packet.withUnsafeMutableBytes {
                    IOAVServiceWriteI2C(service, Self.chipAddress, Self.dataAddress, $0.baseAddress, UInt32($0.count)) == kIOReturnSuccess
                }
            }
            if succeeded { return true }
        }
        return false
        #else
        return false
        #endif
    }

    private static func packet(for bytes: [UInt8], includeDataAddressInChecksum: Bool) -> [UInt8] {
        var packet = [UInt8(0x80 | (bytes.count + 1)), UInt8(bytes.count)] + bytes + [0]
        let seed = UInt8(0x37 << 1) ^ (includeDataAddressInChecksum ? UInt8(dataAddress) : 0)
        packet[packet.count - 1] = packet.dropLast().reduce(seed, ^)
        return packet
    }

    #if arch(arm64)
    private static func registryName(_ entry: io_registry_entry_t) -> String? {
        var name = [CChar](repeating: 0, count: MemoryLayout<io_name_t>.size)
        guard IORegistryEntryGetName(entry, &name) == KERN_SUCCESS else { return nil }
        let bytes = name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func stringProperty(_ key: String, entry: io_registry_entry_t, recursive: Bool = false) -> String? {
        let options = recursive ? IOOptionBits(kIORegistryIterateRecursively) : 0
        guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, options)?.takeRetainedValue() else { return nil }
        return value as? String
    }

    private static func integerProperty(_ key: String, entry: io_registry_entry_t) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { return nil }
        return value as? Int
    }
    #endif
}
