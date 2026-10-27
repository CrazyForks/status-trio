# Release CI performance report

Status: remote baseline, parallel verification diagnostics, and the same-SHA
warm-source-checkout cold/warm pair completed 2026-10-27 (Asia/Shanghai).

This report uses existing GitHub Actions evidence. It makes no promise of a
12-14 minute release and does not claim a speedup from any unmeasured change.

## Observed baseline

- Latest recent full verify/package chain `40344113013`: 20m05s wall,
  including 485s verify and 616s package.
- Latest recovery-only chain `40349355595`: 10m11s wall, including 520s verify
  and 36s publish. Package was skipped, so this is not a full-release time.
- Cold remote package spent roughly 5-6 minutes rebuilding pinned MobileBattery
  dependencies for both architectures in the measured 1.7.3-1.7.5 runs.
- Hot remote / cache-hit behavior: measured 2026-10-27 in
  [run `40428015193`](https://github.com/lingyired/status-trio/actions/runs/40428015193).
- A full remote release with the new cache and stage instrumentation:
  package-only cold/warm measured; publication not run.

## Measurement methodology

The timings came from GitHub Actions metadata and existing job logs:

```bash
gh run list --repo lingyired/status-trio --workflow release.yml \
  --limit 30 --json databaseId,headSha,status,conclusion,createdAt,updatedAt,url
gh run view <RUN_ID> --json jobs
gh api --allow-escape-sequences \
  repos/lingyired/status-trio/actions/jobs/<JOB_ID>/logs
```

For the latest full/recovery runs:

- **Wall duration** is `updated_at - run_started_at`.
- **Active job duration** is `completed_at - started_at` for each completed
  job, excluding skipped jobs.
- **Gap** is wall minus completed-job active time. It includes approval,
  queueing, runner allocation, artifact handoff, and other idle periods. The
  report does not call the entire gap "approval" unless logs identify a
  boundary. This subtraction applies to the serial runs only.
- **Stage duration** is the corresponding job's start/end timestamps.

For the parallel profile, the verification critical path runs from the first
verification job's start to the last verification job's completion. The
verification-to-package gap is package start minus the later verification
completion; it includes approval and runner scheduling. Active job durations
are also summed as a runner-time observation, but overlapping job time must
not be subtracted from wall time to estimate idle time. These durations are
not GitHub billing measurements.

For MobileBattery, the phase boundaries are log timestamps:

- arm64 start: `Configuring OpenSSL ... darwin64-arm64-cc`
- x86_64 start: `Configuring OpenSSL ... darwin64-x86_64-cc`
- dependency package complete: `Built source-pinned mobile battery helper
  package`
- app build complete: `Built ... StatusTrio.app`
- DMG processing: `Processing: ...StatusTrio-<version>.dmg`

The interval from arm64 configuration to the dual-architecture package marker
is labeled **MobileBattery interval**, not pure MobileBattery CPU time. It
excludes source checkout, which precedes OpenSSL configuration. It includes
both dependency builds, helper compilation,
lipo/package assembly, licensing, and validation performed by that script.
The x86-to-package interval is an approximation of the second architecture's
remaining dependency/helper/assembly work because the log does not emit a
per-architecture completion marker.

These are remote runner observations, not a local benchmark. Integer phase
timings from the new `build-timing.sh` TSV are useful for comparing later runs,
but the earlier 1.7.2-1.7.5 runs predate or do not expose those TSV records
consistently. No local cold/hot timing was substituted for remote evidence.

## Latest run evidence

| Run | SHA | Scope | Wall | Verify | Package | Publish | Gap |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| [40344113013](https://github.com/lingyired/status-trio/actions/runs/40344113013) | `57828a41960e` | full package-only | 1,205s / 20m05s | 485s | 616s | skipped | 98s verify-to-package |
| [40349355595](https://github.com/lingyired/status-trio/actions/runs/40349355595) | `2b0d7a5caf17` run head; `57828a41960e` package candidate | recovery/publish | 611s / 10m11s | 520s | skipped | 36s | 49s verify-to-publish |
| [40112321642](https://github.com/lingyired/status-trio/actions/runs/40112321642) | `6265b6422298` | recovery/publish | 1,160s / 19m20s | 503s | skipped | 29s | 623s / 10m23s |

`40349355595` is not a full release timing. It validated an existing package
artifact and published it, while package was skipped. `40112321642` shows why
wall time alone is misleading: nearly half its wall time was an unattributed
gap between verify and publish.

## MobileBattery per-architecture costs

The following successful package jobs are the clearest cold remote evidence.
All three cloned pinned sources and configured/builded both architectures; no
repository cache step is visible in these logs.

| Version / job | arm64 config to x86 config | x86 config to package marker | MobileBattery interval | Package job |
| --- | ---: | ---: | ---: | ---: |
| 1.7.3 / [`120909079608`](https://github.com/lingyired/status-trio/actions/runs/40106014873/job/120909079608) | 149s (2m29s) | 166s (2m46s) | 315s (5m15s) | 591s |
| 1.7.4 / [`120923504263`](https://github.com/lingyired/status-trio/actions/runs/40110818728/job/120923504263) | 154s (2m34s) | 144s (2m24s) | 298s (4m58s) | 563s |
| 1.7.5 / [`121651066894`](https://github.com/lingyired/status-trio/actions/runs/40344113013/job/121651066894) | 150s (2m30s) | 189s (3m09s) | 339s (5m39s) | 616s |

Observed range:

- Per-architecture phase: about 2m24s-3m09s.
- Cold dual-architecture MobileBattery interval: 4m58s-5m39s.
- Apple Swift universal build in the same package path: about 96-110s
  (`Build complete!` values: 108.42s for 1.7.3, 110.34s for 1.7.4, 96.31s for
  1.7.5).
- Signing, DMG creation/notarization, and upload consume the remainder of the
  package job. They are not part of the MobileBattery interval.

The 1.7.2 job `120239165370` used an older build path and took 532s inside the
same MobileBattery boundaries. It is useful historical evidence but is not
included in the 1.7.3-1.7.5 comparison because the build path differs.

## Why the cold cost recurs

Evidence:

- `scripts/build-mobile-battery-helper.sh` computes a per-architecture build
  key from arch, SDK, minimum macOS, clang version, script version, and the
  dependency manifest hash.
- The guard reuses an existing
  `.build/mobile-battery/<arch>/.dependencies-build-key` plus the expected
  installed dylibs.
- The release workflow has no `actions/cache` entry in the audited baseline.
- The audited package jobs show source cloning and both dependency builds even
  when a previous job built the same manifest and toolchain; no dependency
  cache restore appears in those logs.
- Both architecture prefixes are built; the helper and dylibs are combined
  with `lipo`. A cache of only the final helper would not preserve the dylibs
  required by the Universal bundle.

Hypothesis:

- Persisting the unsigned, path-compatible dependency prefixes could remove
  some or all of the cold dual-architecture interval on an exact cache hit.
- The saving is bounded by the 4m58s-5m39s observed cold interval and offset
  by cache download, extraction, validation, and any cache miss.
- Exact path binding makes safe reuse harder and may produce misses when the
  checkout path or toolchain identity changes. That is intentional until
  validation proves a broader key safe; it reduces speculative reuse.
- SwiftPM caches are separate and should not be credited with MobileBattery
  savings.

## What can and cannot be concluded

Can be stated from evidence:

- Recent full verify/package runs are around 20 minutes wall time.
- Verify is approximately 8 minutes; package is approximately 10 minutes in
  the latest full chain.
- MobileBattery is a material cold package cost: roughly 5-6 minutes for both
  architectures in the measured release packages.
- Recovery-only runs are much shorter because they skip package.
- Approval/queue gaps can add 10 minutes or more to wall time.

Cannot be stated without new remote evidence:

- That caching will save a specific number of minutes or make a full release
  12-14 minutes.
- That cache hits are reliable across checkout paths, SDK updates, or runner
  image changes.
- That static-check reordering, diagnostics, or `build-timing.sh` changes
  reduce runner wall time.
- That local `verify-local.sh` timings predict hosted-runner behavior.

## Local native cold/warm measurement

Scope: `scripts/build-mobile-battery-helper.sh` with `UNIVERSAL_BUILD=1`, on
the implementation tree based on
`e5cd7954ee35677a46d796eedf33d39699f17b52`. This is an unsigned native
helper/library package measurement, not a full Universal app or release.

Environment: Mac15,9, arm64, 16 logical CPUs, 128 GiB memory; macOS 27.0.1
(`26A434`), Xcode 27.0 (`27A266a`), Swift 6.4, macOS SDK 27.0. Other local
test work ran concurrently, so these are single-run observations rather than
an isolated CPU benchmark.

The cold run removed only architecture build/prefix/marker outputs and native
package assembly. Pinned source repositories were already present and verified.
The warm run immediately reused the exact same source tree, toolchain and paths.
Neither run used GitHub Actions cache download, compression or upload.

```bash
BUILD_TIMING_FILE=.build/ci-optimization-evidence/native-universal-final-cold.tsv \
  UNIVERSAL_BUILD=1 bash scripts/build-mobile-battery-helper.sh
BUILD_TIMING_FILE=.build/ci-optimization-evidence/native-universal-final-warm.tsv \
  UNIVERSAL_BUILD=1 bash scripts/build-mobile-battery-helper.sh
```

| Scope | Cold | Warm |
| --- | ---: | ---: |
| Complete native script, monotonic wall time | 141.301s | 6.974s |
| Source pin/checkout phase, integer timing | 0s | 0s |
| arm64 dependency phase, includes cache validation | 70s | 2s |
| x86_64 dependency phase, includes cache validation | 69s | 3s |
| arm64 helper and thin-copy staging | 1s | 1s |
| x86_64 helper and thin-copy staging | 1s | 0s |
| Universal package assembly | 0s | 1s |

The measured local native difference is 134.327s (95.1%). It is not a remote
net saving or an end-to-end release improvement. The separately observed
initial source checkout took 96.582s; it is excluded from both cold/warm
dependency comparisons, and source repositories are not persisted by the new
Actions prefix cache.

## Warm source-checkout removal

The final same-SHA remote run still spent 27s checking out all pinned
MobileBattery source trees before discovering that both dependency prefixes
were exact cache hits. Those trees were not needed to compile the Helpers or
assemble the package; they were only needed for a dependency rebuild or to
regenerate license files that are already reviewed and committed under
`Support/MobileBatteryHelper/ThirdPartyNotices/`.

The build now prepares sources only when at least one architecture actually
misses or rejects its dependency cache. Cache-hit runs use the tracked
license texts. On a cold rebuild, the script still verifies every source pin
and compares each upstream license with the reviewed copy after normalizing
line endings and trailing whitespace;
drift fails closed instead of rewriting tracked files. Cache validation no
longer requires a source checkout because the exact key and marker bind the
dependency manifest, build scripts, canonical prefix and full installed
inventory.

The synthetic cache contract covers three new boundaries: a warm build does
not invoke source preparation, a warm Universal build succeeds after the
source trees are removed, and differing reviewed license text fails a cold
build. This is a local contract result, not yet a remote timing claim.

Both warm cache candidates validated and skipped third-party compilation.
Helpers were rebuilt, and complete prefix inventories were byte-identical
before/after the warm run. Uncompressed prefix disk usage was 21,152 KiB
(arm64) and 21,512 KiB (x86_64); this is not a compressed transfer size.

Native contract evidence uses disposable copies, the existing
`rewrite_mobile_battery_binary` function from `build-app.sh`, and ad-hoc
signatures. It verifies the Universal helper plus seven real dylibs, both
slices, minimum macOS 13.0, SDK 27.0, bundled dependencies and allowed rpaths.
This native-only check does not prove a full Universal app, Developer ID or
notarization. The separate app-level check below covers the complete
Universal development bundle.
Raw native package libraries intentionally retain prefix dependency references
until the existing app-assembly rewrite; checks must observe that boundary.

Evidence is retained under `.build/ci-optimization-evidence/`:
`native-universal-final-{cold,warm}.{json,log,tsv}`,
`prefix-*-{before,after}-warm.json`, and `native-universal-contracts.{json,log}`.
These ignored local files are not committed release artifacts.

The first real Universal attempt failed because development rpaths were
removed after `lipo`, where each slice had a different prefix path. A
synthetic Universal test reproduced that failure before the fix. Packaging
now strips disposable thin copies before `lipo`, leaving sealed prefixes
unchanged. The successful times above are from the corrected implementation;
the failed 151.189s attempt is not counted as a successful cold benchmark.

## Full Universal development app

The complete app was built separately with the existing worktree pipeline:

```bash
UNIVERSAL_BUILD=1 \
  BUILD_TIMING_FILE="$PWD/.build/ci-optimization-evidence/universal-app-final.tsv" \
  bash scripts/build-worktree.sh release no-open
```

The build passed in 56.364s using the same implementation and toolchain as
the native measurements. It reused local Swift compilation outputs and
validated native prefixes; this is not a clean-runner app benchmark.
The app has the independent bundle identifier
`com.lingsmbp.StatusTrio.dev.ci-stability-native-cache` and an Ad-hoc signature.

The main executable and both Helpers have exactly `arm64` and `x86_64`
slices. The app-level MobileBattery and privileged Helper contracts,
minimum macOS 13.0 / SDK 26-or-newer contracts, Sparkle Ventura metadata,
and deep strict codesign verification passed. MobileBattery's existing
`--list` bundle smoke test also passed. No app window or privileged
registration was exercised.

Evidence: `universal-app-final.{json,log,tsv}`,
`universal-app-contracts-final.{json,log}`, and
`universal-app-files-final.json` under `.build/ci-optimization-evidence/`.
A copy is retained in `universal-development/StatusTrio.app` under that
directory, separate from later verification outputs. This is a built
development app, not a DMG, Developer ID/notarized package, or release.

## SwiftPM download-cache experiment and P2 decision

A separate local experiment used two new scratch directories and private
SwiftPM cache/config/security directories. It did not reuse the project's
existing `.build` output or the global SwiftPM cache. Both resolutions used
the unchanged `Package.resolved`, with Sparkle 2.9.6 pinned to
`ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a`.

Both commands used `swift package resolve` with
`--manifest-cache local --disable-keychain --disable-netrc
--force-resolved-versions --skip-update` and explicit private paths.
The first resolution populated an empty cache. Only its `repositories` and
`artifacts` directories were compressed and restored into another empty
cache; the second resolution created a fresh working copy.

| Scope | Measured result |
| --- | ---: |
| Empty-cache resolution and dependency downloads | 14.435s |
| Download-cache resolution in a new scratch directory | 1.783s |
| Compressed repositories/artifacts archive | 62,248,695 bytes |
| Local archive compression | 1.075s |
| Local extraction | 0.079s |
| Compilation outputs included | None |

The resolve-only difference is 12.652s. After local extraction, 12.573s
remains before counting Actions download; including compression leaves
11.498s before combined transfer costs. These are single observations of
local file operations and network conditions, not a measured Actions net
saving. SwiftPM reported both the repository and binary artifact as fetched
from cache in the second run. The lockfile SHA-256 remained
`082a01a05e1ab193c61878e6587ed42846ea06a01a3c1b68f612182dd82a6bb4`.

**Decision: do not add a SwiftPM Actions cache in this change.** The measured
download budget is small compared with the native build interval, and
hosted transfer time and hit rate have not been measured. Debug or
Universal Release compilation caches were not included or enabled; their
cross-job correctness and net benefit remain unmeasured. A compilation-cache
experiment is conditional follow-up, not a missing enabled feature.

Repeated-work audit: workflow-policy regression now runs once in static
preflight. Debug tests and the Universal Release build have different
outputs and remain required. Candidate release-pipeline fixtures and trusted
recovery-tool fixtures validate different revisions during recovery and
remain separate. Helper compilation after native-prefix reuse and final
bundle validation remain required. No further work was removed or
parallelized without evidence of equivalent contracts and independent
outputs. Recovery's frozen artifact and trusted-tooling model is retained.

Raw evidence and the reproducible experiment driver are retained in
`.build/ci-optimization-evidence/measure-swiftpm-downloads.py` and
`swiftpm-download-benchmark/{results.json,metadata.json,cold.log,download-cache.log}`.

## Remote cold/warm package measurement

After PR #156 was merged, GitHub rejected the first dispatch because a
job-level environment variable used `runner.temp`. That expression is not
available at job scope. A policy regression and the official `actionlint`
v1.7.12 both reproduced the error. PR #157 moved the timing file under the
workspace and added a fail-closed context check. The rejected dispatch and two
zero-job push validation records were not counted as cold builds.

Both successful diagnostics were dispatched from `main` with the same frozen
SHA `c4fd84196ced2a0c340eabda32fef2b40bec32f0`, version `1.7.6`, build `44`,
`publish=false`, `notarize=false`, and no recovery package. Their source tree
was identical to locally verified commit `aa9ec53d`. Both passed Verify on
`xcode-27` / Xcode 27.0 / Swift 6.4 / SDK 27.0, and both published nothing.
Cheap static preflight, complete Swift tests and native/release regressions
remained in Verify in both runs.

| Stage / job | [Cold `40426198186`](https://github.com/lingyired/status-trio/actions/runs/40426198186) | [Warm `40428015193`](https://github.com/lingyired/status-trio/actions/runs/40428015193) | Change |
| --- | ---: | ---: | ---: |
| Verify job | 372s | 612s | +240s |
| Package job | 484s | 254s | **-230s** |
| Total wall | 901s | 906s | +5s |
| Swift Universal Release build | 122s | 148s | +26s |
| MobileBattery source checkout | 27s | 26s | -1s |
| arm64 dependencies | 142s | 12s | -130s |
| x86_64 dependencies | 135s | 2s | -133s |
| MobileBattery total | 307s | 45s | **-262s** |
| App build/sign/verify | 440s | 203s | -237s |
| Native cache restore interval | 0s | 4s | +4s |
| Native cache save interval | 2s | 0s, skipped | -2s |

The warm cache had two exact hits. Each architecture logged cache restored,
complete prefix validation, and native dependency build skipped. Both Helpers
were rebuilt, final Universal/MobileBattery/signature contracts passed, and
the cache save steps were skipped. The two cache entries remained the same
IDs and keys, together occupying 14,459,151 bytes; their access timestamps
advanced on the warm Runner. The cache transfer interval excludes Actions
download details hidden inside `actions/cache`; it is not a pure network
measurement.

The Package saving is 230s (47.52%) and the MobileBattery interval saving is
262s (85.34%) on this pair. Total wall increased by 5s (+0.55%, no overall
speedup) because Verify was 240s slower. The warm Verify compile took 188.18s
versus 68.43s cold, and its XCTest body took 172.059s versus 147.741s. Runner
load or another external cause was not measured, so the variation is not
attributed to the cache. The result supports a material package-stage
improvement when the exact cache hits, without claiming a guaranteed or
end-to-end 12-14 minute release.

Both DMGs passed local download-only verification after the runs: GitHub
artifact digests matched, manifests identified the frozen SHA, and DMG
sha256 matched the manifest and adjacent checksum. The cold DMG digest was
`97599b8295e1779eeabce155f9d762ea1c62b7e776d31afd7eec9c6c528aa258`;
the warm digest was
`a4af4aad9e9d03afa789966f6dd6ca03e74d5331e486976527198d538581e693`.
The two DMGs came from independent builds, so their byte-level difference is
not a failed digest check. Each archive matched its own manifest and adjacent
checksum; the reason for the byte difference was not diagnosed.

Read-only mounts verified each DMG's version/build, ten app, Helper, and
native binaries as `arm64 + x86_64` with minimum macOS 13.0 / SDK 27 metadata,
and deep strict Ad-hoc signatures. Sparkle's Ventura-compatible minimum was
checked separately as metadata, not as part of the ten-binary contract. No
app launch, XPC/helper registration, Developer ID signing, notarization or
macOS 13 runtime was exercised. After the runs, public releases and tags still
had 18 entries each, `main/appcast.xml` retained the same Git blob, and the
`distribution` Environment protection rules were unchanged.

Raw remote evidence: `.build/ci-optimization-evidence/remote-2026-10-27/`.
It includes run/job JSON, logs, timing TSVs, artifact digests, manifests,
mounted-DMG checks and before/after public-state audits. These local evidence
files are not committed release artifacts.

## Parallel verify/native profile

The latest `main` rerun before the profile change was
[`40435617420`](https://github.com/lingyired/status-trio/actions/runs/40435617420)
at `894a7787b4b9a0fb6add2224cccd85235ff54923`. It passed both cached native
restores, rebuilt both Helpers, and uploaded a valid Universal Ad-hoc package.
Package took 214s and the MobileBattery interval stayed at 45s. Verify took
403s: 13s static preflight, 240s Swift tests, and 134s native/release
contracts. The 240s test stage included a reported 73.64s Swift build and a
134.368s Core XCTest body. Total wall was 737s, including a 116s interval
between verification completion and package start. The job timestamps were
02:04:27Z and 02:06:23Z; the earlier 146s figure was a reporting error.

The subsequent profile moves the native/release contracts into a separate
`native` job on the same `xcode-27` runner. Both jobs check out and reassert
the frozen candidate independently. `package` and `publish` require both jobs
to pass; neither new job receives secrets or Environment access. Diagnostics
remain separate artifacts, so a native failure cannot be hidden by a passing
Swift suite. The full local profile passed after the workflow, policy and
documents changed.

PR #159 merged the profile as
`08644c04ce2f23a69a64582f5f1563b7cc2bb525`. Two diagnostics used that same
frozen SHA, `version=1.7.6`, `build=44`, `publish=false`, `notarize=false`,
and no recovery source. Both used Xcode 27 / Swift 6.4 / SDK 27, passed all
three active jobs, and skipped Publish.

| Scope | Serial baseline `40435617420` | [Parallel 1 `40447422731`](https://github.com/lingyired/status-trio/actions/runs/40447422731) | [Parallel 2 `40448654960`](https://github.com/lingyired/status-trio/actions/runs/40448654960) |
| --- | ---: | ---: | ---: |
| Total wall | 737s / 12m17s | 591s / 9m51s | 667s / 11m07s |
| Verification critical path | 403s | 285s | 368s |
| Swift/static Verify job | 403s, includes native | 285s | 368s |
| Separate Native job | none | 224s | 163s |
| Package job | 214s | 274s | 236s |
| Verification-to-package gap | 116s | 28s | 59s |
| Sum of active job durations | 617s | 783s | 767s |
| Swift test stage | 239.748s | 257.901s | 329.586s |
| Native contract stage | 133.901s | 202.087s | 140.987s |
| Reported Swift test build | 73.64s | 74.85s | 116.68s |
| Core XCTest body | 134.368s | 150.383s | 165.240s |
| Swift Universal Release build | 120s | 152s | 128s |
| MobileBattery total | 45s | 57s | 48s |
| Native cache restore interval | 1s | 5s | 4s |

Verify and Native started at the same second in both parallel runs. Package
started after both succeeded. The 19 unconditional native/offline contracts
remain in Native; the two additional trusted recovery regressions remain
conditional in Verify. Neither normal diagnostic exercised online recovery.
Each full Swift run reported 1,928 Core XCTest and 15 Helper XCTest, with
eight existing skips and zero failures, plus 763 passing Swift Testing tests.

Compared with the serial baseline, the observed verification critical path
fell by 118s (29.28%) and 35s (8.68%). Wall time fell by 146s (19.81%) and
70s (9.50%). The verification-to-package gap also fell by 88s and 57s,
while Package increased by 60s and 22s. Thus the entire wall reduction must
not be attributed to parallel verification. Even with the same candidate,
the two parallel runs differed by 76s wall and 83s in Verify. Runner load
was not measured, and no causal explanation for the stage variation is
established.

The sum of active job durations increased by 166s (26.90%) and 150s
(24.31%). This profile trades a shorter observed verification critical path
for another concurrent runner and more observed runner time. These values
are not billed minutes or proof of a cost reduction. The evidence supports
the structural overlap and the observed elapsed-time ranges; it does not
guarantee a fixed formal-release duration or runner-capacity availability.

Both packages restored and validated the same two exact native cache entries,
skipped third-party dependency compilation, rebuilt both Helpers, and skipped
cache saves. Artifact ZIP digests matched GitHub metadata. Their DMGs matched
their respective frozen-SHA manifests and adjacent checksum files:

| Run | Package artifact | Artifact ZIP SHA-256 | DMG SHA-256 |
| --- | --- | --- | --- |
| `40447422731` | `12708584167` | `d9c71869ea2b0401d9f6940406e7f5a48b5b964fe929df3d95573bdbc9604b63` | `e7f7bd161b4b3a8b3c510ab863c419384da8126ef65cee2c4c389cc3661332a3` |
| `40448654960` | `12709324023` | `c126161c714c8d01c64d5e3644737fd2dbd515371155dcc98c0326ee50462675` | `d614903bab7f5091ca47ab85f824cf7260db70943b66352aec4c14a981e35db4` |

The independent builds are not expected to share a DMG digest. Read-only
inspection checked each package's version/build, ten Universal binaries,
minimum macOS 13 / SDK 27 metadata, Sparkle metadata, and deep strict Ad-hoc
signatures. It did not launch either app or register a Helper.

Raw evidence and the reproducible comparison script are retained in
`.build/ci-optimization-evidence/parallel-native-remote-2026-10-27/`,
including `comparison.json`, `compare.py`, per-run diagnostics, package
manifests, and read-only DMG inspection logs. Cache keys are omitted from
the report.

## Recovery compatibility and policy follow-up

Independent review after the two normal diagnostics found a recovery
compatibility defect: `validate-release-recovery.sh` still required exactly
three source jobs, and its workflow regression retained the old
`package.needs: verify` expectation. Thus normal four-job package runs
could pass while a later recovery would reject their artifacts. This was
found by inspection and reproduced with offline fixtures, not by attempting
a public release.

The validator now matches source-job metadata to the frozen candidate's
workflow. It accepts the exact historical three-job shape or current
four-job shape with their corresponding Package dependencies; the current
shape also requires Native success. A missing Native job cannot downgrade
a four-job workflow to legacy acceptance. New offline cases cover both
valid shapes, package-only and failed-publication sources, missing/failed/
skipped Native, extra jobs, metadata/workflow shape mismatches, and missing
Native dependency.

Policy regressions additionally pin all 19 unconditional native commands and
both conditional trusted recovery regressions, require the normal success
gates, reject conditional Swift/preflight tests, replacement shells, write
permissions or Environment access in verification jobs, and preserve the
release runner and diagnostic ordering. Native summaries now identify Native,
its actual job status, and the `native-diagnostics` artifact. The new missing-
contract, conditional-preflight, and Native-label regressions were observed
failing before their fixes. Full local verification passed in 332.198s,
including the complete Swift suite, Release/local app build, and native/
offline contracts; the recovery regression also passed separately.

Recovery still requires `publish=true` and `notarize=true`; those guards were
not changed to allow a diagnostic recovery. Online recovery/publication,
Developer ID, notarization, Helper/XPC runtime, and macOS 13 runtime remain
`NOT RUN`. The two timing runs above predate this compatibility follow-up
and must not be presented as recovery acceptance.

## Remote warm-source-checkout measurement

PR #162 merged as `518f4e961ceaa26f76fb9f9b120dd6eb4a67d3d2`.
Both diagnostics below used that exact frozen candidate, `version=1.7.6`,
`build=44`, `publish=false`, `notarize=false`, and no recovery source.
The workflow, candidate, toolchain, and inputs were unchanged between runs:
`xcode-27`, Xcode 27.0, Swift 6.4, and SDK 27.0. Changed build scripts made
the first run miss the old keys; the second restored the two newly sealed
prefixes.

| Scope | [Cold `40486083712`](https://github.com/lingyired/status-trio/actions/runs/40486083712) | [Warm `40488843296`](https://github.com/lingyired/status-trio/actions/runs/40488843296) |
| --- | ---: | ---: |
| Total wall | 1,191s / 19m51s | 705s / 11m45s |
| Verification critical path | 405s | 297s |
| Swift/static Verify job | 405s | 297s |
| Separate Native job | 200s | 134s |
| Package job | 750s / 12m30s | 324s / 5m24s |
| Verification-to-package gap | 31s | 79s |
| Sum of active job durations | 1,355s | 755s |
| Swift test stage | 357.227s | 263.756s |
| Reported Swift test build | 141.25s | 80.91s |
| Core XCTest body | 178.443s | 149.490s |
| Swift Universal Release build phase | 223s | 208s |
| MobileBattery source checkout | 34s, six clones | not run, zero clones |
| arm64 dependency phases | 228s | 21s |
| x86_64 dependency phases | 189s | 6s |
| MobileBattery total | 456s | 34s |
| Native cache restore interval | 0s, two misses | 4s, two exact hits |
| Native cache save interval | 2s | 0s, skipped |

The cold TSV emits a dependency row before source preparation and another
after it. The per-architecture values above sum repeated rows with the same
label, including key/inspection work. Source checkout is timed separately
and no longer absorbs compilation. Parent phases still include child phases;
the complete table must not be summed as independent work.

The observed Package saving is **426s (56.80%)** and the MobileBattery saving
is **422s (92.54%)**. Wall fell by **486s (40.81%)**. The 108s shorter
verification critical path and 48s longer verification-to-package gap also
contributed to wall time; the full 486s must not be attributed to caching.
Both Swift test builds and XCTest execution varied on an unchanged candidate.
Runner load was not measured, so the variation has no established cause.
These are two observations, not a guaranteed release duration or billing
measurement. This cold native build was also slower than earlier cold runs;
it is retained rather than replaced with a more favorable sample.

The warm package logged validation and skipped third-party compilation for
both architectures. It rebuilt both Helpers, emitted no
`mobile-source-checkout` row, performed no source clone, and skipped both
cache saves. The two new cache entries remained the same IDs, keys, sizes,
and creation timestamps through the warm run, totaling 14,460,360 compressed
bytes. The previous two entries were preserved.

The preceding warm run
[`40451490957`](https://github.com/lingyired/status-trio/actions/runs/40451490957)
still recorded 27s of source checkout, a 55s MobileBattery interval, a 281s
Package job, and 733s wall. The new warm run eliminated source checkout and
reduced the native interval to 34s, but Package was 43s slower and wall was
28s shorter. Different candidates and runner variation prevent treating
that comparison as an isolated 27s end-to-end speedup.

Both complete Swift runs reported 1,928 Core XCTest and 15 Helper XCTest,
with eight existing skips and zero failures, plus 763 passing Swift Testing
tests. Native and offline release contracts passed in both runs. Downloaded
artifact ZIPs matched GitHub digests, and each DMG matched its own frozen-SHA
manifest and adjacent checksum:

| Run | Package artifact | Artifact ZIP SHA-256 | DMG SHA-256 |
| --- | --- | --- | --- |
| `40486083712` | `12726116510` | `03b92c3de936047720dff57f2ea642685c624e5ade2336803abb5cb09a585865` | `4ac1be9ada0de30170a7079b9041dc34f1e7c044829d6bc0db9b4798b1a5e8db` |
| `40488843296` | `12728321361` | `2a994df647484c2ff3e4790d9844fd9d0847a92ccf712584b404a553eb892556` | `501d4e642098444a31adac23a40a4f1e075793a63f40a21e9f710d483ba9812c` |

Read-only DMG inspection verified version/build, ten binaries with both
architectures, minimum macOS 13 / SDK 27 metadata, Sparkle metadata, and deep
strict Ad-hoc signatures. The workflow retained its Helper `--list` smoke
check. GUI/hardware behavior, privileged Helper/XPC registration, macOS 13
runtime, Developer ID, notarization, and online recovery were not exercised.
Publish was skipped twice. All 18 releases and their asset digests, 18 tags,
the appcast blob, protected Environment settings, and the original worktree
status were unchanged.

Raw run/job metadata, logs, diagnostics, timing TSVs, verified packages,
read-only inspection logs, comparison and public-state audits are retained
under `.build/ci-optimization-evidence/warm-source-skip-remote-2026-10-27/`.

## Reviewed-license cache follow-up

Independent review found that a notice-only change did not alter the cache
identity. A warm cache could therefore package changed reviewed text without
the cold source comparison. It also exposed an ordering defect: the cold
build sealed its marker before comparing licenses, so repeating an input
that failed license verification could reuse that premature marker.

The follow-up binds all reviewed-notice relative paths and file digests to
the cache identity and rejects missing, unreadable, symlink, or unsupported
notice paths. It reuses the existing source comparison before dependency
compilation and cache sealing. Unchanged notices still allow a warm build
without sources. Regressions first reproduced warm acceptance, silently
skipped unreadable directories, and acceptance on a repeated failed build;
the corrected cache fixture passes all three boundaries and the existing
cold/warm, corruption, inventory, and Universal contracts.

The remote pair above predates this follow-up and verifies `518f4e96`, not
the later notice-binding code. Its regression evidence is local. The cache
identity change intentionally causes one cold rebuild per architecture on a
subsequent remote run; no additional performance gain is claimed for it.

## Remaining optimization decisions

The warm run spent 208s in the Universal Swift Release build phase. Debug
test outputs and Universal Release outputs remain different required work;
no compatible compilation-cache experiment has established safe reuse.
The earlier SwiftPM download-only experiment remains local evidence.

The warm job spent 9s resolving exact cache keys, 11s installing/checking
build tools, and 5s validating prefixes before the skipped cache saves.
Avoiding redundant pre-save inspection is a possible seconds-scale
experiment, but its net benefit and replacement integrity boundary have not
been verified. No checks were removed for that unmeasured saving. Further
native-job splitting has no per-contract benchmark or runner-capacity
evidence yet.

## Follow-up measurement plan

1. Completed: run the parallel profile twice on one frozen candidate with
   `publish=false` and no notarization; the comparison is recorded above.
2. Completed: measure source-checkout removal with a same-SHA cold/warm pair;
   retain both the dependency phases and the separate source phase.
3. On a later formal candidate, observe cache invalidation and hit behavior,
   including the reviewed-license binding, signing, and notarization costs.
4. Keep comparisons on the exact same candidate and toolchain; do not compare
   different SDKs or runner images as an isolated cache result.
5. Keep Developer ID signing, notarization, runtime Helper/XPC behavior, and
   public publication as `NOT RUN` until the corresponding protected and
   manual evidence exists. The Ad-hoc package contract and signature checks
   above passed but do not substitute for those gates.

This report records the remote baseline, local native measurements, and
authorized `publish=false` diagnostics; it is not release authorization. The
diagnostics did not create a release or tag, update the appcast, or mutate
protected-environment settings.
