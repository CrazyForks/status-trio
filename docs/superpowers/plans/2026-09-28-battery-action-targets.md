# Battery Action Targets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the battery panel open macOS Battery Settings, installed AlDente or BatFi, any user-selected `.app`, or a custom URL while preserving Battery Settings as the default and final fallback.

**Architecture:** `SettingsStore` persists one explicit `BatteryActionTarget`. A small catalog describes verified known apps; a main-actor launcher owns all Launch Services and `NSWorkspace` calls behind an injectable interface. Settings and popup views consume target presentation and availability without launching apps themselves.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Foundation, SwiftPM, XCTest, UserDefaults.

**Spec:** `docs/superpowers/specs/2026-09-28-battery-action-targets-design.md`

## Global Constraints

- Minimum runtime macOS 15. Acceptance CI: `macos-26`, Xcode `26.6`, Swift `6.3.3`; keep Swift syntax compatible with that compiler. Build the app with macOS SDK 26 or newer and retain `scripts/build-app.sh` and `scripts/verify-platform-version.sh` guards.
- No extra permission, entitlement, private API, shell-based launching, background scan, or polling. Query installed apps on demand.
- Preserve `StatusBarController.batterySettingsURLs` and all Wi-Fi, Network, Bluetooth, and Sound routes.
- Preserve default behavior for missing or corrupt `batteryActionTarget.v1` data. One active target only; switching away discards a prior custom app or URL.
- Do not ship unverified legacy Bundle IDs or AlDente/BatFi deep links. Local `/Applications/AlDente.app` and `/Applications/BatFi.app` Info.plists verify `com.apphousekitchen.aldente-pro` and `software.micropixels.BatFi`.
- Add every new `LocalizationKey` to all 12 `Resources/*.lproj/Localizable.strings` files. Release notes for publication also cover all 12 languages.
- Before committing Swift changes run `swift test` and `swift build -c release`. Because this changes `@MainActor` and SwiftUI bindings, run a `publish=false` release workflow on the implementation branch before merging or publishing. Record every failed Actions run in `docs/swift-ci-compatibility.md`.

## File Map

- `Sources/StatusTrioCore/Battery/BatteryActionTarget.swift`: stable codable target and custom app identity.
- `Sources/StatusTrioCore/Battery/KnownBatteryApps.swift`: verified app catalog and lookup.
- `Sources/StatusTrioCore/Battery/BatteryActionLauncher.swift`: workspace adapter, on-demand detection, launch and fallback order.
- `Sources/StatusTrioCore/Battery/BatteryActionPresentation.swift`: localized, bounded popup label and selected option description.
- `Sources/StatusTrioCore/Settings/SettingsStore.swift`: persist target with existing defaults.
- `Sources/StatusTrioCore/UI/Settings/BatteryActionSettingsView.swift`: choice menu, app picker, URL field and unavailable message.
- `Sources/StatusTrioCore/UI/Settings/BatterySectionView.swift`: mount the new settings group below appearance settings.
- `Sources/StatusTrioCore/UI/{StatusBarController,StatusPopoverView,BatteryStatusView,BatteryDetailsView}.swift`: invoke the configured action and show its name.
- `Sources/StatusTrioCore/Localization/LocalizationKey.swift` and 12 `Resources/*.lproj/Localizable.strings`: text and accessibility labels.
- `Tests/StatusTrioCoreTests/{BatteryActionSettingsTests,KnownBatteryAppsTests,BatteryActionLauncherTests,BatteryActionPresentationTests}.swift`: pure behavior tests with isolated defaults and fake workspace.
- `Tests/StatusTrioCoreTests/{SettingsViewTests,BatteryDetailsLayoutTests,BatteryPopoverPanelTests}.swift`: settings and popup regressions.
- `docs/battery-actions.md` and the selected unreleased `release-notes/` version directory: user documentation and release copy.

## Review Focus

The spec implies these easily missed inputs; each has an explicit test below:

1. A primary Bundle ID and fallback path resolve to the same app: one failed launch must not launch that same URL twice (Task 4).
2. An app disappears after Launch Services resolves it but before launch finishes: the async error must reach the next fallback (Task 4).
3. A pasted URL has leading/trailing whitespace: trim it before URL parsing while preserving its internal content (Task 4).
4. A saved custom app has neither a usable Bundle ID nor an existing `.app` path: preserve its displayed name and use system fallback (Tasks 4 and 6).
5. A selected known app becomes unavailable while other known apps are absent: keep that selection visible with an unavailable status (Task 6).

---

### Task 1: Stable target model

**Files:** Create `Sources/StatusTrioCore/Battery/BatteryActionTarget.swift`; create `Tests/StatusTrioCoreTests/BatteryActionSettingsTests.swift`.

**Interfaces:** Produces `KnownBatteryAppID`, `ExternalApplicationTarget`, and `BatteryActionTarget: Codable, Equatable` with cases `.systemSettings`, `.knownApp(KnownBatteryAppID)`, `.customApp(ExternalApplicationTarget)`, `.customURL(String)`.

```swift
enum KnownBatteryAppID: String, Codable, CaseIterable {
    case alDente, batFi
}

struct ExternalApplicationTarget: Codable, Equatable {
    let displayName: String
    let bundleIdentifier: String?
    let fallbackPath: String?
}
```

- [ ] **Step 1: Write a failing model test.** Encode/decode every case and assert the explicit JSON keys; also assert an unknown `type` throws rather than silently decoding as another case.

```swift
let target = BatteryActionTarget.knownApp(.alDente)
let data = try JSONEncoder().encode(target)
let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
XCTAssertEqual(object["type"], "knownApp")
XCTAssertEqual(object["knownAppID"], "alDente")
XCTAssertEqual(try JSONDecoder().decode(BatteryActionTarget.self, from: data), target)
XCTAssertThrowsError(try JSONDecoder().decode(BatteryActionTarget.self, from: Data(#"{"type":"alien"}"#.utf8)))
```

- [ ] **Step 2: Run the focused test.** Run `swift test --filter BatteryActionSettingsTests`; expect a compilation failure because the target type does not exist.
- [ ] **Step 3: Implement explicit encoding.** Use `CodingKeys { type, knownAppID, application, url }` and a private `Kind: String, Codable`; encode the corresponding associated value only. Decode with a `switch` on `Kind` so unknown or missing fields throw. Define `ExternalApplicationTarget` with `displayName`, optional `bundleIdentifier`, and optional `fallbackPath`.

```swift
switch self {
case .systemSettings: try container.encode(Kind.systemSettings, forKey: .type)
case .knownApp(let id):
    try container.encode(Kind.knownApp, forKey: .type)
    try container.encode(id, forKey: .knownAppID)
case .customApp(let app):
    try container.encode(Kind.customApp, forKey: .type)
    try container.encode(app, forKey: .application)
case .customURL(let text):
    try container.encode(Kind.customURL, forKey: .type)
    try container.encode(text, forKey: .url)
}
```

- [ ] **Step 4: Verify and commit.** Run `swift test --filter BatteryActionSettingsTests`, `swift test`, and `swift build -c release`; commit only this model and its test with `feat(battery): define action targets`.

### Task 2: Store persistence and corrupt-data fallback

**Files:** Modify `Sources/StatusTrioCore/Settings/SettingsStore.swift`; extend `Tests/StatusTrioCoreTests/BatteryActionSettingsTests.swift`.

**Interfaces:** Consumes `BatteryActionTarget`. Produces `SettingsStore.batteryActionTargetDefaultsKey` and `@Published var batteryActionTarget: BatteryActionTarget`.

- [ ] **Step 1: Write failing store tests.** With an isolated `UserDefaults(suiteName:)`, assert missing key defaults to `.systemSettings`; write each case and make a second `SettingsStore`; inject invalid JSON, an unknown target type, and unknown `knownAppID` and assert `.systemSettings` each time.

```swift
let first = SettingsStore(defaults: defaults)
XCTAssertEqual(first.batteryActionTarget, .systemSettings)
first.batteryActionTarget = .customURL("raycast://battery")
XCTAssertEqual(SettingsStore(defaults: defaults).batteryActionTarget, .customURL("raycast://battery"))
defaults.set(Data(#"{"type":"knownApp","knownAppID":"missing"}"#.utf8),
             forKey: SettingsStore.batteryActionTargetDefaultsKey)
XCTAssertEqual(SettingsStore(defaults: defaults).batteryActionTarget, .systemSettings)
```

- [ ] **Step 2: Run `swift test --filter BatteryActionSettingsTests`.** Expect failure because the store property is missing.
- [ ] **Step 3: Add store integration.** Set `static let batteryActionTargetDefaultsKey = "batteryActionTarget.v1"`; initialize with `(defaults.data(forKey: key)).flatMap { try? JSONDecoder().decode(...) } ?? .systemSettings`; write encoded `Data` in `didSet`. Keep all other settings initialization unchanged.

```swift
@Published var batteryActionTarget: BatteryActionTarget {
    didSet {
        guard let data = try? JSONEncoder().encode(batteryActionTarget) else { return }
        defaults.set(data, forKey: Self.batteryActionTargetDefaultsKey)
    }
}
```

- [ ] **Step 4: Verify and commit.** Run the focused test, `swift test`, and `swift build -c release`; commit `feat(battery): persist action target`.

### Task 3: Verified known-app catalog

**Files:** Create `Sources/StatusTrioCore/Battery/KnownBatteryApps.swift`; create `Tests/StatusTrioCoreTests/KnownBatteryAppsTests.swift`.

**Interfaces:** Consumes `KnownBatteryAppID`. Produces `KnownBatteryAppDefinition { id, displayName, bundleIdentifiers, deepLink }` and `KnownBatteryApps.definition(for:)` plus `KnownBatteryApps.all`.

- [ ] **Step 1: Write failing catalog tests.** Assert both product names, modern Bundle IDs, and `deepLink == nil`; assert every `KnownBatteryAppID.allCases` has one definition and no duplicate ID.

```swift
XCTAssertEqual(KnownBatteryApps.definition(for: .alDente).displayName, "AlDente")
XCTAssertEqual(KnownBatteryApps.definition(for: .batFi).bundleIdentifiers,
               ["software.micropixels.BatFi"])
XCTAssertNil(KnownBatteryApps.definition(for: .alDente).deepLink)
```

- [ ] **Step 2: Run `swift test --filter KnownBatteryAppsTests`.** Expect the missing catalog failure.
- [ ] **Step 3: Add catalog constants.** AlDente uses `["com.apphousekitchen.aldente-pro"]`; BatFi uses `["software.micropixels.BatFi"]`; both deep links are `nil`. Add `com.davidwernhart.AlDente` only if an official archived build/source proves it and put that source in a code comment and test.

```swift
static let all: [KnownBatteryAppDefinition] = [
    .init(id: .alDente, displayName: "AlDente",
          bundleIdentifiers: ["com.apphousekitchen.aldente-pro"], deepLink: nil),
    .init(id: .batFi, displayName: "BatFi",
          bundleIdentifiers: ["software.micropixels.BatFi"], deepLink: nil)
]
```

- [ ] **Step 4: Verify and commit.** Run the focused test, `swift test`, and `swift build -c release`; commit `feat(battery): catalog verified utilities`.

### Task 4: Workspace adapter and launcher

**Files:** Create `Sources/StatusTrioCore/Battery/BatteryActionLauncher.swift`; create `Tests/StatusTrioCoreTests/BatteryActionLauncherTests.swift`.

**Interfaces:** Consumes target/catalog. Produces `@MainActor protocol BatteryWorkspace` with `applicationURL(bundleIdentifier:) -> URL?`, `fileExists(at:) -> Bool`, `openURL(_:) -> Bool`, `openApplication(_:) async throws`; `BatteryActionLauncher.init(workspace:definitions:)`, `isInstalled(_:)`, `validatedURL(_:) -> URL?`, and `open(target:systemSettingsFallback:) async`. `SystemBatteryWorkspace` maps these operations to `NSWorkspace` and `FileManager`.

```swift
@MainActor
protocol BatteryWorkspace {
    func applicationURL(bundleIdentifier: String) -> URL?
    func fileExists(at url: URL) -> Bool
    func openURL(_ url: URL) -> Bool
    func openApplication(_ url: URL) async throws
}

```

Use these exact launcher signatures: `init(workspace: any BatteryWorkspace = SystemBatteryWorkspace(), definitions: [KnownBatteryAppDefinition] = KnownBatteryApps.all)`, `func isInstalled(_ definition: KnownBatteryAppDefinition) -> Bool`, `static func validatedURL(_ raw: String) -> URL?`, and `func open(target: BatteryActionTarget, systemSettingsFallback: @escaping @MainActor () -> Void) async`.

- [ ] **Step 1: Write fake-workspace tests.** Cover system target exactly once; known app detection, current tool absent, successful future test-only deep link, failed deep link then app, successful and failed async launches, Bundle ID relocation, fallback path, absent custom app, valid/invalid/failed custom URL. Add the launcher Review Focus inputs: duplicate primary/fallback URL, removal between lookup and launch, whitespace-padded URL, malformed stored app identity, and failure to open a path that existed at selection time. Assert call order, not only total calls.

```swift
workspace.resolved["com.example.Tool"] = URL(fileURLWithPath: "/Applications/Tool.app")
workspace.applicationError = TestLaunchError.failed
await launcher.open(target: .customApp(.init(displayName: "Tool",
    bundleIdentifier: "com.example.Tool", fallbackPath: "/Applications/Tool.app"))) {
    fallbackCount += 1
}
XCTAssertEqual(workspace.openedApplications.count, 1) // identical fallback URL is not retried
XCTAssertEqual(fallbackCount, 1)
```

- [ ] **Step 2: Run `swift test --filter BatteryActionLauncherTests`.** Expect missing API failure.
- [ ] **Step 3: Implement the adapter.** Keep `NSWorkspace` out of SwiftUI. Resolve candidate app URLs on demand, require an existing `.app` bundle, and implement async launch with `try await NSWorkspace.shared.openApplication(at:configuration:)`; set `configuration.activates = true`. The catalog can be supplied to the launcher for a test-only deep link.

```swift
let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = true
_ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
```

- [ ] **Step 4: Implement routing.** For known apps resolve installation before opening a verified deep link. For custom apps try Bundle ID, then a distinct existing `.app` fallback path; catch async errors and advance to the next candidate. For URLs trim surrounding whitespace, require `URL(string:)` with nonempty scheme, and call `openURL`. Invoke system fallback once after all candidates fail. Do not mutate `SettingsStore` during fallback.

```swift
if let link = definition.deepLink, workspace.openURL(link) { return }
for candidate in distinctCandidates {
    do { try await workspace.openApplication(candidate); return }
    catch { continue }
}
systemSettingsFallback()
```

- [ ] **Step 5: Verify and commit.** Run the focused test, `swift test`, and `swift build -c release`; commit `feat(battery): launch configured action with fallback`.

### Task 5: Target wording and localization

**Files:** Create `Sources/StatusTrioCore/Battery/BatteryActionPresentation.swift`; modify `Sources/StatusTrioCore/Localization/LocalizationKey.swift` and all 12 `Sources/StatusTrioCore/Resources/*.lproj/Localizable.strings`; create `Tests/StatusTrioCoreTests/BatteryActionPresentationTests.swift`.

**Interfaces:** Produces `BatteryActionPresentation.openLabel(for:localization:) -> String` and `selectionName(for:localization:) -> String`; views use these results without querying installed apps. Use the existing `Localization.format(_:_:)` method for the `Open %@` key.

- [ ] **Step 1: Write failing presentation tests.** Assert system, AlDente, BatFi, custom app, and custom URL labels in English and Simplified Chinese; assert the product names remain untranslated and a long custom app name remains intact in the model (truncation belongs to views). Assert the localization key set has values in all 12 bundles.

```swift
XCTAssertEqual(BatteryActionPresentation.openLabel(for: .knownApp(.alDente),
    localization: english), "Open AlDente")
XCTAssertEqual(BatteryActionPresentation.openLabel(for: .customURL("raycast://battery"),
    localization: english), "Open Custom Link")
```

- [ ] **Step 2: Run `swift test --filter BatteryActionPresentationTests`.** Expect missing presentation/key failure.
- [ ] **Step 3: Add presentation and strings.** Keep existing `battery.action.openSettings` for exact default wording. Add keys for action group title/description, system target, custom app, custom URL, chooser, change button, unavailable, invalid URL, `battery.action.openTarget` (`Open %@` / `打开%@`) and `battery.action.customLink`. Fill each key in `en`, `ar`, `de`, `es`, `fr`, `it`, `ja`, `ko`, `pt-BR`, `ru`, `zh-Hans`, and `zh-Hant` with the product names unchanged.

```swift
case .systemSettings: return localization.string(.batteryActionOpenSettings)
case .knownApp(let id): return localization.format(.batteryActionOpenTarget,
    KnownBatteryApps.definition(for: id).displayName)
case .customApp(let app): return localization.format(.batteryActionOpenTarget, app.displayName)
case .customURL: return localization.format(.batteryActionOpenTarget,
    localization.string(.batteryActionCustomLink))
```

- [ ] **Step 4: Verify and commit.** Run the focused test, `swift test`, and `swift build -c release`; commit `feat(battery): localize target wording`.

### Task 6: Settings choice UI

**Files:** Create `Sources/StatusTrioCore/UI/Settings/BatteryActionSettingsView.swift`; modify `Sources/StatusTrioCore/UI/Settings/BatterySectionView.swift`; extend `Tests/StatusTrioCoreTests/SettingsViewTests.swift`.

**Interfaces:** Consumes `SettingsStore`, `BatteryActionLauncher.isInstalled`, `BatteryActionLauncher.validatedURL`, and presentation/localization. `BatterySectionView` remains source compatible by supplying a default launcher or read-only availability provider, while tests inject a fake workspace. Produces `BatteryActionChoice` with cases `.systemSettings`, `.knownApp(KnownBatteryAppID)`, `.customApplication`, `.customURL`, and `BatteryActionSettingsView.choices(current:installed:) -> [BatteryActionChoice]`. Keep the panel result handler in `BatteryActionSettingsView.applySelectedApplication(_ url: URL?, to store: SettingsStore)` so a `nil` cancellation is testable without opening a real panel.

- [ ] **Step 1: Write failing settings tests.** Render the battery page in English and Simplified Chinese. Assert the menu choice model contains system, installed known apps, Custom Application, and Custom URL. With no apps installed, assert an unselected known app is absent while a *selected* known app remains with unavailable status. Assert a selected custom app with no resolvable ID/path retains its saved display name and unavailable status. Verify cancelled `NSOpenPanel` response leaves the target unchanged through an injected selection function.

```swift
store.batteryActionTarget = .knownApp(.alDente)
let options = BatteryActionSettingsView.choices(current: store.batteryActionTarget,
    installed: [])
XCTAssertTrue(options.contains(.knownApp(.alDente)))
XCTAssertFalse(options.contains(.knownApp(.batFi)))
```

- [ ] **Step 2: Run `swift test --filter SettingsViewTests`.** Expect missing settings component failure.
- [ ] **Step 3: Implement the group.** Place it below `batteryGroup` in `BatterySectionView` and give that view a default `BatteryActionLauncher` property, overridable in tests. Use a menu with explicit buttons for system, available known apps, Custom Application, and Custom URL. Include the selected unavailable app in the menu and add a local nonmodal status row. Query availability when the settings view appears or menu opens, never with a timer.

```swift
SettingsPage(pinnedHeader: {
    StatusIconPreviewCard(store: store, statusStore: statusStore,
                          isDarkBackground: $previewIsDark)
}) {
    batteryGroup
    BatteryActionSettingsView(store: store, launcher: launcher)
}
```

- [ ] **Step 4: Implement selection details.** Configure `NSOpenPanel` for one `.applicationBundle` under `/Applications`. Only on `.OK` read `Bundle(url:)` display name, Bundle ID, and path and assign `.customApp`. For Custom URL use a text-field binding to `.customURL(text)`; show an inline invalid message only for nonempty invalid text, without opening it. Cancelled app selection leaves `store.batteryActionTarget` unchanged.

```swift
let panel = NSOpenPanel()
panel.allowedContentTypes = [.applicationBundle]
panel.canChooseFiles = true
panel.canChooseDirectories = false
panel.allowsMultipleSelection = false
panel.directoryURL = URL(fileURLWithPath: "/Applications")
guard panel.runModal() == .OK, let url = panel.url else { return }
store.batteryActionTarget = .customApp(ExternalApplicationTarget(
    displayName: Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? url.deletingPathExtension().lastPathComponent,
    bundleIdentifier: Bundle(url: url)?.bundleIdentifier,
    fallbackPath: url.path
))
```

- [ ] **Step 5: Verify and commit.** Run `swift test --filter SettingsViewTests`, `swift test`, and `swift build -c release`; commit `feat(battery): add action choice settings`.

### Task 7: Popup action and labels

**Files:** Modify `Sources/StatusTrioCore/UI/StatusBarController.swift`, `StatusPopoverView.swift`, `BatteryStatusView.swift`, `BatteryDetailsView.swift`; extend `Tests/StatusTrioCoreTests/BatteryDetailsLayoutTests.swift` and `BatteryPopoverPanelTests.swift`.

**Interfaces:** Consumes `SettingsStore.batteryActionTarget`, `BatteryActionLauncher.open`, and presentation. Both battery controls keep the same action closure; popup views receive a display label from `StatusPopoverView`.

- [ ] **Step 1: Write failing popup tests.** Exercise default, AlDente, and a long custom app label in English and Simplified Chinese at the existing 330 pt width. Assert gear help and accessibility label equal the detail-button label, long text truncates rather than enlarging the panel, and both controls use the same closure. Keep battery-absent behavior unchanged.

```swift
let label = BatteryActionPresentation.openLabel(for: .knownApp(.alDente),
    localization: localization)
XCTAssertEqual(label, language == .english ? "Open AlDente" : "打开AlDente")
let renderedSize = try await render(language: language, available: true,
                                    actionLabel: label)
XCTAssertEqual(renderedSize.width, 330, accuracy: 0.5)
```

- [ ] **Step 2: Run `swift test --filter BatteryDetailsLayoutTests` and `swift test --filter BatteryPopoverPanelTests`.** Expect new assertions or changed initializer calls to fail.
- [ ] **Step 3: Route the controller.** Add one launcher property, close the popover, snapshot the selected target, then create a main-actor `Task` that awaits launcher completion and invokes the *unchanged* `batterySettingsURLs` fallback. Do not route other settings actions through it.

```swift
@objc private func handleOpenBatterySettings() {
    popover.performClose(nil)
    let target = settings.batteryActionTarget
    Task { @MainActor in
        await batteryActionLauncher.open(target: target) {
            Self.openSystemSettings(Self.batterySettingsURLs)
        }
    }
}
```

- [ ] **Step 4: Pass and render the label.** In `StatusPopoverView`, derive the label from the target and localization and pass it to the battery summary and detail views. Use it for button title, gear `.help`, and gear accessibility label. Apply `.lineLimit(1)` and `.truncationMode(.tail)` to the detail button text. Update existing direct view constructions in tests with the default label.

```swift
let actionLabel = BatteryActionPresentation.openLabel(
    for: settings.batteryActionTarget, localization: localization)
BatteryStatusView(battery: store.popupSnapshot.battery, actionLabel: actionLabel,
    onOpenBatteryDetails: { panel = .battery }, onOpenBatterySettings: openBatterySettings)
```

- [ ] **Step 5: Verify and commit.** Run both focused suites, `swift test`, and `swift build -c release`; commit `feat(battery): route popup action to selected target`.

### Task 8: Documentation, release copy, and verification

**Files:** Create `docs/battery-actions.md`; update the current unreleased release-note directory (currently `release-notes/1.3.4/`); if a CI run fails, modify `docs/swift-ci-compatibility.md`.

**Interfaces:** No new product API. This task records behavior and provides CI evidence before integration.

- [ ] **Step 1: Document user behavior.** Describe each option, Bundle ID relocation, chosen app disappearing, URL validation, Battery Settings fallback, and the limit that Status Trio does not control third-party apps. State deep links are used only when publicly verified.
- [ ] **Step 2: Add release notes.** Inspect `gh release list --repo lingyired/status-trio --limit 5`, `Support/Info.plist`, `appcast.xml`, and existing `release-notes/` directories. Choose a version/build above the published build; as of this plan, v1.3.3 build 16 is published and `release-notes/1.3.4/` is an unreleased draft. Append the feature under the existing section in all 12 languages for the selected release; retain each `# ... %VERSION% ... %BUILD%` title. Do not overwrite other unreleased content.
- [ ] **Step 3: Run local gates.** Run `swift test`, `swift build -c release`, and `VERSION=1.3.4 BUILD=17 PUBLISH=true bash scripts/validate-appcast-notes.sh` if v1.3.4 build 17 is still the selected next release; substitute the freshly selected numbers otherwise. Run `git diff --check`. Record any limitation of manual checks rather than claiming they passed.
- [ ] **Step 4: Verify on this Mac.** Check AlDente/BatFi detection using their installed bundles and activation, an unrelated `.app`, a working URL scheme, invalid URL fallback, and default Battery Settings route. Do not move/delete the user's installed apps; the fake workspace tests cover relocation and disappearance.
- [ ] **Step 5: Commit the docs and copy.** Commit `docs(battery): explain action targets and release copy` after local gates pass.
- [ ] **Step 6: Run CI preflight on the implementation branch.** Push the branch and dispatch `release.yml` with the selected explicit version/build and `publish=false`; watch it to completion. A failed run must be logged in `docs/swift-ci-compatibility.md` with run ID, stage, root cause, fix, and verification result, then rerun. Do not create a release from a failed preflight.

```bash
battery_release_version=1.3.4
battery_build_number=17
gh workflow run release.yml --repo lingyired/status-trio --ref "$(git branch --show-current)" \
  -f version="$battery_release_version" -f build="$battery_build_number" -f publish=false
battery_run_id=$(gh run list --repo lingyired/status-trio --workflow release.yml \
  --branch "$(git branch --show-current)" --event workflow_dispatch --limit 1 \
  --json databaseId --jq '.[0].databaseId')
gh run watch "$battery_run_id" --repo lingyired/status-trio --exit-status
```

- [ ] **Step 7: Final verification.** Review `git diff` against the approved spec, confirm `swift test`, release build, notes validator, and CI preflight results, then use `finishing-a-development-branch` to integrate by the repo's Change Flow. A large multi-file change merits a PR; attach a created PR to this chat.
