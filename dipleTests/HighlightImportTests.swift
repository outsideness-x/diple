import GRDB
import XCTest
@testable import diple

@MainActor
final class HighlightImportTests: XCTestCase {

    // MARK: - Kindle

    private static let clippings = """
    Sapiens: A Brief History of Humankind (Harari, Yuval Noah)
    - Your Highlight on page 12 | Location 145-147 | Added on Monday, 12 August 2024 21:03:17

    Homo sapiens rules the world because it is the only animal that can believe in things that exist purely in its own imagination.
    ==========
    Sapiens: A Brief History of Humankind (Harari, Yuval Noah)
    - Your Note on page 12 | Location 147 | Added on Monday, 12 August 2024 21:04:02

    Это и есть весь тезис книги.
    ==========
    Sapiens: A Brief History of Humankind (Harari, Yuval Noah)
    - Your Bookmark on page 20 | Location 300 | Added on Monday, 12 August 2024 21:05:00

    ==========
    피라네시 (Clarke, Susanna)
    - Your Highlight on page 3 | Location 40-42 | Added on Tuesday, 13 August 2024 08:00:00

    집의 아름다움은 이루 말할 수 없고, 집의 친절함은 무한하다.
    ==========

    """

    /// The three things a clippings file asks of a parser, in one pass: a byline lives in the
    /// last brackets of the title line, a note belongs to the passage above it, and a bookmark
    /// is nothing the reader wrote.
    func testKindleClippingsPairsNotesFlipsBylinesAndDropsBookmarks() throws {
        let document = try HighlightImporter.shared.parse(Data(Self.clippings.utf8))
        XCTAssertEqual(document.kind, .kindle)
        XCTAssertEqual(document.passages.count, 2, "the bookmark carries nothing of the reader's")
        XCTAssertEqual(document.sourceCount, 2)

        let sapiens = try XCTUnwrap(document.passages.first)
        XCTAssertEqual(sapiens.bookTitle, "Sapiens: A Brief History of Humankind")
        XCTAssertEqual(
            sapiens.bookAuthor,
            "Yuval Noah Harari",
            "Kindle files a byline surname-first; every other screen prints the name people say"
        )
        XCTAssertTrue(sapiens.text.hasPrefix("Homo sapiens rules the world"))
        XCTAssertEqual(
            sapiens.note,
            "Это и есть весь тезис книги.",
            "a single position inside the passage above it is a note on that passage"
        )

        let piranesi = try XCTUnwrap(document.passages.last)
        XCTAssertEqual(piranesi.bookTitle, "피라네시")
        XCTAssertEqual(piranesi.bookAuthor, "Susanna Clarke")
        XCTAssertNil(piranesi.note)

        let expected = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: .current,
            year: 2024, month: 8, day: 12, hour: 21, minute: 3, second: 17
        ).date
        XCTAssertEqual(sapiens.createdAt, expected)
    }

    /// A title with brackets of its own must keep them; only the last group is a byline.
    func testKindleTitleLineKeepsBracketsThatBelongToTheTitle() {
        let (title, author) = KindleClippingsParser.splitTitleAndAuthor(
            "The Man Who Mistook His Wife for a Hat (and Other Clinical Tales) (Sacks, Oliver)"
        )
        XCTAssertEqual(title, "The Man Who Mistook His Wife for a Hat (and Other Clinical Tales)")
        XCTAssertEqual(author, "Oliver Sacks")

        let (bare, none) = KindleClippingsParser.splitTitleAndAuthor("A Title With No Byline")
        XCTAssertEqual(bare, "A Title With No Byline")
        XCTAssertNil(none)
    }

    /// The position is read from the segments before the date, so a file that omits the page
    /// or writes it in another language still yields numbers.
    func testKindlePositionIsReadStructurallyRatherThanByKeyword() {
        XCTAssertEqual(
            KindleClippingsParser.position(in: "- Ihre Markierung bei Position 145-147 | Hinzugefügt am Montag, 12. August 2024")?.start,
            145
        )
        XCTAssertEqual(
            KindleClippingsParser.position(in: "- Your Highlight on page 12 | Location 145-147 | Added on Monday")?.end,
            147
        )
        XCTAssertNil(KindleClippingsParser.position(in: "- a line with no segments at all"))
    }

    // MARK: - Readwise

    /// Extended delimiters, because the file this imitates contains `""` — Readwise's own way
    /// of writing one quotation mark inside a quoted field — and a plain Swift literal would
    /// end on it.
    private static let readwiseCSV = #"""
    Highlight,Book Title,Book Author,Amazon Book ID,Note,Color,Tags,Location Type,Location,Highlighted at
    "A sentence, with a comma in it","The Dispossessed","Ursula K. Le Guin","","My own thought","blue","fiction #Utopia","location","1234","2024-05-14T09:12:00Z"
    "A quote that runs
    across two lines, and says ""this""","The Dispossessed","Ursula K. Le Guin","","","yellow","","location","1300","2024-05-15T09:12:00Z"
    "","The Dispossessed","Ursula K. Le Guin","","a note with no passage","","","location","1400",""
    """#

    func testReadwiseCSVReadsQuotedFieldsTagsAndColours() throws {
        let document = try HighlightImporter.shared.parse(Data(Self.readwiseCSV.utf8))
        XCTAssertEqual(document.kind, .readwise)
        XCTAssertEqual(document.passages.count, 2, "a row with no passage text is not a passage")
        XCTAssertEqual(document.sourceCount, 1)

        let first = try XCTUnwrap(document.passages.first)
        XCTAssertEqual(first.text, "A sentence, with a comma in it")
        XCTAssertEqual(first.note, "My own thought")
        XCTAssertEqual(
            first.tags,
            ["fiction", "utopia"],
            "a foreign tag goes through the same normalisation as one typed here"
        )
        XCTAssertEqual(ImportedHighlightColor.hex(forName: first.colorName), DipleColor.Highlight.blue)
        XCTAssertEqual(first.createdAt, Date(timeIntervalSince1970: 1_715_677_920))

        let second = try XCTUnwrap(document.passages.last)
        XCTAssertTrue(second.text.contains("\n"), "a quoted newline is part of the passage")
        XCTAssertTrue(second.text.hasSuffix("says \"this\""), "a doubled quote is one quote")
    }

    func testAnUnrecognisedFileIsRefusedRatherThanImportedEmpty() {
        XCTAssertThrowsError(try HighlightImporter.shared.parse(Data("just some prose".utf8))) {
            guard case HighlightImportError.unrecognizedFormat = $0 else {
                return XCTFail("Expected unrecognizedFormat, got \($0)")
            }
        }
    }

    // MARK: - Writing it into the library

    /// The property the whole identity scheme exists for. Kindle rewrites `My Clippings.txt` on
    /// every sync, so a reader will run the same file through this more than once; the second
    /// run has to be a no-op rather than a doubled library.
    func testImportingTheSameFileTwiceAddsNothingTheSecondTime() throws {
        let database = try AppDatabase(DatabaseQueue(), syncEnabled: true)
        let document = try HighlightImporter.shared.parse(Data(Self.clippings.utf8))

        let preview = try database.previewHighlightImport(document)
        XCTAssertEqual(preview.passagesToAdd, 2)
        XCTAssertEqual(preview.passagesAlreadyHere, 0)
        XCTAssertEqual(preview.sourceCount, 2)

        let report = try database.importHighlights(document, at: Date(timeIntervalSince1970: 5_000))
        XCTAssertEqual(report.preview.passagesToAdd, 2)
        XCTAssertEqual(try database.fetchAllHighlights().count, 2)

        let second = try database.previewHighlightImport(document)
        XCTAssertTrue(second.isNoOp)
        XCTAssertEqual(second.passagesAlreadyHere, 2)
        _ = try database.importHighlights(document, at: Date(timeIntervalSince1970: 6_000))
        XCTAssertEqual(try database.fetchAllHighlights().count, 2, "no duplicates on a re-import")
    }

    /// What an imported passage is once it is inside: a quote with no position, its own group,
    /// its book's name in the snapshot that already lets a quote outlive its book, and every
    /// word of it in search.
    func testImportedPassagesFormTheirOwnGroupsAndAreSearchable() throws {
        let database = try AppDatabase(DatabaseQueue(), syncEnabled: true)
        // A real book of the same title is already on the shelf. The import must not attach to
        // it: nothing in the file names a position inside *this* file.
        let shelved = Book(
            id: "shelved-dispossessed",
            title: "The Dispossessed",
            author: "Ursula K. Le Guin",
            filePath: "Books/shelved-dispossessed/book.epub",
            addedAt: Date(timeIntervalSince1970: 10)
        )
        try database.saveBook(shelved)

        let document = try HighlightImporter.shared.parse(Data(Self.readwiseCSV.utf8))
        _ = try database.importHighlights(document, at: Date(timeIntervalSince1970: 5_000))

        XCTAssertTrue(
            try database.fetchHighlights(forBookId: shelved.id).isEmpty,
            "an imported passage has no locator, so it must not land in a real book's list"
        )

        let groups = try database.fetchHighlightGroups()
        XCTAssertEqual(groups.count, 1)
        let group = try XCTUnwrap(groups.first)
        XCTAssertEqual(group.quoteCount, 2)
        XCTAssertEqual(group.bookTitle, "The Dispossessed")
        XCTAssertEqual(group.bookAuthor, "Ursula K. Le Guin")
        XCTAssertNil(try database.fetchBook(id: group.bookId), "no fake source row is invented")

        let imported = try XCTUnwrap(
            database.fetchAllHighlights().first { $0.text.hasPrefix("A sentence") }
        )
        XCTAssertNil(imported.parsedLocator, "an empty locator reads as no position, not a broken one")
        XCTAssertEqual(imported.comment, "My own thought")
        XCTAssertEqual(imported.colorHex, DipleColor.Highlight.blue)
        XCTAssertEqual(try database.fetchTags(forHighlightId: imported.id), ["fiction", "utopia"])
        XCTAssertEqual(imported.createdAt, Date(timeIntervalSince1970: 1_715_677_920))

        XCTAssertEqual(try database.search("comma in it").map(\.kind), [.highlight])
        XCTAssertEqual(
            try database.search("utopia").map(\.entityID),
            [imported.id],
            "an imported tag is searchable like any other"
        )
        XCTAssertEqual(
            try database.fetchSyncOutbox().filter { $0.entity == .highlight }.count,
            2,
            "imported passages sync like any other quote"
        )
    }

    /// A passage the file could not date is stamped with the moment it arrived. That is a true
    /// statement about it, and it keeps daily resurfacing — which sorts oldest first — from
    /// putting an unreadable date at the beginning of time.
    func testAPassageWithNoReadableDateTakesTheMomentItArrived() throws {
        let database = try AppDatabase(DatabaseQueue())
        let undated = """
        A Book (Someone)
        - Your Highlight | Location 1-2 | Added on 늘 그렇듯이 알 수 없는 날짜

        A passage whose date nobody can read.
        ==========
        """
        let document = try HighlightImporter.shared.parse(Data(undated.utf8))
        XCTAssertNil(document.passages.first?.createdAt)

        let arrival = Date(timeIntervalSince1970: 9_000)
        _ = try database.importHighlights(document, at: arrival)
        XCTAssertEqual(try database.fetchAllHighlights().first?.createdAt, arrival)
    }
}
