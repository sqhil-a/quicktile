import SwiftUI
import UIKit

/// One recognizer preserves the original touch as a tile enters editing. Hit testing
/// is restricted to the visible grid, so holding toolbar controls never edits a board.
struct PageHoldGesture: UIViewRepresentable {
    var enabled: Bool
    var pageScrollingEnabled: Bool
    var acceptsTouch: (CGPoint) -> Bool
    var preview: (CGPoint) -> Void
    var began: () -> Void
    var moved: (CGPoint) -> Void
    var ended: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> Anchor {
        let view = Anchor(); view.isUserInteractionEnabled = false
        view.attach = { [weak coordinator = context.coordinator] window in coordinator?.attach(window) }
        return view
    }
    func updateUIView(_ view: Anchor, context: Context) { context.coordinator.owner = self }
    static func dismantleUIView(_ view: Anchor, coordinator: Coordinator) { coordinator.attach(nil) }
    final class Anchor: UIView {
        var attach: ((UIWindow?) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); attach?(window) }
    }
    final class Press: UILongPressGestureRecognizer {
        var preview: ((CGPoint) -> Void)?
        var cleanup: (() -> Void)?
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesBegan(touches, with: event)
            if let touch = touches.first { preview?(touch.location(in: view)) }
        }
        override func reset() { super.reset(); cleanup?() }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var owner: PageHoldGesture
        private weak var window: UIWindow?
        private var active = false
        private var previewed = false
        private var scrollViews: [(UIScrollView, Bool)] = []
        private var suspendedScrolling = false
        lazy var press: Press = {
            let value = Press(target: self, action: #selector(changed(_:)))
            value.minimumPressDuration = 0.45; value.allowableMovement = 12
            value.delaysTouchesBegan = false; value.delaysTouchesEnded = false
            value.delegate = self
            value.preview = { [weak self] point in self?.previewed = true; self?.owner.preview(point) }
            value.cleanup = { [weak self] in guard let self else { return }; if self.active || self.previewed { self.owner.ended(false) }; self.active = false; self.previewed = false; self.restoreScrolling() }
            return value
        }()
        init(_ owner: PageHoldGesture) { self.owner = owner }
        func attach(_ window: UIWindow?) {
            self.window?.removeGestureRecognizer(press); self.window = window
            window?.addGestureRecognizer(press)
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard owner.enabled && owner.acceptsTouch(touch.location(in: window)) else { return false }
            scrollViews = []
            var ancestor = touch.view
            while let view = ancestor {
                if let scroll = view as? UIScrollView { scrollViews.append((scroll, scroll.isScrollEnabled)) }
                ancestor = view.superview
            }
            return true
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // SwiftUI buttons begin their press recognition immediately. Sharing
            // the hold prevents that recognizer from discarding the original touch.
            true
        }
        private func restoreScrolling() {
            if suspendedScrolling { for (view, enabled) in scrollViews { view.isScrollEnabled = enabled && owner.pageScrollingEnabled } }
            suspendedScrolling = false
            scrollViews = []
        }
        @objc private func changed(_ gesture: Press) {
            switch gesture.state {
            case .began: active = true; suspendedScrolling = true; for (view, _) in scrollViews { view.isScrollEnabled = false }; owner.began()
            case .changed: owner.moved(gesture.location(in: window))
            case .ended: owner.moved(gesture.location(in: window)); previewed = false; owner.ended(true); active = false; restoreScrolling()
            case .cancelled, .failed: previewed = false; owner.ended(false); active = false; restoreScrolling()
            default: break
            }
        }
    }
}
