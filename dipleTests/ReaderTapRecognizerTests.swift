import CoreGraphics
import XCTest
@testable import diple

/// The one thing this recogniser exists to guarantee: it never stops recognising.
///
/// The bug it replaces was not that a tap was read wrongly — it was that after one touch whose
/// release never reached the app, the reader stopped answering taps for the rest of the sitting.
/// See `ReaderTapRecognizer` for how the toolkit's own recogniser gets there.
@MainActor
final class ReaderTapRecognizerTests: XCTestCase {
    private func down(_ id: Int, _ x: CGFloat = 100, _ y: CGFloat = 100) -> ReaderTapRecognizer.Touch {
        ReaderTapRecognizer.Touch(id: id, phase: .down, location: CGPoint(x: x, y: y))
    }

    private func move(_ id: Int, _ x: CGFloat, _ y: CGFloat = 100) -> ReaderTapRecognizer.Touch {
        ReaderTapRecognizer.Touch(id: id, phase: .move, location: CGPoint(x: x, y: y))
    }

    private func up(_ id: Int, _ x: CGFloat = 100, _ y: CGFloat = 100) -> ReaderTapRecognizer.Touch {
        ReaderTapRecognizer.Touch(id: id, phase: .up, location: CGPoint(x: x, y: y))
    }

    private func cancel(_ id: Int) -> ReaderTapRecognizer.Touch {
        ReaderTapRecognizer.Touch(id: id, phase: .cancel, location: CGPoint(x: 100, y: 100))
    }

    func testATouchThatGoesDownAndUpInOnePlaceIsATap() {
        let recognizer = ReaderTapRecognizer()
        XCTAssertNil(recognizer.receive(down(1, 120, 300)))
        XCTAssertEqual(recognizer.receive(up(1, 120, 300)), CGPoint(x: 120, y: 300))
    }

    /// The case the whole type exists for. A release that never arrives — the page drops it over
    /// a highlight, a footnote marker or an illustration — must cost that one touch and nothing
    /// else. Readium's recogniser keeps the pointer in a set it waits on forever, and every tap
    /// after it is lost.
    func testATouchWhoseReleaseNeverArrivesDoesNotCostTheNextTap() {
        let recognizer = ReaderTapRecognizer()

        XCTAssertNil(recognizer.receive(down(1)), "went down on prose")
        // …and came up on a decoration, so the page never reported it.

        XCTAssertNil(recognizer.receive(down(2, 200, 400)))
        XCTAssertEqual(
            recognizer.receive(up(2, 200, 400)),
            CGPoint(x: 200, y: 400),
            "the next tap is still a tap"
        )

        XCTAssertNil(recognizer.receive(down(3, 50, 50)))
        XCTAssertEqual(recognizer.receive(up(3, 50, 50)), CGPoint(x: 50, y: 50), "and the one after it")
    }

    /// Ten touches lost in a row must still leave the eleventh working: there is no counter that
    /// can run away, because there is no counter.
    func testAnyNumberOfLostTouchesCostNothingButThemselves() {
        let recognizer = ReaderTapRecognizer()
        for id in 1 ... 10 {
            XCTAssertNil(recognizer.receive(down(id)))
        }
        XCTAssertEqual(recognizer.receive(down(11, 30, 30)), nil)
        XCTAssertEqual(recognizer.receive(up(11, 30, 30)), CGPoint(x: 30, y: 30))
    }

    func testADragIsNotATap() {
        let recognizer = ReaderTapRecognizer()
        XCTAssertNil(recognizer.receive(down(1, 100)))
        XCTAssertNil(recognizer.receive(move(1, 160)))
        XCTAssertNil(recognizer.receive(up(1, 160)), "a scroll is not a request for the controls")
    }

    /// A hand holding a phone moves. UIKit accepts 10 pt for every other control on the device,
    /// and so does this; Readium's 1 pt between consecutive reports does not.
    func testAFingerThatWobblesIsStillATap() {
        let recognizer = ReaderTapRecognizer()
        XCTAssertNil(recognizer.receive(down(1, 100, 100)))
        XCTAssertNil(recognizer.receive(move(1, 102, 101)))
        XCTAssertNil(recognizer.receive(move(1, 104, 103)))
        XCTAssertEqual(recognizer.receive(up(1, 105, 103)), CGPoint(x: 105, y: 103))
    }

    /// Travel is measured from where the touch went down, not between reports — a slow drag
    /// arrives in 1 pt steps, and step-by-step comparison would call it a tap.
    func testASlowDragIsMeasuredFromWhereItStarted() {
        let recognizer = ReaderTapRecognizer()
        XCTAssertNil(recognizer.receive(down(1, 100)))
        for x in stride(from: CGFloat(101), through: 140, by: 1) {
            XCTAssertNil(recognizer.receive(move(1, x)))
        }
        XCTAssertNil(recognizer.receive(up(1, 140)))
    }

    func testACancelledTouchIsNotATap() {
        let recognizer = ReaderTapRecognizer()
        XCTAssertNil(recognizer.receive(down(1)))
        XCTAssertNil(recognizer.receive(cancel(1)))
        XCTAssertNil(recognizer.receive(up(1)), "the system took the touch; the page did not get it")
    }

    /// A pinch is not a tap, and it is not one for the right reason: it moves.
    func testAPinchIsNotATap() {
        let recognizer = ReaderTapRecognizer()
        XCTAssertNil(recognizer.receive(down(1, 100)))
        XCTAssertNil(recognizer.receive(down(2, 200)))
        XCTAssertNil(recognizer.receive(move(1, 60)))
        XCTAssertNil(recognizer.receive(move(2, 240)))
        XCTAssertNil(recognizer.receive(up(1, 60)))
        XCTAssertNil(recognizer.receive(up(2, 240)))
    }

    /// A thumb resting on the edge of the page while the other hand taps. From the event stream
    /// this is the same shape as a touch whose release went missing, and the reading that must
    /// win is the one where the tap still works.
    func testAFingerRestingOnThePageDoesNotStopATapWithAnother() {
        let recognizer = ReaderTapRecognizer()
        XCTAssertNil(recognizer.receive(down(1, 8, 400)), "a thumb on the bezel edge")
        XCTAssertNil(recognizer.receive(down(2, 200, 300)))
        XCTAssertEqual(recognizer.receive(up(2, 200, 300)), CGPoint(x: 200, y: 300))
    }

    /// A release from a touch nobody is watching — the other half of a pair whose `down` the
    /// page swallowed — is not a tap in the middle of the page.
    func testAReleaseWithoutItsOwnTouchIsIgnored() {
        let recognizer = ReaderTapRecognizer()
        XCTAssertNil(recognizer.receive(up(9, 300, 300)))
    }
}
