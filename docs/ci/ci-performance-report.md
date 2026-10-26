# Release CI performance report

Status: remote baseline audited 2026-10-26; local implementation measurements
completed overnight on 2026-10-27 (Asia/Shanghai).

This report uses existing GitHub Actions evidence. It makes no promise of a
12-14 minute release and does not claim a speedup from any unmeasured change.

## Observed baseline

- Latest recent full verify/package chain `40344113013`: 20m05s wall,
  including 485s verify and 616s package.
- Latest recovery-only chain `40349355595`: 10m11s wall, including 520s verify
  and 36s publish. Package was skipped, so this is not a full-release time.
- Cold remote package spent roughly 5-6 minutes rebuilding pinned MobileBattery
  dependencies for both architectures in the measured 1.7.3-1.7.5 runs.
- Hot remote / cache-hit behavior: **NOT RUN**.
- A full remote release with the new cache and stage instrumentation:
  **NOT MEASURED**.

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
  boundary.
- **Stage duration** is the corresponding job's start/end timestamps.

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

## Follow-up measurement plan

1. After review and merge, run one full remote `verify/package` from `main`
   with `publish=false` only after explicit maintainer approval, and record
   the artifact hash and same-SHA provenance.
2. Run a second identical candidate to attempt a cache hit; record cache key,
   hit/miss, download/extract time, and MobileBattery interval.
3. Compare arm64 and x86_64 phase rows separately. Treat the x86-to-package
   marker as approximate until a per-architecture completion marker exists.
4. Re-run the package from the exact same candidate and toolchain; do not
   compare different SDKs or runner images as a cache result.
5. Keep `NOT RUN` for signing, notarization, and public publication until the
   corresponding protected and manual evidence exists.

This report records the remote baseline and local native measurements; it is
not release authorization. No release, tag, appcast change, or workflow
dispatch was performed by this task.
