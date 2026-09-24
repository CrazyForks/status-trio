import AppKit
import QuartzCore

/// Presents steady animation frames through a single layer attached to the
/// status-bar button, avoiding an `NSStatusBarButton.image` assignment per tick.
@MainActor
final class StatusBarAnimationLayerPresenter {
    enum DisplayResult: Equatable {
        case installed
        case updated
    }

    private weak var hostView: NSView?
    private var contentsLayer: CALayer?
    private var shouldRestoreLayerBacking = false

    func display(
        _ image: CGImage,
        in view: NSView,
        backingScale: CGFloat
    ) -> DisplayResult? {
        guard backingScale.isFinite, backingScale > 0 else { return nil }

        if hostView !== view || contentsLayer == nil {
            clear()
            let restoreLayerBacking = !view.wantsLayer
            view.wantsLayer = true
            guard let parentLayer = view.layer else {
                if restoreLayerBacking { view.wantsLayer = false }
                return nil
            }

            let layer = CALayer()
            layer.contentsGravity = .resizeAspect
            layer.actions = [
                "bounds": NSNull(),
                "contents": NSNull(),
                "position": NSNull()
            ]
            parentLayer.addSublayer(layer)
            contentsLayer = layer
            hostView = view
            shouldRestoreLayerBacking = restoreLayerBacking
            update(layer, image: image, view: view, backingScale: backingScale)
            return .installed
        }

        guard let contentsLayer else { return nil }
        update(contentsLayer, image: image, view: view, backingScale: backingScale)
        return .updated
    }

    var isInstalled: Bool { contentsLayer != nil }

    func clear() {
        let previousHostView = hostView
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentsLayer?.removeFromSuperlayer()
        CATransaction.commit()
        contentsLayer = nil
        hostView = nil

        if shouldRestoreLayerBacking {
            previousHostView?.wantsLayer = false
        }
        shouldRestoreLayerBacking = false
    }

    private func update(
        _ layer: CALayer,
        image: CGImage,
        view: NSView,
        backingScale: CGFloat
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = view.bounds
        layer.contentsScale = backingScale
        layer.contents = image
        CATransaction.commit()
    }
}
