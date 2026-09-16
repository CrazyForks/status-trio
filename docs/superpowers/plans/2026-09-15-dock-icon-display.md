# Status Trio Dock Icon Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a three-state Menu Bar/Dock placement preference and keep the Dock icon synchronized with the live Status Trio rendering.

**Architecture:** Persist placement as an enum so a hidden-everywhere state is unrepresentable. An injected activation-policy coordinator combines the persistent Dock choice with temporary Settings-window requests, while an `AppIconController` coordinates Menu Bar visibility and assigns a cached Dock-specific bitmap to `NSApplication.applicationIconImage`.

**Tech Stack:** Swift 6.1-compatible Swift, AppKit, SwiftUI, Combine, Core Graphics, UserDefaults, XCTest, Swift Testing

**Spec:** `docs/superpowers/specs/2026-09-15-dock-icon-display-design.md`

## Global Constraints

- Acceptance toolchain: GitHub Actions `macos-15`, Xcode 16.4, Swift 6.1.2.
- Deployment target remains macOS 15.0.
- Keep `LSUIElement=true`; Dock visibility changes at runtime with `NSApplication.ActivationPolicy`.
- Supported placements are exactly Menu Bar Only, Dock Only, and Both; Menu Bar Only is the default.
- Never hide the Menu Bar until AppKit has accepted the transition that makes the Dock available.
- Use `NSApplication.applicationIconImage`; do not introduce `NSDockTile.contentView`.
- The Dock icon uses a fixed 1024-pixel backing image and does not inherit the Menu Bar icon-size preference.
- Battery and connection icon options apply to both surfaces.
- Do not add dependencies or Swift 6.2-only syntax.
- Do not use `isolated deinit`, `weak let`, or actor-isolated methods as function values; use explicit closures.

## File Map

- Create `Sources/StatusTrioCore/Models/AppIconPlacement.swift`: valid placement states and visibility derivation.
- Modify `Sources/StatusTrioCore/Settings/SettingsStore.swift`: persisted placement source of truth.
- Modify `Sources/StatusTrioCore/App/AppActivationPolicy.swift`: injected persistent-plus-temporary policy coordinator.
- Create `Sources/StatusTrioCore/UI/Icon/DockIconRenderer.swift`: fixed-background Dock bitmap compositor.
- Create `Sources/StatusTrioCore/UI/Icon/DockIconRenderCache.swift`: duplicate render suppression.
- Create `Sources/StatusTrioCore/App/AppIconController.swift`: placement transitions and Dock subscriptions.
- Modify `Sources/StatusTrioCore/UI/StatusBarController.swift`: explicit visibility API and hidden-state render suppression.
- Modify `Sources/StatusTrioCore/App/AppEnvironment.swift`: construct and retain the new coordinators.
- Modify `Sources/StatusTrioCore/App/AppDelegate.swift`: remove the hard-coded policy and route Dock reopen to Settings.
- Modify `Sources/StatusTrioCore/UI/Settings/BasicsSettingsPane.swift`: three-way segmented placement picker.
- Modify `Sources/StatusTrioCore/Localization/LocalizationKey.swift`: placement localization keys.
- Modify all 12 `Sources/StatusTrioCore/Resources/*.lproj/Localizable.strings` files: translated placement copy.
- Create `Tests/StatusTrioCoreTests/AppIconPlacementTests.swift`: placement truth table.
- Modify `Tests/StatusTrioCoreTests/SettingsStoreTests.swift`: default, persistence, and invalid-value fallback.
- Create `Tests/StatusTrioCoreTests/AppActivationPolicyTests.swift`: persistent and temporary activation behavior.
- Create `Tests/StatusTrioCoreTests/DockIconRenderCacheTests.swift`: render-key equality and reset behavior.
- Create `Tests/StatusTrioCoreTests/DockIconRendererTests.swift`: bitmap layout and status colors.
- Create `Tests/StatusTrioCoreTests/AppIconControllerTests.swift`: transition ordering and disabled rendering.
- Create `Tests/StatusTrioCoreTests/TestSupport/PixelBuffer.swift`: shared raster assertions.
- Modify `Tests/StatusTrioCoreTests/StatusIconRendererTests.swift`: use the shared pixel helper.
- Modify `Tests/StatusTrioCoreTests/SettingsWindowControllerTests.swift`: inject the activation coordinator.
- Modify `Tests/StatusTrioCoreTests/LocalizationTests.swift`: compact placement labels.

---

### Task 1: Model And Persist The Three Valid Placements

**Files:**

- Create: `Sources/StatusTrioCore/Models/AppIconPlacement.swift`
- Modify: `Sources/StatusTrioCore/Settings/SettingsStore.swift`
- Create: `Tests/StatusTrioCoreTests/AppIconPlacementTests.swift`
- Modify: `Tests/StatusTrioCoreTests/SettingsStoreTests.swift`

**Interfaces:**

- Produces: `AppIconPlacement.menuBar`, `.dock`, and `.both`.
- Produces: `AppIconPlacement.showsMenuBarIcon` and `.showsDockIcon`.
- Produces: `SettingsStore.appIconPlacement` and `SettingsStore.appIconPlacementDefaultsKey`.
- Consumes: the existing injected `UserDefaults` pattern in `SettingsStore`.

- [ ] **Step 1: Add failing placement truth-table tests**

Create `AppIconPlacementTests.swift`:

```swift
import Testing
@testable import StatusTrioCore

struct AppIconPlacementTests {
    @Test(arguments: AppIconPlacement.allCases)
    func visibility(placement: AppIconPlacement) {
        switch placement {
        case .menuBar:
            #expect(placement.showsMenuBarIcon)
            #expect(placement.showsDockIcon == false)
        case .dock:
            #expect(placement.showsMenuBarIcon == false)
            #expect(placement.showsDockIcon)
        case .both:
            #expect(placement.showsMenuBarIcon)
            #expect(placement.showsDockIcon)
        }
    }

    @Test func exposesOnlyThreePlacements() {
        #expect(AppIconPlacement.allCases == [.menuBar, .dock, .both])
    }
}
```

- [ ] **Step 2: Add failing SettingsStore tests**

Add to `SettingsStoreTests`:

```swift
func testAppIconPlacementDefaultsToMenuBar() {
    let store = SettingsStore(defaults: makeSuite().defaults)

    XCTAssertEqual(store.appIconPlacement, .menuBar)
}

func testAppIconPlacementPersistsAcrossStoreInstances() {
    let suite = makeSuite()
    defer { clear(suite) }

    let first = SettingsStore(defaults: suite.defaults)
    first.appIconPlacement = .both

    XCTAssertEqual(SettingsStore(defaults: suite.defaults).appIconPlacement, .both)
}

func testUnknownAppIconPlacementFallsBackToMenuBar() {
    let suite = makeSuite()
    defer { clear(suite) }
    suite.defaults.set("neither", forKey: SettingsStore.appIconPlacementDefaultsKey)

    XCTAssertEqual(SettingsStore(defaults: suite.defaults).appIconPlacement, .menuBar)
}
```

- [ ] **Step 3: Run the focused tests and verify RED**

Run:

```bash
swift test --filter AppIconPlacementTests
swift test --filter SettingsStoreTests
```

Expected: compilation fails because `AppIconPlacement` and `appIconPlacement` do not exist.

- [ ] **Step 4: Add the placement model**

Create `AppIconPlacement.swift`:

```swift
import Foundation

enum AppIconPlacement: String, CaseIterable, Identifiable, Sendable {
    case menuBar
    case dock
    case both

    var id: Self { self }

    var showsMenuBarIcon: Bool {
        self != .dock
    }

    var showsDockIcon: Bool {
        self != .menuBar
    }
}
```

- [ ] **Step 5: Persist placement in SettingsStore**

Add the key and published property near the other app-wide settings:

```swift
static let appIconPlacementDefaultsKey = "appIconPlacement"

@Published var appIconPlacement: AppIconPlacement {
    didSet {
        defaults.set(appIconPlacement.rawValue, forKey: Self.appIconPlacementDefaultsKey)
    }
}
```

Initialize it before the other stored settings:

```swift
let storedAppIconPlacement = defaults.string(forKey: Self.appIconPlacementDefaultsKey)
self.appIconPlacement = storedAppIconPlacement
    .flatMap(AppIconPlacement.init(rawValue:))
    ?? .menuBar
```

- [ ] **Step 6: Run the focused tests and verify GREEN**

Run:

```bash
swift test --filter AppIconPlacementTests
swift test --filter SettingsStoreTests
```

Expected: both suites pass.

- [ ] **Step 7: Commit the placement model**

```bash
git add Sources/StatusTrioCore/Models/AppIconPlacement.swift Sources/StatusTrioCore/Settings/SettingsStore.swift Tests/StatusTrioCoreTests/AppIconPlacementTests.swift Tests/StatusTrioCoreTests/SettingsStoreTests.swift
git commit -m "feat: persist app icon placement"
```

---

### Task 2: Make Activation Policy Combine Dock Preference And Window Ownership

**Files:**

- Modify: `Sources/StatusTrioCore/App/AppActivationPolicy.swift`
- Modify: `Sources/StatusTrioCore/UI/Settings/SettingsWindowController.swift`
- Create: `Tests/StatusTrioCoreTests/AppActivationPolicyTests.swift`
- Modify: `Tests/StatusTrioCoreTests/SettingsWindowControllerTests.swift`

**Interfaces:**

- Produces: `ApplicationActivationPolicyApplying.setActivationPolicy(_:)`.
- Produces: `AppActivationPolicy.setDockIconVisible(_:) -> Bool`.
- Produces: `AppActivationPolicy.enterTemporaryRegularMode()` and `.leaveTemporaryRegularMode()`.
- Consumes: `AppIconPlacement.showsDockIcon` in Task 4.

- [ ] **Step 1: Add failing activation-policy tests**

Create `AppActivationPolicyTests.swift`:

```swift
import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct AppActivationPolicyTests {
    @Test func persistentDockVisibilityKeepsRegularPolicy() {
        let application = ActivationPolicyApplicationSpy()
        let policy = AppActivationPolicy(application: application)

        #expect(policy.setDockIconVisible(true))
        policy.enterTemporaryRegularMode()
        #expect(policy.setDockIconVisible(false))
        policy.leaveTemporaryRegularMode()

        #expect(application.policies == [.regular, .regular, .regular, .accessory])
    }

    @Test func nestedTemporaryRequestsLeaveOnlyAfterFinalOwner() {
        let application = ActivationPolicyApplicationSpy()
        let policy = AppActivationPolicy(application: application)

        policy.enterTemporaryRegularMode()
        policy.enterTemporaryRegularMode()
        policy.leaveTemporaryRegularMode()
        policy.leaveTemporaryRegularMode()
        policy.leaveTemporaryRegularMode()

        #expect(application.policies == [.regular, .regular, .regular, .accessory, .accessory])
    }

    @Test func reportsRejectedPolicyChanges() {
        let application = ActivationPolicyApplicationSpy(result: false)
        let policy = AppActivationPolicy(application: application)

        #expect(policy.setDockIconVisible(true) == false)
        #expect(application.policies == [.regular])
    }
}

@MainActor
private final class ActivationPolicyApplicationSpy: ApplicationActivationPolicyApplying {
    private let result: Bool
    private(set) var policies: [NSApplication.ActivationPolicy] = []

    init(result: Bool = true) {
        self.result = result
    }

    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        policies.append(activationPolicy)
        return result
    }
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter AppActivationPolicyTests
```

Expected: compilation fails because the injected protocol and instance API do not exist.

- [ ] **Step 3: Replace static activation state with an injected instance**

Implement `AppActivationPolicy.swift` with this public shape and state transition:

```swift
import AppKit

@MainActor
protocol ApplicationActivationPolicyApplying: AnyObject {
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool
}

extension NSApplication: ApplicationActivationPolicyApplying {}

@MainActor
final class AppActivationPolicy {
    private let application: any ApplicationActivationPolicyApplying
    private var keepsDockIconVisible = false
    private var temporaryRegularRequestCount = 0

    init(application: any ApplicationActivationPolicyApplying = NSApplication.shared) {
        self.application = application
    }

    @discardableResult
    func setDockIconVisible(_ isVisible: Bool) -> Bool {
        keepsDockIconVisible = isVisible
        return apply()
    }

    func enterTemporaryRegularMode() {
        temporaryRegularRequestCount += 1
        _ = apply()
    }

    func leaveTemporaryRegularMode() {
        temporaryRegularRequestCount = max(0, temporaryRegularRequestCount - 1)
        _ = apply()
    }

    @discardableResult
    private func apply() -> Bool {
        let policy: NSApplication.ActivationPolicy = keepsDockIconVisible
            || temporaryRegularRequestCount > 0
            ? .regular
            : .accessory
        return application.setActivationPolicy(policy)
    }
}
```

- [ ] **Step 4: Inject the policy into SettingsWindowController**

Add an `AppActivationPolicy` initializer argument and replace the static calls:

```swift
private let activationPolicy: AppActivationPolicy

init(
    store: SettingsStore,
    statusStore: SystemStatusStore,
    localization: Localization,
    activationPolicy: AppActivationPolicy
) {
    self.store = store
    self.statusStore = statusStore
    self.localization = localization
    self.activationPolicy = activationPolicy
    super.init(window: nil)
}
```

Use `activationPolicy.enterTemporaryRegularMode()` in `enterActivationPolicyIfNeeded()` and `activationPolicy.leaveTemporaryRegularMode()` in `leaveActivationPolicyIfNeeded()`. Keep the existing `ownsActivationPolicy` guard so duplicate `show()` calls do not increment the count.

- [ ] **Step 5: Update SettingsWindowController tests**

For each test, create the controller with an isolated spy-backed policy:

```swift
let activationApplication = SettingsActivationPolicyApplicationSpy()
let activationPolicy = AppActivationPolicy(application: activationApplication)
let controller = SettingsWindowController(
    store: SettingsStore(defaults: defaults),
    statusStore: makeStatusStore(),
    localization: localization,
    activationPolicy: activationPolicy
)
```

Add a file-private spy with the same recording behavior as the Task 2 activation tests and assert one `.regular` request on first `show()`, no additional request on repeated `show()`, and `.accessory` after close.

- [ ] **Step 6: Run activation and Settings-window tests**

Run:

```bash
swift test --filter AppActivationPolicyTests
swift test --filter SettingsWindowControllerTests
```

Expected: both suites pass.

- [ ] **Step 7: Commit the activation-policy refactor**

```bash
git add Sources/StatusTrioCore/App/AppActivationPolicy.swift Sources/StatusTrioCore/UI/Settings/SettingsWindowController.swift Tests/StatusTrioCoreTests/AppActivationPolicyTests.swift Tests/StatusTrioCoreTests/SettingsWindowControllerTests.swift
git commit -m "refactor: coordinate persistent dock activation"
```

---

### Task 3: Render A Native-Shaped Dynamic Dock Icon

**Files:**

- Create: `Sources/StatusTrioCore/UI/Icon/DockIconRenderer.swift`
- Create: `Sources/StatusTrioCore/UI/Icon/DockIconRenderCache.swift`
- Create: `Tests/StatusTrioCoreTests/DockIconRendererTests.swift`
- Create: `Tests/StatusTrioCoreTests/DockIconRenderCacheTests.swift`
- Create: `Tests/StatusTrioCoreTests/TestSupport/PixelBuffer.swift`
- Modify: `Tests/StatusTrioCoreTests/StatusIconRendererTests.swift`

**Interfaces:**

- Produces: `DockIconRenderer.image(status:options:connectionOptions:) -> NSImage?`.
- Produces: `DockIconRenderKey` and `DockIconRenderCache.shouldRender(_:)`/`.reset()`.
- Consumes: `StatusIconRenderer.render(menuBarStatus:size:scale:foreground:options:connectionOptions:)`.

- [ ] **Step 1: Move PixelBuffer into shared test support**

Move the existing file-private `PixelBuffer` from the bottom of `StatusIconRendererTests.swift` into `Tests/StatusTrioCoreTests/TestSupport/PixelBuffer.swift`. Keep its existing raster methods and add:

```swift
func rgba(x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
    let index = (y * width + x) * 4
    return (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3])
}
```

Make the type and the methods internal to the test target. Do not change existing StatusIconRenderer assertions.

- [ ] **Step 2: Add failing Dock renderer tests**

Create `DockIconRendererTests.swift` using XCTest because it shares the existing XCTest pixel helper:

```swift
import AppKit
import XCTest
@testable import StatusTrioCore

final class DockIconRendererTests: XCTestCase {
    func testDockIconHasExpectedLogicalAndPixelSize() throws {
        let image = try XCTUnwrap(DockIconRenderer.image(status: .placeholder))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))

        XCTAssertEqual(image.size, NSSize(width: 512, height: 512))
        XCTAssertEqual(bitmap.pixelsWide, 1024)
        XCTAssertEqual(bitmap.pixelsHigh, 1024)
    }

    func testDockIconKeepsTransparentMarginAndDarkBody() throws {
        let pixels = try pixels(for: .placeholder)
        let corner = pixels.rgba(x: 0, y: 0)
        let center = pixels.rgba(x: 512, y: 512)

        XCTAssertEqual(corner.alpha, 0)
        XCTAssertGreaterThan(center.alpha, 250)
        XCTAssertEqual(Int(center.red), 21, accuracy: 3)
        XCTAssertEqual(Int(center.green), 21, accuracy: 3)
        XCTAssertEqual(Int(center.blue), 23, accuracy: 3)
    }

    func testChargingStatusPreservesGreenAccent() throws {
        let status = MenuBarStatus(snapshot: StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: 50,
                isPresent: true,
                isCharging: true,
                isLowPowerMode: false,
                isConnectedToPower: true
            ),
            wifi: .placeholder,
            volume: .placeholder
        ))
        let pixels = try pixels(for: status)

        XCTAssertTrue(pixels.containsColor(
            red: 52.0 / 255.0,
            green: 199.0 / 255.0,
            blue: 89.0 / 255.0,
            tolerance: 0.08,
            minimumAlpha: 0.9
        ))
    }

    private func pixels(for status: MenuBarStatus) throws -> PixelBuffer {
        let image = try XCTUnwrap(DockIconRenderer.image(status: status))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        return try PixelBuffer(image: try XCTUnwrap(bitmap.cgImage))
    }
}
```

- [ ] **Step 3: Add failing render-cache tests**

Create `DockIconRenderCacheTests.swift`:

```swift
import Testing
@testable import StatusTrioCore

struct DockIconRenderCacheTests {
    @Test func skipsEqualKeysAndRendersAfterReset() {
        var cache = DockIconRenderCache()
        let key = DockIconRenderKey(
            status: .placeholder,
            options: .standard,
            connectionOptions: .standard
        )

        #expect(cache.shouldRender(key))
        #expect(cache.shouldRender(key) == false)
        cache.reset()
        #expect(cache.shouldRender(key))
    }
}
```

- [ ] **Step 4: Run focused tests and verify RED**

Run:

```bash
swift test --filter DockIconRendererTests
swift test --filter DockIconRenderCacheTests
swift test --filter StatusIconRendererTests
```

Expected: Dock suites fail to compile; existing renderer tests still pass after the helper move.

- [ ] **Step 5: Implement the Dock render cache**

Create `DockIconRenderCache.swift`:

```swift
struct DockIconRenderKey: Equatable {
    let status: MenuBarStatus
    let options: BatteryIconOptions
    let connectionOptions: ConnectionIconOptions
}

struct DockIconRenderCache {
    private(set) var lastKey: DockIconRenderKey?

    mutating func shouldRender(_ key: DockIconRenderKey) -> Bool {
        guard key != lastKey else { return false }
        lastKey = key
        return true
    }

    mutating func reset() {
        lastKey = nil
    }
}
```

- [ ] **Step 6: Implement the Dock bitmap compositor**

Create `DockIconRenderer.swift`. Use the exact geometry and colors from `Support/AppIcon.svg`:

```swift
import AppKit
import CoreGraphics

enum DockIconRenderer {
    static let logicalSize: CGFloat = 512
    static let pixelSize = 1024

    static func image(
        status: MenuBarStatus,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard
    ) -> NSImage? {
        guard let glyph = StatusIconRenderer.render(
            menuBarStatus: status,
            size: 672,
            scale: 1,
            foreground: CGColor(gray: 1, alpha: 1),
            options: options,
            connectionOptions: connectionOptions
        ), let context = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: pixelSize * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let body = CGRect(x: 64, y: 64, width: 896, height: 896)
        context.addPath(CGPath(
            roundedRect: body,
            cornerWidth: 210,
            cornerHeight: 210,
            transform: nil
        ))
        context.setFillColor(CGColor(
            red: 21.0 / 255.0,
            green: 21.0 / 255.0,
            blue: 23.0 / 255.0,
            alpha: 1
        ))
        context.fillPath()

        let border = CGRect(x: 65, y: 65, width: 894, height: 894)
        context.addPath(CGPath(
            roundedRect: border,
            cornerWidth: 209,
            cornerHeight: 209,
            transform: nil
        ))
        context.setStrokeColor(CGColor(
            red: 58.0 / 255.0,
            green: 58.0 / 255.0,
            blue: 61.0 / 255.0,
            alpha: 1
        ))
        context.setLineWidth(2)
        context.strokePath()

        context.draw(glyph, in: CGRect(x: 194.8, y: 171.84, width: 672, height: 672))

        guard let output = context.makeImage() else { return nil }
        let representation = NSBitmapImageRep(cgImage: output)
        representation.size = NSSize(width: logicalSize, height: logicalSize)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        image.isTemplate = false
        return image
    }
}
```

If visual verification shows the glyph vertically mirrored, correct only the glyph draw transform with a local save/translate/scale/restore block; keep the tested status geometry unchanged.

- [ ] **Step 7: Run all icon tests and inspect one rendered fixture**

Run:

```bash
swift test --filter DockIconRendererTests
swift test --filter DockIconRenderCacheTests
swift test --filter StatusIconRendererTests
```

Expected: all three suites pass. Add a temporary test attachment or Quick Look the generated `NSImage` during implementation, then remove any generated fixture before committing.

- [ ] **Step 8: Commit Dock rendering**

```bash
git add Sources/StatusTrioCore/UI/Icon/DockIconRenderer.swift Sources/StatusTrioCore/UI/Icon/DockIconRenderCache.swift Tests/StatusTrioCoreTests/DockIconRendererTests.swift Tests/StatusTrioCoreTests/DockIconRenderCacheTests.swift Tests/StatusTrioCoreTests/TestSupport/PixelBuffer.swift Tests/StatusTrioCoreTests/StatusIconRendererTests.swift
git commit -m "feat: render live dock icon"
```

---

### Task 4: Coordinate Safe Surface Transitions And Live Dock Updates

**Files:**

- Create: `Sources/StatusTrioCore/App/AppIconController.swift`
- Modify: `Sources/StatusTrioCore/UI/StatusBarController.swift`
- Create: `Tests/StatusTrioCoreTests/AppIconControllerTests.swift`

**Interfaces:**

- Produces: `ApplicationDockIconApplying.applicationIconImage`.
- Produces: `AppIconController.start()` and `.stop()`.
- Produces: `StatusBarController.setVisible(_:)`.
- Consumes: `SettingsStore.appIconPlacement`, `AppActivationPolicy`, `DockIconRenderer`, and `DockIconRenderCache`.

- [ ] **Step 1: Add failing transition-order tests**

Create `AppIconControllerTests.swift` with an application spy conforming to both AppKit adapter protocols and an explicit menu-visibility closure. Cover these behaviors:

```swift
import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct AppIconControllerTests {
    @Test func dockOnlyActivatesAndRendersBeforeHidingMenuBar() {
        let harness = AppIconControllerHarness()
        harness.controller.start()
        harness.events.removeAll()

        harness.settings.appIconPlacement = .dock

        #expect(harness.events == ["policy:regular", "dock:image", "menu:false"])
    }

    @Test func rejectedDockActivationKeepsMenuBarVisible() {
        let harness = AppIconControllerHarness(acceptsActivationPolicy: false)
        harness.controller.start()
        harness.events.removeAll()

        harness.settings.appIconPlacement = .dock

        #expect(harness.events == ["policy:regular", "menu:true"])
    }

    @Test func menuBarOnlyRestoresMenuBeforeRemovingDock() {
        let harness = AppIconControllerHarness(initialPlacement: .dock)
        harness.controller.start()
        harness.events.removeAll()

        harness.settings.appIconPlacement = .menuBar

        #expect(harness.events == ["menu:true", "dock:nil", "policy:accessory"])
    }

    @Test func hiddenDockDoesNotRenderStatusChanges() {
        let harness = AppIconControllerHarness(initialPlacement: .menuBar)
        harness.controller.start()
        harness.renderCallCount = 0

        harness.publishDifferentSnapshot()

        #expect(harness.renderCallCount == 0)
    }
}
```

Implement `AppIconControllerHarness` in the same test file with isolated `UserDefaults`, no-op monitors matching existing test fakes, an event-recording application adapter, and this injected renderer closure:

```swift
renderDockIcon: { [weak harnessState] _, _, _ in
    harnessState?.renderCallCount += 1
    harnessState?.events.append("dock:image")
    return NSImage(size: NSSize(width: 512, height: 512))
}
```

Use a small reference-type `HarnessState` so the closure does not capture an incompletely initialized harness.

- [ ] **Step 2: Run the controller tests and verify RED**

Run:

```bash
swift test --filter AppIconControllerTests
```

Expected: compilation fails because `AppIconController` and the Dock adapter protocol do not exist.

- [ ] **Step 3: Add explicit status-item visibility control**

In `StatusBarController`, add state and an API:

```swift
private var isStatusItemVisible: Bool

func setVisible(_ isVisible: Bool) {
    guard isStatusItemVisible != isVisible else { return }
    isStatusItemVisible = isVisible

    if isVisible {
        statusItem.isVisible = true
        renderCache = StatusBarRenderCache()
        renderLatestSnapshot()
    } else {
        popover.performClose(nil)
        store.setPopoverVisible(false)
        statusItem.isVisible = false
    }
}
```

Add `isVisible: Bool = true` to the initializer, initialize both `isStatusItemVisible` and `statusItem.isVisible`, and guard the private `render(...)` method with `guard isStatusItemVisible else { return }` before building a render key. This avoids a Menu Bar flash on a persisted Dock Only launch and avoids hidden Menu Bar rendering.

- [ ] **Step 4: Implement AppIconController adapters and lifecycle**

Start `AppIconController.swift` with:

```swift
import AppKit
import Combine

@MainActor
protocol ApplicationDockIconApplying: AnyObject {
    var applicationIconImage: NSImage? { get set }
}

extension NSApplication: ApplicationDockIconApplying {}

@MainActor
final class AppIconController {
    typealias DockRenderer = (
        MenuBarStatus,
        BatteryIconOptions,
        ConnectionIconOptions
    ) -> NSImage?

    static let snapshotDebounceInterval: TimeInterval = 0.5

    private let store: SystemStatusStore
    private let settings: SettingsStore
    private let activationPolicy: AppActivationPolicy
    private let application: any ApplicationDockIconApplying
    private let setMenuBarVisible: (Bool) -> Void
    private let renderDockIcon: DockRenderer
    private var cancellables: Set<AnyCancellable> = []
    private var renderCache = DockIconRenderCache()
    private var hasRenderedDockIcon = false
    private var currentPlacement: AppIconPlacement
    private var currentBatteryOptions: BatteryIconOptions
    private var currentConnectionOptions: ConnectionIconOptions
    private var isStarted = false

    init(
        store: SystemStatusStore,
        settings: SettingsStore,
        activationPolicy: AppActivationPolicy,
        application: any ApplicationDockIconApplying = NSApplication.shared,
        setMenuBarVisible: @escaping (Bool) -> Void,
        renderDockIcon: @escaping DockRenderer
    ) {
        self.store = store
        self.settings = settings
        self.activationPolicy = activationPolicy
        self.application = application
        self.setMenuBarVisible = setMenuBarVisible
        self.renderDockIcon = renderDockIcon
        self.currentPlacement = settings.appIconPlacement
        self.currentBatteryOptions = settings.batteryIconOptions
        self.currentConnectionOptions = settings.connectionIconOptions
    }
}
```

`start()` must be idempotent and subscribe to:

- `settings.$appIconPlacement.removeDuplicates()` synchronously.
- `store.$snapshot.removeDuplicates().dropFirst().debounce(for: .seconds(0.5), scheduler: RunLoop.main)`.
- The same five battery option publishers and four connection option publishers currently used by `StatusBarController`.

`@Published` sends its new value before the backing property is updated. Each placement/options sink must therefore use the values delivered by the publisher: assign `currentPlacement`, `currentBatteryOptions`, or `currentConnectionOptions` first, then render. Do not synchronously read the just-published property back from `SettingsStore`.

Use explicit closures when passing `DockIconRenderer.image` from production wiring. Do not pass the actor-isolated method directly as a function value.

- [ ] **Step 5: Implement safe placement ordering**

Implement the placement branch with this order:

```swift
private func apply(_ placement: AppIconPlacement) {
    currentPlacement = placement
    if placement.showsDockIcon {
        guard activationPolicy.setDockIconVisible(true) else {
            setMenuBarVisible(true)
            return
        }
        renderLatestDockIcon()
        setMenuBarVisible(placement.showsMenuBarIcon)
    } else {
        setMenuBarVisible(true)
        application.applicationIconImage = nil
        hasRenderedDockIcon = false
        renderCache.reset()
        _ = activationPolicy.setDockIconVisible(false)
    }
}
```

`renderLatestDockIcon()` returns immediately unless `currentPlacement.showsDockIcon`. Build `DockIconRenderKey` from `MenuBarStatus(snapshot: store.snapshot)`, `currentBatteryOptions`, and `currentConnectionOptions`; update the cache before assigning the image. Preserve the last valid image on later render failure, and set `applicationIconImage=nil` only when the first dynamic render fails.

`stop()` cancels the subscriptions, resets `applicationIconImage=nil`, resets the cache, and is idempotent. Do not perform AppKit cleanup from `deinit`.

- [ ] **Step 6: Run transition and render-cache tests**

Run:

```bash
swift test --filter AppIconControllerTests
swift test --filter DockIconRenderCacheTests
swift test --filter StatusMenuBuilderTests
```

Expected: all suites pass, including the existing 0.5-second debounce constant assertion.

- [ ] **Step 7: Commit presentation coordination**

```bash
git add Sources/StatusTrioCore/App/AppIconController.swift Sources/StatusTrioCore/UI/StatusBarController.swift Tests/StatusTrioCoreTests/AppIconControllerTests.swift
git commit -m "feat: coordinate menu bar and dock icons"
```

---

### Task 5: Add The Three-Way Settings Control And Localizations

**Files:**

- Modify: `Sources/StatusTrioCore/UI/Settings/BasicsSettingsPane.swift`
- Modify: `Sources/StatusTrioCore/Localization/LocalizationKey.swift`
- Modify: `Sources/StatusTrioCore/Resources/ar.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/Resources/de.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/Resources/es.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/Resources/fr.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/Resources/it.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/Resources/ja.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/Resources/ko.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/Resources/pt-BR.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/Resources/ru.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/Resources/zh-Hant.lproj/Localizable.strings`
- Modify: `Tests/StatusTrioCoreTests/LocalizationTests.swift`

**Interfaces:**

- Produces: `LocalizationKey.settingsAppIconPlacement`, `.settingsAppIconPlacementDescription`, `.settingsAppIconPlacementMenuBar`, `.settingsAppIconPlacementDock`, and `.settingsAppIconPlacementBoth`.
- Consumes: `$store.appIconPlacement` and `AppIconPlacement.allCases`.

- [ ] **Step 1: Add localization keys and verify the completeness test fails**

Add:

```swift
case settingsAppIconPlacement = "settings.appIconPlacement"
case settingsAppIconPlacementDescription = "settings.appIconPlacement.description"
case settingsAppIconPlacementMenuBar = "settings.appIconPlacement.menuBar"
case settingsAppIconPlacementDock = "settings.appIconPlacement.dock"
case settingsAppIconPlacementBoth = "settings.appIconPlacement.both"
```

Run:

```bash
swift test --filter LocalizationTests/testEveryLanguageHasEveryNonEmptyKey
```

Expected: failure listing the five missing keys for every supported language.

- [ ] **Step 2: Add the exact localized strings**

Use this copy table:

| Locale | Row title | Description | Menu Bar | Dock | Both |
| --- | --- | --- | --- | --- | --- |
| `en` | Show Status Trio In | Choose where the live status icon remains available. | Menu Bar | Dock | Both |
| `zh-Hans` | Status Trio 显示位置 | 选择实时状态图标保留在菜单栏、程序坞或两处。 | 菜单栏 | 程序坞 | 两处 |
| `zh-Hant` | Status Trio 顯示位置 | 選擇即時狀態圖示保留在選單列、Dock 或兩處。 | 選單列 | Dock | 兩處 |
| `ja` | Status Trio の表示場所 | ライブステータスアイコンを表示する場所を選択します。 | メニューバー | Dock | 両方 |
| `ko` | Status Trio 표시 위치 | 실시간 상태 아이콘을 표시할 위치를 선택합니다. | 메뉴 막대 | Dock | 둘 다 |
| `de` | Status Trio anzeigen in | Wähle, wo das Live-Statussymbol verfügbar bleibt. | Menüleiste | Dock | Beide |
| `fr` | Afficher Status Trio dans | Choisissez où conserver l’icône d’état dynamique. | Barre des menus | Dock | Les deux |
| `es` | Mostrar Status Trio en | Elige dónde mantener disponible el icono de estado dinámico. | Barra de menús | Dock | Ambos |
| `it` | Mostra Status Trio in | Scegli dove mantenere disponibile l’icona di stato dinamica. | Barra dei menu | Dock | Entrambi |
| `pt-BR` | Mostrar Status Trio em | Escolha onde manter disponível o ícone de status dinâmico. | Barra de menus | Dock | Ambos |
| `ru` | Показывать Status Trio в | Выберите, где должен отображаться динамический значок состояния. | Строка меню | Dock | В обоих местах |
| `ar` | إظهار Status Trio في | اختر مكان بقاء أيقونة الحالة المباشرة متاحة. | شريط القوائم | Dock | كلاهما |

For each locale, map the five columns to the five keys in the same order. Preserve each `.strings` file's current encoding and punctuation style.

- [ ] **Step 3: Add the segmented placement picker**

In `BasicsSettingsPane`, insert this section immediately after Launch at Login and before Language:

```swift
private var appIconPlacementSection: some View {
    PreferenceRow(
        label: .settingsAppIconPlacement,
        description: .settingsAppIconPlacementDescription
    ) {
        Picker(
            localization.string(.settingsAppIconPlacement),
            selection: $store.appIconPlacement
        ) {
            Text(localization.string(.settingsAppIconPlacementMenuBar))
                .tag(AppIconPlacement.menuBar)
            Text(localization.string(.settingsAppIconPlacementDock))
                .tag(AppIconPlacement.dock)
            Text(localization.string(.settingsAppIconPlacementBoth))
                .tag(AppIconPlacement.both)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }
}
```

Place a `Divider()` before and after the section. Keep it full width within the 450-point Settings content area so translated labels do not overlap.

- [ ] **Step 4: Add compact-copy assertions**

Extend `LocalizationTests` with a loop that resolves the three option strings for every `AppLanguage` and asserts each value is nonempty and no longer than 24 characters. This protects the fixed three-segment layout without snapshot-testing SwiftUI internals.

- [ ] **Step 5: Run localization and Settings tests**

Run:

```bash
swift test --filter LocalizationTests
swift test --filter SettingsStoreTests
swift test --filter SettingsWindowControllerTests
```

Expected: all suites pass for all 12 languages.

- [ ] **Step 6: Commit the settings UI and copy**

```bash
git add Sources/StatusTrioCore/UI/Settings/BasicsSettingsPane.swift Sources/StatusTrioCore/Localization/LocalizationKey.swift Sources/StatusTrioCore/Resources Tests/StatusTrioCoreTests/LocalizationTests.swift
git commit -m "ui: choose menu bar or dock placement"
```

---

### Task 6: Wire Lifecycle, Dock Reopen, And Shutdown Cleanup

**Files:**

- Modify: `Sources/StatusTrioCore/App/AppEnvironment.swift`
- Modify: `Sources/StatusTrioCore/App/AppDelegate.swift`
- Modify: `Tests/StatusTrioCoreTests/SettingsWindowControllerTests.swift`

**Interfaces:**

- Produces: retained `AppEnvironment.activationPolicy` and `AppEnvironment.appIconController`.
- Produces: `AppEnvironment.start()` and `.stop()` lifecycle boundaries.
- Consumes: all controllers from Tasks 2-4.

- [ ] **Step 1: Add a failing lifecycle assertion**

Extend `SettingsWindowControllerTests` to initialize a Dock-visible policy, open and close Settings, and assert the last recorded policy remains `.regular`:

```swift
func testClosingSettingsKeepsUserSelectedDockPolicyRegular() throws {
    let suiteName = "StatusTrioCoreTests.SettingsDockPolicy.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let application = SettingsActivationPolicyApplicationSpy()
    let policy = AppActivationPolicy(application: application)
    XCTAssertTrue(policy.setDockIconVisible(true))
    let controller = SettingsWindowController(
        store: SettingsStore(defaults: defaults),
        statusStore: makeStatusStore(),
        localization: Localization(defaults: defaults, preferredLanguages: ["en"]),
        activationPolicy: policy
    )

    controller.show()
    try XCTUnwrap(controller.window).close()

    XCTAssertEqual(application.policies.last, .regular)
}
```

- [ ] **Step 2: Run the lifecycle test**

Run:

```bash
swift test --filter SettingsWindowControllerTests/testClosingSettingsKeepsUserSelectedDockPolicyRegular
```

Expected: PASS after Task 2. This is a regression guard before changing the app bootstrap.

- [ ] **Step 3: Wire AppEnvironment in dependency order**

Add retained properties for the activation and icon controllers. In `live()` construct in this order:

1. `SettingsStore` and `SystemStatusStore`.
2. `Localization`.
3. One `AppActivationPolicy`.
4. `SettingsWindowController` with that policy.
5. `StatusBarController` with `isVisible: settings.appIconPlacement.showsMenuBarIcon`.
6. `AppIconController` using the same policy and this explicit renderer closure:

```swift
renderDockIcon: { status, options, connectionOptions in
    DockIconRenderer.image(
        status: status,
        options: options,
        connectionOptions: connectionOptions
    )
}
```

Use this explicit Menu Bar closure:

```swift
setMenuBarVisible: { isVisible in
    statusBarController.setVisible(isVisible)
}
```

Add lifecycle methods:

```swift
func start() {
    appIconController.start()
    store.start()
}

func stop() {
    appIconController.stop()
    store.stop()
}
```

- [ ] **Step 4: Update AppDelegate lifecycle and Dock reopen behavior**

Remove the unconditional `NSApplication.shared.setActivationPolicy(.accessory)`. Start the environment as one retained unit:

```swift
let environment = AppEnvironment.live()
self.environment = environment
updaterManager.start()
environment.start()
```

Add:

```swift
public func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
) -> Bool {
    environment?.settingsWindowController.show()
    return false
}
```

Change termination cleanup to `environment?.stop()`.

- [ ] **Step 5: Run the complete local suite and release build**

Run:

```bash
swift test
swift build -c release
```

Expected: all tests pass and the release executable builds with no new warnings.

- [ ] **Step 6: Manually exercise all placement transitions**

Build the app bundle with the repository's existing packaging command, launch it, and verify this matrix:

| Start | Change | Expected |
| --- | --- | --- |
| Menu Bar Only | Dock Only | Dock appears with live icon before Menu Bar disappears |
| Dock Only | Menu Bar Only | Menu Bar appears before Dock disappears |
| Menu Bar Only | Both | Both surfaces remain visible |
| Both | Dock Only | Dock remains; Menu Bar disappears |
| Both | Menu Bar Only | Menu Bar remains; Dock disappears |
| Dock Only | Open/close Settings | Dock remains visible |
| Menu Bar Only | Open/close Settings | temporary Dock icon uses static app icon, then disappears |
| Dock Only | click Dock icon | existing Settings window opens |
| Any mode | relaunch | the same placement is restored |

Change battery charge state, Wi-Fi/connection state, and volume. Confirm the Dock image updates after meaningful changes, shows status colors, and does not flicker on unchanged refreshes.

- [ ] **Step 7: Commit lifecycle integration**

```bash
git add Sources/StatusTrioCore/App/AppEnvironment.swift Sources/StatusTrioCore/App/AppDelegate.swift Tests/StatusTrioCoreTests/SettingsWindowControllerTests.swift
git commit -m "feat: integrate dock icon lifecycle"
```

---

### Task 7: Verify Swift 6.1 CI Compatibility

**Files:**

- Verify only; no source changes expected.

**Interfaces:**

- Consumes: the completed feature branch and `.github/workflows/release.yml`.
- Produces: passing local debug/release builds and a passing non-publishing release workflow.

- [ ] **Step 1: Confirm branch cleanliness and review the diff**

Run:

```bash
git status --short
git diff origin/main...HEAD --check
git diff origin/main...HEAD --stat
```

Expected: clean status, no whitespace errors, and only the files listed by this plan plus the design/plan documents.

- [ ] **Step 2: Run final local verification**

Run:

```bash
swift test
swift build -c release
```

Expected: 0 failures and a successful release build.

- [ ] **Step 3: Push the feature branch for CI preflight**

```bash
git push -u origin codex/dock-icon-display
```

Expected: the remote branch points to the verified local HEAD.

- [ ] **Step 4: Run the non-publishing release workflow**

The currently published appcast version is 1.0.4 build 5, so use the next explicit preflight values 1.0.5 build 6:

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref codex/dock-icon-display \
  -f version=1.0.5 \
  -f build=6 \
  -f publish=false

release_run_id="$(gh run list \
  --repo lingyired/status-trio \
  --workflow release.yml \
  --branch codex/dock-icon-display \
  --event workflow_dispatch \
  --limit 1 \
  --json databaseId \
  --jq '.[0].databaseId')"

gh run watch "$release_run_id" \
  --repo lingyired/status-trio \
  --exit-status
```

Expected: workflow succeeds with `publish=false`; tests, release build, app bundle creation, DMG creation, and ad-hoc signing all pass without publishing a GitHub Release or appcast entry.

- [ ] **Step 5: Inspect CI artifacts and logs**

Run:

```bash
gh run view "$release_run_id" \
  --repo lingyired/status-trio \
  --log-failed
```

Expected: no failed-step log output. Confirm the workflow summary reports test success, DMG creation, and publish steps skipped because `publish=false`.

- [ ] **Step 6: Record final implementation status**

Add no release commit. Report:

- local `swift test` result and test count;
- local `swift build -c release` result;
- non-publishing workflow run URL and result;
- manual results for all three placements;
- the existing limitation that builds are ad-hoc signed because the repository has no Developer ID or notarization secrets.

Do not create a release from this plan. Release planning is a separate user decision after the preflight passes.
