#!/usr/bin/env bash
set -euo pipefail

APP="${1:-}"
if [[ -z "$APP" || ! -d "$APP" ]]; then
    echo "Usage: $0 <StatusTrio.app>" >&2
    exit 2
fi

SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [[ ! -d "$SPARKLE" ]]; then
    echo "Error: Sparkle.framework is missing from $APP" >&2
    exit 1
fi

python3 - "$SPARKLE" <<'PY'
import os
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
executables = []
for path in root.rglob("*"):
    if not path.is_file() or path.is_symlink():
        continue
    try:
        with path.open("rb") as fh:
            magic = fh.read(4)
    except OSError:
        continue
    if magic in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xfe\xed\xfa\xce", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"):
        executables.append(path)
if not executables:
    raise SystemExit(f"no Mach-O files found under {root}")

failures = []
for path in executables:
    archs = subprocess.check_output(["lipo", "-archs", str(path)], text=True).strip().split()
    if not archs:
        failures.append(f"{path.relative_to(root)} has no architecture slices")
        continue
    if set(archs) != {"arm64", "x86_64"}:
        failures.append(
            f"{path.relative_to(root)} must be Universal, found: {' '.join(archs)}"
        )
        continue
    for arch in archs:
        out = subprocess.check_output(["vtool", "-show-build", "-arch", arch, str(path)], text=True, stderr=subprocess.STDOUT)
        lines = out.splitlines()
        minos = None
        for index, line in enumerate(lines):
            if re.match(r"^\s*minos\s+", line):
                minos = line.split()[1]
                break
            if "LC_VERSION_MIN_MACOSX" in line:
                for candidate in lines[index + 1:index + 8]:
                    candidate = candidate.strip()
                    if candidate.startswith("version "):
                        minos = candidate.split()[1]
                        break
                break
        if not minos:
            failures.append(f"{path.relative_to(root)} ({arch}) has no platform minimum")
            continue
        parts = [int(part) for part in minos.split(".")]
        parts += [0] * (3 - len(parts))
        if tuple(parts[:3]) > (13, 0, 0):
            failures.append(f"{path.relative_to(root)} ({arch}) has minimum {minos}")

if failures:
    print("Sparkle binaries require a newer macOS than Ventura:", file=sys.stderr)
    print("\n".join(failures), file=sys.stderr)
    raise SystemExit(1)

print(f"Sparkle metadata is Ventura-compatible across {len(executables)} Mach-O files")
PY
