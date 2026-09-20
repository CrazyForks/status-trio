# Keychain Hardening Implementation Plan

> **STATUS: DEFERRED — needs a conservative rollout (owner decision, 2026-09-20).** This plan migrates Wi-Fi passwords that users have already saved. A mistake costs a user a remembered credential or produces a fresh authorisation prompt, so it must keep the legacy read fallback forever, must never delete an old item before a verified read-back, and should ship only when the owner can watch the first release that contains it. See `2026-09-20-review-findings-index.md` §0.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Wi-Fi credential store ask for the keychain protection it actually gets, migrate already-stored passwords into the data-protection keychain without losing them, replace the two Security APIs deprecated in macOS 11, and put every credential-resolution decision behind an injectable seam so the untested system-keychain fallback and each error mapping are pinned by tests.

**Architecture:** `KeychainWiFiPasswordStore` stops calling `SecItem*` directly and takes a `KeychainAccessing` collaborator (production: `SystemKeychain`; tests: an in-memory double). A `KeychainBackend` value — `.dataProtection` or `.legacyLogin` — is resolved once at first use by a single probe against the data-protection keychain, because on macOS the data-protection keychain is gated on code-signing entitlements and this app is Ad-hoc signed. The store keeps the same public `resolveCredential(for:)` / `save(_:for:)` contract and the same user-visible outcomes; a one-shot migration copies any pre-existing legacy item into the data-protection keychain and only removes the legacy copy after the new copy has been read back successfully.

**Tech Stack:** Swift 6-compatible SwiftPM package (`swift-tools-version: 6.0`, `platforms: [.macOS(.v15)]`), Security.framework, LocalAuthentication.framework, XCTest, `os.Logger`.

**Spec:** Derived from the 2026-09-20 security review; cross-plan index: docs/superpowers/plans/2026-09-20-review-findings-index.md (finding **R-12**)

## Global Constraints

- CI acceptance toolchain is the `macos-26` runner with Xcode 26.6 / Swift 6.3.3; local Xcode 27 / Swift 6.4 is not proof.
- Forbidden in this repo: `isolated deinit`, `weak let` (use `weak var`), passing actor-isolated methods directly as function values (use an explicit closure), assuming `Bundle.module` casing.
- The app is Ad-hoc signed and not notarized; anything relying on a Team ID or a stable code-signing identity must be written as a conditional follow-up, not an assumption.
- Run `swift test` and `swift build -c release` before committing Swift changes.
- A non-publishing release preflight is mandatory if a change touches actor isolation, `@MainActor`, `deinit`, SwiftUI bindings, generics, or `Bundle.module` resources: `gh workflow run release.yml --repo lingyired/status-trio --ref <branch> -f version=1.3.0 -f build=12 -f publish=false` then `gh run watch <run-id> --repo lingyired/status-trio --exit-status`. This plan touches `@MainActor` types (`WiFiNetworkController` calls into the store), so the preflight is mandatory.
- Any user-visible behavior change needs release notes added to the existing unreleased `release-notes/1.3.0/en.md` and `release-notes/1.3.0/zh-Hans.md`.
- Secrets must never be logged, never stored in `UserDefaults`, never interpolated into strings that could reach `os_log`, and never retained longer than needed.
- Tests are mixed Swift Testing / XCTest; match the file you extend. `Tests/StatusTrioCoreTests/WirelessListModelsTests.swift` is XCTest, so its new tests use `XCTAssert*`.
- Never create, read, or delete real keychain items while working on this plan. The only exception is the existing smoke test, which already creates its own item under a random service name and deletes it in a `defer`.

## Review Focus

- A user who saved a password in an earlier build must still get it back after the app moves to the data-protection keychain. Pinned by `KeychainWiFiPasswordStoreTests/testLegacyItemIsMigratedAndRemovedOnlyAfterVerification`.
- A background scan must never raise an authentication prompt. Pinned by `KeychainWiFiPasswordStoreTests/testAppReadNeverPrompts` (asserts the context handed to the seam has `interactionNotAllowed == true` and an empty `localizedReason`).
- The explicit user click that asks the system `AirPort network password` item must still be allowed to show the system prompt. Pinned by `KeychainWiFiPasswordStoreTests/testSystemReadAllowsInteraction`.
- A locked keychain and a denied read must stay distinguishable, because the UI shows different text for each. Pinned by `KeychainWiFiPasswordStoreTests/testErrorMappingStaysDistinct` covering `errSecUserCanceled`, `errSecAuthFailed`, `errSecInteractionNotAllowed`, `errSecNotAvailable` and an unknown OSStatus.
- On an Ad-hoc signed build the data-protection keychain may be refused; the app must fall back to the legacy keychain and keep working rather than lose the password. Pinned by `KeychainWiFiPasswordStoreTests/testDataProtectionRefusalFallsBackToLegacy`.

---

### Task 1: Introduce The `KeychainAccessing` Seam

**Files:**
- Create: `Tests/StatusTrioCoreTests/KeychainWiFiPasswordStoreTests.swift`
- Modify: `Sources/StatusTrioCore/Monitoring/WiFiPasswordStore.swift`

**Interfaces:**
- Produces: `protocol KeychainAccessing: AnyObject` with the four members below.
- Produces: `final class SystemKeychain: KeychainAccessing`.
- Produces: `KeychainWiFiPasswordStore(access:any KeychainAccessing = SystemKeychain(), appService: String = "com.lingsmbp.StatusTrio.wifi-password")`. The `appService` parameter keeps the label it has today so the existing smoke test keeps compiling.
- Consumes nothing from the other plans in this set.

The seam is deliberately raw. It returns `OSStatus` and hands back an opaque `CFTypeRef?` so the store — not the double — owns every mapping from a status code and a value to `WiFiCredentialResult`. A seam that returned `WiFiCredentialResult` would move the logic under test into the test double.

```swift
protocol KeychainAccessing: AnyObject {
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: CFTypeRef?)
    @discardableResult func add(_ attributes: [String: Any]) -> OSStatus
    @discardableResult func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    @discardableResult func delete(_ query: [String: Any]) -> OSStatus
}
```

- [ ] **Step 1: Write failing seam tests**

Create `Tests/StatusTrioCoreTests/KeychainWiFiPasswordStoreTests.swift`:

```swift
import Foundation
import Security
import XCTest
@testable import StatusTrioCore

/// The store's status codes and queries are inspected by an in-memory double, so
/// no test in this file touches a real keychain.
final class InMemoryKeychain: KeychainAccessing {
    struct Entry: Equatable {
        let service: String
        let account: String
        let data: Data
        var accessibility: String?
        var useDataProtection: Bool
    }

    var entries: [Entry] = []
    /// OSStatus forced for every `copyMatching` call, keyed by service.
    var copyStatusByService: [String: OSStatus] = [:]
    /// OSStatus forced for the data-protection probe only.
    var dataProtectionProbeStatus: OSStatus = errSecSuccess
    /// True when the backend is asked to write a data-protection item, so the
    /// probe answer and the write answer can differ.
    var acceptsDataProtectionWrites = true

    private(set) var queries: [[String: Any]] = []
    private(set) var contexts: [LAContext] = []

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: CFTypeRef?) {
        queries.append(query)
        if let context = query[kSecUseAuthenticationContext as String] as? LAContext {
            contexts.append(context)
        }
        guard let service = query[kSecAttrService as String] as? String else {
            return (errSecParam, nil)
        }
        if let forced = copyStatusByService[service] { return (forced, nil) }

        let account = query[kSecAttrAccount as String] as? String
        let matches = entries.filter {
            $0.service == service && (account == nil || $0.account == account)
        }
        guard !matches.isEmpty else { return (errSecItemNotFound, nil) }

        // `kSecReturnData` is how a read asks for the password; the attribute
        // form is how an enumeration asks which accounts exist.
        if query[kSecReturnData as String] as? Bool == true {
            return (errSecSuccess, matches[0].data as CFTypeRef)
        }
        let limitOne = (query[kSecMatchLimit as String] as? String) == (kSecMatchLimitOne as String)
        let rows: [[String: Any]] = (limitOne ? [matches[0]] : matches).map {
            [
                kSecAttrService as String: $0.service,
                kSecAttrAccount as String: $0.account
            ]
        }
        // A CFArray bridged through NSArray comes back out of `as? [[String: Any]]`
        // at the call site, which is what the migration enumerates.
        return (errSecSuccess, rows as NSArray)
    }

    @discardableResult func add(_ attributes: [String: Any]) -> OSStatus {
        let usesDataProtection = attributes[kSecUseDataProtectionKeychain as String] as? Bool == true
        if usesDataProtection && !acceptsDataProtectionWrites { return errSecMissingEntitlement }
        guard let service = attributes[kSecAttrService as String] as? String,
              let account = attributes[kSecAttrAccount as String] as? String,
              let data = attributes[kSecValueData as String] as? Data else { return errSecParam }
        guard !entries.contains(where: { $0.service == service && $0.account == account }) else {
            return errSecDuplicateItem
        }
        entries.append(Entry(
            service: service,
            account: account,
            data: data,
            accessibility: attributes[kSecAttrAccessible as String] as? String,
            useDataProtection: usesDataProtection
        ))
        return errSecSuccess
    }

    @discardableResult func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        guard let service = query[kSecAttrService as String] as? String,
              let account = query[kSecAttrAccount as String] as? String,
              let data = attributes[kSecValueData as String] as? Data else { return errSecParam }
        guard let index = entries.firstIndex(where: { $0.service == service && $0.account == account }) else {
            return errSecItemNotFound
        }
        entries[index].data = data
        if let accessibility = attributes[kSecAttrAccessible as String] as? String {
            entries[index].accessibility = accessibility
        }
        return errSecSuccess
    }

    @discardableResult func delete(_ query: [String: Any]) -> OSStatus {
        guard let service = query[kSecAttrService as String] as? String,
              let account = query[kSecAttrAccount as String] as? String else { return errSecParam }
        let before = entries.count
        entries.removeAll { $0.service == service && $0.account == account }
        return entries.count == before ? errSecItemNotFound : errSecSuccess
    }
}

final class KeychainWiFiPasswordStoreTests: XCTestCase {
    private let appService = "com.lingsmbp.StatusTrio.wifi-password.test"
    private let identity = WiFiNetworkIdentity(ssid: "Studio", security: .wpa2Personal)
    private var account: String { "\(identity.security.rawValue):\(identity.ssid)" }

    func testAppItemHitReturnsAppCredential() {
        let keychain = InMemoryKeychain()
        keychain.entries = [
            .init(service: appService, account: account, data: Data("app-password".utf8), accessibility: nil, useDataProtection: true)
        ]
        let store = KeychainWiFiPasswordStore(access: keychain, appService: appService)
        XCTAssertEqual(
            store.resolveCredential(for: identity),
            .credential("app-password", .appKeychain)
        )
    }

    func testMissingAppItemFallsThroughToSystemItem() {
        let keychain = InMemoryKeychain()
        keychain.entries = [
            .init(service: "AirPort network password", account: identity.ssid, data: Data("system-password".utf8), accessibility: nil, useDataProtection: false)
        ]
        let store = KeychainWiFiPasswordStore(access: keychain, appService: appService)
        XCTAssertEqual(
            store.resolveCredential(for: identity),
            .credential("system-password", .systemKeychain)
        )
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

Run: `swift test --filter KeychainWiFiPasswordStoreTests`
Expected: compile failure — `cannot find type 'KeychainAccessing' in scope` and `extra argument 'access' in call`.

- [ ] **Step 3: Add the seam and route every `SecItem*` call through it**

In `Sources/StatusTrioCore/Monitoring/WiFiPasswordStore.swift`, add:

```swift
/// The four `SecItem` calls the store makes, behind a protocol so the
/// resolution logic can be exercised without a real keychain.
protocol KeychainAccessing: AnyObject {
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: CFTypeRef?)
    @discardableResult func add(_ attributes: [String: Any]) -> OSStatus
    @discardableResult func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    @discardableResult func delete(_ query: [String: Any]) -> OSStatus
}

final class SystemKeychain: KeychainAccessing {
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: CFTypeRef?) {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item)
    }

    @discardableResult func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    @discardableResult func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    @discardableResult func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}
```

Change the store's stored properties and initializer to:

```swift
private let access: any KeychainAccessing
private let appService: String
private let systemAirPortService = "AirPort network password"

init(
    access: any KeychainAccessing = SystemKeychain(),
    appService: String = "com.lingsmbp.StatusTrio.wifi-password"
) {
    self.access = access
    self.appService = appService
}
```

Rewrite the body of the private `read(query:source:)` (currently lines 69-94) to call `access.copyMatching(query)` instead of `SecItemCopyMatching`, and rewrite `save(_:for:)` (lines 48-67) to call `access.update` and `access.add`. Keep the status-code switch exactly as it is, including the `errSecUserCanceled` → `.issue(.cancelled)`, `errSecAuthFailed` → `.issue(.accessDenied)`, and `errSecInteractionNotAllowed, errSecNotAvailable` → `.issue(.keychainLocked)` arms.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `swift test --filter KeychainWiFiPasswordStoreTests`
Expected: 2 tests pass. Then run `swift test --filter WirelessListModelsTests` and confirm the pre-existing `testKeychainPasswordStoreAddsReadsUpdatesAndCleansItsOwnItem` still passes against the real login keychain.

- [ ] **Step 5: Commit**

```bash
git add Sources/StatusTrioCore/Monitoring/WiFiPasswordStore.swift \
        Tests/StatusTrioCoreTests/KeychainWiFiPasswordStoreTests.swift
git commit -m "refactor: put Wi-Fi keychain access behind a KeychainAccessing seam"
```

---

### Task 2: Pin Fall-Through, Every Error Mapping, And A Round Trip

**Files:**
- Modify: `Tests/StatusTrioCoreTests/KeychainWiFiPasswordStoreTests.swift`

**Interfaces:**
- Consumes: `KeychainAccessing`, `InMemoryKeychain` from Task 1.
- Produces: no new production interface.

- [ ] **Step 1: Write the tests**

Append to `KeychainWiFiPasswordStoreTests`:

```swift
    func testBothNamespacesMissingReturnsNoCredential() {
        let store = KeychainWiFiPasswordStore(access: InMemoryKeychain(), appService: appService)
        XCTAssertEqual(store.resolveCredential(for: identity), .noCredential)
    }

    func testAppFailureIsNotMaskedByTheSystemFallback() {
        // A cancelled prompt on the app item must not silently become a system
        // keychain read that can prompt again.
        let keychain = InMemoryKeychain()
        keychain.copyStatusByService[appService] = errSecUserCanceled
        let store = KeychainWiFiPasswordStore(access: keychain, appService: appService)
        XCTAssertEqual(store.resolveCredential(for: identity), .issue(.cancelled))
        XCTAssertFalse(keychain.queries.contains { query in
            (query[kSecAttrService as String] as? String) == "AirPort network password"
        })
    }

    func testErrorMappingStaysDistinct() {
        let cases: [(OSStatus, WiFiCredentialIssue)] = [
            (errSecUserCanceled, .cancelled),
            (errSecAuthFailed, .accessDenied),
            (errSecInteractionNotAllowed, .keychainLocked),
            (errSecNotAvailable, .keychainLocked),
            (errSecIO, .readFailed)
        ]
        for (status, expected) in cases {
            let keychain = InMemoryKeychain()
            keychain.copyStatusByService[appService] = status
            let store = KeychainWiFiPasswordStore(access: keychain, appService: appService)
            XCTAssertEqual(
                store.resolveCredential(for: identity),
                .issue(expected),
                "OSStatus \(status) must map to \(expected)"
            )
        }
    }

    func testEmptyOrNonUTF8AppItemIsAReadFailure() {
        let keychain = InMemoryKeychain()
        keychain.entries = [
            .init(service: appService, account: account, data: Data(), accessibility: nil, useDataProtection: true)
        ]
        let store = KeychainWiFiPasswordStore(access: keychain, appService: appService)
        XCTAssertEqual(store.resolveCredential(for: identity), .issue(.readFailed))
    }

    func testSaveThenResolveRoundTripSurvivesAnUpdate() {
        let keychain = InMemoryKeychain()
        let store = KeychainWiFiPasswordStore(access: keychain, appService: appService)
        XCTAssertTrue(store.save("first-password", for: identity))
        XCTAssertEqual(store.resolveCredential(for: identity), .credential("first-password", .appKeychain))
        XCTAssertTrue(store.save("second-password", for: identity))
        XCTAssertEqual(store.resolveCredential(for: identity), .credential("second-password", .appKeychain))
        XCTAssertFalse(store.save("", for: identity))
    }

    func testSaveReportsFailureWhenTheKeychainRefuses() {
        let keychain = InMemoryKeychain()
        keychain.acceptsDataProtectionWrites = false
        let store = KeychainWiFiPasswordStore(access: keychain, appService: appService)
        XCTAssertFalse(store.save("password", for: identity))
    }
```

- [ ] **Step 2: Run tests and verify RED**

Run: `swift test --filter KeychainWiFiPasswordStoreTests`
Expected: `testSaveReportsFailureWhenTheKeychainRefuses` fails because the store still writes to the legacy keychain and therefore reports `true`; the other four pass once Task 1 landed.

- [ ] **Step 3: Run tests and verify GREEN after Task 4**

Run: `swift test --filter KeychainWiFiPasswordStoreTests`
Expected: all 8 tests pass once Task 4 makes the store prefer the data-protection backend.

- [ ] **Step 4: Commit**

```bash
git add Tests/StatusTrioCoreTests/KeychainWiFiPasswordStoreTests.swift
git commit -m "test: pin keychain fall-through, error mappings and a save-resolve round trip"
```

---

### Task 3: Replace The Two Deprecated Security APIs With `LAContext`

**Files:**
- Modify: `Sources/StatusTrioCore/Monitoring/WiFiPasswordStore.swift`
- Modify: `Package.swift`
- Modify: `Tests/StatusTrioCoreTests/KeychainWiFiPasswordStoreTests.swift`

**Interfaces:**
- Produces: `KeychainPromptPolicy` with `static func context(allowingInteraction: Bool) -> LAContext`.
- Consumes: `KeychainAccessing` from Task 1.

The current code warns twice:

```
Sources/StatusTrioCore/Monitoring/WiFiPasswordStore.swift:108:52: warning: 'kSecUseAuthenticationUIFail' was deprecated in macOS 11.0
Sources/StatusTrioCore/Monitoring/WiFiPasswordStore.swift:131:48: warning: 'kSecUseAuthenticationUIAllow' was deprecated in macOS 11.0
```

`kSecUseAuthenticationUIFail` behaves like an `LAContext` whose `interactionNotAllowed` is `true`; `kSecUseAuthenticationUIAllow` behaves like the default context, which is `interactionNotAllowed == false`. Both are documented in the macOS SDK header `Security.framework/Headers/SecItem.h` (`kSecUseAuthenticationUI` is `API_DEPRECATED(..., macos(10.11, 11.0))`), and the replacement is allowed from macOS 10.11 — well below this package's `platforms: [.macOS(.v15)]`.

- [ ] **Step 1: Write the failing prompt-policy tests**

Append to `KeychainWiFiPasswordStoreTests`:

```swift
    func testAppReadNeverPrompts() {
        let keychain = InMemoryKeychain()
        keychain.copyStatusByService[appService] = errSecItemNotFound
        let store = KeychainWiFiPasswordStore(access: keychain, appService: appService)
        _ = store.resolveCredential(for: identity)

        let appQuery = try? XCTUnwrap(keychain.queries.first { query in
            (query[kSecAttrService as String] as? String) == appService
        })
        let context = appQuery?[kSecUseAuthenticationContext as String] as? LAContext
        XCTAssertNotNil(context, "the app-owned read must pass an explicit LAContext")
        XCTAssertEqual(context?.interactionNotAllowed, true)
        XCTAssertEqual(context?.localizedReason ?? "", "")
    }

    func testSystemReadAllowsInteraction() {
        let keychain = InMemoryKeychain()
        let store = KeychainWiFiPasswordStore(access: keychain, appService: appService)
        _ = store.resolveCredential(for: identity)

        let systemQuery = keychain.queries.first { query in
            (query[kSecAttrService as String] as? String) == "AirPort network password"
        }
        let context = systemQuery?[kSecUseAuthenticationContext as String] as? LAContext
        XCTAssertNotNil(context, "the system read must pass an explicit LAContext")
        XCTAssertEqual(context?.interactionNotAllowed, false)
    }
```

- [ ] **Step 2: Run tests and verify RED**

Run: `swift test --filter KeychainWiFiPasswordStoreTests`
Expected: both new tests fail with `the app-owned read must pass an explicit LAContext` / `the system read must pass an explicit LAContext`, because the queries still set `kSecUseAuthenticationUI`.

- [ ] **Step 3: Link LocalAuthentication**

Add one line to the `StatusTrioCore` target's `linkerSettings` in `Package.swift`, next to the existing `.linkedFramework("Security")`:

```swift
                .linkedFramework("LocalAuthentication"),
```

- [ ] **Step 4: Swap the deprecated keys for a context**

At the top of `Sources/StatusTrioCore/Monitoring/WiFiPasswordStore.swift`, add `import LocalAuthentication`, then:

```swift
/// The two interaction policies the store needs, expressed as the
/// replacement for the `kSecUseAuthenticationUI*` constants deprecated in
/// macOS 11. A fresh context per call keeps the policy from leaking into an
/// unrelated operation.
enum KeychainPromptPolicy {
    /// Fail rather than prompt. This is the contract for every background scan:
    /// a status read must never put a keychain dialog on screen.
    static func silent() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }

    /// Permit the system prompt. Used only for the Keychain standard
    /// `AirPort network password` item, and only after an explicit click.
    static func interactive() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = false
        return context
    }
}
```

In `appReadQuery(for:)` replace

```swift
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
```

with

```swift
        query[kSecUseAuthenticationContext as String] = KeychainPromptPolicy.silent()
```

In `systemAirPortQuery(for:)` replace

```swift
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIAllow,
```

with

```swift
            kSecUseAuthenticationContext as String: KeychainPromptPolicy.interactive(),
```

Do not change any status-code mapping or any returned `WiFiCredentialResult`; the user-visible outcomes are identical by construction because the context policy matches the deprecated constant it replaces.

- [ ] **Step 5: Run tests and verify GREEN, and confirm the warnings are gone**

Run: `swift test --filter KeychainWiFiPasswordStoreTests`
Expected: 10 tests pass.

Run: `rm -rf /tmp/wc-keychain && swift build --build-tests --scratch-path /tmp/wc-keychain 2>&1 | grep -E "^/.*warning:" | grep WiFiPasswordStore`
Expected: no output — both `kSecUseAuthenticationUI` warnings are gone.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/StatusTrioCore/Monitoring/WiFiPasswordStore.swift \
        Tests/StatusTrioCoreTests/KeychainWiFiPasswordStoreTests.swift
git commit -m "fix: replace deprecated kSecUseAuthenticationUI with an LAContext policy"
```

---

### Task 4: Data-Protection Keychain, `ThisDeviceOnly`, And A Safe Migration

**Files:**
- Modify: `Sources/StatusTrioCore/Monitoring/WiFiPasswordStore.swift`
- Modify: `Tests/StatusTrioCoreTests/KeychainWiFiPasswordStoreTests.swift`

**Interfaces:**
- Produces: `enum KeychainBackend: String, Equatable, Sendable { case dataProtection, legacyLogin }`.
- Produces: `KeychainWiFiPasswordStore.backend` (`private(set) var`, readable for diagnostics).
- Consumes: the seam from Task 1.

**Why the backend has to be probed and cannot be assumed.** On macOS, `kSecAttrAccessible` is honoured only when `kSecUseDataProtectionKeychain` is `true` — the SDK header states that the data-protection flag is what makes `kSecAttrAccessGroup` and `kSecAttrAccessible` apply "on macOS without requiring the item to be marked synchronizable". The data-protection keychain derives its access groups from the app's **code-signing entitlements** (Apple TN3137). This app is Ad-hoc signed with no entitlements file (`scripts/build-app.sh` invokes `codesign` with no `--entitlements`), and a missing keychain entitlement surfaces as `errSecMissingEntitlement (-34018)`. So: request the data-protection keychain, but treat a refusal as a condition to detect at runtime and fall back, never as an assumption. Getting a real `keychain-access-groups` entitlement is a separate follow-up that needs a signing identity — see Out of Scope.

**Why `AfterFirstUnlockThisDeviceOnly` and not `WhenUnlockedThisDeviceOnly`.** `WhenUnlocked*` items are readable only while the device is unlocked; `AfterFirstUnlock*` items stay readable after the first unlock following a restart and are what the SDK header recommends "for items that need to be accessible by background applications". This is a menu bar app that can be asked to reconnect from a background path, so `AfterFirstUnlockThisDeviceOnly` is the honest class. The `ThisDeviceOnly` suffix is the part that actually matters for the finding: without it a stored Wi-Fi password is eligible to travel in a device backup, which is exactly the over-statement the review flagged. Changing the class from `kSecAttrAccessibleAfterFirstUnlock` (line 122) to `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` is a strengthening, not a weakening.

- [ ] **Step 1: Write the failing backend and migration tests**

Append to `KeychainWiFiPasswordStoreTests`:

```swift
    func testDataProtectionIsPreferredWhenAvailable() {
        let keychain = InMemoryKeychain()
        let store = KeychainWiFiPasswordStore(access: keychain, appService: appService)
        XCTAssertTrue(store.save("password", for: identity))
        XCTAssertEqual(store.backend, .dataProtection)
        let added = keychain.entries.first
        XCTAssertEqual(added?.useDataProtection, true)
        XCTAssertEqual(added?.accessibility, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    func testDataProtectionRefusalFallsBackToLegacy() {
        let keychain = InMemoryKeychain()
        keychain.acceptsDataProtectionWrites = false
        let store = KeychainWiFiPasswordStore(access: keychain, appService: appService)
        XCTAssertTrue(store.save("password", for: identity))
        XCTAssertEqual(store.backend, .legacyLogin)
        XCTAssertEqual(keychain.entries.first?.useDataProtection, false)
        XCTAssertEqual(store.resolveCredential(for: identity), .credential("password", .appKeychain))
    }

    func testLegacyItemIsMigratedAndRemovedOnlyAfterVerification() {
        let keychain = InMemoryKeychain()
        keychain.entries = [
            .init(service: appService, account: account, data: Data("remembered".utf8), accessibility: nil, useDataProtection: false)
        ]
        let store = KeychainWiFiPasswordStore(access: keychain, appService: appService)

        XCTAssertEqual(store.resolveCredential(for: identity), .credential("remembered", .appKeychain))
        XCTAssertEqual(store.backend, .dataProtection)
        XCTAssertEqual(keychain.entries.count, 1, "the legacy copy must be removed once the new copy reads back")
        XCTAssertEqual(keychain.entries.first?.useDataProtection, true)
        XCTAssertEqual(keychain.entries.first?.data, Data("remembered".utf8))
    }

    func testMigrationKeepsTheLegacyItemWhenTheNewCopyCannotBeVerified() {
        let keychain = InMemoryKeychain()
        keychain.entries = [
            .init(service: appService, account: account, data: Data("remembered".utf8), accessibility: nil, useDataProtection: false)
        ]
        // The data-protection read fails even though the write is accepted, so
        // verification cannot succeed and nothing may be deleted.
        keychain.copyStatusByService[appService] = errSecIO
        let store = KeychainWiFiPasswordStore(access: keychain, appService: appService)

        _ = store.resolveCredential(for: identity)
        XCTAssertTrue(
            keychain.entries.contains { !$0.useDataProtection },
            "a legacy item that could not be verified must survive"
        )
    }

    func testMigrationDoesNotOverwriteANewerDataProtectionItem() {
        let keychain = InMemoryKeychain()
        keychain.entries = [
            .init(service: appService, account: account, data: Data("new".utf8), accessibility: nil, useDataProtection: true),
            .init(service: appService, account: account, data: Data("old".utf8), accessibility: nil, useDataProtection: false)
        ]
        let store = KeychainWiFiPasswordStore(access: keychain, appService: appService)
        XCTAssertEqual(store.resolveCredential(for: identity), .credential("new", .appKeychain))
        XCTAssertEqual(keychain.entries.filter { !$0.useDataProtection }.count, 1)
    }

    func testUpdateReassertsTheProtectionClass() {
        let keychain = InMemoryKeychain()
        let store = KeychainWiFiPasswordStore(access: keychain, appService: appService)
        XCTAssertTrue(store.save("first", for: identity))
        keychain.entries[0].accessibility = kSecAttrAccessibleAfterFirstUnlock as String
        XCTAssertTrue(store.save("second", for: identity))
        XCTAssertEqual(keychain.entries[0].accessibility, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }
```

- [ ] **Step 2: Run tests and verify RED**

Run: `swift test --filter KeychainWiFiPasswordStoreTests`
Expected: compile failure — `value of type 'KeychainWiFiPasswordStore' has no member 'backend'`.

- [ ] **Step 3: Implement the backend probe, the protection class, and the migration**

In `Sources/StatusTrioCore/Monitoring/WiFiPasswordStore.swift`:

```swift
/// Which macOS keychain the app-owned item lives in.
///
/// `.dataProtection` is the only backend on macOS that honours
/// `kSecAttrAccessible`; it is gated on the app's code-signing entitlements, so
/// it has to be probed rather than assumed. `.legacyLogin` is the file-based
/// login keychain the app used before this change.
enum KeychainBackend: String, Equatable, Sendable {
    case dataProtection
    case legacyLogin
}
```

Add to the store:

```swift
    private let lock = NSLock()
    private var resolvedBackend: KeychainBackend?
    private var didRunMigration = false

    /// The backend the store settled on, or nil before the first operation.
    var backend: KeychainBackend? {
        lock.lock()
        defer { lock.unlock() }
        return resolvedBackend
    }

    /// Probes the data-protection keychain once. A refusal is recorded, not
    /// thrown: an Ad-hoc signed build without a keychain entitlement must keep
    /// working on the legacy keychain instead of losing the user's passwords.
    private func resolveBackend() -> KeychainBackend {
        lock.lock()
        defer { lock.unlock() }
        if let resolvedBackend { return resolvedBackend }
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(appService).backend-probe",
            kSecAttrAccount as String: "probe",
            kSecUseDataProtectionKeychain as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true
        ]
        let status = access.copyMatching(probe).status
        // errSecItemNotFound is a success for the probe: the backend answered.
        let backend: KeychainBackend =
            (status == errSecSuccess || status == errSecItemNotFound) ? .dataProtection : .legacyLogin
        resolvedBackend = backend
        return backend
    }
```

Add `kSecUseDataProtectionKeychain as String: backend == .dataProtection` to three places, all inside the store:

- `appIdentity(for:)` — so reads, updates and deletes address the same backend that the write used.
- `appAddAttributes(_:for:)` — replacing `attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock` (line 122) with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- `appUpdateQuery(for:)` — so `SecItemUpdate` re-asserts the protection class on the item that already exists. This is the fix for the finding that the update query never re-asserted it.

`appUpdateQuery(for:)` must also carry the accessibility attribute in the *update* dictionary so the class is re-applied. Replace the body of `save(_:for:)` (lines 48-67) with a call to one shared writer, and add that writer:

```swift
    func save(_ password: String, for identity: WiFiNetworkIdentity) -> Bool {
        guard !password.isEmpty else { return false }
        // The backend is settled before the identity is built, because the
        // identity carries kSecUseDataProtectionKeychain.
        _ = resolveBackend()
        migrateLegacyItemsIfNeeded()
        return write(Data(password.utf8), for: identity)
    }

    /// Writes through the resolved backend only. On an Ad-hoc signed build the
    /// data-protection add can be refused, so a refused write retries once on
    /// the legacy keychain rather than losing the user's password.
    private func write(_ data: Data, for identity: WiFiNetworkIdentity) -> Bool {
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        if access.update(appUpdateQuery(for: identity), update) == errSecSuccess { return true }

        switch access.add(appAddAttributes(data, for: identity)) {
        case errSecSuccess:
            return true
        case errSecDuplicateItem:
            return access.update(appUpdateQuery(for: identity), update) == errSecSuccess
        default:
            guard resolveBackend() == .dataProtection else { return false }
            lock.lock()
            resolvedBackend = .legacyLogin
            lock.unlock()
            if access.update(appUpdateQuery(for: identity), update) == errSecSuccess { return true }
            return access.add(appAddAttributes(data, for: identity)) == errSecSuccess
        }
    }
```

Change `appAddAttributes(_:for:)` to take `Data` instead of `String` so both callers share one attribute builder:

```swift
    private func appAddAttributes(_ data: Data, for identity: WiFiNetworkIdentity) -> [String: Any] {
        var attributes = appIdentity(for: identity)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return attributes
    }
```

Add the migration, and call it at the top of `resolveCredential(for:)` and `save(_:for:)` (after `resolveBackend()` in `save`):

```swift
    /// Copies any pre-existing legacy item into the data-protection keychain.
    ///
    /// Order is fixed and must not be relaxed: enumerate the legacy namespace,
    /// read each legacy value, write it to the new backend, read it back, and
    /// only then delete the legacy copy. A failure at any step leaves the legacy
    /// item in place, so the worst case is a password that stays where it was
    /// instead of a password that disappears.
    private func migrateLegacyItemsIfNeeded() {
        lock.lock()
        let alreadyRan = didRunMigration
        didRunMigration = true
        let backend = resolvedBackend
        lock.unlock()
        guard !alreadyRan, backend == .dataProtection else { return }

        let enumeration: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: appService,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        let (status, item) = access.copyMatching(enumeration)
        guard status == errSecSuccess, let rows = item as? [[String: Any]] else { return }

        for row in rows {
            guard let account = row[kSecAttrAccount as String] as? String else { continue }
            let legacyQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: appService,
                kSecAttrAccount as String: account,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecReturnData as String: true
            ]
            let (readStatus, value) = access.copyMatching(legacyQuery)
            guard readStatus == errSecSuccess, let data = value as? Data else { continue }

            let identity = [kSecAttrService as String: appService, kSecAttrAccount as String: account]
            let attributes: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: appService,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                kSecUseDataProtectionKeychain as String: true
            ]
            if access.add(attributes) != errSecSuccess {
                // An item already in the new backend wins; never overwrite it.
                let updated = access.update(identity, [kSecValueData as String: data])
                guard updated == errSecSuccess else { continue }
            }

            let verification: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: appService,
                kSecAttrAccount as String: account,
                kSecUseDataProtectionKeychain as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecReturnData as String: true
            ]
            let (verifyStatus, verified) = access.copyMatching(verification)
            guard verifyStatus == errSecSuccess,
                  let verifiedData = verified as? Data,
                  verifiedData == data else { continue }

            access.delete(legacyQuery)
        }
    }
```

Note the deliberate omission: no `kSecUseAuthenticationContext` on the legacy enumeration, because the legacy copy carries no protection class and the app must not fail its own migration with `errSecInteractionNotAllowed`. Nothing in this function logs `data`, `account`, or `ssid`; if a log line is added for diagnostics it may name only `OSStatus` codes.

Wire the two entry points so the backend is always settled before a query is built, and so the migration runs before the first read:

```swift
    func resolveCredential(for identity: WiFiNetworkIdentity) -> WiFiCredentialResult {
        _ = resolveBackend()
        migrateLegacyItemsIfNeeded()
        let appResult = read(query: appReadQuery(for: identity), source: .appKeychain)
        switch appResult {
        case .credential, .issue:
            return appResult
        case .noCredential:
            return read(query: systemAirPortQuery(for: identity), source: .systemKeychain)
        }
    }
```

`save` calls `resolveBackend()` and the migration in the same order, before `write(_:for:)`. The system `AirPort network password` query is deliberately **not** given `kSecUseDataProtectionKeychain`: that item belongs to the system's own login-keychain namespace and stays there.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `swift test --filter KeychainWiFiPasswordStoreTests`
Expected: all 16 tests pass. Then run `swift test --filter WirelessListModelsTests` — the smoke test must still pass, and that run is the only real-keychain exercise in this plan.

- [ ] **Step 5: Record the signing reality as a real check, not a guess**

Run: `codesign -d --entitlements - .build/release/StatusTrio.app 2>&1 | head -40` after `swift build -c release && bash scripts/build-app.sh`, and paste the output into the commit message. Expected: no `keychain-access-groups` entitlement. That is the evidence for `backend == .legacyLogin` on this build, and the trigger for the follow-up in Out of Scope.

- [ ] **Step 6: Add the release note**

The backend switch changes where a remembered password is stored; that is user-visible enough to state. Append to `release-notes/1.3.0/en.md`:

```markdown
## Remembered Wi-Fi passwords move to the protected keychain
- Passwords you asked Status Trio to remember are now stored in the macOS data-protection keychain, marked as this-device-only, so they are no longer eligible to travel in a device backup.
- Passwords saved by earlier versions are moved automatically the next time they are used, and are kept until the move has been verified.
```

Append to `release-notes/1.3.0/zh-Hans.md`:

```markdown
## 记住的 Wi-Fi 密码迁入受保护的钥匙串
- 你选择让 Status Trio 记住的密码现在存放在 macOS 的数据保护钥匙串中，并标记为仅限本机，因此不会再随设备备份迁移。
- 旧版本保存的密码会在下次使用时自动迁移；迁移校验完成前旧数据会保留。
```

- [ ] **Step 7: Commit**

```bash
git add Sources/StatusTrioCore/Monitoring/WiFiPasswordStore.swift \
        Tests/StatusTrioCoreTests/KeychainWiFiPasswordStoreTests.swift \
        release-notes/1.3.0/en.md release-notes/1.3.0/zh-Hans.md
git commit -m "fix: store remembered Wi-Fi passwords in the data-protection keychain"
```

---

### Task 5: Make The Real-Keychain Smoke Test Skip Loudly

**Files:**
- Modify: `Tests/StatusTrioCoreTests/WirelessListModelsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: no production interface.

Today the only keychain test (`Tests/StatusTrioCoreTests/WirelessListModelsTests.swift:223`) instantiates the real store against the real login keychain and hard-fails when the runner has no usable keychain. In CI that is a red build for an environmental reason; locally it is the only proof that the real `SecItem*` path works at all. Keep it, but make the environmental precondition explicit so a failure names its cause.

- [ ] **Step 1: Rename and gate the smoke test**

Rename `testKeychainPasswordStoreAddsReadsUpdatesAndCleansItsOwnItem` to `testRealLoginKeychainSmokeTest` and add, as its first statement, a precondition that reports the actual `OSStatus` instead of a bare `XCTAssertTrue` failure:

```swift
    func testRealLoginKeychainSmokeTest() throws {
        let service = "StatusTrioCoreTests.WiFiPassword.\(UUID().uuidString)"
        let identity = WiFiNetworkIdentity(ssid: "Review Test Network", security: .wpa2Personal)
        let cleanup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(identity.security.rawValue):\(identity.ssid)"
        ]
        defer { SecItemDelete(cleanup as CFDictionary) }

        let store = KeychainWiFiPasswordStore(appService: service)
        guard store.save("first-password", for: identity) else {
            throw XCTSkip("the test runner has no usable login keychain to write a smoke-test item into")
        }
        XCTAssertEqual(store.resolveCredential(for: identity), .credential("first-password", .appKeychain))
        XCTAssertTrue(store.save("second-password", for: identity))
        XCTAssertEqual(store.resolveCredential(for: identity), .credential("second-password", .appKeychain))
    }
```

The item still uses a random service name and is still deleted in a `defer`, so no real app item is ever touched.

- [ ] **Step 2: Run tests and verify GREEN**

Run: `swift test --filter WirelessListModelsTests`
Expected: passes. On a runner without a usable keychain the test now reports a skip that names the keychain, not a bare assertion failure.

- [ ] **Step 3: Commit**

```bash
git add Tests/StatusTrioCoreTests/WirelessListModelsTests.swift
git commit -m "test: make the real-keychain smoke test name its environmental precondition"
```

---

### Task 6: Full Verification

**Files:**
- No additional files.

- [ ] **Step 1: Run the whole suite**

Run: `swift test`
Expected: all tests pass; the keychain suite reports 16 tests.

- [ ] **Step 2: Run the release build**

Run: `swift build -c release`
Expected: successful build.

- [ ] **Step 3: Confirm the deprecation warnings are gone**

Run: `rm -rf /tmp/wc-keychain && swift build --build-tests --scratch-path /tmp/wc-keychain 2>&1 | grep -E "^/.*warning:" | grep WiFiPasswordStore`
Expected: no output.

- [ ] **Step 4: Run the non-publishing preflight**

Run:

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref codex/keychain-hardening \
  -f version=1.3.0 \
  -f build=12 \
  -f publish=false

gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

Expected: the workflow passes without publishing. If it fails, append the run ID to `docs/swift-ci-compatibility.md` with the failed stage, root cause and fix, per `AGENTS.md`.

- [ ] **Step 5: Review the diff**

Run: `git diff --check` and `git status --short`
Expected: no whitespace errors; only `Sources/StatusTrioCore/Monitoring/WiFiPasswordStore.swift`, `Package.swift`, `Tests/StatusTrioCoreTests/KeychainWiFiPasswordStoreTests.swift`, `Tests/StatusTrioCoreTests/WirelessListModelsTests.swift` and the two `release-notes/1.3.0/` files are modified.

## Verification

| Check | Command | Expected |
| --- | --- | --- |
| New seam suite | `swift test --filter KeychainWiFiPasswordStoreTests` | 16 tests pass, `backend` reported as `.dataProtection` under the double |
| Pre-existing smoke test | `swift test --filter WirelessListModelsTests` | passes, or skips with a message naming the login keychain |
| Whole suite | `swift test` | all tests pass |
| Release build | `swift build -c release` | successful build |
| Security deprecations | `rm -rf /tmp/wc-keychain && swift build --build-tests --scratch-path /tmp/wc-keychain 2>&1 \| grep -E "^/.*warning:" \| grep WiFiPasswordStore` | no output |
| Entitlement evidence | `codesign -d --entitlements - .build/release/StatusTrio.app` | the output is recorded in the commit message; the expected value today is "no keychain-access-groups" |
| Acceptance gate | non-publishing `release.yml` preflight on the branch | passes, `publish=false` |

## Out of Scope

- **Obtaining a real `keychain-access-groups` entitlement.** The data-protection keychain on macOS builds its access-group list from code-signing entitlements, and this app is Ad-hoc signed with no entitlements file. Adding `Support/StatusTrio.entitlements` and passing `--entitlements` to `codesign` is a conditional follow-up: it must be attempted only in a change that also has a stable signing identity, and it must land with a non-publishing preflight that proves the app still launches and can save and re-read a password on the data-protection backend. Do not claim in any user-facing text that the app is notarized or Developer ID signed.
- Do not add `kSecAttrSynchronizable`, iCloud Keychain sync, or any access-group sharing. A Wi-Fi password is per-device.
- Do not change `WiFiCredentialIssue` cases, their localized strings, or `WiFiNetworkController.receiveCredentialResult` (`Sources/StatusTrioCore/Monitoring/WiFiNetworkController.swift:513`). The mapping from issue to UI state is correct and covered elsewhere.
- Do not add logging of SSIDs, accounts, or password bytes. If diagnostics are wanted, log `OSStatus` codes only.
- Do not replace `WiFiCredentialWorker`'s serialization queue. This plan adds its own `NSLock` around the store's mutable backend state, but the worker remains the mechanism that keeps `SecItem` calls off the main thread.

## File Ownership & Conflicts

**Owned by this plan:**

- `Sources/StatusTrioCore/Monitoring/WiFiPasswordStore.swift`
- `Tests/StatusTrioCoreTests/WirelessListModelsTests.swift` (the keychain test only, lines 223-238)
- `Tests/StatusTrioCoreTests/KeychainWiFiPasswordStoreTests.swift` (new)
- `release-notes/1.3.0/en.md`, `release-notes/1.3.0/zh-Hans.md` (append only)

**Also touched, by one line each:**

- `Package.swift` — one `.linkedFramework("LocalAuthentication")` line. No other plan in this set modifies `Package.swift`.
- `Sources/StatusTrioCore/Monitoring/WiFiNetworkController.swift` is listed as an owned file in the index entry for R-12, but after verification this plan needs **no** change there: `receiveCredentialResult` already renders every `WiFiCredentialIssue` and the store's public contract is unchanged. If an implementer finds a change is required, coordinate with R-02 (`2026-09-20-wifi-scan-cadence.md`), which owns that file's scanning paths.

**Conflicts:**

- `docs/superpowers/plans/2026-09-20-compiler-warning-cleanup.md` (R-20) measures the same build and explicitly leaves the two `WiFiPasswordStore.swift` deprecation warnings to this plan. It must be merged **after** Task 3, or its "before" count will be stale. Do not let both plans edit the `appReadQuery` / `systemAirPortQuery` bodies.
- `Tests/StatusTrioCoreTests/VolumeMonitorTests.swift` and `VolumeMonitorAsyncTests.swift` are listed under both R-06 and R-20 and are **not** touched by this plan.
- No other plan in this set edits `WiFiPasswordStore.swift`; the new `KeychainWiFiPasswordStoreTests.swift` file name is unique in `Tests/StatusTrioCoreTests/`.
