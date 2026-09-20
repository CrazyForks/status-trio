# Menu Bar Render Key Normalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Key the menu bar render cache on the values `StatusIconRenderer` actually draws, so a sub-bucket RSSI wobble or a sub-step volume change stops allocating an `NSImage` and redrawing the status item — without ever suppressing a redraw the user should see, and without freezing the item's VoiceOver text.

**Architecture:** `StatusBarRenderKey` stops carrying the raw `MenuBarStatus` and instead carries the same normalized inputs `DockIconRenderKey` already uses (`wifiBars`, `volumeSteps`, `gapContent`, `batteryColorRole`, the battery percentage, the clamped arc scalar, the Bluetooth device icon) plus the option structs, the icon size, and the appearance name. Both caches are fed the same `MenuBarStatus` and both icons draw through `StatusIconRenderer.draw(menuBarStatus:...)`, so the input list is shared by construction and a parity test makes any drift a failure. The existing `StatusMappings` helpers are reused as they are — no new quantization type is extracted (see `## Out of Scope`) — and the item's accessibility text gets its own cache gate, because the pixel inputs and the VoiceOver inputs are not the same set.

**Tech Stack:** Swift 6.3-compatible SwiftPM package (CI toolchain Xcode 26.6 / Swift 6.3.3, macOS 15 deployment target), AppKit, Combine, CoreGraphics, SF Symbols, XCTest.

**Spec:** Derived from the 2026-09-20 code review; cross-plan index: docs/superpowers/plans/2026-09-20-review-findings-index.md (finding **R-07**).

## Global Constraints

- CI acceptance toolchain is the `macos-26` runner with Xcode 26.6 / Swift 6.3.3. The local machine is Xcode 27 / Swift 6.4 — a local build is NOT proof that CI compiles.
- Forbidden in this repo: `isolated deinit`, enabling the `IsolatedDeinit` experimental feature, `weak let` (use `weak var`), passing actor-isolated methods directly as function values (use an explicit closure), assuming `Bundle.module` resource/lproj casing.
- The app must build with the macOS 26 SDK or newer; `scripts/build-app.sh` enforces it and `scripts/verify-platform-version.sh` asserts the binary. Do not weaken either.
- Run `swift test` and `swift build -c release` before committing Swift changes.
- If a change touches actor isolation, `@MainActor`, `deinit`, SwiftUI bindings, generics, or `Bundle.module` resources, a non-publishing release preflight is mandatory: `gh workflow run release.yml --repo lingyired/status-trio --ref <branch> -f version=1.3.0 -f build=12 -f publish=false` then `gh run watch <run-id> --repo lingyired/status-trio --exit-status`. This plan changes `@MainActor` rendering state, so the preflight is mandatory.
- Any user-visible behavior change requires release notes added to the existing unreleased `release-notes/1.3.0/en.md` and `release-notes/1.3.0/zh-Hans.md`.
- Any change to menu bar icon rendering or icon settings must be mirrored in the Dock icon in the same change (SettingsStore option derivation, StatusBarController subscriptions, AppIconController subscriptions/state, `DockIconRenderKey` cache inputs, `DockIconRenderer` rendering, plus tests for both). This plan *is* the mirror: it brings the menu bar key up to the Dock key, and `testMenuBarAndDockKeysReactToTheSameChanges` asserts that the two keys react to exactly the same status changes. `DockIconRenderKey` itself is not modified.
- Tests are mixed: most files use Swift Testing (`import Testing`, `@Test`, `#expect`, `@MainActor` suites), some use XCTest (`XCTAssert*`, `XCTSkipUnless`). Read the test file you extend and match its framework and style. `Tests/StatusTrioCoreTests/StatusBarRenderCacheTests.swift` exists and is XCTest (`final class ...: XCTestCase`); extend it in that style rather than adding a Swift Testing file.
- The existing initializer signature `StatusBarRenderKey(status:iconSize:options:connectionOptions:volumeOptions:bluetoothAudioOptions:appearanceName:)` is part of two other test files (`Tests/StatusTrioCoreTests/WiFiSummaryTests.swift:119-124`, `Tests/StatusTrioCoreTests/IconAppearancePublisherTests.swift:181-190`). Keep it; normalize inside the initializer, exactly as `DockIconRenderKey` does.
- Do not run the app to verify this plan. The rendered-output assertions use the existing `PixelBuffer` test support (`Tests/StatusTrioCoreTests/TestSupport/PixelBuffer.swift`).

## Review Focus

- **±1 dBm of RSSI wobble used to redraw the menu bar icon for nothing.** `StatusMappings.wifiBars` collapses `-50` and `-55` into the same three bars, so they must share a key: `testSubBucketSignalNoiseDoesNotInvalidateTheMenuBarImage` renders both, requires one cache miss and one suppression, and asserts the two bitmaps are byte-identical.
- **A volume change inside one dot step used to redraw for nothing.** `0.51` and `0.60` both draw three dots: `testSubBucketSignalNoiseDoesNotInvalidateTheMenuBarImage` pins that second half too, and `testStatesWithDifferentRenderKeysDrawDifferentPixels` pins that a real step change (`0.10` against `0.90`) still redraws.
- **Over-normalization would freeze the icon.** Every value the glyph reads must stay in the key: `testMenuBarAndDockKeysReactToTheSameChanges` walks thirteen status pairs and requires the menu bar and Dock keys to agree on "changed" versus "unchanged" for each one, `testStatesWithDifferentRenderKeysDrawDifferentPixels` proves the differing pairs really produce different bitmaps, and `testArcVolumeKeepsTheContinuousScalarInTheKey` keeps the continuous arc out of the four-dot buckets.
- **The VoiceOver text is not the icon.** The SSID, the exact volume percentage and the charged flag reach `StatusPresentation.statusItemAccessibilityValue` but never reach a pixel, so gating the accessibility write behind the image cache would silently freeze the spoken text: `testAccessibilityTextUpdatesWhenOnlyTheVoiceOverValueChanges` requires the two gates to answer independently, and Task 4 moves the accessibility write above the image gate in `StatusBarController.render`.
- **A settings change must still reach the icon immediately.** `IconAppearancePublisherTests` drives every icon setting through `StatusBarRenderCache` and requires a new key for each; the option structs stay whole fields of the key, so a ring-stroke or symbol-scale change cannot be normalized away.

---

### Task 1: Normalize The Menu Bar Render Key To The Drawn Values

**Files:**
- Modify: `Sources/StatusTrioCore/UI/Icon/StatusBarRenderCache.swift` (lines 1-27 `StatusBarRenderKey` and its initializer; `StatusBarRenderCache` at lines 29-37 is unchanged in this task)
- Test: `Tests/StatusTrioCoreTests/StatusBarRenderCacheTests.swift` (new tests after `testRingStrokeWidthChangeRendersAgain`, lines 71-85; extend the helpers at lines 87-131; add `import CoreGraphics` next to `import CoreAudio` at line 1)

**Interfaces:**
- Consumes: `StatusMappings.wifiBars(rssi:)` (`Sources/StatusTrioCore/Models/StatusMappings.swift:29-42`), `StatusMappings.volumeSteps(scalar:isMuted:)` (57-65), `StatusMappings.batteryGapContent(_:options:)` (82-96), `StatusMappings.batteryColorRole(_:criticalThreshold:)` (67-76), `AudioOutputDeviceIcon.source(for:)` (`Sources/StatusTrioCore/Audio/AudioOutputDeviceIcon.swift:194-206`), `MenuBarStatus` (`Sources/StatusTrioCore/Models/MenuBarStatus.swift:31-61`).
- Produces: `StatusBarRenderKey` with stored properties `batteryPercentage: Int`, `gapContent: BatteryGapContent`, `batteryColorRole: BatteryColorRole`, `connection: NetworkConnection`, `wifiState: WiFiState`, `wifiBars: Int`, `volumeSteps: Int`, `volumeArcProgress: Double?`, `bluetoothAudioDeviceIcon: AudioOutputDeviceIconSource?`, `iconSize: Double`, `options: BatteryIconOptions`, `connectionOptions: ConnectionIconOptions`, `volumeOptions: VolumeIconOptions`, `bluetoothAudioOptions: BluetoothAudioIconOptions`, `appearanceName: String`; initializer signature unchanged.

- [ ] **Step 1: Write the failing noise-dedupe test**

Add to `StatusBarRenderCacheTests`:

```swift
    func testSubBucketSignalNoiseDoesNotInvalidateTheMenuBarImage() throws {
        var cache = StatusBarRenderCache()
        // -50 and -55 dBm are the same three Wi-Fi bars; 0.51 and 0.60 are the
        // same three volume dots.
        let calm = makeStatus(wifi: WiFiStatus(state: .connected, rssi: -50), volumeScalar: 0.51)
        let wobble = makeStatus(wifi: WiFiStatus(state: .connected, rssi: -55), volumeScalar: 0.60)

        XCTAssertTrue(cache.shouldRender(makeKey(for: calm)))
        XCTAssertFalse(
            cache.shouldRender(makeKey(for: wobble)),
            "a state that draws the same pixels must not allocate another image"
        )
        XCTAssertEqual(try renderedPixels(calm).bytes, try renderedPixels(wobble).bytes)
    }
```

Add the helpers the rest of this plan uses:

```swift
    private func makeStatus(
        battery: BatteryStatus = .placeholder,
        wifi: WiFiStatus = WiFiStatus(state: .connected, rssi: -50),
        connection: NetworkConnection = .wifi,
        volumeScalar: Double? = 0.5,
        isMuted: Bool = false,
        currentDevice: AudioOutputDevice? = nil
    ) -> MenuBarStatus {
        MenuBarStatus(
            battery: battery,
            wifi: wifi,
            connection: connection,
            volume: MenuBarVolumeStatus(
                scalar: volumeScalar,
                isMuted: isMuted,
                deviceName: "Speakers",
                currentDevice: currentDevice
            )
        )
    }

    private func makeKey(
        for status: MenuBarStatus,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
        appearance: String = "darkAqua"
    ) -> StatusBarRenderKey {
        StatusBarRenderKey(
            status: status,
            iconSize: 28,
            options: options,
            connectionOptions: connectionOptions,
            volumeOptions: volumeOptions,
            bluetoothAudioOptions: bluetoothAudioOptions,
            appearanceName: appearance
        )
    }

    private func renderedPixels(
        _ status: MenuBarStatus,
        connectionOptions: ConnectionIconOptions = .standard,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard
    ) throws -> PixelBuffer {
        let image = try XCTUnwrap(StatusIconRenderer.render(
            menuBarStatus: status,
            size: 20,
            scale: 8,
            foreground: CGColor(gray: 1, alpha: 1),
            connectionOptions: connectionOptions,
            volumeOptions: volumeOptions,
            bluetoothAudioOptions: bluetoothAudioOptions
        ))
        return try PixelBuffer(image: image)
    }
```

- [ ] **Step 2: Run the test and verify RED**

Run: `swift test --filter StatusBarRenderCacheTests/testSubBucketSignalNoiseDoesNotInvalidateTheMenuBarImage`
Expected: `XCTAssertFalse failed: a state that draws the same pixels must not allocate another image` — the key still stores the raw `rssi` (-50 against -55) and the raw scalar (0.51 against 0.60).

- [ ] **Step 3: Replace the key's inputs**

Rewrite `StatusBarRenderKey` in `StatusBarRenderCache.swift`:

```swift
/// Identifies what the menu bar icon actually draws, so signal noise that cannot
/// change a pixel — a different RSSI inside the same bar count, a different
/// volume inside the same dot count — does not allocate another `NSImage` and
/// redraw the status item.
///
/// The input list mirrors `DockIconRenderKey`: both icons draw the same glyph
/// through `StatusIconRenderer.draw(menuBarStatus:...)`, so both keys have to
/// react to the same status changes. `StatusBarRenderCacheTests` asserts that
/// parity, which is what keeps the two paths from drifting apart.
struct StatusBarRenderKey: Equatable {
    let batteryPercentage: Int
    let gapContent: BatteryGapContent
    let batteryColorRole: BatteryColorRole
    let connection: NetworkConnection
    let wifiState: WiFiState
    let wifiBars: Int
    let volumeSteps: Int
    let volumeArcProgress: Double?
    let bluetoothAudioDeviceIcon: AudioOutputDeviceIconSource?
    let iconSize: Double
    let options: BatteryIconOptions
    let connectionOptions: ConnectionIconOptions
    let volumeOptions: VolumeIconOptions
    let bluetoothAudioOptions: BluetoothAudioIconOptions
    let appearanceName: String

    init(
        status: MenuBarStatus,
        iconSize: Double,
        options: BatteryIconOptions,
        connectionOptions: ConnectionIconOptions,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
        appearanceName: String
    ) {
        self.batteryPercentage = status.battery.percentage
        self.gapContent = StatusMappings.batteryGapContent(status.battery, options: options)
        self.batteryColorRole = options.usesStatusColors
            ? StatusMappings.batteryColorRole(
                status.battery,
                criticalThreshold: options.criticalThreshold
            )
            : .foreground
        self.connection = status.connection
        self.wifiState = status.wifi.state
        self.wifiBars = StatusMappings.wifiBars(rssi: status.wifi.rssi)
        self.volumeSteps = StatusMappings.volumeSteps(
            scalar: status.volume.scalar,
            isMuted: status.volume.isMuted
        ) ?? 0
        // The dots are four fixed steps; the arc is continuous, so it keeps the
        // same clamped scalar `DockIconRenderKey` keeps. `volumeArcFill`
        // (StatusIconGeometry.swift:346-360) clamps internally, so values beyond
        // the range draw the same picture.
        self.volumeArcProgress = volumeOptions.displayStyle == .arc
            ? status.volume.scalar.flatMap(Self.clampedVolume)
            : nil
        // A pixel input whenever `replacesNetworkIcon` or `usesVolumeColor` is
        // on, and a Dock key field unconditionally; mirror the Dock.
        self.bluetoothAudioDeviceIcon = status.volume.currentDevice?.isBluetoothAudio == true
            ? status.volume.currentDevice.map { AudioOutputDeviceIcon.source(for: $0) }
            : nil
        self.iconSize = iconSize
        self.options = options
        self.connectionOptions = connectionOptions
        self.volumeOptions = volumeOptions
        self.bluetoothAudioOptions = bluetoothAudioOptions
        self.appearanceName = appearanceName
    }

    private static func clampedVolume(_ scalar: Double) -> Double? {
        guard scalar.isFinite else { return nil }
        return min(1, max(0, scalar))
    }
}
```

The values that stay out of the key are exactly the ones `draw(menuBarStatus:...)` never reads: `wifi.ssid`, `wifi.nameAccess`, `wifi.band` (already dropped by `MenuBarStatus.init`), `volume.deviceName` and `volume.outputDevices`, and `battery.rawPercentage` / `isCharged` / `timeToFullChargeMinutes` beyond the clamped `percentage`. `battery.isPresent`, `isCharging`, `isConnectedToPower` and `isLowPowerMode` are read **only** through `StatusMappings.batteryGapContent` and `StatusMappings.batteryColorRole` (`Sources/StatusTrioCore/UI/Icon/StatusIconRenderer.swift:297-372`), so the two derived fields carry them.

- [ ] **Step 4: Run the tests**

Run: `swift test --filter StatusBarRenderCacheTests`
Expected: PASS, with every pre-existing test in the file still green — `testOutputDevicesDoNotInvalidateMenuBarStatus`, `testAppearanceChangeRendersAgain`, `testRingStrokeWidthChangeRendersAgain` and the two Bluetooth tests cover the option and appearance inputs this rewrite keeps.
Run: `swift test --filter WiFiSummaryTests`
Run: `swift test --filter IconAppearancePublisherTests`
Expected: PASS — both files construct `StatusBarRenderKey` with the unchanged initializer.

- [ ] **Step 5: Commit**

Run: `git add Sources/StatusTrioCore/UI/Icon/StatusBarRenderCache.swift Tests/StatusTrioCoreTests/StatusBarRenderCacheTests.swift && git commit -m "perf(icon): key the menu bar render cache on drawn values"`

---

### Task 2: Prove The Normalized Key Is Neither Too Coarse Nor Too Fine

**Files:**
- Test: `Tests/StatusTrioCoreTests/StatusBarRenderCacheTests.swift` (new tests after the Task 1 test; one new helper)

**Interfaces:**
- Consumes: `StatusBarRenderKey` from Task 1, `DockIconRenderKey` (`Sources/StatusTrioCore/UI/Icon/DockIconRenderCache.swift:4-63`), `PixelBuffer` (test support).
- Produces: no production API; a parity assertion between the two render keys.

- [ ] **Step 1: Write the failing parity test**

Add the Dock key helper and the matrix:

```swift
    private func makeDockKey(
        _ status: MenuBarStatus,
        volumeOptions: VolumeIconOptions = .standard
    ) -> DockIconRenderKey {
        DockIconRenderKey(
            status: status,
            options: .standard,
            connectionOptions: .standard,
            volumeOptions: volumeOptions,
            backgroundStyle: .dark
        )
    }

    /// The two icons draw the same glyph with the same options, so any pair of
    /// states the Dock key treats as one render must be one render for the menu
    /// bar too, and vice versa. This is the assertion that fails when one key
    /// gains an input the other does not have.
    func testMenuBarAndDockKeysReactToTheSameChanges() {
        let pairs: [(name: String, first: MenuBarStatus, second: MenuBarStatus)] = [
            (
                "RSSI inside one bar bucket",
                makeStatus(wifi: WiFiStatus(state: .connected, rssi: -50)),
                makeStatus(wifi: WiFiStatus(state: .connected, rssi: -55))
            ),
            (
                "RSSI across a bar boundary",
                makeStatus(wifi: WiFiStatus(state: .connected, rssi: -50)),
                makeStatus(wifi: WiFiStatus(state: .connected, rssi: -80))
            ),
            (
                "RSSI lost while connected",
                makeStatus(wifi: WiFiStatus(state: .connected, rssi: -50)),
                makeStatus(wifi: WiFiStatus(state: .connected, rssi: nil))
            ),
            (
                "volume inside one dot step",
                makeStatus(volumeScalar: 0.51),
                makeStatus(volumeScalar: 0.60)
            ),
            (
                "volume across dot steps",
                makeStatus(volumeScalar: 0.10),
                makeStatus(volumeScalar: 0.90)
            ),
            (
                "mute at the same scalar",
                makeStatus(volumeScalar: 0.5, isMuted: true),
                makeStatus(volumeScalar: 0.5, isMuted: false)
            ),
            (
                "network name only",
                makeStatus(wifi: WiFiStatus(state: .connected, rssi: -50, ssid: "Home", nameAccess: .authorized)),
                makeStatus(wifi: WiFiStatus(state: .connected, rssi: -50, ssid: "Cafe", nameAccess: .authorized))
            ),
            (
                "Wi-Fi against Ethernet",
                makeStatus(connection: .wifi),
                makeStatus(connection: .ethernet)
            ),
            (
                "Wi-Fi turns off",
                makeStatus(wifi: WiFiStatus(state: .connected, rssi: -50)),
                makeStatus(wifi: WiFiStatus(state: .off, rssi: nil))
            ),
            (
                "battery crosses the critical threshold",
                makeStatus(battery: BatteryStatus(rawPercentage: 19, isPresent: true, isCharging: false, isLowPowerMode: false, isConnectedToPower: false)),
                makeStatus(battery: BatteryStatus(rawPercentage: 20, isPresent: true, isCharging: false, isLowPowerMode: false, isConnectedToPower: false))
            ),
            (
                "battery starts charging",
                makeStatus(battery: BatteryStatus(rawPercentage: 50, isPresent: true, isCharging: false, isLowPowerMode: false, isConnectedToPower: false)),
                makeStatus(battery: BatteryStatus(rawPercentage: 50, isPresent: true, isCharging: true, isLowPowerMode: false, isConnectedToPower: true))
            ),
            (
                "Bluetooth audio becomes the current device",
                makeStatus(currentDevice: nil),
                makeStatus(currentDevice: AudioOutputDevice(
                    id: 42,
                    name: "AirPods Pro",
                    uid: "airpods-pro",
                    isCurrent: true,
                    volume: 0.5,
                    transport: .bluetooth
                ))
            ),
            (
                "charged flag only",
                makeStatus(battery: BatteryStatus(rawPercentage: 100, isPresent: true, isCharging: false, isCharged: true, isLowPowerMode: false, isConnectedToPower: false)),
                makeStatus(battery: BatteryStatus(rawPercentage: 100, isPresent: true, isCharging: false, isCharged: false, isLowPowerMode: false, isConnectedToPower: false))
            )
        ]

        for pair in pairs {
            XCTAssertEqual(
                makeKey(for: pair.first) == makeKey(for: pair.second),
                makeDockKey(pair.first) == makeDockKey(pair.second),
                pair.name
            )
        }
    }
```

- [ ] **Step 2: Write the pixel-completeness and arc tests**

```swift
    func testStatesThatShareOneRenderKeyDrawIdenticalPixels() throws {
        let pairs: [(name: String, first: MenuBarStatus, second: MenuBarStatus)] = [
            (
                "RSSI inside one bar bucket",
                makeStatus(wifi: WiFiStatus(state: .connected, rssi: -50)),
                makeStatus(wifi: WiFiStatus(state: .connected, rssi: -55))
            ),
            (
                "volume inside one dot step",
                makeStatus(volumeScalar: 0.51),
                makeStatus(volumeScalar: 0.60)
            ),
            (
                "network name only",
                makeStatus(wifi: WiFiStatus(state: .connected, rssi: -50, ssid: "Home", nameAccess: .authorized)),
                makeStatus(wifi: WiFiStatus(state: .connected, rssi: -50, ssid: "Cafe", nameAccess: .authorized))
            ),
            (
                "charged flag only",
                makeStatus(battery: BatteryStatus(rawPercentage: 100, isPresent: true, isCharging: false, isCharged: true, isLowPowerMode: false, isConnectedToPower: false)),
                makeStatus(battery: BatteryStatus(rawPercentage: 100, isPresent: true, isCharging: false, isCharged: false, isLowPowerMode: false, isConnectedToPower: false))
            )
        ]

        for pair in pairs {
            XCTAssertEqual(
                makeKey(for: pair.first),
                makeKey(for: pair.second),
                pair.name
            )
            XCTAssertEqual(
                try renderedPixels(pair.first).bytes,
                try renderedPixels(pair.second).bytes,
                pair.name
            )
        }
    }

    func testStatesWithDifferentRenderKeysDrawDifferentPixels() throws {
        let bluetoothOptions = BluetoothAudioIconOptions(replacesNetworkIcon: true)
        let pairs: [(name: String, first: MenuBarStatus, second: MenuBarStatus, bluetooth: BluetoothAudioIconOptions)] = [
            (
                "RSSI across a bar boundary",
                makeStatus(wifi: WiFiStatus(state: .connected, rssi: -50)),
                makeStatus(wifi: WiFiStatus(state: .connected, rssi: -80)),
                .standard
            ),
            (
                "volume across dot steps",
                makeStatus(volumeScalar: 0.10),
                makeStatus(volumeScalar: 0.90),
                .standard
            ),
            (
                "mute at the same scalar",
                makeStatus(volumeScalar: 0.5, isMuted: true),
                makeStatus(volumeScalar: 0.5, isMuted: false),
                .standard
            ),
            (
                "Wi-Fi against Ethernet",
                makeStatus(connection: .wifi),
                makeStatus(connection: .ethernet),
                .standard
            ),
            (
                "Wi-Fi turns off",
                makeStatus(wifi: WiFiStatus(state: .connected, rssi: -50)),
                makeStatus(wifi: WiFiStatus(state: .off, rssi: nil)),
                .standard
            ),
            (
                "battery crosses the critical threshold",
                makeStatus(battery: BatteryStatus(rawPercentage: 19, isPresent: true, isCharging: false, isLowPowerMode: false, isConnectedToPower: false)),
                makeStatus(battery: BatteryStatus(rawPercentage: 20, isPresent: true, isCharging: false, isLowPowerMode: false, isConnectedToPower: false)),
                .standard
            ),
            (
                "battery starts charging",
                makeStatus(battery: BatteryStatus(rawPercentage: 50, isPresent: true, isCharging: false, isLowPowerMode: false, isConnectedToPower: false)),
                makeStatus(battery: BatteryStatus(rawPercentage: 50, isPresent: true, isCharging: true, isLowPowerMode: false, isConnectedToPower: true)),
                .standard
            ),
            (
                "Bluetooth audio replaces the network glyph",
                makeStatus(currentDevice: AudioOutputDevice(
                    id: 42,
                    name: "AirPods Pro",
                    uid: "airpods-pro",
                    isCurrent: true,
                    volume: 0.5,
                    transport: .bluetooth
                )),
                makeStatus(currentDevice: AudioOutputDevice(
                    id: 43,
                    name: "USB Headset",
                    uid: "usb-headset",
                    isCurrent: true,
                    volume: 0.5,
                    transport: .usb
                )),
                bluetoothOptions
            )
        ]

        for pair in pairs {
            XCTAssertNotEqual(
                makeKey(for: pair.first, bluetoothAudioOptions: pair.bluetooth),
                makeKey(for: pair.second, bluetoothAudioOptions: pair.bluetooth),
                pair.name
            )
            XCTAssertNotEqual(
                try renderedPixels(pair.first, bluetoothAudioOptions: pair.bluetooth).bytes,
                try renderedPixels(pair.second, bluetoothAudioOptions: pair.bluetooth).bytes,
                pair.name
            )
        }
    }

    func testArcVolumeKeepsTheContinuousScalarInTheKey() throws {
        let arc = VolumeIconOptions(displayStyle: .arc)
        var cache = StatusBarRenderCache()
        // Both are two dots, but the arc is continuous: these two states must not
        // share a key, or a volume held down with the keyboard would look stuck.
        let quarter = makeStatus(volumeScalar: 0.26)
        let nearlyHalf = makeStatus(volumeScalar: 0.45)

        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.26, isMuted: false), 2)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.45, isMuted: false), 2)
        XCTAssertTrue(cache.shouldRender(makeKey(for: quarter, volumeOptions: arc)))
        XCTAssertTrue(cache.shouldRender(makeKey(for: nearlyHalf, volumeOptions: arc)))
        XCTAssertNotEqual(
            try renderedPixels(quarter, volumeOptions: arc).bytes,
            try renderedPixels(nearlyHalf, volumeOptions: arc).bytes
        )

        // Past the range the renderer's own clamp decides the picture
        // (StatusIconGeometry.swift:346-360), so the key normalizes the same way
        // instead of asking for another redraw of a full arc.
        XCTAssertEqual(
            makeKey(for: makeStatus(volumeScalar: 1.5), volumeOptions: arc),
            makeKey(for: makeStatus(volumeScalar: 2.0), volumeOptions: arc)
        )
        XCTAssertEqual(
            makeKey(for: makeStatus(volumeScalar: -1), volumeOptions: arc),
            makeKey(for: makeStatus(volumeScalar: 0), volumeOptions: arc)
        )
        // Muted draws the empty track whatever the scalar is.
        XCTAssertNotEqual(
            makeKey(for: makeStatus(volumeScalar: 0.5, isMuted: true), volumeOptions: arc),
            makeKey(for: makeStatus(volumeScalar: 0.5, isMuted: false), volumeOptions: arc)
        )
    }
```

`AudioOutputTransport.usb` (`Sources/StatusTrioCore/Audio/AudioOutputDeviceIcon.swift:12-24`) is the wired case that makes `StatusMappings.shouldReplaceNetworkIcon` return false, so with `replacesNetworkIcon` on, the Bluetooth pair draws the device glyph against the Wi-Fi glyph.

- [ ] **Step 3: Run the new tests and verify RED**

Run: `swift test --filter StatusBarRenderCacheTests/testMenuBarAndDockKeysReactToTheSameChanges`
Expected against the un-normalized key (with Task 1's production change stashed): `XCTAssertEqual failed: RSSI inside one bar bucket` — the menu bar key changes where the Dock key does not. With Task 1 in place this test is the green guard that stops a later edit from re-adding an input to only one of the two keys; to watch it fail on demand, temporarily replace `StatusMappings.wifiBars(rssi: status.wifi.rssi)` with `status.wifi.rssi` in the key, confirm the two noise pairs fail, then restore it.

Run: `swift test --filter StatusBarRenderCacheTests/testStatesThatShareOneRenderKeyDrawIdenticalPixels`
Expected against the un-normalized key: the same failure as Task 1's noise test, on the first pair.

Run: `swift test --filter StatusBarRenderCacheTests/testArcVolumeKeepsTheContinuousScalarInTheKey`
Expected against the un-normalized key: `XCTAssertEqual failed:` on the clamp pairs — raw `-1` and `0` do not compare equal before `clampedVolume` runs, and neither do `1.5` and `2.0`.

`testStatesWithDifferentRenderKeysDrawDifferentPixels` is the guard in the other direction: it must pass both before and after the normalization, because it asserts that a change the user can see is never swallowed by the cache.

- [ ] **Step 4: Run the tests**

Run: `swift test --filter StatusBarRenderCacheTests`
Expected: PASS, all five new tests plus the pre-existing ones.

- [ ] **Step 5: Commit**

Run: `git add Tests/StatusTrioCoreTests/StatusBarRenderCacheTests.swift && git commit -m "test(icon): pin menu bar and Dock render key parity"`

---

### Task 3: Gate The Accessibility Text Separately From The Image

**Files:**
- Modify: `Sources/StatusTrioCore/UI/Icon/StatusBarRenderCache.swift` (move `StatusBarAccessibilityKey` here from `Sources/StatusTrioCore/UI/StatusBarController.swift:9-12`; extend `StatusBarRenderCache` at lines 29-37)
- Modify: `Sources/StatusTrioCore/UI/StatusBarController.swift` (delete the now-duplicated private struct at lines 9-12)
- Test: `Tests/StatusTrioCoreTests/StatusBarRenderCacheTests.swift` (new test after the Task 2 tests)

**Interfaces:**
- Consumes: `MenuBarStatus`, `AppLanguage` (`Sources/StatusTrioCore/Localization/AppLanguage.swift:4-16`).
- Produces: `struct StatusBarAccessibilityKey: Equatable { let status: MenuBarStatus; let language: AppLanguage }` (internal, moved from `StatusBarController`).
- Produces: `mutating func shouldUpdateAccessibility(_ key: StatusBarAccessibilityKey) -> Bool` and `private(set) var lastAccessibilityKey: StatusBarAccessibilityKey?` on `StatusBarRenderCache`.

- [ ] **Step 1: Write the failing accessibility-gate test**

```swift
    func testAccessibilityTextUpdatesWhenOnlyTheVoiceOverValueChanges() {
        var cache = StatusBarRenderCache()
        let named = makeStatus(
            wifi: WiFiStatus(state: .connected, rssi: -50, ssid: "Home", nameAccess: .authorized)
        )
        let renamed = makeStatus(
            wifi: WiFiStatus(state: .connected, rssi: -50, ssid: "Cafe", nameAccess: .authorized)
        )

        // The SSID is not drawn into the menu bar icon, so the image is reused.
        XCTAssertTrue(cache.shouldRender(makeKey(for: named)))
        XCTAssertFalse(cache.shouldRender(makeKey(for: renamed)))

        // The spoken text does read it, so it must still be applied — and only
        // once per value, and again for another language.
        XCTAssertTrue(cache.shouldUpdateAccessibility(
            StatusBarAccessibilityKey(status: named, language: .english)
        ))
        XCTAssertTrue(cache.shouldUpdateAccessibility(
            StatusBarAccessibilityKey(status: renamed, language: .english)
        ))
        XCTAssertFalse(cache.shouldUpdateAccessibility(
            StatusBarAccessibilityKey(status: renamed, language: .english)
        ))
        XCTAssertTrue(cache.shouldUpdateAccessibility(
            StatusBarAccessibilityKey(status: renamed, language: .simplifiedChinese)
        ))
    }
```

- [ ] **Step 2: Run the test and verify RED**

Run: `swift test --filter StatusBarRenderCacheTests/testAccessibilityTextUpdatesWhenOnlyTheVoiceOverValueChanges`
Expected: compile failure — `cannot find 'StatusBarAccessibilityKey' in scope` (it is `private` inside `StatusBarController`) and `value of type 'StatusBarRenderCache' has no member 'shouldUpdateAccessibility'`.

- [ ] **Step 3: Move the key and add the second gate**

In `StatusBarRenderCache.swift`, above `StatusBarRenderCache`:

```swift
/// The status item's VoiceOver text. It reads values the icon cannot draw — the
/// network name, the exact volume percentage, the charged flag — so it gets its
/// own cache instead of riding on the image cache.
struct StatusBarAccessibilityKey: Equatable {
    let status: MenuBarStatus
    let language: AppLanguage
}
```

Extend the cache:

```swift
struct StatusBarRenderCache {
    private(set) var lastKey: StatusBarRenderKey?
    private(set) var lastAccessibilityKey: StatusBarAccessibilityKey?

    mutating func shouldRender(_ key: StatusBarRenderKey) -> Bool {
        guard key != lastKey else { return false }
        lastKey = key
        return true
    }

    /// Accessibility has its own gate on purpose: an SSID change or a 1% volume
    /// change alters the spoken text while the bitmap stays identical, and the
    /// image cache must not be allowed to swallow it.
    mutating func shouldUpdateAccessibility(_ key: StatusBarAccessibilityKey) -> Bool {
        guard key != lastAccessibilityKey else { return false }
        lastAccessibilityKey = key
        return true
    }
}
```

In `StatusBarController.swift` delete the private struct at lines 9-12; the type now comes from this file.

- [ ] **Step 4: Run the tests**

Run: `swift test --filter StatusBarRenderCacheTests`
Expected: PASS.
Run: `swift build`
Expected: the build succeeds; `StatusBarController` still compiles because the moved type is internal to the module. Task 4 is what starts using it.

- [ ] **Step 5: Commit**

Run: `git add Sources/StatusTrioCore/UI/Icon/StatusBarRenderCache.swift Sources/StatusTrioCore/UI/StatusBarController.swift Tests/StatusTrioCoreTests/StatusBarRenderCacheTests.swift && git commit -m "fix(icon): give the status item accessibility its own cache gate"`

---

### Task 4: Apply The Two Gates In `StatusBarController`

**Files:**
- Modify: `Sources/StatusTrioCore/UI/StatusBarController.swift` (delete `private var accessibilityKey` at line 41; rewrite `render(_:status:)` at lines 461-500)

**Interfaces:**
- Consumes: `StatusBarAccessibilityKey` and `shouldUpdateAccessibility(_:)` from Task 3; `renderCache` (line 38); `renderLatestSnapshot()` (lines 505-513) and `IconRenderCoalescer` (line 39) are unchanged.
- Produces: `private func render(_ appearance: StatusIconAppearance, status: MenuBarStatus)` whose accessibility write no longer sits behind the image-cache guard.

- [ ] **Step 1: Show that accessibility is still behind the image gate**

Run: `grep -n "shouldRender\|shouldUpdateAccessibility\|setAccessibilityValue" Sources/StatusTrioCore/UI/StatusBarController.swift`
Expected: only `shouldRender` (line 476) and `setAccessibilityValue` (line 494), with the accessibility write below the `guard renderCache.shouldRender(key) else { return }` — so any state whose normalized key repeats keeps the old spoken text.

- [ ] **Step 2: Rewrite `render(_:status:)`**

```swift
    private func render(
        _ appearance: StatusIconAppearance,
        status: MenuBarStatus
    ) {
        guard isStatusItemVisible, let button = statusItem.button else { return }

        // The two caches have different inputs. The icon cannot draw the SSID,
        // the exact volume percentage or the charged flag, and the VoiceOver
        // value reads all three, so it is gated first and on its own.
        let nextAccessibilityKey = StatusBarAccessibilityKey(
            status: status,
            language: localization.resolvedLanguage
        )
        if renderCache.shouldUpdateAccessibility(nextAccessibilityKey) {
            button.setAccessibilityLabel(StatusPresentation.statusItemAccessibilityLabel)
            button.setAccessibilityValue(
                StatusPresentation.statusItemAccessibilityValue(
                    status,
                    localization: localization
                )
            )
        }

        let key = StatusBarRenderKey(
            status: status,
            iconSize: appearance.iconSize,
            options: appearance.batteryOptions,
            connectionOptions: appearance.connectionOptions,
            volumeOptions: appearance.volumeOptions,
            bluetoothAudioOptions: appearance.bluetoothAudioOptions,
            appearanceName: button.effectiveAppearance.name.rawValue
        )
        guard renderCache.shouldRender(key) else { return }

        button.image = StatusIconRenderer.image(
            menuBarStatus: status,
            size: appearance.iconSize,
            options: appearance.batteryOptions,
            connectionOptions: appearance.connectionOptions,
            volumeOptions: appearance.volumeOptions,
            bluetoothAudioOptions: appearance.bluetoothAudioOptions
        )
    }
```

Delete `private var accessibilityKey: StatusBarAccessibilityKey?` at line 41; the cache now owns both keys. `setVisible(_:)` (lines 142-155) keeps resetting `renderCache = StatusBarRenderCache()`, which resets both gates when the item is shown again.

- [ ] **Step 3: Verify the gate order**

Run: `grep -n "shouldRender\|shouldUpdateAccessibility\|setAccessibilityValue" Sources/StatusTrioCore/UI/StatusBarController.swift`
Expected: `shouldUpdateAccessibility` and `setAccessibilityValue` both at lower line numbers than `shouldRender`, so the accessibility write can no longer be skipped by a repeated image key.

- [ ] **Step 4: Run the suites that exercise the cache and the controller**

Run: `swift test --filter StatusBarRenderCacheTests`
Run: `swift test --filter IconAppearancePublisherTests`
Run: `swift test --filter StatusPresentationTests`
Expected: PASS.
Run: `swift build -c release`
Expected: successful build.

- [ ] **Step 5: Commit**

Run: `git add Sources/StatusTrioCore/UI/StatusBarController.swift && git commit -m "fix(a11y): refresh the status item text even when the icon is reused"`

---

### Task 5: Release Notes

**Files:**
- Modify: `release-notes/1.3.0/en.md` (append one section)
- Modify: `release-notes/1.3.0/zh-Hans.md` (append the matching section)

**Interfaces:**
- Consumes: the behavior from Tasks 1-4.
- Produces: no code. `bash scripts/validate-appcast-notes.sh` reads both files.

- [ ] **Step 1: Prove the notes do not mention the change yet**

Run: `grep -c "VoiceOver" release-notes/1.3.0/en.md; grep -c "旁白" release-notes/1.3.0/zh-Hans.md`
Expected: `0` and `0`.

- [ ] **Step 2: Add the English section**

```markdown
## VoiceOver keeps up with the icon
- The menu bar item's VoiceOver description now refreshes as soon as the network name, the exact volume or the charging state changes, including when the icon itself does not need to be redrawn.
- The icon also stops re-drawing itself for signal noise that cannot change a pixel, such as a one-decibel Wi-Fi wobble inside the same bar count.
```

- [ ] **Step 3: Add the Chinese section**

```markdown
## 旁白描述与图标保持同步
- 网络名称、精确音量或充电状态变化时，菜单栏图标的「旁白」描述会立即更新，即使图标本身不需要重绘。
- 同样地，在同一格信号强度内的 Wi-Fi 波动等不会改变像素的噪声，不再触发图标重绘。
```

- [ ] **Step 4: Re-run the checks**

Run: `grep -c "VoiceOver" release-notes/1.3.0/en.md; grep -c "旁白" release-notes/1.3.0/zh-Hans.md`
Expected: `2` and `2` — the new heading and the new first bullet each carry the term in both languages.
Run: `bash scripts/validate-appcast-notes.sh`
Expected: PASS — both files keep their `# Version %VERSION% (Build %BUILD%)` / `# 版本 %VERSION%（构建 %BUILD%）` heading.

- [ ] **Step 5: Commit**

Run: `git add release-notes/1.3.0/en.md release-notes/1.3.0/zh-Hans.md && git commit -m "docs(release-notes): note the VoiceOver refresh and the quieter icon redraw"`

---

### Task 6: Full Verification

**Files:**
- No production files.

**Interfaces:**
- Consumes: every task above.
- Produces: no code.

- [ ] **Step 1: Run the full suite**

Run: `swift test`
Expected: every test passes, including the five new render-cache tests and the unchanged `Issue13IconParityTests`, `DockIconRenderCacheTests` and `StatusIconRendererTests`.

- [ ] **Step 2: Run the release build**

Run: `swift build -c release`
Expected: successful build.

- [ ] **Step 3: Run the non-publishing release preflight**

Run:

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref <branch> \
  -f version=1.3.0 \
  -f build=12 \
  -f publish=false

gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

Expected: the workflow passes without publishing. This plan changes `@MainActor` rendering state, so this step is mandatory; record the run ID in the commit message or the PR body. If the run fails, append the run ID, failed stage, root cause and fix to `docs/swift-ci-compatibility.md`.

- [ ] **Step 4: Confirm the Dock icon path is untouched**

Run: `git diff --stat main -- Sources/StatusTrioCore/UI/Icon/DockIconRenderCache.swift Sources/StatusTrioCore/UI/Icon/DockIconRenderer.swift Sources/StatusTrioCore/App/AppIconController.swift`
Expected: no output — this plan changes the menu bar key only, and the parity test is what keeps the Dock honest.

- [ ] **Step 5: Review the diff**

Run: `git diff --check; git status --short`
Expected: no whitespace errors, and only `StatusBarRenderCache.swift`, `StatusBarController.swift`, the two release-note files, and `StatusBarRenderCacheTests.swift` modified.

## Verification

- `swift test` passes with the new tests: `testSubBucketSignalNoiseDoesNotInvalidateTheMenuBarImage`, `testMenuBarAndDockKeysReactToTheSameChanges`, `testStatesThatShareOneRenderKeyDrawIdenticalPixels`, `testStatesWithDifferentRenderKeysDrawDifferentPixels`, `testArcVolumeKeepsTheContinuousScalarInTheKey`, `testAccessibilityTextUpdatesWhenOnlyTheVoiceOverValueChanges`.
- No existing test is weakened: `StatusBarRenderCacheTests`' five original tests, `IconAppearancePublisherTests` (every icon setting must still invalidate the menu bar key), `WiFiSummaryTests` (band-only changes must still compare equal), `DockIconRenderCacheTests` and `Issue13IconParityTests` all keep their assertions.
- `swift build -c release` passes.
- The initializer signature of `StatusBarRenderKey` is unchanged, so the two other test files that build one still compile without edits.
- A non-publishing release preflight passes on the CI toolchain.
- `bash scripts/validate-appcast-notes.sh` passes after the release-note edits.

## Out of Scope

- **Extracting a shared quantization type** (for example an `IconRenderInputs` embedded by both keys). The existing `StatusMappings` helpers are reused as they are: they are the single source of the bar/step/threshold arithmetic already, `DockIconImageCache` is keyed by `DockIconRenderKey` and is owned by `2026-09-20-icon-preview-rendering.md` (R-04), and the parity test fails the moment the two field lists disagree. Extract the shared type in a follow-up if a third consumer appears, not here.
- **Bucketing `volumeArcProgress`.** A pixel-sized bucket would have to be derived from the rendered size, and the menu bar icon renders between 16 and 36 pt while the Dock renders at 512 px, so one bucket size cannot serve both. Keeping the clamped scalar mirrors the Dock exactly and leaves no state whose arc is drawn differently under one key.
- **Adding an image cache keyed by `StatusBarRenderKey`** (the Dock's `DockIconImageCache` equivalent). The normalized key plus `IconRenderCoalescer` already remove the repeated redraw the finding reports; a bitmap cache would need the pixel length in its key, which is R-04's problem.
- **Keying on the icon's pixel size or display scale.** The status item redraws on `NSApplication.didChangeScreenParametersNotification` through `renderLatestSnapshot()`, and `StatusBarRenderKey` has no scale input today; adding one is a separate change.
- **Changing the `wifiBars` / `volumeSteps` thresholds.** Those are what the user sees; this plan only stops re-rendering when they do not move.
- **The Dock key's own pixel-size gap and the icon-parity enumeration tests** — `2026-09-20-icon-preview-rendering.md` (R-04) and `2026-09-20-icon-parity-and-lifecycle-tests.md` (R-19).

## File Ownership & Conflicts

- `Sources/StatusTrioCore/UI/StatusBarController.swift` is also owned by **`2026-09-20-toolchain-method-reference-compliance.md`** (R-18). The review index's §3.1 rule is explicit: **R-18 lands first** — it rewrites the handler arguments passed into `StatusPopoverView`. This plan then rebases and keeps its edits to `render(_:status:)` and the removal of the unused `accessibilityKey` property; it does not touch the handler arguments. Do not run the two in parallel.
- `Tests/StatusTrioCoreTests/StatusBarRenderCacheTests.swift` is owned by this plan alone. **`2026-09-20-icon-parity-and-lifecycle-tests.md`** (R-19) adds new test files plus edits to `DockIconRenderCacheTests.swift` and `Issue13IconParityTests.swift`; land this plan first (Wave 2 before Wave 3) so R-19's enumeration tests start from a normalized menu bar key and can reuse `testMenuBarAndDockKeysReactToTheSameChanges` rather than duplicating it.
- `Sources/StatusTrioCore/UI/Icon/DockIconRenderCache.swift` and `Sources/StatusTrioCore/UI/Icon/DockIconRenderer.swift` are owned by **`2026-09-20-icon-preview-rendering.md`** (R-04). This plan reads them but modifies neither, so the two can land in either order; if R-04 adds a pixel-size field to `DockIconRenderKey`, the parity test keeps compiling (it uses the labeled initializer with defaulted option parameters) and must stay green.
- `release-notes/1.3.0/en.md` and `release-notes/1.3.0/zh-Hans.md` are also touched by **`2026-09-20-status-poll-scheduling.md`** (R-03), **`2026-09-20-update-source-fallback-policy.md`** (R-09) and **`2026-09-20-single-instance-and-pasteboard.md`** (R-13). All four only append sections; resolve conflicts by keeping every section, then re-run `bash scripts/validate-appcast-notes.sh`.
- Recommended merge order: **R-18 (toolchain compliance) → R-07 (this plan) → R-19 (parity and lifecycle tests)**, with R-04 and the release-note-only plans landing whenever they are ready.
