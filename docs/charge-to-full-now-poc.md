# Charge to Full Now: phase A/B research

## Decision

**BLOCKED at phase B. No product integration or charging write implementation.**

The feature request requires proof of safety, availability, and actual effect
before settings or UI integration. The supplied plan permits compiling an
unverified implementation in some circumstances, but the user's explicit
instruction is stricter. We stop before phases C-F until that gate passes.
This is not evidence that a permission-free implementation is impossible.

Research started October 27, 2026; regression verification continued October 28,
2026, Asia/Shanghai.

- Initial baseline: `origin/main`, `a9ee5cab352b6464d3a6b5a2a4cb51a5bd6c99b9`.
- Final integrated baseline: `origin/main`,
  `27ef4ca27217f09cdd3ee9efa4f5e1ad59209f89`.
- Branch: `codex/charge-to-full-now`, research commit
  `29577226dad404e2a8a4eddfa402807d2e9a5647`.
- Isolated worktree: `/Users/lingsmbp/.codex/worktrees/charge-to-full-now/status-trio`.
- Host: Apple Silicon, macOS 27.0.1 (26A434), Xcode 27.0 (27A266a).
- Zero charging requests, new permissions, authorization requests, Helper
  changes, SMC writes, or persistent charging-setting writes.

## Reproduce the read-only experiment

From this worktree:

```bash
bash scripts/probe-charge-to-full-now.sh --self-test
bash scripts/probe-charge-to-full-now.sh --inspect
```

The first command uses local fake Objective-C classes; it does not load PowerUI
or contact a charging service. The second explicitly loads the system's
PowerUI framework in a short-lived command-line process and reads state.
No arguments, unknown arguments, Intel/Rosetta processes, or macOS before 26.4
stop before loading PowerUI. The inspection child has a 20-second timeout.
Private Objective-C classes are kept loaded until process exit.

The tool is outside `Sources`, is not a Swift package target, and is not
called by the app, settings, popover, or tests in `scripts/test.sh`.
The app does not acquire an additional query or background task.
There is deliberately no write flag, declared write method, privileged
service, or charge-limit setter in the tool.

The probe checks class, selector, return type, argument count, and out-pointer
encodings before initializing the client or sending state queries.
`temporarilyDisableMCL:` is inspected as metadata only.

## Observed ABI and state

These encodings were read from the running macOS 27.0.1 arm64 process:

| Selector | Encoding | Interpretation |
| --- | --- | --- |
| `initWithClientName:` | `@24@0:8@16` | Object argument and object result |
| `isMCLSupported` | `B16@0:8` | `BOOL` |
| `isMCLCurrentlyEnabled:` | `Q24@0:8^@16` | `NSUInteger`, **not BOOL**; `NSError **` |
| `getMCLLimitWithError:` | `C24@0:8^@16` | `unsigned char`, **not NSUInteger**; `NSError **` |
| `smartChargingUIState:chargeLimit:chargingOverrideAllowed:withError:` | `B48@0:8^Q16^Q24^B32^@40` | `BOOL`; two `NSUInteger *`, `BOOL *`, `NSError **` |
| `temporarilyDisableMCL:` | `B24@0:8^@16` | `BOOL`; `NSError **`; never invoked |

The Objective-C implementation is independent and uses checked typed messages,
not unchecked function-pointer casts or statically linked private frameworks.
It does not copy JuiceLeft source, comments, or tests.

Observed on the development machine:

| Reading | Value |
| --- | --- |
| Internal battery present / external power | `true` / `true` |
| Battery percentage / currently charging / fully charged | `80` / `false` / `false` |
| MCL supported | `true` |
| MCL enabled raw result | `1`, no error |
| MCL limit / UI limit | `80` / `80`, no error |
| UI state raw result / query success | `14` / `true`, no error |
| `chargingOverrideAllowed` | **`false`** |
| Charging write requested | **`false`** |

Both private enum results remain raw. Their meanings have not been verified
against native UI and must not become production enum cases or boolean
assumptions. The applicability of the override-allowed signal to MCL, as
distinct from Optimized Battery Charging, still needs verification.

The false signal prevents our conservative experiment gate from permitting a
write. It does not prove entitlement denial, permanently unsupported hardware,
or that native Charge to Full Now is unavailable. There was no write attempt
from which to infer a permission failure.

The native Control Center inspection tool timed out. Native button
visibility/enabled state was therefore **NOT RUN**. No Accessibility,
Automation, or other authorization was requested to bypass this limitation.
Read-only queries returned without an observed permission interaction;
this says nothing about write authorization or write-time prompts.

Raw output and temporary exploratory tools are in the ignored
`.build/charge-to-full-now-poc/` directory. Re-running inspection replaces the
machine observation and may produce different state.

## Architecture audit and plan corrections

The audited baseline supports the proposed layout, with these corrections:

1. The repository ships **12** languages, not the plan's 13.
2. `BatteryStatusView` consumes `PanelSummaryState`; it must remain a
   presentation view. Future state belongs in the existing store/panel
   architecture, with actions through `StatusPanelActions`.
3. Popover content can survive closure. Future PowerUI demand must follow
   explicit panel lifecycle, setting enablement, and battery-section visibility
   in `StatusPanelViewModel`/`SystemStatusStore`, with release on closure.
   View disappearance alone is insufficient.
4. `BatteryMonitor` stays read-only. Neither its existing cadence nor
   `SystemChargeLimitReader`'s cached plist proves override eligibility.
   `batteryFullThreshold` remains an icon-display threshold.
5. Existing trailing leaf/chevron/gear geometry, home-row navigation, and the
   330-point width must remain intact. A future action is a sibling below the
   home battery row, with layout/VoiceOver tests across all 12 languages.

No setting, localization key, UI row, app controller, renderer, charging
animation, or low-power-mode code was changed. The current README and known
limitations correctly continue to say the app has no charge-to-full action.

## Verification matrix

| Scope | Result |
| --- | --- |
| Native arm64 fake ABI/platform checks | PASS: 17 checks, 0 failures; no PowerUI load |
| Universal PoC and fake-test compilation | PASS: `arm64` and `x86_64`, macOS 13 deployment target |
| Fake ABI/platform tests under Rosetta | PASS: 17 checks, 0 failures |
| Rosetta inspection fallback | PASS: exit 2, unsupported, no PowerUI load, no write |
| Missing/unknown/extra command arguments | PASS: exit 2 before compiling or loading the probe |
| Live arm64 class/selector/ABI and state reads | PASS for this OS build only |
| Existing focused battery/panel tests | PASS: 5 XCTest tests and 8 Swift Testing tests |
| Complete repository local profile | PASS: `bash scripts/verify-local.sh full`, exit 0; see provenance below |
| Updated-main DDC regression | PASS: 14 tests, 0 failures after rebasing onto `27ef4ca2` |
| Independent four-file safety review | PASS: no remaining Critical or Important findings |
| Native system menu comparison | NOT RUN: UI inspection timed out |
| 80% override authorization and actual continued charging | BLOCKED: no confirmed safe eligibility |
| Persistent limit unchanged after override / natural restoration | NOT RUN: no write was sent |
| 90%, limit 100%, unplugged, already charging/full, thermal/power restriction | NOT RUN |
| Legacy OBC override | NOT RUN; outside supported scope |
| Physical Intel, macOS 13-26.3, macOS 26.4, sleep/wake | NOT RUN; fake/version and Rosetta checks are not hardware coverage |
| Feature settings/panel/UI/VoiceOver/localization acceptance | NOT RUN: product integration stopped at phase B |

### Local verification environment

The first `bash scripts/verify-local.sh full` run passed 15 Helper XCTest
tests, 1,928 app XCTest tests (8 existing skips), 763 Swift Testing tests in
112 suites, and the Release build. It failed at `App bundle build`, exit 128,
because GitHub returned HTTP 403 while cloning the existing `libplist`
dependency. This was a source-download failure, not a feature or test failure.

All six dependency commit pins were verified in the main checkout's existing
local source cache. The absent repositories were cloned locally into this
worktree's ignored build directory, without hardlinks or changes to the
source cache, and their origins restored to the manifest URLs. No dependency
pins, build scripts, tests, or assertions were changed. The complete profile
was then run again with these pinned source inputs available and passed
(exit 0) on October 28, 2026.

After the research commit was created, `origin/main` advanced to
`27ef4ca27217f09cdd3ee9efa4f5e1ad59209f89` with an unrelated DDC test and
compatibility-document change. The branch was rebased onto that commit, the
14 affected DDC tests passed, and `bash scripts/verify-local.sh full` passed
again with exit 0 at research commit
`29577226dad404e2a8a4eddfa402807d2e9a5647`.

The successful final run reported 15 Helper XCTest tests, 1,928 app XCTest
tests (8 existing skips), and 763 Swift Testing tests in 112 suites, with zero
failures. Release compilation, the local non-Universal Ad-hoc app bundle,
platform/SDK and Helper contracts, native compatibility checks, and offline
release simulations all passed. Existing Swift concurrency warnings in the
unchanged Low Power Mode sources remain baseline warnings.

These results validate the existing app with the separate research files
present. They do not validate the proposed product feature, actual charging,
physical Intel hardware, Ventura runtime, Universal app packaging, Developer
ID signing, notarization, or publication.

The initial failure log is retained at
`.build/charge-to-full-now-poc/full-verification-initial-failure.log`;
the subsequent run is at
`.build/charge-to-full-now-poc/full-verification-console.log` (first complete,
pre-rebase run) and `.build/charge-to-full-now-poc/full-verification-final.log`
(final post-rebase run).
The repository's canonical current report is
`.build/local-verification/log.txt`. Its `status.txt` records a failing step
when applicable; it is empty on this successful run. The saved initial status
is `.build/charge-to-full-now-poc/full-verification-initial-status.txt`.

## Resume criteria

First manually compare the native battery menu with a fresh read-only
observation. Do not change the user's persistent charge limit to manufacture a
test condition, impersonate an Apple client, request additional permissions,
or bypass a false/unknown eligibility signal.

Before implementing a write experiment, independently establish the native
MCL eligibility and private-state meanings on the tested OS. A separately
reviewed experiment must send only `temporarilyDisableMCL:` following an
explicit manual click, observe actual charging, confirm the persistent limit
is unchanged, and leave recovery to macOS. Any permission request fails the
gate. Returning `true` alone cannot pass it.

Only after this evidence passes may phases C-F add the injectable controller,
default-off persistent setting, home summary action, fake-driven unit/UI
tests, translations, and user-facing documentation. This branch contains no
fallback that substitutes low-power-mode control, SMC writes, shell writes,
or permanent limit changes.

## Sources and provenance

- Apple's [About Optimized Battery Charging and Charge Limit on Mac](https://support.apple.com/en-us/102338),
  published April 6, 2026, describes Charge Limit on Apple Silicon and macOS
  26.4+, and the native Charge to Full Now menu action. Retrieved October 27,
  2026. It does not document this private programming interface.
- Apple's installed framework runtime metadata and live read-only results
  above are the ABI/state evidence. They are version-specific.
- The user's supplied `StatusTrio_ChargeToFullNow_Codex_Plan.md` provided
  candidate Apple API names. JuiceLeft's license was inspected to confirm
  its restricted terms; its implementation was not read or reused.
