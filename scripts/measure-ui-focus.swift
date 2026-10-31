import AppKit
import CoreGraphics
import Foundation

// Standalone, read-only diagnostics. Never linked into the app.
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2,
      arguments[0].hasPrefix("com.lingsmbp.StatusTrio.dev."),
      let duration = Double(arguments[1]),
      duration.isFinite, duration > 0, duration <= 120 else {
    FileHandle.standardError.write(Data(
        "Usage: swift scripts/measure-ui-focus.swift <dev-bundle-id> <seconds: 0...120>\n".utf8
    ))
    exit(2)
}

let bundleID = arguments[0]
let interval = 0.025
var started = ProcessInfo.processInfo.systemUptime
var samples = 0
var sampleTransitions = 0
var activationEvents = 0
var previousPID: pid_t?
var maximumSampleGap = 0.0
var lastSample = started

func emit(_ record: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else {
        return
    }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}

func elapsed() -> Double {
    ProcessInfo.processInfo.systemUptime - started
}

emit([
    "type": "start",
    "date": ISO8601DateFormatter().string(from: Date()),
    "bundleID": bundleID,
    "durationSeconds": duration,
    "intervalSeconds": interval,
    "mainDisplayID": CGMainDisplayID(),
    "screens": NSScreen.screens.map { screen -> [String: Any] in
        [
            "displayID": (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber)?.uint32Value ?? 0,
            "frame": NSStringFromRect(screen.frame),
            "visibleFrame": NSStringFromRect(screen.visibleFrame),
            "scale": screen.backingScaleFactor
        ]
    }
])
started = ProcessInfo.processInfo.systemUptime
lastSample = started

let center = NSWorkspace.shared.notificationCenter
let observer = center.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification,
    object: nil,
    queue: .main
) { notification in
    guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
        as? NSRunningApplication else { return }
    activationEvents += 1
    emit([
        "type": "activation",
        "elapsed": elapsed(),
        "pid": app.processIdentifier,
        "bundleID": app.bundleIdentifier ?? ""
    ])
}

while elapsed() < duration {
    let now = ProcessInfo.processInfo.systemUptime
    maximumSampleGap = max(maximumSampleGap, now - lastSample)
    lastSample = now
    let foreground = NSWorkspace.shared.frontmostApplication
    let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    let foregroundPID = foreground?.processIdentifier ?? 0
    if let previousPID, previousPID != foregroundPID {
        sampleTransitions += 1
    }
    previousPID = foregroundPID
    samples += 1
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0)
        as? [[String: Any]] ?? []
    let targetPIDs = Set(target.map(\.processIdentifier))
    emit([
        "type": "sample",
        "elapsed": elapsed(),
        "foregroundPID": foregroundPID,
        "foregroundBundleID": foreground?.bundleIdentifier ?? "",
        "targets": target.map { app -> [String: Any] in
            [
                "pid": app.processIdentifier,
                "active": app.isActive,
                "activationPolicy": app.activationPolicy.rawValue
            ]
        },
        "windows": windows.compactMap { window -> [String: Any]? in
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  targetPIDs.contains(pid) else { return nil }
            return [
                "number": window[kCGWindowNumber as String] ?? 0,
                "layer": window[kCGWindowLayer as String] ?? 0,
                "bounds": window[kCGWindowBounds as String] ?? [:]
            ]
        }
    ])
    RunLoop.current.run(until: Date(timeIntervalSinceNow: interval))
}
center.removeObserver(observer)
emit([
    "type": "summary",
    "elapsed": elapsed(),
    "samples": samples,
    "sampleTransitions": sampleTransitions,
    "activationEvents": activationEvents,
    "maximumSampleGapSeconds": maximumSampleGap
])
