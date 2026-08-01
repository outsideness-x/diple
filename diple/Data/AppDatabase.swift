import Foundation
import GRDB

/// - Important: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would otherwise pin every query
///   to the main thread, which is exactly where reading-position writes must not happen.
///   GRDB's `DatabaseQueue` serializes access itself, so this type opts out of that default.
public nonisolated final class AppDatabase: Sendable {
    public static let shared: AppDatabase = {
        do {
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dbURL = appSupportURL.appendingPathComponent("diple.sqlite")
            var config = Configuration()
            config.qos = .userInitiated
            let dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)
            let database = try AppDatabase(dbQueue)
            return database
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }()

    private let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try migrator.migrate(writer)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = false
        #endif

        migrator.registerMigration("v1_createBookTable") { db in
            try db.create(table: "book") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("author", .text)
                t.column("filePath", .text).notNull()
                t.column("coverPath", .text)
                t.column("addedAt", .datetime).notNull()
                t.column("lastOpenedAt", .datetime)
                t.column("progress", .double).notNull().defaults(to: 0.0)
                t.column("locator", .text)
            }
        }

        migrator.registerMigration("v2_createHighlightTable") { db in
            try db.create(table: "highlight") { t in
                t.column("id", .text).primaryKey()
                t.column("bookId", .text).notNull().indexed()
                t.column("locator", .text).notNull()
                t.column("text", .text).notNull()
                t.column("colorHex", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v3_createBookmarkTable") { db in
            try db.create(table: "bookmark") { t in
                t.column("id", .text).primaryKey()
                t.column("bookId", .text).notNull().indexed()
                t.column("locator", .text).notNull()
                t.column("name", .text).notNull()
                t.column("colorHex", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v4_createNoteTables") { db in
            try db.create(table: "note") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text)
                t.column("body", .text).notNull()
                t.column("bookId", .text).indexed()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "noteTag") { t in
                t.column("noteId", .text).notNull()
                t.column("tag", .text).notNull()
                t.primaryKey(["noteId", "tag"])
            }
            try db.create(index: "noteTag_on_tag", on: "noteTag", columns: ["tag"])
        }

        return migrator
    }

    // MARK: - Database Access

    public func saveBook(_ book: Book) throws {
        try writer.write { db in
            try book.save(db)
        }
    }

    public func fetchAllBooks() throws -> [Book] {
        try writer.read { db in
            try Book.order(Column("addedAt").desc).fetchAll(db)
        }
    }

    public func fetchBook(id: String) throws -> Book? {
        try writer.read { db in
            try Book.filter(Column("id") == id).fetchOne(db)
        }
    }

    public func updateReadingProgress(id: String, progress: Double, locator: String?, lastOpenedAt: Date = Date()) throws {
        try writer.write { db in
            if var book = try Book.filter(Column("id") == id).fetchOne(db) {
                book.progress = progress
                book.locator = locator
                book.lastOpenedAt = lastOpenedAt
                try book.update(db)
            }
        }
    }

    public func updateBookMetadata(id: String, title: String, author: String?, coverPath: String? = nil) throws {
        try writer.write { db in
            if var book = try Book.filter(Column("id") == id).fetchOne(db) {
                book.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedAuthor = author?.trimmingCharacters(in: .whitespacesAndNewlines)
                book.author = (trimmedAuthor?.isEmpty ?? true) ? nil : trimmedAuthor
                if let coverPath = coverPath {
                    book.coverPath = coverPath
                }
                try book.update(db)
            }
        }
    }

    public func deleteBook(id: String) throws {
        try writer.write { db in
            _ = try Bookmark.filter(Column("bookId") == id).deleteAll(db)
            _ = try Highlight.filter(Column("bookId") == id).deleteAll(db)
            // Notes are the user's own writing and survive the book they referenced;
            // only the tag pointing at it goes away.
            try db.execute(sql: "UPDATE note SET bookId = NULL WHERE bookId = ?", arguments: [id])
            _ = try Book.filter(Column("id") == id).deleteAll(db)
        }
    }

    // MARK: - Highlight CRUD

    public func saveHighlight(_ highlight: Highlight) throws {
        try writer.write { db in
            try highlight.save(db)
        }
    }

    public func fetchHighlights(forBookId bookId: String) throws -> [Highlight] {
        try writer.read { db in
            try Highlight.filter(Column("bookId") == bookId).order(Column("createdAt").desc).fetchAll(db)
        }
    }

    /// Number of quotes per book id, for the hub's book list. Counting in SQL keeps the
    /// whole highlight table out of memory just to render a badge.
    public func fetchHighlightCountsByBook() throws -> [String: Int] {
        try writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT bookId, COUNT(*) AS count FROM highlight GROUP BY bookId
                """)
            return rows.reduce(into: [String: Int]()) { result, row in
                result[row["bookId"]] = row["count"]
            }
        }
    }

    public func deleteHighlight(id: String) throws {
        try writer.write { db in
            _ = try Highlight.filter(Column("id") == id).deleteAll(db)
        }
    }

    // MARK: - Bookmark CRUD

    public func saveBookmark(_ bookmark: Bookmark) throws {
        try writer.write { db in
            try bookmark.save(db)
        }
    }

    public func fetchBookmarks(forBookId bookId: String) throws -> [Bookmark] {
        try writer.read { db in
            try Bookmark.filter(Column("bookId") == bookId).order(Column("createdAt").desc).fetchAll(db)
        }
    }

    public func deleteBookmark(id: String) throws {
        try writer.write { db in
            _ = try Bookmark.filter(Column("id") == id).deleteAll(db)
        }
    }

    // MARK: - Note CRUD

    /// Writes the note and replaces its tag set in one transaction, so a note is never
    /// visible with a half-applied set of tags.
    public func saveNote(_ note: Note, tags: [String]) throws {
        try writer.write { db in
            try note.save(db)
            _ = try NoteTag.filter(Column("noteId") == note.id).deleteAll(db)
            for tag in Set(tags.compactMap(NoteTag.normalized)) {
                try NoteTag(noteId: note.id, tag: tag).insert(db)
            }
        }
    }

    public func fetchAllNotes() throws -> [Note] {
        try writer.read { db in
            try Note.order(Column("updatedAt").desc).fetchAll(db)
        }
    }

    /// Tags for every note at once — the notes board renders them on each card, and one
    /// query per card would mean a query per scroll.
    public func fetchTagsByNote() throws -> [String: [String]] {
        try writer.read { db in
            let tags = try NoteTag.order(Column("tag")).fetchAll(db)
            return tags.reduce(into: [String: [String]]()) { result, noteTag in
                result[noteTag.noteId, default: []].append(noteTag.tag)
            }
        }
    }

    public func fetchAllTags() throws -> [String] {
        try writer.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT tag FROM noteTag ORDER BY tag")
        }
    }

    public func deleteNote(id: String) throws {
        try writer.write { db in
            _ = try NoteTag.filter(Column("noteId") == id).deleteAll(db)
            _ = try Note.filter(Column("id") == id).deleteAll(db)
        }
    }
}
