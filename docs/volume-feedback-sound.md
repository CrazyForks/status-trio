# Volume-change feedback sound

Issue [#64](https://github.com/lingyired/status-trio/issues/64) asked for the
same feedback macOS gives when the volume changes from the volume keys or
Control Center. The app follows the system switch instead of adding a switch of
its own, and plays a tick of its own making.

## The system switch can be read

macOS's "Play feedback when volume is changed" is the checkbox under System
Settings › Sound › Output. It writes a `Bool` under a **dotted key inside the
global domain**:

```bash
defaults read -g com.apple.sound.beep.feedback   # 1 = on, 0 = off
```

The value lives in `~/Library/Preferences/.GlobalPreferences.plist`. The dotted
name is the key itself, and there is no `com.apple.sound` domain:
`UserDefaults(suiteName: "com.apple.sound")` with `beep.feedback` reads nothing
at all. Reading it goes through the standard search list, which includes the
global domain:

```swift
UserDefaults.standard.object(forKey: "com.apple.sound.beep.feedback")
```

Confirmed against the setting's own implementation, which is the SwiftUI view in
`/System/Library/ExtensionKit/Extensions/Sound.appex/Contents/MacOS/Sound`:

```
%s -- playVolumeKeyFeedback
-[AppleSound_SoundSettings setPlayVolumeKeyFeedback:]
VolumeKeyFeedbackCheckbox
com.apple.sound.beep.feedback
```

A Mac whose owner never touched the checkbox keeps the value macOS ships — the
switch is on — so a **missing key counts as enabled**. The neighbouring keys
behave the same way: `.GlobalPreferences.plist` spells out
`com.apple.sound.beep.flash = 0` even though screen flashing is off by default.

A `UserDefaults(suiteName:)` instance does **not** isolate that read: the suite
domain goes in front of the standard search list, which still ends at
`NSGlobalDomain`. A brand-new suite with no value of its own therefore reads
whatever this Mac is set to, and reads `nil` only on a Mac that has never written
the key. Tests cover the two branches separately for that reason.

## The app has to play the sound itself

The system plays its tick for the volume changes the system mediates: the volume
keys, Control Center, and the slider in Sound settings. Status Trio writes the
volume through CoreAudio, which is not one of those paths, so no system feedback
follows and the tick is played from `SystemStatusStore.setVolume(_:)`.

## The bundled tick is ours, not Apple's

macOS's tick is
`/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff`.
The Sound settings extension implements its own preview with the same shape —
`beepFile`, `beepVolume`, `playBeepAtSystemVolume`, `cancelBeepAtSystemVolume` —
that is, `NSSound` playing one file, restarting rather than layering.

That file cannot be used: it sits on a private path that moves between releases,
a per-release difference is exactly what the bundled copy avoids, and it is
Apple's asset to ship. `scripts/generate-volume-feedback-sound.py` therefore
synthesizes an equivalent tone — a pure sine plus a short transient, so nothing
of Apple's is redistributed. Measured on macOS 26:

| | System `volume.aiff` | `VolumeFeedback.wav` |
| --- | --- | --- |
| File length | 0.382 s (only the first ~28 ms carries sound) | 0.040 s |
| Fundamental | 500 Hz, harmonics ≤ −62 dB | 500 Hz, harmonics ≤ −67 dB |
| Onset | peak inside 1 ms | 0.5 ms ramp |
| Decay | ~5.4 ms amplitude e-folding | 5.8 ms |
| Transient | 2450 Hz at −19.4 dB | 2450 Hz at −14.5 dB |
| Level | −7.0 dBFS peak | −7.0 dBFS peak |

Running the script rewrites `Sources/StatusTrioCore/Resources/VolumeFeedback.wav`.
Loudness tracks the output volume on its own, because the tick is played through
the same device the volume change applied to — which is what makes the feedback
rise and fall with the volume.

## Rules the player follows

| Situation | Behaviour |
| --- | --- |
| System switch off | Silent, read fresh on every call, so flipping the switch applies immediately |
| Volume actually changed | One tick, played after the CoreAudio write so it sounds at the new level |
| Same scalar asked for again (scrolling past either end) | Silent |
| Mute toggled | Silent, as on the system, where the mute key makes no sound |
| Mute released by turning the volume up | The volume change itself ticks |
| Scroll burst | Coalesced to one tick per `VolumeFeedbackThrottle.minimumInterval` (0.1 s) |
| Tick already ringing | Restarted, not layered |

`VolumeFeedbackPlayer` takes its defaults, clock, sound URL and playback as
initializer arguments so tests can exercise the gate and the coalescing without
making a sound.

## Verifying by hand

```bash
defaults read -g com.apple.sound.beep.feedback        # flip the checkbox, read again
afinfo Sources/StatusTrioCore/Resources/VolumeFeedback.wav
```

Then change the volume from the popover slider and from a scroll over it with
the switch on and off in turn.
