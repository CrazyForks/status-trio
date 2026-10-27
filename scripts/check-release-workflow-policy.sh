#!/usr/bin/env bash
# Fails closed when release-only CI regresses or publication gains build powers.
set -euo pipefail

ROOT="${STATUS_TRIO_RELEASE_POLICY_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
WORKFLOW="$ROOT/.github/workflows/release.yml"
PUBLISH_SCRIPT="$ROOT/scripts/publish-release.sh"

fail() {
    echo "release workflow policy check failed: $*" >&2
    exit 1
}

require_text() {
    local path="$1"
    local text="$2"
    grep -Fq -- "$text" "$path" || fail "$path must contain: $text"
}

forbid_text() {
    local path="$1"
    local text="$2"
    if grep -Fq -- "$text" "$path"; then
        fail "$path must not contain: $text"
    fi
}

[[ -f "$WORKFLOW" ]] || fail "release workflow is missing"
[[ -f "$PUBLISH_SCRIPT" ]] || fail "publish script is missing"

require_text "$WORKFLOW" "workflow_dispatch:"
require_text "$WORKFLOW" "candidate_sha:"
require_text "$WORKFLOW" "^[0-9a-f]{40}$"
require_text "$WORKFLOW" 'refs/heads/main'
require_text "$WORKFLOW" "ref: \${{ inputs.candidate_sha }}"
require_text "$WORKFLOW" "group: status-trio-release-publish"
require_text "$WORKFLOW" "  verify:"
require_text "$WORKFLOW" "  package:"
require_text "$WORKFLOW" "  publish:"
require_text "$WORKFLOW" "needs: verify"
require_text "$WORKFLOW" "needs: [verify, package]"
require_text "$WORKFLOW" "name: status-trio-release-package"
require_text "$WORKFLOW" "bash scripts/package-release.sh"
require_text "$WORKFLOW" "bash scripts/publish-release.sh"
require_text "$WORKFLOW" "RESOLVED_RELEASE_REPO: \${{ vars.RELEASE_REPO || 'lingyired/status-trio' }}"
require_text "$WORKFLOW" "RESOLVED_RELEASE_BRANCH: \${{ vars.RELEASE_BRANCH || 'main' }}"
require_text "$WORKFLOW" "NOTES_MODE=publish"
require_text "$WORKFLOW" "NOTES_MODE=package"
require_text "$WORKFLOW" "RELEASE_REPO: \${{ env.RESOLVED_RELEASE_REPO }}"
require_text "$WORKFLOW" "RELEASE_BRANCH: \${{ env.RESOLVED_RELEASE_BRANCH }}"
require_text "$WORKFLOW" "bash scripts/test.sh"
require_text "$WORKFLOW" "needs.verify.outputs.candidate_sha"
require_text "$WORKFLOW" "needs.verify.outputs.version"
require_text "$WORKFLOW" "needs.verify.outputs.build"
require_text "$WORKFLOW" "needs.verify.outputs.tag"
require_text "$WORKFLOW" "xcode-27"
require_text "$WORKFLOW" "/Applications/Xcode_27.app/Contents/Developer"
require_text "$WORKFLOW" "xcrun --sdk macosx --show-sdk-version"
if [[ "$(grep -c 'runs-on: xcode-27' "$WORKFLOW")" -ne 3 ]]; then
    fail "verify, package, and publish must all run on xcode-27"
fi
if grep -Eq '^    runs-on: (macos-|ubuntu-|windows-)' "$WORKFLOW"; then
    fail "release jobs must not fall back to a generic runner"
fi

for forbidden in \
    "push:" \
    "github.ref_name" \
    "github.event_name == 'push'" \
    "scripts/prepare-release-body.sh" \
    "gh release create --target" \
    "bash scripts/build-app.sh" \
    "hdiutil create" \
    "notarytool submit"; do
    forbid_text "$WORKFLOW" "$forbidden"
done

if ! grep -Eq '^      candidate_sha:$' "$WORKFLOW"; then
    fail "workflow must declare a candidate_sha input"
fi

for forbidden in \
    "swift build" \
    "bash scripts/build-app.sh" \
    "hdiutil create" \
    "notarytool submit" \
    "codesign --force" \
    "SKIP_SOURCE_SHA_CHECK" \
    "TEST_SPARKLE_METADATA"; do
    forbid_text "$PUBLISH_SCRIPT" "$forbidden"
done

for production_script in "$ROOT/scripts/package-release.sh" "$ROOT/scripts/release.sh"; do
    for forbidden in \
        "SKIP_SOURCE_SHA_CHECK" \
        "TEST_SPARKLE_METADATA" \
        "BUILD_APP=" \
        "VERIFY_PLATFORM="; do
        forbid_text "$production_script" "$forbidden"
    done
done

job_block() {
    local name="$1"
    awk -v name="$name" '
        BEGIN { in_job = 0; in_fence = 0 }
        /^  [A-Za-z0-9_-]+:$/ {
            in_job = ($0 == "  " name ":")
        }
        in_job { print }
    ' "$WORKFLOW"
}

VERIFY_BLOCK="$(job_block verify)"
PACKAGE_BLOCK="$(job_block package)"
PUBLISH_BLOCK="$(job_block publish)"

[[ -n "$VERIFY_BLOCK" ]] || fail "verify job is missing"
[[ -n "$PACKAGE_BLOCK" ]] || fail "package job is missing"
[[ -n "$PUBLISH_BLOCK" ]] || fail "publish job is missing"
if printf '%s\n' "$VERIFY_BLOCK" | grep -Eq '^[[:space:]]+swift test([[:space:]]|$)'; then
    fail "verify job must run scripts/test.sh so forbidden-pattern checks cannot be bypassed"
fi
for required_check in \
    "scripts/test-mobile-battery-source-cache.sh" \
    "scripts/test-mobile-battery-clang-version.sh" \
    "scripts/test-verify-local.sh" \
    "scripts/test-verify-local-bundle.sh" \
    "scripts/test-workflow-policy.sh"; do
    printf '%s\n' "$VERIFY_BLOCK" | grep -Fq "bash $required_check" ||
        fail "verify job must run $required_check"
done
printf '%s\n' "$PACKAGE_BLOCK" | grep -Fq '      name: distribution' ||
    fail "package job must use the protected distribution environment"
printf '%s\n' "$PUBLISH_BLOCK" | grep -Fq '      name: distribution' ||
    fail "publish job must use the protected distribution environment"
printf '%s\n' "$VERIFY_BLOCK" | grep -Fq 'bash scripts/test-release-notarization.sh' ||
    fail "verify job must run the offline release notarization regressions"

printf '%s\n' "$VERIFY_BLOCK" | grep -Fxq '    outputs:' ||
    fail "verify job must declare workflow outputs"
printf '%s\n' "$VERIFY_BLOCK" | grep -A6 -Fx '    outputs:' |
    grep -Fq 'candidate_sha: ${{ steps.release.outputs.candidate_sha }}' ||
    fail "verify job must expose candidate_sha output"
printf '%s\n' "$VERIFY_BLOCK" | grep -A6 '^    outputs:$' |
    grep -Fq 'version: ${{ steps.release.outputs.version }}' ||
    fail "verify job must expose version output"
printf '%s\n' "$VERIFY_BLOCK" | grep -A6 '^    outputs:$' |
    grep -Fq 'build: ${{ steps.release.outputs.build }}' ||
    fail "verify job must expose build output"
printf '%s\n' "$VERIFY_BLOCK" | grep -A6 '^    outputs:$' |
    grep -Fq 'tag: ${{ steps.release.outputs.tag }}' ||
    fail "verify job must expose tag output"

if printf '%s\n' "$VERIFY_BLOCK" | grep -Fq 'secrets.'; then
    fail "verify job must not receive secrets"
fi
if sed -n '/^permissions:$/,/^[^ ]/p' "$WORKFLOW" | grep -Fq 'contents: write'; then
    fail "workflow-level permissions must be read-only"
fi
if printf '%s\n' "$PACKAGE_BLOCK" | grep -Fq 'secrets.GITHUB_TOKEN'; then
    fail "package job must not publish with a GitHub write token"
fi
if printf '%s\n' "$PUBLISH_BLOCK" | grep -Eq 'SPARKLE_PRIVATE_KEY|DEVELOPER_ID_CERTIFICATE|APPSTORE_CONNECT'; then
    fail "publish job must not receive build/signing/notarization secrets"
fi
if printf '%s\n' "$PUBLISH_BLOCK" | grep -Eq 'swift build|build-app\.sh|hdiutil create|notarytool submit|codesign'; then
    fail "publish job must not rebuild, repackage, sign, or notarize"
fi
if printf '%s\n' "$PUBLISH_BLOCK" | grep -Eq 'gh release (create|upload|edit)|update-appcast\.rb'; then
    fail "publish job must delegate publication to scripts/publish-release.sh"
fi

# Inspect actual steps as well as text so reordering or a conditional cannot
# leave a required command present but ineffective.
ruby -ryaml - "$WORKFLOW" <<'RUBY'
workflow = YAML.load_file(ARGV.fetch(0))
verify = workflow.fetch("jobs").fetch("verify").fetch("steps")
candidate_step = verify.find { |s| s["name"] == "Validate frozen candidate and resolve release" }
abort "release policy: frozen candidate validation must enforce main dispatch" unless
  candidate_step && candidate_step.fetch("run").include?(%q{if [[ "${GITHUB_REF}" != "refs/heads/main" ]]; then})
names = verify.map { |step| step["name"] }
preflight = names.index("Run static release preflight")
tests = names.index("Run tests")
native = names.index("Run native and release-contract tests")
abort "release policy: static preflight must precede tests and native contracts" unless
  preflight && tests && native && preflight < tests && tests < native
abort "release policy: test execution must preserve diagnostics and original exit code" unless
  verify[tests].fetch("run").strip == %q{bash "$CI_TOOLS_ROOT/scripts/ci-run-stage.sh" tests bash scripts/test.sh}
["Summarize verify diagnostics", "Upload verify diagnostics"].each do |name|
  step = verify.find { |item| item["name"] == name }
  abort "release policy: #{name} must run after failure" unless step && step["if"] == "always()"
end
["verify", "package"].each do |job|
  abort "release policy: #{job} may not suppress failures" if
    workflow.fetch("jobs").fetch(job).fetch("steps").any? { |step| step["continue-on-error"] }
end
package = workflow.fetch("jobs").fetch("package").fetch("steps")
build_index = package.index { |s| s["name"] == "Build, sign, notarize, and package once" }
validation = package.index { |s| s["name"] == "Validate native dependency caches before saving" }
abort "release policy: native cache save must follow successful package validation" unless
  build_index && validation && build_index < validation && !package[validation].key?("if")
%w[arm64 x86_64].each do |arch|
  %w[restore save].each do |operation|
    step = package.find { |s| s["uses"] == "actions/cache/#{operation}@v4" &&
      s.fetch("with", {})["key"] == "${{ steps.native-cache-keys.outputs.key_#{arch} }}" }
    abort "release policy: missing exact #{arch} cache #{operation}" unless step
    settings = step.fetch("with")
    expected = [".build/mobile-battery/#{arch}/prefix", ".build/mobile-battery/#{arch}/.dependencies-cache.json"]
    abort "release policy: cache may contain only one native prefix and its inventory" unless
      settings.fetch("path").lines.map(&:strip).reject(&:empty?) == expected
    abort "release policy: native release caches may not use fallback keys" if settings.key?("restore-keys")
    condition = "github.ref == 'refs/heads/main'"
    condition += " && steps.native-cache-#{arch}.outputs.cache-hit != 'true'" if operation == "save"
    abort "release policy: native cache writes/restores must be trusted main only" unless step["if"] == condition
    abort "release policy: native cache save precedes validation" if
      operation == "save" && package.index(step) <= validation
    abort "release policy: native cache restore must precede package build" if
      operation == "restore" && package.index(step) >= build_index
  end
end
abort "release policy: unexpected cache action in release jobs" unless
  package.count { |s| s.fetch("uses", "").start_with?("actions/cache") } == 4 &&
  workflow.fetch("jobs").reject { |name, _| name == "package" }.values.all? { |j|
    j.fetch("steps").none? { |s| s.fetch("uses", "").start_with?("actions/cache") }
  }
RUBY

echo "release workflow policy check passed"
