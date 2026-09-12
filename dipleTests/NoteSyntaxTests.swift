import XCTest
@testable import diple

/// What the editor believes each stretch of Markdown means while it is being typed.
///
/// Every assertion is about ranges over the same characters: the styling never changes a byte,
/// so the only way it can be wrong is by pointing at the wrong ones.
final class NoteSyntaxTests: XCTestCase {

    private func spans(_ text: String, restyling range: NSRange? = nil) -> [NoteSyntaxSpan] {
        NoteSyntax.spans(in: text as NSString, restyling: range)
    }

    /// The substrings a role covers, in order — readable in a failure message, unlike ranges.
    private func words(_ text: String, _ role: NoteSyntaxRole, restyling range: NSRange? = nil) -> [String] {
        let source = text as NSString
        return spans(text, restyling: range)
            .filter { $0.role == role }
            .map { source.substring(with: $0.range) }
    }

    func testAHeadingIsItsWholeLineWithItsHashesDimmed() {
        let text = "## The idea\nplain"
        XCTAssertEqual(words(text, .heading(level: 2)), ["## The idea"])
        XCTAssertEqual(words(text, .marker), ["## "])
    }

    func testAHashAgainstAWordIsATagNotAHeading() {
        let text = "#reading list"
        XCTAssertTrue(words(text, .heading(level: 1)).isEmpty)
        XCTAssertEqual(words(text, .link), ["#reading"])
    }

    func testStrengthAndEmphasisCoverTheirMarkersAndDimThem() {
        let text = "a **bold** and *soft* word"
        XCTAssertEqual(words(text, .strong), ["**bold**"])
        XCTAssertEqual(words(text, .emphasis), ["*soft*"])
        XCTAssertEqual(words(text, .marker), ["**", "**", "*", "*"])
    }

    func testArithmeticAndSnakeCaseAreNotEmphasis() {
        XCTAssertTrue(words("2 * 3 * 4", .emphasis).isEmpty)
        XCTAssertTrue(words("call file_name_here now", .emphasis).isEmpty)
    }

    func testNothingInsideACodeSpanIsReadAsMarkdown() {
        let text = "run `**not bold** #nottag` now"
        XCTAssertEqual(words(text, .code), ["`**not bold** #nottag`"])
        XCTAssertTrue(words(text, .strong).isEmpty)
        XCTAssertTrue(words(text, .link).isEmpty)
    }

    func testAFenceMakesEveryLineUntilItClosesCode() {
        let text = "before\n```swift\nlet x = **1**\n# not a heading\n```\nafter **b**"
        XCTAssertEqual(words(text, .code), ["let x = **1**", "# not a heading"])
        XCTAssertTrue(words(text, .heading(level: 1)).isEmpty)
        XCTAssertEqual(words(text, .strong), ["**b**"])
    }

    func testAFenceBelowTheEditStillKnowsWhichSideALineIsOn() {
        let text = "```\ninside\n```\noutside"
        let inside = (text as NSString).range(of: "inside")
        let range = NoteSyntax.restyleRange(for: inside, in: text as NSString)
        // Any fence in the note restyles all of it.
        XCTAssertEqual(range, NSRange(location: 0, length: (text as NSString).length))
        XCTAssertEqual(words(text, .code, restyling: range), ["inside"])
    }

    func testAQuoteCarriesItsLineAndACalloutLabelIsNotation() {
        let text = "> [!NOTE] Keep this"
        XCTAssertEqual(words(text, .quote), ["> [!NOTE] Keep this"])
        XCTAssertEqual(words(text, .marker), ["> ", "[!NOTE] "])
    }

    func testATaskBoxIsItsOwnSpanAndATickedTaskIsStruckThrough() {
        let text = "- [ ] open\n- [x] finished"
        let tasks = spans(text).filter {
            if case .task = $0.role { return true }
            return false
        }
        XCTAssertEqual(tasks.map(\.role), [.task(isDone: false), .task(isDone: true)])
        XCTAssertEqual(words(text, .done), ["finished"])
        XCTAssertEqual(words(text, .listMarker), ["- ", "- "])
    }

    func testNumberedAndBulletedItemsDimOnlyTheirMarkers() {
        let text = "1. first\n  * nested"
        XCTAssertEqual(words(text, .listMarker), ["1. ", "* "])
    }

    func testWikiLinksAndMarkdownLinksColourTheWordsNotTheAddress() {
        let text = "See [[Essay outline]] and [the source](https://example.com)."
        XCTAssertEqual(words(text, .link), ["Essay outline", "the source"])
        XCTAssertEqual(words(text, .marker), ["[[", "]]", "[", "](https://example.com)"])
    }

    func testADividerIsAllNotation() {
        XCTAssertEqual(words("---", .marker), ["---"])
        XCTAssertTrue(words("-- not a rule", .marker).isEmpty)
    }

    /// Ranges are UTF-16, the unit `NSTextStorage` counts in. A span measured in characters
    /// would drift one step to the left after every emoji and land inside a Hangul word.
    func testRangesStayOnTheirWordsAfterEmojiAndHangul() {
        let text = "🌿 오늘 **책을** 읽었다 #독서"
        XCTAssertEqual(words(text, .strong), ["**책을**"])
        XCTAssertEqual(words(text, .link), ["#독서"])

        let cyrillic = "## Поля и чернила"
        XCTAssertEqual(words(cyrillic, .heading(level: 2)), ["## Поля и чернила"])
    }

    func testRestylingTouchesOnlyTheLinesOfTheEdit() {
        let text = "# One\nsecond **line**\n# Three"
        let source = text as NSString
        let edit = source.range(of: "line")
        let range = NoteSyntax.restyleRange(for: edit, in: source)
        XCTAssertEqual(source.substring(with: range), "second **line**\n")

        let restyled = spans(text, restyling: range)
        XCTAssertFalse(restyled.contains { $0.role == .heading(level: 1) })
        XCTAssertTrue(restyled.contains { $0.role == .strong })
        XCTAssertTrue(restyled.allSatisfy { NSIntersectionRange($0.range, range).length == $0.range.length })
    }

    func testAnEditAtTheVeryEndOfTheNoteRestylesTheLastLine() {
        let text = "first\n# last"
        let source = text as NSString
        let range = NoteSyntax.restyleRange(for: NSRange(location: source.length, length: 0), in: source)
        XCTAssertEqual(source.substring(with: range), "# last")
        XCTAssertEqual(words(text, .heading(level: 1), restyling: range), ["# last"])
    }

    func testAnEmptyNoteHasNothingToStyle() {
        XCTAssertTrue(spans("").isEmpty)
        XCTAssertEqual(NoteSyntax.restyleRange(for: NSRange(location: 0, length: 0), in: ""), NSRange(location: 0, length: 0))
    }

    func testNoSpanEverCrossesALine() {
        let text = "**open\nclose** and `tick\ntock` and [[a\nb]]"
        let source = text as NSString
        for span in spans(text) {
            XCTAssertFalse(source.substring(with: span.range).contains("\n"), "\(span)")
        }
    }
}
