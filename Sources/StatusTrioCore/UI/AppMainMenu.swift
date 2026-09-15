import AppKit

@MainActor
enum AppMainMenu {
    /// Builds the app's main menu bar.
    ///
    /// An `NSApplication` without a main menu keeps showing the previously active
    /// app's menus while it is active, which leaves the Apple menu unclickable, so
    /// the app menu and the window menu have to exist for the Settings window.
    @discardableResult
    static func make(
        localization: Localization,
        target: AnyObject?,
        openSettingsAction: Selector
    ) -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = makeAppMenu(
            localization: localization,
            target: target,
            openSettingsAction: openSettingsAction
        )
        mainMenu.addItem(appMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = makeWindowMenu(localization: localization)
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApplication.shared.windowsMenu = windowMenu
        return mainMenu
    }

    private static func makeAppMenu(
        localization: Localization,
        target: AnyObject?,
        openSettingsAction: Selector
    ) -> NSMenu {
        let menu = NSMenu(title: AppMetadata.name)

        menu.addItem(item(
            title: localization.format(.menuAbout, AppMetadata.name),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            target: nil
        ))
        menu.addItem(separator())
        menu.addItem(item(
            title: localization.string(.menuSettings),
            action: openSettingsAction,
            target: target,
            keyEquivalent: ","
        ))
        menu.addItem(separator())
        menu.addItem(item(
            title: localization.format(.menuHide, AppMetadata.name),
            action: #selector(NSApplication.hide(_:)),
            target: nil,
            keyEquivalent: "h"
        ))
        menu.addItem(item(
            title: localization.string(.menuHideOthers),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            target: nil,
            keyEquivalent: "h",
            modifiers: [.command, .option]
        ))
        menu.addItem(item(
            title: localization.string(.menuShowAll),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            target: nil
        ))
        menu.addItem(separator())
        menu.addItem(item(
            title: localization.string(.menuQuit),
            action: #selector(NSApplication.terminate(_:)),
            target: nil,
            keyEquivalent: "q"
        ))

        return menu
    }

    private static func makeWindowMenu(localization: Localization) -> NSMenu {
        let menu = NSMenu(title: localization.string(.menuWindow))
        menu.addItem(item(
            title: localization.string(.menuCloseWindow),
            action: #selector(NSWindow.performClose(_:)),
            target: nil,
            keyEquivalent: "w"
        ))
        return menu
    }

    private static func item(
        title: String,
        action: Selector,
        target: AnyObject?,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        if !keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        return item
    }

    private static func separator() -> NSMenuItem {
        .separator()
    }
}
