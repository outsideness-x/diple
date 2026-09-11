import XCTest
@testable import diple

@MainActor
final class InkHighlightTests: XCTestCase {
    private var css: String { InkHighlightCSS.stylesheet }

    /// A highlight that is not new must be exactly what it always was: flat colour, no
    /// animation, nothing to replay. Every reflow re-lays out every decoration on the page, so
    /// a rule that reached the resting state would redraw the whole page's marks on every page
    /// turn. `Scripts/ink-stroke-profile.swift` measures the same claim in a real WebKit.
    func testARestingHighlightIsPlainColourWithNothingToPlay() {
        let resting = InkHighlightCSS.element(ink: "rgba(255, 214, 10, 0.3)", isFresh: false)
        XCTAssertFalse(resting.contains(InkHighlightCSS.freshAttribute))
        XCTAssertTrue(resting.contains("--diple-ink: rgba(255, 214, 10, 0.3)"))

        // The animation is reachable only through the freshness attribute.
        let animationLines = css
            .components(separatedBy: .newlines)
            .filter { $0.contains("animation:") }
        XCTAssertFalse(animationLines.isEmpty)
        XCTAssertTrue(
            animationLines.allSatisfy { $0.contains("diple-ink-stroke") || $0.contains("animation: none") },
            "the only animation in this stylesheet is the stroke, and the only other value is its absence"
        )
    }

    func testAFreshHighlightCarriesTheMarkThatSelectsTheStroke() {
        let fresh = InkHighlightCSS.element(ink: "rgba(48, 209, 88, 0.3)", isFresh: true)
        XCTAssertTrue(fresh.contains("\(InkHighlightCSS.freshAttribute)=\"\(InkHighlightCSS.freshValue)\""))
        XCTAssertTrue(css.contains("[\(InkHighlightCSS.freshAttribute)=\"\(InkHighlightCSS.freshValue)\"]"))
    }

    /// Every saved highlight was invisible on the page. diple sets a page colour in every
    /// theme, and ReadiumCSS answers that with `:root[style*="--USER__backgroundColor"] *
    /// { background-color: transparent !important; }` — a stylesheet fill loses to it however it
    /// is written. Only an inline `!important` outranks it, which is what Readium's own template
    /// does. `Scripts/ink-stroke-profile.swift` checks the same thing against the real CSS.
    func testTheRestingFillIsInlineAndImportantSoReadiumsThemeResetCannotClearIt() {
        let resting = InkHighlightCSS.element(ink: "rgba(255, 214, 10, 0.3)", isFresh: false)
        XCTAssertTrue(resting.contains("background-color: rgba(255, 214, 10, 0.3) !important;"))

        // A stylesheet fill would be dead code that looks like the thing doing the work.
        XCTAssertFalse(css.contains("background-color: var(--diple-ink)"))
    }

    /// The wet mark must not carry the flat fill: it would sit under the stroke from the first
    /// frame, and nothing would appear to be drawn.
    func testAFreshHighlightHasNoFlatFillUnderTheStroke() {
        let fresh = InkHighlightCSS.element(ink: "rgba(48, 209, 88, 0.3)", isFresh: true)
        XCTAssertFalse(fresh.contains("background-color"))
    }

    /// The lines are staggered, and the stagger stops. A twelve-line passage is a page, and a
    /// stagger that kept going would land its last line a second and a half after the tap.
    func testTheStaggerRunsDownTheLinesAndThenStops() {
        for line in 0..<InkHighlightCSS.staggeredLines {
            XCTAssertTrue(
                css.contains("nth-child(\(line + 1))") && css.contains("animation-delay: \(line * InkHighlightCSS.lineStagger)ms;"),
                "line \(line + 1) has no delay of its own"
            )
        }
        let capped = (InkHighlightCSS.staggeredLines - 1) * InkHighlightCSS.lineStagger
        XCTAssertTrue(
            css.contains("nth-child(n + \(InkHighlightCSS.staggeredLines + 1))"),
            "every line past the cap shares the last delay"
        )
        XCTAssertTrue(css.contains("animation-delay: \(capped)ms;"))
    }

    /// The whole point of the overshoot: the soft leading edge has to finish *past* the end of
    /// the box, or every line settles with a fade at its right margin.
    func testTheStrokeSettlesPastTheEndSoTheMarkIsFlat() {
        XCTAssertTrue(css.contains("to { background-size: 130% 100%; }"))
        XCTAssertTrue(css.contains("from { background-size: 0% 100%; }"))
    }

    /// The web view follows the system setting, so this is the whole of the Reduce Motion
    /// story — there is nothing to wire on the Swift side, and nothing that can fall out of
    /// step with it.
    func testReduceMotionGetsTheMarkWithoutTheStroke() {
        XCTAssertTrue(css.contains("@media (prefers-reduced-motion: reduce)"))
        guard let range = css.range(of: "@media (prefers-reduced-motion: reduce)") else {
            return XCTFail("no reduced-motion block")
        }
        let block = String(css[range.lowerBound...])
        XCTAssertTrue(block.contains("animation: none;"))
        // The stroke's own last frame, not a background-color — ReadiumCSS clears those.
        XCTAssertTrue(block.contains("background-size: 130% 100%;"))
    }

    /// The flag has to outlast the ink, or the second write lands mid-stroke and the mark
    /// finishes by snapping to flat.
    func testTheInkIsWetForAsLongAsTheStrokeTakes() {
        let lastLineFinishes = (InkHighlightCSS.staggeredLines - 1) * InkHighlightCSS.lineStagger
            + InkHighlightCSS.lineDuration
        XCTAssertEqual(InkHighlightCSS.duration, lastLineFinishes)
        XCTAssertEqual(InkHighlight.duration, InkHighlightCSS.duration)
    }
}
