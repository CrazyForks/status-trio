import AppKit
import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
struct ChargingEffectMotionMonitorTests {
    @Test func readsAndPublishesReduceMotionChangesFromInjectedDependencies() {
        let center = NotificationCenter()
        var reduceMotion = false
        let monitor = ChargingEffectMotionMonitor(
            readReduceMotion: { reduceMotion },
            notificationCenter: center
        )
        var changes: [Bool] = []
        monitor.onChange = { changes.append($0) }

        #expect(monitor.shouldReduceMotion == false)
        monitor.start()
        reduceMotion = true
        center.post(name: ChargingEffectMotionMonitor.didChangeNotification, object: nil)

        #expect(monitor.shouldReduceMotion)
        #expect(changes == [true])

        center.post(name: ChargingEffectMotionMonitor.didChangeNotification, object: nil)
        #expect(changes == [true])

        reduceMotion = false
        center.post(name: ChargingEffectMotionMonitor.didChangeNotification, object: nil)
        #expect(monitor.shouldReduceMotion == false)
        #expect(changes == [true, false])
        monitor.stop()
    }

    @Test func stopRemovesTheAccessibilityObserver() {
        let center = NotificationCenter()
        var reduceMotion = false
        let monitor = ChargingEffectMotionMonitor(
            readReduceMotion: { reduceMotion },
            notificationCenter: center
        )
        monitor.start()
        monitor.stop()
        reduceMotion = true
        center.post(name: ChargingEffectMotionMonitor.didChangeNotification, object: nil)

        #expect(monitor.shouldReduceMotion == false)
    }
}
