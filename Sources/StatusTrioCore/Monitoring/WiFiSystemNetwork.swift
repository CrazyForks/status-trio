import Foundation

struct WiFiNetworkSetupCommand: Equatable, Sendable {
    let arguments: [String]

    static func listPreferredNetworks(interface: String) -> Self {
        Self(arguments: ["-listpreferredwirelessnetworks", interface])
    }

    static func associate(interface: String, ssid: String) -> Self {
        Self(arguments: ["-setairportnetwork", interface, ssid])
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

protocol WiFiSystemNetworkConfiguring: Sendable {
    func preferredNetworkSSIDs(interface: String) -> Set<String>
    func associate(interface: String, ssid: String) -> Bool
}

/// Runs `networksetup` from the CoreWLAN worker's serial queue. Omitting the
/// password lets macOS reuse the credential stored in the system preferred
/// network profile instead of presenting Status Trio's password sheet.
final class NetworksetupWiFiSystemNetwork: WiFiSystemNetworkConfiguring, @unchecked Sendable {
    private static let executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")

    func preferredNetworkSSIDs(interface: String) -> Set<String> {
        let result = run(
            WiFiNetworkSetupCommand.listPreferredNetworks(interface: interface),
            capturesOutput: true
        )
        guard result.succeeded else { return [] }
        return WiFiPreferredNetworkOutputParser.parse(result.output)
    }

    func associate(interface: String, ssid: String) -> Bool {
        run(
            WiFiNetworkSetupCommand.associate(interface: interface, ssid: ssid),
            capturesOutput: false
        ).succeeded
    }

    private func run(
        _ command: WiFiNetworkSetupCommand,
        capturesOutput: Bool
    ) -> (succeeded: Bool, output: String) {
        let process = Process()
        process.executableURL = Self.executableURL
        process.arguments = command.arguments
        process.standardError = FileHandle.nullDevice

        let outputPipe: Pipe?
        if capturesOutput {
            let pipe = Pipe()
            process.standardOutput = pipe
            outputPipe = pipe
        } else {
            process.standardOutput = FileHandle.nullDevice
            outputPipe = nil
        }

        do {
            try process.run()
        } catch {
            return (false, "")
        }

        let outputData = outputPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return (false, "") }
        return (true, String(data: outputData, encoding: .utf8) ?? "")
    }
}
