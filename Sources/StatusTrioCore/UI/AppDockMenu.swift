import AppKit

@MainActor
enum AppDockMenu {
    /// The menu shown when the Dock icon is right-clicked. Quit is provided by
    /// the Dock itself, so only the app's own entry is added here.
    static func make(
        localization: Localization,
        target: AnyObject?,
        action: Selector?
    ) -> NSMenu {
        let menu = NSMenu()
        let item = NSMenuItem(
            title: localization.string(.menuSettings),
            action: action,
            keyEquivalent: ""
        )
        item.target = target
        menu.addItem(item)
        return menu
    }
}
