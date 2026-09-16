import SwiftUI

struct BatteryDetailsView: View {
    @EnvironmentObject private var localization: Localization
    @ObservedObject var controller: BatteryDetailsController
    let battery: BatteryStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let details = controller.details {
                if let power = details.power {
                    row(power.watts > 0 ? .batteryDetailsCharging : .batteryDetailsDischarging,
                        abs(power.watts).formatted(.number.precision(.fractionLength(1))) + " W")
                        .foregroundStyle(power.watts > 0 ? Color.green : Color.primary)
                    row(.batteryDetailsVoltage, power.volts.formatted(.number.precision(.fractionLength(2))) + " V")
                    row(.batteryDetailsCurrent, power.amps.formatted(.number.precision(.fractionLength(2))) + " A")
                    row(.batteryDetailsSampled, power.updatedAt.formatted(date: .omitted, time: .standard))
                } else {
                    row(.batteryDetailsPower, localization.string(.batteryDetailsUnavailable))
                }
                if let watts = details.adapterWatts {
                    row(.batteryDetailsAdapter, watts.formatted() + " W")
                }
                if !battery.isConnectedToPower {
                    row(.batteryDetailsRemaining, details.remainingMinutes.map {
                        Duration.seconds($0 * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
                    } ?? localization.string(.batteryDetailsUnavailable))
                }
                if let count = details.cycleCount {
                    row(.batteryDetailsCycles, count.formatted())
                }
            } else {
                Text(localization.string(.batteryDetailsLoading)).foregroundStyle(.secondary)
            }
            row(.batteryDetailsLowPower, localization.string(battery.isLowPowerMode ? .batteryDetailsOn : .batteryDetailsOff))
            Text(localization.string(.batteryDetailsExplanation))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .monospacedDigit()
        .task(id: BatteryPowerState(battery)) {
            controller.activate(state: BatteryPowerState(battery))
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15), tolerance: .seconds(3)) }
                catch { return }
                guard !Task.isCancelled else { return }
                controller.refresh()
            }
        }
        .onDisappear { controller.deactivate() }
    }

    private func row(_ key: LocalizationKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(localization.string(key)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
