import AppKit
import SwiftUI

struct AboutSettingsPane: View {
    @EnvironmentObject private var localization: Localization

    var body: some View {
        PreferencesPane {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 112, height: 112)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(AppMetadata.name)
                        .font(.system(size: 20, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(
                        localization.format(
                            .settingsAboutVersion,
                            AppMetadata.versionDisplayString
                        )
                    )
                    .font(.system(size: 11, weight: .light))

                    Text(localization.string(.settingsAboutDescription))
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(localization.string(.settingsAboutCopyright))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: 8) {
                Link(destination: AppMetadata.repositoryURL) {
                    Label {
                        Text(localization.string(.settingsAboutRepository))
                    } icon: {
                        GitHubMarkIcon()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Link(destination: AppMetadata.authorURL) {
                    Label(AppMetadata.authorName, systemImage: "person.crop.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Link(destination: AppMetadata.projectHomepageURL) {
                    Label(
                        localization.string(.settingsAboutProject),
                        systemImage: "house"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if localization.resolvedLanguage.isChinese {
                    Link(destination: AppMetadata.authorWebsiteURL) {
                        Label(
                            localization.string(.settingsAboutWebsite),
                            systemImage: "globe"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
}

private struct GitHubMarkIcon: View {
    var body: some View {
        if let image = AboutIcon.githubMark {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "link")
                .accessibilityHidden(true)
        }
    }
}
