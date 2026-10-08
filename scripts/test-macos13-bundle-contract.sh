#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioBundleContract.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() {
    echo "bundle contract failed: $*" >&2
    exit 1
}

expect_rejected() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        fail "$label was accepted"
    fi
}

cat > "$WORK/lipo" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${MOCK_ARCHS:?}" in
    missing-x86_64) echo "arm64" ;;
    *) echo "${MOCK_ARCHS}" ;;
esac
SH
chmod +x "$WORK/lipo"

cat > "$WORK/vtool" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cat <<INFO
${MOCK_ARCH:?}:
    cmd LC_BUILD_VERSION
  cmdsize 32
  platform macos
     minos ${MOCK_MINOS:?}
       sdk ${MOCK_SDK:-26.0}
INFO
SH
chmod +x "$WORK/vtool"

cat > "$WORK/otool" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
    -arch)
        shift
        arch="$1"
        shift
        binary="${2:?}"
        ;;
    -l)
        binary="${2:?}"
        ;;
    -L)
        binary="${2:?}"
        ;;
    *)
        exec /usr/bin/otool "$@"
        ;;
esac
if [[ "$1" == "-l" ]]; then
    cat <<INFO
${binary}:
      cmd LC_RPATH
  cmdsize 48
     path ${MOCK_RPATH:-@executable_path/../Frameworks/MobileBattery} (offset 12)
INFO
elif [[ "$1" == "-L" ]]; then
    cat <<INFO
${binary}:
	@rpath/libimobiledevice-1.0.6.dylib (compatibility version 7.0.0, current version 7.0.0)
INFO
else
    exec /usr/bin/otool "$@"
fi
SH
chmod +x "$WORK/otool"

cat > "$WORK/codesign" <<'SH'
#!/usr/bin/env bash
exit "${MOCK_CODESIGN_STATUS:-0}"
SH
chmod +x "$WORK/codesign"

make_app() {
    local name="$1"
    mkdir -p "$WORK/$name/Contents/Helpers" "$WORK/$name/Contents/Frameworks/MobileBattery"
    cat > "$WORK/$name/Contents/Helpers/StatusTrioMobileBatteryHelper" <<'HELPER'
#!/bin/sh
cat <<'JSON'
{"schemaVersion":1,"phones":[]}
JSON
HELPER
    chmod +x "$WORK/$name/Contents/Helpers/StatusTrioMobileBatteryHelper"
    printf "#!/bin/sh\nexit 0\n" > "$WORK/$name/Contents/Frameworks/MobileBattery/libimobiledevice-1.0.6.dylib"
}

# Missing x86_64 must be rejected for a Universal build.
make_app missing-x86_64
set +e
PATH="$WORK:$PATH" MOCK_ARCHS=arm64 MOCK_ARCH=arm64 MOCK_MINOS=13.0     UNIVERSAL_BUILD=1 bash "$ROOT/scripts/verify-mobile-battery-bundle.sh" "$WORK/missing-x86_64" >/dev/null 2>&1
rc=$?
set -e
[[ $rc -ne 0 ]] || fail "helper missing x86_64 was accepted"

# minos 15.0 must be rejected after the deployment target moved to 13.0.
make_app old-minos
set +e
PATH="$WORK:$PATH" MOCK_ARCHS="arm64 x86_64" MOCK_ARCH=x86_64 MOCK_MINOS=15.0     bash "$ROOT/scripts/verify-mobile-battery-bundle.sh" "$WORK/old-minos" >/dev/null 2>&1
rc=$?
set -e
[[ $rc -ne 0 ]] || fail "minos 15.0 helper was accepted"

# An unbundled Homebrew dependency must be rejected by the existing checker.
set +e
bash "$ROOT/scripts/check-mobile-battery-dependency.sh" "/opt/homebrew/lib/libplist.dylib"     "$WORK/old-minos/Contents/Frameworks/MobileBattery" >/dev/null 2>&1
rc=$?
set -e
[[ $rc -ne 0 ]] || fail "absolute Homebrew dependency was accepted"

# A development RPATH must be rejected by the existing checker.
set +e
bash "$ROOT/scripts/check-mobile-battery-rpath.sh" "$ROOT/.build/mobile-battery/arm64/prefix/lib"     "$WORK/old-minos/Contents/Frameworks/MobileBattery" >/dev/null 2>&1
rc=$?
set -e
[[ $rc -ne 0 ]] || fail "development RPATH was accepted"

# A failing signature verification must be rejected.
make_app bad-signature
set +e
PATH="$WORK:$PATH" MOCK_ARCHS="arm64 x86_64" MOCK_ARCH=x86_64 MOCK_MINOS=13.0     MOCK_CODESIGN_STATUS=1 bash "$ROOT/scripts/verify-mobile-battery-bundle.sh" "$WORK/bad-signature" >/dev/null 2>&1
rc=$?
set -e
[[ $rc -ne 0 ]] || fail "bad signature was accepted"

# Positive control: the mocked verifier accepts the expected shape.
make_app valid
PATH="$WORK:$PATH" MOCK_ARCHS="arm64 x86_64" MOCK_ARCH=x86_64 MOCK_MINOS=13.0     MOCK_CODESIGN_STATUS=0 bash "$ROOT/scripts/verify-mobile-battery-bundle.sh" "$WORK/valid" >/dev/null

echo "macOS 13 bundle-contract regressions passed"
