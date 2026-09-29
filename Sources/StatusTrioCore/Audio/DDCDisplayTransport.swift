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

        var candidates: [(edidUUID: String, handle: IOAVService)] = []
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL else { break }
            defer { IOObjectRelease(entry) }
            guard Self.registryName(entry) == "DCPAVServiceProxy",
                  Self.stringProperty("Location", entry: entry) == "External",
                  let edidUUID = Self.parentEDIDUUID(entry),
                  let unmanagedService = IOAVServiceCreateWithService(kCFAllocatorDefault, entry) else { continue }
            let service = unmanagedService.takeRetainedValue()
            candidates.append((edidUUID: edidUUID, handle: service))
        }

        guard let candidate = Self.uniqueMatch(uid: uid, services: candidates) else {
            // Release all retained service references on this worker.
            candidates.removeAll()
            return nil
        }
        // Drop all non-selected handles here, still on the worker.
        let target = DDCDisplayTarget(uid: uid, service: candidate.handle)
        candidates.removeAll()
        return target
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

    private static func stringProperty(_ key: String, entry: io_registry_entry_t) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { return nil }
        return value as? String
    }

    private static func parentEDIDUUID(_ entry: io_registry_entry_t) -> String? {
        var current = entry
        var ownsCurrent = false
        defer { if ownsCurrent { IOObjectRelease(current) } }
        for _ in 0..<12 {
            if let uuid = stringProperty("EDID UUID", entry: current) { return uuid }
            var parent: io_registry_entry_t = IO_OBJECT_NULL
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS,
                  parent != IO_OBJECT_NULL else { return nil }
            if ownsCurrent { IOObjectRelease(current) }
            current = parent
            ownsCurrent = true
        }
        return nil
    }
    #endif
}
