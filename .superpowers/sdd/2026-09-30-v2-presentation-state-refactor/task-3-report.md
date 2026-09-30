# Task 3 Report: Pure Icon Presentation Mapper

## Result

Implemented configuration, a pure mapper for the battery ring, center slot, and volume footer, and an AppKit-backed resource resolver. No production consumer migration was included.

The mapper is in `Sources/StatusTrioCore/Presentation/Icon/IconPresentationMapper.swift` and imports only Foundation. `IconPresentationConfiguration` and `IconPresentationInputs` are value types that conform to `Equatable` and `Sendable`. `IconPresentationMapper.scene(inputs:configuration:)` always creates one battery ring segment and delegates battery and Bluetooth replacement priority to the existing `StatusMappings` helpers.

`Sources/StatusTrioCore/App/IconPresentationResourceResolver.swift` resolves the current output's icon before mapping. The resolver preserves driver images with a renderer fallback symbol and resolves absent images through the existing device classification and symbol candidate mapping. Tests inject file existence and symbol availability closures per call; no process-wide environment is changed.

## Behavior coverage

`IconPresentationMapperTests` contains 19 state-level tests covering:

- battery threshold and color priority, battery presence, charging/charged/plug/percentage/closed gaps, and charging-effect eligibility;
- present-battery center priority, Bluetooth replacement with and without a selected symbol override, network-error priority, and Ethernet's fixed full Wi-Fi level;
- connected signal values and inactive zero signal, off/unavailable equality, and hotspot/temporary/shared symbol options;
- nil, non-finite, boundary, muted, and clamped volume values, plus Bluetooth volume tint only when the active output is Bluetooth;
- normalized scene equality when signal and dot inputs differ within the same visible bucket; effect flags are off for percentage/nil accessories, and empty volume fills canonicalize to the primary color.

`IconPresentationResourceResolverTests` covers a missing device image falling back to a classified symbol, an existing image retaining a renderer fallback, and the no-current-device case.

## TDD and verification

A final self-review added two equality regressions: non-bolt charging accessories must not inherit bolt heartbeat/tint flags, and an empty Bluetooth volume fill must not retain Bluetooth tint. Both tests failed against the prior mapper state, then passed after canonicalizing those invisible properties.

RED: `swift test --filter 'IconPresentation(Mapper|ResourceResolver)Tests'` failed at test compilation because the requested presentation input/configuration/mapper/resolver interfaces did not exist. The new accessory/equality assertions later failed as expected against the first mapper implementation.

GREEN: The same focused command passed 22 tests: 19 mapper tests and 3 resolver tests.

Full suite:

```text
$ swift test
✔ Test run with 410 tests in 69 suites passed after 2.214 seconds.
EXIT_CODE=0
```

Release build:

```text
$ swift build -c release
Build complete! (0.30秒; cached incremental build)
EXIT_CODE=0
```

`git diff --check` exited 0. An import scan found no AppKit, SwiftUI, or CoreGraphics imports in the pure mapper/configuration files.

The local machine uses macOS 27 / Xcode 27 / Swift 6.4. This does not establish compatibility with the required macOS 26 / Xcode 26.6 / Swift 6.3.3 CI toolchain.

## Remaining CI gate and concern

The required `publish=false` release preflight has not been dispatched. `git ls-remote --heads origin codex/2.0-presentation-refactor` returned no ref, so GitHub cannot run the workflow against this local commit without first publishing the branch. The latest published release is v1.3.3, build 16; Task 13 owns the preflight and should run it on the shared remote branch with the next explicit build number when available. This task did not push the branch or dispatch the workflow. No workflow failure occurred in this task.

No implementation ambiguity remains. `IconPresentationResourceResolver` is `@MainActor` because it owns the AppKit `NSImage` availability check; all injectable closures are call-scoped.
