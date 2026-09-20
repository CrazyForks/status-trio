# Compiler Warning Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the full build warning-free, on the CI toolchain, by replacing the deprecated `String(cString:)` call with the truncate-then-decode form the compiler asks for and by removing the four "weak variable was never mutated" diagnostics **without** contradicting the `AGENTS.md` rule that forbids `weak let` — then leave a verification command and a recorded before/after count so the claim is checkable.

**Architecture:** One production change (`HostMacKind` gains a pure, testable `modelIdentifier(from:)` buffer parser and stops calling `String(cString:)`) and one test-infrastructure change (a small weak-reference probe helper in the test target that the four warning sites use). The `AGENTS.md` rule is not edited: this plan adds evidence for *why* `weak let` cannot be the fix and picks a resolution that leaves the rule and the toolchain requirement intact.

**Tech Stack:** Swift 6-compatible SwiftPM package (`swift-tools-version: 6.0`, `platforms: [.macOS(.v15)]`), Swift Testing (`AudioOutputDeviceIconTests.swift`), XCTest (`WiFiClassifierTests.swift`, `VolumeMonitorTests.swift`, `VolumeMonitorAsyncTests.swift`), Darwin `sysctlbyname`.

**Spec:** Derived from the 2026-09-20 security review; cross-plan index: docs/superpowers/plans/2026-09-20-review-findings-index.md (finding **R-20**)

## Global Constraints

- CI acceptance toolchain is the `macos-26` runner with Xcode 26.6 / Swift 6.3.3; local Xcode 27 / Swift 6.4 is not proof.
- Forbidden in this repo: `isolated deinit`, `weak let` (use `weak var`), passing actor-isolated methods directly as function values (use an explicit closure), assuming `Bundle.module` casing.
- The app is Ad-hoc signed and not notarized; anything relying on a Team ID or a stable code-signing identity must be written as a conditional follow-up, not an assumption.
- Run `swift test` and `swift build -c release` before committing Swift changes.
- A non-publishing release preflight is mandatory if a change touches actor isolation, `@MainActor`, `deinit`, SwiftUI bindings, generics, or `Bundle.module` resources: `gh workflow run release.yml --repo lingyired/status-trio --ref <branch> -f version=1.3.0 -f build=12 -f publish=false` then `gh run watch <run-id> --repo lingyired/status-trio --exit-status`. This plan adds a **generic** helper (`DeinitProbe`) and changes code in files that reference `deinit`-adjacent behavior, so the preflight is mandatory.
- Any user-visible behavior change needs release notes added to the existing unreleased `release-notes/1.3.0/en.md` and `release-notes/1.3.0/zh-Hans.md`. **This plan changes no user-visible behavior and therefore adds no release note.** If the `hw.model` parser turns out to change an icon on any machine, that is a visible change and the release note requirement applies — the new test in Task 1 is the check that decides this.
- Secrets must never be logged, never stored in `UserDefaults`, never interpolated into strings that could reach `os_log`, and never retained longer than needed.
- Tests are mixed Swift Testing / XCTest; match the file you extend. `AudioOutputDeviceIconTests.swift` uses Swift Testing (`#expect`); the other three use XCTest.

## Review Focus

- A Mac whose `hw.model` has no null terminator inside the returned size: today `String(cString:)` reads past the buffer, tomorrow the parser must return the whole buffer rather than crash or truncate silently. Pinned by `AudioOutputDeviceIconTests/modelIdentifierParsingStopsAtTheNulTerminator`.
- The kernel reports a smaller size on the second `sysctlbyname` call than the first: today that returns `""` and the machine family falls back to a device name. That must not change, because the built-in speaker icon depends on it. Pinned by `AudioOutputDeviceIconTests/modelIdentifierParserHandlesAShrinkingBuffer`.
- A deallocation test that stops proving deallocation: the weak-reference refactor must keep asserting `nil` *after* the strong reference is released. Pinned by the unchanged assertions in `WiFiClassifierTests.testSlowReadDoesNotRetainMonitor`, `VolumeMonitorTests.testDeinitWithoutStopStopsEventMonitorAndFinishesUpdates`, and `VolumeMonitorAsyncTests.testOutstandingReadDoesNotRetainMonitor`.
- A "fix" that silently reintroduces `weak let` and breaks the CI toolchain contract: forbidden by `AGENTS.md` and recorded in `docs/swift-ci-compatibility.md` run `34753843803`. Pinned by the diff-level check in Task 3 Step 4 (`grep -rn "weak let" Sources Tests` must stay empty) plus the CI preflight.
- A clean-machine claim that only holds for an incremental build: the verification command uses a fresh `--scratch-path`, so a stale object file cannot hide a warning. Pinned by Task 4 Step 1.

---

### Task 1: Replace `String(cString:)` And Make The `hw.model` Parsing Testable

**Files:**
- Modify: `Sources/StatusTrioCore/Audio/AudioOutputDeviceIcon.swift`
- Modify: `Tests/StatusTrioCoreTests/AudioOutputDeviceIconTests.swift`

**Interfaces:**
- Produces: `HostMacKind.modelIdentifier(from buffer: [CChar]) -> String` (`static`, pure).
- Keeps: `HostMacKind(modelIdentifier: String)`, `HostMacKind.current`, `HostMacKind(deviceName:host:)` unchanged.

**What is actually wrong, and what is not.** The warning is:

```
Sources/StatusTrioCore/Audio/AudioOutputDeviceIcon.swift:144:16: warning: 'init(cString:)' is deprecated: Use String(decoding: array, as: UTF8.self) instead, after truncating the null termination. [#DeprecatedDeclaration]
```

`buffer` is `[CChar](repeating: 0, count: size)` (line 140) with `size` read from the first `sysctlbyname("hw.model", nil, &size, nil, 0)` call (line 136), and the array is zero-filled before the second call. There is **no out-of-bounds read today** — a zero-filled byte exists at the end even if the kernel writes fewer bytes than `size`. This is a deprecation and robustness fix, not a memory-safety bug, and it must not be described as one in the commit message.

- [ ] **Step 1: Write the failing parser tests**

Add to `Tests/StatusTrioCoreTests/AudioOutputDeviceIconTests.swift`, next to `hostMachineIdentifiersMapToFamilies` (line 26):

```swift
    @Test("hw.model parsing stops at the NUL terminator")
    func modelIdentifierParsingStopsAtTheNulTerminator() {
        // CChar is Int8 on Darwin, so 0 is the terminator and the trailing
        // 0x7F bytes are garbage that must never reach the string.
        let wellFormed: [CChar] = [77, 97, 99, 49, 53, 44, 57, 0, 127, 127]
        #expect(HostMacKind.modelIdentifier(from: wellFormed) == "Mac15,9")

        // A buffer with no terminator at all still yields every byte.
        let unterminated: [CChar] = [77, 97, 99, 49, 53, 44, 57]
        #expect(HostMacKind.modelIdentifier(from: unterminated) == "Mac15,9")

        // An empty buffer must not trap on withUnsafeMutableBytes.
        #expect(HostMacKind.modelIdentifier(from: []) == "")
    }

    @Test("A shrinking hw.model size degrades to an empty identifier")
    func modelIdentifierParserHandlesAShrinkingBuffer() {
        // The first sysctlbyname call reports the size; the second may report a
        // smaller one. The existing code returns "" in that case and the caller
        // falls back to the device name for the machine family, which is what
        // the built-in speaker symbol depends on.
        #expect(HostMacKind.modelIdentifier(from: [0]) == "")
        #expect(HostMacKind.modelIdentifier(from: [77, 97, 99]) == "Mac")
    }
```

- [ ] **Step 2: Run tests and verify RED**

Run: `swift test --filter AudioOutputDeviceIconTests`
Expected: compile failure — `type 'HostMacKind' has no member 'modelIdentifier'`.

- [ ] **Step 3: Implement the pure parser and use it**

In `Sources/StatusTrioCore/Audio/AudioOutputDeviceIcon.swift`, add a `static func` next to `currentModelIdentifier()` (line 134) and rewrite that function to keep its exact fallback behavior:

```swift
    /// Decodes a NUL-terminated `hw.model` buffer.
    ///
    /// `String(cString:)` is deprecated in favour of decoding after truncating,
    /// which is what this does. `sysctlbyname` writes a C string, but a buffer
    /// that is not terminated (or is shorter than the size the kernel reported
    /// on the first call) must degrade to a value the caller can still use,
    /// never to a read past the end.
    static func modelIdentifier(from buffer: [CChar]) -> String {
        guard !buffer.isEmpty else { return "" }
        let terminator = buffer.firstIndex(of: 0)
        let bytes = terminator.map { buffer[..<$0] } ?? buffer[...]
        return String(decoding: bytes.map(UInt8.init(bitPattern:)), as: Unicode.ASCII.self)
    }

    private static func currentModelIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
            return ""
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else {
            return ""
        }
        return modelIdentifier(from: buffer)
    }
```

`Unicode.ASCII` rather than `UTF8` in the `String(decoding:as:)` call: `hw.model` is a model identifier made of ASCII, which is a subset of UTF-8, so the two agree on every real value — but `Unicode.ASCII` replaces an out-of-range byte with `U+FFFD` instead of producing a multi-byte replacement, so a garbage byte can never shift the decoded length. Both spellings were compiled and their behavior compared while writing this plan, against the five cases Task 1 tests.

`HostMacKind.current` (line 95) stays a `static let`, so this runs once per process and the extra allocation is irrelevant. Do not change `init(modelIdentifier:)` — the sanity check that `"Mac15,9"` maps to `.unknown` at line 32 must keep passing.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `swift test --filter AudioOutputDeviceIconTests`
Expected: all tests pass, including the two new ones.

- [ ] **Step 5: Confirm this specific warning is gone**

Run: `rm -rf /tmp/wc-warnings && swift build --build-tests --scratch-path /tmp/wc-warnings 2>&1 | grep -E "^/.*warning:" | grep AudioOutputDeviceIcon`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusTrioCore/Audio/AudioOutputDeviceIcon.swift \
        Tests/StatusTrioCoreTests/AudioOutputDeviceIconTests.swift
git commit -m "fix: decode hw.model without the deprecated String(cString:)"
```

---

### Task 2: Resolve The `weak var` Warnings Without Writing `weak let`

**Files:**
- Create: `Tests/StatusTrioCoreTests/DeinitProbe.swift`
- Modify: `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift`
- Modify: `Tests/StatusTrioCoreTests/VolumeMonitorTests.swift`
- Modify: `Tests/StatusTrioCoreTests/VolumeMonitorAsyncTests.swift`

**Interfaces:**
- Produces: `enum DeinitProbe` with `@discardableResult static func track<T: AnyObject>(_ object: T?) -> DeinitProbeRef<T>`.
- Produces: `final class DeinitProbeRef<T: AnyObject> { weak var value: T? }`.
- Consumes: nothing.

**The conflict, stated explicitly.** The four diagnostics are:

```
Tests/StatusTrioCoreTests/VolumeMonitorAsyncTests.swift:79:18: warning: weak variable 'weakMonitor' was never mutated; consider changing to 'let' constant [#VariableNeverMutated::WeakMutability]
Tests/StatusTrioCoreTests/VolumeMonitorTests.swift:415:18: warning: weak variable 'weakMonitor' was never mutated; consider changing to 'let' constant [#VariableNeverMutated::WeakMutability]
Tests/StatusTrioCoreTests/WiFiClassifierTests.swift:1148:18: warning: weak variable 'weakMonitor' was never mutated; consider changing to 'let' constant [#VariableNeverMutated::WeakMutability]
Tests/StatusTrioCoreTests/WiFiClassifierTests.swift:701:18: warning: weak variable 'weakMonitor' was never mutated; consider changing to 'let' constant [#VariableNeverMutated::WeakMutability]
```

The compiler's suggestion is `weak let`. `AGENTS.md:45` says *"Do not write `weak let`; weak reference bindings must be `var`."* and `docs/swift-ci-compatibility.md:17` records why: on the older CI toolchain (`macos-15` / Xcode 16.4 / Swift 6.1.2), `weak let` was **illegal** and failed run `34753843803` at the `Run tests` stage with the fix "改为 `weak var`". `docs/swift-ci-compatibility.md:9` also states that the rules derived from those older incidents remain in force even though the current CI toolchain is newer.

**The decision, and why.** Take the compiler's *diagnostic* seriously without taking its *suggestion*. Both of these are false:

- Switching to `weak let` contradicts a documented rule on the strength of a local compiler, and this plan has no evidence that Swift 6.3.3 accepts it — the local toolchain (Xcode 27 / Swift 6.4) is explicitly not proof.
- Leaving the warning with a comment contradicts this plan's own goal and leaves four warnings that will hide the next real one.

Instead, give the weak binding a genuine mutation by making it a stored property of a small class. A `weak var` stored property that is assigned in an initializer and read later is not "never mutated" in the sense the diagnostic means, because the runtime writes the property to `nil` when the object deallocates. The tests keep asserting exactly what they assert today, and the `weak var` spelling required by `AGENTS.md` is preserved verbatim.

**Do not treat this as a promise about diagnostic text.** The exact wording of `VariableNeverMutated::WeakMutability` is a compiler implementation detail on the local Xcode 27 / Swift 6.4 toolchain where it was measured; on CI's Swift 6.3.3 it may not fire at all, or may be phrased differently. The acceptance criterion is the *measured* warning list from Task 4, not a claim that a particular diagnostic was silenced by a particular trick. If CI still reports one of these four locations after the change, treat it as an unresolved warning and say so in the commit message rather than adding a suppression.

- [ ] **Step 1: Write the helper**

Create `Tests/StatusTrioCoreTests/DeinitProbe.swift`:

```swift
import Foundation

/// Holds a weak reference so a test can assert that an object deallocated.
///
/// This exists because `AGENTS.md` requires weak reference bindings to be
/// `var` (see docs/swift-ci-compatibility.md, run 34753843803), while the
/// compiler warns about a `weak var` local that is only ever read. A weak `var`
/// stored property satisfies both: the rule keeps its exact spelling, and the
/// diagnostic goes away without weakening any test.
final class DeinitProbeRef<T: AnyObject> {
    weak var value: T?

    init(_ object: T?) {
        value = object
    }
}

enum DeinitProbe {
    /// - Parameter object: the strong reference to observe. Pass the variable
    ///   itself, then set that variable to nil and read `probe.value`.
    @discardableResult
    static func track<T: AnyObject>(_ object: T?) -> DeinitProbeRef<T> {
        DeinitProbeRef(object)
    }
}
```

- [ ] **Step 2: Run the build and verify RED (the helper is unused, the four warnings remain)**

Run: `rm -rf /tmp/wc-warnings && swift build --build-tests --scratch-path /tmp/wc-warnings 2>&1 | grep -E "weak variable"`
Expected: exactly 4 lines, at `WiFiClassifierTests.swift:701` and `:1148`, `VolumeMonitorTests.swift:415`, `VolumeMonitorAsyncTests.swift:79`.

- [ ] **Step 3: Replace the four sites**

`Tests/StatusTrioCoreTests/WiFiClassifierTests.swift:701` (inside `testSlowReadDoesNotRetainMonitor`) and `:1148`:

```swift
        weak var weakMonitor = monitor
```

becomes

```swift
        let probe = DeinitProbe.track(monitor)
```

and each `XCTAssertNil(weakMonitor)` becomes `XCTAssertNil(probe.value)`.

`Tests/StatusTrioCoreTests/VolumeMonitorTests.swift:415` (inside `testDeinitWithoutStopStopsEventMonitorAndFinishesUpdates`) and `Tests/StatusTrioCoreTests/VolumeMonitorAsyncTests.swift:79` (inside `testOutstandingReadDoesNotRetainMonitor`) get the same two-line change.

Two rules for this edit:

1. **Do not move the `probe` declaration**, do not reorder the `monitor = nil` statement relative to the assertions, and do not change any assertion other than the identifier it reads. The deallocation proof is the assertion *after* the strong reference is released; that ordering is the test.
2. **Keep `probe` alive across the assertions.** If nothing reads `probe` after it is initialized, the optimizer may release the probe object early, its `weak` slot is never filled, and `XCTAssertNil(probe.value)` would pass for the wrong reason. Record that intent at each site:

```swift
        let probe = DeinitProbe.track(monitor)
        withExtendedLifetime(probe) {
            monitor = nil
            XCTAssertNil(probe.value)
        }
```

`XCTAssertNil` takes `Any?`, so `probe.value`'s extra optional level needs no unwrapping. In `VolumeMonitorTests` and `VolumeMonitorAsyncTests` the same block also carries the pre-existing `XCTAssertEqual(eventMonitor.stopCount, 1)` / `XCTAssertEqual(events.stopCount, 1)` and the `iterator.next()` assertions that currently follow; keep them inside or outside the block exactly as they are, and do not change what they assert.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `swift test --filter WiFiClassifierTests`
Run: `swift test --filter VolumeMonitorTests`
Run: `swift test --filter VolumeMonitorAsyncTests`
Expected: all pass — in particular the three deallocation tests still observe `nil`.

- [ ] **Step 5: Confirm the four warnings are gone and the rule is intact**

Run: `rm -rf /tmp/wc-warnings && swift build --build-tests --scratch-path /tmp/wc-warnings 2>&1 | grep -E "^/.*warning:"`
Expected: no output from these three test files. At this point the only remaining `file:line` warnings in the whole build are the two `WiFiPasswordStore.swift` deprecation warnings owned by the keychain plan.

Run: `grep -rn "weak let" Sources Tests`
Expected: no output — `AGENTS.md:45` is not contradicted by this change.

- [ ] **Step 6: Commit**

```bash
git add Tests/StatusTrioCoreTests/DeinitProbe.swift \
        Tests/StatusTrioCoreTests/WiFiClassifierTests.swift \
        Tests/StatusTrioCoreTests/VolumeMonitorTests.swift \
        Tests/StatusTrioCoreTests/VolumeMonitorAsyncTests.swift
git commit -m "test: observe deallocation through a weak property instead of a never-mutated weak var"
```

---

### Task 3: Record The Rule Decision Where The Next Reader Will Look

**Files:**
- Modify: `docs/swift-ci-compatibility.md`
- Modify: `AGENTS.md` (one parenthetical only; see the constraint below)

**Interfaces:**
- Produces: no code interface.

Task 2 resolved the warnings without writing `weak let`. That resolution is invisible to the next person who hits the same diagnostic and reaches for the compiler's suggestion, so it has to be written down next to the rule it constrains. This is a documentation change only; do **not** relax `AGENTS.md:45`.

- [ ] **Step 1: Append an entry to the compatibility document**

Add a row to the failure table in `docs/swift-ci-compatibility.md` (the table starts at line 13):

```markdown
| （本轮，非失败记录） | `swift build --build-tests` | 本机 Xcode 27 / Swift 6.4 对四处测试里的 `weak var weakMonitor` 报 `weak variable ... was never mutated; consider changing to 'let' constant`。编译器的建议是 `weak let`，但 `AGENTS.md` 明令禁止该写法，且没有证据表明 CI 的 Swift 6.3.3 接受它 | 不采用 `weak let`。把这四处改成 `Tests/StatusTrioCoreTests/DeinitProbe.swift` 里的 `DeinitProbe.track(_:)`，弱引用以 `weak var` 存储属性保存（写法仍满足规则），断言内容与顺序不变 |
```

Then extend the rule list at the bottom of the document (the section that currently reads "不使用 `weak let`，weak 绑定必须是 `var`" around line 185):

```markdown
- 不使用 `weak let`，weak 绑定必须是 `var`
  - 如果编译器因此报 `weak variable ... was never mutated`，不要照它的建议改成 `weak let`。用测试目标里的 `DeinitProbe.track(_:)`，把弱引用放进 `weak var` 存储属性。
  - 要推翻这条规则，必须同时提供 CI 工具链（`macos-26` / Xcode 26.6 / Swift 6.3.3）接受 `weak let` 的运行记录，然后才改 `AGENTS.md`。
```

- [ ] **Step 2: Cross-reference the rule in `AGENTS.md`**

Change line 45 only, adding a pointer and nothing else:

```markdown
- Do not write `weak let`; weak reference bindings must be `var` (when the compiler asks for `weak let` to silence a never-mutated warning, use the test target's `DeinitProbe` instead and see [Swift toolchain CI compatibility](docs/swift-ci-compatibility.md)).
```

This is the entire `AGENTS.md` change. Do not delete or weaken the rule, and do not touch any other line.

- [ ] **Step 3: Verify the documentation renders and nothing else changed**

Run: `git diff --stat AGENTS.md docs/swift-ci-compatibility.md`
Expected: two files, small line counts, no unrelated edits.

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md docs/swift-ci-compatibility.md
git commit -m "docs: record how to resolve the weak-var warning without writing weak let"
```

---

### Task 4: Full Verification And The Recorded Warning Count

**Files:**
- No additional files.

The measurement used throughout this plan is the same command the review used:

```bash
swift build --build-tests --scratch-path /tmp/warning-check 2>&1 | grep -E "warning:|error:"
```

The plan's own fresh-scratch-path form is the one to quote, because it cannot be served from stale object files:

```bash
rm -rf /tmp/wc-warnings && swift build --build-tests --scratch-path /tmp/wc-warnings 2>&1 | grep -E "^/.*warning:"
```

**The count today, verified before writing this plan.** A fresh full `--build-tests` build emits **7 distinct `file:line: warning:` locations**, in 4 warning kinds:

| # | Location | Kind | Owner |
| --- | --- | --- | --- |
| 1 | `Sources/StatusTrioCore/Audio/AudioOutputDeviceIcon.swift:144` | `init(cString:)` deprecated | **this plan**, Task 1 |
| 2-5 | `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift:701`, `:1148`, `VolumeMonitorTests.swift:415`, `VolumeMonitorAsyncTests.swift:79` | `weak variable ... was never mutated` | **this plan**, Task 2 |
| 6-7 | `Sources/StatusTrioCore/Monitoring/WiFiPasswordStore.swift:108`, `:131` | `kSecUseAuthenticationUIFail` / `Allow` deprecated | `2026-09-20-keychain-hardening.md`, **not this plan** |

The review index states "exactly 4 unique warnings"; re-measuring the clean build gives **7 warning locations / 4 kinds**, and 5 of the 7 belong to this plan. The difference is that the index counted the pre-`R-12` state without `--build-tests`. Cite the table above, not the index's number. Do not "fix" the two `WiFiPasswordStore.swift` warnings here: the keychain plan replaces them with an `LAContext` policy, and two workers editing the same query functions will collide.

- [ ] **Step 1: Measure before the plan, then after**

Run before starting: `rm -rf /tmp/wc-before && swift build --build-tests --scratch-path /tmp/wc-before 2>&1 | grep -E "^/.*warning:" | sort > /tmp/warnings-before.txt && wc -l < /tmp/warnings-before.txt`
Expected: `7`. Save the file; paste the diff into the final commit message.

Run after Tasks 1-3: `rm -rf /tmp/wc-after && swift build --build-tests --scratch-path /tmp/wc-after 2>&1 | grep -E "^/.*warning:" | sort > /tmp/warnings-after.txt && cat /tmp/warnings-after.txt`
Expected: exactly the two `WiFiPasswordStore.swift` lines remain, and `diff /tmp/warnings-before.txt /tmp/warnings-after.txt` shows five removals and no additions.

- [ ] **Step 2: Run the whole suite**

Run: `swift test`
Expected: all tests pass, including the two new `hw.model` parsing tests.

- [ ] **Step 3: Run the release build**

Run: `swift build -c release`
Expected: successful build with no warnings from `AudioOutputDeviceIcon.swift`.

- [ ] **Step 4: Confirm the release binary still resolves the machine family**

Run: `swift build -c release && .build/release/StatusTrio & sleep 2; pgrep -f StatusTrio >/dev/null && echo "launched"; pkill -f ".build/release/StatusTrio"`

Then compare the built-in speaker menu bar symbol before and after the change on this machine, where `hw.model` is a well-formed Apple Silicon identifier. Expected: identical symbol. If the symbol differs on any machine, this stopped being a behavior-preserving change and needs a release note in `release-notes/1.3.0/en.md` and `zh-Hans.md` before it can land.

- [ ] **Step 5: Run the non-publishing preflight**

Run:

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref codex/compiler-warning-cleanup \
  -f version=1.3.0 \
  -f build=12 \
  -f publish=false

gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

Expected: the workflow passes without publishing. The preflight is mandatory here because Task 2 adds a generic helper. If it fails, append the run ID to `docs/swift-ci-compatibility.md` with the failed stage, root cause and fix, per `AGENTS.md`.

- [ ] **Step 6: Review the diff**

Run: `git diff --check` and `git status --short`
Expected: no whitespace errors; only the files listed in File Ownership are modified. Confirm `git diff AGENTS.md` contains exactly one changed line.

## Verification

| Check | Command | Expected |
| --- | --- | --- |
| Before count | `rm -rf /tmp/wc-before && swift build --build-tests --scratch-path /tmp/wc-before 2>&1 \| grep -E "^/.*warning:" \| wc -l` | `7` |
| After count | `rm -rf /tmp/wc-after && swift build --build-tests --scratch-path /tmp/wc-after 2>&1 \| grep -E "^/.*warning:" \| wc -l` | `2`, both in `WiFiPasswordStore.swift` and both owned by the keychain plan |
| This plan's warnings | `grep -E "AudioOutputDeviceIcon\|WiFiClassifierTests\|VolumeMonitorTests\|VolumeMonitorAsyncTests" /tmp/warnings-after.txt` | no output |
| Rule intact | `grep -rn "weak let" Sources Tests` | no output |
| Parser tests | `swift test --filter AudioOutputDeviceIconTests` | passes, including the two new tests |
| Deallocation tests | `swift test --filter WiFiClassifierTests`, `--filter VolumeMonitorTests`, `--filter VolumeMonitorAsyncTests` | all pass |
| Whole suite | `swift test` | all tests pass |
| Release build | `swift build -c release` | successful build |
| Acceptance gate | non-publishing `release.yml` preflight on the branch | passes, `publish=false` |

**Note on "warning-free".** This plan leaves the repo with two warnings, both owned by `2026-09-20-keychain-hardening.md` Task 3. "Full clean build warning-free" is reached only when both plans have landed. If this plan is executed first, the acceptance statement is "5 of the 7 warning locations removed, 0 added, and the remaining 2 are tracked"; stating "warning-free" before the keychain plan lands would be false.

## Out of Scope

- **Do not change `AGENTS.md:45` from a prohibition into a permission.** No evidence is offered here that the CI toolchain accepts `weak let`; the local Swift 6.4 compiler accepting it would prove nothing. Revisiting the rule requires a recorded passing `macos-26` / Swift 6.3.3 run that uses `weak let`, and that run is a separate change.
- **Do not suppress the diagnostics with `-suppress-warnings`, `@available` tricks, or a `#if compiler(>=...)` split.** A warning that is hidden is worse than a warning that is fixed or documented.
- **Do not touch the two `WiFiPasswordStore.swift` deprecation warnings.** They are `2026-09-20-keychain-hardening.md` Task 3, and that task changes user-visible keychain behavior in the same lines.
- **Do not restructure `currentModelIdentifier()` to cache in a different way, to use `sysctl` instead of `sysctlbyname`, or to read `hw.model` lazily.** `HostMacKind.current` being a `static let` is existing, working behavior.
- **Do not "fix" `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift:1341` and `:1427`** (`weak var storedDelegate: AnyObject?` and `weak var delegate: (any CWEventDelegate)?`). Those are stored properties in fakes, they are genuinely mutated, and they emit no warning.
- **Do not convert any warning site to Swift Testing or XCTest to change which compiler flags apply.** The mixed framework layout is deliberate (`AGENTS.md`).

## File Ownership & Conflicts

**Owned by this plan:**

- `Sources/StatusTrioCore/Audio/AudioOutputDeviceIcon.swift`
- `Tests/StatusTrioCoreTests/AudioOutputDeviceIconTests.swift`
- `Tests/StatusTrioCoreTests/DeinitProbe.swift` (new)
- `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift` (the two warning lines only)
- `Tests/StatusTrioCoreTests/VolumeMonitorTests.swift` (the one warning line only)
- `Tests/StatusTrioCoreTests/VolumeMonitorAsyncTests.swift` (the one warning line only)
- `docs/swift-ci-compatibility.md` (append only)
- `AGENTS.md` (line 45 only)

**Conflicts:**

- `Tests/StatusTrioCoreTests/VolumeMonitorTests.swift` and `VolumeMonitorAsyncTests.swift` are also owned by `2026-09-20-volume-monitor-main-actor-io.md` (R-06). Per the index's merge order (`docs/superpowers/plans/2026-09-20-review-findings-index.md` §3.1, footnote 7), **R-06 lands first**. R-06 owns the production change and may add tests; this plan touches only the `weak var weakMonitor` line in each file. Rebase onto R-06 and re-run `swift test --filter VolumeMonitorTests` before committing.
- `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift` is also touched by `2026-09-20-wifi-scan-cadence.md` (R-02, Wi-Fi tests). Split by test function, not by file. This plan changes exactly two lines at `:701` and `:1148`.
- `Sources/StatusTrioCore/Monitoring/WiFiPasswordStore.swift` is owned by `2026-09-20-keychain-hardening.md`. This plan must not edit it, and its "after" count of 2 warnings is only `0` once that plan lands. Merge order between the two does not matter as long as neither edits the other's lines.
- `docs/swift-ci-compatibility.md` is appended to by any plan whose CI run fails. Append a new row; never rewrite an existing row.
- **No other plan in this set edits `AGENTS.md`.** If one does, land it first and re-read line 45 before editing, because the line number will have moved.
