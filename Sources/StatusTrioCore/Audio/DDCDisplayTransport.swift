import DDCPrivateAPI
import Foundation
import IOKit
import os

private let ddcTargetLogger = Logger(
    subsystem: "com.lingsmbp.StatusTrio",
    category: "DDCTarget"
)

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

    /// Maps `IONameMatched` ("dispext0,t603x") to the branch token shared with
    /// the owning DCP branch ("dispext0"). Returns nil for anything that is not
    /// a numbered `dispextN` branch, which keeps matching strict.
    static func branchToken(fromIONameMatched name: String?) -> String? {
        guard let name else { return nil }
        let token = name.split(separator: ",", maxSplits: 1).first.map(String.init) ?? name
        return isExternalBranchToken(token) ? token : nil
    }

    static func isExternalBranchToken(_ token: String) -> Bool {
        let prefix = "dispext"
        guard token.hasPrefix(prefix) else { return false }
        let suffix = token.dropFirst(prefix.count)
        return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
    }

    /// Extracts the branch token an external DCP AV service proxy belongs to.
    ///
    /// Real Apple Silicon firmware registers the proxy's ancestor as
    /// `dispextN:dcpav-service-epic:U` under the matching `dcpextN` branch, so
    /// the token comes from the registry name itself rather than from
    /// enumeration order.
    static func branchToken(fromServiceAncestorNames names: [String]) -> String? {
        for name in names {
            guard let separator = name.firstIndex(of: ":") else { continue }
            let token = String(name[name.startIndex..<separator])
            let role = String(name[name.index(after: separator)...])
            guard isExternalBranchToken(token), role.hasPrefix("dcpav-service-epic") else { continue }
            return token
        }
        return nil
    }

    func resolve(uid: String) -> DDCDisplayTarget? {
        #if arch(arm64)
        guard !uid.isEmpty else {
            logUnavailable(.missingAudioUID, framebuffers: 0, services: 0)
            return nil
        }
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else {
            logUnavailable(.transportUnavailable, framebuffers: 0, services: 0)
            return nil
        }
        defer { IOObjectRelease(root) }

        var iterator: io_iterator_t = IO_OBJECT_NULL
        guard IORegistryEntryCreateIterator(root, "IOService", IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            logUnavailable(.transportUnavailable, framebuffers: 0, services: 0)
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var framebuffers: [DDCFramebufferSnapshot] = []
        var services: [(entryID: UInt64, snapshot: DDCServiceSnapshot, entry: io_service_t)] = []
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
                ), let branchToken = Self.branchToken(fromIONameMatched: ioNameMatched),
                   let entryID = Self.registryEntryID(entry) {
                    framebuffers.append(DDCFramebufferSnapshot(
                        entryID: entryID,
                        branchName: branchToken,
                        edidUUID: Self.stringProperty("EDID UUID", entry: entry, recursive: true)
                    ))
                }
                IOObjectRelease(entry)
            case "DCPAVServiceProxy" where Self.stringProperty("Location", entry: entry) == "External":
                if let entryID = Self.registryEntryID(entry) {
                    services.append((
                        entryID: entryID,
                        snapshot: DDCServiceSnapshot(
                            entryID: entryID,
                            branchName: Self.branchToken(fromServiceAncestorNames: Self.ancestorNames(of: entry)),
                            location: "External"
                        ),
                        entry: entry
                    ))
                } else {
                    IOObjectRelease(entry)
                }
            default:
                IOObjectRelease(entry)
            }
        }
        defer { services.forEach { _ = IOObjectRelease($0.entry) } }

        let resolution = DDCTargetResolver.resolve(
            outputUID: uid,
            framebuffers: framebuffers,
            services: services.map(\.snapshot)
        )
        let selected = DDCTargetResolver.openResolvedTarget(
            resolution,
            services: services.map { (entryID: $0.entryID, handle: $0.entry) }
        ) { entry in
            IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue()
        }
        guard let selected else {
            logFailure(resolution, framebuffers: framebuffers.count, services: services.count)
            return nil
        }
        let target = selected.opened
        if let branchName = services.first(where: { $0.entryID == selected.serviceEntryID })?.snapshot.branchName {
            ddcTargetLogger.debug(
                "DDC target resolved: branch=\(branchName, privacy: .public), framebuffers=\(framebuffers.count, privacy: .public), services=\(services.count, privacy: .public)"
            )
        } else {
            ddcTargetLogger.debug(
                "DDC target resolved via legacy single-display path: framebuffers=\(framebuffers.count, privacy: .public), services=\(services.count, privacy: .public)"
            )
        }
        return DDCDisplayTarget(uid: uid, service: target)
        #else
        logUnavailable(.unsupportedArchitecture, framebuffers: 0, services: 0)
        return nil
        #endif
    }

    func read(_ target: DDCDisplayTarget) -> DDCVolumeReply? {
        #if arch(arm64)
        guard let service = target.service else { return nil }
        let request: [UInt8] = [Self.volumeVCP]
        var sawValidTransportReply = false
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
            if readResult == kIOReturnSuccess { sawValidTransportReply = true }
            if readResult == kIOReturnSuccess, let decoded = DDCVolumeReply.decode(reply) {
                return decoded
            }
        }
        ddcTargetLogger.debug(
            "DDC read failed: \(sawValidTransportReply ? DDCResolutionFailure.unsupportedVolumeVCP.diagnosticName : DDCResolutionFailure.readFailed.diagnosticName, privacy: .public)"
        )
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
    private static func registryEntryID(_ entry: io_registry_entry_t) -> UInt64? {
        var identifier: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(entry, &identifier) == KERN_SUCCESS, identifier != 0 else { return nil }
        return identifier
    }

    /// Ancestor entry names on the IOService plane, nearest first.
    private static func ancestorNames(of entry: io_registry_entry_t, limit: Int = 8) -> [String] {
        var names: [String] = []
        var current = entry
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }
        for _ in 0..<limit {
            var parent: io_registry_entry_t = IO_OBJECT_NULL
            guard IORegistryEntryGetParentEntry(current, "IOService", &parent) == KERN_SUCCESS,
                  parent != IO_OBJECT_NULL else { break }
            if let name = registryName(parent) { names.append(name) }
            IOObjectRelease(current)
            current = parent
        }
        return names
    }

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

    private func logFailure(_ resolution: DDCResolution, framebuffers: Int, services: Int) {
        let reason: DDCResolutionFailure = switch resolution {
        case .unavailable(let failure): failure
        case .matched: .transportUnavailable
        }
        logUnavailable(reason, framebuffers: framebuffers, services: services)
    }

    private func logUnavailable(_ failure: DDCResolutionFailure, framebuffers: Int, services: Int) {
        ddcTargetLogger.debug(
            "DDC target unavailable: \(failure.diagnosticName, privacy: .public), framebuffers=\(framebuffers, privacy: .public), services=\(services, privacy: .public)"
        )
    }
}
