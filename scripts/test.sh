#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Enforce the AGENTS.md rule the CI toolchain needs: never pass an
# actor-isolated method as a function value (docs/swift-ci-compatibility.md).
# Unconditional, so a filtered run still enforces the rule even though
# ForbiddenPatternGuardTests is filtered out.
bash "$SCRIPT_DIR/check-forbidden-patterns.sh"

if [[ $# -gt 0 ]]; then
    swift test --filter "$1"
else
    swift test
fi
