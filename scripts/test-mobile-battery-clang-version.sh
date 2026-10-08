#!/usr/bin/env bash
# Exercise only the real helper's version probe; no compiler or dependency build.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

cat > "$TEST_ROOT/clang" <<'CLANG'
#!/bin/bash
set -euo pipefail
trap - PIPE
printf 'Apple clang version fixture\n'
if [[ "${PRODUCER_STATUS:-0}" != 0 ]]; then
    exit "$PRODUCER_STATUS"
fi
payload="$(printf '%4096s' '')"
for ((line = 0; line < 1024; line++)); do
    printf '%s\n' "$payload"
done
CLANG
chmod +x "$TEST_ROOT/clang"

# Keep the old pipeline as a control: output exceeds pipe capacity, so head
# closes the read end while the producer is still writing.
status=0
CLANG="$TEST_ROOT/clang" /bin/bash -euo pipefail -c \
    'CLANG_VERSION="$("$CLANG" --version | head -n 1)"' \
    > "$TEST_ROOT/legacy.log" 2>&1 || status=$?
if [[ "$status" != 141 ]]; then
    echo "FAIL: legacy truncating pipeline exited $status instead of SIGPIPE (141)." >&2
    exit 1
fi

# Extract the production assignments up to BUILD_KEY rather than duplicating
# the fix, and stop before any SDK, cache, architecture, or build operations.
ruby -e '
  source = File.read(ARGV[0])
  start = source.index(/^    CLANG_VERSION=/) or abort "missing version probe"
  finish = source.index(/^    BUILD_KEY=/, start) or abort "missing build-key boundary"
  File.write(ARGV[1], source[start...finish] + %q{printf "%s\n" "$CLANG_VERSION"} + "\n")
' "$ROOT/scripts/build-mobile-battery-helper.sh" "$TEST_ROOT/probe.sh"

status=0
CLANG="$TEST_ROOT/clang" /bin/bash -euo pipefail "$TEST_ROOT/probe.sh" \
    > "$TEST_ROOT/version.log" 2>&1 || status=$?
if [[ "$status" != 0 || "$(<"$TEST_ROOT/version.log")" != 'Apple clang version fixture' ]]; then
    echo "FAIL: production version capture exited $status or changed the first line." >&2
    exit 1
fi

status=0
CLANG="$TEST_ROOT/clang" PRODUCER_STATUS=23 /bin/bash -euo pipefail "$TEST_ROOT/probe.sh" \
    > "$TEST_ROOT/failure.log" 2>&1 || status=$?
if [[ "$status" != 23 || -s "$TEST_ROOT/failure.log" ]]; then
    echo "FAIL: producer failure was not preserved (exit $status)." >&2
    exit 1
fi
echo 'clang version capture: legacy SIGPIPE reproduced, first line preserved, producer failure propagated'
