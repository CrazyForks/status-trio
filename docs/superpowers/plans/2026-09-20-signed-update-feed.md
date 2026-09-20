# Signed Update Feed Implementation Plan

> **STATUS: DEFERRED — do not start (owner decision, 2026-09-20).** Sparkle auto-update works today and must not be disrupted for the existing user base. Enabling `SURequireSignedFeed` together with `SUVerifyUpdateBeforeExtraction` changes the trust contract for every build that ships it and permanently fixes the EdDSA key, so it requires a staged rollout, a verified rollback, and a proof that the published feed passes verification *before* it reaches users. See `2026-09-20-review-findings-index.md` §0.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Sparkle authenticate the appcast feed itself, not only the DMG inside it: sign the committed feed, turn on `SURequireSignedFeed` with the `SUVerifyUpdateBeforeExtraction` it requires, make `scripts/release.sh` emit a signed feed on every publish, and fail the build when a feed is unsigned or an item lacks `sparkle:edSignature`/`length`.

**Architecture:** Sparkle 2.9.0 added opt-in feed signing (upstream commit `7761e65c`, "Add support for signing and verifying appcast feeds (#2822)"). A signed feed is the appcast document followed by one trailing XML comment, `<!-- sparkle-signatures:` / `edSignature: <base64>` / `length: <byte count>` / `-->`, whose signature covers every byte that precedes it. `sign_update` already implements both signing and verification for `.xml` feed inputs, so this plan does not invent a format: it makes the release path call `sign_update` on the generated appcast, verifies the result cryptographically in the release path and against the pinned public key in `swift test`, and adds a structural verifier that needs no secret so it can also run on the committed feed. Note that this pipeline builds its appcast with `scripts/update-appcast.rb`, **not** with `generate_appcast`; `grep -rn generate_appcast scripts/ .github/workflows/` returns nothing, so the vendored `generate_appcast` behaviour (`generate_appcast/ArchiveItem.swift:256-261`) is context, not the code path being changed.

**Tech Stack:** Swift 6 / SwiftPM (macOS 15 deployment target), Sparkle 2.9.6 (resolved revision `ac2def28`), Ed25519 via `CryptoKit` in tests and via Sparkle's `sign_update` in the pipeline, Ruby 2.6-compatible scripting, Bash, GitHub Actions `macos-26`.

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

Every line below was re-read while writing this plan.

| Fact | Location |
| --- | --- |
| `SUFeedURL` = `https://raw.githubusercontent.com/lingyired/status-trio/main/appcast.xml` (mutable `main` branch); `SUPublicEDKey` = `N5FLwhXCzo7Z/8z3lOWbOJ7aW04hvXxI7LUk+6f+yDQ=`; **no** `SURequireSignedFeed`, **no** `SUVerifyUpdateBeforeExtraction` | `Support/Info.plist:35-38` |
| The feed signature is only checked when the app opts in | `.build/checkouts/Sparkle/Sparkle/SUAppcastDriver.m:95` (`if (_host.requiresSignedAppcast)`) |
| Opt-in key name is `SURequireSignedFeed` | `.build/checkouts/Sparkle/Sparkle/SUConstants.m:36`; `SUHost.m:229-232` |
| Verify-before-extraction key name | `.build/checkouts/Sparkle/Sparkle/SUConstants.m:37` |
| **`SURequireSignedFeed` forces `SUVerifyUpdateBeforeExtraction`**: the updater refuses to start with `SUInvalidUpdaterError` if the latter is absent, and `UpdaterManager.start()` surfaces that as a modal alert | `.build/checkouts/Sparkle/Sparkle/SPUUpdater.m:373-386`; `Sources/StatusTrioCore/App/UpdaterManager.swift:52-56` |
| The upgrade decision uses the feed's declared version | `.build/checkouts/Sparkle/Sparkle/SUAppcastDriver.m:275` (`compareVersion:_host.version toVersion:notFoundPrimaryItem.versionString`) |
| Feed signing/verification is a `.xml`-suffix mode of `sign_update`; it embeds the block and rewrites the file in place | `.build/checkouts/Sparkle/sign_update/main.swift:132-134`, `:237-251`, `:110-111` |
| Exact signed-feed byte format | `.build/checkouts/Sparkle/common_cli/Signing.swift:85-99` |
| Extraction is a **backwards** search for the block prefix; a missing suffix returns the whole document | `.build/checkouts/Sparkle/Sparkle/SPUExtractSignedFeed.m:13-32` |
| A base64-encoded 32-byte seed is a valid private-key file (`--ed-key-file`), so tests need no Keychain | `.build/checkouts/Sparkle/common_cli/Secret.swift:11-13`, `:23-46` |
| Every item in the committed feed already carries `sparkle:edSignature` and a decimal `length` (7 items, builds 9/8/5/4/3/2/1) | `appcast.xml:22-114` |
| The committed feed and the live feed are today **byte-identical** (`shasum -a 256` = `2f4bf90d3ddad9e4a0f63ad298504f34534d19b0b60e32810db7db42c2b63f7d`, 82,865 bytes, newest item 1.2.0 / build 9) while the working tree is 1.3.0 / build 11 | `appcast.xml`; `Support/Info.plist:18-21` |
| `scripts/build-app.sh` copies `Support/Info.plist` verbatim and then overwrites only `CFBundleIdentifier`, `CFBundleDisplayName`, `CFBundleName`, `CFBundleShortVersionString`, `CFBundleVersion`, `STDevelopmentCodename`, `SUFeedURL` — `SUPublicEDKey` is never rewritten | `scripts/build-app.sh:129-148` |
| The publish path fetches the live feed, adds the item with `scripts/update-appcast.rb`, then `xmllint --noout`, then `gh api --method PUT` | `scripts/release.sh:108-114`, `:258-273`, `:276-287` |
| Existing trust posture: DMGs are EdDSA-signed before upload | `scripts/release.sh:188-213` |

**What is actually at risk.** Because every enclosure already carries `sparkle:edSignature` and `length`, remote code execution still requires the private key — the feed writer cannot forge an installable update. What is unauthenticated today is the *document*: the declared `sparkle:version`, the release-notes HTML, and the download URL. A writer who controls the feed bytes can point the enclosure at an old, genuinely signed DMG and declare a huge `sparkle:version`, which makes Sparkle offer, download and install a rollback; or silently rewrite/suppress release notes. Turning on `SURequireSignedFeed` closes that hole.

## Review Focus

- **`SURequireSignedFeed` without `SUVerifyUpdateBeforeExtraction` bricks the updater.** `SPUUpdater.m:373-386` returns `SUInvalidUpdaterError`, and `UpdaterManager.start()` turns that into `NSAlert(error: error).runModal()` at launch: the user sees an error dialog and never gets an update check again. Pinned by `SignedUpdateFeedTests.testInfoPlistRequiresSignedFeedAndVerifiesBeforeExtraction` (Task 2).
- **The signing key can silently be the wrong one.** Appending a valid Ed25519 signature made with a key that is not `SUPublicEDKey` produces a feed every shipping client rejects while the file "looks signed". Pinned by `SignedUpdateFeedTests.testCommittedAppcastSignatureVerifiesAgainstPinnedPublicKey` (Task 2), which verifies the committed bytes against the pinned key and needs no secret.
- **Every item must keep an explicit `<sparkle:version>`.** With signing active, `signingValidationStatus` is no longer `Skipped`, so Sparkle stops inferring the version from the enclosure filename (`SUAppcastItem.m:485-495`); an item without the element becomes unparseable and the whole item is dropped. Pinned by `SignedUpdateFeedTests.testEveryItemDeclaresANumericSparkleVersion` (Task 2).
- **The block must be the last bytes of the feed, and there must be exactly one.** Extraction searches backwards and stops at the *last* prefix (`SPUExtractSignedFeed.m:18`), so a second block left behind by a bad merge would be signed over rather than removed, and any byte after the block would be outside the signature. Pinned by `verify-signed-appcast.rb`'s exact-one-block and end-of-file assertions, exercised in Task 1 and Task 3.
- **Signed feeds reject external release-notes references.** Upstream ships this hardening with the feature (commit `7761e65c`: "The standard user driver's release notes HTML web view rejects external file references when appcasts are signed"). Status Trio embeds notes inline as `<description xml:lang="…"><![CDATA[…]]></description>` (`appcast.xml:24`) and must keep doing so; a future move to `<sparkle:releaseNotesLink>` would need its own signature. Pinned by `SignedUpdateFeedTests.testItemDescriptionsStayInlineAndLocalized`.

---

### Task 1: Verify a signed feed, and sign the committed one

**Files:**
- Create: `scripts/verify-signed-appcast.rb`
- Modify: `appcast.xml` (append one `sparkle-signatures` block; no other byte changes)

**Interfaces:**
- Produces: `ruby scripts/verify-signed-appcast.rb <path-to-appcast.xml>` — exits 0 only when the document has exactly one `sparkle-signatures` block, the block is the final bytes of the file, `edSignature` base64-decodes to 64 bytes, `length` equals the byte count of the content before the block, and every `<item>` has a numeric `<sparkle:version>` plus an `<enclosure>` carrying `sparkle:edSignature` (64 bytes decoded) and a positive decimal `length`. Never reads a private key.
- Consumes: the Sparkle private key (from `SPARKLE_PRIVATE_KEY`, else the login Keychain) and `$SIGN_UPDATE` at `.build/artifacts/sparkle/Sparkle/bin/sign_update`.

**Prerequisite:** signing `appcast.xml` needs the Sparkle private key whose public half is `SUPublicEDKey` in `Support/Info.plist:38`. It is available either as the `SPARKLE_PRIVATE_KEY` repository secret or as the `ed25519` Keychain item on the release machine. If neither exists on your machine, stop after Task 1 Step 1 and complete the rest of this plan with the maintainer; do not substitute a different key.

- [ ] **Step 1: Write the failing assertion**

The verifier does not exist yet, which is the failure this step records:

```bash
ruby scripts/verify-signed-appcast.rb appcast.xml
```

Expected: FAIL — `ruby: No such file or directory -- scripts/verify-signed-appcast.rb (LoadError)`.

- [ ] **Step 2: Implement the structural verifier**

Create `scripts/verify-signed-appcast.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Verifies that a Sparkle appcast is a correctly formed signed feed.
#
# This is the structural half of the check and deliberately needs no secret, so
# it runs on the committed feed in any preflight. The cryptographic half lives
# in Tests/StatusTrioCoreTests/SignedUpdateFeedTests.swift (public key only) and
# in scripts/sign-appcast.sh (sign_update --verify, release path only).
#
# Format reference: Sparkle common_cli/Signing.swift:85-99 writes
#   "<!-- sparkle-signatures:\nedSignature: <base64>\nlength: <bytes>\n-->\n"
# and Sparkle/SPUExtractSignedFeed.m:11-32 finds the *last* occurrence of the
# prefix and treats everything before it as the signed content.

require "base64"
require "optparse"

BLOCK_MARKER = "<!-- sparkle-signatures:"
BLOCK = /\A<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+\/=]+)\nlength: (\d+)\n-->\n\z/

def fail_with(message)
  warn "::error::#{message}"
  exit 1
end

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/verify-signed-appcast.rb <appcast.xml>"
  parser.on("--quiet") { options[:quiet] = true }
end.parse!

path = ARGV.fetch(0) { fail_with("Usage: ruby scripts/verify-signed-appcast.rb <appcast.xml>") }
fail_with("Appcast file does not exist: #{path}") unless File.file?(path)

data = File.binread(path)
marker_count = data.scan(BLOCK_MARKER).length
fail_with("Appcast has #{marker_count} sparkle-signatures blocks, expected exactly 1: #{path}") unless marker_count == 1

block_start = data.rindex(BLOCK_MARKER)
block = data[block_start..-1]
match = BLOCK.match(block)
unless match
  fail_with("Appcast signing block is malformed or is not the final bytes of #{path}.")
end

content = data[0...block_start]
declared_length = Integer(match[2], 10)
if declared_length != content.bytesize
  fail_with("Appcast signs #{declared_length} bytes but #{content.bytesize} bytes precede the block.")
end

signature = Base64.strict_decode64(match[1])
if signature.bytesize != 64
  fail_with("Appcast Ed25519 signature is #{signature.bytesize} bytes, expected 64.")
end

items = content.scan(%r{[ \t]*<item>.*?</item>}m)
fail_with("Appcast has no <item> elements.") if items.empty?

items.each_with_index do |item, index|
  unless item.match?(%r{<sparkle:version>\s*\d+\s*</sparkle:version>})
    fail_with("Appcast item #{index + 1} has no numeric <sparkle:version>; signed feeds cannot infer it from the enclosure URL.")
  end

  enclosure = item[%r{<enclosure\b.*?/>}m]
  fail_with("Appcast item #{index + 1} has no <enclosure>.") unless enclosure

  ed_signature = enclosure[/sparkle:edSignature="([^"]+)"/, 1]
  fail_with("Appcast item #{index + 1} enclosure has no sparkle:edSignature.") unless ed_signature
  item_signature = Base64.strict_decode64(ed_signature)
  if item_signature.bytesize != 64
    fail_with("Appcast item #{index + 1} edSignature is #{item_signature.bytesize} bytes, expected 64.")
  end

  length = enclosure[/\blength="(\d+)"/, 1]
  fail_with("Appcast item #{index + 1} enclosure has no length attribute.") unless length
  fail_with("Appcast item #{index + 1} enclosure length is zero.") unless Integer(length, 10).positive?
end

puts "Signed appcast OK: #{items.length} items, signature over #{content.bytesize} bytes." unless options[:quiet]
```

- [ ] **Step 3: Run the verifier and watch it fail for the right reason**

```bash
ruby -c scripts/verify-signed-appcast.rb
ruby scripts/verify-signed-appcast.rb appcast.xml
```

Expected: `Syntax OK`, then FAIL — `::error::Appcast has 0 sparkle-signatures blocks, expected exactly 1: appcast.xml`, exit status 1. The committed feed is genuinely unsigned today, so this is the real defect, not a scaffolding error.

- [ ] **Step 4: Sign the committed feed**

GitHub-hosted CI supplies the key as a secret; a local release machine has it in the login Keychain. Run whichever matches your machine:

```bash
SIGN_UPDATE="$PWD/.build/artifacts/sparkle/Sparkle/bin/sign_update"
test -x "$SIGN_UPDATE" || { echo "sign_update missing; run: swift build" >&2; exit 1; }

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" \
    | env -u SPARKLE_PRIVATE_KEY "$SIGN_UPDATE" --ed-key-file - --disable-signing-warning appcast.xml
else
  "$SIGN_UPDATE" --disable-signing-warning appcast.xml
fi
```

`--disable-signing-warning` is deliberate: without it `sign_update` re-serializes the document through `XMLDocument` to insert a warning comment (`common_cli/Signing.swift:37-80`), which rewrites bytes throughout a feed that carries 12 `<title xml:lang>` nodes and escaped CDATA. With the flag, `SPUExtractAppcastContent` returns the original bytes untouched (`SPUExtractSignedFeed.m:20-24`) and only the block is appended — the byte-for-byte guarantee the old-client migration in Task 5 depends on. The human-facing warning is replaced by the verifier assertions below, which fail the build instead of merely commenting.

- [ ] **Step 5: Verify the signature cryptographically with the same key**

```bash
SIGN_UPDATE="$PWD/.build/artifacts/sparkle/Sparkle/bin/sign_update"
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | env -u SPARKLE_PRIVATE_KEY "$SIGN_UPDATE" --ed-key-file - --verify appcast.xml
else
  "$SIGN_UPDATE" --verify appcast.xml
fi
```

Expected: no output, exit status 0. `sign_update --verify` in feed mode takes no second argument (`sign_update/main.swift:157-163`) and reads the embedded block itself.

- [ ] **Step 6: Run the structural verifier again**

```bash
ruby scripts/verify-signed-appcast.rb appcast.xml
xmllint --noout appcast.xml
git diff --stat -- appcast.xml
```

Expected: PASS — `Signed appcast OK: 7 items, signature over 82865 bytes.`; `xmllint` silent with exit 0 (a trailing comment after the root element is legal XML `Misc`, verified while writing this plan); `git diff --stat` shows `1 file changed, 4 insertions(+)` because the only change is the appended four-line block (`<!-- sparkle-signatures:`, `edSignature: …`, `length: …`, `-->`) and no existing byte moved.

- [ ] **Step 7: Commit**

```bash
git add scripts/verify-signed-appcast.rb appcast.xml
git commit -m "fix: sign the published appcast feed"
```

---

### Task 2: Pin the trust contract in `Support/Info.plist` and in tests

**Files:**
- Modify: `Support/Info.plist`
- Create: `Tests/StatusTrioCoreTests/SignedUpdateFeedTests.swift`

**Interfaces:**
- Consumes: `appcast.xml` signed in Task 1; `slurp`-style repository-root lookup derived from `#filePath`, matching `Tests/StatusTrioCoreTests/TestSupport/SocialCoverSheet.swift:28`.
- Produces: `SignedUpdateFeedTests` (XCTest) whose seams are `repositoryRoot`, `loadInfoPlist()`, `extractSignedFeed(_:) throws -> SignedFeed`, and `feedItems(in:)`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/StatusTrioCoreTests/SignedUpdateFeedTests.swift`:

```swift
import CryptoKit
import Foundation
import XCTest

final class SignedUpdateFeedTests: XCTestCase {
    private static let signedBlockPrefix = Data("<!-- sparkle-signatures:\n".utf8)

    private struct SignedFeed {
        let content: Data
        let signature: Data
        let declaredLength: Int
        let blockCount: Int
    }

    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func loadInfoPlist() throws -> [String: Any] {
        let url = Self.repositoryRoot.appendingPathComponent("Support/Info.plist")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any]
        )
    }

    private func loadAppcast() throws -> Data {
        try Data(contentsOf: Self.repositoryRoot.appendingPathComponent("appcast.xml"))
    }

    private func extractSignedFeed(_ data: Data) throws -> SignedFeed {
        let blockCount = data.occurrenceCount(of: Self.signedBlockPrefix)
        let prefixRange = try XCTUnwrap(
            data.range(of: Self.signedBlockPrefix, options: .backwards),
            "appcast.xml carries no sparkle-signatures block"
        )
        let content = data[data.startIndex..<prefixRange.lowerBound]
        let remainder = data[prefixRange.upperBound...]
        let suffixRange = try XCTUnwrap(
            remainder.range(of: Data("-->".utf8)),
            "appcast signing block is not terminated by -->"
        )
        let blockText = String(decoding: remainder[remainder.startIndex..<suffixRange.lowerBound], as: UTF8.self)

        var signatureBase64: String?
        var declaredLength: Int?
        for line in blockText.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("edSignature:") {
                signatureBase64 = line.dropFirst("edSignature:".count)
                    .trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("length:") {
                declaredLength = Int(line.dropFirst("length:".count).trimmingCharacters(in: .whitespaces))
            }
        }

        return SignedFeed(
            content: Data(content),
            signature: Data(base64Encoded: try XCTUnwrap(signatureBase64, "signing block has no edSignature line")),
            declaredLength: try XCTUnwrap(declaredLength, "signing block has no length line"),
            blockCount: blockCount
        )
    }

    private func feedItems(in data: Data) -> [String] {
        let text = String(decoding: data, as: UTF8.self)
        let expression = try? NSRegularExpression(pattern: "<item>.*?</item>", options: [.dotMatchesLineSeparators])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return (expression?.matches(in: text, options: [], range: range) ?? []).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    func testInfoPlistRequiresSignedFeedAndVerifiesBeforeExtraction() throws {
        let plist = try loadInfoPlist()

        XCTAssertEqual(plist["SURequireSignedFeed"] as? Bool, true)
        XCTAssertEqual(
            plist["SUVerifyUpdateBeforeExtraction"] as? Bool,
            true,
            "Sparkle refuses to start with SUInvalidUpdaterError when SURequireSignedFeed is set without SUVerifyUpdateBeforeExtraction (SPUUpdater.m:373-386)."
        )
    }

    func testPinnedPublicKeyIsAnEd25519KeyAndFeedURLIsHTTPS() throws {
        let plist = try loadInfoPlist()

        let key = try XCTUnwrap(plist["SUPublicEDKey"] as? String)
        let keyData = try XCTUnwrap(Data(base64Encoded: key))
        XCTAssertEqual(keyData.count, 32, "SUPublicEDKey must decode to a 32-byte Ed25519 public key.")

        let feedURL = try XCTUnwrap(plist["SUFeedURL"] as? String)
        let url = try XCTUnwrap(URL(string: feedURL))
        XCTAssertEqual(url.scheme, "https")
    }

    func testCommittedAppcastSignatureVerifiesAgainstPinnedPublicKey() throws {
        let plist = try loadInfoPlist()
        let keyData = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(plist["SUPublicEDKey"] as? String)))
        let feed = try extractSignedFeed(try loadAppcast())

        XCTAssertEqual(feed.blockCount, 1, "Exactly one signing block is allowed: the extractor only strips the last one.")
        XCTAssertEqual(feed.declaredLength, feed.content.count)
        XCTAssertEqual(feed.signature.count, 64)

        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        XCTAssertTrue(
            publicKey.isValidSignature(feed.signature, for: feed.content),
            "appcast.xml is not signed by the key pinned in Support/Info.plist."
        )
    }

    func testEveryItemDeclaresANumericSparkleVersion() throws {
        let items = feedItems(in: try loadAppcast())
        XCTAssertEqual(items.count, 7)

        for (index, item) in items.enumerated() {
            XCTAssertNotNil(
                item.range(of: "<sparkle:version>[0-9]+</sparkle:version>", options: .regularExpression),
                "item \(index + 1) needs an explicit numeric sparkle:version: a signed feed no longer infers it from the enclosure URL."
            )
        }
    }

    func testEveryEnclosureCarriesASignatureAndLength() throws {
        for (index, item) in feedItems(in: try loadAppcast()).enumerated() {
            let signature = try XCTUnwrap(
                item.range(of: "sparkle:edSignature=\"([^\"]+)\"", options: .regularExpression),
                "item \(index + 1) enclosure has no sparkle:edSignature"
            )
            let base64 = String(item[signature])
                .replacingOccurrences(of: "sparkle:edSignature=\"", with: "")
                .replacingOccurrences(of: "\"", with: "")
            XCTAssertEqual(Data(base64Encoded: base64)?.count, 64, "item \(index + 1) signature is not 64 bytes")

            let length = try XCTUnwrap(
                item.range(of: "length=\"([0-9]+)\"", options: .regularExpression),
                "item \(index + 1) enclosure has no length"
            )
            XCTAssertNotEqual(String(item[length]), "length=\"0\"")
        }
    }

    func testItemDescriptionsStayInlineAndLocalized() throws {
        for (index, item) in feedItems(in: try loadAppcast()).enumerated() {
            XCTAssertNil(
                item.range(of: "<sparkle:releaseNotesLink>"),
                "item \(index + 1) uses an external release-notes link; signed feeds reject external references, so notes must stay inline."
            )
            XCTAssertNotNil(item.range(of: "<description xml:lang=\"en\">"))
        }
    }

    /// Old clients (any build without SURequireSignedFeed) never call
    /// SPUExtractAppcastContent, so they parse the document *including* the
    /// trailing signing block. This reproduces that parse with Sparkle's own
    /// reader options (SUAppcast.m:82-84).
    func testSignedFeedStillParsesAsPlainXMLForOldClients() throws {
        let document = try XMLDocument(
            data: try loadAppcast(),
            options: [.nodeLoadExternalEntitiesNever]
        )
        let items = try document.nodes(forXPath: "/rss/channel/item")
        XCTAssertEqual(items.count, 7)
    }
}

private extension Data {
    func occurrenceCount(of needle: Data) -> Int {
        var count = 0
        var searchStart = startIndex
        while let found = range(of: needle, options: [], in: searchStart..<endIndex) {
            count += 1
            searchStart = found.upperBound
        }
        return count
    }
}
```

- [ ] **Step 2: Run the tests and verify RED**

```bash
swift test --filter SignedUpdateFeedTests
```

Expected: `testInfoPlistRequiresSignedFeedAndVerifiesBeforeExtraction` FAILs with `XCTAssertEqual failed: ("nil") is not equal to ("Optional(true)")` — `Support/Info.plist` has no such key yet. `testCommittedAppcastSignatureVerifiesAgainstPinnedPublicKey` PASSes already because Task 1 signed the feed, and that is the point: it is the guard that proves your Task 1 signature used the pinned key.

- [ ] **Step 3: Add the two keys**

Insert both keys after `SUEnableInstallerLauncherService` in `Support/Info.plist` so the Sparkle block stays together:

```bash
/usr/libexec/PlistBuddy -c 'Add :SURequireSignedFeed bool true' Support/Info.plist
/usr/libexec/PlistBuddy -c 'Add :SUVerifyUpdateBeforeExtraction bool true' Support/Info.plist
plutil -lint Support/Info.plist
/usr/libexec/PlistBuddy -c 'Print :SURequireSignedFeed' Support/Info.plist
/usr/libexec/PlistBuddy -c 'Print :SUVerifyUpdateBeforeExtraction' Support/Info.plist
```

Expected: `Support/Info.plist: OK`, then `true` twice. Do not add `SUAllowsInsecureUpdates` and do not set `SUSignedFeedFailureExpirationInterval`: the reviewed default is 20 days (`SUAppcastDriver.m:39`, `:136-138`), after which Sparkle may present sanitised items instead of failing closed, and changing that value is a separate decision.

- [ ] **Step 4: Run the tests and verify GREEN**

```bash
swift test --filter SignedUpdateFeedTests
```

Expected: all 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Support/Info.plist Tests/StatusTrioCoreTests/SignedUpdateFeedTests.swift
git commit -m "feat: require a signed Sparkle feed and verify updates before extraction"
```

---

### Task 3: Emit a signed feed from the release path

**Files:**
- Create: `scripts/sign-appcast.sh`
- Modify: `scripts/release.sh:258-274` (sign between the appcast update and `xmllint`)

**Interfaces:**
- Consumes: `scripts/verify-signed-appcast.rb` (Task 1); `$SIGN_UPDATE`; `SPARKLE_PRIVATE_KEY` or the login Keychain.
- Produces: `bash scripts/sign-appcast.sh <path-to-appcast.xml>` — signs the feed in place, then verifies it cryptographically (`sign_update --verify`) and structurally (`verify-signed-appcast.rb`). Exits non-zero when the path does not end in `.xml`, when the file is missing, when `$SIGN_UPDATE` is not executable, or when either verification fails.

- [ ] **Step 1: Write the failing assertion**

```bash
bash scripts/sign-appcast.sh
```

Expected: FAIL — `bash: scripts/sign-appcast.sh: No such file or directory`, exit status 127.

- [ ] **Step 2: Implement the signing script**

Create `scripts/sign-appcast.sh`:

```bash
#!/usr/bin/env bash
# Signs a Sparkle appcast feed in place and verifies the result.
#
# sign_update decides between "sign an update archive" and "sign an appcast
# feed" by the .xml suffix alone (sign_update/main.swift:132-134). A temp file
# named without that suffix would silently print an enclosure signature instead
# of embedding one, so the suffix is asserted rather than assumed.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APPCAST_PATH="${1:?Usage: bash scripts/sign-appcast.sh <path-to-appcast.xml>}"
SIGN_UPDATE="${SIGN_UPDATE:-$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update}"
SPARKLE_PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:-}"

if [[ ! -f "$APPCAST_PATH" ]]; then
    echo "Error: appcast file does not exist: $APPCAST_PATH" >&2
    exit 1
fi

case "$APPCAST_PATH" in
    *.xml|*.XML) ;;
    *)
        echo "Error: sign_update only signs a feed when the path ends in .xml: $APPCAST_PATH" >&2
        exit 1
        ;;
esac

if [[ ! -x "$SIGN_UPDATE" ]]; then
    echo "Error: Sparkle sign_update was not found at $SIGN_UPDATE." >&2
    exit 1
fi

if [[ -n "$SPARKLE_PRIVATE_KEY" ]]; then
    printf '%s' "$SPARKLE_PRIVATE_KEY" \
        | env -u SPARKLE_PRIVATE_KEY "$SIGN_UPDATE" --ed-key-file - --disable-signing-warning "$APPCAST_PATH"
    printf '%s' "$SPARKLE_PRIVATE_KEY" \
        | env -u SPARKLE_PRIVATE_KEY "$SIGN_UPDATE" --ed-key-file - --verify "$APPCAST_PATH"
else
    "$SIGN_UPDATE" --disable-signing-warning "$APPCAST_PATH"
    "$SIGN_UPDATE" --verify "$APPCAST_PATH"
fi

ruby "$ROOT/scripts/verify-signed-appcast.rb" "$APPCAST_PATH"
```

- [ ] **Step 3: Prove the round trip with a throwaway key**

No Keychain and no production key are touched: a base64-encoded 32-byte seed is a valid `--ed-key-file` secret (`Secret.swift:11-13`).

```bash
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioSignAppcast.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
SEED="$(head -c 32 /dev/urandom | base64)"
cp appcast.xml "$WORK/appcast.xml"

# Strip Task 1's block so the fixture starts unsigned.
ruby -e '
  data = File.binread(ARGV[0])
  index = data.rindex("<!-- sparkle-signatures:")
  File.binwrite(ARGV[0], index ? data[0...index] : data)
' "$WORK/appcast.xml"

SPARKLE_PRIVATE_KEY="$SEED" bash scripts/sign-appcast.sh "$WORK/appcast.xml"
ruby scripts/verify-signed-appcast.rb "$WORK/appcast.xml"

# Tampering after signing must fail verification.
printf '<!-- tampered -->' >> "$WORK/appcast.xml"
if ruby scripts/verify-signed-appcast.rb "$WORK/appcast.xml"; then
  echo "Expected the verifier to reject a tampered feed." >&2
  exit 1
fi

# A non-.xml path must be refused before sign_update is invoked.
if bash scripts/sign-appcast.sh "$WORK/appcast"; then
  echo "Expected a non-.xml path to be refused." >&2
  exit 1
fi
```

Expected: the first run prints `Signed appcast OK: 7 items, signature over 82865 bytes.`; the tampered run prints `::error::Appcast signing block is malformed or is not the final bytes of …` and the outer `if` does not fire; the non-`.xml` run prints `Error: sign_update only signs a feed when the path ends in .xml` and the outer `if` does not fire.

- [ ] **Step 4: Wire signing into the publish path**

In `scripts/release.sh`, the block that currently reads:

```bash
    --appcast "$APPCAST_PATH"

xmllint --noout "$APPCAST_PATH"
```

becomes:

```bash
    --appcast "$APPCAST_PATH"

bash "$ROOT/scripts/sign-appcast.sh" "$APPCAST_PATH"
xmllint --noout "$APPCAST_PATH"
```

Do not move the `--appcast "$APPCAST_PATH"` argument. Everything from `ruby "$ROOT/scripts/update-appcast.rb"` through `gh api --method PUT` is publish-only (`PUBLISH=false` exits earlier), and the publish path always has either `SPARKLE_PRIVATE_KEY` or the Keychain, so signing never runs without a key by accident.

- [ ] **Step 5: Confirm the non-publish path is untouched**

```bash
bash -n scripts/release.sh
bash -n scripts/sign-appcast.sh
git diff -- scripts/release.sh
```

Expected: both `bash -n` calls silent with exit 0; the diff shows exactly one added line (`bash "$ROOT/scripts/sign-appcast.sh" "$APPCAST_PATH"`).

- [ ] **Step 6: Commit**

```bash
git add scripts/sign-appcast.sh scripts/release.sh
git commit -m "build: sign the generated appcast before publishing"
```

---

### Task 4: Assert the trust anchors survive packaging

**Files:**
- Create: `scripts/verify-app-bundle-plist.sh`
- Modify: `scripts/release.sh:249-259` (assert the built bundle right after `scripts/build-app.sh` returns)

**Interfaces:**
- Consumes: `scripts/build-app.sh:129-148` (the verbatim `Info.plist` copy and the `SUFeedURL` overwrite).
- Produces: `bash scripts/verify-app-bundle-plist.sh <path-to-.app> [expected-feed-url]` — exits 0 only when the packaged `Contents/Info.plist` carries a 32-byte `SUPublicEDKey` byte-equal to `Support/Info.plist`, an `https://` `SUFeedURL` (equal to the expected URL when one is given), and `true` for both `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction`. Runs in both the publish and non-publish paths.

- [ ] **Step 1: Write the failing assertion**

```bash
bash scripts/verify-app-bundle-plist.sh dist/StatusTrio.app "https://raw.githubusercontent.com/lingyired/status-trio/main/appcast.xml"
```

Expected: FAIL — `bash: scripts/verify-app-bundle-plist.sh: No such file or directory`, exit status 127.

- [ ] **Step 2: Implement the bundle assertion**

Create `scripts/verify-app-bundle-plist.sh`:

```bash
#!/usr/bin/env bash
# Asserts the packaged app still carries the update trust anchors.
#
# scripts/build-app.sh copies Support/Info.plist verbatim and then rewrites
# only the bundle/version keys and SUFeedURL (build-app.sh:129-148). A future
# edit that instead rewrites the whole plist would silently drop SUPublicEDKey
# and every installed copy would stop accepting updates, so the packaged file
# is checked rather than the source file.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_PATH="${1:?Usage: bash scripts/verify-app-bundle-plist.sh <app-bundle> [expected-feed-url]}"
EXPECTED_FEED_URL="${2:-}"
SOURCE_PLIST="$ROOT/Support/Info.plist"
BUNDLE_PLIST="$BUNDLE_PATH/Contents/Info.plist"

print_plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

if [[ ! -f "$BUNDLE_PLIST" ]]; then
    echo "Error: packaged Info.plist does not exist: $BUNDLE_PLIST" >&2
    exit 1
fi

SOURCE_KEY="$(print_plist_value "$SOURCE_PLIST" SUPublicEDKey)"
BUNDLE_KEY="$(print_plist_value "$BUNDLE_PLIST" SUPublicEDKey)"

if [[ -z "$SOURCE_KEY" ]]; then
    echo "Error: Support/Info.plist has no SUPublicEDKey." >&2
    exit 1
fi

if [[ "$BUNDLE_KEY" != "$SOURCE_KEY" ]]; then
    echo "Error: packaged SUPublicEDKey is '$BUNDLE_KEY', expected '$SOURCE_KEY'." >&2
    exit 1
fi

if [[ "$(printf '%s' "$BUNDLE_KEY" | base64 --decode 2>/dev/null | wc -c | tr -d ' ')" != "32" ]]; then
    echo "Error: packaged SUPublicEDKey is not a 32-byte Ed25519 key." >&2
    exit 1
fi

BUNDLE_FEED_URL="$(print_plist_value "$BUNDLE_PLIST" SUFeedURL)"
if [[ "$BUNDLE_FEED_URL" != https://* ]]; then
    echo "Error: packaged SUFeedURL is not HTTPS: '$BUNDLE_FEED_URL'" >&2
    exit 1
fi

if [[ -n "$EXPECTED_FEED_URL" && "$BUNDLE_FEED_URL" != "$EXPECTED_FEED_URL" ]]; then
    echo "Error: packaged SUFeedURL is '$BUNDLE_FEED_URL', expected '$EXPECTED_FEED_URL'." >&2
    exit 1
fi

for key in SURequireSignedFeed SUVerifyUpdateBeforeExtraction; do
    if [[ "$(print_plist_value "$BUNDLE_PLIST" "$key")" != "true" ]]; then
        echo "Error: packaged Info.plist must set $key to true." >&2
        exit 1
    fi
done

echo "Packaged plist OK: pinned key, HTTPS feed, signed feed required."
```

- [ ] **Step 3: Prove it detects a dropped key**

```bash
bash scripts/build-app.sh release no-open
bash scripts/verify-app-bundle-plist.sh dist/StatusTrio.app \
  "https://raw.githubusercontent.com/lingyired/status-trio/main/appcast.xml"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioBundlePlist.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cp -R dist/StatusTrio.app "$WORK/StatusTrio.app"
/usr/libexec/PlistBuddy -c 'Delete :SUPublicEDKey' "$WORK/StatusTrio.app/Contents/Info.plist"
if bash scripts/verify-app-bundle-plist.sh "$WORK/StatusTrio.app"; then
  echo "Expected the verifier to reject a bundle without SUPublicEDKey." >&2
  exit 1
fi
```

Expected: the real bundle prints `Packaged plist OK: pinned key, HTTPS feed, signed feed required.`; the copied bundle prints `Error: packaged SUPublicEDKey is '', expected 'N5FLwhXCzo7Z/8z3lOWbOJ7aW04hvXxI7LUk+6f+yDQ='.` and the outer `if` does not fire.

- [ ] **Step 4: Call it from the release path**

In `scripts/release.sh`, directly after the build invocation:

```bash
bash "$ROOT/scripts/build-app.sh" release no-open

bash "$ROOT/scripts/verify-app-bundle-plist.sh" "$ROOT/dist/StatusTrio.app" "$SU_FEED_URL"
```

This sits before the publish-only `exit 0`, so every non-publishing preflight exercises it.

- [ ] **Step 5: Commit**

```bash
git add scripts/verify-app-bundle-plist.sh scripts/release.sh
git commit -m "build: assert the packaged app keeps its update trust anchors"
```

---

### Task 5: Document the migration and prove old clients still parse the feed

**Files:**
- Modify: `release-notes/1.3.0/en.md`
- Modify: `release-notes/1.3.0/zh-Hans.md`

**Interfaces:**
- Consumes: the signed `appcast.xml` from Task 1 and the parseability test from Task 2.
- Produces: release-notes copy in the two always-required languages, and a recorded migration procedure.

**Migration risk, stated plainly:** every client already in the field was built without `SURequireSignedFeed`, so it does not verify the feed — that is exactly why this change is needed. Those clients parse the whole document, including the trailing signing block, and they must keep working. The first feed published after this change therefore adds one XML comment and changes no element, attribute, namespace or CDATA byte. Three checks hold that line: `xmllint --noout` in the release path, `SignedUpdateFeedTests.testSignedFeedStillParsesAsPlainXMLForOldClients`, and the manual install of the shipped 1.2.0 build in the Verification section.

- [ ] **Step 1: Add the English notes entry**

Append to `release-notes/1.3.0/en.md`:

```markdown
## Update feed is now signed
- Status Trio now verifies the signature of the update feed itself, not only the signature of the downloaded disk image. Both are protected by the same key that has always been pinned in the app.
- If the feed is ever modified, truncated, or served by something other than the official project, the update is refused instead of being offered. That closes the last way an attacker could have pointed you at an older release or rewritten these release notes.
- Updates are also validated before they are unpacked, so a tampered download is rejected earlier.
```

- [ ] **Step 2: Add the Simplified Chinese notes entry**

Append to `release-notes/1.3.0/zh-Hans.md`:

```markdown
## 更新源已签名
- Status Trio 现在会校验更新源（appcast）本身的签名，而不只是校验下载的磁盘映像。两者都由应用内一直固定的同一个密钥保护。
- 如果更新源被篡改、截断，或被官方项目以外的服务提供，更新会被直接拒绝，而不再提示安装。这堵住了攻击者把更新指向旧版本、或改写这些更新说明的最后一条路径。
- 更新在解压之前也会先校验，因此被篡改的下载会更早被拒绝。
```

- [ ] **Step 3: Validate the notes and the item they generate**

```bash
VERSION=1.3.0 BUILD=12 bash scripts/validate-appcast-notes.sh
```

Expected: `Release notes coverage for 1.3.0: 12/12 languages`, then `Appcast notes OK: 12 titles and 12 descriptions, en first.`

- [ ] **Step 4: Commit**

```bash
git add release-notes/1.3.0/en.md release-notes/1.3.0/zh-Hans.md
git commit -m "docs: describe signed update feeds in the 1.3.0 notes"
```

---

### Task 6: Full verification

**Files:**
- No production files.

- [ ] **Step 1: Run the full test suite**

```bash
swift test
```

Expected: all tests pass, including the 7 `SignedUpdateFeedTests`.

- [ ] **Step 2: Run the release build**

```bash
swift build -c release
```

Expected: successful build against the local SDK.

- [ ] **Step 3: Re-verify the appcast assertions end to end**

```bash
SIGN_UPDATE="$PWD/.build/artifacts/sparkle/Sparkle/bin/sign_update"
ruby scripts/verify-signed-appcast.rb appcast.xml
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | env -u SPARKLE_PRIVATE_KEY "$SIGN_UPDATE" --ed-key-file - --verify appcast.xml
else
  "$SIGN_UPDATE" --verify appcast.xml
fi
VERSION=1.3.0 BUILD=12 bash scripts/validate-appcast-notes.sh
```

Expected: `Signed appcast OK`, `sign_update --verify` silent with exit 0, and `Appcast notes OK: 12 titles and 12 descriptions, en first.`

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

Expected: the workflow passes; the log of `Validate appcast notes` ends in `Appcast notes OK`, the log of `Run tests` includes `SignedUpdateFeedTests`, and the log of `Build, sign, notarize, and publish` contains `Packaged plist OK: pinned key, HTTPS feed, signed feed required.` No GitHub Release is created and the appcast is not modified.

- [ ] **Step 5: Prove the first signed feed still works for an old client**

This is the one part that cannot run in CI, because it needs a client built before this change.

1. Install the shipped 1.2.0 (build 9) DMG from `https://github.com/lingyired/status-trio/releases/download/v1.2.0/StatusTrio-1.2.0.dmg`, run `xattr -dr com.apple.quarantine "/Applications/Status Trio.app"`, and open it.
2. Because that build has no `SURequireSignedFeed`, it consumes the signed feed unauthenticated. Choose “Check for Updates…” and confirm it reads the feed successfully and reports either the newest published version or “You're up to date” — never an appcast parse error.
3. Record the result in the pull request or commit message.

If step 2 reports a parse error, the block placement is wrong: stop and re-check Task 1 Step 6 (`git diff --stat` must show exactly four inserted lines — the signing block — and no other change) before publishing anything.

- [ ] **Step 6: Record any failed CI run**

If any step above fails on CI, append a row to `docs/swift-ci-compatibility.md` with the run ID, the failed stage, the reproducible root cause, the fix, and the verification run, following the rule at `docs/swift-ci-compatibility.md:44-54`.

- [ ] **Step 7: Review the diff**

```bash
git status --short
git diff --check
```

Expected: only `Support/Info.plist`, `appcast.xml`, `scripts/release.sh`, `scripts/sign-appcast.sh`, `scripts/verify-signed-appcast.rb`, `scripts/verify-app-bundle-plist.sh`, `Tests/StatusTrioCoreTests/SignedUpdateFeedTests.swift`, `release-notes/1.3.0/en.md`, `release-notes/1.3.0/zh-Hans.md` changed, with no whitespace errors.

## Verification

1. `swift test` and `swift build -c release` pass on the CI toolchain (`macos-26`, Xcode 26.6, Swift 6.3.3).
2. `ruby scripts/verify-signed-appcast.rb appcast.xml` exits 0, and `sign_update --verify appcast.xml` exits 0 with the pinned key.
3. `SignedUpdateFeedTests.testCommittedAppcastSignatureVerifiesAgainstPinnedPublicKey` proves the committed feed is signed by `SUPublicEDKey` without needing any secret.
4. `VERSION=1.3.0 BUILD=12 bash scripts/validate-appcast-notes.sh` prints `Appcast notes OK`.
5. `bash scripts/verify-app-bundle-plist.sh dist/StatusTrio.app "$SU_FEED_URL"` prints `Packaged plist OK`.
6. The non-publishing preflight passes, and Task 5 Step 5 records that the shipped 1.2.0 client still parses the signed feed.
7. No GitHub Release is created and `appcast.xml` is unchanged by the preflight.

## Out of Scope

- **Rotating `SUPublicEDKey`.** Turning on `SUVerifyUpdateBeforeExtraction` makes key rotation require a Developer ID code-signed DMG archive (`Autoupdate/AppInstaller.m:289-296` accepts the code-signing fallback only for regular app updates from a matching Developer ID team). This repository has no Developer ID, so the EdDSA key is now permanent. That is consistent with the global constraint, and rotating it would need the Developer ID migration first — a conditional, documented follow-up in `2026-09-13-ad-hoc-release-pipeline.md` Task 6, not part of this plan.
- **`SUSignedFeedFailureExpirationInterval`.** Left at Sparkle's 20-day default (the safe fallback that lets users still update through a key rotation). Changing it is a separate trust decision.
- **Signing the release-notes files.** Notes are embedded inline in each item's `<description>`; no `sparkle:releaseNotesLink` is used, so there is nothing to sign separately. `SignedUpdateFeedTests.testItemDescriptionsStayInlineAndLocalized` pins that.
- **Editing `.github/workflows/release.yml`.** Owned by plan R-10 (`2026-09-20-release-pipeline-hardening.md`). The added checks reach CI through `swift test` and through `scripts/release.sh`, both of which the workflow already runs. Follow-up once R-10 lands: add `ruby scripts/verify-signed-appcast.rb appcast.xml` as an explicit step next to `Validate appcast notes`, and add `dist/appcast.xml` to the uploaded artifact paths.
- **Editing `scripts/build-app.sh` or `scripts/verify-platform-version.sh`.** Owned by plan R-11 (`2026-09-20-build-signing-hardening.md`). The packaging assertion lives in `scripts/release.sh`, which calls `build-app.sh` and then checks the produced bundle.
- **`generate_appcast`.** Not used by this pipeline; nothing to change there.
- **Removing the third-party update mirrors.** Owned by plan R-09 (`2026-09-20-update-source-fallback-policy.md`). Until R-09 lands, a mirror can still serve a *stale but genuinely signed* feed, which is a denial of service rather than a rollback, because the signature and the declared version both come from the real publisher.

## File Ownership & Conflicts

**Owned by this plan**

| File | Change |
| --- | --- |
| `Support/Info.plist` | add `SURequireSignedFeed`, `SUVerifyUpdateBeforeExtraction` (Task 2) |
| `appcast.xml` | append exactly one `sparkle-signatures` block (Task 1) |
| `scripts/verify-signed-appcast.rb` | new structural verifier (Task 1) |
| `Tests/StatusTrioCoreTests/SignedUpdateFeedTests.swift` | new (Task 2) |
| `scripts/sign-appcast.sh` | new signing + verification wrapper (Task 3) |
| `scripts/verify-app-bundle-plist.sh` | new packaging assertion (Task 4) |
| `scripts/release.sh` | two inserted lines: bundle assertion (Task 4), appcast signing (Task 3) |
| `release-notes/1.3.0/en.md`, `release-notes/1.3.0/zh-Hans.md` | new section (Task 5) |

**Conflicts with other plans in this set** (matrix: `2026-09-20-review-findings-index.md` §3.1)

- **R-17 (`2026-09-20-preflight-validator-and-appcast-sync.md`) — same files, hard sequence.** R-08 and R-17 both change `scripts/release.sh`, and R-17 also owns `appcast.xml` through its write-back and sync rules. **R-08 lands first**, exactly as §3.1 records ("R-08 lands first (it changes how the appcast is generated/signed). R-17 then adjusts the validator contract and the working-copy sync"). R-17 must rebase on the two inserted lines from Tasks 3 and 4: its write-back and byte-comparison steps go *after* Task 3's signature block, because the bytes it writes back must be the signed bytes. R-17 must not re-order or remove the signing call.
- **R-10 (`2026-09-20-release-pipeline-hardening.md`) — `.github/workflows/release.yml`.** Not touched here. The two follow-up steps listed in Out of Scope belong to R-10's file; whoever lands R-10 second should add them.
- **R-11 (`2026-09-20-build-signing-hardening.md`) — `scripts/build-app.sh`.** Not touched here. If R-11 restructures the `Info.plist` handling, `scripts/verify-app-bundle-plist.sh` and its Task 4 Step 3 negative case are the guard that keeps `SUPublicEDKey` in the bundle.
- **R-09 (`2026-09-20-update-source-fallback-policy.md`) — the feed URL this plan authenticates.** R-09 changes *where* the feed is fetched from and must not remove `SUFeedURL` or `SUPublicEDKey`, must not add `SUAllowsInsecureUpdates`, and must keep `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction` intact while rebuilding `UpdateSourceFallback`. R-09 may land before or after this plan, but `SignedUpdateFeedTests.testInfoPlistRequiresSignedFeedAndVerifiesBeforeExtraction` will fail if R-09 drops either key.
