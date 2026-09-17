import Foundation

struct WiFiNetworkSetupCommand: Equatable, Sendable {
    let arguments: [String]

    static func listPreferredNetworks(interface: String) -> Self {
        Self(arguments: ["-listpreferredwirelessnetworks", interface])
    }
}

enum WiFiPreferredNetworkOutputParser {
    static func parse(_ output: String) -> Set<String> {
        var lines = output.split(
            omittingEmptySubsequences: false,
            whereSeparator: \.isNewline
        )
        guard !lines.isEmpty else { return [] }
        lines.removeFirst()

        return Set(lines.compactMap { rawLine in
            var line = String(rawLine)
            if line.hasSuffix("\r") {
                line.removeLast()
            }
            while line.first == "\t" {
                line.removeFirst()
            }
            return line.isEmpty ? nil : line
        })
    }
}

protocol WiFiKnownNetworkProviding: Sendable {
    func preferredNetworkSSIDs(interface: String) -> Set<String>
}

/// Reads the system's preferred-network names without accessing their stored
/// passwords. The process runs on the CoreWLAN worker's serial queue.
final class NetworksetupWiFiKnownNetworkProvider: WiFiKnownNetworkProviding, @unchecked Sendable {
    private static let executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")

    func preferredNetworkSSIDs(interface: String) -> Set<String> {
        let process = Process()
        process.executableURL = Self.executableURL
        process.arguments = WiFiNetworkSetupCommand
            .listPreferredNetworks(interface: interface)
            .arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        return WiFiPreferredNetworkOutputParser.parse(
            String(data: outputData, encoding: .utf8) ?? ""
        )
    }
}
