import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// A horizontal swipe that leaves an enclosing `ScrollView` able to scroll.
///
/// SwiftUI's `DragGesture` cannot do this, and `simultaneousGesture` does not make it so: the
/// gesture claims *every* pan that starts on the view, vertical ones included, and the scroll
/// view never receives them. On Home that turned the resurfacing card — a sixth of the display,
/// in the middle, where a thumb naturally lands — into a band the page could not be scrolled by.
/// Measured on the simulator: the same 260 pt upward drag moved the page 200 pt when it started
/// just below the card, and moved nothing at all when it started on the quote.
///
/// Reading the direction inside `onChanged` cannot fix it, which is why the guards that were
/// already there did not. By the time a value arrives the gesture has won the touch; discarding
/// the value only means nothing happens instead of the wrong thing.
///
/// A `UIPanGestureRecognizer` can decide *before* it begins, which is the whole fix: this one
/// measures the first few points of travel and fails outright unless they are clearly
/// horizontal, so a vertical drag leaves it in `.failed` and the scroll view has the touch
/// uncontested. The verdict is delivered from `touchesMoved` rather than from a
/// `UIGestureRecognizerDelegate`, so it does not depend on SwiftUI leaving the recognizer's
/// `delegate` free for us to use.
struct HorizontalSwipe: UIGestureRecognizerRepresentable {
    var isEnabled: Bool = true
    /// Travel along x so far, in points.
    let onChanged: (CGFloat) -> Void
    /// Travel along x at the end. Zero when the system cancelled the drag, so a cancel reads
    /// as a swipe too short to act on rather than as one that has to be undone separately.
    let onEnded: (CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> HorizontalPanGestureRecognizer {
        let recognizer = HorizontalPanGestureRecognizer(target: nil, action: nil)
        recognizer.maximumNumberOfTouches = 1
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: HorizontalPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: HorizontalPanGestureRecognizer, context: Context) {
        let travel = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed:
            onChanged(travel)
        case .ended:
            onEnded(travel)
        case .cancelled:
            onEnded(0)
        default:
            break
        }
    }
}

/// A one-finger pan that only ever begins horizontally. See `HorizontalSwipe` for why.
final class HorizontalPanGestureRecognizer: UIPanGestureRecognizer {
    /// Far enough to have a direction, and short of the ~10 pt a pan needs to begin, so the
    /// refusal lands before the recognizer could take the touch away from the scroll view.
    private static let decisionDistance: CGFloat = 8
    /// The margin by which horizontal has to beat vertical, kept at the value the SwiftUI
    /// gesture used so a diagonal flick is read the way it always was.
    private static let horizontalBias: CGFloat = 1.15

    private var origin: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        origin = touches.first?.location(in: nil)
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible, let origin, let point = touches.first?.location(in: nil) {
            let travel = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
            if hypot(travel.x, travel.y) >= Self.decisionDistance,
               abs(travel.x) <= abs(travel.y) * Self.horizontalBias {
                state = .failed
                return
            }
        }
        super.touchesMoved(touches, with: event)
    }

    override func reset() {
        super.reset()
        origin = nil
    }
}

extension View {
    /// Adds a horizontal swipe that an enclosing `ScrollView` can scroll through.
    ///
    /// Use this and not `DragGesture` for anything inside a scrolling page: see
    /// `HorizontalSwipe`.
    func horizontalSwipe(
        isEnabled: Bool = true,
        onChanged: @escaping (CGFloat) -> Void,
        onEnded: @escaping (CGFloat) -> Void
    ) -> some View {
        gesture(HorizontalSwipe(isEnabled: isEnabled, onChanged: onChanged, onEnded: onEnded))
    }
}
