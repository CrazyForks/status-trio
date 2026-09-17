#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORKTREE_NAME="$(basename "$ROOT")"
BRANCH_NAME="$(git -C "$ROOT" branch --show-current 2>/dev/null || true)"
IDENTITY="${BRANCH_NAME:-$WORKTREE_NAME}"
SUFFIX="$(
    printf '%s' "$IDENTITY" \
        | sed -E 's#^codex/##' \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
)"
if [[ -z "$SUFFIX" ]]; then
    SUFFIX="worktree"
fi

DEFAULT_BUNDLE_ID="com.lingsmbp.StatusTrio.dev.$SUFFIX"
DISPLAY_NAME="$(
    printf '%s' "$SUFFIX"         | tr '-' ' '         | awk '{ for (i = 1; i <= NF; i++) $i = toupper(substr($i, 1, 1)) substr($i, 2) } 1'
)"
DEFAULT_APP_NAME="Status Trio ($DISPLAY_NAME)"
BUNDLE_ID="${BUNDLE_ID:-$DEFAULT_BUNDLE_ID}"
APP_NAME="${APP_NAME:-$DEFAULT_APP_NAME}"

exec env BUNDLE_ID="$BUNDLE_ID" APP_NAME="$APP_NAME" DEVELOPMENT_CODENAME="$DISPLAY_NAME" \
    bash "$ROOT/scripts/build-app.sh" "$@"
