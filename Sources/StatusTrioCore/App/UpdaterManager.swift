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
    private var updateSourceFallback = UpdateSourceFallback()
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
        #if DEBUG
        return
        #else
        controller.startUpdater()
        #endif
    }

    func checkForUpdates() {
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

    func feedURLString(for updater: SPUUpdater) -> String? {
        guard
            let directURLString = Bundle.main.object(
                forInfoDictionaryKey: "SUFeedURL"
            ) as? String
        else {
            return nil
        }

        return updateSourceFallback.appcastURLString(from: directURLString)
    }

    func updater(
        _ updater: SPUUpdater,
        willDownloadUpdate item: SUAppcastItem,
        with request: NSMutableURLRequest
    ) {
        guard let fileURL = item.fileURL else { return }
        request.url = updateSourceFallback.downloadURL(for: fileURL)
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        if updateSourceFallback.advanceAfterError(error) {
            retryUpdateCheck(updateCheck)
            return
        }

        guard isShowingManualUpdateUI else { return }
        isShowingManualUpdateUI = false
        NSApp.setActivationPolicy(.accessory)
    }

    private func retryUpdateCheck(_ updateCheck: SPUUpdateCheck) {
        switch updateCheck {
        case .updates:
            controller.checkForUpdates(nil)
        case .updatesInBackground:
            controller.updater.checkForUpdatesInBackground()
        default:
            break
        }
    }
}
