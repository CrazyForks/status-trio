#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioSparkleContract.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/lipo" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${MOCK_ARCHS:?}"
SH
chmod +x "$WORK/lipo"

cat > "$WORK/vtool" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cat <<INFO
${MOCK_ARCH:?}:
    cmd LC_BUILD_VERSION
  cmdsize 32
  platform MACOS
    minos ${MOCK_MINOS:?}
      sdk 26.0
INFO
SH
chmod +x "$WORK/vtool"

make_app() {
    local name="$1"
    mkdir -p "$WORK/$name/Contents/Frameworks/Sparkle.framework/Versions/B"
    printf '\xcf\xfa\xed\xfe' > "$WORK/$name/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
}

run_check() {
    local name="$1"
    shift
    PATH="$WORK:$PATH" "$@" bash "$ROOT/scripts/test-macos13-sparkle-metadata.sh" "$WORK/$name"
}

make_app valid
MOCK_ARCHS="arm64 x86_64" MOCK_ARCH=arm64 MOCK_MINOS=13.0 run_check valid >/dev/null

make_app too-new
if MOCK_ARCHS="arm64 x86_64" MOCK_ARCH=arm64 MOCK_MINOS=13.1 run_check too-new >/dev/null 2>&1; then
    echo "Sparkle minimum 13.1 was accepted" >&2
    exit 1
fi

make_app missing-slice
if MOCK_ARCHS="arm64" MOCK_ARCH=arm64 MOCK_MINOS=13.0 run_check missing-slice >/dev/null 2>&1; then
    echo "arm64-only Sparkle binary was accepted" >&2
    exit 1
fi

# The release script must verify the built bundle before it creates a DMG or
# calls any publishing command.
python3 - "$ROOT/scripts/release.sh" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text()
verify = source.index('scripts/verify-platform-version.sh')
publish = source.index('gh release create')
assert verify < publish, "release metadata verification must precede gh release create"
PY

echo "macOS 13 Sparkle metadata contract passed"
