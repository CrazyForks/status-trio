# Test Gate Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `.github/workflows/ci.yml` so `swift test` runs on every pull request and every push to `main`, using the same `macos-26` toolchain the release pipeline uses, without touching the release workflow's permissions.

**Architecture:** A separate, read-only workflow with two triggers (`pull_request`, `push: branches: [main]`), `permissions: contents: read`, pinned action SHAs, a `concurrency` group that cancels superseded runs, and a job `timeout-minutes`. A toolchain-baseline step fails the job when the resolved Xcode or Swift is older than the versions the release workflow accepts. The release workflow is left completely unchanged: it remains the only acceptance path and the only thing that can publish.

**Tech Stack:** GitHub Actions, YAML, Bash, SwiftPM, `xcodebuild`, `swift`, `gh` CLI

**Spec:** Derived from the 2026-09-20 security review; cross-plan index: docs/superpowers/plans/2026-09-20-review-findings-index.md

## Global Constraints

- CI acceptance toolchain is the `macos-26` runner with Xcode 26.6 / Swift 6.3.3; local Xcode 27 / Swift 6.4 is not proof.
- No Developer ID certificate / notarization secrets exist today; Ad-hoc signing is the documented status. Steps requiring a Developer ID must be written as conditional follow-ups, never as assumed prerequisites.
- The app must build with the macOS 26 SDK or newer. `scripts/build-app.sh` fails on an older SDK and `scripts/verify-platform-version.sh` asserts the built binary's `LC_BUILD_VERSION`. Do not remove or weaken either check (see `docs/swift-ci-compatibility.md` and issue #40).
- Run `swift test` and `swift build -c release` for Swift changes; a script-only change must still pass `bash scripts/validate-appcast-notes.sh` and a `publish=false` release preflight where applicable: `gh workflow run release.yml --repo lingyired/status-trio --ref <branch> -f version=1.3.0 -f build=12 -f publish=false` then `gh run watch <run-id> --repo lingyired/status-trio --exit-status`.
- Release notes live in `release-notes/<version>/<language>.md`; `en.md` + `zh-Hans.md` always required; every file starts with a `# <title>` line containing `%VERSION%` and `%BUILD%`. Any user-visible behavior change needs an entry.
- Never print, echo, or pass secrets on a command line; never commit key material.
- This plan creates `.github/workflows/ci.yml` and edits `AGENTS.md` and `docs/swift-ci-compatibility.md` only. `.github/workflows/release.yml` is owned by the release-pipeline plan and must not be edited here.

## Verified Findings

| Finding | Location | Evidence |
| --- | --- | --- |
| `release.yml` is the only workflow | `.github/workflows/` | `ls -1 .github/workflows/` → `release.yml` |
| It triggers only on tags and manual dispatch | `.github/workflows/release.yml:3-25` | `on:` lists `push: tags: ["v*"]` and `workflow_dispatch` |
| No `pull_request` or `push: branches:` trigger exists anywhere | `.github/workflows/` | `grep -rn "pull_request\|branches:" .github/workflows/` → no matches |
| `swift test` runs and its exit code propagates | `.github/workflows/release.yml:242-256` | `TEST_EXIT_CODE=$?` then `exit "${TEST_EXIT_CODE}"` |
| The toolchain is selected with `DEVELOPER_DIR`, not `xcode-select` | `.github/workflows/release.yml:39` | `DEVELOPER_DIR: /Applications/Xcode_26.6.app/Contents/Developer` |
| The runner image ships Xcode 26.6 at that path as the default | `actions/runner-images` `images/macos/macos-26-Readme.md` | `\| 26.6 (default) \| 17F113 \| /Applications/Xcode_26.6.app \| ...` |
| Actions float on mutable major tags | `.github/workflows/release.yml:46`, `.github/workflows/release.yml:266` | `actions/checkout@v4`, `actions/upload-artifact@v4` |
| `AGENTS.md` states PRs get no CI coverage | `AGENTS.md` (Change Flow section) | `The release workflow only runs on tags and manual dispatches, so a pull request does not add CI coverage on its own.` |

Test volume measured during planning: 97 Swift files under `Tests/` totalling 20,487 lines, containing 149 `@Test` functions and 615 `func test…` methods. `Sources/` is 18,398 lines. None of that is exercised before a tag today.

## Review Focus

- **A broken test reaches `main` and is only discovered at tag time.** With no `pull_request` trigger, `main` can carry a red suite until someone happens to dispatch a release preflight. Task 2 adds the trigger; the pinning command is `gh run list --workflow ci.yml --event pull_request --limit 1` returning a run for the first PR after merge.
- **CI could silently run an older toolchain and still pass.** A `macos-26` runner that resolved a different default Xcode would compile with an older Swift than the release path accepts, so green CI would be misleading. Task 3 adds the baseline step; the pinning command is `XCODE_BASELINE=99.0 SWIFT_BASELINE=6.3.3 SDK_MAJOR_BASELINE=26 bash /tmp/st-baseline-check.sh`, which must exit `1` with `Resolved version 27.0 does not satisfy the CI baseline 99.0.` on this machine. Against the current tree that command does not exist at all, and no run reports a resolved toolchain.
- **CI reporting green while the SDK floor is broken.** Issue #40 is about the macOS 26 SDK, and `scripts/build-app.sh:66-70` refuses an older SDK. CI that only runs `swift test` never calls that script. Task 4 adds `swift build -c release` plus an explicit SDK-major check; the pinning command is `xcrun --sdk macosx --show-sdk-version | cut -d. -f1` being `26` or higher.
- **A `pull_request` workflow with write permissions is a privilege-escalation path.** A PR from a fork runs contributor-controlled code; if the workflow carried `contents: write` or a secret, that code could use it. Task 2 sets `permissions: contents: read` at workflow and job scope and references no `secrets.` expression; the pinning command is `grep -c "secrets\." .github/workflows/ci.yml` returning `0`.
- **Superseded runs and hung jobs waste the queue and hide the real failure.** Pushing twice to a PR leaves two runs, and a hung SwiftPM resolve can burn the six-hour default. Task 5 adds `concurrency` with `cancel-in-progress: true` and `timeout-minutes: 45`; the pinning command is `grep -c "cancel-in-progress: true" .github/workflows/ci.yml` returning `1`.

### Task 1: Record the coverage gap as executable evidence

**Files:**
- No file changes. This task captures the "before" state the later tasks must move.

**Interfaces:**
- Consumes: the checked-out repository at the commit under review.
- Produces: the exact commands and baseline outputs Task 6 re-runs.

- [ ] **Step 1: Confirm exactly one workflow exists**

```bash
ls -1 .github/workflows/
```

Expected:

```text
release.yml
```

- [ ] **Step 2: Confirm nothing triggers on pull requests or on `main`**

```bash
grep -rn "pull_request" .github/workflows/ || echo "NO pull_request trigger"
grep -rn "branches:" .github/workflows/ || echo "NO branch trigger"
grep -n "on:" -A 6 .github/workflows/release.yml
```

Expected:

```text
NO pull_request trigger
NO branch trigger
3:on:
4:  push:
5:    tags:
6:      - "v*"
7:  workflow_dispatch:
```

- [ ] **Step 3: Confirm tests only run inside the release job**

```bash
grep -n "swift test" .github/workflows/release.yml
grep -n "name: Run tests" .github/workflows/release.yml
```

Expected: one match for `swift test` at line `245`, inside the `Run tests` step at line `242`, which belongs to the `release` job that only a tag push or a dispatch can start.

- [ ] **Step 4: Confirm the toolchain selection mechanism to mirror**

```bash
grep -n "DEVELOPER_DIR" .github/workflows/release.yml
grep -c "xcode-select" .github/workflows/release.yml
```

Expected: `39:      DEVELOPER_DIR: /Applications/Xcode_26.6.app/Contents/Developer` and `0`. There is no `sudo xcode-select` and no `maxim` step; the workflow pins the toolchain with a job-level `DEVELOPER_DIR`, and `.github/workflows/ci.yml` must do the same rather than introducing a second mechanism.

- [ ] **Step 5: Confirm the current documentation admits the gap**

```bash
grep -n "pull request does not add CI coverage" AGENTS.md
```

Expected: one match. Task 7 removes it because it becomes false.

### Task 2: Create the read-only CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: a workflow named `CI` with triggers `pull_request` and `push: branches: [main]`, workflow-level `permissions: contents: read`, job `test` on `macos-26`, and a `DEVELOPER_DIR` matching `.github/workflows/release.yml:39`.

Both action SHAs were read from the GitHub API during planning and are the same commits the floating major tags resolved to: `actions/checkout` `v4` → `11d5960a326750d5838078e36cf38b85af677262` (`v4.4.0`), `actions/cache` `v4` → `0057852bfaa89a56745cba8c7296529d2fc39830` (`v4.3.0`). Confirm each with `gh api repos/<owner>/<repo>/git/ref/tags/<tag> --jq .object.sha` before committing, and never copy a SHA from prose without checking it.

- [ ] **Step 1: Confirm the file does not exist**

```bash
test -e .github/workflows/ci.yml && echo "EXISTS" || echo "absent"
```

Expected: `absent`.

- [ ] **Step 2: Verify the action SHAs before use**

Query the tag list per repository rather than the single-tag ref endpoint; the single-ref endpoint returned intermittent `EOF` errors from the GitHub API during planning, while the list endpoint resolved consistently:

```bash
for repo in actions/checkout actions/cache; do
  printf '%s: ' "$repo"
  gh api "repos/$repo/tags?per_page=100" --jq '.[] | "\(.name) \(.commit.sha)"' \
    | grep -E "^v4\." | sort -rV | head -1
done
```

Expected:

```text
actions/checkout: v4.4.0 11d5960a326750d5838078e36cf38b85af677262
actions/cache: v4.3.0 0057852bfaa89a56745cba8c7296529d2fc39830
```

If either differs, use the value the API returns in the `uses:` lines below and update the `# vX.Y.Z` comment to the tag that produced it. Never commit a SHA copied from this plan's prose without running this command.

- [ ] **Step 3: Create the workflow**

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  pull_request:
  push:
    branches:
      - main

permissions:
  contents: read

concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    runs-on: macos-26
    timeout-minutes: 45
    permissions:
      contents: read
    env:
      # Must match .github/workflows/release.yml so CI compiles with the same
      # toolchain the release pipeline accepts. See AGENTS.md.
      DEVELOPER_DIR: /Applications/Xcode_26.6.app/Contents/Developer
      XCODE_BASELINE: "26.6"
      SWIFT_BASELINE: "6.3.3"
      SDK_MAJOR_BASELINE: "26"
    steps:
      - name: Check out repository
        uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
        with:
          persist-credentials: false

      - name: Assert toolchain baseline
        run: |
          set -euo pipefail

          XCODE_VERSION="$(DEVELOPER_DIR="${DEVELOPER_DIR}" xcodebuild -version | sed -n 's/^Xcode //p' | head -1)"
          SWIFT_VERSION="$(DEVELOPER_DIR="${DEVELOPER_DIR}" swift --version | sed -n 's/.*Apple Swift version \([0-9][0-9.]*\).*/\1/p' | head -1)"
          SDK_VERSION="$(DEVELOPER_DIR="${DEVELOPER_DIR}" xcrun --sdk macosx --show-sdk-version)"

          echo "Resolved Xcode ${XCODE_VERSION}, Swift ${SWIFT_VERSION}, macOS SDK ${SDK_VERSION}."

          if [[ -z "${XCODE_VERSION}" || -z "${SWIFT_VERSION}" || -z "${SDK_VERSION}" ]]; then
            echo "::error::Could not determine the toolchain version; refusing to report a passing test run."
            exit 1
          fi

          newer_or_equal() {
            local newest
            newest="$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)"
            [[ "$newest" == "$1" ]]
          }

          for pair in "${XCODE_VERSION}:${XCODE_BASELINE}" "${SWIFT_VERSION}:${SWIFT_BASELINE}"; do
            current="${pair%%:*}"
            baseline="${pair##*:}"
            if ! newer_or_equal "${current}" "${baseline}"; then
              echo "::error::Resolved version ${current} does not satisfy the CI baseline ${baseline}."
              echo "::error::This run would compile with a toolchain the release workflow rejects."
              exit 1
            fi
          done

          if (( ${SDK_VERSION%%.*} < ${SDK_MAJOR_BASELINE} )); then
            echo "::error::macOS SDK ${SDK_VERSION} does not satisfy the ${SDK_MAJOR_BASELINE} SDK floor; the app would ship the pre-Tahoe appearance (issue #40)."
            exit 1
          fi

          echo "Toolchain baseline satisfied."

      - name: Cache SwiftPM build
        uses: actions/cache@0057852bfaa89a56745cba8c7296529d2fc39830 # v4.3.0
        with:
          path: .build
          key: ${{ runner.os }}-swiftpm-${{ hashFiles('Package.resolved') }}
          restore-keys: |
            ${{ runner.os }}-swiftpm-

      - name: Run tests
        run: |
          set +e
          swift test
          TEST_EXIT_CODE=$?
          set -e

          if [[ "${TEST_EXIT_CODE}" -ne 0 ]]; then
            echo "SwiftPM resource bundle diagnostics:"
            find .build -name 'StatusTrio_StatusTrioCore.bundle' -type d -print
            find .build -name 'StatusTrio_StatusTrioCore.bundle' -type d -exec find {} -maxdepth 4 -print \;
            find .build -name 'Localizable.strings' -print | head -n 50
          fi

          exit "${TEST_EXIT_CODE}"

      - name: Build release
        run: swift build -c release

      - name: Summarize
        if: always()
        run: |
          {
            echo "### CI toolchain"
            echo ""
            echo "| Item | Resolved |"
            echo "| --- | --- |"
            echo "| Xcode | $(DEVELOPER_DIR="${DEVELOPER_DIR}" xcodebuild -version | sed -n 's/^Xcode //p' | head -1) |"
            echo "| Swift | $(DEVELOPER_DIR="${DEVELOPER_DIR}" swift --version | sed -n 's/.*Apple Swift version \([0-9][0-9.]*\).*/\1/p' | head -1) |"
            echo "| macOS SDK | $(DEVELOPER_DIR="${DEVELOPER_DIR}" xcrun --sdk macosx --show-sdk-version) |"
            echo "| Runner | macos-26 |"
          } >> "${GITHUB_STEP_SUMMARY}"
```

- [ ] **Step 4: Prove the workflow parses and carries no secret reference**

```bash
python3 -m venv /tmp/st-wfcheck && /tmp/st-wfcheck/bin/pip install --quiet pyyaml
/tmp/st-wfcheck/bin/python - <<'PY'
import yaml
d = yaml.load(open('.github/workflows/ci.yml'), Loader=yaml.BaseLoader)
print('triggers:', sorted(d['on'].keys()))
print('workflow permissions:', d['permissions'])
job = d['jobs']['test']
print('runs-on:', job['runs-on'], 'timeout:', job['timeout-minutes'])
print('job permissions:', job['permissions'])
print('env:', job['env'])
print('uses:', [s.get('uses') for s in job['steps'] if 'uses' in s])
PY
grep -c "secrets\." .github/workflows/ci.yml || echo "0 secret references"
```

`yaml.BaseLoader` is required: `yaml.safe_load` resolves the `on:` key to the boolean `True` under YAML 1.1 rules and the script would fail with a `KeyError`.

Expected:

```text
triggers: ['pull_request', 'push']
workflow permissions: {'contents': 'read'}
runs-on: macos-26 timeout: 45
job permissions: {'contents': 'read'}
env: {'DEVELOPER_DIR': '/Applications/Xcode_26.6.app/Contents/Developer', 'XCODE_BASELINE': '26.6', 'SWIFT_BASELINE': '6.3.3', 'SDK_MAJOR_BASELINE': '26'}
uses: ['actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0', 'actions/cache@0057852bfaa89a56745cba8c7296529d2fc39830 # v4.3.0']
0 secret references
```

- [ ] **Step 5: Confirm the toolchain pin matches the release workflow**

```bash
grep -h "DEVELOPER_DIR:" .github/workflows/ci.yml .github/workflows/release.yml
```

Expected: two identical lines, both `/Applications/Xcode_26.6.app/Contents/Developer`. A mismatch means CI and the release path compile with different compilers, which is exactly the situation `AGENTS.md` warns about.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: run tests on pull requests and pushes to main"
```

### Task 3: Prove the baseline step can actually fail

**Files:**
- No file changes. This task tests the Step 3 script from Task 2 without running a workflow.

**Interfaces:**
- Consumes: the `Assert toolchain baseline` script body from Task 2.
- Produces: evidence that the guard rejects an older toolchain and accepts the pinned one.

- [ ] **Step 1: Extract the guard into a runnable script**

```bash
sed -n '/- name: Assert toolchain baseline/,/Toolchain baseline satisfied/p' .github/workflows/ci.yml \
  | sed -n '/run: |/,$p' | sed '1d' | sed 's/^          //' > /tmp/st-baseline-check.sh
bash -n /tmp/st-baseline-check.sh
wc -l /tmp/st-baseline-check.sh
```

Expected: no output from `bash -n`, and roughly 30 lines. If `wc -l` reports 0, the indentation in Task 2 Step 3 drifted; the `run:` block is indented ten spaces.

- [ ] **Step 2: Prove the guard passes on the pinned toolchain**

On this machine `xcodebuild -version` reports `27.0` and `swift --version` reports `6.4`, both newer than the baseline, so the pinned baseline must pass:

```bash
DEVELOPER_DIR="$(xcode-select -p)" XCODE_BASELINE=26.6 SWIFT_BASELINE=6.3.3 SDK_MAJOR_BASELINE=26 \
  bash /tmp/st-baseline-check.sh 2>/dev/null; echo "exit=$?"
```

Expected:

```text
Resolved Xcode 27.0, Swift 6.4, macOS SDK 27.0.
Toolchain baseline satisfied.
exit=0
```

The `2>/dev/null` matters: `swift --version` writes a `swift-driver version: …` line to stderr before the `Apple Swift version …` line it writes to stdout. Redirecting stderr keeps this step's output readable, and it is also why the version must be parsed with `sed -n 's/.*Apple Swift version \([0-9][0-9.]*\).*/\1/p'` rather than by taking the first version-looking token on the line — that token is the driver version, not the compiler version.

- [ ] **Step 3: Prove the guard fails on a baseline the toolchain cannot satisfy**

```bash
DEVELOPER_DIR="$(xcode-select -p)" XCODE_BASELINE=99.0 SWIFT_BASELINE=6.3.3 SDK_MAJOR_BASELINE=26 \
  bash /tmp/st-baseline-check.sh 2>/dev/null; echo "exit=$?"
```

Expected:

```text
Resolved Xcode 27.0, Swift 6.4, macOS SDK 27.0.
::error::Resolved version 27.0 does not satisfy the CI baseline 99.0.
::error::This run would compile with a toolchain the release workflow rejects.
exit=1
```

Raising the baseline above what the machine has is the only way to exercise the failure without installing an old Xcode, and it proves the comparison is wired to the expected value rather than to itself.

- [ ] **Step 4: Prove the guard fails on an older Swift and on an old SDK**

```bash
DEVELOPER_DIR="$(xcode-select -p)" XCODE_BASELINE=26.6 SWIFT_BASELINE=99.0 SDK_MAJOR_BASELINE=26 \
  bash /tmp/st-baseline-check.sh 2>/dev/null; echo "exit=$?"
DEVELOPER_DIR="$(xcode-select -p)" XCODE_BASELINE=26.6 SWIFT_BASELINE=6.3.3 SDK_MAJOR_BASELINE=99 \
  bash /tmp/st-baseline-check.sh 2>/dev/null; echo "exit=$?"
```

Expected: the first exits `1` with `::error::Resolved version 6.4 does not satisfy the CI baseline 99.0.`; the second exits `1` with `::error::macOS SDK 27.0 does not satisfy the 99 SDK floor; the app would ship the pre-Tahoe appearance (issue #40).` A pass in either case means the `sort -V` comparison or the SDK check is not wired to its variable.

- [ ] **Step 5: Confirm nothing was committed**

```bash
git status --short
```

Expected: no changes. `/tmp/st-baseline-check.sh` is outside the repository.

### Task 4: Confirm the release workflow's acceptance role is unchanged

**Files:**
- No file changes. This task is an assertion about the diff.

**Interfaces:**
- Consumes: the new `.github/workflows/ci.yml` from Task 2.
- Produces: proof that adding CI did not weaken the release path.

- [ ] **Step 1: Confirm `release.yml` is byte-identical to its pre-change state**

```bash
git diff --stat main -- .github/workflows/release.yml
git diff --exit-code main -- .github/workflows/release.yml && echo "release.yml unchanged"
```

Expected: no diff output and `release.yml unchanged`. A change here belongs to the release-pipeline plan, not this one.

- [ ] **Step 2: Confirm the CI workflow cannot publish**

```bash
grep -c "scripts/release.sh" .github/workflows/ci.yml || echo "ci.yml never calls release.sh"
grep -c "environment:" .github/workflows/ci.yml || echo "ci.yml declares no environment"
grep -c "contents: write" .github/workflows/ci.yml || echo "ci.yml has no write permission"
grep -c "workflow_run" .github/workflows/ci.yml || echo "ci.yml does not chain off the release workflow"
```

Expected: `ci.yml never calls release.sh`, `ci.yml declares no environment`, `ci.yml has no write permission`, `ci.yml does not chain off the release workflow`. All four are exit-1 from `grep -c` absorbed by `||`.

- [ ] **Step 3: State the boundary in the workflow itself**

Add immediately after the `name: CI` line:

```yaml
# This workflow is a pre-merge gate. It does not publish, does not sign, and does
# not replace the release workflow: .github/workflows/release.yml remains the
# only acceptance path and the only thing that may create a Release or update
# appcast.xml. A green run here means the suite passes on this commit, nothing
# more.
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: document that the CI gate does not replace the release workflow"
```

### Task 5: Confirm caching and concurrency behave as intended

**Files:**
- No file changes.

**Interfaces:**
- Consumes: the workflow from Task 2.
- Produces: verified `concurrency` and cache-key behaviour.

- [ ] **Step 1: Confirm the concurrency group cancels superseded runs**

```bash
grep -n -A2 "concurrency:" .github/workflows/ci.yml
```

Expected:

```text
concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

`github.ref` is `refs/pull/<n>/merge` for pull requests and `refs/heads/main` for pushes, so each PR cancels only its own older runs.

- [ ] **Step 2: Confirm the cache key is pinned to the resolved dependency graph**

```bash
grep -n -A5 "actions/cache" .github/workflows/ci.yml
```

Expected: `key: ${{ runner.os }}-swiftpm-${{ hashFiles('Package.resolved') }}` with a `restore-keys` fallback. Keying on `Package.resolved` rather than `Package.swift` means a dependency bump invalidates the cache, which matters because `Package.resolved` pins Sparkle 2.9.6 at revision `ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a`.

- [ ] **Step 3: Confirm the timeout is present**

```bash
grep -n "timeout-minutes" .github/workflows/ci.yml
```

Expected: `timeout-minutes: 45`. A hung `swift test` on a cold cache is the realistic failure mode; without this the job would occupy a `macos-26` runner for the six-hour default.

- [ ] **Step 4: Confirm nothing was committed**

```bash
git status --short
```

Expected: no changes.

### Task 6: Watch the first run

**Files:**
- No file changes. The workflow cannot be exercised locally because GitHub evaluates `on:`, `permissions`, `concurrency`, and `timeout-minutes`; the only proof is the first real run.

**Interfaces:**
- Consumes: the committed workflow from Tasks 2-5.
- Produces: run IDs recorded in Task 7.

- [ ] **Step 1: Land the workflow on a branch and push it**

```bash
git push origin HEAD:ci/test-gate
gh workflow list --repo lingyired/status-trio
```

Expected: `gh workflow list` shows `CI` with state `active` once GitHub has parsed the file. A missing `CI` entry means the file failed to parse; fix the YAML rather than re-pushing, and re-read the note in `Task 3` before assuming the push was the problem.

- [ ] **Step 2: Open a pull request and capture the run**

```bash
gh pr create --repo lingyired/status-trio --base main --head ci/test-gate \
  --title "ci: add the pre-merge test gate" \
  --body "Adds .github/workflows/ci.yml so swift test runs on pull_request and on push to main. The release workflow is unchanged."

gh run list --repo lingyired/status-trio --workflow ci.yml --event pull_request --limit 3 \
  --json databaseId,status,conclusion,headBranch --jq '.[] | "\(.databaseId) \(.status) \(.conclusion) \(.headBranch)"'
```

Expected: a run appears for `ci/test-gate`. Note the run ID for the next step.

- [ ] **Step 3: Watch it to completion**

```bash
gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

Expected: exit 0, with the `Assert toolchain baseline` step printing `Resolved Xcode 26.6, Swift 6.3.3, macOS SDK 26.x.` and `Toolchain baseline satisfied.` This is the step that proves the pinned `DEVELOPER_DIR` resolves to the toolchain the release path uses. If it prints a different Xcode, stop: the environment pin is wrong and every later green run would be misleading.

- [ ] **Step 4: Confirm the run reports the versions in its summary**

```bash
gh run view <run-id> --repo lingyired/status-trio --json jobs \
  --jq '.jobs[] | "\(.name) \(.conclusion) \(.steps[] | select(.name=="Assert toolchain baseline") | .conclusion)"'
```

Expected: `test success success`. If the baseline step failed, its log names the version that was too old.

- [ ] **Step 5: Prove cancellation on a second push**

```bash
git commit --allow-empty -m "ci: verify superseded runs are cancelled"
git push origin ci/test-gate
gh run list --repo lingyired/status-trio --workflow ci.yml --limit 3 \
  --json databaseId,status,conclusion --jq '.[] | "\(.databaseId) \(.status) \(.conclusion)"'
```

Expected: the newer run completes and the older one reports `cancelled`. A queued-but-never-cancelled older run means the concurrency group is not matching; check that `github.ref` is the same for both pushes.

- [ ] **Step 6: Prove a failing test actually fails the gate**

Introduce a deliberate failure on a scratch branch, confirm the run fails, then revert it:

```bash
git checkout -b ci/failure-probe
printf '\nfunc testDeliberateCIFailure() {\n    XCTFail("deliberate failure probe")\n}\n' >> Tests/StatusTrioCoreTests/ToolchainProbeTests.swift
git add Tests/StatusTrioCoreTests/ToolchainProbeTests.swift
git commit -m "ci: probe that a failing test fails the gate"
git push origin ci/failure-probe
gh pr create --repo lingyired/status-trio --base main --head ci/failure-probe \
  --title "ci: failure probe (do not merge)" --body "Probe only."
gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

Expected: the run fails in `Run tests` and `gh run watch --exit-status` exits non-zero. Close the probe PR without merging and delete the branch:

```bash
gh pr close ci/failure-probe --repo lingyired/status-trio --delete-branch
```

If `Tests/StatusTrioCoreTests/ToolchainProbeTests.swift` does not exist, append the probe to any existing test file instead and revert that file with `git checkout main -- <path>` before closing.

- [ ] **Step 7: Merge and confirm the gate runs on `main`**

```bash
gh pr merge ci/test-gate --repo lingyired/status-trio --squash
gh run list --repo lingyired/status-trio --workflow ci.yml --event push --limit 1 \
  --json databaseId,status,conclusion,headBranch --jq '.[0] | "\(.databaseId) \(.status) \(.conclusion) \(.headBranch)"'
```

Expected: a `push` run appears with `headBranch` `main`. This is the trigger that would have caught a broken test landing on `main` before this plan.

### Task 7: Update the documentation that claims there is no CI

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/swift-ci-compatibility.md`

**Interfaces:**
- Consumes: the run IDs from Task 6.
- Produces: an accurate statement of what CI covers and what it does not.

- [ ] **Step 1: Confirm the stale claim**

```bash
grep -n "a pull request does not add CI coverage on its own" AGENTS.md
tail -5 docs/swift-ci-compatibility.md
```

Expected: one match in `AGENTS.md`, and no entry mentioning `.github/workflows/ci.yml` in the compatibility document.

- [ ] **Step 2: Replace the stale sentence in `AGENTS.md`**

Replace the Change Flow bullet with text that keeps the release rule intact and states the new coverage:

```markdown
- The release workflow only runs on tags and manual dispatches. `.github/workflows/ci.yml` adds a pre-merge gate: it runs `swift test` and `swift build -c release` on every pull request and every push to `main`, on `macos-26` with the same `DEVELOPER_DIR` pin, and fails if the resolved Xcode or Swift is older than the CI baseline. That gate does not replace the release workflow: the `publish=false` release preflight is still required before publishing, and only `release.yml` may create a Release or update `appcast.xml`.
```

- [ ] **Step 3: Record the gate in the compatibility document**

Append a section that names the file, the triggers, the pinned toolchain, the baseline values (`XCODE_BASELINE=26.6`, `SWIFT_BASELINE=6.3.3`, `SDK_MAJOR_BASELINE=26`), and the first successful run IDs from Task 6. Follow the existing `## 失败记录规则` shape: run ID, failed stage, root cause, fix, verification.

- [ ] **Step 4: Prove the claim is gone and the release rule survives**

```bash
grep -c "a pull request does not add CI coverage on its own" AGENTS.md || echo "stale claim removed"
grep -c "publish=false" AGENTS.md
grep -c "only release.yml may create a Release" AGENTS.md
grep -c "ci.yml" docs/swift-ci-compatibility.md
```

Expected: `stale claim removed`, a non-zero count for `publish=false` (the release preflight rule is untouched), `1`, and a non-zero count for `ci.yml`.

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md docs/swift-ci-compatibility.md
git commit -m "docs: describe the new pre-merge CI gate"
```

## Verification

- `ls -1 .github/workflows/` lists both `ci.yml` and `release.yml`, and `grep -rn "pull_request" .github/workflows/` now matches only `ci.yml`.
- The `yaml.BaseLoader` script from Task 2 Step 4 prints `triggers: ['pull_request', 'push']`, `workflow permissions: {'contents': 'read'}`, `runs-on: macos-26 timeout: 45`, and the two pinned `uses:` lines.
- `grep -c "secrets\." .github/workflows/ci.yml` returns `0`; `grep -c "contents: write" .github/workflows/ci.yml` returns `0`; `grep -c "scripts/release.sh" .github/workflows/ci.yml` returns `0`.
- `grep -h "DEVELOPER_DIR:" .github/workflows/ci.yml .github/workflows/release.yml` prints two identical lines.
- `bash /tmp/st-baseline-check.sh` exits `0` with `XCODE_BASELINE=26.6 SWIFT_BASELINE=6.3.3 SDK_MAJOR_BASELINE=26`, and exits `1` with `XCODE_BASELINE=99.0`, with `SWIFT_BASELINE=99.0`, and with `SDK_MAJOR_BASELINE=99`.
- `git diff --exit-code main -- .github/workflows/release.yml` produces no output.
- `gh workflow list --repo lingyired/status-trio` shows `CI` as `active`, and `gh run watch <run-id> --repo lingyired/status-trio --exit-status` exits 0 with `Toolchain baseline satisfied.` in the log.
- A deliberate failing test on a scratch PR fails the run and `gh run watch --exit-status` exits non-zero; the probe PR is closed without merging.
- A second push to the same branch shows the older run `cancelled` and the newer one completed.
- `grep -c "a pull request does not add CI coverage on its own" AGENTS.md` returns `0` while `grep -c "publish=false" AGENTS.md` stays non-zero.
- The first `push` run on `main` appears in `gh run list --workflow ci.yml --event push`.

## Out of Scope

- `.github/workflows/release.yml`. It is owned by the release-pipeline plan and this plan asserts it is unchanged.
- Making CI a required status check. That is a branch-protection setting, so it belongs with the release-pipeline plan's owner actions; adding the workflow without that setting still improves the signal but does not block a merge.
- Running the app, packaging a DMG, or signing anything in CI. Signing needs the Sparkle key and a keychain, which must not be reachable from a `pull_request` run.
- Replacing or duplicating the `publish=false` release preflight. The preflight exercises `scripts/build-app.sh`, `scripts/release.sh`, DMG creation, and appcast validation; a test gate cannot cover those, and `AGENTS.md` keeps requiring the preflight.
- Matrix-testing multiple Xcode versions. The acceptance toolchain is a single pinned version by project rule; a matrix would invite green runs on a toolchain the release path rejects.
- `swift-format`/lint steps. The repository does not run a linter today and adding one is a separate decision.
- Caching `.build` artifacts for cross-run binary reuse. The cache here covers SwiftPM checkouts and compiled artifacts keyed on `Package.resolved`; splitting it further is premature.

## File Ownership & Conflicts

- `.github/workflows/ci.yml` is created and owned exclusively by this plan. No sibling plan may edit it. It must never gain `contents: write`, an `environment:`, a `secrets.` reference, or a call to `scripts/release.sh`.
- `.github/workflows/release.yml` is owned by the release-pipeline plan. This plan does not modify it and Task 4 asserts that with `git diff --exit-code`.
- `AGENTS.md` is touched by both this plan (Task 7, the Change Flow bullet) and the build/signing plan (its line 67 release-body rule). Different sections; if they conflict, keep both edits and re-apply whichever landed second.
- `docs/swift-ci-compatibility.md` is appended to by this plan (Task 7), by the build/signing plan (its Task 7 Step 7), and by the release-pipeline plan (its Task 9). Land each as its own commit and expect a trivial append conflict; the failed-run table and the compatibility notes must not be reordered.
- `Package.swift` and `Package.resolved` are not modified. The cache key depends on `Package.resolved` staying the source of dependency truth.
- The release-pipeline plan creates an environment named `release`; this plan references no environment, so the two cannot collide.
