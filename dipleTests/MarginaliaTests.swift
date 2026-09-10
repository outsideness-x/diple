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

    // MARK: - Mark colour

    private func coloured(_ id: String, _ hex: String, book: Book, tags: [String] = []) -> MarginaliaEntry {
        .passage(
            PassageItem(
                highlight: Highlight(
                    id: id, bookId: book.id, locator: "{}", text: "text",
                    colorHex: hex, createdAt: Date(timeIntervalSince1970: 1_000_000),
                    bookTitle: book.title
                ),
                tags: tags,
                book: book
            )
        )
    }

    /// A note carries no mark, so asking about colour excludes every note. Quietly keeping them
    /// in the result would make the number on the swatch a lie.
    func testAskingAboutColourExcludesNotes() {
        let entries = [
            coloured("y", "#FFD60A", book: sapiens),
            note("n", tags: ["physics"])
        ]
        let shot = snapshot(entries, .init(facets: MarginaliaFacets(colors: ["#FFD60A"])))
        XCTAssertEqual(shot.results.map(\.id), ["passage:y"])
        XCTAssertEqual(shot.writtenCount, 0)
    }

    /// Two colours is "either mark": a passage carries exactly one, so intersecting could only
    /// ever return nothing.
    func testColoursAreUnioned() {
        let entries = [
            coloured("y", "#FFD60A", book: sapiens),
            coloured("p", "#FF375F", book: sapiens),
            coloured("g", "#30D158", book: dune)
        ]
        let shot = snapshot(entries, .init(facets: MarginaliaFacets(colors: ["#FFD60A", "#FF375F"])))
        XCTAssertEqual(Set(shot.results.map(\.id)), ["passage:y", "passage:p"])
    }

    /// One colour in play is not a choice, and a row of one swatch filters nothing.
    func testASingleColourIsNotOffered() {
        let entries = [
            coloured("a", "#FFD60A", book: sapiens),
            coloured("b", "#FFD60A", book: dune)
        ]
        XCTAssertTrue(snapshot(entries).colorOptions.isEmpty)

        let mixed = entries + [coloured("c", "#30D158", book: dune)]
        XCTAssertEqual(snapshot(mixed).colorOptions.count, 2)
    }

    /// Tallied with the colour filter lifted, like a source: the number says what that mark
    /// would bring, because adding one widens the result.
    func testAColourSwatchCountsWhatThatMarkBrings() {
        let entries = [
            coloured("y1", "#FFD60A", book: sapiens),
            coloured("y2", "#FFD60A", book: sapiens),
            coloured("g", "#30D158", book: sapiens)
        ]
        let shot = snapshot(entries, .init(facets: MarginaliaFacets(colors: ["#30D158"])))
        let yellow = shot.colorOptions.first { $0.kind == .color("#FFD60A") }
        XCTAssertEqual(yellow?.count, 2)
        XCTAssertEqual(shot.results.count, 1)
    }

    /// Colour narrows alongside the other axes rather than replacing them.
    func testColourIntersectsWithTagsAndSources() {
        let entries = [
            coloured("a", "#FFD60A", book: sapiens, tags: ["objection"]),
            coloured("b", "#FFD60A", book: dune, tags: ["objection"]),
            coloured("c", "#30D158", book: sapiens, tags: ["objection"])
        ]
        let shot = snapshot(entries, .init(
            facets: MarginaliaFacets(bookIds: ["sapiens"], tags: ["objection"], colors: ["#FFD60A"])
        ))
        XCTAssertEqual(shot.results.map(\.id), ["passage:a"])
    }

    /// The swatches stay together as a run. They are aimed at rather than read, and one that
    /// migrated into the middle of the words would have to be found again every time.
    func testTheSwatchesStayTogetherInTheRow() {
        let entries = [
            coloured("a", "#FFD60A", book: sapiens, tags: ["objection"]),
            coloured("b", "#30D158", book: dune, tags: ["essay"])
        ]
        let kinds = snapshot(entries).facetOptions.map(\.kind)
        let colorPositions = kinds.indices.filter {
            if case .color = kinds[$0] { return true }
            return false
        }
        XCTAssertEqual(colorPositions, Array(colorPositions.first!...colorPositions.last!))
    }

    // MARK: - The runs

    /// Every kind stands in one contiguous run, and the runs come in a fixed order: marks,
    /// then shelves, then words. A single ranking by count put a book between two tags and
    /// moved every chip whenever the numbers did, so the row had to be read end to end each
    /// time — see the note in `MarginaliaBoard`.
    func testTheRowIsThreeRunsInAFixedOrder() {
        let entries = [
            coloured("a", "#FFD60A", book: sapiens, tags: ["objection", "essay"]),
            coloured("b", "#30D158", book: dune, tags: ["essay"]),
            coloured("c", "#30D158", book: dune, tags: ["essay"])
        ]

        let ranks: [Int] = snapshot(entries).facetOptions.map { option in
            switch option.kind {
            case .color: return 0
            case .source: return 1
            case .tag: return 2
            }
        }

        XCTAssertEqual(ranks, ranks.sorted(), "runs are out of order or interleaved: \(ranks)")
        XCTAssertTrue(ranks.contains(0) && ranks.contains(1) && ranks.contains(2))
    }

    /// Chosen first, but only inside its own run: a pressed word does not jump the shelves.
    ///
    /// Both marks have to survive the narrowing for this to test anything — a single colour
    /// left standing is not a choice and the swatch run is not drawn at all — so `objection`
    /// is on one passage of each colour.
    func testAChosenChipLeadsItsOwnRunRatherThanTheWholeRow() {
        let entries = [
            coloured("a", "#FFD60A", book: sapiens, tags: ["objection"]),
            coloured("b", "#30D158", book: dune, tags: ["objection"]),
            coloured("c", "#30D158", book: dune, tags: ["essay"])
        ]
        let options = snapshot(entries, .init(facets: MarginaliaFacets(tags: ["objection"]))).facetOptions

        // The row still opens on the marks, not on the pressed word.
        guard case .color = options.first?.kind else {
            return XCTFail("the row should still open on the swatches, not on \(String(describing: options.first?.kind))")
        }

        let tags = options.filter { if case .tag = $0.kind { return true } else { return false } }
        XCTAssertEqual(tags.first?.label, "objection")
        XCTAssertTrue(tags.first?.isSelected == true)
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

    // MARK: - Collecting into one note

    private func compile(
        _ entries: [MarginaliaEntry],
        facets: MarginaliaFacets = MarginaliaFacets()
    ) -> MarginaliaBoard.Compilation {
        MarginaliaBoard.compile(
            entries,
            narrowedBy: facets,
            books: [sapiens, dune],
            on: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    /// A passage has no page of its own, so its words travel. A note already is a page, so a
    /// link travels instead — copying it here would fork the one copy.
    func testAPassageIsQuotedAndANoteIsLinked() {
        let entries = [
            passage("p", text: "Money is a system of mutual trust.", book: sapiens),
            note("n", title: "On imagined orders", book: sapiens)
        ]
        let body = compile(entries).body

        XCTAssertTrue(body.contains("> Money is a system of mutual trust."))
        XCTAssertTrue(body.contains("[[On imagined orders]]"))
        XCTAssertFalse(body.contains("a thought"), "the note's own text stays on its own page")
    }

    /// One source needs no heading — the note carries the link to it, and a heading would be
    /// the title printed twice — so the quotation keeps no attribution either.
    func testUnderOneSourceThereAreNoHeadingsAndTheSourceIsLinked() {
        let entries = [
            passage("p1", text: "First.", book: sapiens),
            passage("p2", text: "Second.", book: sapiens)
        ]
        let compilation = compile(entries)

        XCTAssertFalse(compilation.body.contains("##"))
        XCTAssertFalse(compilation.body.contains("— Sapiens"))
        XCTAssertEqual(compilation.bookId, "sapiens")
        XCTAssertEqual(compilation.title, "From Sapiens")
    }

    /// Across sources the heading is what stops the quotations running together into one voice,
    /// and it is also what makes the per-quotation attribution redundant.
    func testAcrossSourcesEachRunGetsOneHeadingAndTheQuotationsDropTheirAttribution() {
        let entries = [
            passage("p1", text: "First.", book: sapiens),
            passage("p2", text: "Second.", book: sapiens),
            passage("p3", text: "Third.", book: dune)
        ]
        let body = compile(entries).body

        XCTAssertEqual(body.components(separatedBy: "## Sapiens").count - 1, 1)
        XCTAssertEqual(body.components(separatedBy: "## Dune").count - 1, 1)
        XCTAssertFalse(body.contains("— Sapiens"))
        XCTAssertNil(compile(entries).bookId, "no single source to link")
    }

    func testAFreeNoteCollectsUnderItsOwnHeadingWhenMixedWithSources() {
        let entries = [passage("p", book: sapiens), note("free")]
        XCTAssertTrue(compile(entries).body.contains("## Without a source"))
    }

    /// The reader's own line on a passage is the part they will actually reuse; leaving it
    /// behind would make the compilation a worse copy of the board it came from.
    func testACommentTravelsUnderItsQuotation() {
        let entries = [
            passage("p", text: "The Agricultural Revolution was a fraud.", book: sapiens, comment: "Too neat.")
        ]
        let body = compile(entries).body
        let quoteLine = body.range(of: "> The Agricultural")
        let commentLine = body.range(of: "Too neat.")
        XCTAssertNotNil(quoteLine)
        XCTAssertNotNil(commentLine)
        XCTAssertTrue(quoteLine!.upperBound < commentLine!.lowerBound)
    }

    /// Gathered while the board was narrowed to a word, the note is about that word. Arriving
    /// without it would make the reader file by hand what they had just filed with a chip.
    func testTheNarrowingNamesAndTagsTheGatheredNote() {
        let entries = [passage("p", book: sapiens), passage("q", book: dune)]
        let compilation = compile(entries, facets: MarginaliaFacets(tags: ["objection", "essay"]))

        XCTAssertEqual(compilation.tags, ["essay", "objection"])
        XCTAssertEqual(compilation.title, "#essay #objection")
    }

    /// Never "Untitled": a document the reader asked to have made should not arrive nameless.
    func testAnUnnarrowedCollectionIsNamedByItsDate() {
        let compilation = compile([passage("p", book: sapiens), passage("q", book: dune)])
        XCTAssertEqual(compilation.title, "Collected 15 Jan 2027")
    }

    func testNotesWithNoSourceCollectUnderTheirOwnHeading() {
        let entries = [note("free"), passage("p", book: dune)]
        let shot = snapshot(entries, .init(grouping: .source))
        XCTAssertTrue(shot.groups.contains { $0.title == "No source" })
    }
}
