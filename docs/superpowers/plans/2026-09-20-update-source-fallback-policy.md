# Update Source Fallback Policy Implementation Plan

> **STATUS: DEFERRED — owner decision required (2026-09-20).** This plan removes or gates the GitHub mirrors that users on restricted networks currently rely on to receive updates. A user who can no longer update is a worse outcome than a privacy leak in the fallback path, so do not start it without the owner weighing that trade-off explicitly. See `2026-09-20-review-findings-index.md` §0.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the updater from silently handing the appcast and DMG requests to unvetted third-party mirrors: never fall back on cancellation or TLS/certificate failures, reset the source per check cycle, and make mirror use an explicit, disclosed, default-off setting.

**Architecture:** Keep `UpdateSourceFallback` as the single pure decision unit and narrow what may move the client off GitHub. The retry policy gains a deny-list that is evaluated over the whole `NSUnderlyingErrorKey` chain, so a TLS failure wrapped inside a Sparkle `appcastError`/`downloadError` is still refused. The source list becomes policy-driven (`defaultSources(allowsMirrors:)`), defaults to GitHub only, and is rebuilt at the start of every check cycle so a transient failure can never pin the session. The setting lives in `SettingsStore`, cannot be enabled before a one-time disclosure is acknowledged, and is surfaced as a Settings row whose copy names both relays.

**Tech Stack:** Swift 6 / SwiftPM, Foundation `URLError`, Sparkle 2.9.6 (`SPUUpdaterDelegate`, `SUError`), Combine, SwiftUI, XCTest + Swift Testing, 12 localized `.strings` files.

**Spec:** Derived from the 2026-09-20 security review; cross-plan index: docs/superpowers/plans/2026-09-20-review-findings-index.md

## Global Constraints

- CI acceptance toolchain is the `macos-26` runner with Xcode 26.6 / Swift 6.3.3; local Xcode 27 / Swift 6.4 is not proof.
- This repository has NO Developer ID certificate and NO notarization secrets. Releases are Ad-hoc signed. Plans must not assume a Developer ID exists; any step that needs one must be written as a conditional, documented follow-up.
- The release path is `.github/workflows/release.yml` + `scripts/release.sh` + `scripts/update-appcast.rb` + `scripts/validate-appcast-notes.sh`. Do not publish manually.
- Never weaken update integrity: `SUPublicEDKey` stays pinned; no `SUAllowsInsecureUpdates`, no signature-skipping delegate, no disabling of EdDSA verification.
- Run `bash scripts/validate-appcast-notes.sh` for anything touching appcast or release notes, and `swift test` + `swift build -c release` for Swift changes.
- A non-publishing release preflight is the acceptance test for release-pipeline changes: `gh workflow run release.yml --repo lingyired/status-trio --ref <branch> -f version=1.3.0 -f build=12 -f publish=false` then `gh run watch <run-id> --repo lingyired/status-trio --exit-status`.
- Release notes: `release-notes/<version>/<language>.md`, one file per language, `en.md` + `zh-Hans.md` always required, each starting with a `# <title>` line containing `%VERSION%` and `%BUILD%`. Version/build numbers must increase the published build number.
- Tests are mixed Swift Testing / XCTest — match the file you extend.

## Verified Evidence

| Fact | Location |
| --- | --- |
| Mirror hosts are `https://gh-proxy.com/` and `https://ghfast.top/` | `Sources/StatusTrioCore/App/UpdateSourceFallback.swift:9-18` |
| `url(for:)` rewrites a URL through the current mirror whenever the host is `github.com` or `raw.githubusercontent.com` | `UpdateSourceFallback.swift:20-30`, `:32-39` |
| **Any** `NSURLErrorDomain` error advances the source — including `NSURLErrorCancelled` (`-999`) and `NSURLErrorServerCertificateUntrusted` (`-1202`) | `UpdateSourceFallback.swift:110-116` |
| Sparkle `appcastError`/`downloadError` also advance, and the code recurses into `NSUnderlyingErrorKey`, so a wrapped TLS failure advances too | `UpdateSourceFallback.swift:118-132` |
| `advanceAfterError` mutates `currentSource` and never restores `.github`; only an exhausted/refused advance clears `attemptedSources` | `UpdateSourceFallback.swift:82-106` |
| The mirrored appcast URL is published to Sparkle as the feed URL | `Sources/StatusTrioCore/App/UpdaterManager.swift:71-81` (`feedURLString(for:)`, line 80) |
| The DMG request URL is rewritten to the mirror | `UpdaterManager.swift:83-90` (line 89) |
| One transient failure retries the whole check on the next source | `UpdaterManager.swift:92-103` (line 97-98) |
| Errors are hidden from the user whenever another source exists | `Sources/StatusTrioCore/App/UpdateFallbackUserDriver.swift:18-32` (`shouldSuppressUpdaterError`, lines 22-25); wired at `UpdaterManager.swift:13-19` |
| Existing tests cover URL rewriting and advance behaviour only; four tests rely on the mirror list being the default | `Tests/StatusTrioCoreTests/UpdateSourceFallbackTests.swift:22-52`, `:62-95`, `:115-137` |
| `SettingsStore` is the single `UserDefaults`-backed preference owner with an injectable suite | `Sources/StatusTrioCore/Settings/SettingsStore.swift:1-6`, `:468-470`, `:849-859` |
| The update UI is one toggle in `updatesGroup` | `Sources/StatusTrioCore/UI/Settings/GeneralSectionView.swift:132-142` |
| `SettingsToggleRow` takes a title and an optional subtitle | `Sources/StatusTrioCore/UI/Settings/SettingsChrome.swift:157-172` |
| A localization test already pins third-party names inside a description, and another requires every key in all 12 languages | `Tests/StatusTrioCoreTests/LocalizationTests.swift:61-71`, `:73-114` |
| `UpdaterManager.start` has exactly one caller | `Sources/StatusTrioCore/App/AppDelegate.swift:23` |
| The three relays are undocumented in the README and in every published release note — the current fallback is silent in both senses | `grep -rn "gh-proxy\|ghfast" README.md release-notes/` returns nothing |

**What is actually at risk.** Breaking TLS to `raw.githubusercontent.com` (trivial on a hostile network, and the failure surfaces as a plain `NSURLErrorDomain` error) moves the client onto `gh-proxy.com` or `ghfast.top`, which then serve the appcast. Before the sibling plan `2026-09-20-signed-update-feed.md` lands, that feed is fully unauthenticated. After it lands, a mirror still cannot forge an installable update, but it can withhold or serve a stale feed (denial of service) and it always learns the user's IP address and update timing without ever being asked.

## Review Focus

- **A cancellation is not a network failure.** `NSURLErrorCancelled` (`-999`) means the request was abandoned — by the user closing the update window or by Sparkle tearing the cycle down. Treating it as "try another host" issues a request nobody is waiting for, and it moves the client to a third party after a *local* event. Pinned by `UpdateSourceFallbackTests/fallbackDoesNotAdvanceWhenTheRequestWasCancelled`.
- **A TLS failure must never be routed around.** `NSURLErrorServerCertificateUntrusted`, `…HasBadDate`, `…NotYetValid`, `…SecureConnectionFailed`, both client-certificate codes and `NSURLErrorAppTransportSecurityRequiresSecureConnection` are the exact signals of interception or downgrade; falling back to a different host on those turns a detected attack into a silent backend switch. Pinned by `fallbackDoesNotAdvanceForTLSErrors` and `fallbackDoesNotAdvanceForTLSErrorsWrappedInSparkleErrors`.
- **A mirror must not be reachable before the user has said yes.** The setting defaults to off and `SettingsStore` refuses to store `true` until the disclosure is acknowledged, so no code path — including a future one — can enable relays silently. Pinned by `SettingsStoreTests.testUpdateMirrorsCannotBeEnabledBeforeTheDisclosureIsAcknowledged` and `UpdateSourceFallbackTests/fallbackStaysOnGitHubWhenMirrorsAreDisabled`.
- **One failure must not pin the session.** Today, a single transient error during a background check leaves every later check in that launch talking to the mirror. Pinned by `fallbackResetsToGitHubForTheNextCycle` and by the manager test `UpdaterManagerTests/mirrorChoiceIsRecomputedForEveryCycle`.
- **Turning mirrors off must still tell the user something.** With GitHub-only sources there is no next source, so `canAdvanceAfterError` is false and the existing driver presents the error instead of acknowledging it away. Pinned by `UpdateFallbackUserDriverTests/suppressesUpdaterErrorWhenNextSourceIsAvailable` (unchanged, proves suppression only happens when a source exists) plus `UpdateSourceFallbackTests/fallbackStaysOnGitHubWhenMirrorsAreDisabled`.

---

### Task 1: Refuse to fall back on cancellation and TLS failures

**Files:**
- Modify: `Sources/StatusTrioCore/App/UpdateSourceFallback.swift:109-133`
- Test: `Tests/StatusTrioCoreTests/UpdateSourceFallbackTests.swift`

**Interfaces:**
- Consumes: `UpdateSourceFallback.advanceAfterError(_:)` and `canAdvanceAfterError(_:)` (unchanged signatures).
- Produces: `UpdateSourceRetryPolicy.shouldTryNextSource(after:)` keeps its signature but consults a new private `neverFallbackCodes: Set<URLError.Code>` over the entire `NSUnderlyingErrorKey` chain.
- Produces: `UpdateSourceFallback.mirrorSources` (`[.github, .ghProxy, .ghFast]`) so tests that exercise mirror behaviour stop depending on the production default.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/StatusTrioCoreTests/UpdateSourceFallbackTests.swift` (Swift Testing, matching the file):

```swift
    @Test
    func fallbackDoesNotAdvanceWhenTheRequestWasCancelled() {
        var fallback = UpdateSourceFallback(sources: UpdateSourceFallback.mirrorSources)
        let error = URLError(.cancelled)

        let advanced = fallback.advanceAfterError(error)
        #expect(!advanced)
        #expect(fallback.currentSource == .github)
    }

    @Test
    func fallbackDoesNotAdvanceForTLSErrors() {
        let tlsErrors: [URLError.Code] = [
            .secureConnectionFailed,
            .serverCertificateHasBadDate,
            .serverCertificateUntrusted,
            .serverCertificateNotYetValid,
            .clientCertificateRejected,
            .clientCertificateRequired,
            .appTransportSecurityRequiresSecureConnection
        ]

        for code in tlsErrors {
            var fallback = UpdateSourceFallback(sources: UpdateSourceFallback.mirrorSources)
            let advanced = fallback.advanceAfterError(URLError(code))
            #expect(!advanced, "\(code) must not move the client to a mirror")
            #expect(fallback.currentSource == .github)
        }
    }

    @Test
    func fallbackDoesNotAdvanceForTLSErrorsWrappedInSparkleErrors() {
        var fallback = UpdateSourceFallback(sources: UpdateSourceFallback.mirrorSources)
        let error = NSError(
            domain: SUSparkleErrorDomain,
            code: Int(SUError.appcastError.rawValue),
            userInfo: [NSUnderlyingErrorKey: URLError(.serverCertificateUntrusted)]
        )

        let advanced = fallback.advanceAfterError(error)
        #expect(!advanced)
        #expect(fallback.currentSource == .github)
    }

    @Test
    func fallbackStillAdvancesForTransientNetworkErrors() {
        var fallback = UpdateSourceFallback(sources: UpdateSourceFallback.mirrorSources)
        let error = NSError(
            domain: SUSparkleErrorDomain,
            code: Int(SUError.appcastError.rawValue),
            userInfo: [NSUnderlyingErrorKey: URLError(.networkConnectionLost)]
        )

        let advanced = fallback.advanceAfterError(error)
        #expect(advanced)
        #expect(fallback.currentSource == .ghProxy)
    }
```

Because `mirrorSources` does not exist yet, this also fails to compile until Step 3; that is the RED for the whole task.

- [ ] **Step 2: Run the tests and verify RED**

```bash
swift test --filter UpdateSourceFallbackTests
```

Expected: compile failure — `type 'UpdateSourceFallback' has no member 'mirrorSources'`.

- [ ] **Step 3: Add the sink and the deny-list**

In `Sources/StatusTrioCore/App/UpdateSourceFallback.swift`, add to the struct (just above `defaultSources`):

```swift
    /// GitHub first, then the two third-party relays. Only used when the user has
    /// explicitly enabled mirrors in Settings and acknowledged the disclosure.
    static let mirrorSources: [UpdateSource] = [.github, .ghProxy, .ghFast]
```

Replace the whole `private enum UpdateSourceRetryPolicy` block (`UpdateSourceFallback.swift:109-133`) with:

```swift
private enum UpdateSourceRetryPolicy {
    /// Errors that must never move the client to a third-party host.
    ///
    /// `cancelled` means the request was abandoned locally, so there is nothing
    /// to retry. The rest are the interception and downgrade signals: routing
    /// around them would turn a detected attack into a silent backend switch.
    private static let neverFallbackCodes: Set<URLError.Code> = [
        .cancelled,
        .secureConnectionFailed,
        .serverCertificateHasBadDate,
        .serverCertificateUntrusted,
        .serverCertificateNotYetValid,
        .clientCertificateRejected,
        .clientCertificateRequired,
        .appTransportSecurityRequiresSecureConnection
    ]

    static func shouldTryNextSource(after error: Error?) -> Bool {
        guard let error else { return false }

        // Checked over the whole chain first: Sparkle wraps URL failures inside
        // SUAppcastError/SUDownloadError, so the top-level domain alone would
        // let a wrapped TLS failure through.
        if containsNeverFallbackCode(error) {
            return false
        }

        if isRetryableOuterError(error) {
            return true
        }

        guard let underlyingError = (error as NSError).userInfo[NSUnderlyingErrorKey] as? Error else {
            return false
        }

        return shouldTryNextSource(after: underlyingError)
    }

    private static func containsNeverFallbackCode(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           let code = URLError.Code(rawValue: nsError.code),
           neverFallbackCodes.contains(code) {
            return true
        }

        guard let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error else {
            return false
        }

        return containsNeverFallbackCode(underlyingError)
    }

    private static func isRetryableOuterError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return true
        }

        if nsError.domain == SUSparkleErrorDomain {
            switch nsError.code {
            case Int(SUError.appcastError.rawValue),
                 Int(SUError.downloadError.rawValue):
                return true
            default:
                break
            }
        }

        return false
    }
}
```

- [ ] **Step 4: Point the mirror-dependent tests at the explicit list**

Five existing tests expect to move through the mirrors and currently rely on `defaultSources`; they must name the mirror list so Task 3 can safely make GitHub the default. Change the constructor calls only — leave every assertion untouched.

| Test | Line | Before | After |
| --- | --- | --- | --- |
| `fallbackAdvancesThroughEverySourceOnce` | `:64` | `var fallback = UpdateSourceFallback(initialSource: .github)` | `var fallback = UpdateSourceFallback(sources: UpdateSourceFallback.mirrorSources, initialSource: .github)` |
| `fallbackCanAdvanceWithoutChangingSourceWhenNextSourceExists` | `:81` | `let fallback = UpdateSourceFallback(initialSource: .github)` | `let fallback = UpdateSourceFallback(sources: UpdateSourceFallback.mirrorSources, initialSource: .github)` |
| `fallbackCannotAdvanceAfterLastSource` | `:90` | `let fallback = UpdateSourceFallback(initialSource: .ghFast)` | `let fallback = UpdateSourceFallback(sources: UpdateSourceFallback.mirrorSources, initialSource: .ghFast)` |
| `fallbackAdvancesForSparkleDownloadErrors` | `:117` | `var fallback = UpdateSourceFallback(initialSource: .github)` | `var fallback = UpdateSourceFallback(sources: UpdateSourceFallback.mirrorSources, initialSource: .github)` |
| `fallbackAdvancesForWrappedNetworkErrors` | `:127` | `var fallback = UpdateSourceFallback(initialSource: .github)` | `var fallback = UpdateSourceFallback(sources: UpdateSourceFallback.mirrorSources, initialSource: .github)` |

Leave four call sites alone, for the stated reason:

- `fallbackUsesSelectedSourceForFeedAndDownloadURLs` (`:99`) keeps `UpdateSourceFallback(initialSource: .ghFast)`: it only rewrites URLs, and `url(for:)` reads `currentSource`, never `sources`.
- `fallbackDoesNotAdvanceWhenNoUpdateWasFound` (`:141`) and `fallbackDoesNotAdvanceForSignatureFailures` (`:151`) keep `UpdateSourceFallback(initialSource: .github)` and assert no advance, which holds for any source list.
- `fallbackCannotAdvanceAfterLastSource` is listed above rather than here because naming the mirror list is what makes "after the last source" true.

Verify the edit landed:

```bash
grep -n "UpdateSourceFallback(" Tests/StatusTrioCoreTests/UpdateSourceFallbackTests.swift
```

Expected: `mirrorSources` appears on the five lines above and nowhere else.

- [ ] **Step 5: Run the tests and verify GREEN**

```bash
swift test --filter UpdateSourceFallbackTests
```

Expected: all tests PASS, including the four new ones and the four relabelled ones.

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusTrioCore/App/UpdateSourceFallback.swift Tests/StatusTrioCoreTests/UpdateSourceFallbackTests.swift
git commit -m "fix: never fall back to an update mirror on TLS or cancellation errors"
```

---

### Task 2: Reset the source at the start of every check cycle

**Files:**
- Modify: `Sources/StatusTrioCore/App/UpdateSourceFallback.swift:42-107`
- Modify: `Sources/StatusTrioCore/App/UpdaterManager.swift:26`, `:60-69`, `:92-103`
- Test: `Tests/StatusTrioCoreTests/UpdateSourceFallbackTests.swift`

**Interfaces:**
- Produces: `UpdateSourceFallback.resetForNewCycle()` — restores `currentSource` to the first configured source and clears `attemptedSources`.
- Produces: `UpdaterManager.beginNewSourceCycle()` (internal so tests can drive it) which replaces the fallback with a fresh one, and an internal `UpdaterManager.updateSourceFallback` so tests can read it.
- Consumes: `UpdateSourceFallback.mirrorSources` from Task 1.
- Note: this task keeps today's three-element source list; Task 3 makes it policy-driven and default-off.

- [ ] **Step 1: Write the failing test**

Append to `Tests/StatusTrioCoreTests/UpdateSourceFallbackTests.swift`:

```swift
    @Test
    func fallbackResetsToGitHubForTheNextCycle() {
        var fallback = UpdateSourceFallback(sources: UpdateSourceFallback.mirrorSources)
        let error = URLError(.networkConnectionLost)

        #expect(fallback.advanceAfterError(error))
        #expect(fallback.currentSource == .ghProxy)

        fallback.resetForNewCycle()
        #expect(fallback.currentSource == .github)

        // A reset must also drop the "already attempted" bookkeeping, otherwise a
        // second failure in the same session could never reach the same mirror.
        #expect(fallback.advanceAfterError(error))
        #expect(fallback.currentSource == .ghProxy)
    }
```

- [ ] **Step 2: Run the test and verify RED**

```bash
swift test --filter UpdateSourceFallbackTests/fallbackResetsToGitHubForTheNextCycle
```

Expected: compile failure — `value of type 'UpdateSourceFallback' has no member 'resetForNewCycle'`.

- [ ] **Step 3: Implement the reset**

In `Sources/StatusTrioCore/App/UpdateSourceFallback.swift`, add above `canAdvanceAfterError`:

```swift
    /// Restores the fallback to the first configured source.
    ///
    /// Called once per update-check cycle. Without it, one transient failure pins
    /// every later check in the same launch to whichever mirror answered last.
    mutating func resetForNewCycle() {
        attemptedSources.removeAll()
        currentSource = sources.first ?? Self.defaultSources[0]
    }
```

- [ ] **Step 4: Wire the reset into `UpdaterManager`**

Change `UpdaterManager.swift:26` from

```swift
    private var updateSourceFallback = UpdateSourceFallback()
```

to

```swift
    /// Internal, not private: `UpdaterManagerTests` drives the source policy
    /// through `beginNewSourceCycle()` without starting Sparkle, which is skipped
    /// under `#if DEBUG` anyway (UpdaterManager.swift:49-51).
    var updateSourceFallback = UpdateSourceFallback()
```

At the top of `checkForUpdates()` (before `guard canCheckForUpdates else { return }`) add:

```swift
        beginNewSourceCycle()
```

Replace `didFinishUpdateCycleFor` so a completed cycle also resets:

```swift
    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        if updateSourceFallback.advanceAfterError(error) {
            retryUpdateCheck(updateCheck)
            return
        }

        // The cycle is over: the next one starts from the first source again so a
        // single transient failure cannot pin this launch to a mirror.
        beginNewSourceCycle()
        manualUpdatePresentation?.end()
    }

    func beginNewSourceCycle() {
        updateSourceFallback = UpdateSourceFallback()
    }
```

`UpdateSourceFallback()` still builds today's `[.github, .ghProxy, .ghFast]` list, so this task changes only *when* the source is chosen, not which sources exist. Task 3 replaces both constructor calls with the policy-driven form.

Wiring check, by hand, that no recursion is possible: `retryUpdateCheck` calls `updater.checkForUpdates()`, not the manager's `checkForUpdates()`, so the per-cycle reset never re-runs inside an in-flight retry chain (`UpdaterManager.swift:105-114`).

- [ ] **Step 5: Run the tests and verify GREEN**

```bash
swift test --filter UpdateSourceFallbackTests
swift test --filter UpdaterManagerTests
```

Expected: all PASS. `UpdaterManagerTests` currently exercises only `automaticallyChecksForUpdatesBinding`, which the new code does not touch.

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusTrioCore/App/UpdateSourceFallback.swift Sources/StatusTrioCore/App/UpdaterManager.swift Tests/StatusTrioCoreTests/UpdateSourceFallbackTests.swift
git commit -m "fix: reset the update source at the start of every check cycle"
```

---

### Task 3: Make mirrors opt-in with a disclosed, enforced setting

**Files:**
- Modify: `Sources/StatusTrioCore/App/UpdateSourceFallback.swift` (the `defaultSources` declaration)
- Modify: `Sources/StatusTrioCore/App/UpdaterManager.swift:45-58` (`start` signature and stored settings)
- Modify: `Sources/StatusTrioCore/App/AppDelegate.swift:23`
- Modify: `Sources/StatusTrioCore/Settings/SettingsStore.swift:6-8`, `:468-496`, `:~570`
- Test: `Tests/StatusTrioCoreTests/UpdateSourceFallbackTests.swift`
- Test: `Tests/StatusTrioCoreTests/UpdaterManagerTests.swift`
- Test: `Tests/StatusTrioCoreTests/SettingsStoreTests.swift`

**Interfaces:**
- Produces: `UpdateSourceFallback.defaultSources(allowsMirrors:) -> [UpdateSource]`; `static let defaultSources` becomes GitHub-only.
- Produces: `SettingsStore.allowsUpdateMirrors: Bool` (default `false`), `SettingsStore.hasAcknowledgedUpdateMirrorDisclosure: Bool`, `SettingsStore.enableUpdateMirrorsAfterDisclosure()`, and the defaults keys `allowsUpdateMirrors` / `hasAcknowledgedUpdateMirrorDisclosure`.
- Produces: `UpdaterManager.start(activationPolicy:settings:)`.
- Consumes: `UpdateSourceFallback.mirrorSources` (Task 1), `UpdaterManager.beginNewSourceCycle()` (Task 2).

- [ ] **Step 1: Write the failing tests**

Append to `Tests/StatusTrioCoreTests/UpdateSourceFallbackTests.swift`:

```swift
    @Test
    func fallbackStaysOnGitHubWhenMirrorsAreDisabled() {
        var fallback = UpdateSourceFallback(
            sources: UpdateSourceFallback.defaultSources(allowsMirrors: false)
        )
        let error = URLError(.networkConnectionLost)

        #expect(!fallback.canAdvanceAfterError(error))
        #expect(!fallback.advanceAfterError(error))
        #expect(fallback.currentSource == .github)
    }

    @Test
    func fallbackUsesEveryMirrorWhenMirrorsAreAllowed() {
        var fallback = UpdateSourceFallback(
            sources: UpdateSourceFallback.defaultSources(allowsMirrors: true)
        )
        let error = URLError(.networkConnectionLost)

        #expect(fallback.advanceAfterError(error))
        #expect(fallback.currentSource == .ghProxy)
        #expect(fallback.advanceAfterError(error))
        #expect(fallback.currentSource == .ghFast)
    }

    @Test
    func mirrorHostsAreNeverUsedWithoutOptIn() {
        let disabled = UpdateSourceFallback.defaultSources(allowsMirrors: false)
        #expect(disabled == [.github])

        for source in disabled {
            let url = URL(string: "https://raw.githubusercontent.com/lingyired/status-trio/main/appcast.xml")!
            #expect(source.url(for: url) == url)
        }
    }
```

Append to `Tests/StatusTrioCoreTests/UpdaterManagerTests.swift` (Swift Testing, `@MainActor` file; add `import Foundation` to the existing `Combine`/`Testing` imports):

```swift
    @Test
    func mirrorChoiceIsRecomputedForEveryCycle() throws {
        let manager = UpdaterManager.shared
        let name = "StatusTrioCoreTests.UpdaterManager.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer {
            manager.settings = nil
            manager.beginNewSourceCycle()
            TestUserDefaults.removeSuite(named: name)
        }
        defaults.removeTestSuite(named: name)

        let settings = SettingsStore(defaults: defaults)
        manager.settings = settings

        manager.beginNewSourceCycle()
        #expect(manager.updateSourceFallback.currentSource == .github)
        #expect(manager.updateSourceFallback.advanceAfterError(URLError(.networkConnectionLost)) == false)

        settings.enableUpdateMirrorsAfterDisclosure()
        manager.beginNewSourceCycle()
        #expect(manager.updateSourceFallback.advanceAfterError(URLError(.networkConnectionLost)))
        #expect(manager.updateSourceFallback.currentSource == .ghProxy)

        // The next cycle must start from GitHub again, and opting out must take
        // effect on the cycle after it.
        manager.beginNewSourceCycle()
        #expect(manager.updateSourceFallback.currentSource == .github)
        settings.allowsUpdateMirrors = false
        manager.beginNewSourceCycle()
        #expect(manager.updateSourceFallback.advanceAfterError(URLError(.networkConnectionLost)) == false)
    }
```

Swift Testing has no `addTeardownBlock`, so the suite is discarded with `defer` rather than the `addTeardownBlock` form used by the XCTest-based `SettingsStoreTests` (`SettingsStoreTests.swift:857`).

Append to `Tests/StatusTrioCoreTests/SettingsStoreTests.swift` (XCTest, matching the file):

```swift
    func testUpdateMirrorsDefaultOff() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertFalse(store.allowsUpdateMirrors)
        XCTAssertFalse(store.hasAcknowledgedUpdateMirrorDisclosure)
    }

    func testUpdateMirrorsCannotBeEnabledBeforeTheDisclosureIsAcknowledged() {
        let suite = makeSuite()
        defer { clear(suite) }

        let store = SettingsStore(defaults: suite.defaults)
        store.allowsUpdateMirrors = true

        XCTAssertFalse(store.allowsUpdateMirrors, "mirrors must not be reachable before the disclosure")
        XCTAssertFalse(suite.defaults.bool(forKey: SettingsStore.allowsUpdateMirrorsDefaultsKey))
    }

    func testEnablingUpdateMirrorsAfterTheDisclosurePersists() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        first.enableUpdateMirrorsAfterDisclosure()

        XCTAssertTrue(first.allowsUpdateMirrors)
        XCTAssertTrue(first.hasAcknowledgedUpdateMirrorDisclosure)

        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertTrue(second.allowsUpdateMirrors)
        XCTAssertTrue(second.hasAcknowledgedUpdateMirrorDisclosure)
    }

    func testEnablingUpdateMirrorsTwiceDoesNotForgetTheDisclosure() {
        let suite = makeSuite()
        defer { clear(suite) }

        let store = SettingsStore(defaults: suite.defaults)
        store.enableUpdateMirrorsAfterDisclosure()
        store.allowsUpdateMirrors = false
        store.allowsUpdateMirrors = true

        XCTAssertTrue(store.allowsUpdateMirrors)
        XCTAssertTrue(store.hasAcknowledgedUpdateMirrorDisclosure)
    }
```

- [ ] **Step 2: Run the tests and verify RED**

```bash
swift test --filter UpdateSourceFallbackTests
swift test --filter SettingsStoreTests
swift test --filter UpdaterManagerTests
```

Expected: compile failures — `type 'UpdateSourceFallback' has no member 'defaultSources(allowsMirrors:)'`, `value of type 'SettingsStore' has no member 'allowsUpdateMirrors'`, `value of type 'UpdaterManager' has no member 'settings'`.

- [ ] **Step 3: Add the policy to `UpdateSourceFallback`**

Replace the `defaultSources` declaration (`UpdateSourceFallback.swift:43`) with:

```swift
    /// GitHub only. This is the default: the relays are third parties, so they
    /// are reachable only after the user enables them and acknowledges the
    /// disclosure in Settings.
    static let defaultSources: [UpdateSource] = [.github]

    static func defaultSources(allowsMirrors: Bool) -> [UpdateSource] {
        allowsMirrors ? mirrorSources : defaultSources
    }
```

- [ ] **Step 4: Add the setting to `SettingsStore`**

Next to the other Sparkle keys (`SettingsStore.swift:6-8`) add:

```swift
    static let allowsUpdateMirrorsDefaultsKey = "allowsUpdateMirrors"
    static let hasAcknowledgedUpdateMirrorDisclosureDefaultsKey = "hasAcknowledgedUpdateMirrorDisclosure"
```

Add the two published properties next to `refreshIntervalSeconds` (`SettingsStore.swift:260-269`):

```swift
    /// Third-party relays for the update feed. Refuses to turn on until
    /// `enableUpdateMirrorsAfterDisclosure()` has been called, so no UI path and
    /// no future code path can reach a mirror without the user being told.
    @Published var allowsUpdateMirrors: Bool {
        didSet {
            if allowsUpdateMirrors && !hasAcknowledgedUpdateMirrorDisclosure {
                allowsUpdateMirrors = false
                return
            }
            guard allowsUpdateMirrors != oldValue else { return }
            defaults.set(allowsUpdateMirrors, forKey: Self.allowsUpdateMirrorsDefaultsKey)
        }
    }

    @Published private(set) var hasAcknowledgedUpdateMirrorDisclosure: Bool {
        didSet {
            guard hasAcknowledgedUpdateMirrorDisclosure != oldValue else { return }
            defaults.set(
                hasAcknowledgedUpdateMirrorDisclosure,
                forKey: Self.hasAcknowledgedUpdateMirrorDisclosureDefaultsKey
            )
        }
    }

    func enableUpdateMirrorsAfterDisclosure() {
        hasAcknowledgedUpdateMirrorDisclosure = true
        allowsUpdateMirrors = true
    }
```

In `init(defaults:)`, next to the other stored reads (`SettingsStore.swift:486-495`) add:

```swift
        let storedAllowsUpdateMirrors = defaults.object(forKey: Self.allowsUpdateMirrorsDefaultsKey) as? Bool
        let storedMirrorDisclosure = defaults.object(
            forKey: Self.hasAcknowledgedUpdateMirrorDisclosureDefaultsKey
        ) as? Bool
```

and next to the other assignments (`SettingsStore.swift:~568`) add:

```swift
        self.hasAcknowledgedUpdateMirrorDisclosure = storedMirrorDisclosure ?? false
        // A stored `true` without the disclosure cannot happen through the setter,
        // but a stale preference file could still hold one, so it is re-checked.
        self.allowsUpdateMirrors = (storedAllowsUpdateMirrors ?? false)
            && (storedMirrorDisclosure ?? false)
```

`didSet` does not run during `init`, so the constructor assignment above is the only place the invariant is not enforced by the setter.

- [ ] **Step 5: Wire the setting into `UpdaterManager`**

Change the `start` signature (`UpdaterManager.swift:45`) to

```swift
    func start(activationPolicy: AppActivationPolicy, settings: SettingsStore) {
        self.settings = settings
        manualUpdatePresentation = ManualUpdatePresentation(
            activationPolicy: activationPolicy
        )
```

Add the stored settings next to `private var manualUpdatePresentation: ManualUpdatePresentation?`:

```swift
    /// Assigned by `start(activationPolicy:settings:)`. While it is nil — which is
    /// the case in tests that never start the updater — mirrors are read as off.
    var settings: SettingsStore?
```

Then replace **both** `UpdateSourceFallback()` constructor calls from Task 2 with the policy-driven form:

```swift
    var updateSourceFallback = UpdateSourceFallback(
        sources: UpdateSourceFallback.defaultSources(allowsMirrors: false)
    )
```

```swift
    func beginNewSourceCycle() {
        updateSourceFallback = UpdateSourceFallback(
            sources: UpdateSourceFallback.defaultSources(allowsMirrors: settings?.allowsUpdateMirrors == true)
        )
    }
```

The stored property keeps the literal `false` so a manager that was never started cannot reach a mirror; only `beginNewSourceCycle()` consults the setting.

Update the single caller (`AppDelegate.swift:23`):

```swift
        updaterManager.start(activationPolicy: environment.activationPolicy, settings: environment.settings)
```

- [ ] **Step 6: Run the tests and verify GREEN**

```bash
swift test --filter UpdateSourceFallbackTests
swift test --filter SettingsStoreTests
swift test --filter UpdaterManagerTests
swift test --filter UpdateFallbackUserDriverTests
```

Expected: all PASS, including the 7 pre-existing `SettingsStoreTests` neighbours and `UpdateFallbackUserDriverTests`, whose driver shape is deliberately unchanged.

- [ ] **Step 7: Commit**

```bash
git add Sources/StatusTrioCore/App/UpdateSourceFallback.swift \
        Sources/StatusTrioCore/App/UpdaterManager.swift \
        Sources/StatusTrioCore/App/AppDelegate.swift \
        Sources/StatusTrioCore/Settings/SettingsStore.swift \
        Tests/StatusTrioCoreTests/UpdateSourceFallbackTests.swift \
        Tests/StatusTrioCoreTests/UpdaterManagerTests.swift \
        Tests/StatusTrioCoreTests/SettingsStoreTests.swift
git commit -m "feat: make third-party update mirrors opt-in and default off"
```

---

### Task 4: Show the disclosure in Settings, in all 12 languages

**Files:**
- Modify: `Sources/StatusTrioCore/Localization/LocalizationKey.swift:164-166`
- Modify: all 12 `Sources/StatusTrioCore/Resources/*.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/UI/Settings/GeneralSectionView.swift:132-142`
- Test: `Tests/StatusTrioCoreTests/LocalizationTests.swift`

**Interfaces:**
- Produces: `LocalizationKey.settingsUpdatesMirrors` = `"settings.updates.mirrors"`, `.settingsUpdatesMirrorsDescription` = `"settings.updates.mirrors.description"`, `.settingsUpdatesMirrorsConfirm` = `"settings.updates.mirrors.confirm"`, `.settingsUpdatesMirrorsCancel` = `"settings.updates.mirrors.cancel"` — four keys in all 12 language files.
- Consumes: `SettingsStore.allowsUpdateMirrors`, `SettingsStore.hasAcknowledgedUpdateMirrorDisclosure`, `SettingsStore.enableUpdateMirrorsAfterDisclosure()` (Task 3).

- [ ] **Step 1: Write the failing test**

Append to `Tests/StatusTrioCoreTests/LocalizationTests.swift`:

```swift
    func testUpdateMirrorDisclosureNamesBothRelays() throws {
        for language in AppLanguage.allCases {
            let bundle = try XCTUnwrap(Localization.resourceBundle(for: language))
            let title = bundle.localizedString(
                forKey: LocalizationKey.settingsUpdatesMirrors.rawValue,
                value: nil,
                table: nil
            )
            let description = bundle.localizedString(
                forKey: LocalizationKey.settingsUpdatesMirrorsDescription.rawValue,
                value: nil,
                table: nil
            )

            XCTAssertFalse(title.isEmpty, "\(language.rawValue) has no mirror title")
            for relay in ["gh-proxy.com", "ghfast.top"] {
                XCTAssertTrue(
                    description.contains(relay),
                    "\(language.rawValue) mirror disclosure does not name \(relay)"
                )
            }
            XCTAssertTrue(
                description.contains("GitHub"),
                "\(language.rawValue) mirror disclosure does not name GitHub as the default host"
            )
        }
    }

    func testUpdateMirrorRowLabelsStayCompact() throws {
        let limited: [AppLanguage: Int] = [.english: 40, .simplifiedChinese: 14, .traditionalChinese: 14]
        for (language, limit) in limited {
            let bundle = try XCTUnwrap(Localization.resourceBundle(for: language))
            let title = bundle.localizedString(
                forKey: LocalizationKey.settingsUpdatesMirrors.rawValue,
                value: nil,
                table: nil
            )
            XCTAssertLessThanOrEqual(
                title.count,
                limit,
                "\(language.rawValue) mirror title is too long for the settings row"
            )
        }
    }
```

- [ ] **Step 2: Run the test and verify RED**

```bash
swift test --filter LocalizationTests/testUpdateMirrorDisclosureNamesBothRelays
```

Expected: compile failure — `type 'LocalizationKey' has no member 'settingsUpdatesMirrors'`.

- [ ] **Step 3: Add the keys**

In `Sources/StatusTrioCore/Localization/LocalizationKey.swift`, after `settingsUpdatesCheck`:

```swift
    case settingsUpdatesMirrors = "settings.updates.mirrors"
    case settingsUpdatesMirrorsDescription = "settings.updates.mirrors.description"
```

- [ ] **Step 4: Add the copy to all 12 language files**

Append directly after the `settings.updates.check` line in each file (`en.lproj/Localizable.strings:104`, `zh-Hans.lproj/Localizable.strings:104`, and the matching line in the other ten):

```text
"settings.updates.mirrors" = "Use third-party update mirrors";
"settings.updates.mirrors.description" = "When GitHub is unreachable, fetch updates through the third-party relays gh-proxy.com and ghfast.top. These relays see your IP address and when you check for updates. Leave this off to contact GitHub only; an unreachable GitHub then reports an error instead of switching hosts.";
```

```text
"settings.updates.mirrors" = "使用第三方更新镜像";
"settings.updates.mirrors.description" = "GitHub 无法访问时，改用第三方中继 gh-proxy.com 和 ghfast.top 获取更新。这些中继会看到你的 IP 地址和检查更新的时间。关闭此项时只访问 GitHub；GitHub 无法访问时会直接报错，而不会切换主机。";
```

```text
"settings.updates.mirrors" = "使用第三方更新鏡像";
"settings.updates.mirrors.description" = "GitHub 無法連線時，改用第三方中繼 gh-proxy.com 與 ghfast.top 取得更新。這些中繼會看到你的 IP 位址與檢查更新的時間。關閉此項時只連線 GitHub；GitHub 無法連線時會直接顯示錯誤，而不會切換主機。";
```

```text
"settings.updates.mirrors" = "サードパーティの更新ミラーを使う";
"settings.updates.mirrors.description" = "GitHub に接続できないとき、サードパーティの中継 gh-proxy.com と ghfast.top を使って更新を取得します。これらのサービスには IP アドレスと更新確認の時刻が見えます。オフのままにすると GitHub のみに接続し、GitHub に接続できない場合は接続先を切り替えずエラーを表示します。";
```

```text
"settings.updates.mirrors" = "서드파티 업데이트 미러 사용";
"settings.updates.mirrors.description" = "GitHub에 연결할 수 없을 때 서드파티 중계 gh-proxy.com과 ghfast.top을 통해 업데이트를 받아옵니다. 이 중계 서비스는 사용자의 IP 주소와 업데이트 확인 시각을 볼 수 있습니다. 꺼 두면 GitHub에만 연결하며, GitHub에 연결할 수 없으면 호스트를 바꾸지 않고 오류를 표시합니다.";
```

```text
"settings.updates.mirrors" = "Update-Spiegel von Drittanbietern verwenden";
"settings.updates.mirrors.description" = "Wenn GitHub nicht erreichbar ist, Updates über die Drittanbieter-Relays gh-proxy.com und ghfast.top beziehen. Diese Relays sehen deine IP-Adresse und wann du nach Updates suchst. Ausgeschaltet wird nur GitHub kontaktiert; ist GitHub nicht erreichbar, erscheint ein Fehler, statt den Host zu wechseln.";
```

```text
"settings.updates.mirrors" = "Usar servidores espejo de terceros";
"settings.updates.mirrors.description" = "Cuando GitHub no esté disponible, obtener las actualizaciones mediante los relés de terceros gh-proxy.com y ghfast.top. Estos relés ven tu dirección IP y cuándo buscas actualizaciones. Si lo dejas desactivado, solo se contacta con GitHub; si GitHub no está disponible, se muestra un error en lugar de cambiar de servidor.";
```

```text
"settings.updates.mirrors" = "Utiliser des miroirs de mise à jour tiers";
"settings.updates.mirrors.description" = "Lorsque GitHub est injoignable, récupérer les mises à jour via les relais tiers gh-proxy.com et ghfast.top. Ces relais voient votre adresse IP et le moment où vous recherchez des mises à jour. Désactivé, seul GitHub est contacté ; si GitHub est injoignable, une erreur s’affiche au lieu de changer d’hôte.";
```

```text
"settings.updates.mirrors" = "Usa mirror di aggiornamento di terze parti";
"settings.updates.mirrors.description" = "Quando GitHub non è raggiungibile, scarica gli aggiornamenti tramite i relay di terze parti gh-proxy.com e ghfast.top. Questi relay vedono il tuo indirizzo IP e quando cerchi aggiornamenti. Se disattivato, viene contattato solo GitHub; se GitHub non è raggiungibile, viene mostrato un errore invece di cambiare host.";
```

```text
"settings.updates.mirrors" = "Usar espelhos de atualização de terceiros";
"settings.updates.mirrors.description" = "Quando o GitHub estiver inacessível, buscar atualizações pelos relays de terceiros gh-proxy.com e ghfast.top. Esses relays veem seu endereço IP e quando você verifica atualizações. Com esta opção desligada, apenas o GitHub é contatado; se o GitHub estiver inacessível, um erro é exibido em vez de trocar de servidor.";
```

```text
"settings.updates.mirrors" = "Использовать сторонние зеркала обновлений";
"settings.updates.mirrors.description" = "Когда GitHub недоступен, получать обновления через сторонние посредники gh-proxy.com и ghfast.top. Эти посредники видят ваш IP-адрес и время проверки обновлений. Если выключено, используется только GitHub; при недоступности GitHub появляется ошибка вместо смены узла.";
```

```text
"settings.updates.mirrors" = "استخدام مرايا تحديث خارجية";
"settings.updates.mirrors.description" = "عند تعذّر الوصول إلى GitHub، استخدم الوسيطين الخارجيين gh-proxy.com وghfast.top لجلب التحديثات. يرى هذان الوسيطان عنوان IP الخاص بك ووقت التحقق من التحديثات. إذا كان الخيار متوقفًا، فلن يُتصل إلا بـ GitHub؛ وعند تعذّر الوصول إليه يظهر خطأ بدل تبديل الخادم.";
```

- [ ] **Step 5: Add the Settings row with the one-time disclosure**

Replace the whole `updatesGroup` (`GeneralSectionView.swift:132-142`) with the version below, add `import AppKit` above `import SwiftUI` at the top of the file (`NSAlert` is AppKit), and add the two new keys **before** writing this code:

```text
"settings.updates.mirrors.confirm" = "Enable mirrors";
"settings.updates.mirrors.cancel" = "Keep GitHub only";
```

```text
"settings.updates.mirrors.confirm" = "启用镜像";
"settings.updates.mirrors.cancel" = "仅使用 GitHub";
```

```text
"settings.updates.mirrors.confirm" = "啟用鏡像";
"settings.updates.mirrors.cancel" = "僅使用 GitHub";
```

```text
"settings.updates.mirrors.confirm" = "ミラーを有効にする";
"settings.updates.mirrors.cancel" = "GitHub のみを使う";
```

```text
"settings.updates.mirrors.confirm" = "미러 사용";
"settings.updates.mirrors.cancel" = "GitHub만 사용";
```

```text
"settings.updates.mirrors.confirm" = "Spiegel aktivieren";
"settings.updates.mirrors.cancel" = "Nur GitHub verwenden";
```

```text
"settings.updates.mirrors.confirm" = "Activar espejos";
"settings.updates.mirrors.cancel" = "Usar solo GitHub";
```

```text
"settings.updates.mirrors.confirm" = "Activer les miroirs";
"settings.updates.mirrors.cancel" = "Utiliser GitHub uniquement";
```

```text
"settings.updates.mirrors.confirm" = "Attiva i mirror";
"settings.updates.mirrors.cancel" = "Usa solo GitHub";
```

```text
"settings.updates.mirrors.confirm" = "Ativar espelhos";
"settings.updates.mirrors.cancel" = "Usar apenas o GitHub";
```

```text
"settings.updates.mirrors.confirm" = "Включить зеркала";
"settings.updates.mirrors.cancel" = "Только GitHub";
```

```text
"settings.updates.mirrors.confirm" = "تفعيل المرايا";
"settings.updates.mirrors.cancel" = "استخدام GitHub فقط";
```

Add the matching enum cases after `settingsUpdatesMirrorsDescription`:

```swift
    case settingsUpdatesMirrorsConfirm = "settings.updates.mirrors.confirm"
    case settingsUpdatesMirrorsCancel = "settings.updates.mirrors.cancel"
```

Then the view:

```swift
    private var updatesGroup: some View {
        SettingsGroup(localization.string(.settingsUpdatesTitle)) {
            SettingsToggleRow(
                symbol: "arrow.triangle.2.circlepath",
                tint: .green,
                title: localization.string(.settingsUpdatesAutomatic),
                isOn: updaterManager.automaticallyChecksForUpdatesBinding
            )

            SettingsDivider()

            SettingsToggleRow(
                symbol: "arrow.triangle.2.circlepath.circle",
                tint: .orange,
                title: localization.string(.settingsUpdatesMirrors),
                subtitle: localization.string(.settingsUpdatesMirrorsDescription),
                isOn: Binding(
                    get: { store.allowsUpdateMirrors },
                    set: { newValue in
                        guard newValue else {
                            store.allowsUpdateMirrors = false
                            return
                        }
                        guard store.hasAcknowledgedUpdateMirrorDisclosure
                            || confirmUpdateMirrorDisclosure() else { return }
                        store.enableUpdateMirrorsAfterDisclosure()
                    }
                )
            )
        }
    }

    /// One-time disclosure. `SettingsStore` refuses to store `true` without the
    /// acknowledgement, so cancelling here cannot silently enable the relays.
    private func confirmUpdateMirrorDisclosure() -> Bool {
        let alert = NSAlert()
        alert.messageText = localization.string(.settingsUpdatesMirrors)
        alert.informativeText = localization.string(.settingsUpdatesMirrorsDescription)
        alert.alertStyle = .warning
        alert.addButton(withTitle: localization.string(.settingsUpdatesMirrorsConfirm))
        alert.addButton(withTitle: localization.string(.settingsUpdatesMirrorsCancel))
        return alert.runModal() == .alertFirstButtonReturn
    }
```

- [ ] **Step 6: Run the tests and verify GREEN**

```bash
swift test --filter LocalizationTests
swift test --filter SettingsStoreTests
```

Expected: all PASS, including `testEveryLanguageHasEveryNonEmptyKey` (all 12 files now carry all four new keys) and `testUpdateMirrorDisclosureNamesBothRelays`.

- [ ] **Step 7: Commit**

```bash
git add Sources/StatusTrioCore/Localization/LocalizationKey.swift \
        Sources/StatusTrioCore/Resources \
        Sources/StatusTrioCore/UI/Settings/GeneralSectionView.swift \
        Tests/StatusTrioCoreTests/LocalizationTests.swift
git commit -m "feat: disclose the third-party update relays in Settings"
```

---

### Task 5: Release notes for the new setting

**Files:**
- Modify: `release-notes/1.3.0/en.md`, `release-notes/1.3.0/zh-Hans.md`, `release-notes/1.3.0/ar.md`, `de.md`, `es.md`, `fr.md`, `it.md`, `ja.md`, `ko.md`, `pt-BR.md`, `ru.md`, `zh-Hant.md`

**Interfaces:**
- Consumes: the setting and copy from Tasks 3 and 4.
- Produces: the user-facing note that mirrors are now opt-in, in every language the app ships.

- [ ] **Step 1: Add the English and Simplified Chinese entries**

Append to `release-notes/1.3.0/en.md`:

```markdown
## Update checks no longer switch hosts on their own
- Status Trio used to fall back to third-party relays when GitHub could not be reached, without asking and without saying so. That fallback now only happens if you turn it on: Settings › General › Updates has a new switch, off by default, that names the two relays.
- Turning it on shows a one-time explanation first. If you leave it off, update checks contact GitHub only, and an unreachable GitHub reports an error instead of quietly routing your request elsewhere.
- Dropped connections and certificate errors never trigger a fallback, so a network that interferes with the GitHub connection can no longer move the update check to a different host.
```

Append to `release-notes/1.3.0/zh-Hans.md`:

```markdown
## 检查更新不再自行切换主机
- 以前 GitHub 无法访问时，Status Trio 会直接改用第三方中继，既不询问也不说明。现在只有在你主动开启时才会这样：设置 › 通用 › 更新 新增了一个默认关闭的开关，并在其中写明使用哪两个中继。
- 开启前会先显示一次性说明。保持关闭时，检查更新只访问 GitHub；GitHub 无法访问会直接报错，而不会悄悄把请求转到别处。
- 连接中断和证书错误都不会触发切换，因此干扰 GitHub 连接的网络无法再把更新检查引到其他主机。
```

- [ ] **Step 2: Add the remaining ten languages**

Append to `release-notes/1.3.0/zh-Hant.md`:

```markdown
## 檢查更新不再自行切換主機
- 以前 GitHub 無法連線時，Status Trio 會直接改用第三方中繼，既不詢問也不說明。現在只有在你主動開啟時才會如此：設定 › 一般 › 更新 新增了一個預設關閉的開關，並在其中寫明使用哪兩個中繼。
- 開啟前會先顯示一次性說明。保持關閉時，檢查更新只連線 GitHub；GitHub 無法連線會直接顯示錯誤，而不會悄悄把請求轉到別處。
- 連線中斷與憑證錯誤都不會觸發切換，因此干擾 GitHub 連線的網路無法再把更新檢查引到其他主機。
```

Append to `release-notes/1.3.0/ja.md`:

```markdown
## 更新確認が接続先を勝手に切り替えなくなりました
- これまで GitHub に接続できないとき、Status Trio は確認も説明もなくサードパーティの中継に切り替えていました。切り替えは、設定 › 一般 › アップデート に追加した既定オフのスイッチをオンにした場合だけ行います。スイッチには中継の名前を明記しています。
- オンにするときは最初に一度だけ説明を表示します。オフのままなら更新確認は GitHub にだけ接続し、GitHub に接続できない場合はエラーを表示します。要求先が黙って変わることはありません。
- 接続の切断や証明書エラーでは切り替えを行わないため、GitHub への接続を妨害するネットワークが更新確認を別のホストへ誘導することはできません。
```

Append to `release-notes/1.3.0/ko.md`:

```markdown
## 업데이트 확인이 임의로 호스트를 바꾸지 않습니다
- 이전에는 GitHub에 연결할 수 없으면 묻지도 알리지도 않고 서드파티 중계로 넘어갔습니다. 이제는 설정 › 일반 › 업데이트에 추가된 기본 꺼짐 스위치를 직접 켠 경우에만 전환합니다. 스위치에는 어느 중계를 쓰는지 적혀 있습니다.
- 켤 때는 처음 한 번 설명을 보여 줍니다. 꺼 두면 업데이트 확인은 GitHub에만 연결하며, GitHub에 연결할 수 없으면 오류를 표시합니다. 요청 대상이 조용히 바뀌지 않습니다.
- 연결 끊김이나 인증서 오류로는 전환하지 않으므로, GitHub 연결을 방해하는 네트워크가 업데이트 확인을 다른 호스트로 유도할 수 없습니다.
```

Append to `release-notes/1.3.0/de.md`:

```markdown
## Update-Prüfungen wechseln nicht mehr von selbst den Host
- Bisher ist Status Trio ohne Nachfrage und ohne Hinweis auf Relays von Drittanbietern ausgewichen, wenn GitHub nicht erreichbar war. Das passiert nur noch, wenn du es einschaltest: Unter Einstellungen › Allgemein › Updates gibt es einen neuen, standardmäßig ausgeschalteten Schalter, der beide Relays nennt.
- Beim Einschalten erscheint zuerst eine einmalige Erklärung. Ausgeschaltet kontaktiert die Update-Prüfung nur GitHub; ist GitHub nicht erreichbar, erscheint ein Fehler, statt die Anfrage still umzuleiten.
- Abgebrochene Verbindungen und Zertifikatsfehler lösen nie einen Wechsel aus. Ein Netz, das die GitHub-Verbindung stört, kann die Update-Prüfung also nicht mehr auf einen anderen Host lenken.
```

Append to `release-notes/1.3.0/es.md`:

```markdown
## Las comprobaciones de actualización ya no cambian de servidor por su cuenta
- Antes, cuando GitHub no estaba disponible, Status Trio pasaba a relés de terceros sin preguntar y sin decirlo. Ahora eso solo ocurre si lo activas tú: Ajustes › General › Actualizaciones tiene un interruptor nuevo, desactivado por omisión, que indica cuáles son los dos relés.
- Al activarlo se muestra primero una explicación única. Si lo dejas desactivado, la comprobación de actualizaciones solo contacta con GitHub, y si GitHub no está disponible se muestra un error en lugar de desviar la solicitud en silencio.
- Las conexiones cortadas y los errores de certificado nunca provocan un cambio, así que una red que interfiera en la conexión con GitHub ya no puede llevar la comprobación a otro servidor.
```

Append to `release-notes/1.3.0/fr.md`:

```markdown
## La recherche de mises à jour ne change plus d’hôte toute seule
- Auparavant, lorsque GitHub était injoignable, Status Trio basculait vers des relais tiers sans demander ni le signaler. Cela n’arrive plus que si vous l’activez : Réglages › Général › Mises à jour propose un nouveau commutateur, désactivé par défaut, qui nomme les deux relais.
- L’activation affiche d’abord une explication unique. Désactivé, la recherche de mises à jour ne contacte que GitHub ; si GitHub est injoignable, une erreur s’affiche au lieu de détourner la requête en silence.
- Les connexions interrompues et les erreurs de certificat ne déclenchent jamais de bascule : un réseau qui perturbe la connexion à GitHub ne peut donc plus déplacer la recherche vers un autre hôte.
```

Append to `release-notes/1.3.0/it.md`:

```markdown
## Il controllo aggiornamenti non cambia più host da solo
- Prima, quando GitHub non era raggiungibile, Status Trio passava a relay di terze parti senza chiedere e senza dirlo. Ora succede solo se lo attivi: Impostazioni › Generale › Aggiornamenti ha un nuovo interruttore, disattivato per impostazione predefinita, che indica quali sono i due relay.
- All’attivazione viene mostrata prima una spiegazione una tantum. Se lo lasci disattivato, il controllo aggiornamenti contatta solo GitHub; se GitHub non è raggiungibile viene mostrato un errore invece di deviare la richiesta in silenzio.
- Le connessioni interrotte e gli errori di certificato non attivano mai un passaggio, quindi una rete che interferisce con la connessione a GitHub non può più spostare il controllo su un altro host.
```

Append to `release-notes/1.3.0/pt-BR.md`:

```markdown
## A verificação de atualizações não troca mais de servidor sozinha
- Antes, quando o GitHub estava inacessível, o Status Trio passava para relays de terceiros sem perguntar e sem avisar. Agora isso só acontece se você ativar: Ajustes › Geral › Atualizações tem um novo interruptor, desligado por padrão, que informa quais são os dois relays.
- Ao ativar, uma explicação única é exibida primeiro. Se ficar desligado, a verificação de atualizações contata apenas o GitHub; se o GitHub estiver inacessível, um erro é exibido em vez de desviar a solicitação em silêncio.
- Conexões interrompidas e erros de certificado nunca provocam troca, então uma rede que interfira na conexão com o GitHub não pode mais levar a verificação para outro servidor.
```

Append to `release-notes/1.3.0/ru.md`:

```markdown
## Проверка обновлений больше не меняет узел сама
- Раньше, когда GitHub был недоступен, Status Trio переключалась на сторонние посредники без запроса и без предупреждения. Теперь это происходит только если вы включите: в разделе Настройки › Основные › Обновления появился новый переключатель, выключенный по умолчанию, в котором названы оба посредника.
- При включении сначала показывается однократное пояснение. Если оставить его выключенным, проверка обновлений обращается только к GitHub; при недоступности GitHub появляется ошибка, а запрос не перенаправляется молча.
- Обрывы соединения и ошибки сертификата никогда не вызывают переключение, поэтому сеть, мешающая соединению с GitHub, больше не может увести проверку на другой узел.
```

Append to `release-notes/1.3.0/ar.md`:

```markdown
## لم يعد التحقق من التحديثات يبدّل الخادم من تلقاء نفسه
- سابقًا، عندما تعذّر الوصول إلى GitHub، كانت Status Trio تنتقل إلى وسيطين خارجيين دون سؤال ودون إخبار. الآن لا يحدث ذلك إلا إذا شغّلت الخيار بنفسك: في الإعدادات › عام › التحديثات مفتاح جديد متوقف افتراضيًا يوضّح اسمي الوسيطين.
- عند التشغيل يظهر أولًا شرح لمرة واحدة. وإذا بقي متوقفًا، فلا يتصل التحقق من التحديثات إلا بـ GitHub؛ وعند تعذّر الوصول إليه يظهر خطأ بدل تحويل الطلب بصمت.
- لا تؤدي الاتصالات المقطوعة ولا أخطاء الشهادات إلى أي تبديل، لذا لم تعد شبكة تعترض الاتصال بـ GitHub قادرة على توجيه التحقق إلى خادم آخر.
```

- [ ] **Step 3: Validate the notes and the item they generate**

```bash
VERSION=1.3.0 BUILD=12 bash scripts/validate-appcast-notes.sh
```

Expected: `Release notes coverage for 1.3.0: 12/12 languages`, then `Appcast notes OK: 12 titles and 12 descriptions, en first.`

- [ ] **Step 4: Commit**

```bash
git add release-notes/1.3.0
git commit -m "docs: note that update mirrors are now opt-in"
```

---

### Task 6: Full verification

**Files:**
- No production files.

- [ ] **Step 1: Run the full test suite**

```bash
swift test
```

Expected: all tests pass, including the new fallback, settings, manager and localization tests.

- [ ] **Step 2: Run the release build**

```bash
swift build -c release
```

Expected: successful build.

- [ ] **Step 3: Confirm nothing reaches a mirror while the setting is off**

```bash
plutil -p Support/Info.plist | grep -E "SUFeedURL|SUPublicEDKey|SURequireSignedFeed|SUVerifyUpdateBeforeExtraction"
grep -rn "SUAllowsInsecureUpdates" Sources/ Support/ scripts/ || echo "no SUAllowsInsecureUpdates"
defaults read com.lingsmbp.StatusTrio allowsUpdateMirrors 2>&1 || echo "no stored mirror preference (mirrors off)"
```

Expected: the pinned key, the HTTPS GitHub feed URL, and `SURequireSignedFeed => 1` all present; `no SUAllowsInsecureUpdates`; the last command reports that the preference is absent, which reads as off.

- [ ] **Step 4: Run a non-publishing release preflight**

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref "$(git branch --show-current)" \
  -f version=1.3.0 \
  -f build=12 \
  -f publish=false

gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

Expected: the workflow passes; `Validate appcast notes` prints `Appcast notes OK`; `Run tests` includes the new test names. This runs the real `UpdaterManager` construction path, which is the only place the manager wiring from Task 3 is exercised end to end, since `UpdaterManager.start` returns early under `#if DEBUG` (`UpdaterManager.swift:49-51`) and `feedURLString(for:)` reads `Bundle.main` rather than an injected value.

- [ ] **Step 5: Observe the GitHub-only failure path by hand**

The unit tests pin the decision; this pins what the user sees.

1. Note the paths in Settings › General › Updates: the new switch is visible and off.
2. Turn off Wi-Fi and Ethernet so `raw.githubusercontent.com` cannot resolve, then choose “Check for Updates…” from the menu bar.
3. Expect Sparkle's standard update-check error alert. With no next source, `canAdvanceAfterError` is false (`UpdateSourceFallback.swift:67-80` over a one-element source list), so `UpdateFallbackUserDriver.showUpdaterError` does not acknowledge the error away (`UpdateFallbackUserDriver.swift:22-25`).
4. Restore the network, turn the switch on, and confirm the one-time disclosure names `gh-proxy.com` and `ghfast.top` before the switch stays on. Cancel once and confirm the switch stays off.

Record the observed alert text in the pull request or commit message.

- [ ] **Step 6: Record any failed CI run**

If CI fails, append a row to `docs/swift-ci-compatibility.md` with the run ID, failed stage, reproducible root cause, fix and verification run, per `docs/swift-ci-compatibility.md:44-54`.

- [ ] **Step 7: Review the diff**

```bash
git status --short
git diff --check
```

Expected: only the files listed in Task 1–5 `Files:` blocks, with no whitespace errors.

## Verification

1. `swift test` and `swift build -c release` pass on the CI toolchain (`macos-26`, Xcode 26.6, Swift 6.3.3).
2. `UpdateSourceFallbackTests` proves: cancellation and every TLS/ATS code refuse to advance, wrapped TLS failures inside `SUAppcastError` refuse to advance, transient errors still advance when mirrors are enabled, and the GitHub-only list never rewrites a URL.
3. `SettingsStoreTests` proves the default is off, that `true` cannot be stored before the disclosure, and that the disclosure is remembered.
4. `UpdaterManagerTests/mirrorChoiceIsRecomputedForEveryCycle` proves the per-cycle rebuild and that opting out takes effect on the next cycle.
5. `LocalizationTests` proves all 12 languages carry the two new strings and that each description names both relays and GitHub.
6. `VERSION=1.3.0 BUILD=12 bash scripts/validate-appcast-notes.sh` prints `Appcast notes OK`.
7. The non-publishing preflight passes and Task 6 Step 5 records the two observed user-visible outcomes.

## Out of Scope

- **Removing the relays entirely.** Rejected in favour of opt-in: the relays exist for users whose network blocks GitHub, and deleting them would be a silent feature removal. Opt-in keeps that path available while making it a decision the user makes. The disclosure copy is the compensating control.
- **A bespoke “update check could not reach GitHub” alert.** `UpdateFallbackUserDriver` replaces Sparkle's presenter wholesale when `presentUpdaterError` is supplied (`UpdateFallbackUserDriver.swift:27-31`), so a custom network-error message would also swallow Sparkle's exact wording for signature and validation failures, which must not be softened or reworded. Sparkle's standard alert already surfaces the failure once suppression is off, and the clearer explanation lives in the settings disclosure. Adding a fallthrough-capable presenter is a separate change.
- **Signed feeds.** Owned by plan R-08 (`2026-09-20-signed-update-feed.md`). This plan removes the *route* to an unauthenticated feed; R-08 removes the *possibility*. R-08 lands first per the index, and this plan must not remove `SURequireSignedFeed`, `SUVerifyUpdateBeforeExtraction` or `SUPublicEDKey`.
- **`SUSparkleErrorDomain` `noUpdateError`/`signatureError` handling.** Already correct — both refuse to advance (`UpdateSourceFallbackTests.swift:139-157`) and stay untouched.
- **Logging mirror switches.** Considered and dropped: the codebase has three `Logger` instances, all in monitors, and a log line here would be unassertable. The switch is instead visible in the UI state and in `defaults read com.lingsmbp.StatusTrio allowsUpdateMirrors`.
- **Retrying the check automatically after the network returns.** Not requested by the review and not needed: Sparkle's own scheduled checks run again on the next interval.

## File Ownership & Conflicts

**Owned by this plan**

| File | Change |
| --- | --- |
| `Sources/StatusTrioCore/App/UpdateSourceFallback.swift` | deny-list in the retry policy, `mirrorSources`, `resetForNewCycle()`, `defaultSources(allowsMirrors:)` |
| `Sources/StatusTrioCore/App/UpdaterManager.swift` | internal fallback + `settings`, `beginNewSourceCycle()`, `start(activationPolicy:settings:)` |
| `Sources/StatusTrioCore/App/AppDelegate.swift` | pass `environment.settings` to `start` (one line) |
| `Sources/StatusTrioCore/Settings/SettingsStore.swift` | `allowsUpdateMirrors`, `hasAcknowledgedUpdateMirrorDisclosure`, `enableUpdateMirrorsAfterDisclosure()` |
| `Sources/StatusTrioCore/Localization/LocalizationKey.swift` | four new keys |
| `Sources/StatusTrioCore/Resources/*.lproj/Localizable.strings` | four new strings × 12 languages |
| `Sources/StatusTrioCore/UI/Settings/GeneralSectionView.swift` | mirror row + one-time disclosure |
| `Tests/StatusTrioCoreTests/UpdateSourceFallbackTests.swift` | new policy tests, four existing tests relabelled to `mirrorSources` |
| `Tests/StatusTrioCoreTests/UpdaterManagerTests.swift` | cycle test + suite helpers |
| `Tests/StatusTrioCoreTests/SettingsStoreTests.swift` | four new tests |
| `Tests/StatusTrioCoreTests/LocalizationTests.swift` | two new tests |
| `release-notes/1.3.0/*.md` | one section × 12 languages |

**Conflicts with other plans in this set** (matrix: `2026-09-20-review-findings-index.md` §3.1)

- **R-08 (`2026-09-20-signed-update-feed.md`) — same trust chain, opposite direction.** R-08 owns `Support/Info.plist`, `appcast.xml`, `scripts/release.sh`, `scripts/update-appcast.rb` and `Tests/StatusTrioCoreTests/SignedUpdateFeedTests.swift`; this plan touches none of them. R-08 lands first per the index, and both plans keep `SUPublicEDKey` pinned. This plan's Task 6 Step 3 re-asserts that the plist keys R-08 adds are still present, so a rebase that drops them fails loudly.
- **R-13 (`2026-09-20-single-instance-and-pasteboard.md`) — also touches `release-notes/1.3.0/*`.** Two workers must not append to the same release-notes files at the same time. Whichever lands second rebases the notes; the sections are independent and both must survive, because `publish=true` requires all 12 languages to exist (they do) and the appcast item stacks every section in the file.
- **R-03 (`2026-09-20-status-poll-scheduling.md`) — also touches `Settings/SettingsStore.swift`.** R-03 owns `refreshIntervalSeconds` and the poll loop; this plan owns the two mirror properties and `enableUpdateMirrorsAfterDisclosure()`. The regions do not overlap (`SettingsStore.swift:45-47` and `:260-269` for R-03, `:6-8`, `:260-269` neighbours and `:468-496` for this plan), but the two must not be edited in parallel; land R-03 first if both are in flight in the same wave, since it is listed in Wave 1 and this plan is in Wave 3.
- **R-10 (`2026-09-20-release-pipeline-hardening.md`) — `.github/workflows/release.yml`.** Not touched here.
