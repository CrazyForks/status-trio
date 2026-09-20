# Single Instance And Pasteboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the single-instance lock resistant to a planted symlink or non-regular entry, replace the silent `terminate` with a diagnosable failure that tells the user which of the two problems happened, mark copied network details as transient and concealed so Universal Clipboard and clipboard managers do not retain them, and replace the python3-gated cross-process test with a probe that runs the app's own production guard and cannot silently vanish.

**Architecture:** `SingleInstanceGuard` keeps its per-user private lock file but opens it with `O_NOFOLLOW`, then validates the descriptor with `fstat` + `S_IFREG` before locking. Its failure mode becomes a typed `SingleInstanceGuard.LockFailure` (`.alreadyRunning` vs `.unavailable`) surfaced through a throwing `init()`; `AppDelegate` turns `.unavailable` into an `os_log` error plus an `NSAlert` and a non-zero exit, and keeps the quiet immediate exit for `.alreadyRunning`, which is the normal case when a user double-clicks the app twice. A new `LockProbe` entry point in the executable makes the guard reachable as a child process, which is how the cross-process test proves the lock without an interpreter. The pasteboard copy moves into a small `ConcealedPasteboard` helper that writes `org.nspasteboard.ConcealedType` and `org.nspasteboard.TransientType` next to the string.

**Tech Stack:** Swift 6-compatible SwiftPM package (`swift-tools-version: 6.0`, `platforms: [.macOS(.v15)]`), AppKit, Darwin (`open`, `fstat`, `flock`), `os.Logger`, XCTest.

**Spec:** Derived from the 2026-09-20 security review; cross-plan index: docs/superpowers/plans/2026-09-20-review-findings-index.md (finding **R-13**)

## Global Constraints

- CI acceptance toolchain is the `macos-26` runner with Xcode 26.6 / Swift 6.3.3; local Xcode 27 / Swift 6.4 is not proof.
- Forbidden in this repo: `isolated deinit`, `weak let` (use `weak var`), passing actor-isolated methods directly as function values (use an explicit closure), assuming `Bundle.module` casing.
- The app is Ad-hoc signed and not notarized; anything relying on a Team ID or a stable code-signing identity must be written as a conditional follow-up, not an assumption.
- Run `swift test` and `swift build -c release` before committing Swift changes.
- A non-publishing release preflight is mandatory if a change touches actor isolation, `@MainActor`, `deinit`, SwiftUI bindings, generics, or `Bundle.module` resources: `gh workflow run release.yml --repo lingyired/status-trio --ref <branch> -f version=1.3.0 -f build=12 -f publish=false` then `gh run watch <run-id> --repo lingyired/status-trio --exit-status`. This plan changes an `@MainActor` `NSApplicationDelegate` method and one SwiftUI view, so the preflight is mandatory.
- Any user-visible behavior change needs release notes added to the existing unreleased `release-notes/1.3.0/en.md` and `release-notes/1.3.0/zh-Hans.md`.
- Secrets must never be logged, never stored in `UserDefaults`, never interpolated into strings that could reach `os_log`, and never retained longer than needed. The lock path and the copied network details are not secrets, but they are the only strings this plan may log, and it must not log the SSID or any credential.
- Tests are mixed Swift Testing / XCTest; match the file you extend. `Tests/StatusTrioCoreTests/SingleInstanceGuardTests.swift` is XCTest, so its new tests use `XCTAssert*` and `XCTSkip*`.

## Review Focus

- A user double-clicks the app a second time: they must see nothing at all, not an error dialog. Pinned by `SingleInstanceGuardTests/testSecondGuardCannotAcquireUntilFirstIsReleased` plus `testFailureDiagnosticsSeparateRunningFromBrokenPath`, which asserts `.alreadyRunning` carries no alert text and no failure exit code.
- A same-user process plants a symlink or a directory at the predictable lock path: the app must still start, or explain itself — never exit silently. Pinned by `SingleInstanceGuardTests/testSymlinkAtLockPathDoesNotRedirectTheOpen` and `testDirectoryAtLockPathIsReportedAsUnavailable`.
- A user copies a BSSID or DNS server and expects it on their other devices: after this change it must not travel. Pinned by `PasteboardConcealmentTests/testCopiedDetailsAreMarkedConcealedAndTransient`.
- A machine without an interpreter: the proof that a second process cannot take the lock must still run. Pinned by `SingleInstanceGuardTests/testSubprocessCannotAcquireLockUntilOwnerReleasesIt`, which spawns the app's own binary and has no `XCTSkip`.
- The lock file must stay readable only by its owner. Pinned by `SingleInstanceGuardTests/testLockFileIsOwnerOnly`, which asserts mode `0600`.

---

### Task 1: Typed Lock Outcomes And Hardened `open(2)` Flags

**Files:**
- Modify: `Sources/StatusTrioCore/App/SingleInstanceGuard.swift`
- Modify: `Tests/StatusTrioCoreTests/SingleInstanceGuardTests.swift`

**Interfaces:**
- Produces: `enum SingleInstanceGuardOutcome` — the internal outcome of one acquisition attempt (`.acquired(descriptor: Int32)`, `.alreadyRunning`, `.pathIsNotARegularFile`, `.openFailed(errno: Int32)`).
- Produces: `enum SingleInstanceGuard.LockFailure: Error, Equatable` — `.alreadyRunning`, `.pathIsNotARegularFile`, `.unavailable(errno: Int32)`.
- Produces: `SingleInstanceGuard.init(lockPath: String) throws` and `SingleInstanceGuard.init() throws` (the app's entry point, using `defaultLockPath`), plus `static func acquire(lockPath: String, diagnostics: Bool) -> SingleInstanceGuardOutcome` used by both initializers and by the probe in Task 3.
- Keeps: `init?(lockPath: String = SingleInstanceGuard.defaultLockPath)` and `static func lockFileName(for:)` unchanged in signature, so the existing tests keep compiling. The `?` and `throws` overloads are disambiguated by `try` at the call site, which is why every throwing call site in this plan writes `try SingleInstanceGuard(lockPath:)`.

- [ ] **Step 1: Write the failing tests**

Add the three new test methods to `Tests/StatusTrioCoreTests/SingleInstanceGuardTests.swift`, inserting them after `testSecondGuardCannotAcquireUntilFirstIsReleased` (line 44) and before `testSubprocessCannotAcquireLockUntilOwnerReleasesIt` (line 46), so that `makeTemporaryDirectory()` stays the last member of the class. The two pre-existing tests at lines 6 and 25 stay exactly as they are — they are the regression proof for the current behavior.

Every assertion on the throwing initializer goes through an explicit `do`/`catch` rather than `XCTAssertThrowsError(try ...)`, because both a failable and a throwing `init(lockPath:)` exist and the `do` form is unambiguous at a glance:

```swift
    func testFailureDiagnosticsSeparateRunningFromBrokenPath() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockPath = directory.appendingPathComponent("StatusTrio.lock").path

        let first = try XCTUnwrap(SingleInstanceGuard(lockPath: lockPath))
        withExtendedLifetime(first) {
            do {
                _ = try SingleInstanceGuard(lockPath: lockPath)
                XCTFail("a second guard must not acquire a held lock")
            } catch let failure as SingleInstanceGuard.LockFailure {
                XCTAssertEqual(failure, .alreadyRunning)
                XCTAssertNil(failure.diagnostic, "a second launch is normal and must stay silent")
            } catch {
                XCTFail("unexpected error: \(error)")
            }
        }

        // A directory at the lock path is not "another instance is running".
        try FileManager.default.removeItem(atPath: lockPath)
        try FileManager.default.createDirectory(atPath: lockPath, withIntermediateDirectories: false)
        do {
            _ = try SingleInstanceGuard(lockPath: lockPath)
            XCTFail("a directory at the lock path must not be treated as a lock")
        } catch let failure as SingleInstanceGuard.LockFailure {
            XCTAssertEqual(failure, .pathIsNotARegularFile)
            XCTAssertNotNil(failure.diagnostic, "a broken lock path must be reported to the user")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testSymlinkAtLockPathDoesNotRedirectTheOpen() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("planted-target")
        let lockPath = directory.appendingPathComponent("StatusTrio.lock").path

        try Data("attacker-controlled".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(atPath: lockPath, withDestinationPath: target.path)

        do {
            _ = try SingleInstanceGuard(lockPath: lockPath)
            XCTFail("O_NOFOLLOW must refuse a symlink at the lock path")
        } catch let failure as SingleInstanceGuard.LockFailure {
            XCTAssertEqual(failure, .pathIsNotARegularFile)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        // The target must be byte-identical: the open followed the link only if
        // O_NOFOLLOW failed to apply.
        XCTAssertEqual(try Data(contentsOf: target), Data("attacker-controlled".utf8))
    }

    func testLockFileIsOwnerOnly() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockPath = directory.appendingPathComponent("StatusTrio.lock").path

        let guardInstance = try XCTUnwrap(SingleInstanceGuard(lockPath: lockPath))
        withExtendedLifetime(guardInstance) {
            var status = stat()
            XCTAssertEqual(lstat(lockPath, &status), 0)
            XCTAssertEqual(status.st_mode & 0o777, 0o600)
            XCTAssertTrue((status.st_mode & S_IFMT) == S_IFREG)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StatusTrioTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
```

The pre-existing tests keep using `XCTAssertNil(SingleInstanceGuard(lockPath:))`, which still compiles because the failable initializer stays.

**One trap this refactor must not fall into.** `acquire(lockPath:diagnostics:)` creates the lock itself, so a `SingleInstanceGuard` local that is never used would be deallocated immediately and the guard's `deinit` would release the lock (lines 51-54 today). That is why `testLockFileIsOwnerOnly` and `testFailureDiagnosticsSeparateRunningFromBrokenPath` hold their guard inside `withExtendedLifetime` and why Task 3's probe closes the descriptor explicitly instead of relying on a local's lifetime.

- [ ] **Step 2: Run tests and verify RED**

Run: `swift test --filter SingleInstanceGuardTests`
Expected: compile failure — `cannot find 'SingleInstanceGuard.LockFailure' in scope`, because the throwing initializer and the failure type do not exist yet. The pre-existing `XCTAssertNil(SingleInstanceGuard(lockPath:))` calls in the two older tests must **not** produce an ambiguity error: the failable and throwing overloads are selected by `try` at the call site.

- [ ] **Step 3: Implement the outcome, the flags and the validation**

Rewrite `Sources/StatusTrioCore/App/SingleInstanceGuard.swift`. Keep `defaultLockPath` (lines 5-10) and `lockFileName(for:)` (lines 12-24) byte-for-byte; replace everything from `private let descriptor: Int32` (line 26) to the end:

```swift
/// The outcome of one attempt to take the lock.
enum SingleInstanceGuardOutcome {
    case acquired(descriptor: Int32)
    case alreadyRunning
    /// Something other than a regular file sits at the lock path: a directory,
    /// a symlink, a socket, a FIFO. `O_NOFOLLOW` turns the symlink case into an
    /// `ELOOP` open failure, which is folded into this case as well.
    case pathIsNotARegularFile
    case openFailed(errno: Int32)
}

final class SingleInstanceGuard {
    /// Why an instance could not start. The two cases are not interchangeable:
    /// `.alreadyRunning` is normal and silent, the others must be shown.
    enum LockFailure: Error, Equatable {
        case alreadyRunning
        case pathIsNotARegularFile
        case unavailable(errno: Int32)
    }

    private let descriptor: Int32

    /// Throwing initializer for the app. Uses the user-owned lock path.
    init() throws {
        try self.init(lockPath: SingleInstanceGuard.defaultLockPath)
    }

    /// Throwing initializer that reports *why* the lock could not be taken, so
    /// a caller can tell "another copy is running" from "the path is broken".
    init(lockPath: String) throws {
        switch SingleInstanceGuard.acquire(lockPath: lockPath, diagnostics: true) {
        case let .acquired(descriptor):
            self.descriptor = descriptor
        case .alreadyRunning:
            throw LockFailure.alreadyRunning
        case .pathIsNotARegularFile:
            throw LockFailure.pathIsNotARegularFile
        case let .openFailed(code):
            throw LockFailure.unavailable(errno: code)
        }
    }

    /// Failable initializer kept for callers that only need "may I run".
    init?(lockPath: String = SingleInstanceGuard.defaultLockPath) {
        guard case let .acquired(descriptor) = SingleInstanceGuard.acquire(
            lockPath: lockPath,
            diagnostics: false
        ) else {
            return nil
        }
        self.descriptor = descriptor
    }

    /// One acquisition attempt. The order is fixed: create the parent
    /// directory, open without following symlinks and without handing the
    /// descriptor to a child process, confirm the descriptor is a regular file,
    /// and only then take the non-blocking exclusive lock.
    static func acquire(lockPath: String, diagnostics: Bool) -> SingleInstanceGuardOutcome {
        let lockURL = URL(fileURLWithPath: lockPath)
        do {
            try FileManager.default.createDirectory(
                at: lockURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return .openFailed(errno: EACCES)
        }

        // O_NOFOLLOW: a symlink planted at the predictable path must not
        // redirect this open at a file the app does not own. O_CLOEXEC: the
        // descriptor is not inherited by the app's subprocesses.
        // O_CREAT without O_EXCL keeps the "one file, reused across launches"
        // model; the mode bits are explicit so the result is 0600 regardless of
        // the caller's umask.
        let descriptor = lockPath.withCString { path in
            open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else {
            let code = errno
            // ELOOP is what O_NOFOLLOW reports for a symlink. EISDIR is what
            // O_RDWR reports for a directory. Both mean "not a regular file at
            // this path", which is the failure the user needs to see, so both
            // are folded into that case rather than reported as a generic
            // errno. The remaining errnos are real environment problems.
            switch code {
            case ELOOP, EISDIR:
                return .pathIsNotARegularFile
            default:
                return .openFailed(errno: code)
            }
        }

        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            let code = errno
            close(descriptor)
            return .openFailed(errno: code)
        }
        // Defence in depth for the entry kinds that open successfully but are
        // not regular files, for example a FIFO.
        guard (status.st_mode & S_IFMT) == S_IFREG else {
            close(descriptor)
            return .pathIsNotARegularFile
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            // EWOULDBLOCK is what a held lock reports; anything else is an
            // environment problem worth reporting rather than swallowing.
            return code == EWOULDBLOCK ? .alreadyRunning : .openFailed(errno: code)
        }

        _ = diagnostics
        return .acquired(descriptor: descriptor)
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
```

Both `EISDIR` and `ELOOP` mappings and the `fstat`/`S_IFREG` check were exercised against a real directory, a real symlink and a real regular file while writing this plan; the observed results were `.pathIsNotARegularFile`, `.pathIsNotARegularFile` and `.acquired`, and a symlink target was left byte-identical.

The `diagnostics` parameter is already used by `AppDelegate` in Task 2 through the throwing initializer; it is part of the signature now so the probe in Task 3 can share one code path. Delete the now-unused parameter only if both call sites stop needing it, and do not add logging inside `acquire` — `AppDelegate` owns the visible diagnostic so the same failure is reported exactly once.

`S_IFMT`, `S_IFREG`, `O_NOFOLLOW`, `EISDIR`, `ELOOP`, `EWOULDBLOCK` and `stat` come from `Darwin`, which the file already imports (line 1). `S_IFREG`/`S_IFMT` are `Int32`-typed on Darwin and `st_mode` is `mode_t`, so the comparison compiles as written on the local SDK; if the CI toolchain disagrees, narrow explicitly with `mode_t(S_IFREG)` rather than casting the whole expression.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `swift test --filter SingleInstanceGuardTests`
Expected: the four pre-existing/new locking tests pass; `testSubprocessCannotAcquireLockUntilOwnerReleasesIt` still passes through its python3 path (Task 3 removes that dependency).

- [ ] **Step 5: Commit**

```bash
git add Sources/StatusTrioCore/App/SingleInstanceGuard.swift \
        Tests/StatusTrioCoreTests/SingleInstanceGuardTests.swift
git commit -m "fix: open the single-instance lock with O_NOFOLLOW and validate it is a regular file"
```

---

### Task 2: Diagnosable Startup Failure

**Files:**
- Modify: `Sources/StatusTrioCore/App/AppDelegate.swift`
- Modify: `Sources/StatusTrioCore/Localization/LocalizationKey.swift`
- Modify: `Sources/StatusTrioCore/Resources/*.lproj/Localizable.strings` (all 12 languages; `en` and `zh-Hans` are the two that the acceptance preflight requires)
- Modify: `Tests/StatusTrioCoreTests/SingleInstanceGuardTests.swift`

**Interfaces:**
- Produces: `SingleInstanceGuard.LockFailure.diagnostic` — a `(message: String, detail: String, exitCode: Int32)?` tuple, `nil` for `.alreadyRunning`.
- Consumes: `SingleInstanceGuard.init() throws` and `LockFailure` from Task 1.

Today the failure is completely silent. `Sources/StatusTrioCore/App/AppDelegate.swift:14` is:

```swift
        guard let singleInstanceGuard = SingleInstanceGuard() else {
            NSApplication.shared.terminate(nil)
            return
        }
```

The user double-clicks the app and nothing happens: no window, no log, no way to tell "already running" from "your lock file is broken".

- [ ] **Step 1: Write the failing diagnostic test**

Append to `Tests/StatusTrioCoreTests/SingleInstanceGuardTests.swift`:

```swift
    func testRunningStaysSilentAndABrokenPathIsReported() {
        XCTAssertNil(SingleInstanceGuard.LockFailure.alreadyRunning.diagnostic)
        XCTAssertNil(SingleInstanceGuard.LockFailure.alreadyRunning.alertMessage)
        XCTAssertEqual(SingleInstanceGuard.LockFailure.alreadyRunning.exitCode, EXIT_SUCCESS)

        let broken = SingleInstanceGuard.LockFailure.pathIsNotARegularFile
        XCTAssertNotNil(broken.alertMessage)
        XCTAssertEqual(broken.exitCode, EXIT_FAILURE)
        XCTAssertEqual(broken.logLine.contains("single-instance"), true)
        XCTAssertEqual(broken.logDetail.isEmpty, false)

        let unavailable = SingleInstanceGuard.LockFailure.unavailable(errno: EACCES)
        XCTAssertEqual(unavailable.exitCode, EXIT_FAILURE)
        XCTAssertEqual(unavailable.logDetail.isEmpty, false)
        XCTAssertNotEqual(unavailable.alertMessage, broken.alertMessage)
    }
```

Task 1's `testFailureDiagnosticsSeparateRunningFromBrokenPath` covers the *mapping* from a real filesystem condition to a `LockFailure`; this test covers the *presentation* of that failure and is what pins "already running stays silent". Keep both.

- [ ] **Step 2: Run tests and verify RED**

Run: `swift test --filter SingleInstanceGuardTests/testRunningStaysSilentAndABrokenPathIsReported`
Expected: compile failure — `value of type 'SingleInstanceGuard.LockFailure' has no member 'diagnostic'`.

- [ ] **Step 3: Add the diagnostic surface**

In `Sources/StatusTrioCore/App/SingleInstanceGuard.swift`, extend `LockFailure`:

```swift
extension SingleInstanceGuard.LockFailure {
    /// True only when the lock is held by a running copy of the app. That is
    /// the normal result of a second double-click and must stay silent.
    var isAlreadyRunning: Bool { self == .alreadyRunning }

    /// Non-nil only for failures the user needs to see. Composed here, not at
    /// the call site, so the alert, the log line and the exit code cannot drift
    /// apart. Never contains an SSID, a path under the user's home, or anything
    /// derived from a credential.
    var diagnostic: (message: String, detail: String, exitCode: Int32)? {
        switch self {
        case .alreadyRunning:
            return nil
        case .pathIsNotARegularFile:
            return (
                message: "Status Trio could not start its single-instance lock.",
                detail: "Something other than a regular file is at the lock path, so Status Trio cannot tell whether another copy is running. Remove that entry and start Status Trio again.",
                exitCode: EXIT_FAILURE
            )
        case let .unavailable(code):
            return (
                message: "Status Trio could not create its single-instance lock.",
                detail: "The lock file could not be created or locked (\(String(cString: strerror(code)))). Status Trio stopped instead of starting a second copy.",
                exitCode: EXIT_FAILURE
            )
        }
    }

    var alertMessage: String? { diagnostic?.message }
    var logLine: String { "single-instance lock unavailable: \(self)" }
    var logDetail: String { diagnostic?.detail ?? "" }
    var exitCode: Int32 { diagnostic?.exitCode ?? EXIT_SUCCESS }
}
```

- [ ] **Step 4: Replace the silent terminate**

In `Sources/StatusTrioCore/App/AppDelegate.swift`, add `import os` and `import Darwin` (the file currently imports only `AppKit`, line 1), a file-scope logger, then the two methods above:

```swift
private let appDelegateLogger = Logger(
    subsystem: "com.lingsmbp.StatusTrio",
    category: "SingleInstanceGuard"
)
```

```swift
    public func applicationDidFinishLaunching(_ notification: Notification) {
        guard let singleInstanceGuard = startSingleInstanceGuard() else { return }
        self.singleInstanceGuard = singleInstanceGuard

        let environment = AppEnvironment.live()
        self.environment = environment
        environment.start()
        updaterManager.start(activationPolicy: environment.activationPolicy)
    }

    /// Returns nil when this launch must not continue: another copy is already
    /// running, or the lock path is broken and the user has been told why.
    private func startSingleInstanceGuard() -> SingleInstanceGuard? {
        do {
            return try SingleInstanceGuard(lockPath: SingleInstanceGuard.defaultLockPath)
        } catch let failure as SingleInstanceGuard.LockFailure {
            // Another copy is running: that is what the user asked for, so
            // quietly hand the second launch back to the first one.
            guard let diagnostic = failure.diagnostic else { return nil }
            appDelegateLogger.error("\(failure.logLine, privacy: .public)")
            presentLockFailure(diagnostic)
            exit(diagnostic.exitCode)
        } catch {
            appDelegateLogger.error("single-instance lock unavailable: \(String(describing: error), privacy: .public)")
            exit(EXIT_FAILURE)
        }
    }

    /// Shows the failure instead of exiting with no explanation. `runModal`
    /// blocks until dismissed, which is correct here: without the guard the app
    /// must not continue to `environment.start()`.
    private func presentLockFailure(_ diagnostic: (message: String, detail: String, exitCode: Int32)) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = localizationString(.singleInstanceUnavailable)
        alert.informativeText = diagnostic.detail
        alert.addButton(withTitle: localizationString(.singleInstanceQuit))
        alert.runModal()
    }
```

Add a small accessor for the two localized strings. `Localization` is `@MainActor` and `AppDelegate` is `@MainActor`, so either inject the existing `Localization` instance or, more simply, add these two cases and read them through the same bundle lookup the rest of the app uses:

```swift
    private func localizationString(_ key: LocalizationKey) -> String {
        guard let bundle = Localization.resourceBundle(for: AppLanguage.resolved(preferredLanguages: Locale.preferredLanguages)) else {
            return key.rawValue
        }
        return bundle.localizedString(forKey: key.rawValue, value: nil, table: nil)
    }
```

If `resourceBundle(for:)` or `AppLanguage.resolved(preferredLanguages:)` is not reachable from here, read the resolved language from `environment`/the existing `Localization` instance instead of resolving it again — do not add a second language-resolution path.

- [ ] **Step 5: Add the two strings**

In `Sources/StatusTrioCore/Localization/LocalizationKey.swift`, next to the other app-level cases:

```swift
    case singleInstanceUnavailable = "app.singleInstanceUnavailable"
    case singleInstanceQuit = "app.singleInstanceQuit"
```

Add both keys to every `Sources/StatusTrioCore/Resources/*.lproj/Localizable.strings`. English:

```
"app.singleInstanceUnavailable" = "Status Trio could not start";
"app.singleInstanceQuit" = "Quit";
```

Simplified Chinese:

```
"app.singleInstanceUnavailable" = "Status Trio 无法启动";
"app.singleInstanceQuit" = "退出";
```

Translate the remaining ten files consistently with their existing terminology. `publish=false` needs `en.md` and `zh-Hans.md` release notes only, but a missing key in any shipped `.lproj` is a real gap: `swift test --filter LocalizationTests` is the check that every `LocalizationKey` case resolves in every language, so run it.

- [ ] **Step 6: Run tests and verify GREEN**

Run: `swift test --filter SingleInstanceGuardTests`
Run: `swift test --filter LocalizationTests`
Run: `swift test --filter AppMetadataTests`
Expected: pass. Then launch the app twice by hand with `open -n` on the built bundle and confirm the second launch shows no alert and the first one keeps running; launch with a directory sitting at `~/Library/Application Support/StatusTrio/com.lingsmbp.StatusTrio.lock` and confirm the alert appears and `echo $?` is non-zero. Remove that directory afterwards — do not leave the developer machine in the broken state.

- [ ] **Step 7: Commit**

```bash
git add Sources/StatusTrioCore/App/AppDelegate.swift \
        Sources/StatusTrioCore/App/SingleInstanceGuard.swift \
        Sources/StatusTrioCore/Localization/LocalizationKey.swift \
        Sources/StatusTrioCore/Resources \
        Tests/StatusTrioCoreTests/SingleInstanceGuardTests.swift
git commit -m "fix: report a broken single-instance lock instead of exiting silently"
```

---

### Task 3: A Cross-Process Test That Cannot Silently Vanish

**Files:**
- Create: `Sources/StatusTrioCore/App/LockProbe.swift`
- Modify: `Sources/StatusTrio/main.swift`
- Modify: `Tests/StatusTrioCoreTests/SingleInstanceGuardTests.swift`

**Interfaces:**
- Produces: `enum LockProbe` with `public static let environmentKey = "STATUS_TRIO_LOCK_PROBE_PATH"` and `public static func runIfRequested() -> Bool`.
- Produces: `enum LockProbeOutcome: Int32` — `.acquired = 0`, `.alreadyRunning = 3`, `.pathIsNotARegularFile = 4`, `.openFailed = 5`.
- Consumes: `SingleInstanceGuard.acquire(lockPath:diagnostics:)` from Task 1.

The current test at `Tests/StatusTrioCoreTests/SingleInstanceGuardTests.swift:46-51` guards its whole body with `XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/bin/python3"))`. On a machine without python3 the only proof that a second process cannot take the lock disappears and the suite still reports success. This task keeps an interpreter-free second process by reusing the app's own production guard.

- [ ] **Step 1: Write the failing probe test**

Replace `testSubprocessCannotAcquireLockUntilOwnerReleasesIt` and delete `runFlockHelper(pythonPath:lockPath:)`:

```swift
    func testSubprocessCannotAcquireLockUntilOwnerReleasesIt() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockPath = directory.appendingPathComponent("StatusTrio.lock").path

        var first: SingleInstanceGuard? = try XCTUnwrap(SingleInstanceGuard(lockPath: lockPath))
        withExtendedLifetime(first) {
            XCTAssertEqual(try runLockProbe(lockPath: lockPath), 3)
        }

        first = nil
        XCTAssertEqual(try runLockProbe(lockPath: lockPath), 0)
    }

    /// Runs the built app binary in probe mode. No interpreter, no skip: if the
    /// binary is missing the test fails with the path it looked for.
    private func runLockProbe(lockPath: String) throws -> Int32 {
        let executable = try XCTUnwrap(
            locateAppExecutable(),
            "the app executable was not found next to the test bundle; build with `swift build --build-tests` and re-run"
        )

        let process = Process()
        process.executableURL = executable
        var environment = ProcessInfo.processInfo.environment
        environment[LockProbe.environmentKey] = lockPath
        process.environment = environment

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()

        // Bounded wait so a hung probe fails the test instead of parking it
        // until the whole-run timeout.
        let deadline = Date().addingTimeInterval(30)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            XCTFail("the lock probe did not exit within 30 s")
        }
        let outputText = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        XCTAssertEqual(process.terminationReason, .exit, outputText)
        XCTAssertTrue([0, 3, 4, 5].contains(process.terminationStatus), outputText)
        return process.terminationStatus
    }

    private func locateAppExecutable() -> URL? {
        // The test bundle lives in the same build directory as the products.
        let buildDirectory = Bundle(for: SingleInstanceGuardTests.self)
            .bundleURL
            .deletingLastPathComponent()
        let candidates = [
            buildDirectory.appendingPathComponent("StatusTrio"),
            buildDirectory.appendingPathComponent("debug/StatusTrio")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
```

- [ ] **Step 2: Run tests and verify RED**

Run: `swift test --filter SingleInstanceGuardTests/testSubprocessCannotAcquireLockUntilOwnerReleasesIt`
Expected: compile failure — `cannot find 'LockProbe' in scope` and `cannot find 'locateAppExecutable'` is not the issue; the probe type does not exist yet.

- [ ] **Step 3: Add the probe entry point**

Create `Sources/StatusTrioCore/App/LockProbe.swift`:

```swift
import Darwin
import Foundation

/// A hidden entry point that exercises the real single-instance guard from a
/// second process and reports the result on stdout. It exists so the
/// cross-process lock test does not need an interpreter that may be missing.
///
/// This is not a user-facing flag: it is reached only when the environment
/// variable is set, and it never starts the UI.
enum LockProbe {
    public static let environmentKey = "STATUS_TRIO_LOCK_PROBE_PATH"

    /// Returns true when probe mode ran, so the caller must not continue to the
    /// normal application startup.
    public static func runIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty else {
            return false
        }

        switch SingleInstanceGuard.acquire(lockPath: path, diagnostics: false) {
        case let .acquired(descriptor):
            FileHandle.standardOutput.write(Data("acquired\n".utf8))
            // Hold the lock long enough for the parent test to observe it when
            // the probe is used as the lock owner rather than as the contender.
            if ProcessInfo.processInfo.environment["STATUS_TRIO_LOCK_PROBE_HOLD"] != nil {
                sleep(5)
            }
            close(descriptor)
            exit(LockProbeOutcome.acquired.rawValue)
        case .alreadyRunning:
            FileHandle.standardOutput.write(Data("already-running\n".utf8))
            exit(LockProbeOutcome.alreadyRunning.rawValue)
        case .pathIsNotARegularFile:
            FileHandle.standardOutput.write(Data("path-not-regular\n".utf8))
            exit(LockProbeOutcome.pathIsNotARegularFile.rawValue)
        case let .openFailed(code):
            FileHandle.standardOutput.write(Data("open-failed \(code)\n".utf8))
            exit(LockProbeOutcome.openFailed.rawValue)
        }
    }
}

enum LockProbeOutcome: Int32 {
    case acquired = 0
    case alreadyRunning = 3
    case pathIsNotARegularFile = 4
    case openFailed = 5
}
```

Add one line to `Sources/StatusTrio/main.swift`, before the application is created:

```swift
import AppKit
import StatusTrioCore

// Probe mode answers a lock question and exits; it never starts the UI.
if LockProbe.runIfRequested() {
    exit(EXIT_SUCCESS)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
```

`exit(_:)` never returns, so no `return` is needed after it and the compiler emits no "missing return" diagnostic for this shape (verified against a minimal reproduction while writing this plan). Keep exactly one `exit` per outcome so the probe's exit code cannot be produced two different ways, and keep `runIfRequested()`'s return value meaningful: `false` means "not probe mode, carry on into the app".

- [ ] **Step 4: Run tests and verify GREEN**

Run: `swift test --filter SingleInstanceGuardTests`
Expected: all locking tests pass with no skip reported. Then confirm the probe really is the production guard by running it by hand:

```bash
swift build --build-tests
STATUS_TRIO_LOCK_PROBE_HOLD=1 STATUS_TRIO_LOCK_PROBE_PATH=/tmp/status-trio-probe.lock .build/debug/StatusTrio &
sleep 1
STATUS_TRIO_LOCK_PROBE_PATH=/tmp/status-trio-probe.lock .build/debug/StatusTrio; echo "exit=$?"
wait
```

Expected: `already-running` / `exit=3` from the second invocation, then the first exits with `exit=0`. The same path used twice with no holder prints `acquired` / `exit=0` both times.

- [ ] **Step 5: Commit**

```bash
git add Sources/StatusTrioCore/App/LockProbe.swift Sources/StatusTrio/main.swift \
        Tests/StatusTrioCoreTests/SingleInstanceGuardTests.swift
git commit -m "test: prove the single-instance lock across processes with the app's own guard"
```

---

### Task 4: Mark Copied Network Details As Concealed And Transient

**Files:**
- Create: `Sources/StatusTrioCore/App/ConcealedPasteboard.swift`
- Modify: `Sources/StatusTrioCore/UI/WiFiNetworkListView.swift`
- Create: `Tests/StatusTrioCoreTests/PasteboardConcealmentTests.swift`

**Interfaces:**
- Produces: `enum ConcealedPasteboard` with `@MainActor static func copy(_ value: String, to pasteboard: NSPasteboard = .general)`.
- Consumes: nothing.

`Sources/StatusTrioCore/UI/WiFiNetworkListView.swift:351-352` writes BSSID, IPv4/IPv6 addresses, router and DNS servers to `NSPasteboard.general` with `clearContents()` + `setString(_:forType: .string)`. The general pasteboard is readable by every process and syncs through Universal Clipboard; these are network identifiers rather than secrets, but the copy is an unnecessary broadcast.

- [ ] **Step 1: Write the failing test**

Create `Tests/StatusTrioCoreTests/PasteboardConcealmentTests.swift`:

```swift
import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class PasteboardConcealmentTests: XCTestCase {
    func testCopiedDetailsAreMarkedConcealedAndTransient() throws {
        // A private pasteboard, so the real general pasteboard is never touched
        // by the test suite.
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("StatusTrioTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        ConcealedPasteboard.copy("192.168.1.1", to: pasteboard)

        XCTAssertEqual(
            pasteboard.data(forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")),
            Data()
        )
        XCTAssertEqual(
            pasteboard.data(forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType")),
            Data()
        )
        XCTAssertEqual(pasteboard.string(forType: .string), "192.168.1.1")
        XCTAssertFalse(
            pasteboard.types?.contains(NSPasteboard.PasteboardType("com.apple.pasteboard.promised-plain-text")) ?? true,
            "marking a transient copy as storable would defeat the marker"
        )
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

Run: `swift test --filter PasteboardConcealmentTests`
Expected: compile failure — `cannot find 'ConcealedPasteboard' in scope`.

- [ ] **Step 3: Add the helper and use it**

Create `Sources/StatusTrioCore/App/ConcealedPasteboard.swift`:

```swift
import AppKit

/// Copies text without asking the rest of the system to keep it.
///
/// `org.nspasteboard.ConcealedType` is the convention clipboard managers read to
/// decide that a copy is sensitive, and `org.nspasteboard.TransientType` is the
/// convention Universal Clipboard reads to decide that a copy should not sync to
/// the user's other devices. Neither marker is enforced by macOS, so this is a
/// request rather than a guarantee — but it is the difference between a network
/// detail being broadcast to every device the user owns and staying on this Mac.
enum ConcealedPasteboard {
    @MainActor
    static func copy(_ value: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
    }
}
```

Deliberately absent: `com.apple.pasteboard.promised-plain-text` and any `NSPasteboardContents` plain-text flag. Those ask the system to *keep* the content, which is the opposite of the intent.

In `WiFiNetworkListView.swift`, replace lines 351-352:

```swift
                Button(value) {
                    ConcealedPasteboard.copy(value)
                }
```

The view is a `View` whose `body` runs on the main actor, so the `@MainActor` annotation on `copy` is satisfied without an explicit closure or `MainActor.assumeIsolated`. Do not add a `Task {}` wrapper here: the copy must complete synchronously before the button's action returns.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `swift test --filter PasteboardConcealmentTests`
Expected: one test passes.

- [ ] **Step 5: Add the release note**

The alert from Task 2 is user-visible, so both changes are recorded together. Append to `release-notes/1.3.0/en.md`:

```markdown
## Clearer failure when the app cannot start
- If Status Trio cannot create its single-instance lock — for example because something other than a regular file is sitting at the lock path — it now explains the problem in a dialog and exits with a non-zero status instead of quitting with nothing on screen. Starting a second copy while Status Trio is already running stays silent, as before.

## Copied network details stay on this Mac
- Copying a BSSID, IP address, router or DNS server from the Wi-Fi panel now marks the clipboard entry as concealed and transient, so clipboard managers and Universal Clipboard do not retain it or send it to your other devices.
```

Append to `release-notes/1.3.0/zh-Hans.md`:

```markdown
## 无法启动时给出明确原因
- 当 Status Trio 无法创建单实例锁时（例如锁文件路径上放着的不是普通文件），现在会弹出对话框说明原因并以非零状态退出，而不是毫无提示地退出。已经有一个 Status Trio 在运行时再次启动，仍然像以前一样静默退出。

## 复制的网络信息留在本机
- 从 Wi-Fi 面板复制 BSSID、IP 地址、路由器或 DNS 时，剪贴板条目现在会标记为隐藏且临时，剪贴板管理器与「通用剪贴板」不会再保留或同步到你的其他设备。
```

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusTrioCore/App/ConcealedPasteboard.swift \
        Sources/StatusTrioCore/UI/WiFiNetworkListView.swift \
        Tests/StatusTrioCoreTests/PasteboardConcealmentTests.swift \
        release-notes/1.3.0/en.md release-notes/1.3.0/zh-Hans.md
git commit -m "fix: mark copied network details as concealed and transient on the pasteboard"
```

---

### Task 5: Full Verification

**Files:**
- No additional files.

- [ ] **Step 1: Run the whole suite**

Run: `swift test`
Expected: all tests pass, with no skip reported in `SingleInstanceGuardTests`.

- [ ] **Step 2: Run the release build**

Run: `swift build -c release`
Expected: successful build.

- [ ] **Step 3: Verify the app still launches and the guard still works end to end**

Run:

```bash
bash scripts/build-app.sh
open -n ".build/release/Status Trio.app"
sleep 3
pgrep -f "Status Trio" | wc -l
```

Expected: `1`. Then run `open -n` a second time and confirm the count is still `1` and no dialog appeared. Quit the app.

- [ ] **Step 4: Run the non-publishing preflight**

Run:

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref codex/single-instance-and-pasteboard \
  -f version=1.3.0 \
  -f build=12 \
  -f publish=false

gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

Expected: the workflow passes without publishing. If it fails, append the run ID to `docs/swift-ci-compatibility.md` with the failed stage, root cause and fix, per `AGENTS.md`.

- [ ] **Step 5: Review the diff**

Run: `git diff --check` and `git status --short`
Expected: no whitespace errors; only the files listed in File Ownership are modified, and the deleted python3 helper leaves no reference to `python3` anywhere:

```bash
grep -rn "python3" Sources Tests
```

Expected: no output.

## Verification

| Check | Command | Expected |
| --- | --- | --- |
| Lock hardening | `swift test --filter SingleInstanceGuardTests` | all pass, including the symlink, directory and `0600` cases |
| Cross-process proof | `swift test --filter SingleInstanceGuardTests/testSubprocessCannotAcquireLockUntilOwnerReleasesIt` | passes with no skip |
| Diagnostics | `swift test --filter SingleInstanceGuardTests/testRunningStaysSilentAndABrokenPathIsReported` | passes |
| Pasteboard marker | `swift test --filter PasteboardConcealmentTests` | passes |
| Localization coverage | `swift test --filter LocalizationTests` | passes for all 12 languages |
| Whole suite | `swift test` | all tests pass |
| Release build | `swift build -c release` | successful build |
| Real launch | `bash scripts/build-app.sh && open -n ".build/release/Status Trio.app"` twice | one process, no dialog on the second launch |
| Acceptance gate | non-publishing `release.yml` preflight on the branch | passes, `publish=false` |

## Out of Scope

- **Do not move the lock file out of `~/Library/Application Support/StatusTrio/`.** Per-user scope is the correct model: the lock exists to stop a second copy of the app for the *same user*, and a shared location would either need root to create or let one user's stale file block another user's launch. The directory is created by the app inside the user's own home, the file is `0600`, and `O_NOFOLLOW` plus the `S_IFREG` check close the same-user pre-creation gap without widening the scope.
- **Do not add a `flock`-based crash-recovery marker, a PID file, or a stale-lock timeout.** `flock` is released by the kernel when the process exits, including on a crash, so none of that machinery is needed.
- **Do not change `lockFileName(for:)` or the sanitization rules** (lines 12-24). They are covered by `testLockFileNameIsScopedByBundleIdentifier` and a change there would alter which file an existing install uses.
- **Do not apply the concealment marker to any other pasteboard write, and do not add pasteboard *reads*.** The review found exactly one write site. Reading the pasteboard, or a general "clipboard privacy" mode, is a different feature with different UX.
- **Do not claim the pasteboard markers are enforced.** `org.nspasteboard.*` types are a convention honoured by cooperating clipboard managers and by Universal Clipboard; macOS does not guarantee them. Any user-facing text must say "do not retain / do not sync", not "cannot".
- **Do not add an app-side lock for the `NSAlert`.** `runModal` on the main actor is the existing pattern in this repo (`Sources/StatusTrioCore/App/UpdaterManager.swift:55`).

## File Ownership & Conflicts

**Owned by this plan:**

- `Sources/StatusTrioCore/App/SingleInstanceGuard.swift`
- `Sources/StatusTrioCore/App/AppDelegate.swift`
- `Sources/StatusTrioCore/App/LockProbe.swift` (new)
- `Sources/StatusTrioCore/App/ConcealedPasteboard.swift` (new)
- `Sources/StatusTrioCore/UI/WiFiNetworkListView.swift`
- `Sources/StatusTrioCore/Localization/LocalizationKey.swift`
- `Sources/StatusTrioCore/Resources/*.lproj/Localizable.strings` (two new keys in each)
- `Sources/StatusTrio/main.swift`
- `Tests/StatusTrioCoreTests/SingleInstanceGuardTests.swift`
- `Tests/StatusTrioCoreTests/PasteboardConcealmentTests.swift` (new)
- `release-notes/1.3.0/en.md`, `release-notes/1.3.0/zh-Hans.md` (append only)

**Conflicts:**

- `Sources/StatusTrioCore/App/AppDelegate.swift` is also touched by `2026-09-20-bluetooth-polling-and-lifetime.md` (R-01, lifetime of the Bluetooth controller) and possibly by other lifecycle plans. This plan changes only `applicationDidFinishLaunching`; if another plan has already rewritten that method, rebase and keep both changes rather than choosing one.
- `Sources/StatusTrioCore/Localization/LocalizationKey.swift` and the twelve `Localizable.strings` files are shared with every plan that adds user-facing text. Adding two cases at the end of the enum and two lines per file keeps the conflict textual and trivial; do not reorder existing cases.
- `release-notes/1.3.0/en.md` and `zh-Hans.md` are appended to by several plans in this set. Append a new `##` section at the end; never rewrite an existing section.
- `Sources/StatusTrioCore/UI/WiFiNetworkListView.swift` appears in R-02 (`2026-09-20-wifi-scan-cadence.md`) under `UI/StatusPopoverView.swift`-adjacent Wi-Fi work. This plan owns only the `detail(_:_:copyable:)` helper near line 344-363; if R-02 also edits this file, land R-02 first or split by function and review both diffs together.
- `Sources/StatusTrio/main.swift` is a seven-line file; no other plan in this set edits it.
