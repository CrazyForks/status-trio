# Status Trio Agent Rules

## Highest Priority: Match the CI Toolchain

The release workflow is the acceptance environment:

- Runner: `macos-15`
- Xcode: `16.4`
- Swift: `6.1.2`

A newer local toolchain is useful, but it is not proof that CI will compile. Swift code must remain buildable with the CI toolchain.

Before committing Swift changes:

```bash
swift test
swift build -c release
```

If a change touches actor isolation, `@MainActor`, `deinit`, SwiftUI bindings, generics, or `Bundle.module` resources, also run a non-publishing release workflow before merging or publishing:

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref <branch> \
  -f version=<next-version> \
  -f build=<next-build> \
  -f publish=false

gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

Do not create a release if that preflight has not passed.

## Swift 6.1 Compatibility Rules

- Do not use `isolated deinit` or enable the `IsolatedDeinit` experimental feature. Use `deinit` with explicit cleanup; use `nonisolated(unsafe)` only for teardown-owned storage and explain why it is safe.
- Do not pass actor-isolated methods directly as function values. Use an explicit closure instead.
- Do not write `weak let`; weak reference bindings must be `var`.
- Do not assume SwiftPM `Bundle.module` resource names or directory casing match local builds. For localized resources, try the canonical and lowercase `lproj` names and load with `Bundle(path:)`.
- Do not add syntax or language features that require Swift 6.2 or newer unless the CI runner and minimum toolchain are upgraded together.
- If the Swift compiler crashes with `IRGenRequest`, `SmallVector unable to grow`, or a signal 6, reduce the code pattern that causes the crash. Do not treat it as a flaky failure and do not hide it with experimental compiler flags.

## Change Flow

- Small, low-risk changes — especially your own follow-up tweaks — go straight to `main`: commit directly, or use a short-lived branch and fast-forward it into `main`. No pull request is required.
- Use a pull request when a change is large, touches several subsystems, or when a review/discussion record is worth keeping.
- Whichever route is taken, the verification rules above still apply: `swift test` and `swift build -c release`, plus a non-publishing release workflow run when the change touches actor isolation, `@MainActor`, `deinit`, SwiftUI bindings, generics, or `Bundle.module` resources.
- The release workflow only runs on tags and manual dispatches, so a pull request does not add CI coverage on its own.

## Menu Bar and Dock Icon Parity

- Every change to a menu bar icon's rendering or icon-related settings must be mirrored in the Dock icon in the same change. Do not leave the Dock on a default or stale representation.
- When adding or changing an icon option, update both paths end-to-end as applicable: `SettingsStore` option derivation, `StatusBarController` subscriptions, `AppIconController` subscriptions/state, `DockIconRenderKey` cache inputs, `DockIconRenderer` rendering, and tests covering both menu bar and Dock output.
- If a setting is intentionally menu-bar-only, the issue or specification must say so explicitly, and the limitation must be documented and covered by a test.

## Release Rules

- GitHub Release notes must use a top-level `# Version X.Y.Z （English + 中文， 中文在下方）` heading, followed by English notes and then Chinese notes. Provide the English text through `release_notes` and the Chinese text through `release_notes_zh`; the release workflow combines them.
- Sparkle appcast items are localized, not bilingual: emit `<title xml:lang="en">` plus `<title xml:lang="zh-Hans">` and `<description xml:lang="en">` plus `<description xml:lang="zh-Hans">` for every new item, and give every variant an explicit `xml:lang`. Sparkle renders the variant matching the user's preferred languages and falls back to English. Never stack both languages inside one `<description>`.
- GitHub Release bodies must append the first-launch commands `xattr -dr com.apple.quarantine "/Applications/Status Trio.app"` and `open "/Applications/Status Trio.app"` after the bilingual notes. Do not include these commands in the Sparkle appcast.
- Release announcements remain in English.
- Release through `.github/workflows/release.yml`; do not publish manually unless the workflow is unavailable and the user explicitly asks for a manual fallback.
- Version and build numbers must be explicit and must increase the published build number.
- Confirm tests, DMG creation, Release upload, and appcast publication in the workflow result.
- The current repository has no Developer ID certificate or notarization secrets. Releases are Ad-hoc signed; document this limitation rather than claiming notarization.

See [Swift 6.1 CI compatibility](docs/swift-6.1-ci-compatibility.md) for the incident history and examples.
