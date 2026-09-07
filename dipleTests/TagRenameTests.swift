import GRDB
import XCTest
@testable import diple

/// Renaming a tag.
///
/// The one repair the app could not make. A note's text can be edited and its source relinked,
/// but `phisics` typed once stayed `phisics` on every row that carried it and went on offering
/// itself in the suggestion menu. What has to hold: the word changes wherever the board can
/// show it, renaming onto an existing word merges instead of failing, the shelf's own
/// vocabulary is left alone, and nothing about the note itself is treated as edited.
@MainActor
final class TagRenameTests: XCTestCase {

    private func database() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(), syncEnabled: true)
    }

    private func book(_ id: String = "sapiens") -> Book {
        Book(id: id, title: "Sapiens", author: "Harari", filePath: "Books/\(id)/b.epub")
    }

    private func highlight(_ id: String, in book: Book) -> Highlight {
        Highlight(id: id, bookId: book.id, locator: "{}", text: "a passage", bookTitle: book.title)
    }

    // MARK: - What it changes

    func testTheWordChangesOnBothNotesAndPassages() throws {
        let db = try database()
        let source = book()
        try db.saveBook(source)
        try db.saveNote(Note(id: "n1", body: "a thought"), tags: ["phisics", "essay"])
        try db.saveHighlight(highlight("h1", in: source), tags: ["phisics"])

        let touched = try db.renameTag("phisics", to: "physics")

        XCTAssertEqual(touched, 2)
        XCTAssertEqual(try db.fetchTags(forNoteID: "n1"), ["essay", "physics"])
        XCTAssertEqual(try db.fetchTags(forHighlightId: "h1"), ["physics"])
        XCTAssertFalse(try db.fetchAllTags().contains("phisics"))
        XCTAssertFalse(try db.fetchAllHighlightTags().contains("phisics"))
    }

    /// The same normalisation a hand-typed tag goes through, so the rename cannot create a word
    /// that could never have been typed.
    func testTheNewNameIsNormalisedLikeAnyOtherTag() throws {
        let db = try database()
        try db.saveNote(Note(id: "n1", body: "a thought"), tags: ["physics"])

        try db.renameTag("physics", to: "  #Natural Philosophy  ")

        XCTAssertEqual(try db.fetchTags(forNoteID: "n1"), ["natural philosophy"])
    }

    func testRenamingToTheSameWordOrToNothingDoesNothing() throws {
        let db = try database()
        try db.saveNote(Note(id: "n1", body: "a thought"), tags: ["physics"])

        XCTAssertEqual(try db.renameTag("physics", to: "physics"), 0)
        XCTAssertEqual(try db.renameTag("physics", to: "#Physics"), 0, "normalises to the same word")
        XCTAssertEqual(try db.renameTag("physics", to: "  #  "), 0)
        XCTAssertEqual(try db.renameTag("nothing here", to: "anything"), 0)
        XCTAssertEqual(try db.fetchTags(forNoteID: "n1"), ["physics"])
    }

    // MARK: - Merging

    /// Renaming onto a word already in use is a merge. An `UPDATE` would collide on the primary
    /// key of an item carrying both and abort the whole rename.
    func testRenamingOntoAnExistingWordMergesInsteadOfFailing() throws {
        let db = try database()
        try db.saveNote(Note(id: "carries-both", body: "one"), tags: ["phisics", "physics"])
        try db.saveNote(Note(id: "carries-old", body: "two"), tags: ["phisics"])
        try db.saveNote(Note(id: "carries-new", body: "three"), tags: ["physics"])

        let touched = try db.renameTag("phisics", to: "physics")

        XCTAssertEqual(touched, 2, "only the rows that carried the old word were rewritten")
        XCTAssertEqual(try db.fetchTags(forNoteID: "carries-both"), ["physics"])
        XCTAssertEqual(try db.fetchTags(forNoteID: "carries-old"), ["physics"])
        XCTAssertEqual(try db.fetchTags(forNoteID: "carries-new"), ["physics"])
        XCTAssertEqual(try db.fetchAllTags(), ["physics"])
    }

    /// What the confirmation counts before it asks.
    func testUsageCountsBothVocabularies() throws {
        let db = try database()
        let source = book()
        try db.saveBook(source)
        try db.saveNote(Note(id: "n1", body: "a"), tags: ["essay"])
        try db.saveNote(Note(id: "n2", body: "b"), tags: ["essay"])
        try db.saveHighlight(highlight("h1", in: source), tags: ["essay"])

        XCTAssertEqual(try db.tagUsage("essay"), 3)
        XCTAssertEqual(try db.tagUsage("#Essay"), 3, "normalised before counting")
        XCTAssertEqual(try db.tagUsage("unused"), 0)
    }

    // MARK: - What it leaves alone

    /// A different vocabulary over a different thing — where a text sits on the shelf, not what
    /// a thought is about. The screen this is reached from does not show it, and renaming
    /// across all three would quietly merge two meanings the schema keeps apart on purpose.
    func testTheShelfsOwnVocabularyIsUntouched() throws {
        let db = try database()
        let source = book()
        try db.saveBook(source)
        try db.setTags(["phisics"], forBookId: source.id)
        try db.saveNote(Note(id: "n1", body: "a thought"), tags: ["phisics"])

        try db.renameTag("phisics", to: "physics")

        XCTAssertEqual(try db.fetchTags(forBookId: source.id), ["phisics"])
        XCTAssertEqual(try db.fetchTags(forNoteID: "n1"), ["physics"])
    }

    /// Fixing a typo in a tag is not editing a note. `note.updatedAt` orders the board, and
    /// bumping it would send every note carrying the word to the top as though it had just been
    /// rewritten — while the sync clock, which is a different column, does have to move or the
    /// rename would never reach the other device.
    func testTheNoteIsNotTreatedAsEditedButTheChangeStillSyncs() throws {
        let db = try database()
        let written = Date(timeIntervalSince1970: 1_000)
        try db.saveNote(
            Note(id: "n1", body: "a thought", createdAt: written, updatedAt: written),
            tags: ["phisics"]
        )

        try db.renameTag("phisics", to: "physics")

        XCTAssertEqual(try db.fetchNote(id: "n1")?.updatedAt, written)
        let metadata = try db.fetchSyncMetadata(entity: .note, id: "n1")
        XCTAssertNotNil(metadata)
        XCTAssertGreaterThan(metadata?.modifiedAt ?? .distantPast, written)
        XCTAssertTrue(try db.fetchSyncOutbox().contains { $0.entityID == "n1" })
    }

    /// The renamed word has to be findable by its new spelling and unfindable by its old one,
    /// or the rename only half happened.
    func testSearchFollowsTheRename() throws {
        let db = try database()
        let source = book()
        try db.saveBook(source)
        try db.saveNote(Note(id: "n1", body: "a thought"), tags: ["phisics"])
        try db.saveHighlight(highlight("h1", in: source), tags: ["phisics"])

        try db.renameTag("phisics", to: "physics")

        let found = try db.search("physics", limit: 20)
        XCTAssertTrue(found.contains { $0.entityID == "n1" })
        XCTAssertTrue(found.contains { $0.entityID == "h1" })
        XCTAssertTrue(try db.search("phisics", limit: 20).isEmpty)
    }
}
