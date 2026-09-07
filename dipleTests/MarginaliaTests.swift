import XCTest
@testable import diple

/// One board over notes and passages.
///
/// What is worth proving is the narrowing, not the layout: that a note and a passage are the
/// same kind of row to every control, that the number printed on a chip is the number pressing
/// it produces, and that the two facet axes mean what the chips promise — any of these sources,
/// all of these tags.
final class MarginaliaTests: XCTestCase {

    // MARK: - Fixtures

    private let sapiens = Book(id: "sapiens", title: "Sapiens", author: "Harari", filePath: "Books/s/s.epub")
    private let dune = Book(id: "dune", title: "Dune", author: "Herbert", filePath: "Books/d/d.epub")

    private func note(
        _ id: String,
        body: String = "a thought",
        title: String? = nil,
        book: Book? = nil,
        tags: [String] = [],
        updated: Date = Date(timeIntervalSince1970: 1_000_000),
        created: Date? = nil
    ) -> MarginaliaEntry {
        .note(
            NoteItem(
                note: Note(
                    id: id,
                    title: title,
                    body: body,
                    bookId: book?.id,
                    createdAt: created ?? updated,
                    updatedAt: updated
                ),
                tags: tags,
                book: book
            )
        )
    }

    private func passage(
        _ id: String,
        text: String = "a saved sentence",
        book: Book,
        comment: String? = nil,
        tags: [String] = [],
        created: Date = Date(timeIntervalSince1970: 1_000_000)
    ) -> MarginaliaEntry {
        .passage(
            PassageItem(
                highlight: Highlight(
                    id: id,
                    bookId: book.id,
                    locator: "{}",
                    text: text,
                    comment: comment,
                    createdAt: created,
                    bookTitle: book.title,
                    bookAuthor: book.author
                ),
                tags: tags,
                book: book
            )
        )
    }

    private func snapshot(
        _ entries: [MarginaliaEntry],
        _ controls: MarginaliaBoard.Controls = .init(),
        now: Date = Date(timeIntervalSince1970: 1_000_000)
    ) -> MarginaliaBoard.Snapshot {
        MarginaliaBoard.snapshot(
            entries: entries,
            books: [sapiens, dune],
            controls: controls,
            now: now
        )
    }

    // MARK: - One catalogue

    /// The identifiers of the two tables are independent, and a `ForEach` silently drops a
    /// duplicate row rather than complaining about one.
    func testANoteAndAPassageSharingAnIdAreStillTwoRows() {
        let entries = [note("same"), passage("same", book: dune)]
        XCTAssertEqual(Set(entries.map(\.id)).count, 2)
    }

    /// A passage outlives the book it came from, and the snapshot taken when it was saved is
    /// the only name left to file it under.
    func testAPassageWhoseBookIsGoneKeepsItsName() {
        let orphan = MarginaliaEntry.passage(
            PassageItem(
                highlight: Highlight(
                    id: "h", bookId: "gone", locator: "{}", text: "text",
                    bookTitle: "A Deleted Book", bookAuthor: "Someone"
                ),
                tags: [],
                book: nil
            )
        )
        XCTAssertEqual(orphan.bookTitle, "A Deleted Book")
        XCTAssertEqual(orphan.bookId, "gone")
    }

    // MARK: - Scope

    func testScopeCountsAreWhatSwitchingToThemShows() {
        let entries = [
            note("n1", tags: ["physics"]),
            note("n2"),
            passage("p1", book: sapiens, tags: ["physics"]),
            passage("p2", book: dune)
        ]
        let narrowed = MarginaliaBoard.Controls(facets: MarginaliaFacets(tags: ["physics"]))
        let shot = snapshot(entries, narrowed)

        XCTAssertEqual(shot.writtenCount, 1)
        XCTAssertEqual(shot.savedCount, 1)

        let written = snapshot(entries, MarginaliaBoard.Controls(scope: .written, facets: narrowed.facets))
        XCTAssertEqual(written.results.count, shot.writtenCount)
    }

    // MARK: - Facets

    /// Two tags is "both words". An entry carrying one of them is not an answer to a question
    /// that named two.
    func testTagsAreIntersected() {
        let entries = [
            note("both", tags: ["physics", "essay"]),
            note("one", tags: ["physics"]),
            note("other", tags: ["essay"])
        ]
        let shot = snapshot(entries, .init(facets: MarginaliaFacets(tags: ["physics", "essay"])))
        XCTAssertEqual(shot.results.map(\.id), ["note:both"])
    }

    /// Two sources is "either shelf". Nothing is in two places at once, so intersecting them
    /// could only ever return nothing.
    func testSourcesAreUnioned() {
        let entries = [
            passage("p1", book: sapiens),
            passage("p2", book: dune),
            note("n1")
        ]
        let shot = snapshot(entries, .init(facets: MarginaliaFacets(bookIds: ["sapiens", "dune"])))
        XCTAssertEqual(Set(shot.results.map(\.id)), ["passage:p1", "passage:p2"])
    }

    /// The whole reason the reader is never told the AND/OR rule: the number on the chip has
    /// already answered it.
    func testATagChipCountsExactlyWhatPressingItLeaves() {
        let entries = [
            note("a", tags: ["physics", "essay"]),
            note("b", tags: ["physics"]),
            passage("c", book: sapiens, tags: ["physics", "essay"]),
            passage("d", book: dune, tags: ["essay"])
        ]
        let before = snapshot(entries, .init(facets: MarginaliaFacets(tags: ["physics"])))
        let essay = before.tagOptions.first { $0.kind == .tag("essay") }
        XCTAssertEqual(essay?.count, 2)

        let after = snapshot(entries, .init(facets: MarginaliaFacets(tags: ["physics", "essay"])))
        XCTAssertEqual(after.results.count, 2)
    }

    /// A source chip is tallied with the source filter lifted, because adding one widens the
    /// result rather than narrowing it.
    func testASourceChipCountsWhatThatSourceBrings() {
        let entries = [
            passage("p1", book: sapiens),
            passage("p2", book: sapiens),
            passage("p3", book: dune)
        ]
        let shot = snapshot(entries, .init(facets: MarginaliaFacets(bookIds: ["dune"])))
        let sapiensChip = shot.sourceOptions.first { $0.kind == .source("sapiens") }
        XCTAssertEqual(sapiensChip?.count, 2)
        XCTAssertEqual(shot.results.count, 1)
    }

    /// An unchosen chip at zero is a dead end; a chosen one at zero is the reason the board is
    /// empty, and taking it away would leave a blank page with no way back.
    func testAChosenChipSurvivesItsOwnCountFallingToNothing() {
        let entries = [note("a", tags: ["physics"]), note("b", tags: ["essay"])]
        let shot = snapshot(entries, .init(facets: MarginaliaFacets(tags: ["physics", "essay"])))

        XCTAssertTrue(shot.results.isEmpty)
        let labels = shot.facetOptions.map(\.label)
        XCTAssertTrue(labels.contains("physics"))
        XCTAssertTrue(labels.contains("essay"))
        XCTAssertTrue(shot.facetOptions.allSatisfy(\.isSelected))
    }

    func testChosenChipsArePrintedBeforeOfferedOnes() {
        let entries = [
            note("a", tags: ["physics", "essay"]),
            note("b", tags: ["physics"]),
            note("c", tags: ["physics"])
        ]
        let shot = snapshot(entries, .init(facets: MarginaliaFacets(tags: ["essay"])))
        XCTAssertEqual(shot.facetOptions.first?.label, "essay")
        XCTAssertTrue(shot.facetOptions.first?.isSelected == true)
    }

    // MARK: - Lenses

    /// Unsorted asks a different question of each kind: a note with no tag and no source has
    /// not been filed, while a passage always has a source, so what marks it unsorted is that
    /// the reader never came back to it.
    func testUnsortedMeansSomethingDifferentForANoteAndAPassage() {
        XCTAssertTrue(note("bare").isUnsorted)
        XCTAssertFalse(note("filed", book: sapiens).isUnsorted)
        XCTAssertFalse(note("tagged", tags: ["x"]).isUnsorted)

        XCTAssertTrue(passage("bare", book: sapiens).isUnsorted)
        XCTAssertFalse(passage("commented", book: sapiens, comment: "yes").isUnsorted)
        XCTAssertFalse(passage("tagged", book: sapiens, tags: ["x"]).isUnsorted)
    }

    /// A comment that is only whitespace is not a comment. Blank input is normalised away at
    /// the database boundary, but an imported record can still arrive holding spaces.
    func testAWhitespaceCommentDoesNotCountAsHavingComeBack() {
        XCTAssertTrue(passage("p", book: sapiens, comment: "   \n ").isUnsorted)
    }

    func testALensOfferingNothingIsNotOffered() {
        let entries = [note("a", tags: ["x"], updated: Date(timeIntervalSince1970: 0))]
        let shot = snapshot(entries, .init(), now: Date(timeIntervalSince1970: 10_000_000))
        XCTAssertFalse(shot.lensOptions.contains { $0.lens == .recent })
        XCTAssertFalse(shot.lensOptions.contains { $0.lens == .fromLibrary })
    }

    // MARK: - The search field

    func testTheFieldReadsHashAndAtAsConstraints() {
        let query = MarginaliaQuery.parse("gravity #physics @sapiens waves")
        XCTAssertEqual(query.text, "gravity waves")
        XCTAssertEqual(query.tagPrefixes, ["physics"])
        XCTAssertEqual(query.sourcePrefixes, ["sapiens"])
    }

    /// The operator has to work while it is still half typed, or it is a trick you have to
    /// know rather than a way to type.
    func testAHalfTypedTagNarrowsByPrefix() {
        let entries = [note("a", tags: ["objection"]), note("b", tags: ["essay"])]
        let shot = snapshot(entries, .init(rawQuery: "#obj"))
        XCTAssertEqual(shot.results.map(\.id), ["note:a"])
    }

    /// A `#` inside a URL and an `@` inside an address are text the reader is searching for.
    func testOnlyATokenOpeningAWordAtTheCaretIsAnOperator() {
        XCTAssertNil(MarginaliaQuery.activeToken(in: "read docs#section"))
        XCTAssertNil(MarginaliaQuery.activeToken(in: "#physics "))
        XCTAssertEqual(MarginaliaQuery.activeToken(in: "note #phy"), .tag("phy"))
        XCTAssertEqual(MarginaliaQuery.activeToken(in: "@sap"), .source("sap"))
    }

    func testChoosingASuggestionTakesTheTokenBackOutOfTheField() {
        XCTAssertEqual(MarginaliaQuery.removingActiveToken(from: "gravity #phy"), "gravity")
        XCTAssertEqual(MarginaliaQuery.removingActiveToken(from: "#phy"), "")
        XCTAssertEqual(MarginaliaQuery.removingActiveToken(from: "gravity "), "gravity ")
    }

    func testTheFieldSearchesAPassagesCommentAndItsBook() {
        let entries = [
            passage("p", text: "nothing here", book: sapiens, comment: "an objection"),
            passage("q", text: "nothing here", book: dune)
        ]
        XCTAssertEqual(snapshot(entries, .init(rawQuery: "objection")).results.map(\.id), ["passage:p"])
        XCTAssertEqual(snapshot(entries, .init(rawQuery: "Herbert")).results.map(\.id), ["passage:q"])
    }

    // MARK: - Order and grouping

    /// A note carries an edit date and a passage does not, so "last touched" has to mean
    /// something for both or the two collections cannot share one order.
    func testLastTouchedOrdersNotesByEditAndPassagesBySaving() {
        let early = Date(timeIntervalSince1970: 100)
        let late = Date(timeIntervalSince1970: 900)
        let entries = [
            note("edited", updated: late, created: early),
            passage("saved", book: dune, created: Date(timeIntervalSince1970: 500))
        ]
        XCTAssertEqual(
            snapshot(entries, .init(sort: .recent)).results.map(\.id),
            ["note:edited", "passage:saved"]
        )
        XCTAssertEqual(
            snapshot(entries, .init(sort: .created)).results.map(\.id),
            ["passage:saved", "note:edited"]
        )
    }

    /// Sections take the order their first member already stands in, so grouping never
    /// overrules the sort the reader chose.
    func testGroupingFollowsTheChosenOrderRatherThanImposingItsOwn() {
        let entries = [
            note("z", title: "Zeta", book: sapiens),
            note("a", title: "Alpha", book: dune),
            note("m", title: "Mu", book: sapiens)
        ]
        let shot = snapshot(entries, .init(sort: .title, grouping: .source))
        XCTAssertEqual(shot.groups.map(\.title), ["Dune", "Sapiens"])
        XCTAssertEqual(shot.groups.last?.entries.map(\.displayTitle), ["Mu", "Zeta"])
    }

    func testNotesWithNoSourceCollectUnderTheirOwnHeading() {
        let entries = [note("free"), passage("p", book: dune)]
        let shot = snapshot(entries, .init(grouping: .source))
        XCTAssertTrue(shot.groups.contains { $0.title == "No source" })
    }
}
