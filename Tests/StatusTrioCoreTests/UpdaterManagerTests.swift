import Combine
import Testing
@testable import StatusTrioCore

@MainActor
struct UpdaterManagerTests {
    @Test
    func settingAutomaticallyChecksForUpdatesPublishesChange() {
        let manager = UpdaterManager.shared
        let originalValue = manager.automaticallyChecksForUpdates
        defer {
            manager.automaticallyChecksForUpdatesBinding.wrappedValue = originalValue
        }

        var didPublishChange = false
        let cancellable = manager.objectWillChange.sink {
            didPublishChange = true
        }
        defer { cancellable.cancel() }

        manager.automaticallyChecksForUpdatesBinding.wrappedValue = !originalValue

        #expect(didPublishChange)
        #expect(manager.automaticallyChecksForUpdates == !originalValue)
    }
}
