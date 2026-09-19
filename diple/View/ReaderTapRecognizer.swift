import CoreGraphics
import Foundation
import ReadiumNavigator

/// Decides which touches on the page are the tap that raises the reader's controls — and, above
/// everything else, keeps deciding.
///
/// **Why the app recognises this itself.** Readium already recognises a tap and reports it as
/// `didTapAt`, through `ActivatePointerObserver`. That recogniser keeps a set of pointers it is
/// waiting on, and a pointer leaves the set only when its own `up` or `cancel` arrives:
///
/// ```swift
/// case var (.failed(activePointers), .up), var (.failed(activePointers), .cancel):
///     activePointers.remove(id)
///     if activePointers.isEmpty { return .idle } else { return .failed(activePointers) }
/// ```
///
/// So one pointer whose release never arrives leaves the set permanently non-empty, `.idle`
/// becomes unreachable, and with it `.recognized`: **no tap is ever recognised again** for as
/// long as the book stays open. Closing and reopening the book is the only way back, which is
/// exactly how this was reported — the controls stop answering the page part-way through a long
/// sitting and answer again next time the book is opened.
///
/// A release goes missing more often than it sounds, because the page drops pointer events on
/// purpose. `gestures.js` returns early for any event over a decoration, and every saved passage
/// is a decoration; `EPUBSpreadView.didReceivePointerEvent` drops any event whose target is an
/// interactive element, and a footnote marker is one; and this app's own `ReaderFigureScript`
/// stops them over an illustration. A touch that goes down on prose and comes up a few points
/// away on a highlight, a marker or a picture is an ordinary, frequent thing in a book that is
/// being marked up — and it is all it takes.
///
/// **What this does instead.** It holds at most one candidate touch: the one that went down last.
/// A `down` overwrites whatever was there, so a touch whose release never arrives is forgotten by
/// the next one rather than remembered forever. There is no set to drain and no state that a
/// missing event can leave behind.
///
/// That also settles the second finger honestly. A thumb resting on the edge of the page and a
/// finger tapping with it are indistinguishable, from the event stream alone, from a touch whose
/// release went missing — and of the two readings, "the tap still works" is the one that never
/// leaves a reader stuck. A pinch is not a tap for the reason it should not be: it moves.
///
/// It sees the same events Readium's recogniser sees, after the same filtering, so a tap on a
/// link, a decoration or an illustration still does not raise the controls.
@MainActor
final class ReaderTapRecognizer {
    /// How far the finger may travel and still be a tap.
    ///
    /// UIKit's own allowance for `UITapGestureRecognizer`, measured from where the touch went
    /// down rather than between consecutive reports. Readium's recogniser fails on **1 pt**
    /// between two `move` events, which the hand of someone holding a phone exceeds routinely:
    /// the stricter rule loses taps that every other control on the device accepts.
    static let allowableMovement: CGFloat = 10

    /// A touch, as this recogniser needs it: which finger, what it did, and where.
    ///
    /// Its own type rather than Readium's `PointerEvent` because that struct has no public
    /// initialiser, so nothing outside the toolkit can make one — and a recogniser that cannot
    /// be driven from a test is a recogniser whose whole point, that it never jams, is a claim
    /// rather than a fact.
    struct Touch {
        enum Phase {
            case down
            case move
            case up
            case cancel
        }

        let id: AnyHashable
        let phase: Phase
        let location: CGPoint

        init(id: AnyHashable, phase: Phase, location: CGPoint) {
            self.id = id
            self.phase = phase
            self.location = location
        }
    }

    private var candidate: (id: AnyHashable, origin: CGPoint)?

    /// One candidate and nothing else is torn down here, so the isolation is declined rather
    /// than back-deployed — see `ReaderViewModel.deinit` for the libmalloc abort that an
    /// isolated `deinit` runs into when the object is released from a plain main thread, which
    /// is every one of this type's own tests.
    nonisolated deinit {}

    /// Feeds one touch in. Returns where the tap landed, on the report that completes one.
    func receive(_ touch: Touch) -> CGPoint? {
        switch touch.phase {
        case .down:
            // The newest touch is the candidate, always. A touch already being watched is
            // forgotten here rather than remembered: it is either a finger resting on the
            // screen — whose owner is tapping with another one and expects that to work — or a
            // touch whose release the page swallowed, which must not outlive the next one.
            candidate = (touch.id, touch.location)
            return nil

        case .move:
            guard let candidate, candidate.id == touch.id else { return nil }
            if distance(from: candidate.origin, to: touch.location) > Self.allowableMovement {
                self.candidate = nil
            }
            return nil

        case .up:
            guard let candidate, candidate.id == touch.id else { return nil }
            self.candidate = nil
            guard distance(from: candidate.origin, to: touch.location) <= Self.allowableMovement
            else { return nil }
            return touch.location

        case .cancel:
            if candidate?.id == touch.id { candidate = nil }
            return nil
        }
    }

    private func distance(from origin: CGPoint, to point: CGPoint) -> CGFloat {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// Feeds `ReaderTapRecognizer` from a navigator's input stream.
///
/// Registered with `addObserver`, which is the toolkit's own door for this. The observer never
/// consumes an event — everything Readium does with pointers on its side, it keeps doing.
@MainActor
final class ReaderTapObserver: InputObserving {
    private let recognizer = ReaderTapRecognizer()
    /// Handed the tap and the moment its touch went down. The second argument is what lets the
    /// reader tell a tap from the tap that dismissed a selection: the page takes a selection
    /// down on touch-down and says so through its own channel, so the only thing tying the two
    /// together is that they happened inside one touch. See `Coordinator.pageWasTapped`.
    private let onTap: (CGPoint, ContinuousClock.Instant) -> Void
    private var touchBeganAt = ContinuousClock.now

    init(onTap: @escaping (CGPoint, ContinuousClock.Instant) -> Void) {
        self.onTap = onTap
    }

    /// See `ReaderTapRecognizer.deinit`: the navigator lets its observers go from the main
    /// thread, which is exactly where an isolated `deinit` aborts.
    nonisolated deinit {}

    func didReceive(_ event: PointerEvent) async -> Bool {
        guard !shouldIgnore(event) else { return false }

        var phase: ReaderTapRecognizer.Touch.Phase = switch event.phase {
        case .down: .down
        case .move: .move
        case .up: .up
        case .cancel: .cancel
        }

        // A click with a modifier held is a shortcut meant for something else, so the touch is
        // dropped rather than started — the same exclusion Readium's own recogniser applies,
        // spelled as a cancellation because this one holds a candidate rather than a state.
        if phase == .down, event.modifiers != [] {
            phase = .cancel
        }

        if phase == .down {
            touchBeganAt = .now
        }

        if let point = recognizer.receive(
            ReaderTapRecognizer.Touch(id: event.pointer.id, phase: phase, location: event.location)
        ) {
            onTap(point, touchBeganAt)
        }
        return false
    }

    func didReceive(_ event: KeyEvent) async -> Bool { false }

    /// A mouse button other than the main one is not a tap — Readium's own exclusion.
    private func shouldIgnore(_ event: PointerEvent) -> Bool {
        if case let .mouse(pointer) = event.pointer,
           pointer.buttons != [], pointer.buttons != .main {
            return true
        }
        return false
    }
}
