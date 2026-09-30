// Status Trio — AirPods Listening Mode hardware spike (Issue #79, Phase 0)
//
// A diagnostic, not a test and not the shipping architecture. It drives the
// undocumented CoreAudio HAL `lstm` / `lsms` properties against the live system,
// outside the app, to answer one question before any UI is written: on this macOS
// and on the AirPods actually connected here, can the listening mode be probed,
// read, and *written* — with the write confirmed by a bounded read-back — without
// changing the default output, spoofing an entitlement, or touching a private
// AVFoundation setter?
//
// Usage:
//   swift scripts/probe-airpods-listening-mode.swift
//   swift scripts/probe-airpods-listening-mode.swift --write      # also try a write/read-back + restore
//
// Without `--write` it only reads and reports (safe, changes nothing). Pass
// `--write` to run the spike's write test; it switches to another supported mode,
// polls `lstm` until it settles, and restores the original mode afterwards.
//
// The selectors and the read/write path mirror Sources/StatusTrioCore/Audio/* so
// this script stays independent of the package build. The logic it exercises in
// the app is pinned by BluetoothListeningModeHALTests; this file is the on-device
// gate the plan calls Step 1.

import CoreAudio
import Foundation

// MARK: - HAL selectors (Apple-private; four-char codes, not a public contract)

let iaap: AudioObjectPropertySelector = 0x6961_6170 // "iaap" — Apple audio device marker
let lstm: AudioObjectPropertySelector = 0x6C73_746D // "lstm" — current mode + write target
let lsms: AudioObjectPropertySelector = 0x6C73_6D73 // "lsms" — support bitmask

func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
        mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
    )
}

// MARK: - Mode naming

func modeName(_ raw: UInt32) -> String {
    switch raw {
    case 0: return "unresolved/unknown"
    case 1: return "Off"
    case 2: return "Noise Cancellation"
    case 3: return "Transparency"
    case 4: return "Adaptive"
    default: return "unknown(\(raw))"
    }
}

// bit0 = NC, bit1 = Transparency, bit2 = Adaptive
func supportSummary(_ mask: UInt32) -> String {
    var parts: [String] = []
    if mask & 0x1 != 0 { parts.append("NC") }
    if mask & 0x2 != 0 { parts.append("Transparency") }
    if mask & 0x4 != 0 { parts.append("Adaptive") }
    let known = mask & 0b111
    if mask & ~known != 0 { parts.append("UNKNOWN bits 0b\(String(mask & ~known, radix: 2))") }
    return parts.isEmpty ? "none" : parts.joined(separator: ", ")
}

// MARK: - Property helpers

func hasProperty(_ deviceID: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> Bool {
    var addr = address(selector)
    return AudioObjectHasProperty(deviceID, &addr)
}

func dataSize(_ deviceID: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> UInt32? {
    var addr = address(selector)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &size) == noErr else { return nil }
    return size
}

func readUInt32(_ deviceID: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> UInt32? {
    var addr = address(selector)
    guard AudioObjectHasProperty(deviceID, &addr) else { return nil }
    var value = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &value) == noErr ? value : nil
}

func isSettable(_ deviceID: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> Bool {
    var addr = address(selector)
    guard AudioObjectHasProperty(deviceID, &addr) else { return false }
    var settable = DarwinBoolean(false)
    return AudioObjectIsPropertySettable(deviceID, &addr, &settable) == noErr && settable.boolValue
}

func writeUInt32(_ deviceID: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ value: UInt32) -> OSStatus {
    var addr = address(selector)
    var mutable = value
    return AudioObjectSetPropertyData(deviceID, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &mutable)
}

func deviceName(_ deviceID: AudioDeviceID) -> String {
    var addr = address(kAudioObjectPropertyName)
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    if AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &name) == noErr, let name {
        return name.takeRetainedValue() as String
    }
    return "(unnamed)"
}

func isOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
    var addr = address(kAudioDevicePropertyStreams)
    addr.mScope = AudioObjectPropertyScope(kAudioObjectPropertyScopeOutput)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &size) == noErr else { return false }
    return size >= UInt32(MemoryLayout<AudioStreamID>.size)
}

func allDeviceIDs() -> [AudioDeviceID] {
    var addr = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr
    else { return [] }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var ids = Array(repeating: AudioDeviceID(0), count: count)
    var mutable = size
    let status = ids.withUnsafeMutableBytes { buffer in
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &mutable, buffer.baseAddress!)
    }
    guard status == noErr else { return [] }
    return ids.filter { $0 != 0 }
}

func defaultOutputDeviceID() -> AudioDeviceID? {
    var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
    var id = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
          id != kAudioObjectUnknown else { return nil }
    return id
}

// MARK: - Bounded read-back (mirrors BluetoothListeningModeHAL.confirmWrite)

func boundedReadback(_ deviceID: AudioDeviceID, target: UInt32, attempts: Int = 16, delayMs: Int = 50) -> (matched: Bool, final: UInt32?) {
    var last: UInt32?
    for _ in 0..<attempts {
        Thread.sleep(forTimeInterval: Double(delayMs) / 1000.0)
        guard let raw = readUInt32(deviceID, lstm) else { return (false, nil) } // property vanished
        last = raw
        if raw == target { return (true, raw) }
    }
    return (false, last)
}

// MARK: - Report

func section(_ title: String) {
    print("\n" + String(repeating: "=", count: 72))
    print(title)
    print(String(repeating: "=", count: 72))
}

let doWrite = CommandLine.arguments.contains("--write")
let defaultID = defaultOutputDeviceID()

section("Status Trio — AirPods Listening Mode Spike (Issue #79 Phase 0)")
print("Mode: \(doWrite ? "READ + WRITE (will change and restore the mode)" : "READ-ONLY (no changes)")")
print("Default output device: \(defaultID.map { "#\($0) — \(deviceName($0))" } ?? "unknown")")

let outputs = allDeviceIDs().filter(isOutputDevice)
print("Output endpoints: \(outputs.count)")

var writableCandidates: [(AudioDeviceID, UInt32, UInt32)] = []

section("1. Per-device `lstm` / `lsms` probe")
for id in outputs {
    let isDefault = (id == defaultID)
    let iaapPresent = hasProperty(id, iaap)
    let lstmPresent = hasProperty(id, lstm)
    let lsmsPresent = hasProperty(id, lsms)
    let lstmSize = dataSize(id, lstm)
    let lsmsSize = dataSize(id, lsms)

    print("\n#\(id)  \(deviceName(id))\(isDefault ? "   [default output]" : "")")
    print("   iaap present:   \(iaapPresent)")
    print("   lstm present:   \(lstmPresent)  size: \(lstmSize.map(String.init(describing:)) ?? "-")  settable: \(lstmPresent ? String(isSettable(id, lstm)) : "-")")
    print("   lsms present:   \(lsmsPresent)  size: \(lsmsSize.map(String.init(describing:)) ?? "-")")

    guard lstmPresent, lsmsPresent,
          lstmSize == UInt32(MemoryLayout<UInt32>.size),
          lsmsSize == UInt32(MemoryLayout<UInt32>.size),
          let currentRaw = readUInt32(id, lstm),
          let mask = readUInt32(id, lsms) else {
        print("   → not a listening-mode endpoint (property missing / wrong size / unreadable)")
        continue
    }

    let settable = isSettable(id, lstm)
    print("   → current mode: \(modeName(currentRaw)) (raw \(currentRaw))")
    print("   → support mask: 0b\(String(mask, radix: 2)) → \(supportSummary(mask))")
    print("   → writable candidates from mask (non-Off, selectable): ", terminator: "")
    let selectable: [UInt32] = [2, 3, 4]
    let supported = selectable.filter { currentRaw == $0 ? false : mask & (1 << ($0 - 2)) != 0 }
    print(supported.isEmpty ? "none beyond current" : supported.map(modeName).joined(separator: ", "))

    if settable, !supported.isEmpty {
        writableCandidates.append((id, currentRaw, mask))
    } else if !settable {
        print("   → lstm NOT settable on this endpoint")
    }
}

section("2. Write / read-back test")
if !doWrite {
    print("Skipped. Re-run with --write to attempt a mode switch and restore it.")
} else if writableCandidates.isEmpty {
    print("No endpoint was both `lstm`-settable and had a second supported mode to switch to.")
} else {
    for (id, originalRaw, mask) in writableCandidates {
        let selectable: [UInt32] = [2, 3, 4]
        guard let target = selectable.first(where: { $0 != originalRaw && mask & (1 << ($0 - 2)) != 0 }) else { continue }
        print("\n#\(id)  \(deviceName(id))  \(modeName(originalRaw)) → \(modeName(target))")

        let status = writeUInt32(id, lstm, target)
        print("   set status: \(status) (\(status == noErr ? "noErr — but this is NOT device acknowledgement" : "FAILED"))")
        if status != noErr { continue }

        let result = boundedReadback(id, target: target)
        print("   read-back:  matched=\(result.matched)  final=\(result.final.map { modeName($0) + " (raw \($0))" } ?? "property-gone")")

        // Restore the original mode regardless of the outcome.
        let restoreStatus = writeUInt32(id, lstm, originalRaw)
        let restore = boundedReadback(id, target: originalRaw)
        print("   restore \(modeName(originalRaw)):  status=\(restoreStatus)  matched=\(restore.matched)")
    }
}

section("3. Spike verdict (see plan §3.2 / §3.3)")
if writableCandidates.isEmpty {
    print("""
    No writable endpoint found in read-only or write mode.
      • If `lstm` exists but is never settable → §3.3 Case B: STOP, do not build UI.
      • If only an endpoint you could not enumerate is settable → re-check on the real
        AirPods while they are the connected audio output.
      • If the connected device is not the default output and only the default is writable
        → §3.3 Case A: accept the "current output only" limitation.
    """)
} else {
    print("""
    \(writableCandidates.count) endpoint(s) expose a settable `lstm` with a second supported mode.
    Run with --write and confirm the read-back matched the target (not merely set=noErr).
    A matching read-back is macOS's control surface agreeing, not an accessory ack.
    If it matched on real ANC AirPods without changing default output / entitlement / private
    AV setter → Phase 0 PASSED; proceed to Step 2 (already scaffolded in StatusTrioCore/Audio).
    """)
}
