import AppKit
import SwiftUI

/// Remembers where the volume control sits so the popover scroll monitor can
/// tell whether the pointer is over the control itself.
///
/// The region is read from a real `NSView` frame instead of SwiftUI
/// geometry, so it always matches the window coordinates carried by the
/// scroll event.
@MainActor
final class PopoverScrollTargets {
    private weak var volumeControlView: NSView?

    func registerVolumeControl(_ view: NSView) {
        volumeControlView = view
    }

    func unregisterVolumeControl(_ view: NSView) {
        guard volumeControlView === view else { return }
        volumeControlView = nil
    }

    func containsVolumeControl(at point: NSPoint, in window: NSWindow?) -> Bool {
        guard let window,
              let volumeControlView,
              volumeControlView.window === window else {
            return false
        }
        return volumeControlView.convert(volumeControlView.bounds, to: nil).contains(point)
    }
}

/// Marks a SwiftUI region as the volume control for scroll targeting.
struct VolumeControlScrollTarget: NSViewRepresentable {
    let targets: PopoverScrollTargets

    func makeNSView(context: Context) -> ScrollTargetView {
        let view = ScrollTargetView()
        view.targets = targets
        targets.registerVolumeControl(view)
        return view
    }

    func updateNSView(_ nsView: ScrollTargetView, context: Context) {
        nsView.targets = targets
        targets.registerVolumeControl(nsView)
    }

    static func dismantleNSView(_ nsView: ScrollTargetView, coordinator: ()) {
        nsView.targets?.unregisterVolumeControl(nsView)
    }
}

/// A transparent marker view: it reports its frame but never takes clicks,
/// so the volume slider underneath stays fully interactive.
final class ScrollTargetView: NSView {
    weak var targets: PopoverScrollTargets?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
