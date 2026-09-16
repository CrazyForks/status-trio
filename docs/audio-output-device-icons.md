# Audio output device icons

The volume output list shows one icon per device. Issue
[#12](https://github.com/lingyired/status-trio/issues/12) reported that every
device rendered as a speaker, including connected AirPods.

## Which APIs exist

There is no public API that returns the exact icon the system volume menu draws.
The public CoreAudio properties that describe an output device are:

| Property | Scope | What it reports |
| --- | --- | --- |
| `kAudioDevicePropertyTransportType` | global | Hardware family of the device: `bltn`, `blue`, `blea`, `usb `, `hdmi`, `dprt`, `thun`, `airp`, `grup`, `virt`, and others |
| `kAudioDevicePropertyDataSource` | output | The live output source on built-in hardware: `ispk` internal speakers, `hdpn` headphones, `espk` external speakers |

`kAudioDevicePropertyDataSource` is what lets a built-in output device show the
headphones icon while something is plugged into the headphone jack, matching the
system menu.

## What stays name based

The system volume menu tells AirPods Pro, AirPods Max, AirPods, and other Apple
accessories apart with a private Bluetooth product-ID table. `ControlCenter`
contains strings such as:

```
Unable to find device class for productID: %{public}x, fallback to default headphones symbol
```

Third-party apps cannot read that product ID through a public API, so the
AirPods, HomePod, and display/TV names remain name based fallbacks. Bluetooth
audio devices that are not recognized by name default to the headphones symbol,
because Bluetooth audio is overwhelmingly headphones and earbuds.

## Where the mapping lives

`Sources/StatusTrioCore/Audio/AudioOutputDeviceIcon.swift` holds the transport
and data-source value types plus `AudioOutputDeviceIcon`, which maps a device to
an `AudioOutputDeviceKind` and then to an SF Symbol name. Both the popup output
list (`OutputDeviceRow`) and the settings output-order list
(`AudioSectionView`) use it so the two surfaces stay aligned.
