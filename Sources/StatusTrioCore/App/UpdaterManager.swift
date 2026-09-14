import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class UpdaterManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdaterManager()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    private var isShowingManualUpdateUI = false

    var automaticallyChecksForUpdatesBinding: Binding<Bool> {
        Binding(
            get: { self.automaticallyChecksForUpdates },
            set: { self.controller.updater.automaticallyChecksForUpdates = $0 }
        )
    }

    private override init() {
        super.init()

        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
    }

    func start() {
        guard !PreviewAppIdentity.isPreviewBuild else { return }
        #if DEBUG
        return
        #else
        controller.startUpdater()
        #endif
    }

    func checkForUpdates() {
        guard !PreviewAppIdentity.isPreviewBuild else { return }
        #if DEBUG
        return
        #else
        guard canCheckForUpdates else { return }

        isShowingManualUpdateUI = true
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
        #endif
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        guard isShowingManualUpdateUI else { return }
        isShowingManualUpdateUI = false
        NSApp.setActivationPolicy(.accessory)
    }
}
