#!/usr/bin/env bash
# Guards the LC_BUILD_VERSION metadata that macOS reads when deciding whether an
# app adopts the current design language.
#
# AppKit keys that decision off the `sdk` field, not `minos`. SwiftPM's build
# system can record the deployment target in that field instead of the real SDK
# version, which silently keeps the pre-Tahoe appearance for the menu bar
# popover. See docs/swift-ci-compatibility.md and issue #40.
#
# Usage: verify-platform-version.sh <binary> <expected-minos> [minimum-sdk-major]
# Exit codes: 0 = every architecture satisfies the expectations,
#             1 = at least one architecture does not,
#             2 = the arguments or the binary are unusable.

set -euo pipefail

BINARY="${1:-}"
EXPECTED_MINOS="${2:-}"
MINIMUM_SDK_MAJOR="${3:-26}"

if [[ -z "$BINARY" || -z "$EXPECTED_MINOS" ]]; then
    echo "Usage: $0 <binary> <expected-minos> [minimum-sdk-major]" >&2
    exit 2
fi

if [[ ! -f "$BINARY" ]]; then
    echo "Error: no such file: $BINARY" >&2
    exit 2
fi

ARCHS="$(lipo -archs "$BINARY" 2>/dev/null || true)"
if [[ -z "$ARCHS" ]]; then
    ARCHS="unknown"
fi

FAILED=0
for arch in $ARCHS; do
    if [[ "$arch" == "unknown" ]]; then
        BUILD_INFO="$(vtool -show-build "$BINARY" 2>/dev/null || true)"
    else
        BUILD_INFO="$(vtool -show-build -arch "$arch" "$BINARY" 2>/dev/null || true)"
    fi

    minos="$(awk '/^[[:space:]]*minos[[:space:]]/ {print $2; exit}' <<<"$BUILD_INFO")"
    sdk="$(awk '/^[[:space:]]*sdk[[:space:]]/ {print $2; exit}' <<<"$BUILD_INFO")"

    if [[ -z "$minos" || -z "$sdk" ]]; then
        echo "Error: ${arch}: unable to read LC_BUILD_VERSION from $BINARY." >&2
        FAILED=1
        continue
    fi

    sdk_major="${sdk%%.*}"
    if [[ "$minos" != "$EXPECTED_MINOS" ]]; then
        echo "Error: ${arch}: deployment target is ${minos}, expected ${EXPECTED_MINOS}." >&2
        FAILED=1
    fi
    if (( sdk_major < MINIMUM_SDK_MAJOR )); then
        echo "Error: ${arch}: built against SDK ${sdk}, but the current design language requires SDK ${MINIMUM_SDK_MAJOR} or newer." >&2
        FAILED=1
    fi

    printf '%s: minos %s, sdk %s\n' "$arch" "$minos" "$sdk"
done

if (( FAILED != 0 )); then
    echo "LC_BUILD_VERSION check failed for $BINARY" >&2
    exit 1
fi

echo "LC_BUILD_VERSION check passed for $BINARY"
