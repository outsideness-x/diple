import GRDB
import XCTest
@testable import diple

@MainActor
final class MarkdownExportTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("diple-markdown-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func seededDatabase() throws -> AppDatabase {
        let database = try AppDatabase(DatabaseQueue())
        let book = Book(
            id: "dispossessed",
            title: "The Dispossessed: An Ambiguous Utopia",
            author: "Ursula K. Le Guin",
            filePath: "Books/dispossessed/book.epub",
            addedAt: Date(timeIntervalSince1970: 10)
        )
        try database.saveBook(book)
        try database.saveHighlight(
            Highlight(
                id: "h1",
                bookId: book.id,
                locator: "{}",
                text: "You cannot buy the revolution.",
                comment: "Стоит запомнить.",
                createdAt: Date(timeIntervalSince1970: 100)
            ),
            tags: ["Politics", "к эссе"]
        )
        try database.saveHighlight(
            Highlight(
                id: "h2",
                bookId: book.id,
                locator: "{}",
                text: "첫 번째 줄\n두 번째 줄",
                createdAt: Date(timeIntervalSince1970: 200)
            )
        )
        try database.saveNote(
            Note(
                id: "n1",
                title: "On walls",
                body: "A wall has two sides. See [[The Dispossessed]].",
                bookId: book.id,
                createdAt: Date(timeIntervalSince1970: 300),
                updatedAt: Date(timeIntervalSince1970: 300)
            ),
            tags: ["utopia"]
        )
        return database
    }

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: folder.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testWritesOneFilePerSourceAndOnePerNote() throws {
        let database = try seededDatabase()
        let report = try MarkdownLibraryExporter.shared.export(to: folder, database: database)

        XCTAssertEqual(report.sourceFiles, 1)
        XCTAssertEqual(report.passagesWritten, 2)
        XCTAssertEqual(report.noteFiles, 1)
        XCTAssertEqual(report.passagesAlreadyThere, 0)

        let source = try read("Highlights/The Dispossessed An Ambiguous Utopia.md")
        XCTAssertTrue(source.contains("diple_source: dispossessed"))
        XCTAssertTrue(
            source.contains("title: \"The Dispossessed: An Ambiguous Utopia\""),
            "a title with a colon has to stay one YAML field"
        )
        XCTAssertTrue(source.contains("> You cannot buy the revolution."))
        XCTAssertTrue(source.contains("Стоит запомнить."))
        XCTAssertTrue(source.contains("#politics #к эссе"), "tags travel as Obsidian tags")
        XCTAssertTrue(source.contains("<!-- diple:h1 -->"))
        XCTAssertTrue(
            source.contains("> 첫 번째 줄\n> 두 번째 줄"),
            "every line of a passage stays inside the blockquote"
        )

        // The note's filename is its `displayTitle`, which is what a `[[Wiki link]]` resolves
        // on inside diple and what Obsidian resolves on in a folder.
        let note = try read("Notes/On walls.md")
        XCTAssertTrue(note.contains("diple_note: n1"))
        XCTAssertTrue(note.contains("# On walls"))
        XCTAssertTrue(note.contains("[[The Dispossessed]]"), "wiki links are written through untouched")
        XCTAssertTrue(note.contains("#utopia"))
        XCTAssertTrue(note.contains("From *The Dispossessed: An Ambiguous Utopia*"))
    }

    /// The property that makes this safe to run every week: a second export adds only what is
    /// new, and whatever the reader wrote into the file between the quotes is still there.
    func testASecondExportAppendsOnlyWhatIsNewAndKeepsWhatTheReaderWrote() throws {
        let database = try seededDatabase()
        _ = try MarkdownLibraryExporter.shared.export(to: folder, database: database)

        let sourceURL = folder.appendingPathComponent("Highlights/The Dispossessed An Ambiguous Utopia.md")
        var edited = try String(contentsOf: sourceURL, encoding: .utf8)
        edited += "\nMy own paragraph, written in Obsidian.\n"
        try Data(edited.utf8).write(to: sourceURL)

        try database.saveHighlight(
            Highlight(
                id: "h3",
                bookId: "dispossessed",
                locator: "{}",
                text: "A new passage, saved later.",
                createdAt: Date(timeIntervalSince1970: 300)
            )
        )

        let second = try MarkdownLibraryExporter.shared.export(to: folder, database: database)
        XCTAssertEqual(second.passagesWritten, 1)
        XCTAssertEqual(second.passagesAlreadyThere, 2)

        let after = try read("Highlights/The Dispossessed An Ambiguous Utopia.md")
        XCTAssertTrue(after.contains("My own paragraph, written in Obsidian."))
        XCTAssertTrue(after.contains("<!-- diple:h3 -->"))
        XCTAssertEqual(
            after.components(separatedBy: "<!-- diple:h1 -->").count - 1,
            1,
            "a passage already in the file is never written twice"
        )
    }

    /// A file diple did not write is never opened for writing, however tempting its name.
    func testAForeignFileOfTheSameNameIsWrittenBesideRatherThanOver() throws {
        let database = try seededDatabase()
        let highlights = folder.appendingPathComponent("Highlights", isDirectory: true)
        try FileManager.default.createDirectory(at: highlights, withIntermediateDirectories: true)
        let foreign = highlights.appendingPathComponent("The Dispossessed An Ambiguous Utopia.md")
        try Data("# My own file about this book\n".utf8).write(to: foreign)

        let report = try MarkdownLibraryExporter.shared.export(to: folder, database: database)
        XCTAssertEqual(report.skippedForeignFiles, 1)
        XCTAssertEqual(
            try String(contentsOf: foreign, encoding: .utf8),
            "# My own file about this book\n",
            "somebody else's notes are not ours to replace"
        )
        XCTAssertTrue(try read("Highlights/The Dispossessed An Ambiguous Utopia 2.md").contains("<!-- diple:h1 -->"))
    }

    // MARK: - Spaces

    /// The vault is laid out the way the notes workshop is: a note filed in a space is written
    /// into that space's folder, and says so in its front matter.
    func testANoteInASpaceIsWrittenIntoItsFolder() throws {
        let database = try AppDatabase(DatabaseQueue())
        let space = try database.createSpace(named: "Essay: on time")
        try database.saveNote(Note(id: "n1", title: "Borges", body: "the garden", spaceId: space.id), tags: [])
        try database.setPinned(true, noteID: "n1")
        try database.saveNote(Note(id: "n2", title: "Loose", body: "no space"), tags: [])

        _ = try MarkdownLibraryExporter.shared.export(to: folder, database: database)

        let filed = try read("Notes/Essay on time/Borges.md")
        XCTAssertTrue(filed.contains("space: \"Essay: on time\""))
        XCTAssertTrue(filed.contains("pinned: true"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Notes/Loose.md").path))
    }

    /// A note moved between spaces must not be left behind in the old folder as a second, stale
    /// copy — and a file in that folder which diple did not write stays exactly where it is.
    func testMovingANoteMovesItsFileAndLeavesForeignFilesAlone() throws {
        let database = try AppDatabase(DatabaseQueue())
        let first = try database.createSpace(named: "First")
        let second = try database.createSpace(named: "Second")
        try database.saveNote(Note(id: "n1", title: "Wandering", body: "a thought", spaceId: first.id), tags: [])
        _ = try MarkdownLibraryExporter.shared.export(to: folder, database: database)

        let foreign = folder.appendingPathComponent("Notes/First/Mine.md")
        try "---\nauthor: me\n---\n\nnot diple's".write(to: foreign, atomically: true, encoding: .utf8)
        try database.moveNotes(ids: ["n1"], toSpace: second.id)
        _ = try MarkdownLibraryExporter.shared.export(to: folder, database: database)

        let fileManager = FileManager.default
        XCTAssertFalse(fileManager.fileExists(atPath: folder.appendingPathComponent("Notes/First/Wandering.md").path))
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("Notes/Second/Wandering.md").path))
        XCTAssertTrue(fileManager.fileExists(atPath: foreign.path))
    }

    /// Recently deleted is not part of the library, so it is not written into the vault.
    func testADeletedNoteIsNotExported() throws {
        let database = try AppDatabase(DatabaseQueue())
        try database.saveNote(Note(id: "n1", title: "Gone", body: "x"), tags: [])
        try database.trashNote(id: "n1")

        let report = try MarkdownLibraryExporter.shared.export(to: folder, database: database)

        XCTAssertEqual(report.noteFiles, 0)
    }

    func testFileNamesSurviveTitlesThatFilesystemsRefuse() {
        XCTAssertEqual(
            MarkdownLibraryExporter.safeFileName("Sapiens: A Brief/History* of \"Humankind\""),
            "Sapiens A Brief History of Humankind"
        )
        XCTAssertEqual(MarkdownLibraryExporter.safeFileName("   "), "Untitled")
        XCTAssertEqual(MarkdownLibraryExporter.safeFileName("..."), "Untitled")
        XCTAssertEqual(MarkdownLibraryExporter.safeFileName("책을 읽는 사람"), "책을 읽는 사람")
    }
}
