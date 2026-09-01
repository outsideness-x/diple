import GRDB
import XCTest
@testable import diple

/// A note written on the page it was thought about.
///
/// What is worth proving is the seam, not the sheet: the tag a note is born with, that it is
/// one ordinary row in the same table the notes tab reads, and that the reader shows the notes
/// of the book it has open and no others.
@MainActor
final class ReaderNoteTests: XCTestCase {

    // MARK: - The tag a source lends

    func testSourceTagDropsTheSubtitleAndKeepsTheName() {
        XCTAssertEqual(TagName.forSource(titled: "Sapiens: A Brief History of Humankind"), "sapiens")
        XCTAssertEqual(TagName.forSource(titled: "The Idiot"), "the idiot")
        XCTAssertEqual(TagName.forSource(titled: "  Дюна  "), "дюна")
        XCTAssertEqual(TagName.forSource(titled: "데미안"), "데미안")
    }

    /// The head has to be a name before it can stand for one. `1` is a volume number, not a
    /// book, and a tag that says `#1` says nothing about what was read.
    func testSourceTagKeepsTheWholeTitleWhenNothingSubstantialPrecedesTheColon() {
        XCTAssertEqual(TagName.forSource(titled: "1: The Beginning"), "1: the beginning")
        XCTAssertEqual(TagName.forSource(titled: ": Untitled"), ": untitled")
    }

    /// The same rule a hand-typed tag goes through, so a tag written by the app and one
    /// written by the reader are the same tag.
    func testSourceTagNormalisesLikeAnyOtherTag() {
        XCTAssertEqual(TagName.forSource(titled: "#Physics"), TagName.normalized("physics "))
        XCTAssertNil(TagName.forSource(titled: "   "))
        XCTAssertNil(TagName.forSource(titled: "#"))
    }

    // MARK: - What a new note is born with

    func testANoteStartedInASourceIsBornTaggedAndLinked() {
        let book = Book(id: "dune", title: "Dune: A Novel", filePath: "Books/dune/dune.epub")
        let route = NoteRoute.newFromSource(book)

        XCTAssertEqual(route.initialTags, ["dune"])
        XCTAssertEqual(route.initialBookId, book.id)
    }

    /// Both, not either: the tag is the word, the link is the fact. Losing the link would take
    /// the note out of the source overview and the book filter; losing the tag would take it
    /// out of the tag row, the export and every other Markdown client.
    func testAPlainNewNoteIsBornWithNeither() {
        XCTAssertEqual(NoteRoute.new.initialTags, [])
        XCTAssertNil(NoteRoute.new.initialBookId)
    }

    func testAnExistingNoteKeepsItsOwnTagsRatherThanInheritingAny() {
        let item = NoteItem(
            note: Note(id: "kept", body: "Already written"),
            tags: ["mine"],
            book: nil
        )
        XCTAssertEqual(NoteRoute.existing(item).initialTags, [])
    }

    // MARK: - Written on the page, kept in the notes tab

    /// The whole promise of the feature in one pass: written from the reader, the note is an
    /// ordinary row — the notes tab's own query returns it, its tag is in the tag vocabulary
    /// the board offers, and the book it came from is on it.
    func testANoteWrittenInTheReaderIsAnOrdinaryNote() throws {
        let database = try AppDatabase(DatabaseQueue())
        let book = Book(id: "dune", title: "Dune: A Novel", filePath: "Books/dune/dune.epub")
        try database.saveBook(book)
        let model = ReaderViewModel(book: book, database: database)
        let route = NoteRoute.newFromSource(book)

        XCTAssertTrue(model.saveNote(
            Note(body: "The spice must flow", bookId: route.initialBookId),
            tags: route.initialTags
        ))

        let saved = try XCTUnwrap(try database.fetchAllNotes().first)
        XCTAssertEqual(saved.bookId, book.id)
        XCTAssertEqual(try database.fetchTags(forNoteID: saved.id), ["dune"])
        XCTAssertTrue(try database.fetchAllTags().contains("dune"))
        XCTAssertEqual(model.notes.forThisBook.map(\.id), [saved.id])
        XCTAssertEqual(model.notes.forThisBook.first?.tags, ["dune"])
        XCTAssertEqual(model.notes.forThisBook.first?.book?.id, book.id)
    }

    func testTheReaderCarriesOnlyTheOpenBooksNotes() throws {
        let database = try AppDatabase(DatabaseQueue())
        let open = Book(id: "open", title: "Open", filePath: "Books/open/open.epub")
        let other = Book(id: "other", title: "Other", filePath: "Books/other/other.epub")
        try database.saveBook(open)
        try database.saveBook(other)
        try database.saveNote(Note(id: "here", body: "About the open book", bookId: open.id), tags: ["open"])
        try database.saveNote(Note(id: "elsewhere", body: "About the other one", bookId: other.id), tags: ["other"])
        try database.saveNote(Note(id: "loose", body: "About nothing in particular"), tags: [])

        let model = ReaderViewModel(book: open, database: database)

        XCTAssertEqual(model.notes.forThisBook.map(\.id), ["here"])
        // The editor still needs the whole library: a wiki link written on the board has to
        // keep resolving when the same note is opened from the page.
        XCTAssertEqual(Set(model.notes.all.map(\.id)), ["here", "elsewhere", "loose"])
        XCTAssertEqual(Set(model.notes.books.map(\.id)), ["open", "other"])
        XCTAssertEqual(model.notes.tagSuggestions, ["open", "other"])
    }

    func testDeletingANoteFromTheBookRemovesItEverywhere() throws {
        let database = try AppDatabase(DatabaseQueue())
        let book = Book(id: "book", title: "Book", filePath: "Books/book/book.epub")
        try database.saveBook(book)
        try database.saveNote(Note(id: "doomed", body: "Second thoughts", bookId: book.id), tags: ["book"])
        let model = ReaderViewModel(book: book, database: database)
        let item = try XCTUnwrap(model.notes.forThisBook.first)

        model.deleteNote(item)

        XCTAssertTrue(model.notes.forThisBook.isEmpty)
        XCTAssertTrue(try database.fetchAllNotes().isEmpty)
        XCTAssertTrue(try database.fetchTags(forNoteID: "doomed").isEmpty)
    }

    /// The editor autosaves on a debounce, so a save is not the moment to speak: the toast
    /// would queue up behind a sheet nobody can see it through. The page says it once, when
    /// the editor leaves, and only if something was written.
    func testThePageConfirmsASavedNoteExactlyOnce() throws {
        let database = try AppDatabase(DatabaseQueue())
        let book = Book(id: "book", title: "Book", filePath: "Books/book/book.epub")
        try database.saveBook(book)
        let model = ReaderViewModel(book: book, database: database)

        model.announceSavedNote()
        XCTAssertNil(model.toast, "nothing was written, so there is nothing to confirm")

        _ = model.saveNote(Note(body: "Kept", bookId: book.id), tags: [])
        XCTAssertNil(model.toast, "a debounced autosave must not speak over the editor")

        model.announceSavedNote()
        XCTAssertEqual(model.toast, "Note saved")

        model.toast = nil
        model.announceSavedNote()
        XCTAssertNil(model.toast, "the same save must not be announced twice")
    }

    func testOneSourcesNotesComeBackNewestFirst() throws {
        let database = try AppDatabase(DatabaseQueue())
        let book = Book(id: "book", title: "Book", filePath: "Books/book/book.epub")
        try database.saveBook(book)
        let old = Date(timeIntervalSince1970: 1_000)
        let recent = Date(timeIntervalSince1970: 2_000)
        try database.saveNote(
            Note(id: "old", body: "Earlier", bookId: book.id, createdAt: old, updatedAt: old),
            tags: []
        )
        try database.saveNote(
            Note(id: "recent", body: "Later", bookId: book.id, createdAt: recent, updatedAt: recent),
            tags: []
        )

        XCTAssertEqual(try database.fetchNotes(forBookID: book.id).map(\.id), ["recent", "old"])
    }
}
