# Release Pipeline Hardening Implementation Plan

> **STATUS: DEFERRED — do not start (owner decision, 2026-09-20).** Nothing here changes what an installed user runs, but it edits the release path and several controls (protected environment, tag protection, secret handling) need the owner's action in repository settings. See `2026-09-20-review-findings-index.md` §0.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `.github/workflows/release.yml` into a least-privilege, review-gated release pipeline so that the Sparkle EdDSA private key, the release token, and the published feed can no longer be reached by unreviewed code.

**Architecture:** Split the single `release` job into an unprivileged `validate` job (read-only `GITHUB_TOKEN`, no secrets, no environment) and a `release` job that runs behind a protected `release` environment with required reviewers and `contents: write`. Add a trusted-ref guard, pin both actions to immutable commit SHAs, stop persisting checkout credentials, and restrict the imported Developer ID key to `/usr/bin/codesign`.

**Tech Stack:** GitHub Actions, YAML, Bash, `security` (macOS keychain CLI), `gh` CLI, `actions/checkout`, `actions/upload-artifact`

**Spec:** Derived from the 2026-09-20 security review (finding **R-10**); cross-plan index: docs/superpowers/plans/2026-09-20-review-findings-index.md

## Global Constraints

- CI acceptance toolchain is the `macos-26` runner with Xcode 26.6 / Swift 6.3.3; local Xcode 27 / Swift 6.4 is not proof.
- No Developer ID certificate / notarization secrets exist today; Ad-hoc signing is the documented status. Steps requiring a Developer ID must be written as conditional follow-ups, never as assumed prerequisites.
- The app must build with the macOS 26 SDK or newer. `scripts/build-app.sh` fails on an older SDK and `scripts/verify-platform-version.sh` asserts the built binary's `LC_BUILD_VERSION`. Do not remove or weaken either check (see `docs/swift-ci-compatibility.md` and issue #40).
- Run `swift test` and `swift build -c release` for Swift changes; a script-only change must still pass `bash scripts/validate-appcast-notes.sh` and a `publish=false` release preflight where applicable: `gh workflow run release.yml --repo lingyired/status-trio --ref <branch> -f version=1.3.0 -f build=12 -f publish=false` then `gh run watch <run-id> --repo lingyired/status-trio --exit-status`.
- Release notes live in `release-notes/<version>/<language>.md`; `en.md` + `zh-Hans.md` always required; every file starts with a `# <title>` line containing `%VERSION%` and `%BUILD%`. Any user-visible behavior change needs an entry.
- Never print, echo, or pass secrets on a command line; never commit key material.
- This plan touches `.github/workflows/release.yml` only. The Sparkle private-key handling inside `scripts/release.sh` (line 199 pipes the key on stdin and line 152 strips it from the child environment via `env -u`) is already correct and is covered by a sibling plan. Do not change it here.

## Verified Findings

Every line number below was re-read from the working tree before this plan was written.

| Finding | Location | Evidence |
| --- | --- | --- |
| Trigger is tag push or manual dispatch; a dispatch may name any branch | `.github/workflows/release.yml:3-25` | `on:` lists only `push: tags: ["v*"]` and `workflow_dispatch` |
| No job declares an `environment`, so nothing requires a reviewer | `.github/workflows/release.yml` | `grep -c "environment:" .github/workflows/release.yml` → `0` |
| A tag push publishes with no human in the loop | `.github/workflows/release.yml:42` | `PUBLISH: ${{ github.event_name == 'push' || inputs.publish }}` |
| Secrets and a write token are exported into the release step | `.github/workflows/release.yml:258-262` | `GH_TOKEN: ${{ secrets.RELEASE_TOKEN \|\| secrets.GITHUB_TOKEN }}`, `SPARKLE_PRIVATE_KEY: ...`, then `run: bash scripts/release.sh` |
| The workflow grants write at workflow scope | `.github/workflows/release.yml:27-28` | `permissions:` / `contents: write` |
| `-A` gives every runner process the imported key; the password is on `argv` | `.github/workflows/release.yml:139-144` | `security import "${CERT_PATH}" -P "${CERTIFICATE_PASSWORD}" -A ...` |
| Actions float on mutable major tags | `.github/workflows/release.yml:46`, `.github/workflows/release.yml:266` | `actions/checkout@v4`, `actions/upload-artifact@v4` |
| Checkout persists a credential into the local git config | `.github/workflows/release.yml:46-48` | no `persist-credentials: false` |

The Sparkle key itself is handled correctly: `scripts/release.sh:199` pipes it on stdin (`printf '%s' "$SPARKLE_PRIVATE_KEY" | env -u SPARKLE_PRIVATE_KEY "$SIGN_UPDATE" --ed-key-file -`). This plan does not change that.

Repository facts confirmed through the GitHub API during planning: the only repository secret is `SPARKLE_PRIVATE_KEY` (so `secrets.RELEASE_TOKEN` is unset and the expression falls through to `secrets.GITHUB_TOKEN`); no repository variables are set (so `vars.RELEASE_REPO` and `vars.RELEASE_BRANCH` are empty and `scripts/release.sh:30-31` falls back to `release.json`); the repository owner is `lingyired` (numeric user id `804785`); one ruleset named `Protect main` exists with `rules: [deletion, non_fast_forward]` on `refs/heads/main`; the only existing environment is `copilot`.

## Review Focus

- **An unreviewed branch dispatch reaches the Sparkle key.** Anyone with push access can edit `scripts/release.sh` on a branch and dispatch the workflow with that branch as `--ref`; today the release step starts immediately with `SPARKLE_PRIVATE_KEY` in its environment, and the EdDSA private key forges updates for every installed copy. Task 2 pins this with `gh api repos/lingyired/status-trio/environments/release --jq '[.protection_rules[].type] | join(",")'` expected to contain `required_reviewers`, plus the trusted-ref guard at Task 3.
- **A tag push publishes without any human decision.** `PUBLISH` is `true` for every `push` on `v*` (`.github/workflows/release.yml:42`), so a mistyped or attacker-pushed tag ships a GitHub Release and an appcast item. Task 2 makes the publish job wait for the `release` environment, and Task 9 restricts who can create `v*` tags; the reviewer sees the resolved `VERSION`/`BUILD`/`TAG` before approving.
- **The imported Developer ID key is readable by every process on the runner.** `-A` (`.github/workflows/release.yml:141`) grants unrestricted access to the private key, so a compromised build step can sign arbitrary code. Task 5 removes `-A` and grants access only to `/usr/bin/codesign` via `-T`.
- **The certificate password is on the process list.** `-P "${CERTIFICATE_PASSWORD}"` at `.github/workflows/release.yml:140` is visible to any process that reads `argv`. Task 5 feeds the passphrase on stdin instead, which was measured on this machine to work (`printf '%s' pw | security import cert.p12 -T /usr/bin/codesign -t cert -f pkcs12 -k kc-db` exits 0; a wrong passphrase exits 1 with `SecKeychainItemImport: The user name or passphrase you entered is not correct.`).
- **A mutable action tag can change under a release.** `actions/checkout@v4` (`.github/workflows/release.yml:46`) resolves through a movable tag; the commit it pointed to during planning was `11d5960a326750d5838078e36cf38b85af677262` (`v4.4.0`, dated 2026-07-16). Task 4 pins both actions to commit SHAs, and Task 4's verification `git config --get http.https://github.com/.extraheader` returning nothing pins that no token is left in the checkout for later steps.

### Task 1: Record the current exposure as executable evidence

**Files:**
- No file changes in this task. It captures the "before" evidence the later tasks must move.

**Interfaces:**
- Consumes: the checked-out repository at the commit under review.
- Produces: the exact commands and baseline outputs that Tasks 2-6 re-run to prove improvement.

- [ ] **Step 1: Confirm the directory holds exactly one workflow and it has no review gate**

Run:

```bash
ls .github/workflows/
grep -c "environment:" .github/workflows/release.yml
grep -c "persist-credentials" .github/workflows/release.yml
```

Expected:

```text
release.yml
0
0
```

- [ ] **Step 2: Confirm the publish flag is true on every tag push**

Run:

```bash
grep -n "PUBLISH:" .github/workflows/release.yml
```

Expected:

```text
42:      PUBLISH: ${{ github.event_name == 'push' || inputs.publish }}
```

- [ ] **Step 3: Confirm the private key reaches an ungated step**

Run:

```bash
sed -n '258,262p' .github/workflows/release.yml
```

Expected: the `Build, sign, notarize, and publish` step name, then `GH_TOKEN` and `SPARKLE_PRIVATE_KEY` in its `env:`, then `run: bash scripts/release.sh`.

- [ ] **Step 4: Confirm the keychain import is over-permissive**

Run:

```bash
grep -n -- "-A" .github/workflows/release.yml
grep -n -- "-P " .github/workflows/release.yml
grep -c -- "-T /usr/bin/codesign" .github/workflows/release.yml
```

Expected:

```text
141:            -A \
140:            -P "${CERTIFICATE_PASSWORD}" \
0
```

- [ ] **Step 5: Confirm both actions float**

Run:

```bash
grep -n "uses:" .github/workflows/release.yml
```

Expected:

```text
46:        uses: actions/checkout@v4
266:        uses: actions/upload-artifact@v4
```

- [ ] **Step 6: Confirm the release environment does not exist yet**

Run:

```bash
gh api repos/lingyired/status-trio/environments --jq '[.environments[].name] | join(",")'
```

Expected: `copilot` (no `release` entry). This command fails its assertion on purpose; Task 8 creates the environment.

### Task 2: Split the run into a read-only `validate` job and a gated `release` job

**Files:**
- Modify: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: the environment named `release`, created in Task 8.
- Produces: a `validate` job that always runs with `permissions: contents: read` and no `env:` block containing secrets, and a `release` job with `needs: validate`, `if: ${{ needs.validate.outputs.publish == 'true' }}`, `environment: release`, and `permissions: contents: write`.

Splitting is what makes the approval gate meaningful. GitHub exposes a job's secrets only after the job's environment protection rules are satisfied, so moving `SPARKLE_PRIVATE_KEY` out of job-level `env:` and into the gated job is the control; everything else here is supporting least privilege.

- [ ] **Step 1: Verify the action SHAs before pasting them**

Query the tag list per repository rather than the single-tag ref endpoint; the single-ref endpoint returned intermittent `EOF` errors from the GitHub API during planning, while the list endpoint resolved consistently:

```bash
for repo in actions/checkout actions/upload-artifact; do
  printf '%s: ' "$repo"
  gh api "repos/$repo/tags?per_page=100" --jq '.[] | "\(.name) \(.commit.sha)"' \
    | grep -E "^v4\." | sort -rV | head -1
done
```

Expected:

```text
actions/checkout: v4.4.0 11d5960a326750d5838078e36cf38b85af677262
actions/upload-artifact: v4.6.2 ea165f8d65b6e75b540449e92b4886f43607fa02
```

If either differs, use the value the API returns in the workflow below and update the `# vX.Y.Z` comment to the tag that produced it. Never commit a SHA copied from this plan's prose without running this command.

- [ ] **Step 2: Write the split workflow**

The resulting `.github/workflows/release.yml` must satisfy all of the following, which the later steps check one by one:

```yaml
name: Build and Release macOS

on:
  push:
    tags:
      - "v*"
  workflow_dispatch:
    inputs:
      version:
        description: "Marketing version, for example 1.2.0. Defaults to Support/Info.plist."
        required: false
        type: string
      build:
        description: "Numeric CFBundleVersion. Defaults to the GitHub run number for manual runs."
        required: false
        type: string
      tag:
        description: "Release tag. Defaults to vVERSION."
        required: false
        type: string
      publish:
        description: "Create a GitHub Release and publish appcast.xml."
        required: true
        default: false
        type: boolean

permissions:
  contents: read

concurrency:
  group: macos-release-${{ github.ref }}
  cancel-in-progress: false

jobs:
  validate:
    runs-on: macos-26
    timeout-minutes: 90
    permissions:
      contents: read
    env:
      DEVELOPER_DIR: /Applications/Xcode_26.6.app/Contents/Developer
      RELEASE_REPO: ${{ vars.RELEASE_REPO }}
      RELEASE_BRANCH: ${{ vars.RELEASE_BRANCH }}
      PUBLISH: ${{ github.event_name == 'push' || inputs.publish }}
    outputs:
      version: ${{ steps.version.outputs.version }}
      build: ${{ steps.version.outputs.build }}
      tag: ${{ steps.version.outputs.tag }}
      publish: ${{ steps.version.outputs.publish }}
    steps:
      - name: Check out repository
        uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
        with:
          fetch-depth: 0
          persist-credentials: false

      - name: Show toolchain
        run: |
          swift --version
          xcodebuild -version

      - name: Resolve release version
        id: version
        env:
          VERSION_INPUT: ${{ inputs.version }}
          BUILD_INPUT: ${{ inputs.build }}
          TAG_INPUT: ${{ inputs.tag }}
        run: |
          set -euo pipefail

          PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)"
          PLIST_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Support/Info.plist)"

          if [[ "${GITHUB_REF_TYPE}" == "tag" ]]; then
            TAG="${GITHUB_REF_NAME}"
            VERSION="${TAG#v}"
            BUILD="${PLIST_BUILD}"

            if [[ "${VERSION}" != "${PLIST_VERSION}" ]]; then
              echo "::error::Tag ${TAG} does not match CFBundleShortVersionString ${PLIST_VERSION}."
              exit 1
            fi
          else
            VERSION="${VERSION_INPUT:-${PLIST_VERSION}}"
            BUILD="${BUILD_INPUT:-${GITHUB_RUN_NUMBER}}"
            TAG="${TAG_INPUT:-v${VERSION}}"
          fi

          if [[ ! "${VERSION}" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
            echo "::error::VERSION must contain dot-separated numbers."
            exit 1
          fi

          if [[ ! "${BUILD}" =~ ^[0-9]+$ ]]; then
            echo "::error::BUILD must contain only digits."
            exit 1
          fi

          {
            echo "version=${VERSION}"
            echo "build=${BUILD}"
            echo "tag=${TAG}"
            echo "publish=${PUBLISH}"
          } >> "${GITHUB_OUTPUT}"

          echo "Resolved release ${TAG}: ${VERSION} (${BUILD}), publish=${PUBLISH}"

      - name: Validate appcast notes
        run: bash scripts/validate-appcast-notes.sh

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

  release:
    needs: validate
    if: ${{ needs.validate.outputs.publish == 'true' }}
    runs-on: macos-26
    timeout-minutes: 90
    environment: release
    permissions:
      contents: write
    env:
      DEVELOPER_DIR: /Applications/Xcode_26.6.app/Contents/Developer
      RELEASE_REPO: ${{ vars.RELEASE_REPO }}
      RELEASE_BRANCH: ${{ vars.RELEASE_BRANCH }}
      PUBLISH: "true"
      VERSION: ${{ needs.validate.outputs.version }}
      BUILD: ${{ needs.validate.outputs.build }}
      TAG: ${{ needs.validate.outputs.tag }}
    steps:
      - name: Check out repository
        uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
        with:
          fetch-depth: 0
          persist-credentials: false

      - name: Show toolchain
        run: |
          swift --version
          xcodebuild -version

      - name: Validate appcast notes
        run: bash scripts/validate-appcast-notes.sh

      - name: Validate Sparkle signing secret
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          set -euo pipefail
          if [[ -z "${SPARKLE_PRIVATE_KEY}" ]]; then
            echo "::error::Set the SPARKLE_PRIVATE_KEY repository secret before publishing updates."
            exit 1
          fi

      - name: Configure Developer ID signing
        env:
          DEVELOPER_ID_CERTIFICATE_P12: ${{ secrets.DEVELOPER_ID_CERTIFICATE_P12 }}
          CERTIFICATE_PASSWORD: ${{ secrets.DEVELOPER_ID_CERTIFICATE_PASSWORD }}
        run: |
          set -euo pipefail

          if [[ -z "${DEVELOPER_ID_CERTIFICATE_P12}" ]]; then
            echo "Developer ID signing is not configured; using Ad-hoc signing."
            exit 0
          fi

          if [[ -z "${CERTIFICATE_PASSWORD}" ]]; then
            echo "::error::DEVELOPER_ID_CERTIFICATE_PASSWORD is required when a certificate is provided."
            exit 1
          fi

          CERT_PATH="${RUNNER_TEMP}/developer-id.p12"
          KEYCHAIN_PATH="${RUNNER_TEMP}/app-signing.keychain-db"
          KEYCHAIN_PASSWORD="$(openssl rand -hex 24)"

          printf '%s' "${DEVELOPER_ID_CERTIFICATE_P12}" | base64 -D > "${CERT_PATH}"

          security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
          security set-keychain-settings -lut 21600 "${KEYCHAIN_PATH}"
          security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
          printf '%s' "${CERTIFICATE_PASSWORD}" | security import "${CERT_PATH}" \
            -T /usr/bin/codesign \
            -t cert \
            -f pkcs12 \
            -k "${KEYCHAIN_PATH}"
          rm -f "${CERT_PATH}"
          security set-key-partition-list \
            -S apple-tool:,apple: \
            -s \
            -k "${KEYCHAIN_PASSWORD}" \
            "${KEYCHAIN_PATH}" >/dev/null
          security list-keychains -d user -s "${KEYCHAIN_PATH}" \
            $(security list-keychains -d user | tr -d '"')

          IDENTITY="$(
            security find-identity -v -p codesigning "${KEYCHAIN_PATH}" \
              | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' \
              | head -n 1
          )"

          if [[ -z "${IDENTITY}" ]]; then
            echo "::error::No Developer ID Application identity was found in the imported certificate."
            exit 1
          fi

          {
            echo "CODE_SIGN_IDENTITY=${IDENTITY}"
            echo "KEYCHAIN_PATH=${KEYCHAIN_PATH}"
          } >> "${GITHUB_ENV}"

      - name: Configure Apple notarization
        env:
          NOTARY_API_KEY_ID: ${{ secrets.APPSTORE_CONNECT_API_KEY_ID }}
          NOTARY_API_ISSUER_ID: ${{ secrets.APPSTORE_CONNECT_API_ISSUER_ID }}
          NOTARY_API_PRIVATE_KEY: ${{ secrets.APPSTORE_CONNECT_API_PRIVATE_KEY }}
        run: |
          set -euo pipefail

          if [[ -z "${NOTARY_API_PRIVATE_KEY}" ]]; then
            echo "Apple notarization is not configured."
            exit 0
          fi

          if [[ -z "${NOTARY_API_KEY_ID}" || -z "${NOTARY_API_ISSUER_ID}" ]]; then
            echo "::error::App Store Connect API key ID and issuer ID are required for notarization."
            exit 1
          fi

          KEY_PATH="${RUNNER_TEMP}/AuthKey_${NOTARY_API_KEY_ID}.p8"
          printf '%s' "${NOTARY_API_PRIVATE_KEY}" > "${KEY_PATH}"

          xcrun notarytool store-credentials "status-trio-notary" \
            --key "${KEY_PATH}" \
            --key-id "${NOTARY_API_KEY_ID}" \
            --issuer "${NOTARY_API_ISSUER_ID}"
          rm -f "${KEY_PATH}"

          echo "NOTARY_PROFILE=status-trio-notary" >> "${GITHUB_ENV}"

      - name: Prepare release notes
        run: |
          set -euo pipefail
          NOTES_DIR="${GITHUB_WORKSPACE}/release-notes/${VERSION}"
          RELEASE_BODY_PATH="${RUNNER_TEMP}/github-release-notes.md"

          for language in en zh-Hans; do
            if [[ ! -f "${NOTES_DIR}/${language}.md" ]]; then
              echo "::error::Release notes file does not exist: ${NOTES_DIR}/${language}.md"
              exit 1
            fi
          done

          # The body carries its own H1, so each language's '# <title>' line is
          # dropped; '## section' headings are preserved.
          {
            printf '# Version %s （English + 中文， 中文在下方）\n\n' "${VERSION}"
            printf '## English\n\n'
            grep -v '^# ' "${NOTES_DIR}/en.md"
            printf '\n## 中文\n\n'
            grep -v '^# ' "${NOTES_DIR}/zh-Hans.md"
          } > "${RELEASE_BODY_PATH}"

          {
            printf '\n## First launch / 首次启动\n\n'
            printf 'Status Trio is Ad-hoc signed and is not notarized by Apple. macOS cannot\n'
            printf 'verify the publisher, so the first launch is a decision you make, not a\n'
            printf 'check macOS can make for you. Only continue if you downloaded this DMG\n'
            printf 'from the official GitHub Releases page.\n\n'
            printf 'The published SHA-256 in the same release protects against a corrupted or\n'
            printf 'truncated download. It cannot protect you if the release itself was\n'
            printf 'published by someone who should not have: the checksum and the DMG come\n'
            printf 'from the same place.\n\n'
            printf 'If macOS blocks the first launch, run:\n\n'
            printf '```bash\n'
            printf 'xattr -dr com.apple.quarantine "/Applications/Status Trio.app"\n'
            printf 'open "/Applications/Status Trio.app"\n'
            printf '```\n\n'
            printf 'Status Trio 使用 Ad-hoc 签名，未经 Apple 公证。macOS 无法验证发布者，首次启动\n'
            printf '需要你自行决定是否信任，而不是由 macOS 替你判断。请仅在你从官方 GitHub Releases\n'
            printf '页面下载该 DMG 时才继续。\n\n'
            printf '同一 Release 中公布的 SHA-256 只能防止下载损坏或截断，无法防止 Release 本身被\n'
            printf '不应发布的人发布：校验和与 DMG 来自同一个地方。\n\n'
            printf '如果 macOS 阻止首次启动，请运行：\n\n'
            printf '```bash\n'
            printf 'xattr -dr com.apple.quarantine "/Applications/Status Trio.app"\n'
            printf 'open "/Applications/Status Trio.app"\n'
            printf '```\n'
          } >> "${RELEASE_BODY_PATH}"

          {
            echo "RELEASE_NOTES_DIR=${NOTES_DIR}"
            echo "RELEASE_BODY_FILE=${RELEASE_BODY_PATH}"
          } >> "${GITHUB_ENV}"

      - name: Build, sign, notarize, and publish
        env:
          GH_TOKEN: ${{ secrets.RELEASE_TOKEN || secrets.GITHUB_TOKEN }}
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: bash scripts/release.sh

      - name: Upload release artifacts
        if: always()
        uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2
        with:
          name: StatusTrio-${{ github.run_number }}
          path: |
            dist/*.dmg
            dist/*.dmg.sha256
            dist/release.env
          if-no-files-found: ignore

      - name: Clean up signing keychain
        if: always() && env.KEYCHAIN_PATH != ''
        run: security delete-keychain "${KEYCHAIN_PATH}" || true
```

- [ ] **Step 3: Prove the workflow still parses as YAML with the expected shape**

Run:

```bash
python3 -m venv /tmp/st-wfcheck && /tmp/st-wfcheck/bin/pip install --quiet pyyaml
/tmp/st-wfcheck/bin/python - <<'PY'
import yaml
d = yaml.load(open('.github/workflows/release.yml'), Loader=yaml.BaseLoader)
print('triggers:', sorted(d['on'].keys()))
print('workflow permissions:', d['permissions'])
for name, job in d['jobs'].items():
    print(f"{name}: needs={job.get('needs')} env_key={job.get('environment')} perms={job.get('permissions')}")
    print(f"  secrets in job env: {[k for k in (job.get('env') or {}) if 'secret' in str(job.get('env')[k])]}")
    print(f"  uses: {[s.get('uses') for s in job['steps'] if 'uses' in s]}")
PY
```

`yaml.BaseLoader` is required: `yaml.safe_load` resolves the `on:` key to the boolean `True` under YAML 1.1 rules. The same script run against the pre-change file printed `on keys: ['push', 'workflow_dispatch']`, `perm: {'contents': 'write'}`, and `uses: ['actions/checkout@v4', 'actions/upload-artifact@v4']`.

Expected:

```text
triggers: ['push', 'workflow_dispatch']
workflow permissions: {'contents': 'read'}
validate: needs=None env_key=None perms={'contents': 'read'}
  secrets in job env: []
  uses: ['actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0']
release: needs=validate env_key=release perms={'contents': 'write'}
  secrets in job env: []
  uses: ['actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0', 'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2']
```

- [ ] **Step 4: Prove no job-level environment block carries a secret**

Run:

```bash
grep -c "environment: release" .github/workflows/release.yml
grep -n "SPARKLE_PRIVATE_KEY" .github/workflows/release.yml
```

Expected: `1`, then two matches only — the `Validate Sparkle signing secret` step and the `Build, sign, notarize, and publish` step, both inside the `release` job. A third match outside the `release` job means the split is incomplete.

- [ ] **Step 5: Prove the destructive path stays honest about the missing Developer ID**

Run:

```bash
grep -n "not configured; using Ad-hoc signing" .github/workflows/release.yml
```

Expected: one match inside the `Configure Developer ID signing` step. The Developer ID and notarization steps remain conditional: with neither secret set they print a message and exit 0, so the Ad-hoc path is unchanged and no step assumes a certificate exists.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: split release into a read-only validate job and a gated release job"
```

### Task 3: Restrict dispatch to trusted refs

**Files:**
- Modify: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: a first step in the `validate` job named `Enforce trusted refs` that exits non-zero for any `refs/heads/...` outside the allowlist.

- [ ] **Step 1: Confirm no ref guard exists**

Run:

```bash
grep -c "TRUSTED_REFS\|refs/heads/main" .github/workflows/release.yml
```

Expected: `0`.

- [ ] **Step 2: Add the guard as the first step of the `validate` job**

Insert before `Check out repository`:

```yaml
      - name: Enforce trusted refs
        run: |
          set -euo pipefail
          TRUSTED_REFS="^(refs/tags/v[0-9].*|refs/heads/main|refs/heads/release/.*)$"
          if [[ ! "${GITHUB_REF}" =~ ${TRUSTED_REFS} ]]; then
            echo "::error::Refusing to build ${GITHUB_REF}. Allowed refs: ${TRUSTED_REFS}"
            echo "::error::Push to main, use a release/* branch, or push a v* tag."
            exit 1
          fi
          echo "Trusted ref ${GITHUB_REF}."
```

Also add the same step as the first step of the `release` job, so the gated job cannot be reached through any path the `validate` job does not cover.

- [ ] **Step 3: Prove the pattern matches and rejects correctly**

Run the guard body against representative refs:

```bash
TRUSTED_REFS="^(refs/tags/v[0-9].*|refs/heads/main|refs/heads/release/.*)$"
for r in refs/tags/v1.3.0 refs/heads/main refs/heads/release/1.3 refs/heads/feature/x refs/pull/7/merge refs/heads/release-none; do
  if [[ "$r" =~ $TRUSTED_REFS ]]; then echo "ALLOW $r"; else echo "REJECT $r"; fi
done
```

Expected:

```text
ALLOW refs/tags/v1.3.0
ALLOW refs/heads/main
ALLOW refs/heads/release/1.3
REJECT refs/heads/feature/x
REJECT refs/pull/7/merge
REJECT refs/heads/release-none
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: refuse release runs from untrusted refs"
```

### Task 4: Pin actions to commit SHAs and stop persisting checkout credentials

**Files:**
- Modify: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: the two `uses:` lines already rewritten in Task 2.
- Produces: both actions resolved by immutable SHA, and `persist-credentials: false` on both checkouts.

SHAs were read from the GitHub API during planning and are the same commits the floating major tags pointed at: `actions/checkout` `v4` → `11d5960a326750d5838078e36cf38b85af677262` (`v4.4.0`), `actions/upload-artifact` `v4` → `ea165f8d65b6e75b540449e92b4886f43607fa02` (`v4.6.2`). Keeping the `# vX.Y.Z` comment is what makes Dependabot able to update them.

- [ ] **Step 1: Confirm no floating tag remains**

Run:

```bash
grep -n "uses:" .github/workflows/release.yml | grep -v "@[0-9a-f]\{40\}" || echo "all pinned"
```

Expected: `all pinned`.

- [ ] **Step 2: Add a step that fails if checkout left a credential behind**

Insert after the `Show toolchain` step in the `validate` job:

```yaml
      - name: Assert no persisted git credential
        run: |
          set -euo pipefail
          if git config --local --get-regexp '^http\..*\.extraheader$' >/dev/null 2>&1; then
            echo "::error::actions/checkout persisted a credential into .git/config."
            git config --local --get-regexp '^http\..*\.extraheader$' | sed 's/:.*/: <redacted>/'
            exit 1
          fi
          echo "No persisted git credential."
```

The step prints only the key name, never the header value, so the assertion cannot leak the token.

- [ ] **Step 3: Prove the assertion is meaningful**

A checkout with persisted credentials sets `http.https://github.com/.extraheader` in the local git config. Run the check against the current checkout, which has no such key:

```bash
git config --local --get-regexp '^http\..*\.extraheader$' || echo "No persisted git credential."
```

Expected: `No persisted git credential.` (exit 1 from `git config`, absorbed by `||`).

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: pin release actions to commit SHAs and drop persisted checkout credentials"
```

### Task 5: Grant the imported key to `codesign` only, and keep the passphrase off `argv`

**Files:**
- Modify: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: the `Configure Developer ID signing` step as rewritten in Task 2.
- Produces: a `security import` invocation with no `-A`, an explicit `-T /usr/bin/codesign`, and the passphrase delivered on stdin.

This step only runs when `DEVELOPER_ID_CERTIFICATE_P12` is set, which is not the case today. The point of the change is that the day the certificate is added, it is not added with `-A`.

- [ ] **Step 1: Confirm the over-permissive import is gone and the narrowed one is present**

Run:

```bash
grep -c -F -- "-A \" .github/workflows/release.yml
grep -c -F -- "-T /usr/bin/codesign" .github/workflows/release.yml
grep -A3 -F -- "security import" .github/workflows/release.yml
```

Against the pre-change file the first command prints `1` (line 141); it must print `0` afterwards. The second must print `1` afterwards. The third must show `printf '%s' "${CERTIFICATE_PASSWORD}" | security import` and no `-P` on the following lines.

- [ ] **Step 2: Prove the passphrase can be delivered on stdin**

`security import` has no file-descriptor option for the passphrase; its `-P` flag takes the passphrase itself on `argv`, which is the exposure. Omitting `-P` makes `security` read the passphrase from stdin. Measured on this machine with a throwaway self-signed p12:

```bash
openssl req -x509 -newkey rsa:2048 -keyout k.pem -out c.pem -days 1 -nodes -subj "/CN=ST Test"
openssl pkcs12 -export -out cert.p12 -inkey k.pem -in c.pem -passout pass:testpw123
security create-keychain -p kcpw /tmp/st-test-db && security unlock-keychain -p kcpw /tmp/st-test-db
printf '%s' testpw123 | security import cert.p12 -T /usr/bin/codesign -t cert -f pkcs12 -k /tmp/st-test-db; echo "exit=$?"
printf '%s' wrongpw   | security import cert.p12 -T /usr/bin/codesign -t cert -f pkcs12 -k /tmp/st-test-db; echo "exit=$?"
security delete-keychain /tmp/st-test-db
```

Expected: the first import prints `password to unlock cert.p12:` on stderr and exits `0`; the second exits `1` with `security: SecKeychainItemImport: The user name or passphrase you entered is not correct.` A silent exit 0 on the second command would mean stdin delivery is not working and the step must be reverted to `-P` with a comment recording the limitation.

- [ ] **Step 3: Confirm the man page documents both flags being used**

Run:

```bash
man security | col -b | grep -A2 -- "-T appPath"
```

Expected: `-T appPath    Specify an application which may access the imported key (multiple -T options are allowed)`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: scope the imported signing key to codesign and take its passphrase on stdin"
```

### Task 6: Prove the gate on GitHub, end to end

**Files:**
- No file changes. This task produces the evidence that the workflow behaves as intended.

**Interfaces:**
- Consumes: the pushed branch from Tasks 2-5 and the `release` environment from Task 8.
- Produces: a recorded run URL showing a blocked-then-approved publish, and a preflight run showing no approval is needed when `publish=false`.

- [ ] **Step 1: Confirm the environment is actually protected before testing the workflow**

Run:

```bash
gh api repos/lingyired/status-trio/environments/release \
  --jq '[.name, ([.protection_rules[].type] | join(",")), ([.protection_rules[] | select(.type=="required_reviewers") | .reviewers[] | .reviewer.login] | join(","))] | @tsv'
```

Expected: `release<TAB>required_reviewers<TAB>lingyired`. Until this prints `required_reviewers`, the workflow change is not a control and this task must not be marked done.

- [ ] **Step 2: Run the preflight on a trusted branch and confirm it needs no approval**

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref release/hardening \
  -f version=1.3.0 -f build=12 -f publish=false
gh run list --repo lingyired/status-trio --workflow release.yml --limit 1 \
  --json databaseId,status,conclusion,event --jq '.[0]'
gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

Expected: the `validate` job runs, `release` is skipped, and the run concludes `success` without any pending approval. Tests, the DMG build, and artifact upload are exercised exactly as before this plan.

- [ ] **Step 3: Confirm an untrusted branch dispatch is refused**

Push a scratch branch and dispatch it:

```bash
git push origin HEAD:scratch/ref-guard-test
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref scratch/ref-guard-test \
  -f version=1.3.0 -f build=12 -f publish=false
gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

Expected: the run fails in `Enforce trusted refs` with `::error::Refusing to build refs/heads/scratch/ref-guard-test.` Delete the scratch branch afterwards: `git push origin --delete scratch/ref-guard-test`.

- [ ] **Step 4: Confirm a real publish waits for a reviewer**

Run a publishing dispatch from `release/hardening` only when a release is genuinely intended:

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref release/hardening \
  -f version=1.3.0 -f build=12 -f publish=true
gh run list --repo lingyired/status-trio --workflow release.yml --limit 1 \
  --json databaseId,status --jq '.[0]'
```

Expected immediately after dispatch: the run reports `status: waiting` with a pending `release` environment deployment, and no `Build, sign, notarize, and publish` log exists yet. Approve it in **Actions → the run → Review deployments → release → Approve and deploy**, then:

```bash
gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

Expected: the previously blocked job proceeds with `SPARKLE_PRIVATE_KEY` available, and the DMG, Release, and appcast item appear. If the run is dispatched but never approved, it must stay `waiting` indefinitely — that is the control working.

- [ ] **Step 5: Confirm the release body carries the honest trust framing**

```bash
gh release view v1.3.0 --repo lingyired/status-trio --json body --jq .body
```

Expected: the body contains `It cannot protect you if the release itself was published by someone who should not have`, and does not claim notarization.

- [ ] **Step 6: Record the outcome**

Append the run IDs to `docs/swift-ci-compatibility.md` if any run failed at any stage, per the repository's failed-run rule.

### Task 7: Tag protection for `v*` (owner action)

**Files:**
- No repository files. This is a repository-settings change that must be applied through the GitHub API or UI.

**Interfaces:**
- Consumes: repository admin rights on `lingyired/status-trio`.
- Produces: a tag ruleset that blocks tag deletion and force-updates for `v*`.

**This task needs owner action.** Required reviewers and rulesets cannot be expressed in a workflow file; a compromised workflow cannot weaken a control it does not own. That property only holds once the settings exist.

- [ ] **Step 1: Read the existing branch ruleset as the template**

Run:

```bash
gh api repos/lingyired/status-trio/rulesets --jq '.[] | "\(.id) \(.name) \(.target) \(.enforcement)"'
```

Expected: `23279048 Protect main branch active`.

- [ ] **Step 2: Create the tag ruleset**

```bash
gh api --method POST repos/lingyired/status-trio/rulesets --input - <<'JSON'
{
  "name": "Protect release tags",
  "target": "tag",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/tags/v*"], "exclude": [] } },
  "rules": [ { "type": "deletion" }, { "type": "non_fast_forward" } ]
}
JSON
```

Expected: JSON containing `"name":"Protect release tags"` and `"target":"tag"`.

- [ ] **Step 3: Verify the ruleset is active and targets tags**

```bash
gh api repos/lingyired/status-trio/rulesets --jq '.[] | select(.target=="tag") | "\(.name) \(.target) \(.enforcement)"'
```

Expected: `Protect release tags tag active`.

- [ ] **Step 4: Verify a tag cannot be moved**

```bash
git tag v0.0.0-guardtest
git push origin v0.0.0-guardtest
git tag -f v0.0.0-guardtest
git push --force origin v0.0.0-guardtest
git push origin --delete v0.0.0-guardtest
```

Expected: the first push succeeds, the force push is rejected with `remote: error: GH013: Repository rule violations found`, and the delete is rejected the same way. A successful force push or delete means the ruleset is not enforcing and Step 2 must be corrected before relying on it.

- [ ] **Step 5: Note the residual gap in the plan's own record**

A ruleset protects existing tags; it does not stop a compromised maintainer account from creating a new tag that matches `v*`, which is why Task 2's reviewer gate is the control that matters for the Sparkle key and this task is defence in depth for the published feed.

### Task 8: Create the protected `release` environment (owner action)

**Files:**
- No repository files. This is a repository-settings change.

**Interfaces:**
- Consumes: repository admin rights.
- Produces: an environment named `release` with a required reviewer, which Task 2's `release` job references and Task 6 verifies.

**This task needs owner action.** Until it is done, `environment: release` in the workflow matches nothing and adds no gate.

- [ ] **Step 1: Create the environment with a required reviewer**

The reviewer is identified by numeric user id; `lingyired` is `804785` (read from `gh api repos/lingyired/status-trio/collaborators`).

```bash
gh api --method PUT repos/lingyired/status-trio/environments/release --input - <<'JSON'
{
  "wait_timer": 0,
  "prevent_self_review": false,
  "reviewers": [ { "type": "User", "id": 804785 } ],
  "deployment_branch_policy": {
    "protected_branches": false,
    "custom_branch_policies": true
  }
}
JSON
```

Then restrict which branches and tags may deploy into it:

```bash
for policy in "main" "release/*" "v*"; do
  gh api --method POST repos/lingyired/status-trio/environments/release/deployment-branch-policies \
    -f name="$policy" -f type=branch >/dev/null
done
gh api repos/lingyired/status-trio/environments/release/deployment-branch-policies \
  --jq '[.branch_policies[].name] | join(",")'
```

Expected: `main,release/*,v*`. If the tag policy is rejected with `Invalid request`, add it with `-f type=tag` instead; the API distinguishes branch and tag policies and the accepted value must be read from the error text rather than assumed.

- [ ] **Step 2: Confirm the gate**

```bash
gh api repos/lingyired/status-trio/environments/release \
  --jq '[ ([.protection_rules[].type] | join(",")), ([.protection_rules[] | select(.type=="required_reviewers") | .reviewers[] | .reviewer.login] | join(",")) ] | @tsv'
```

Expected: `required_reviewers<TAB>lingyired`.

- [ ] **Step 3: Consider self-review**

`prevent_self_review` is `false` above, which lets the owner approve their own deployment. That is the honest setting for a single-maintainer repository: setting it to `true` makes the environment undrainable because there is no second reviewer. If a second maintainer is added, flip it with `-f prevent_self_review=true` through the same `PUT` and re-run Step 2.

- [ ] **Step 4: Use environment-scoped secrets**

Move the publishing secrets from repository scope to the `release` environment so they are only decrypted for an approved deployment:

```bash
gh secret set SPARKLE_PRIVATE_KEY --repo lingyired/status-trio --env release
gh secret list --repo lingyired/status-trio --env release
gh secret delete SPARKLE_PRIVATE_KEY --repo lingyired/status-trio
gh secret list --repo lingyired/status-trio
```

Expected: the environment listing shows `SPARKLE_PRIVATE_KEY`, and the repository-scoped listing afterwards is empty. Run `gh secret set` without a value so it prompts interactively — never pass the key as an argument, since `argv` is world-readable on some systems and the value would also land in shell history.

### Task 9: Fold the outcome back into the documentation

**Files:**
- Modify: `docs/swift-ci-compatibility.md`

**Interfaces:**
- Consumes: the run IDs from Task 6.
- Produces: a record of the new workflow stages so a future reader can tell which runs used the split workflow.

- [ ] **Step 1: Confirm the document currently has no entry for this change**

Run:

```bash
grep -c "Enforce trusted refs" docs/swift-ci-compatibility.md
```

Expected: `0`.

- [ ] **Step 2: Add the entry**

Append a short section that records, in the same shape as the existing `## 失败记录规则` entries: the preflight run ID from Task 6 Step 2, the blocked-run ID from Task 6 Step 3, and one sentence stating that preflights now run only the `validate` job while publishing additionally requires `release` environment approval.

- [ ] **Step 3: Commit**

```bash
git add docs/swift-ci-compatibility.md
git commit -m "docs: record the split release workflow and its approval gate"
```

## Verification

- `python3 -m venv /tmp/st-wfcheck && /tmp/st-wfcheck/bin/pip install --quiet pyyaml`, then the `yaml.BaseLoader` script from Task 2 Step 3, prints `workflow permissions: {'contents': 'read'}`, `validate: needs=None env_key=None perms={'contents': 'read'}`, `release: needs=validate env_key=release perms={'contents': 'write'}`, and empty `secrets in job env` for both jobs. `yaml.safe_load` must not be used: it resolves `on:` to `True`.
- `grep -c "environment:" .github/workflows/release.yml` returns `1` and `grep -n "SPARKLE_PRIVATE_KEY"` matches only inside the `release` job.
- `grep -n "uses:" .github/workflows/release.yml | grep -v "@[0-9a-f]\{40\}"` prints nothing.
- `grep -c -F -- "-A \" .github/workflows/release.yml` returns `0` and `grep -c -F -- "-T /usr/bin/codesign"` returns `1`.
- The stdin-passphrase probe from Task 5 Step 2 exits `0` with the correct passphrase and `1` with a wrong one.
- `bash scripts/validate-appcast-notes.sh` passes.
- `gh workflow run release.yml --repo lingyired/status-trio --ref release/hardening -f version=1.3.0 -f build=12 -f publish=false` followed by `gh run watch <run-id> --repo lingyired/status-trio --exit-status` exits 0 with `release` skipped, and `swift test` passing inside `validate`.
- `gh api repos/lingyired/status-trio/environments/release --jq '[.protection_rules[].type] | join(",")'` contains `required_reviewers`, and a `publish=true` dispatch visibly waits for approval before `Build, sign, notarize, and publish` starts.
- `gh api repos/lingyired/status-trio/rulesets --jq '.[] | select(.target=="tag") | .name'` prints `Protect release tags`, and a forced tag move is rejected by the remote.

## Out of Scope

- `scripts/release.sh`, including its Sparkle key handling at lines 152 and 199. That file is owned by a sibling plan.
- `scripts/build-app.sh` and `scripts/verify-platform-version.sh` signing and SDK behaviour; owned by the build/signing plan.
- The `xattr -dr com.apple.quarantine` text in `README.md:157` and `AGENTS.md:67`. This plan only makes the release body's framing consistent (Task 2 Steps 2 and 5); the installer documentation is owned by the build/signing plan.
- Adding a Developer ID certificate or notarization secrets. The workflow keeps both paths conditional and the Ad-hoc path is what actually runs.
- Rotating `SPARKLE_PRIVATE_KEY`. Rotation invalidates the trust root for every installed copy and needs its own decision.
- Converting `RELEASE_REPO`/`RELEASE_BRANCH` from repository variables to anything else; both are unset today and `scripts/release.sh:30-31` already falls back to `release.json`.

## File Ownership & Conflicts

- `.github/workflows/release.yml` is owned exclusively by this plan. No sibling plan may edit it.
- `docs/swift-ci-compatibility.md` is edited by Task 9 and may also be edited by the CI-gate plan when its first runs fail. Land those edits in separate commits and expect a trivial conflict; whichever lands second appends its own section.
- `README.md` and `AGENTS.md` are **not** touched here. The build/signing plan owns their quarantine guidance. If that plan rewrites `AGENTS.md:67`, the release-body text added by Task 2 Step 2 stays as written here; the two are not required to match word for word, only to agree that the checksum is a transit check.
- A new `.github/workflows/ci.yml` is owned by the CI-gate plan. It must not declare `contents: write`, must not reference the `release` environment, and must not call `scripts/release.sh`; the release workflow stays the only acceptance path.
- `release-notes/<version>/` files are untouched by this plan.
