# Audio output device icons

The volume output list shows one icon per device. Issue
[#12](https://github.com/lingyired/status-trio/issues/12) reported that every
device rendered as a speaker, including connected AirPods.

## Where the system keeps its icon table

The system UI does not hard-code device glyphs. It resolves a device type, then
reads the matching symbol from
`/System/Library/CoreServices/CoreTypes.bundle/Contents/Info.plist`, whose
`UTTypeSymbolName` keys are the SF Symbols the system draws:

| Device type | Symbol |
| --- | --- |
| `public.speaker` | `hifispeaker.fill` |
| `public.display` | `display` |
| `com.apple.accessory.headphones` | `headphones` |
| `com.apple.airpods` | `airpods` |
| `com.apple.airpods-gen3` | `airpods.gen3` |
| `com.apple.airpods-pro` | `airpods.pro.gen1` |
| `com.apple.airpods-max` | `airpodsmax` |
| `com.apple.beats-*` | `beats.headphones`, `beats.powerbeatspro`, `beats.studiobuds`, `beats.fit.pro`, `beats.earphones` |
| `com.apple.homepod`, `com.apple.homepod-mini` | `homepod`, `homepodmini` |
| `com.apple.apple-tv` | `appletv` |
| `com.apple.mac.laptop` | `macbook` |
| `com.apple.macmini`, `com.apple.macstudio`, `com.apple.macpro` | `macmini.gen2`, `macstudio`, `macpro.gen3` |

`AudioOutputDeviceIcon` uses those exact symbol names, so the app draws what the
system draws for the same device class. Note that the system always uses the
filled speaker glyph; the app distinguishes the selected device with its accent
circle instead of a second symbol.

## Built-in output draws the machine

For a built-in output the system draws the machine itself, not a speaker: a
MacBook row shows the `macbook` symbol. `HostMacKind` reproduces that from the
device name, which carries the family (`MacBook Pro扬声器`, `Mac mini扬声器`),
and falls back to `hw.model` when the name does not name the machine. Apple
Silicon identifiers such as `Mac15,9` no longer encode the family, which is why
the device name is read first.

A Mac with a headphone jack keeps one built-in output device and switches its
data source, so plugging headphones in switches the row from the machine symbol
to the headphones symbol.

## AirPlay

AirPlay outputs use `airplayaudio`, the AirPlay glyph, unless the device name
identifies an Apple TV (`appletv`) or a HomePod (`homepod`, `homepodmini`).

## Driver supplied icons

`kAudioDevicePropertyIcon` is an optional public property that returns a
`CFURLRef` to an image file the driver ships. HAL plugin devices use it, for
example `Background Music` points at
`/Library/Audio/Plug-Ins/HAL/Background Music Device.driver/Contents/Resources/DeviceIcon.icns`.
Built-in hardware and most USB devices do not provide it and return
`kAudioHardwareUnknownPropertyError` instead.

`AudioOutputDeviceIcon.source(for:)` therefore returns the driver image when the
file exists and the class symbol otherwise. `AudioOutputDeviceIconView` draws
that image as a template so it takes the same tint as the symbol it replaces.

Several of those symbols are recent additions. `airpods.pro.gen1` ships with
macOS 26, so every class also carries an older fallback and
`AudioOutputDeviceIcon.symbolName(for:)` returns the first symbol the running
system actually provides. That keeps macOS 15 correct instead of blank.

## How a device is classified

Two public CoreAudio properties describe an output device:

| Property | Scope | What it reports |
| --- | --- | --- |
| `kAudioDevicePropertyTransportType` | global | Hardware family: `bltn` built-in, `blue`/`blea` Bluetooth, `usb `, `hdmi`, `dprt` display, `thun`, `airp`, `grup`, `virt` |
| `kAudioDevicePropertyDataSource` | output | Live source on built-in hardware: `ispk` internal speakers, `hdpn` headphones, `espk` external speakers |

`kAudioDevicePropertyDataSource` is what lets a built-in output show the
headphones icon while something is plugged into the headphone jack, matching the
system menu.

## What stays name based

The system picks the Apple accessory type from a private Bluetooth product-ID
table. `ControlCenter` contains strings such as:

```
Unable to find device class for productID: %{public}x, fallback to default headphones symbol
```

Third-party apps cannot read that product ID through a public API, so the
AirPods, Beats, HomePod, and Apple TV model names remain name based. Bluetooth
audio that is not recognized by name defaults to the headphones symbol, because
Bluetooth audio is overwhelmingly headphones and earbuds.

## Where the mapping lives

`Sources/StatusTrioCore/Audio/AudioOutputDeviceIcon.swift` holds the transport
and data-source value types plus `AudioOutputDeviceIcon`, which maps a device to
an `AudioOutputDeviceKind` and then to an SF Symbol name. Both the popup output
list (`OutputDeviceRow`) and the settings output-order list
(`AudioSectionView`) use it so the two surfaces stay aligned.
