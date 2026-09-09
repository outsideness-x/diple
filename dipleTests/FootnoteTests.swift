import XCTest
@testable import diple

/// What Readium hands over for a tapped note is the note element's inner HTML and the marker
/// anchor's inner HTML — see `EPUBNavigatorViewController.getNoteData`. Every string in these
/// tests is shaped the way real books shape them.
final class FootnoteTests: XCTestCase {
    private func footnote(_ content: String, referrer: String? = nil) -> Footnote? {
        FootnoteParser.footnote(id: "notes.xhtml#fn1", content: content, referrer: referrer)
    }

    func testAParagraphBecomesTheNote() {
        let note = footnote("<p>The lanterns were paper until 1951.</p>", referrer: "<sup>1</sup>")
        XCTAssertEqual(note?.marker, "1")
        XCTAssertEqual(note?.paragraphs, ["The lanterns were paper until 1951."])
    }

    func testEveryParagraphSurvivesInOrder() {
        let note = footnote("<p>First.</p><p>Second.</p>")
        XCTAssertEqual(note?.paragraphs, ["First.", "Second."])
    }

    /// The way back is a control, and this card is what makes it unnecessary.
    func testTheBacklinkIsNotPartOfTheNote() {
        let note = footnote(
            """
            <p>The harbour office kept the count until 1974.
            <a epub:type="backlink" href="ch1.xhtml#fnref2">↩</a></p>
            """
        )
        XCTAssertEqual(note?.paragraphs, ["The harbour office kept the count until 1974."])
    }

    func testANoteThatRepeatsItsOwnNumberOnlySaysItOnce() {
        XCTAssertEqual(
            footnote("<p>1. The lanterns were paper.</p>", referrer: "<sup>1</sup>")?.paragraphs,
            ["The lanterns were paper."]
        )
        XCTAssertEqual(
            footnote("<p>1 The lanterns were paper.</p>", referrer: "<sup>1</sup>")?.paragraphs,
            ["The lanterns were paper."]
        )
    }

    /// The boundary check, which is the whole of the care that rule needs.
    func testANoteOpeningOnAYearKeepsItsCentury() {
        XCTAssertEqual(
            footnote("<p>1938 was the year of the last count.</p>", referrer: "<sup>1</sup>")?.paragraphs,
            ["1938 was the year of the last count."]
        )
    }

    /// Only what a publisher sets *between* a number and its note is dropped.
    func testANoteOpeningOnAQuotationKeepsItsQuotationMark() {
        XCTAssertEqual(
            footnote("<p>“Ephemeral,” he wrote, and left it there.</p>", referrer: "<sup>4</sup>")?.paragraphs,
            ["“Ephemeral,” he wrote, and left it there."]
        )
    }

    func testBracketsAroundAMarkerAreNotTheMarker() {
        XCTAssertEqual(footnote("<p>A note.</p>", referrer: "[12]")?.marker, "12")
        XCTAssertEqual(footnote("<p>A note.</p>", referrer: "<sup>*</sup>")?.marker, "*")
    }

    /// A publisher who used a phrase as the link did not give the note a marker, and printing
    /// the phrase where a numeral belongs would put a sentence in the margin.
    func testAPhraseIsNotAMarker() {
        XCTAssertNil(footnote("<p>A note.</p>", referrer: "see the appendix on lanterns")?.marker)
    }

    func testMarkupWithNoWordsInItIsNotAFootnote() {
        XCTAssertNil(footnote("<p></p>"))
        XCTAssertNil(footnote(""))
        XCTAssertNil(footnote("<p>1</p>", referrer: "<sup>1</sup>"))
    }

    /// Russian and Korean notes have to come back as themselves — the parser must not be a
    /// parser of Latin text that happens to run on everything else.
    func testCyrillicAndHangulNotesSurvive() {
        XCTAssertEqual(
            footnote("<p>Фонари были бумажными до 1951 года.</p>")?.paragraphs,
            ["Фонари были бумажными до 1951 года."]
        )
        XCTAssertEqual(
            footnote("<p>등불은 1951년까지 종이로 만들었다.</p>")?.paragraphs,
            ["등불은 1951년까지 종이로 만들었다."]
        )
    }

    /// A note kept in a list, a table or a blockquote is still a note. This is the app's one
    /// definition of a paragraph, shared with the content index and Second Read.
    func testABlockThatIsNotAParagraphIsStillTheNote() {
        XCTAssertEqual(
            footnote("<ul><li>Clear, then fog.</li><li>Rain from the west.</li></ul>")?.paragraphs,
            ["Clear, then fog.", "Rain from the west."]
        )
    }
}
