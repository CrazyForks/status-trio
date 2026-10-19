import Foundation

enum MenuBarHelpSettingsTier: Equatable {
    /// macOS 26 and later name the pane Menu Bar, although it still loads the
    /// `ControlCenter-Settings` extension.
    case menuBarSettings
    /// macOS 13 through 25 expose the same extension as Control Center.
    case controlCenterSettings
}

struct MenuBarHelpPolicy: Equatable {
    let majorVersion: Int

    init(majorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) {
        self.majorVersion = majorVersion
    }

    var tier: MenuBarHelpSettingsTier {
        majorVersion >= 26 ? .menuBarSettings : .controlCenterSettings
    }

    /// macOS 27 is the first release whose menu bar exposes the native overflow
    /// indicator. Later releases inherit it.
    var showsNativeOverflowEntry: Bool {
        majorVersion >= 27
    }

    var stepKeys: [LocalizationKey] {
        if showsNativeOverflowEntry {
            return [
                .guideMenuBarHelpOverflowStep,
                .guideMenuBarHelpMenuBarSettingsStep,
                .guideMenuBarHelpMoveStep
            ]
        }

        if majorVersion >= 26 {
            return [
                .guideMenuBarHelpMenuBarSettingsStep,
                .guideMenuBarHelpFindStatusTrioStep,
                .guideMenuBarHelpMoveStep
            ]
        }

        return [
            .guideMenuBarHelpControlCenterStep,
            .guideMenuBarHelpMoveStep
        ]
    }

    var systemSettingsButtonKey: LocalizationKey {
        showsNativeOverflowEntry
            ? .guideMenuBarHelpOpenMenuBarSettings
            : .guideMenuBarHelpOpenSystemSettings
    }

    var systemSettingsURLs: [URL] {
        if showsNativeOverflowEntry {
            return [
                URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!,
                Self.systemSettingsAppURL
            ]
        }

        // The direct pane route is verified on macOS 27 only. Older releases
        // keep the exact written path and use the System Settings app so the
        // button never claims a destination that this build cannot verify.
        return [Self.systemSettingsAppURL]
    }

    static let systemSettingsAppURL = URL(string: "x-apple.systempreferences:")!

    static let allLocalizationKeys: [LocalizationKey] = [
        .guideMenuBarHelpPrompt,
        .guideMenuBarHelpOpen,
        .guideMenuBarHelpTitle,
        .guideMenuBarHelpReason,
        .guideMenuBarHelpOverflowStep,
        .guideMenuBarHelpMenuBarSettingsStep,
        .guideMenuBarHelpControlCenterStep,
        .guideMenuBarHelpFindStatusTrioStep,
        .guideMenuBarHelpSimplifyStep,
        .guideMenuBarHelpMoveStep,
        .guideMenuBarHelpOpenMenuBarSettings,
        .guideMenuBarHelpOpenSystemSettings,
        .guideMenuBarHelpReopen,
        .guideMenuBarHelpLearnMore,
        .guideMenuBarHelpClose
    ]
}
