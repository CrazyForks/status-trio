#!/usr/bin/env python3
"""Regenerate the volume-change feedback sound bundled with the app.

The app plays its own tick when the volume changes through Status Trio, gated on
macOS's "Play feedback when volume is changed" switch. macOS's own tick lives at
`/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff`,
but that file is Apple's, it is a private path that can move between releases, and
it must not be redistributed inside an app bundle. This script therefore
synthesizes an equivalent tone from scratch — a pure sine plus a short transient,
which is why the asset carries no third-party audio.

Measured on macOS 26 (the shape this reproduces):

    duration      0.3824 s of file, but only the first ~28 ms carries sound
    onset         peak reached inside 1 ms
    fundamental   500 Hz, harmonics below -62 dB (i.e. a pure sine)
    transient     2450 Hz at -14.5 dB, decaying over ~10 ms
    decay         ~5.4 ms amplitude e-folding time
    level         -7.0 dBFS peak

Usage:
    python3 scripts/generate-volume-feedback-sound.py
"""

from __future__ import annotations

import math
import struct
import sys
import wave
from pathlib import Path

SAMPLE_RATE = 44_100
FUNDAMENTAL_HZ = 500.0
TRANSIENT_HZ = 2_450.0
TRANSIENT_RELATIVE_LEVEL = 10 ** (-14.5 / 20)
TRANSIENT_DECAY_SECONDS = 0.004
DECAY_SECONDS = 0.006  # 1/e amplitude time
ATTACK_SECONDS = 0.0005
DURATION_SECONDS = 0.040
FADE_OUT_SECONDS = 0.004
PEAK = 0.4467  # -7.0 dBFS, matching the sound this replaces

OUTPUT = (
    Path(__file__).resolve().parent.parent
    / "Sources/StatusTrioCore/Resources/VolumeFeedback.wav"
)


def envelope(t: float) -> float:
    attack = min(1.0, t / ATTACK_SECONDS)
    body = math.exp(-t / DECAY_SECONDS)
    fade_start = DURATION_SECONDS - FADE_OUT_SECONDS
    fade = 1.0 if t <= fade_start else max(0.0, (DURATION_SECONDS - t) / FADE_OUT_SECONDS)
    return attack * body * fade


def samples() -> list[int]:
    count = int(DURATION_SECONDS * SAMPLE_RATE)
    raw = []
    for index in range(count):
        t = index / SAMPLE_RATE
        gain = envelope(t)
        tone = math.sin(2 * math.pi * FUNDAMENTAL_HZ * t)
        transient = TRANSIENT_RELATIVE_LEVEL * math.sin(2 * math.pi * TRANSIENT_HZ * t)
        transient *= math.exp(-t / TRANSIENT_DECAY_SECONDS)
        raw.append(gain * (tone + transient))

    peak = max(abs(value) for value in raw)
    scale = PEAK / peak
    return [int(round(max(-1.0, min(1.0, value * scale)) * 32767)) for value in raw]


def main() -> int:
    data = samples()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUTPUT), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(b"".join(struct.pack("<h", value) for value in data))
    print(f"wrote {OUTPUT} ({OUTPUT.stat().st_size} bytes, {len(data)} frames)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
