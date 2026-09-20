# Preflight Validator and Appcast Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the release preflight fail loudly instead of skipping when release notes are absent, and make the appcast the preflight validates be the appcast that is actually published and committed.

**Architecture:** Two contract fixes in the release scripts, both pinned by subprocess tests that run under `swift test` so CI covers them without touching the workflow file. First, the notes-directory skip in `scripts/validate-appcast-notes.sh` becomes an `::error::` with a non-zero exit in every mode, matching the check `scripts/release.sh` already applies to both publishing and non-publishing runs. Second, the validator prints the identity of the document it validated (path, sha256, newest build, item count), the publish path writes the signed bytes it published back to the working tree and to `dist/`, and a new byte-comparison script asserts that the feed served after publication is byte-identical to the bytes that were validated and signed.

**Tech Stack:** Bash 3.2-compatible scripts, `cmp`/`shasum`/`xmllint`/`ruby`, XCTest subprocess tests (`Process`, matching `Tests/StatusTrioCoreTests/SingleInstanceGuardTests.swift`), GitHub Actions `macos-26`.

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
| Missing notes directory prints `::notice:: … skipping validation.` and exits **0** when `PUBLISH != true` | `scripts/validate-appcast-notes.sh:21-28` |
| `scripts/release.sh` hard-fails on the same missing directory, for **both** publish modes | `scripts/release.sh:142-147` |
| That asymmetry is the recorded root cause of CI run `35375443023` and is still unfixed | `docs/swift-ci-compatibility.md:24`, `:29-35` |
| The validator copies the **repository** copy of the appcast and generates the item into a temp directory | `scripts/validate-appcast-notes.sh:16`, `:62-63` |
| The non-publish path also validates the repository copy | `scripts/release.sh:114` |
| The publish path fetches the live feed, then publishes with `gh api --method PUT …/contents/$APPCAST_FILE` and never writes the working copy | `scripts/release.sh:108-114`, `:286-288` |
| The only post-publish check is a `grep` for the build number, not a comparison of the bytes | `scripts/release.sh:290-294` |
| The committed `appcast.xml` is 82,865 bytes with newest item 1.2.0 / build 9 and 7 items | `appcast.xml:22-23`; `grep -c '<item>' appcast.xml` = 7 |
| `Support/Info.plist` in the working tree is already 1.3.0 / build 11, so no 1.3.x item exists in any appcast yet | `Support/Info.plist:18-21` |
| The committed copy and the live feed are byte-identical today: `shasum -a 256` = `2f4bf90d3ddad9e4a0f63ad298504f34534d19b0b60e32810db7db42c2b63f7d`, and `curl …/main/appcast.xml` returns HTTP 200 with 82,865 bytes | measured while writing this plan |
| Worst case today is therefore not live-vs-committed drift; it is that **nothing enforces** the invariant and the preflight validates a document that contains no 1.3.x item at all | `scripts/validate-appcast-notes.sh:62`, `scripts/release.sh:114` |
| `release.sh` requires `shasum`, `xmllint`, `ruby` before doing anything | `scripts/release.sh:19-21` |
| The repository already tests scripts by running them as subprocesses | `Tests/StatusTrioCoreTests/SingleInstanceGuardTests.swift:78-111` |
| `ruby` on the maintenance machine is 2.6.10 and `rexml` is available; `File.readlines(path, chomp: true)`, `Dir.children`, `String#delete_suffix` are all used by the existing scripts | `ruby -v`; `scripts/update-appcast.rb:55-59` |

**Why the skip is wrong, stated plainly.** `scripts/release.sh:142-147` requires `release-notes/$VERSION` to exist before it builds anything, and that check runs *before* the `PUBLISH == false` early exit at `scripts/release.sh:238-241`. There is therefore no reachable state in which a release dispatch can succeed without the notes directory. The skip at `scripts/validate-appcast-notes.sh:21-28` cannot protect a legitimate dry run — it only delays the failure from a validator that costs two seconds to a release job that costs a full build, a universal release compile, a DMG and an installer, which is exactly what run `35375443023` recorded. The skip is removed rather than made opt-in.

## Review Focus

- **A preflight for a version without notes must fail at the validator, with the same reason `release.sh` would give.** A worker who dispatches `version=1.3.1` before writing `release-notes/1.3.1/` must read one clear error two seconds in, not a build failure ten minutes in. Pinned by `ReleaseScriptsTests.testValidateNotesFailsWhenTheNotesDirectoryIsMissing` for both `PUBLISH=false` and `PUBLISH=true`.
- **The bytes served must be the bytes that were validated and signed.** With feed signing enabled by the sibling plan, a mismatch between the validated document and the published one is a correctness bug in the trust chain, not a cosmetic drift. Pinned by `ReleaseScriptsTests.testCheckAppcastSyncRejectsDivergingDocuments` plus the release-path comparison in Task 4.
- **A stale committed copy must be visible, not silent.** The preflight currently says nothing about which document it read, so a validator that checked a document with no in-flight item looks identical to one that checked the right thing. Pinned by `ReleaseScriptsTests.testValidateNotesReportsTheDocumentIdentity`.
- **The validator must be usable against a document outside the repository.** `APPCAST_PATH="$ROOT/$APPCAST_FILE"` silently mangles an absolute path, which is what stops the rule above from being testable at all and what would break any future check that fetches the live feed first. Pinned by `ReleaseScriptsTests.testValidateNotesAcceptsAnAbsoluteAppcastPath`.
- **Signing must stay after item insertion.** The generated document's trailing signature block is invalidated the moment an item is inserted, so a future reorder of `scripts/release.sh` that signs before `update-appcast.rb` would publish a feed every client rejects. Pinned by `ReleaseScriptsTests.testReleaseScriptSignsTheAppcastAfterInsertingTheItem`, which asserts the line order in the script.

---

### Task 1: Fail loudly when release notes are missing

**Files:**
- Modify: `scripts/validate-appcast-notes.sh:10-28`
- Create: `Tests/StatusTrioCoreTests/ReleaseScriptsTests.swift`

**Interfaces:**
- Produces: `ReleaseScriptsTests.runScript(_:arguments:environment:) throws -> (status: Int32, output: String)`, `ReleaseScriptsTests.repositoryRoot`, `ReleaseScriptsTests.makeTemporaryDirectory()`.
- Produces: `scripts/validate-appcast-notes.sh` exits 1 with `::error::Release notes directory does not exist:` in every mode, and honours an absolute `APPCAST_FILE`.

**Decision, with the rejected alternative recorded.** There is no dry-run escape hatch. `release.sh:142-147` cannot proceed without the notes directory, so a documented opt-out would only re-create the masking behaviour of run `35375443023`; the alternative of adding `ALLOW_MISSING_NOTES=1` was rejected for that reason, and the incident history at `docs/swift-ci-compatibility.md:29-35` is the evidence.

- [ ] **Step 1: Write the failing tests**

Create `Tests/StatusTrioCoreTests/ReleaseScriptsTests.swift`:

```swift
import Foundation
import XCTest

final class ReleaseScriptsTests: XCTestCase {
    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // StatusTrioCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repository root

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StatusTrioReleaseScripts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    @discardableResult
    private func runScript(
        _ relativePath: String,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [Self.repositoryRoot.appendingPathComponent(relativePath).path] + arguments
        process.currentDirectoryURL = Self.repositoryRoot

        var merged = ProcessInfo.processInfo.environment
        for key in ["VERSION", "BUILD", "PUBLISH", "RELEASE_NOTES_DIR", "APPCAST_FILE"] {
            merged.removeValue(forKey: key)
        }
        merged.merge(environment) { _, new in new }
        process.environment = merged

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, output)
    }

    func testValidateNotesFailsWhenTheNotesDirectoryIsMissing() throws {
        let directory = try makeTemporaryDirectory()
        let missingNotes = directory.appendingPathComponent("release-notes/9.9.9").path

        for publish in ["false", "true"] {
            let result = try runScript(
                "scripts/validate-appcast-notes.sh",
                environment: [
                    "VERSION": "9.9.9",
                    "BUILD": "999",
                    "PUBLISH": publish,
                    "RELEASE_NOTES_DIR": missingNotes,
                    "APPCAST_FILE": "appcast.xml"
                ]
            )

            XCTAssertEqual(result.status, 1, "PUBLISH=\(publish) must fail: \(result.output)")
            XCTAssertTrue(
                result.output.contains("::error::Release notes directory does not exist"),
                "PUBLISH=\(publish) output was: \(result.output)"
            )
            XCTAssertFalse(
                result.output.contains("skipping validation"),
                "PUBLISH=\(publish) must not skip validation any more: \(result.output)"
            )
        }
    }

    func testValidateNotesAcceptsAnAbsoluteAppcastPath() throws {
        let directory = try makeTemporaryDirectory()
        let absoluteAppcast = directory.appendingPathComponent("appcast.xml")
        try """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>Status Trio</title>
          </channel>
        </rss>
        """.write(to: absoluteAppcast, atomically: true, encoding: .utf8)

        let result = try runScript(
            "scripts/validate-appcast-notes.sh",
            environment: [
                "VERSION": "1.3.0",
                "BUILD": "999",
                "PUBLISH": "false",
                "RELEASE_NOTES_DIR": Self.repositoryRoot.appendingPathComponent("release-notes/1.3.0").path,
                "APPCAST_FILE": absoluteAppcast.path
            ]
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Appcast notes OK"), result.output)
    }
}
```

- [ ] **Step 2: Run the tests and verify RED**

```bash
swift test --filter ReleaseScriptsTests
```

Expected: `testValidateNotesFailsWhenTheNotesDirectoryIsMissing` FAILs with `XCTAssertEqual failed: ("0") is not equal to ("1")` for `PUBLISH=false`, because `scripts/validate-appcast-notes.sh:26` prints the notice and exits 0. `testValidateNotesAcceptsAnAbsoluteAppcastPath` FAILs with a non-zero status and a `cp:` message, because `scripts/validate-appcast-notes.sh:16` builds `$ROOT/$APPCAST_FILE` from an absolute path.

- [ ] **Step 3: Remove the skip and accept an absolute appcast path**

In `scripts/validate-appcast-notes.sh`, replace line 16

```bash
APPCAST_PATH="$ROOT/$APPCAST_FILE"
```

with

```bash
case "$APPCAST_FILE" in
    /*) APPCAST_PATH="$APPCAST_FILE" ;;
    *) APPCAST_PATH="$ROOT/$APPCAST_FILE" ;;
esac
```

and replace the whole block at lines 21-28

```bash
if [[ ! -d "$NOTES_DIR" ]]; then
    if [[ "$PUBLISH" == "true" ]]; then
        echo "::error::Release notes directory does not exist: $NOTES_DIR"
        exit 1
    fi
    echo "::notice::Release notes directory does not exist yet: $NOTES_DIR — skipping validation."
    exit 0
fi
```

with

```bash
# No publish/non-publish branch: scripts/release.sh:142-147 requires this
# directory for both, so a non-publishing preflight cannot succeed without it
# either. Skipping here only moved the failure into the release job, which is
# what CI run 35375443023 recorded (docs/swift-ci-compatibility.md:24).
if [[ ! -d "$NOTES_DIR" ]]; then
    echo "::error::Release notes directory does not exist: $NOTES_DIR"
    echo "::error::Create release-notes/$VERSION/en.md and release-notes/$VERSION/zh-Hans.md before dispatching this workflow; scripts/release.sh fails on the same condition."
    exit 1
fi
```

- [ ] **Step 4: Run the tests and verify GREEN**

```bash
swift test --filter ReleaseScriptsTests
bash -n scripts/validate-appcast-notes.sh
```

Expected: both tests PASS; `bash -n` silent with exit 0.

- [ ] **Step 5: Confirm the publish-mode behaviour on the real notes**

```bash
VERSION=1.3.0 BUILD=12 bash scripts/validate-appcast-notes.sh
VERSION=9.9.9 BUILD=999 bash scripts/validate-appcast-notes.sh; echo "exit=$?"
```

Expected: the first prints `Release notes coverage for 1.3.0: 12/12 languages` and `Appcast notes OK: 12 titles and 12 descriptions, en first.`; the second prints the two `::error::` lines and `exit=1`.

- [ ] **Step 6: Commit**

```bash
git add scripts/validate-appcast-notes.sh Tests/StatusTrioCoreTests/ReleaseScriptsTests.swift
git commit -m "fix: fail the release preflight when release notes are missing"
```

---

### Task 2: Report which appcast the preflight validated

**Files:**
- Modify: `scripts/validate-appcast-notes.sh` (after the notes-directory check)
- Test: `Tests/StatusTrioCoreTests/ReleaseScriptsTests.swift`

**Interfaces:**
- Produces: one log line `Appcast under validation: <path> (sha256 <hex>, newest build <N>, <M> items)` printed before the item is generated; `::error::Appcast file does not exist:` / `::error::Appcast has no </channel>:` / `::error::Appcast is empty:` otherwise.
- Consumes: the absolute-path handling from Task 1.

- [ ] **Step 1: Write the failing test**

Append to `Tests/StatusTrioCoreTests/ReleaseScriptsTests.swift`:

```swift
    func testValidateNotesReportsTheDocumentIdentity() throws {
        let result = try runScript(
            "scripts/validate-appcast-notes.sh",
            environment: [
                "VERSION": "1.3.0",
                "BUILD": "999",
                "PUBLISH": "false",
                "RELEASE_NOTES_DIR": Self.repositoryRoot.appendingPathComponent("release-notes/1.3.0").path,
                "APPCAST_FILE": "appcast.xml"
            ]
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("Appcast under validation: "),
            "the preflight must say which document it read: \(result.output)"
        )
        XCTAssertTrue(
            result.output.range(of: "sha256 [0-9a-f]{64}", options: .regularExpression) != nil,
            "the identity line must carry the document hash: \(result.output)"
        )
        XCTAssertTrue(
            result.output.range(of: "newest build [0-9]+", options: .regularExpression) != nil,
            "the identity line must carry the newest build in the document: \(result.output)"
        )
    }

    func testValidateNotesRejectsAnEmptyAppcast() throws {
        let directory = try makeTemporaryDirectory()
        let emptyAppcast = directory.appendingPathComponent("appcast.xml")
        try "".write(to: emptyAppcast, atomically: true, encoding: .utf8)

        let result = try runScript(
            "scripts/validate-appcast-notes.sh",
            environment: [
                "VERSION": "1.3.0",
                "BUILD": "999",
                "PUBLISH": "false",
                "RELEASE_NOTES_DIR": Self.repositoryRoot.appendingPathComponent("release-notes/1.3.0").path,
                "APPCAST_FILE": emptyAppcast.path
            ]
        )

        XCTAssertEqual(result.status, 1, result.output)
        XCTAssertTrue(result.output.contains("::error::Appcast is empty"), result.output)
    }
```

- [ ] **Step 2: Run the tests and verify RED**

```bash
swift test --filter ReleaseScriptsTests
```

Expected: both new tests FAIL — `testValidateNotesReportsTheDocumentIdentity` on the missing `Appcast under validation: ` substring, `testValidateNotesRejectsAnEmptyAppcast` on `XCTAssertEqual failed: ("0") is not equal to ("1")` (an empty file reaches `xmllint` and, with no items, produces no error today).

- [ ] **Step 3: Add the identity line and the document guards**

In `scripts/validate-appcast-notes.sh`, insert directly after the notes-directory check:

```bash
require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "::error::Required command '$1' is not available." >&2
        exit 1
    fi
}

for command in shasum grep sort sed awk; do
    require_command "$command"
done

if [[ ! -f "$APPCAST_PATH" ]]; then
    echo "::error::Appcast file does not exist: $APPCAST_PATH"
    exit 1
fi

if [[ ! -s "$APPCAST_PATH" ]]; then
    echo "::error::Appcast is empty: $APPCAST_PATH"
    exit 1
fi

if ! grep -qF '</channel>' "$APPCAST_PATH"; then
    echo "::error::Appcast has no </channel>: $APPCAST_PATH"
    exit 1
fi

newest_build_in() {
    local value
    value="$(grep -o '<sparkle:version>[0-9]*</sparkle:version>' "$1" 2>/dev/null \
        | sed 's/[^0-9]//g' | sort -n | tail -1 || true)"
    printf '%s' "${value:-none}"
}

item_count_in() {
    grep -c '<item>' "$1" 2>/dev/null || true
}

# The preflight used to validate the committed copy without saying so, which made
# a document with no in-flight item indistinguishable from the right one in the
# log. scripts/check-appcast-sync.sh compares this copy against the live feed.
echo "Appcast under validation: $APPCAST_PATH (sha256 $(shasum -a 256 "$APPCAST_PATH" | awk '{print $1}'), newest build $(newest_build_in "$APPCAST_PATH"), $(item_count_in "$APPCAST_PATH") items)"
```

- [ ] **Step 4: Run the tests and verify GREEN**

```bash
swift test --filter ReleaseScriptsTests
VERSION=1.3.0 BUILD=12 bash scripts/validate-appcast-notes.sh | head -3
```

Expected: all four tests PASS; the manual run's first line is
`Appcast under validation: /Users/…/status-trio/appcast.xml (sha256 2f4bf90d…, newest build 9, 7 items)`.

- [ ] **Step 5: Commit**

```bash
git add scripts/validate-appcast-notes.sh Tests/StatusTrioCoreTests/ReleaseScriptsTests.swift
git commit -m "build: report which appcast the release preflight validated"
```

---

### Task 3: Compare two appcast documents byte for byte

**Files:**
- Create: `scripts/check-appcast-sync.sh`
- Test: `Tests/StatusTrioCoreTests/ReleaseScriptsTests.swift`

**Interfaces:**
- Produces: `bash scripts/check-appcast-sync.sh <validated.xml> <published.xml>` — exits 0 and prints `Appcast sync OK: … are byte-identical.` when the two files are identical; exits 1 and prints both documents' sha256, newest build and item count when they differ.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/StatusTrioCoreTests/ReleaseScriptsTests.swift`:

```swift
    private func writeAppcast(_ builds: [Int], to url: URL) throws {
        let items = builds.map { build in
            """
                <item>
                  <sparkle:version>\(build)</sparkle:version>
                  <enclosure url="https://example.invalid/StatusTrio-\(build).dmg"
                             sparkle:edSignature="AAAA"
                             length="1" />
                </item>
            """
        }.joined(separator: "\n")

        try """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>Status Trio</title>
        \(items)
          </channel>
        </rss>
        """.write(to: url, atomically: true, encoding: .utf8)
    }

    func testCheckAppcastSyncAcceptsIdenticalDocuments() throws {
        let directory = try makeTemporaryDirectory()
        let validated = directory.appendingPathComponent("validated.xml")
        let published = directory.appendingPathComponent("published.xml")
        try writeAppcast([12, 9], to: validated)
        try writeAppcast([12, 9], to: published)

        let result = try runScript("scripts/check-appcast-sync.sh", arguments: [validated.path, published.path])
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Appcast sync OK"), result.output)
    }

    func testCheckAppcastSyncRejectsDivergingDocuments() throws {
        let directory = try makeTemporaryDirectory()
        let validated = directory.appendingPathComponent("validated.xml")
        let published = directory.appendingPathComponent("published.xml")
        try writeAppcast([12, 9], to: validated)
        try writeAppcast([9], to: published)

        let result = try runScript("scripts/check-appcast-sync.sh", arguments: [validated.path, published.path])
        XCTAssertEqual(result.status, 1, result.output)
        XCTAssertTrue(result.output.contains("::error::"), result.output)
        XCTAssertTrue(result.output.contains("validated: "), result.output)
        XCTAssertTrue(result.output.contains("published: "), result.output)
        XCTAssertTrue(result.output.contains("newest build 12"), result.output)
        XCTAssertTrue(result.output.contains("newest build 9"), result.output)
    }
```

- [ ] **Step 2: Run the tests and verify RED**

```bash
swift test --filter ReleaseScriptsTests
```

Expected: both new tests FAIL with `XCTAssertEqual failed: ("127") …`, because `/bin/bash <repo>/scripts/check-appcast-sync.sh` exits 127 with `No such file or directory`.

- [ ] **Step 3: Implement the comparison**

Create `scripts/check-appcast-sync.sh`:

```bash
#!/usr/bin/env bash
# Compares the appcast that was validated and signed with the appcast that is
# actually being served, byte for byte.
#
# A build-number grep is not enough: scripts/release.sh:290-294 only checked that
# the published feed mentioned the new build, so a feed that lost an item, gained
# an item, or carried a different signature block would still pass. Feed signing
# makes this a trust-chain check rather than a cosmetic one.
set -euo pipefail

VALIDATED="${1:?Usage: bash scripts/check-appcast-sync.sh <validated.xml> <published.xml>}"
PUBLISHED="${2:?Usage: bash scripts/check-appcast-sync.sh <validated.xml> <published.xml>}"

for file in "$VALIDATED" "$PUBLISHED"; do
    if [[ ! -f "$file" ]]; then
        echo "::error::Appcast file does not exist: $file"
        exit 1
    fi
done

describe() {
    local file="$1"
    local value
    value="$(grep -o '<sparkle:version>[0-9]*</sparkle:version>' "$file" 2>/dev/null \
        | sed 's/[^0-9]//g' | sort -n | tail -1 || true)"
    printf 'newest build %s, %s items, sha256 %s' \
        "${value:-none}" \
        "$(grep -c '<item>' "$file" 2>/dev/null || true)" \
        "$(shasum -a 256 "$file" | awk '{print $1}')"
}

if cmp -s "$VALIDATED" "$PUBLISHED"; then
    echo "Appcast sync OK: the validated and published appcasts are byte-identical."
    exit 0
fi

{
    echo "::error::The published appcast is not the appcast that was validated and signed."
    echo "  validated: $VALIDATED ($(describe "$VALIDATED"))"
    echo "  published: $PUBLISHED ($(describe "$PUBLISHED"))"
} >&2
exit 1
```

- [ ] **Step 4: Run the tests and verify GREEN**

```bash
swift test --filter ReleaseScriptsTests
bash -n scripts/check-appcast-sync.sh
bash scripts/check-appcast-sync.sh appcast.xml appcast.xml
```

Expected: all six tests PASS; `bash -n` silent; the manual run prints `Appcast sync OK: the validated and published appcasts are byte-identical.`

- [ ] **Step 5: Commit**

```bash
git add scripts/check-appcast-sync.sh Tests/StatusTrioCoreTests/ReleaseScriptsTests.swift
git commit -m "build: compare the validated and published appcasts byte for byte"
```

---

### Task 4: Make the published appcast and the committed copy converge

**Files:**
- Modify: `scripts/release.sh:290-297`
- Test: `Tests/StatusTrioCoreTests/ReleaseScriptsTests.swift`

**Interfaces:**
- Consumes: `scripts/check-appcast-sync.sh` (Task 3).
- Produces: the publish path fetches the served feed after `gh api --method PUT`, fails unless it is byte-identical to the bytes that were validated and signed, then writes those bytes back to `$ROOT/$APPCAST_FILE` and `$OUTPUT_DIR/$APPCAST_FILE`, and prints `git diff --stat` to show whether the working copy moved.

**Decision, with the rejected alternative recorded.** Writing the bytes back was chosen over "document the committed copy as intentionally stale". The committed copy is not stale by design — `scripts/validate-appcast-notes.sh:62` and the non-publish path at `scripts/release.sh:114` both read it, so a copy that lags the live feed silently weakens the max-build check and makes the preflight's subject different from the release's subject. Convergence also keeps `bash scripts/release.sh` usable as the documented manual fallback (AGENTS.md, "Release Rules"). Because the branch itself is updated by `gh api --method PUT`, the write-back is what makes a *local* publish leave a consistent checkout and what puts the exact published bytes into `dist/` for inspection; it does not replace the API commit.

- [ ] **Step 1: Write the failing structural test**

The publish path cannot be executed in a test — it needs `gh` authentication and would create a Release — so the ordering constraint that this task must not break is pinned structurally, and the byte comparison itself is pinned by Task 3's tests.

Append to `Tests/StatusTrioCoreTests/ReleaseScriptsTests.swift`:

```swift
    private func lineNumber(of needle: String, in text: String) throws -> Int {
        let index = try XCTUnwrap(
            text.split(separator: "\n", omittingEmptySubsequences: false)
                .firstIndex(where: { $0.contains(needle) }),
            "scripts/release.sh has no line containing '\(needle)'"
        )
        return index + 1
    }

    func testReleaseScriptSignsTheAppcastAfterInsertingTheItem() throws {
        let text = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("scripts/release.sh"),
            encoding: .utf8
        )

        let insert = try lineNumber(of: "scripts/update-appcast.rb", in: text)
        let sign = try lineNumber(of: "scripts/sign-appcast.sh", in: text)
        let publish = try lineNumber(of: "--method PUT", in: text)
        let compare = try lineNumber(of: "scripts/check-appcast-sync.sh", in: text)
        let writeBack = try lineNumber(of: "cp \"$APPCAST_PATH\" \"$ROOT/$APPCAST_FILE\"", in: text)

        XCTAssertLessThan(insert, sign, "signing must follow item insertion: inserting an item invalidates the signature block.")
        XCTAssertLessThan(sign, publish, "the published bytes must be the signed bytes.")
        XCTAssertLessThan(publish, compare, "the served feed can only be compared after it is published.")
        XCTAssertLessThan(compare, writeBack, "never write the working copy before the published feed is proven identical.")
    }

    func testReleaseScriptKeepsTheBuildPresenceCheck() throws {
        let text = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("scripts/release.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(
            text.contains("published appcast does not contain build $BUILD"),
            "the existing build-number check must stay alongside the byte comparison"
        )
    }
```

- [ ] **Step 2: Run the tests and verify RED**

```bash
swift test --filter ReleaseScriptsTests
```

Expected: `testReleaseScriptSignsTheAppcastAfterInsertingTheItem` FAILs with `scripts/release.sh has no line containing 'scripts/check-appcast-sync.sh'` (and, on a tree where the sibling signed-feed plan has not landed, on `scripts/sign-appcast.sh` first). `testReleaseScriptKeepsTheBuildPresenceCheck` PASSes today and is the guard that this task does not delete it.

- [ ] **Step 3: Replace the post-publish check with the byte comparison and the write-back**

In `scripts/release.sh`, replace lines 290-294

```bash
if ! gh api "repos/$RELEASE_REPO/contents/$APPCAST_FILE?ref=$RELEASE_BRANCH" \
    -H "Accept: application/vnd.github.raw" | grep -Fq "<sparkle:version>$BUILD</sparkle:version>"; then
    echo "Error: published appcast does not contain build $BUILD." >&2
    exit 1
fi
```

with

```bash
PUBLISHED_APPCAST_PATH="$TEMP_ROOT/appcast.published.xml"
gh api "repos/$RELEASE_REPO/contents/$APPCAST_FILE?ref=$RELEASE_BRANCH" \
    -H "Accept: application/vnd.github.raw" > "$PUBLISHED_APPCAST_PATH"

if ! grep -Fq "<sparkle:version>$BUILD</sparkle:version>" "$PUBLISHED_APPCAST_PATH"; then
    echo "Error: published appcast does not contain build $BUILD." >&2
    exit 1
fi

# The served feed must be the bytes that were validated, signed and uploaded.
bash "$ROOT/scripts/check-appcast-sync.sh" "$APPCAST_PATH" "$PUBLISHED_APPCAST_PATH"

# Keep the working copy and the local release directory in step with what users
# are now being served. The branch itself was already updated by the API commit;
# this is what makes a local `bash scripts/release.sh` leave a consistent
# checkout, and what puts the published bytes into dist/ for inspection.
cp "$APPCAST_PATH" "$ROOT/$APPCAST_FILE"
cp "$APPCAST_PATH" "$OUTPUT_DIR/$APPCAST_FILE"
echo "Working copy updated:"
git -C "$ROOT" diff --stat -- "$APPCAST_FILE" || true
```

- [ ] **Step 4: Run the tests and verify GREEN**

```bash
swift test --filter ReleaseScriptsTests
bash -n scripts/release.sh
```

Expected: all eight tests PASS; `bash -n` silent with exit 0.

- [ ] **Step 5: Prove the comparison can fail, by hand**

```bash
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioAppcastSync.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cp appcast.xml "$WORK/validated.xml"
sed 's|<sparkle:version>9</sparkle:version>|<sparkle:version>99</sparkle:version>|' appcast.xml > "$WORK/published.xml"

if bash scripts/check-appcast-sync.sh "$WORK/validated.xml" "$WORK/published.xml"; then
  echo "Expected the comparison to reject a diverging feed." >&2
  exit 1
fi

bash scripts/check-appcast-sync.sh "$WORK/validated.xml" "$WORK/validated.xml"
```

Expected: the first call prints `::error::The published appcast is not the appcast that was validated and signed.` with `newest build 9` for the validated file and `newest build 99` for the published one, and the outer `if` does not fire; the second call prints `Appcast sync OK`.

- [ ] **Step 6: Commit**

```bash
git add scripts/release.sh Tests/StatusTrioCoreTests/ReleaseScriptsTests.swift
git commit -m "build: converge the published and committed appcasts"
```

---

### Task 5: Full verification

**Files:**
- No production files.

- [ ] **Step 1: Run the full test suite**

```bash
swift test
```

Expected: all tests pass, including the eight `ReleaseScriptsTests`.

- [ ] **Step 2: Run the release build**

```bash
swift build -c release
```

Expected: successful build.

- [ ] **Step 3: Re-run the validator assertions by hand**

```bash
VERSION=1.3.0 BUILD=12 bash scripts/validate-appcast-notes.sh
VERSION=9.9.9 BUILD=999 bash scripts/validate-appcast-notes.sh; echo "exit=$?"
bash scripts/check-appcast-sync.sh appcast.xml appcast.xml
```

Expected: `Release notes coverage for 1.3.0: 12/12 languages`, the identity line, `Appcast notes OK: 12 titles and 12 descriptions, en first.`; then two `::error::` lines and `exit=1`; then `Appcast sync OK`.

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

Expected: the workflow passes. The `Validate appcast notes` log shows the identity line naming `appcast.xml` with its sha256 and newest build 9, then `Appcast notes OK`. No GitHub Release is created and `appcast.xml` is unchanged on the branch.

The same dispatch with `-f version=1.3.1` must fail in `Validate appcast notes` within seconds, with `::error::Release notes directory does not exist:` — the exact failure that run `35375443023` reached only after its release job started. Record the new run ID next to that row in the compatibility table when it is verified.

- [ ] **Step 5: Record any failed CI run**

If CI fails, append a row to `docs/swift-ci-compatibility.md` with the run ID, failed stage, reproducible root cause, fix and verification run, per `docs/swift-ci-compatibility.md:44-54`. Run `35375443023` already has its row; add the verification run that proves the skip is gone.

- [ ] **Step 6: Review the diff**

```bash
git status --short
git diff --check
```

Expected: only `scripts/validate-appcast-notes.sh`, `scripts/check-appcast-sync.sh`, `scripts/release.sh`, `Tests/StatusTrioCoreTests/ReleaseScriptsTests.swift` and `docs/swift-ci-compatibility.md` changed, with no whitespace errors.

## Verification

1. `swift test` and `swift build -c release` pass on the CI toolchain (`macos-26`, Xcode 26.6, Swift 6.3.3).
2. `ReleaseScriptsTests` proves: the missing-notes skip is gone in both `PUBLISH` modes, an absolute `APPCAST_FILE` is honoured, the identity line carries a sha256 and the newest build, an empty appcast is rejected, the byte comparison accepts identical documents and rejects diverging ones, and `scripts/release.sh` keeps the ordering `update-appcast.rb` → `sign-appcast.sh` → `PUT` → `check-appcast-sync.sh` → write-back.
3. `VERSION=1.3.0 BUILD=12 bash scripts/validate-appcast-notes.sh` prints the identity line and `Appcast notes OK`.
4. A `publish=false` preflight passes and shows the identity line in its log.
5. A `publish=false` preflight for a version with no notes fails inside `Validate appcast notes`, not inside the build job.
6. The publish path's byte comparison and the working-copy write-back are exercised by the next real release; until then they are covered by the structural test and by Task 4 Step 5's manual proof that the comparison can fail.

## Out of Scope

- **`ALLOW_MISSING_NOTES` / a documented dry-run skip.** Rejected; see the decision under Task 1. `release.sh:142-147` makes the notes directory mandatory in every mode, so an opt-out would only reintroduce the masking that run `35375443023` recorded.
- **Comparing the live feed against the committed copy at preflight time as a hard failure.** Rejected as a false-positive generator: a feature branch cut before a release legitimately carries an older `appcast.xml` than `main`, so a hard check would block its preflight for a reason unrelated to the change. `scripts/check-appcast-sync.sh` is instead the explicit operator command (`bash scripts/check-appcast-sync.sh "$(mktemp)" appcast.xml`) and the hard check runs only where it cannot false-positive — after a publish, on the bytes that were just uploaded.
- **Uploading `dist/appcast.xml` as a CI artifact.** `scripts/release.sh` writes it, but the workflow's artifact path list is owned by plan R-10 (`2026-09-20-release-pipeline-hardening.md`); add `dist/appcast.xml` to `path:` there.
- **Signing the feed.** Owned by plan R-08 (`2026-09-20-signed-update-feed.md`), which lands first. This plan only guarantees that whatever signing produces is what gets published and committed.
- **Backfilling the missing 1.2.1 item.** The live feed and the committed copy both stop at build 9 (verified by hash while writing this plan), so there is nothing to reconcile; `Support/Info.plist` being 1.3.0 / build 11 is normal in-flight state, because an item only exists once a release is published.
- **A `swift test` case that runs `scripts/release.sh`.** It performs a full release build and requires `gh`, so the publish path stays covered structurally plus manually rather than being executed in the test suite.

## File Ownership & Conflicts

**Owned by this plan**

| File | Change |
| --- | --- |
| `scripts/validate-appcast-notes.sh` | drop the skip, accept an absolute `APPCAST_FILE`, print the validated document's identity, guard empty/non-channel documents |
| `scripts/check-appcast-sync.sh` | new byte comparison |
| `scripts/release.sh` | post-publish byte comparison replaces the bare grep; write the published bytes back to `$ROOT/$APPCAST_FILE` and `$OUTPUT_DIR/$APPCAST_FILE` |
| `Tests/StatusTrioCoreTests/ReleaseScriptsTests.swift` | new subprocess tests |
| `docs/swift-ci-compatibility.md` | verification row for the fixed `35375443023` root cause |

**Conflicts with other plans in this set** (matrix: `2026-09-20-review-findings-index.md` §3.1)

- **R-08 (`2026-09-20-signed-update-feed.md`) — the hard conflict on `scripts/release.sh`, and the recommended merge order is R-08 first.** §3.1 already records it: "**R-08 lands first** (it changes how the appcast is generated/signed). R-17 then adjusts the validator contract and the working-copy sync." Concretely, R-08 inserts `bash "$ROOT/scripts/sign-appcast.sh" "$APPCAST_PATH"` between the `update-appcast.rb` call and `xmllint --noout "$APPCAST_PATH"` (`scripts/release.sh:269-271`). This plan rebases on that and must preserve three ordering rules, all pinned by `testReleaseScriptSignsTheAppcastAfterInsertingTheItem`: item insertion before signing (inserting an item invalidates the trailing signature block), signing before the `PUT` (the uploaded bytes must be signed), and the `PUT` plus the byte comparison before the working-copy write-back (never commit bytes that are not proven served). Do not run R-08 and R-17 in parallel; two workers editing `scripts/release.sh` at once will lose one of the two insertions.
- **R-08 also owns `appcast.xml`, which this plan's write-back overwrites at publish time.** The write-back must copy the **signed** bytes produced by R-08's `scripts/sign-appcast.sh`. If a rebase places the write-back before the signing call, the working copy would silently lose its signature and R-08's `SignedUpdateFeedTests.testCommittedAppcastSignatureVerifiesAgainstPinnedPublicKey` would fail on the next `swift test` — that test is the cross-check.
- **R-10 (`2026-09-20-release-pipeline-hardening.md`) — `.github/workflows/release.yml`.** Not touched here. This plan deliberately reaches CI through `swift test` (which the workflow already runs at `release.yml:245`) and through `scripts/release.sh` (invoked at `release.yml:262`) instead of adding a workflow step, so it does not collide with R-10's rewrite of that file. The `dist/appcast.xml` artifact path and any explicit `check-appcast-sync.sh` step belong to whoever lands R-10 second.
- **`docs/swift-ci-compatibility.md` is shared by every plan in this set** (§3.3 rule 4). Append a row; do not rewrite the table. If another plan has already added rows, add yours at the end.
- **No conflict with R-09 (`2026-09-20-update-source-fallback-policy.md`)** — different files, and R-09's Outcome does not change the appcast generation or publication contract.
