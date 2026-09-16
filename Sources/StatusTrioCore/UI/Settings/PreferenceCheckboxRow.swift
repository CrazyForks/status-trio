import SwiftUI

struct PreferenceCheckboxRow: View {
    let label: LocalizationKey
    let description: LocalizationKey?
    @Binding var isOn: Bool
    @EnvironmentObject private var localization: Localization

    init(
        label: LocalizationKey,
        description: LocalizationKey? = nil,
        isOn: Binding<Bool>
    ) {
        self.label = label
        self.description = description
        _isOn = isOn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(isOn: $isOn) {
                Text(localization.string(label))
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)

            if let description {
                Text(localization.string(description))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
