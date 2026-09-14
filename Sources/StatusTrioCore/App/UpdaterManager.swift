import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class UpdaterManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdaterManager()

    @Published private(set) var canCheckForUpdates = false

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    private var isShowingManualUpdateUI = false

    var automaticallyChecksForUpdates: Bool {
        get {
            if PreviewAppIdentity.isPreviewBuild { return false }
            return controller.updater.automaticallyChecksForUpdates
        }
        set {
            guard !PreviewAppIdentity.isPreviewBuild else { return }
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    var automaticallyChecksForUpdatesBinding: Binding<Bool> {
        Binding(
            get: { self.automaticallyChecksForUpdates },
            set: { self.automaticallyChecksForUpdates = $0 }
        )
    }

    private override init() {
        super.init()

        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
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
