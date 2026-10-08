import SwiftUI

enum MobileBatteryDeviceRowPresentation {
    static func displayName(_ snapshot: MobileBatterySnapshot, fallbackWatchName: String) -> String {
        let name = snapshot.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            return BluetoothMobileDeviceModel.kind(forModel: snapshot.model) == .mobile(.watch)
                ? fallbackWatchName
                : "iPhone"
        }
        return name
    }

    static func sourceText(_ snapshot: MobileBatterySnapshot, viaIPhone: String) -> String? {
        nil
    }

    static func chargingText(_ snapshot: MobileBatterySnapshot, charging: String) -> String? {
        snapshot.isCharging == true ? charging : nil
    }

    static func detailText(_ snapshot: MobileBatterySnapshot, charging: String) -> String? {
        chargingText(snapshot, charging: charging)
    }
}

/// The observation detail drawn under a row backed by the trusted-phone helper.
/// Watch names and charging state are absent from the helper response today, so
/// the row uses the localized fallback and only reports charging when observed.
struct MobileBatteryDeviceRows: View {
    @EnvironmentObject private var localization: Localization
    let snapshot: MobileBatterySnapshot

    var body: some View {
        if let detailText = MobileBatteryDeviceRowPresentation.detailText(
            snapshot,
            charging: localization.string(.mobileBatteryCharging)
        ) {
            Text(detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
