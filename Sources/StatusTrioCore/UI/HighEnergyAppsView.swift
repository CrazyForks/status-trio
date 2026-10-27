import SwiftUI

struct HighEnergyAppsView: View {
    let ranking: ApplicationEnergyRanking
    @EnvironmentObject private var localization: Localization

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(localization.string(.batteryHighEnergyApps)).font(.caption.weight(.semibold))
            if ranking.phase == .sampling {
                Text(localization.string(.batteryDetailsCollecting)).foregroundStyle(.secondary)
            } else if ranking.phase == .unavailable {
                Text(localization.string(.batteryDetailsUnavailable)).foregroundStyle(.secondary)
            } else if ranking.apps.isEmpty {
                Text(localization.string(.batteryEnergyAppsEmpty)).foregroundStyle(.secondary)
            } else {
                ForEach(ranking.apps) { app in
                    Label(app.name, systemImage: "app")
                        .lineLimit(1)
                        .help(app.name)
                }
            }
            Text(localization.string(ranking.basis == .cpuEnergy ? .batteryEnergyCPUExplanation : .batteryEnergyActivityExplanation))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
