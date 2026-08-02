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

        /// Articles imported from the web are ordinary books on disk — a generated EPUB — so
        /// they need one extra column and nothing else. Existing rows keep a NULL here, which
        /// is exactly what "this came from a file" means.
        migrator.registerMigration("v5_addBookSourceURL") { db in
            try db.alter(table: "book") { t in
                t.add(column: "sourceURL", .text)
            }
        }

        /// One search surface for reader-authored notes, saved highlights and library
        /// metadata. FTS rows deliberately keep stable entity ids instead of mirroring source
        /// rowids: UUID-backed records can be rebuilt or reindexed without coupling tables.
        migrator.registerMigration("v6_createGlobalSearchIndex") { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE searchIndex USING fts5(
                    entityType UNINDEXED,
                    entityID UNINDEXED,
                    bookID UNINDEXED,
                    title,
                    subtitle,
                    body,
                    tags,
                    tokenize = 'unicode61 remove_diacritics 2'
                )
                """)

            try db.execute(sql: """
                INSERT INTO searchIndex(entityType, entityID, bookID, title, subtitle, body, tags)
                SELECT
                    'book', id, id, title,
                    trim(coalesce(author, '') || ' ' || coalesce(sourceURL, '')),
                    '', ''
                FROM book
                """)

            try db.execute(sql: """
                INSERT INTO searchIndex(entityType, entityID, bookID, title, subtitle, body, tags)
                SELECT
                    'note', note.id, coalesce(note.bookId, ''), coalesce(note.title, ''), '',
                    note.body,
                    coalesce((SELECT group_concat(tag, ' ') FROM noteTag WHERE noteId = note.id), '')
                FROM note
                """)

            try db.execute(sql: """
                INSERT INTO searchIndex(entityType, entityID, bookID, title, subtitle, body, tags)
                SELECT
                    'highlight', highlight.id, highlight.bookId, book.title,
                    trim(coalesce(book.author, '') || ' ' || coalesce(book.sourceURL, '')),
                    highlight.text, ''
                FROM highlight
                JOIN book ON book.id = highlight.bookId
                """)
        }

        return migrator
    }

    // MARK: - Database Access

    public func saveBook(_ book: Book) throws {
        try writer.write { db in
            try book.save(db)
            try indexBook(book, in: db)
        }
    }

    /// An imported article is a regular book plus one FTS document containing its clean prose.
    /// Both become visible atomically, so search cannot return a publication whose library row
    /// failed to save (or miss the text of one that succeeded).
    public func saveArticle(_ book: Book, searchableText: String) throws {
        try writer.write { db in
            try book.save(db)
            try indexBook(book, in: db)
            try indexArticle(book, text: searchableText, in: db)
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
                try indexBook(book, in: db)

                // Highlight results display their publication title and byline. Keep those
                // denormalized labels current when metadata is edited.
                let highlights = try Highlight.filter(Column("bookId") == id).fetchAll(db)
                for highlight in highlights {
                    try indexHighlight(highlight, book: book, in: db)
                }

                try db.execute(
                    sql: "UPDATE searchIndex SET title = ?, subtitle = ? WHERE entityType = 'article' AND bookID = ?",
                    arguments: [book.title, book.sourceHost ?? "", book.id]
                )
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
            try db.execute(
                sql: "UPDATE searchIndex SET bookID = '' WHERE entityType = 'note' AND bookID = ?",
                arguments: [id]
            )
            try db.execute(
                sql: "DELETE FROM searchIndex WHERE (entityType = 'book' AND entityID = ?) OR (entityType IN ('highlight', 'article') AND bookID = ?)",
                arguments: [id, id]
            )
            _ = try Book.filter(Column("id") == id).deleteAll(db)
        }
    }

    // MARK: - Highlight CRUD

    public func saveHighlight(_ highlight: Highlight) throws {
        try writer.write { db in
            try highlight.save(db)
            if let book = try Book.filter(Column("id") == highlight.bookId).fetchOne(db) {
                try indexHighlight(highlight, book: book, in: db)
            }
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
            try deleteSearchDocument(type: .highlight, id: id, in: db)
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
            let normalizedTags = Set(tags.compactMap(NoteTag.normalized))
            for tag in normalizedTags {
                try NoteTag(noteId: note.id, tag: tag).insert(db)
            }
            try indexNote(note, tags: normalizedTags.sorted(), in: db)
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
            try deleteSearchDocument(type: .note, id: id, in: db)
        }
    }

    public func fetchNote(id: String) throws -> Note? {
        try writer.read { db in
            try Note.filter(Column("id") == id).fetchOne(db)
        }
    }

    public func fetchTags(forNoteID noteID: String) throws -> [String] {
        try writer.read { db in
            try NoteTag
                .filter(Column("noteId") == noteID)
                .order(Column("tag"))
                .fetchAll(db)
                .map(\.tag)
        }
    }

    /// Legacy web imports that predate article-body indexing. The existence check lives in SQL
    /// so opening Search does not read every EPUB just to discover that it is already indexed.
    public func fetchArticlesMissingTextIndex() throws -> [Book] {
        try writer.read { db in
            try Book.fetchAll(
                db,
                sql: """
                    SELECT book.*
                    FROM book
                    WHERE book.sourceURL IS NOT NULL
                      AND NOT EXISTS (
                          SELECT 1 FROM searchIndex
                          WHERE entityType = 'article' AND bookID = book.id
                      )
                    ORDER BY book.addedAt DESC
                    """
            )
        }
    }

    public func indexArticleText(book: Book, text: String) throws {
        try writer.write { db in
            try indexArticle(book, text: text, in: db)
        }
    }

    // MARK: - Global Search

    public func search(_ query: String, limit: Int = 60) throws -> [GlobalSearchResult] {
        guard let matchQuery = Self.ftsMatchQuery(query) else { return [] }

        return try writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT
                        entityType,
                        entityID,
                        nullif(bookID, '') AS bookID,
                        title,
                        subtitle,
                        snippet(searchIndex, 5, '', '', ' … ', 22) AS snippet
                    FROM searchIndex
                    WHERE searchIndex MATCH ?
                    ORDER BY
                        CASE entityType
                            WHEN 'note' THEN 0
                            WHEN 'highlight' THEN 1
                            WHEN 'book' THEN 2
                            ELSE 3
                        END,
                        bm25(searchIndex, 0.0, 0.0, 0.0, 5.0, 2.0, 1.0, 1.5)
                    LIMIT ?
                    """,
                arguments: [matchQuery, max(1, limit)]
            )

            return rows.compactMap { row in
                guard let rawKind: String = row["entityType"],
                      let kind = GlobalSearchKind(rawValue: rawKind),
                      let entityID: String = row["entityID"]
                else { return nil }

                let rawTitle: String = row["title"] ?? ""
                let title = rawTitle.isEmpty
                    ? (kind == .note ? "Untitled Note" : "Untitled")
                    : rawTitle
                return GlobalSearchResult(
                    kind: kind,
                    entityID: entityID,
                    bookID: row["bookID"],
                    title: title,
                    subtitle: row["subtitle"] ?? "",
                    snippet: row["snippet"] ?? ""
                )
            }
        }
    }

    private static func ftsMatchQuery(_ raw: String) -> String? {
        let tokens = raw
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).replacingOccurrences(of: "\"", with: "\"\"") }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " AND ")
    }

    private func indexBook(_ book: Book, in db: Database) throws {
        try deleteSearchDocument(type: .book, id: book.id, in: db)
        try db.execute(
            sql: """
                INSERT INTO searchIndex(entityType, entityID, bookID, title, subtitle, body, tags)
                VALUES ('book', ?, ?, ?, ?, '', '')
                """,
            arguments: [
                book.id,
                book.id,
                book.title,
                [book.author, book.sourceURL].compactMap { $0 }.joined(separator: " ")
            ]
        )
    }

    private func indexHighlight(_ highlight: Highlight, book: Book, in db: Database) throws {
        try deleteSearchDocument(type: .highlight, id: highlight.id, in: db)
        try db.execute(
            sql: """
                INSERT INTO searchIndex(entityType, entityID, bookID, title, subtitle, body, tags)
                VALUES ('highlight', ?, ?, ?, ?, ?, '')
                """,
            arguments: [
                highlight.id,
                highlight.bookId,
                book.title,
                [book.author, book.sourceURL].compactMap { $0 }.joined(separator: " "),
                highlight.text
            ]
        )
    }

    private func indexNote(_ note: Note, tags: [String], in db: Database) throws {
        try deleteSearchDocument(type: .note, id: note.id, in: db)
        try db.execute(
            sql: """
                INSERT INTO searchIndex(entityType, entityID, bookID, title, subtitle, body, tags)
                VALUES ('note', ?, ?, ?, '', ?, ?)
                """,
            arguments: [
                note.id,
                note.bookId ?? "",
                note.title ?? "",
                note.body,
                tags.joined(separator: " ")
            ]
        )
    }

    private func indexArticle(_ book: Book, text: String, in db: Database) throws {
        try deleteSearchDocument(type: .article, id: book.id, in: db)
        try db.execute(
            sql: """
                INSERT INTO searchIndex(entityType, entityID, bookID, title, subtitle, body, tags)
                VALUES ('article', ?, ?, ?, ?, ?, '')
                """,
            arguments: [book.id, book.id, book.title, book.sourceHost ?? "", text]
        )
    }

    private func deleteSearchDocument(type: GlobalSearchKind, id: String, in db: Database) throws {
        try db.execute(
            sql: "DELETE FROM searchIndex WHERE entityType = ? AND entityID = ?",
            arguments: [type.rawValue, id]
        )
    }
}
