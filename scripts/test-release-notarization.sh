#!/usr/bin/env bash
# Exercises release orchestration with fake external tools; never changes a keychain.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
export TEST_ROOT
ruby -ryaml -rjson -e '
  workflow = YAML.load_file(ARGV[0])
  input = (workflow["on"] || workflow.fetch(true)).fetch("workflow_dispatch").fetch("inputs").fetch("notarize")
  abort "notarize must be boolean, default false" unless input["type"] == "boolean" && input["default"] == false
  job = workflow.fetch("jobs").fetch("release")
  abort "NOTARIZE must be wired from dispatch" unless job.fetch("env").fetch("NOTARIZE").include?("inputs.notarize")
  steps = job.fetch("steps")
  ["Validate notarization test mode", "Configure Developer ID signing", "Configure Apple notarization"].each do |name|
    step = steps.find { |candidate| candidate["name"] == name }
    File.write(File.join(ENV.fetch("TEST_ROOT"), name + ".sh"), step ? step.fetch("run") : "")
  end
' "$ROOT/.github/workflows/release.yml"

# Evaluate real workflow gate bodies, stopping before any actual credential setup.
for step in 'Configure Developer ID signing' 'Configure Apple notarization'; do
    if env PUBLISH=false NOTARIZE=true DEVELOPER_ID_CERTIFICATE_P12='' CERTIFICATE_PASSWORD='' \
        NOTARY_API_PRIVATE_KEY='' NOTARY_API_KEY_ID='' NOTARY_API_ISSUER_ID='' \
        /bin/bash "$TEST_ROOT/$step.sh" > "$TEST_ROOT/gate.log" 2>&1; then
        echo "FAIL: explicitly requested notarization accepted missing secrets: $step" >&2
        exit 1
    fi
    env PUBLISH=false NOTARIZE=false DEVELOPER_ID_CERTIFICATE_P12='' CERTIFICATE_PASSWORD='' \
        NOTARY_API_PRIVATE_KEY='' NOTARY_API_KEY_ID='' NOTARY_API_ISSUER_ID='' \
        /bin/bash "$TEST_ROOT/$step.sh" > "$TEST_ROOT/gate.log" 2>&1
    env PUBLISH=true NOTARIZE=false DEVELOPER_ID_CERTIFICATE_P12='' CERTIFICATE_PASSWORD='' \
        NOTARY_API_PRIVATE_KEY='' NOTARY_API_KEY_ID='' NOTARY_API_ISSUER_ID='' \
        /bin/bash "$TEST_ROOT/$step.sh" > "$TEST_ROOT/gate.log" 2>&1
 done

mkdir -p "$TEST_ROOT/repo/scripts" "$TEST_ROOT/repo/release-notes/1.0" "$TEST_ROOT/bin"
# Redirect absolute tool names only in the disposable test copy.
sed -e 's@/usr/bin/codesign@codesign@g' -e 's@/usr/bin/xcrun@xcrun@g' \
    "$ROOT/scripts/release.sh" > "$TEST_ROOT/repo/scripts/release.sh"
cat > "$TEST_ROOT/repo/release.json" <<'JSON'
{"app_name":"Fixture","bundle_id":"test.fixture","github_repo":"test/fixture","git_branch":"main","min_system_version":"15.0","appcast_file":"appcast.xml","dmg_name":"Fixture.dmg"}
JSON
printf '<rss/>' > "$TEST_ROOT/repo/appcast.xml"
cat > "$TEST_ROOT/repo/scripts/build-app.sh" <<'BUILD'
#!/usr/bin/env bash
set -euo pipefail
printf 'build\n' >> "$TRACE"
mkdir -p dist/StatusTrio.app/Contents
printf fixture > dist/StatusTrio.app/Contents/fixture
BUILD
cat > "$TEST_ROOT/bin/tool" <<'TOOL'
#!/usr/bin/env bash
set -euo pipefail
name="$(basename "$0")"
printf '%s' "$name" >> "$TRACE"
printf ' <%s>' "$@" >> "$TRACE"
printf '\n' >> "$TRACE"
case "$name" in
    hdiutil) touch "${!#}" ;;
    ditto)
        if [[ "$1" != '-c' ]]; then cp -R "$1" "$2"; else touch "${!#}"; fi ;;
    xcrun)
        if [[ "$1 $2" == 'notarytool submit' ]]; then
            printf '{"status":"%s"}\n' "${NOTARY_STATUS:-Accepted}"
        fi ;;
    gh) echo 'FAIL: publishing tool reached in no-publish run' >&2; exit 99 ;;
esac
TOOL
chmod +x "$TEST_ROOT/bin/tool"
for command in swift hdiutil ditto codesign xcrun spctl plutil xmllint gh sign_update shasum; do
    ln -s tool "$TEST_ROOT/bin/$command"
done
ln -s /bin/bash "$TEST_ROOT/bin/bash"

if env PUBLISH=true NOTARIZE=true /bin/bash "$TEST_ROOT/Validate notarization test mode.sh" > "$TEST_ROOT/gate.log" 2>&1; then
    echo 'FAIL: workflow allowed notarize=true with publish=true' >&2
    exit 1
fi
grep -q 'notarize=true requires publish=false' "$TEST_ROOT/gate.log" || {
    echo 'FAIL: workflow did not reject notarize=true before credential setup' >&2
    cat "$TEST_ROOT/gate.log" >&2
    exit 1
}

if env PUBLISH=false NOTARIZE=true DEVELOPER_ID_CERTIFICATE_P12='fixture' CERTIFICATE_PASSWORD='' \
    /bin/bash "$TEST_ROOT/Configure Developer ID signing.sh" > "$TEST_ROOT/gate.log" 2>&1; then
    echo 'FAIL: notarization accepted a missing Developer ID certificate password' >&2
    exit 1
fi

for missing in key-id issuer-id; do
    :
    if [[ "$missing" == key-id ]]; then
        key_id=''
        issuer_id='fixture-issuer'
    else
        key_id='fixture-key'
        issuer_id=''
    fi
    if env PUBLISH=false NOTARIZE=true NOTARY_API_PRIVATE_KEY='fixture' \
        NOTARY_API_KEY_ID="$key_id" NOTARY_API_ISSUER_ID="$issuer_id" KEYCHAIN_PATH='' \
        RUNNER_TEMP="$TEST_ROOT" GITHUB_ENV="$TEST_ROOT/github-env" \
        /bin/bash "$TEST_ROOT/Configure Apple notarization.sh" > "$TEST_ROOT/gate.log" 2>&1; then
        echo "FAIL: notarization accepted missing App Store Connect $missing" >&2
        exit 1
    fi
done
export PATH="$TEST_ROOT/bin:$PATH" TRACE="$TEST_ROOT/trace"

: > "$TRACE"
env PUBLISH=false NOTARIZE=true NOTARY_API_PRIVATE_KEY='fixture-private-key' \
    NOTARY_API_KEY_ID='fixture-key' NOTARY_API_ISSUER_ID='fixture-issuer' \
    KEYCHAIN_PATH="$TEST_ROOT/keychain with spaces" RUNNER_TEMP="$TEST_ROOT" \
    GITHUB_ENV="$TEST_ROOT/github-env" /bin/bash "$TEST_ROOT/Configure Apple notarization.sh" \
    > "$TEST_ROOT/notary-setup.log" 2>&1
grep -Fq "xcrun <notarytool> <store-credentials> <status-trio-notary> <--key> <$TEST_ROOT/AuthKey_fixture-key.p8> <--key-id> <fixture-key> <--issuer> <fixture-issuer> <--keychain> <$TEST_ROOT/keychain with spaces>" "$TRACE" || {
    echo 'FAIL: notary credentials did not retain the keychain path as one argument' >&2
    cat "$TRACE" >&2
    exit 1
}
if [[ -e "$TEST_ROOT/AuthKey_fixture-key.p8" ]]; then
    echo 'FAIL: temporary App Store Connect private key was not removed' >&2
    exit 1
fi

: > "$TRACE"
if ! env PUBLISH=false NOTARIZE=true NOTARY_API_PRIVATE_KEY='fixture-private-key' \
    NOTARY_API_KEY_ID='fixture-key' NOTARY_API_ISSUER_ID='fixture-issuer' \
    KEYCHAIN_PATH='' RUNNER_TEMP="$TEST_ROOT" GITHUB_ENV="$TEST_ROOT/github-env" \
    /bin/bash "$TEST_ROOT/Configure Apple notarization.sh" > "$TEST_ROOT/notary-setup.log" 2>&1; then
    echo 'FAIL: Bash 3.2 workflow setup failed with an empty keychain path' >&2
    cat "$TEST_ROOT/notary-setup.log" >&2
    exit 1
fi
if grep -q '<--keychain>' "$TRACE"; then
    echo 'FAIL: empty keychain path produced a --keychain argument' >&2
    cat "$TRACE" >&2
    exit 1
fi

run_release() {
    env VERSION=1.0 BUILD=99 PUBLISH=false UNIVERSAL_BUILD=1 OUTPUT_DIR="$TEST_ROOT/output" \
        SIGN_UPDATE="$TEST_ROOT/bin/sign_update" SPARKLE_PRIVATE_KEY='' \
        /bin/bash "$TEST_ROOT/repo/scripts/release.sh"
}
if env VERSION=1.0 BUILD=99 PUBLISH=true NOTARIZE=true UNIVERSAL_BUILD=1 OUTPUT_DIR="$TEST_ROOT/output" \
    SIGN_UPDATE="$TEST_ROOT/bin/sign_update" SPARKLE_PRIVATE_KEY='' \
    CODE_SIGN_IDENTITY='Developer ID Application: Fixture' NOTARY_PROFILE=fixture \
    /bin/bash "$TEST_ROOT/repo/scripts/release.sh" > "$TEST_ROOT/release.log" 2>&1; then
    echo 'FAIL: notarized test mode allowed publishing' >&2
    exit 1
fi
grep -q 'NOTARIZE=true requires PUBLISH=false' "$TEST_ROOT/release.log" || {
    echo 'FAIL: release script did not reject notarized publishing before external actions' >&2
    cat "$TEST_ROOT/release.log" >&2
    exit 1
}
if grep -q '^build' "$TRACE"; then
    echo 'FAIL: notarized publish request reached build' >&2
    exit 1
fi

for bad in missing-profile missing-identity; do
    : > "$TRACE"
    if [[ "$bad" == missing-profile ]]; then
        export NOTARIZE=true NOTARY_PROFILE='' CODE_SIGN_IDENTITY='Developer ID Application: Fixture' KEYCHAIN_PATH=test-keychain
    else
        export NOTARIZE=true NOTARY_PROFILE=fixture CODE_SIGN_IDENTITY='-' KEYCHAIN_PATH=test-keychain
    fi
    if run_release > "$TEST_ROOT/release.log" 2>&1; then
        echo "FAIL: requested notarization accepted $bad" >&2; exit 1
    fi
    if grep -q '^build' "$TRACE"; then echo 'FAIL: invalid request reached build' >&2; exit 1; fi
done
export NOTARIZE=true NOTARY_PROFILE=fixture CODE_SIGN_IDENTITY='Developer ID Application: Fixture' KEYCHAIN_PATH=test-keychain
: > "$TRACE"
run_release > "$TEST_ROOT/release.log" 2>&1
ruby -e '
  lines = File.readlines(ARGV[0])
  def locate(lines, *parts)
    lines.index { |line| parts.all? { |part| line.include?(part) } } || abort("missing operation #{parts.inspect}")
  end
  operations = [
    ["ditto", "<-c>"], ["xcrun", "<submit>", ".zip>"],
    ["xcrun", "<staple>", ".app>"], ["xcrun", "<validate>", ".app>"],
    ["hdiutil", "<create>"], ["codesign", "<--sign>", ".dmg>", "<--timestamp>", "<--keychain>", "<test-keychain>"],
    ["codesign", "<--verify>", ".dmg>"], ["xcrun", "<submit>", ".dmg>"],
    ["xcrun", "<staple>", ".dmg>"], ["xcrun", "<validate>", ".dmg>"],
    ["spctl", "<--type>", "<open>", "<context:primary-signature>"],
    ["spctl", "<--type>", "<execute>"], ["shasum", "<-a>", "<256>", ".dmg>"]
  ].map { |parts| locate(lines, *parts) }
  abort "incorrect sign/notary/staple order" unless operations == operations.sort && operations.uniq.length == operations.length
  abort "unexpected duplicate submissions" unless lines.count { |line| line.include?("<submit>") } == 2
  abort "publishing reached" if lines.any? { |line| line.start_with?("gh ") }
' "$TRACE"

: > "$TRACE"
export KEYCHAIN_PATH=''
if ! run_release > "$TEST_ROOT/release.log" 2>&1; then
    echo 'FAIL: Bash 3.2 release notarization failed with an empty keychain path' >&2
    cat "$TEST_ROOT/release.log" >&2
    exit 1
fi
ruby -e '
  lines = File.readlines(ARGV[0])
  submits = lines.select { |line| line.start_with?("xcrun ") && line.include?("<notarytool> <submit>") }
  abort "expected app and DMG notarization submissions" unless submits.length == 2
  abort "empty keychain path was passed to notarytool" if submits.any? { |line| line.include?("<--keychain>") }
  abort "empty keychain path was passed to codesign" if lines.any? { |line| line.start_with?("codesign ") && line.include?("<--keychain>") }
' "$TRACE"

# Rejected submissions must stop before an artifact is advertised as successful.
: > "$TRACE"
if NOTARY_STATUS=Invalid run_release > "$TEST_ROOT/rejected.log" 2>&1; then
    echo 'FAIL: rejected notarization succeeded' >&2; exit 1
fi
: > "$TRACE"
NOTARIZE=false NOTARY_PROFILE='' CODE_SIGN_IDENTITY='-' run_release > "$TEST_ROOT/release.log" 2>&1
if grep -Eq '^(xcrun <notarytool>|codesign |spctl |gh )' "$TRACE"; then
    echo 'FAIL: fast preflight reached notarization/signing/publishing' >&2; cat "$TRACE" >&2; exit 1
fi
# No-publish return must precede every publishing action and appcast generation.
ruby -e '
  source = File.read(ARGV[0])
  gate = source.index(%q{if [[ "$PUBLISH" == "false" ]]; then}) or abort "missing no-publish gate"
  stop = source.index("exit 0", gate) or abort "missing no-publish return"
  ["gh release view", "gh release create", "update-appcast.rb"].each do |action|
    abort "publish action precedes return: #{action}" unless source.index(action) > stop
  end
' "$ROOT/scripts/release.sh"
echo 'release notarization gates, artifact ordering, rejection and no-publish regressions passed'
