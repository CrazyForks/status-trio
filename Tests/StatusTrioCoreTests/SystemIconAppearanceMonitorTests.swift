import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct SystemIconAppearanceMonitorTests {
    @Test func reportsOnlyRealThemeChanges() {
        let center = NotificationCenter()
        var theme = SystemIconAppearanceTheme.default
        let monitor = SystemIconAppearanceMonitor(
            readTheme: { theme },
            notificationCenter: center
        )
        var reported: [SystemIconAppearanceTheme] = []
        monitor.onChange = { reported.append($0) }
        monitor.start()

        center.post(name: SystemIconAppearanceMonitor.didChangeNotificationName, object: nil)
        #expect(reported.isEmpty)

        let clearTheme = SystemIconAppearanceTheme(style: .clear, appearance: .dark)
        theme = clearTheme
        center.post(name: SystemIconAppearanceMonitor.didChangeNotificationName, object: nil)
        #expect(reported == [clearTheme])
    }

    @Test func reReadsWhenTheAppBecomesActive() {
        let center = NotificationCenter()
        var theme = SystemIconAppearanceTheme.default
        let monitor = SystemIconAppearanceMonitor(
            readTheme: { theme },
            notificationCenter: center
        )
        var reported: [SystemIconAppearanceTheme] = []
        monitor.onChange = { reported.append($0) }
        monitor.start()

        let darkTheme = SystemIconAppearanceTheme(style: .defaultStyle, appearance: .dark)
        theme = darkTheme
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        #expect(reported == [darkTheme])
    }

    @Test func stopsReportingAfterStop() {
        let center = NotificationCenter()
        var theme = SystemIconAppearanceTheme.default
        let monitor = SystemIconAppearanceMonitor(
            readTheme: { theme },
            notificationCenter: center
        )
        var reported: [SystemIconAppearanceTheme] = []
        monitor.onChange = { reported.append($0) }
        monitor.start()
        monitor.stop()

        theme = SystemIconAppearanceTheme(style: .clear, appearance: .light)
        center.post(name: SystemIconAppearanceMonitor.didChangeNotificationName, object: nil)

        #expect(reported.isEmpty)
    }
}
