import AppKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    exit(1)
}

func command(_ executable: String, _ arguments: [String]) -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: executable)
    task.arguments = arguments
    let output = Pipe()
    task.standardOutput = output
    do { try task.run() } catch { fail("\(executable): \(error)") }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else { fail("\(executable) exited \(task.terminationStatus)") }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard (arguments.count == 3 && arguments[0] == "prepare")
        || (arguments.count == 4 && arguments[0] == "launch"
            && ["automatic", "secondary"].contains(arguments[3])),
      arguments[1].hasPrefix("com.lingsmbp.StatusTrio.dev.") else {
    fail("Usage: computer-use-instance.swift <prepare|launch> <dev-bundle-id> <app-path> [automatic|secondary]")
}
let mode = arguments[0]
let bundleID = arguments[1]
let appURL = URL(fileURLWithPath: arguments[2]).resolvingSymlinksInPath()
let executableURL = appURL.appendingPathComponent("Contents/MacOS/StatusTrio").resolvingSymlinksInPath()

func instances() -> [NSRunningApplication] {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { !$0.isTerminated }
}

func validatePath(_ app: NSRunningApplication) {
    guard app.bundleURL?.resolvingSymlinksInPath() == appURL,
          app.executableURL?.resolvingSymlinksInPath() == executableURL else {
        fail("Bundle ID collision at PID \(app.processIdentifier); another checkout will not be touched.")
    }
}

func launchArguments(_ app: NSRunningApplication) -> [Substring] {
    command("/bin/ps", ["-ww", "-p", String(app.processIdentifier), "-o", "args="])
        .split(whereSeparator: \.isWhitespace)
}

if mode == "prepare" {
    let running = instances()
    guard running.count <= 1 else { fail("Multiple instances share \(bundleID); stop and inspect them.") }
    if let app = running.first {
        validatePath(app)
        guard launchArguments(app).contains("--background-ui-testing") else {
            fail("PID \(app.processIdentifier) is a non-test dev instance. Quit it explicitly before testing.")
        }
        guard app.terminate() else { fail("Test PID \(app.processIdentifier) refused graceful termination.") }
        let deadline = Date(timeIntervalSinceNow: 8)
        while !app.isTerminated, Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        guard app.isTerminated else { fail("Test PID \(app.processIdentifier) did not exit; no force kill.") }
        print("Stopped this worktree's test PID \(app.processIdentifier).")
    }
} else {
    // Recheck after the build: another launch may have occurred in the meantime.
    guard instances().isEmpty else { fail("An instance appeared during build; no reopen or duplicate launch sent.") }
    var flags = ["--background-ui-testing"]
    if arguments[3] == "secondary" { flags.append("--test-display=secondary") }
    // A process racing a manual launch must not be reported as this launch.
    let launchToken = "--status-trio-ui-test-launch=\(UUID().uuidString)"
    flags.append(launchToken)
    _ = command("/usr/bin/open", ["-g", "-a", appURL.path, "--args"] + flags)
    let deadline = Date(timeIntervalSinceNow: 8)
    var launched: NSRunningApplication?
    while Date() < deadline {
        let running = instances()
        guard running.count <= 1 else { fail("Unexpected duplicate launch; inspect \(bundleID).") }
        if let app = running.first, app.isFinishedLaunching {
            launched = app
            break
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }
    guard let app = launched else { fail("No running test instance after launch; inspect SingleInstance logs.") }
    validatePath(app)
    let actualArguments = launchArguments(app)
    guard flags.allSatisfy({ actualArguments.contains(Substring($0)) }) else {
        fail("Running PID \(app.processIdentifier) does not have the requested test arguments.")
    }
    let plist = NSDictionary(contentsOf: appURL.appendingPathComponent("Contents/Info.plist")) ?? [:]
    let report: [String: Any] = [
        "bundleID": bundleID, "path": appURL.path, "pid": app.processIdentifier,
        "sha": plist["STBuildCommit"] ?? "", "sourceDirty": plist["STBuildSourceDirty"] ?? false,
        "backgroundUITesting": true, "requestedDisplay": arguments[3],
        "launchToken": launchToken,
        "mainDisplayID": CGMainDisplayID(),
        "connectedDisplayIDs": NSScreen.screens.map {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        }
    ]
    let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}
