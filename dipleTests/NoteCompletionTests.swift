import XCTest
@testable import diple

/// What `[[` and `#` offer while they are typed.
final class NoteCompletionTests: XCTestCase {

    func testTitlesThatStartWithTheQueryComeBeforeTitlesThatContainIt() {
        let titles = ["Essay outline", "Reading list", "An essay on time", "Essays unwritten"]
        XCTAssertEqual(
            NoteCompletion.links(matching: "ess", in: titles).map(\.title),
            ["Essay outline", "Essays unwritten", "An essay on time", "ess"]
        )
    }

    func testAnEmptyQueryOffersTheMostRecentNotesAndNothingUnwritten() {
        let titles = ["One", "Two", "Three"]
        XCTAssertEqual(NoteCompletion.links(matching: "", in: titles), [.note("One"), .note("Two"), .note("Three")])
    }

    func testATitleThatExistsIsNotAlsoOfferedAsUnwritten() {
        let picks = NoteCompletion.links(matching: "roadmap", in: ["Roadmap"])
        XCTAssertEqual(picks, [.note("Roadmap")])
    }

    func testAnUnknownTitleIsOfferedAsALinkToWriteLater() {
        let picks = NoteCompletion.links(matching: "A later thought ", in: ["Roadmap"])
        XCTAssertEqual(picks, [.unwritten("A later thought")])
    }

    func testTwoNotesWithOneTitleAreOneRow() {
        XCTAssertEqual(NoteCompletion.links(matching: "", in: ["Draft", "draft", "Draft"]).count, 1)
    }

    func testMatchingIgnoresCaseAndDiacriticsInCyrillicAndLatin() {
        XCTAssertEqual(NoteCompletion.links(matching: "поля и ЧЕРНИЛА", in: ["Поля и чернила"]), [.note("Поля и чернила")])
        XCTAssertEqual(NoteCompletion.links(matching: "cafe notes", in: ["Café notes"]), [.note("Café notes")])
        // A prefix is still only part of a title: the words typed so far stay offered as a link.
        XCTAssertEqual(NoteCompletion.links(matching: "поля", in: ["Поля и чернила"]), [.note("Поля и чернила"), .unwritten("поля")])
    }

    func testTheUnwrittenRowTakesTheLastPlaceWhenTheListIsFull() {
        let titles = (1...10).map { "Idea \($0)" }
        let picks = NoteCompletion.links(matching: "Idea", in: titles, limit: 3)
        XCTAssertEqual(picks, [.note("Idea 1"), .note("Idea 2"), .unwritten("Idea")])
    }

    func testTagsMatchByPrefixOnTheNormalisedWordAndOfferTheNewOneLast() {
        let vocabulary = ["reading", "research", "method", "Физика"]
        XCTAssertEqual(
            NoteCompletion.tags(matching: "re", in: vocabulary),
            [.existing("reading"), .existing("research"), .new("re")]
        )
        XCTAssertEqual(NoteCompletion.tags(matching: "ФИЗ", in: vocabulary), [.existing("физика"), .new("физ")])
    }

    func testATagAlreadyInTheVocabularyIsNotOfferedAsNew() {
        XCTAssertEqual(NoteCompletion.tags(matching: "Method", in: ["method"]), [.existing("method")])
    }

    func testAKoreanTagIsATag() {
        XCTAssertEqual(NoteCompletion.tags(matching: "독", in: ["독서"]), [.existing("독서"), .new("독")])
    }

    func testTheNewTagKeepsItsPlaceWhenTheVocabularyFillsTheList() {
        let vocabulary = (1...10).map { "tag\($0)" }
        let picks = NoteCompletion.tags(matching: "tag", in: vocabulary, limit: 4)
        XCTAssertEqual(picks.count, 4)
        XCTAssertEqual(picks.last, .new("tag"))
    }

    // MARK: - Writing the choice

    // The `inout NSRange` form, not `NoteSelectionBox`: a main-actor class released on the test
    // host's synchronous main thread crashes in the isolated-deinit shim (see "Выделение в reader").
    func testChoosingALinkClosesItAndLeavesTheCaretAfterIt() {
        var text = "See [[Ro and more"
        var selection = NSRange(location: 8, length: 0)
        let context = NoteCompletionContext(kind: .link, query: "Ro", range: NSRange(location: 4, length: 4), caretRect: .zero)
        NoteEditing.complete(context, with: "Roadmap", in: &text, selection: &selection)
        XCTAssertEqual(text, "See [[Roadmap]] and more")
        XCTAssertEqual(selection, NSRange(location: 15, length: 0))
    }

    func testChoosingATagAddsOneSpaceAndNeverASecond() {
        var atEnd = "Notes on #rea"
        var endSelection = NSRange(location: 0, length: 0)
        let endContext = NoteCompletionContext(kind: .tag, query: "rea", range: NSRange(location: 9, length: 4), caretRect: .zero)
        NoteEditing.complete(endContext, with: "reading", in: &atEnd, selection: &endSelection)
        XCTAssertEqual(atEnd, "Notes on #reading ")

        var midLine = "#rea then more"
        var midSelection = NSRange(location: 0, length: 0)
        let midContext = NoteCompletionContext(kind: .tag, query: "rea", range: NSRange(location: 0, length: 4), caretRect: .zero)
        NoteEditing.complete(midContext, with: "reading", in: &midLine, selection: &midSelection)
        XCTAssertEqual(midLine, "#reading then more")
        XCTAssertEqual(midSelection, NSRange(location: 8, length: 0))
    }
}
