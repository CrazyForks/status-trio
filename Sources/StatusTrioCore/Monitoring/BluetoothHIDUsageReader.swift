import Foundation
import IOKit

/// One HID interface a device presents, as the I/O Registry describes it.
///
/// `usagePage` 1 is Generic Desktop, where the usages that name an input device
/// live: 2 mouse, 4 joystick, 5 game pad, 6 keyboard, 7 keypad, 8 multi-axis.
/// `usagePage` 0x0D is Digitizer, whose 5 is a touch pad — a trackpad also
/// enumerates as a pointer, so the page is what tells the two apart.
struct BluetoothHIDUsage: Equatable, Sendable {
    let usagePage: Int
    let usage: Int
}

/// Reads the HID usages of every Bluetooth device the system has enumerated.
///
/// The class wording in the system profiler's report is the manufacturer's
/// claim about its product and it can be wrong: a Logitech keyboard reports
/// `Mouse` in `device_minorType`, while the usage it presents is Generic
/// Desktop keyboard — the one macOS actually loads a keyboard driver for. The
/// I/O Registry carries that usage and nothing else in the app reads it.
///
/// The walk runs inside this process: `IORegistryEntryCreateCFProperties` over
/// the services `IOServiceMatching` returns. There is no `ioreg` or `hidutil`
/// subprocess to hang the way `/usr/sbin/system_profiler` can, no Bluetooth
/// grant is involved, and the app is not sandboxed, so the Registry is readable
/// without a permission of any kind.
///
/// Only connected devices have a node. A paired but disconnected device keeps
/// the class the report declared, which is the same answer the app gave before
/// this reader existed.
enum BluetoothHIDUsageReader {
    /// Keyed by `BluetoothBatteryReader.normalizedAddress`, the one
    /// normalization the app joins devices by, so a Registry address written
    /// `d3-6d-6c-40-a3-2e` and a report address written `D3:6D:6C:40:A3:2E`
    /// meet on the same key.
    static func read() -> [String: [BluetoothHIDUsage]] {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOHIDDevice")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return [:]
        }
        defer { IOObjectRelease(iterator) }

        var usages: [String: [BluetoothHIDUsage]] = [:]
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let properties = unmanaged?.takeRetainedValue() as? [String: Any],
                  let address = bluetoothAddress(of: properties),
                  let usagePage = properties["PrimaryUsagePage"] as? Int,
                  let usage = properties["PrimaryUsage"] as? Int else {
                continue
            }

            let key = BluetoothBatteryReader.normalizedAddress(address)
            guard !key.isEmpty else { continue }
            usages[key, default: []].append(
                BluetoothHIDUsage(usagePage: usagePage, usage: usage)
            )
        }
        return usages
    }

    /// The node's own address, and only for a Bluetooth node: the transport is
    /// what separates these from the built-in and USB devices that also carry
    /// primary usages. Both transports the system reports for a Bluetooth
    /// accessory — `Bluetooth` and `Bluetooth Low Energy` — contain the word.
    private static func bluetoothAddress(of properties: [String: Any]) -> String? {
        let transport = (properties["Transport"] as? String) ?? ""
        guard transport.lowercased().contains("bluetooth") else { return nil }
        return properties["DeviceAddress"] as? String
    }
}

/// Turns the usages a device presents into the peripheral it is.
///
/// Pure, so the precedence is unit-tested rather than inferred from a live
/// Mac's device list. A device presents several interfaces at once — a
/// trackpad is both a pointer and a touch pad, a keyboard with a jog wheel
/// presents more than one keyboard collection — so the order below is the rule
/// that decides, not the order the Registry happens to return them in.
enum BluetoothHIDUsageClassifier {
    private enum UsagePage {
        static let genericDesktop = 1
        static let digitizer = 0x0D
    }

    private enum GenericDesktopUsage {
        static let pointer = 1
        static let mouse = 2
        static let joystick = 4
        static let gamePad = 5
        static let keyboard = 6
        static let keypad = 7
        static let multiAxisController = 8
    }

    private enum DigitizerUsage {
        static let touchPad = 0x05
        static let finger = 0x22
    }

    /// `nil` when nothing here describes the device, which leaves whatever the
    /// report declared in place.
    ///
    /// A touch pad outranks the pointer interface the same trackpad also
    /// presents, and a keyboard outranks the pointer collection on a device
    /// that is both: a combination device is a keyboard that happens to have a
    /// pointing surface, and reading it the other way would redraw the
    /// keyboard the user is typing on as a mouse.
    static func peripheralForm(from usages: [BluetoothHIDUsage]) -> PeripheralForm? {
        func has(_ page: Int, _ usage: Int) -> Bool {
            usages.contains { $0.usagePage == page && $0.usage == usage }
        }

        if has(UsagePage.digitizer, DigitizerUsage.touchPad)
            || has(UsagePage.digitizer, DigitizerUsage.finger) {
            return .trackpad
        }
        if has(UsagePage.genericDesktop, GenericDesktopUsage.gamePad)
            || has(UsagePage.genericDesktop, GenericDesktopUsage.joystick) {
            return .gamepad
        }
        if has(UsagePage.genericDesktop, GenericDesktopUsage.keyboard)
            || has(UsagePage.genericDesktop, GenericDesktopUsage.keypad) {
            return .keyboard
        }
        if has(UsagePage.genericDesktop, GenericDesktopUsage.mouse)
            || has(UsagePage.genericDesktop, GenericDesktopUsage.pointer)
            || has(UsagePage.genericDesktop, GenericDesktopUsage.multiAxisController) {
            return .mouse
        }
        return nil
    }
}
