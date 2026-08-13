import Foundation
import GRDB

/// - Important: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would otherwise pin every query
///   to the main thread, which is exactly where reading-position writes must not happen.
///   GRDB's `DatabaseQueue` serializes access itself, so this type opts out of that default.
public nonisolated final class AppDatabase: Sendable {
    /// Why the on-disk library could not be opened, when it could not be.
    ///
    /// A corrupt SQLite file, a migration that fails halfway or an unwritable Application
    /// Support directory used to be a `fatalError`, which meant the app crashed on launch and
    /// kept crashing: the reader had no way back in, and with iCloud sync off by default the
    /// library, quotes and notes were only recoverable by deleting the app along with them.
    /// The failure is reported instead, and `dipleApp` shows a recovery screen rather than
    /// starting a session on top of a database that isn't there.
    public struct StartupFailure: Sendable {
        /// The database file that would not open, kept exactly where it was.
        public let fileURL: URL?
        public let reason: String
    }

    /// Opened once, together with whatever went wrong doing it, so both are immutable and
    /// there is no shared mutable static to synchronise.
    private static let opened: (database: AppDatabase, failure: StartupFailure?) = {
        var fileURL: URL? = nil
        do {
            let appSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dbURL = appSupportURL.appendingPathComponent("diple.sqlite")
            fileURL = dbURL
            var config = Configuration()
            config.qos = .userInitiated
            let dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)
            return (try AppDatabase(dbQueue, syncEnabled: true, signalsSyncService: true), nil)
        } catch {
            // A stand-in so `shared` stays non-optional and the recovery screen has something
            // inert to be built against. Nothing reads it: the root view blocks on
            // `startupFailure` before any screen that queries the library appears, and sync
            // never starts, so an empty in-memory database is never mistaken for an empty
            // library and never uploaded over the real one.
            let failure = StartupFailure(fileURL: fileURL, reason: "\(error)")
            if let standIn = try? AppDatabase(DatabaseQueue(), syncEnabled: false, signalsSyncService: false) {
                return (standIn, failure)
            }
            // Reached only if SQLite cannot allocate an in-memory database, which means the
            // process is already out of memory and has nothing left to run on.
            fatalError("Failed to open an in-memory database: \(error)")
        }
    }()

    public static var shared: AppDatabase { opened.database }

    /// `nil` when the library opened normally.
    public static var startupFailure: StartupFailure? { opened.failure }

    /// Moves the unreadable database aside so the next launch starts a fresh library, keeping
    /// the original file next to it — a database this app cannot open is not necessarily one
    /// that nothing can, and deleting a reader's only copy of their quotes is not a recovery.
    /// The renamed file is dated so a second attempt never overwrites the first.
    ///
    /// Reopening has to wait for the next launch: `shared` is resolved once per process.
    public static func quarantineDatabaseFile() throws -> URL? {
        guard let fileURL = startupFailure?.fileURL else { return nil }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let quarantined = fileURL.deletingLastPathComponent()
            .appendingPathComponent("diple-unreadable-\(stamp).sqlite")

        try fileManager.moveItem(at: fileURL, to: quarantined)
        // The write-ahead log and shared memory file belong to the database that just moved;
        // left behind, SQLite would try to replay them into the new one.
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: fileURL.path + suffix)
            guard fileManager.fileExists(atPath: sidecar.path) else { continue }
            try? fileManager.moveItem(at: sidecar, to: URL(fileURLWithPath: quarantined.path + suffix))
        }
        return quarantined
    }

    private let writer: any DatabaseWriter
    private let syncEnabled: Bool
    private let signalsSyncService: Bool

    public init(
        _ writer: any DatabaseWriter,
        syncEnabled: Bool = false,
        signalsSyncService: Bool = false
    ) throws {
        self.writer = writer
        self.syncEnabled = syncEnabled
        self.signalsSyncService = signalsSyncService
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

        /// CloudKit is not the primary store: SQLite remains fully usable offline. The outbox
        /// durably bridges committed local transactions to CKSyncEngine, while metadata keeps
        /// each record's last server system fields for optimistic conflict handling.
        migrator.registerMigration("v7_createCloudSyncState") { db in
            try db.create(table: "syncMetadata") { t in
                t.column("entityType", .text).notNull()
                t.column("entityID", .text).notNull()
                t.column("modifiedAt", .datetime).notNull()
                t.column("systemFields", .blob)
                t.primaryKey(["entityType", "entityID"])
            }

            try db.create(table: "syncOutbox") { t in
                t.column("entityType", .text).notNull()
                t.column("entityID", .text).notNull()
                t.column("operation", .text).notNull()
                t.column("modifiedAt", .datetime).notNull()
                t.primaryKey(["entityType", "entityID"])
            }

            try db.create(table: "syncState") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }
        }

        /// Additive, nullable, backfill-only. Quotes must survive the book they were cut from
        /// being deleted, so the title/author they display afterward has to live on the
        /// highlight itself rather than come from a `book` join that may no longer resolve.
        migrator.registerMigration("v8_addHighlightBookSnapshot") { db in
            try db.alter(table: "highlight") { t in
                t.add(column: "bookTitle", .text)
                t.add(column: "bookAuthor", .text)
            }
            try db.execute(sql: """
                UPDATE highlight
                SET bookTitle = (SELECT title FROM book WHERE book.id = highlight.bookId),
                    bookAuthor = (SELECT author FROM book WHERE book.id = highlight.bookId)
                """)
        }

        /// A second FTS5 table, deliberately separate from `searchIndex`: content needs its own
        /// bm25 weights and must be rebuildable per book (delete-then-reinsert its chunks)
        /// without touching every other kind of search document. Like `searchIndex` it is a
        /// derived local index — not synced, not backed up, safe to drop and rebuild.
        /// `bookContentIndex` is the resumable-backfill ledger: one row per book that has been
        /// swept, so a restart never re-parses a book it already finished (or already gave up
        /// on for lacking any extractable text).
        migrator.registerMigration("v9_createBookContentIndex") { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE bookContent USING fts5(
                    bookID UNINDEXED,
                    href UNINDEXED,
                    chapterTitle,
                    ordinal UNINDEXED,
                    locatorJSON UNINDEXED,
                    body,
                    tokenize = 'unicode61 remove_diacritics 2',
                    prefix = '2 3'
                )
                """)

            try db.create(table: "bookContentIndex") { t in
                t.column("bookID", .text).primaryKey()
                t.column("indexedAt", .datetime).notNull()
                t.column("chunkCount", .integer).notNull()
            }
        }

        /// Reader comments belong to the quote itself: they must survive deletion of the
        /// source book and travel with the existing DipleHighlight CloudKit record.
        migrator.registerMigration("v10_addHighlightComment") { db in
            try db.alter(table: "highlight") { t in
                t.add(column: "comment", .text)
            }
        }

        /// A web article is stored as an EPUB, which made file-extension checks lie about what
        /// the reader had actually saved. Backfill the explicit kind from the two facts older
        /// versions did preserve, then let all future imports and CloudKit records carry it.
        migrator.registerMigration("v11_addBookSourceKind") { db in
            try db.alter(table: "book") { t in
                t.add(column: "sourceKind", .text).notNull().defaults(to: PublicationKind.epub.rawValue)
            }
            try db.execute(
                sql: "UPDATE book SET sourceKind = ? WHERE lower(filePath) LIKE '%.pdf'",
                arguments: [PublicationKind.pdf.rawValue]
            )
            try db.execute(
                sql: "UPDATE book SET sourceKind = ? WHERE sourceURL IS NOT NULL",
                arguments: [PublicationKind.article.rawValue]
            )
        }

        return migrator
    }

    // MARK: - Database Access

    public func saveBook(_ book: Book) throws {
        try writer.write { db in
            try book.save(db)
            try indexBook(book, in: db)
            try markLocalSave(.book, id: book.id, at: book.addedAt, in: db)
            try markLocalSave(.bookAsset, id: book.id, at: book.addedAt, in: db)
        }
        signalSyncIfNeeded()
    }

    /// An imported article is a regular book plus one FTS document containing its clean prose.
    /// Both become visible atomically, so search cannot return a publication whose library row
    /// failed to save (or miss the text of one that succeeded).
    public func saveArticle(_ book: Book, searchableText: String) throws {
        try writer.write { db in
            try book.save(db)
            try indexBook(book, in: db)
            try indexArticle(book, text: searchableText, in: db)
            try markLocalSave(.book, id: book.id, at: book.addedAt, in: db)
            try markLocalSave(.bookAsset, id: book.id, at: book.addedAt, in: db)
        }
        signalSyncIfNeeded()
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
                try markLocalSave(.book, id: id, at: lastOpenedAt, in: db)
            }
        }
        signalSyncIfNeeded()
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

                let changedAt = Date()

                // Highlight results display their publication title and byline, and now carry
                // a durable snapshot of both so a quote can outlive its book. Keep every
                // highlight's copy current when metadata is edited, and push the change like
                // any other save so synced devices pick up the new snapshot too.
                var highlights = try Highlight.filter(Column("bookId") == id).fetchAll(db)
                for i in highlights.indices {
                    highlights[i].bookTitle = book.title
                    highlights[i].bookAuthor = book.author
                    try highlights[i].update(db)
                    try indexHighlight(highlights[i], book: book, in: db)
                    try markLocalSave(.highlight, id: highlights[i].id, at: changedAt, in: db)
                }

                try db.execute(
                    sql: "UPDATE searchIndex SET title = ?, subtitle = ? WHERE entityType = 'article' AND bookID = ?",
                    arguments: [book.title, book.sourceHost ?? "", book.id]
                )
                try markLocalSave(.book, id: id, at: changedAt, in: db)
                if coverPath != nil {
                    try markLocalSave(.bookAsset, id: id, at: changedAt, in: db)
                }
            }
        }
        signalSyncIfNeeded()
    }

    public func deleteBook(id: String) throws {
        try writer.write { db in
            let bookmarkIDs = try String.fetchAll(
                db,
                sql: "SELECT id FROM bookmark WHERE bookId = ?",
                arguments: [id]
            )
            let linkedNoteIDs = try String.fetchAll(
                db,
                sql: "SELECT id FROM note WHERE bookId = ?",
                arguments: [id]
            )
            let book = try Book.filter(Column("id") == id).fetchOne(db)

            _ = try Bookmark.filter(Column("bookId") == id).deleteAll(db)

            // Quotes outlive the book they were cut from: only the bookmark and the library
            // row disappear here. `bookId` is left dangling on purpose — there is no foreign
            // key — and the snapshot frozen into the highlight (and its FTS document) is what
            // the hub and search fall back to from now on. No outbox entry is written for the
            // highlights themselves: they were never deleted, so there is nothing to sync.
            if let book {
                let subtitle = [book.author, book.sourceURL].compactMap { $0 }.joined(separator: " ")
                try db.execute(
                    sql: "UPDATE highlight SET bookTitle = ?, bookAuthor = ? WHERE bookId = ?",
                    arguments: [book.title, book.author, id]
                )
                try db.execute(
                    sql: "UPDATE searchIndex SET title = ?, subtitle = ? WHERE entityType = 'highlight' AND bookID = ?",
                    arguments: [book.title, subtitle, id]
                )
            }

            // Notes are the user's own writing and survive the book they referenced;
            // only the tag pointing at it goes away.
            try db.execute(sql: "UPDATE note SET bookId = NULL WHERE bookId = ?", arguments: [id])
            try db.execute(
                sql: "UPDATE searchIndex SET bookID = '' WHERE entityType = 'note' AND bookID = ?",
                arguments: [id]
            )
            try db.execute(
                sql: "DELETE FROM searchIndex WHERE (entityType = 'book' AND entityID = ?) OR (entityType = 'article' AND bookID = ?)",
                arguments: [id, id]
            )
            _ = try Book.filter(Column("id") == id).deleteAll(db)

            let changedAt = Date()
            for bookmarkID in bookmarkIDs {
                try markLocalDelete(.bookmark, id: bookmarkID, at: changedAt, in: db)
            }
            for noteID in linkedNoteIDs {
                try db.execute(
                    sql: "UPDATE note SET updatedAt = ? WHERE id = ?",
                    arguments: [changedAt, noteID]
                )
                try markLocalSave(.note, id: noteID, at: changedAt, in: db)
            }
            try markLocalDelete(.book, id: id, at: changedAt, in: db)
            try markLocalDelete(.bookAsset, id: id, at: changedAt, in: db)
        }
        signalSyncIfNeeded()
    }

    // MARK: - Highlight CRUD

    public func saveHighlight(_ highlight: Highlight) throws {
        try writer.write { db in
            var highlight = highlight
            let book = try Book.filter(Column("id") == highlight.bookId).fetchOne(db)
            if let book {
                highlight.bookTitle = book.title
                highlight.bookAuthor = book.author
            }
            try highlight.save(db)
            try indexHighlight(highlight, book: book, in: db)
            try markLocalSave(.highlight, id: highlight.id, at: highlight.createdAt, in: db)
        }
        signalSyncIfNeeded()
    }

    public func fetchHighlights(forBookId bookId: String) throws -> [Highlight] {
        try writer.read { db in
            try Highlight.filter(Column("bookId") == bookId).order(Column("createdAt").desc).fetchAll(db)
        }
    }

    public func updateHighlightComment(id: String, comment: String?, changedAt: Date = Date()) throws {
        try writer.write { db in
            guard var highlight = try Highlight.filter(Column("id") == id).fetchOne(db) else {
                return
            }
            let trimmed = comment?.trimmingCharacters(in: .whitespacesAndNewlines)
            highlight.comment = (trimmed?.isEmpty ?? true) ? nil : trimmed
            try highlight.update(db)
            let book = try Book.filter(Column("id") == highlight.bookId).fetchOne(db)
            try indexHighlight(highlight, book: book, in: db)
            try markLocalSave(.highlight, id: id, at: changedAt, in: db)
        }
        signalSyncIfNeeded()
    }

    /// Quotes are deliberately fetched independently of their books: a saved passage may
    /// outlive the publication it came from, and resurfacing should still bring it back.
    public func fetchAllHighlights() throws -> [Highlight] {
        try writer.read { db in
            try Highlight.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    /// One row per book id that still holds quotes, grouped straight from `highlight` — a book
    /// row is only consulted afterward, by the caller, so a deleted book still produces a
    /// group instead of silently dropping out of the hub.
    public func fetchHighlightGroups() throws -> [HighlightGroup] {
        try writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT
                    bookId,
                    COUNT(*) AS quoteCount,
                    MAX(bookTitle) AS bookTitle,
                    MAX(bookAuthor) AS bookAuthor
                FROM highlight
                GROUP BY bookId
                ORDER BY MAX(createdAt) DESC
                """)
            return rows.map { row in
                HighlightGroup(
                    bookId: row["bookId"],
                    quoteCount: row["quoteCount"],
                    bookTitle: row["bookTitle"],
                    bookAuthor: row["bookAuthor"]
                )
            }
        }
    }

    public func deleteHighlight(id: String) throws {
        try writer.write { db in
            _ = try Highlight.filter(Column("id") == id).deleteAll(db)
            try deleteSearchDocument(type: .highlight, id: id, in: db)
            try markLocalDelete(.highlight, id: id, at: Date(), in: db)
        }
        signalSyncIfNeeded()
    }

    // MARK: - Bookmark CRUD

    public func saveBookmark(_ bookmark: Bookmark) throws {
        try writer.write { db in
            try bookmark.save(db)
            try markLocalSave(.bookmark, id: bookmark.id, at: bookmark.createdAt, in: db)
        }
        signalSyncIfNeeded()
    }

    public func fetchBookmarks(forBookId bookId: String) throws -> [Bookmark] {
        try writer.read { db in
            try Bookmark.filter(Column("bookId") == bookId).order(Column("createdAt").desc).fetchAll(db)
        }
    }

    public func deleteBookmark(id: String) throws {
        try writer.write { db in
            _ = try Bookmark.filter(Column("id") == id).deleteAll(db)
            try markLocalDelete(.bookmark, id: id, at: Date(), in: db)
        }
        signalSyncIfNeeded()
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
            try markLocalSave(.note, id: note.id, at: note.updatedAt, in: db)
        }
        signalSyncIfNeeded()
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
            try markLocalDelete(.note, id: id, at: Date(), in: db)
        }
        signalSyncIfNeeded()
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

    // MARK: - Book Content Index

    /// Books whose own prose has never been swept into `bookContent`. Articles are excluded:
    /// their body already lives in `searchIndex` as an `article` document, and indexing them
    /// again here would surface every hit twice. The existence check lives in SQL for the same
    /// reason as `fetchArticlesMissingTextIndex` — opening Search must not itself read a whole
    /// already-indexed library just to find out there is nothing left to do.
    public func fetchBooksMissingContentIndex() throws -> [Book] {
        try writer.read { db in
            try Book.fetchAll(
                db,
                sql: """
                    SELECT book.*
                    FROM book
                    WHERE book.sourceURL IS NULL
                      AND NOT EXISTS (
                          SELECT 1 FROM bookContentIndex WHERE bookContentIndex.bookID = book.id
                      )
                    ORDER BY book.addedAt DESC
                    """
            )
        }
    }

    /// Replaces one book's chunks in a single transaction — the resumable backfill never holds
    /// a write transaction across more than one book, so an in-progress read (search, or the
    /// reader itself) is never blocked for longer than one book's worth of inserts.
    public func indexBookContent(book: Book, chunks: [BookContentChunk]) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM bookContent WHERE bookID = ?", arguments: [book.id])
            for (ordinal, chunk) in chunks.enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO bookContent(bookID, href, chapterTitle, ordinal, locatorJSON, body)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [book.id, chunk.href, chunk.chapterTitle, ordinal, chunk.locatorJSON, chunk.body]
                )
            }
            try db.execute(
                sql: """
                    INSERT INTO bookContentIndex(bookID, indexedAt, chunkCount)
                    VALUES (?, ?, ?)
                    ON CONFLICT(bookID) DO UPDATE SET
                        indexedAt = excluded.indexedAt,
                        chunkCount = excluded.chunkCount
                    """,
                arguments: [book.id, Date(), chunks.count]
            )
        }
    }

    /// Whether `bookID` has ever been swept into `bookContent`, not whether it has any rows.
    /// A book with genuinely no extractable text is swept with zero chunks and must read as
    /// "no matches", while a book the backfill has not reached yet has no `bookContentIndex`
    /// row at all and must read as "still indexing" — the same zero-row result from
    /// `searchBookContent` alone cannot tell those two apart.
    public func isBookContentIndexed(bookID: String) throws -> Bool {
        try writer.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM bookContentIndex WHERE bookID = ?)",
                arguments: [bookID]
            ) ?? false
        }
    }

    /// Scopes task 7's own `bookContent` index to one book — the reader's in-book search sheet
    /// reuses the exact index built for cross-library search rather than a second parallel
    /// implementation, which also covers PDFs for free (indexed page-by-page there already).
    /// Ordered by `ordinal` (reading order) rather than bm25 relevance: a search inside the
    /// single open book reads like a find-in-page pass through the text, not a ranked pick
    /// from the whole library.
    public func searchBookContent(bookID: String, query: String, limit: Int = 200) throws -> [BookSearchHit] {
        guard let matchQuery = Self.ftsMatchQuery(query) else { return [] }

        return try writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT
                        rowid AS chunkID,
                        href,
                        chapterTitle,
                        locatorJSON,
                        snippet(bookContent, 5, ?, ?, ' … ', 24) AS snippet
                    FROM bookContent
                    WHERE bookContent MATCH ? AND bookID = ?
                    ORDER BY ordinal
                    LIMIT ?
                    """,
                arguments: [
                    BookSearchHit.matchMarkerStart,
                    BookSearchHit.matchMarkerEnd,
                    matchQuery,
                    bookID,
                    max(1, limit)
                ]
            )

            return rows.compactMap { row in
                guard let chunkID: Int64 = row["chunkID"],
                      let locatorJSON: String = row["locatorJSON"]
                else { return nil }
                let chapterTitle: String = row["chapterTitle"] ?? ""
                return BookSearchHit(
                    id: String(chunkID),
                    chapterTitle: chapterTitle.isEmpty ? "Untitled" : chapterTitle,
                    href: row["href"] ?? "",
                    snippet: row["snippet"] ?? "",
                    locatorJSON: locatorJSON
                )
            }
        }
    }

    // MARK: - Global Search

    public func search(_ query: String, limit: Int = 60) throws -> [GlobalSearchResult] {
        guard let matchQuery = Self.ftsMatchQuery(query) else { return [] }
        let highlightBodyQuery = "body : (\(matchQuery))"

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
                      AND (
                          entityType != 'highlight'
                          OR rowid IN (
                              SELECT rowid FROM searchIndex WHERE searchIndex MATCH ?
                          )
                      )
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
                arguments: [matchQuery, highlightBodyQuery, max(1, limit)]
            )

            let metadataResults: [GlobalSearchResult] = rows.compactMap { row in
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

            // Own query, own bm25 weights, own table: `bookContent` is not part of
            // `searchIndex` (see the v9 migration note), so it cannot share the query above.
            let contentRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT
                        bookContent.rowid AS chunkID,
                        bookContent.bookID,
                        bookContent.chapterTitle,
                        bookContent.locatorJSON,
                        book.filePath AS bookFilePath,
                        snippet(bookContent, 5, '', '', ' … ', 20) AS snippet
                    FROM bookContent
                    JOIN book ON book.id = bookContent.bookID
                    WHERE bookContent MATCH ?
                    ORDER BY bm25(bookContent, 0.0, 0.0, 3.0, 0.0, 0.0, 1.0)
                    LIMIT ?
                    """,
                arguments: [matchQuery, max(1, limit)]
            )

            let contentResults: [GlobalSearchResult] = contentRows.compactMap { row in
                guard let chunkID: Int64 = row["chunkID"],
                      let bookID: String = row["bookID"],
                      let locatorJSON: String = row["locatorJSON"]
                else { return nil }

                let chapterTitle: String = row["chapterTitle"] ?? ""
                let bookFilePath: String = row["bookFilePath"] ?? ""
                let bookFileName = URL(fileURLWithPath: bookFilePath).lastPathComponent
                return GlobalSearchResult(
                    kind: .bookContent,
                    entityID: String(chunkID),
                    bookID: bookID,
                    title: bookFileName.isEmpty ? "Untitled" : bookFileName,
                    subtitle: chapterTitle,
                    snippet: row["snippet"] ?? "",
                    locatorJSON: locatorJSON
                )
            }

            return metadataResults + contentResults
        }
    }

    /// Every token becomes an exact match except the last, which stays a prefix — while the
    /// user is mid-word the final token is unfinished, but the earlier ones are already
    /// complete and a stray prefix match there only widens results without helping relevance.
    private static func ftsMatchQuery(_ raw: String) -> String? {
        let tokens = raw
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).replacingOccurrences(of: "\"", with: "\"\"") }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.enumerated()
            .map { index, token in index == tokens.count - 1 ? "\"\(token)\"*" : "\"\(token)\"" }
            .joined(separator: " AND ")
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

    /// `book` is the live row when it still exists; a highlight whose book is gone falls back
    /// to the snapshot taken at save time, which is what keeps it searchable under its former
    /// title instead of disappearing from the index along with the book.
    private func indexHighlight(_ highlight: Highlight, book: Book?, in db: Database) throws {
        try deleteSearchDocument(type: .highlight, id: highlight.id, in: db)
        let title = book?.title ?? highlight.bookTitle ?? ""
        let subtitle = [book?.author ?? highlight.bookAuthor, book?.sourceURL]
            .compactMap { $0 }
            .joined(separator: " ")
        try db.execute(
            sql: """
                INSERT INTO searchIndex(entityType, entityID, bookID, title, subtitle, body, tags)
                VALUES ('highlight', ?, ?, ?, ?, ?, '')
                """,
            arguments: [
                highlight.id,
                highlight.bookId,
                title,
                subtitle,
                [highlight.text, highlight.comment].compactMap { $0 }.joined(separator: " ")
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

    // MARK: - Cloud Sync Bridge

    /// Adds every pre-sync-installation object exactly once. Later edits use the same outbox,
    /// so initial migration and normal operation share one delivery path.
    public func prepareInitialSync() throws {
        try writer.write { db in
            let didBootstrap = try String.fetchOne(
                db,
                sql: "SELECT value FROM syncState WHERE key = 'initialUploadQueued'"
            ) == "1"
            guard !didBootstrap else { return }

            for book in try Book.fetchAll(db) {
                let changedAt = book.lastOpenedAt ?? book.addedAt
                try markLocalSave(.book, id: book.id, at: changedAt, in: db)
                try markLocalSave(.bookAsset, id: book.id, at: book.addedAt, in: db)
            }
            for highlight in try Highlight.fetchAll(db) {
                try markLocalSave(.highlight, id: highlight.id, at: highlight.createdAt, in: db)
            }
            for bookmark in try Bookmark.fetchAll(db) {
                try markLocalSave(.bookmark, id: bookmark.id, at: bookmark.createdAt, in: db)
            }
            for note in try Note.fetchAll(db) {
                try markLocalSave(.note, id: note.id, at: note.updatedAt, in: db)
            }
            // A fresh device's defaults must lose to any real settings already in iCloud.
            try markLocalSave(.settings, id: "current", at: Date(timeIntervalSince1970: 0), in: db)
            try db.execute(
                sql: "INSERT OR REPLACE INTO syncState(key, value) VALUES ('initialUploadQueued', '1')"
            )
        }
    }

    /// An iCloud account change needs a fresh upload into the new private database.
    public func queueFullResync() throws {
        try writer.write { db in
            for book in try Book.fetchAll(db) {
                let changedAt = max(book.lastOpenedAt ?? .distantPast, book.addedAt)
                try markLocalSave(.book, id: book.id, at: changedAt, in: db)
                try markLocalSave(.bookAsset, id: book.id, at: changedAt, in: db)
            }
            for highlight in try Highlight.fetchAll(db) {
                try markLocalSave(.highlight, id: highlight.id, at: highlight.createdAt, in: db)
            }
            for bookmark in try Bookmark.fetchAll(db) {
                try markLocalSave(.bookmark, id: bookmark.id, at: bookmark.createdAt, in: db)
            }
            for note in try Note.fetchAll(db) {
                try markLocalSave(.note, id: note.id, at: note.updatedAt, in: db)
            }
            try markLocalSave(.settings, id: "current", at: Date(), in: db)
        }
        signalSyncIfNeeded()
    }

    public func markSettingsChanged(at date: Date = Date()) throws {
        try writer.write { db in
            try markLocalSave(.settings, id: "current", at: date, in: db)
        }
        signalSyncIfNeeded()
    }

    public func fetchSyncOutbox() throws -> [SyncOutboxEntry] {
        try writer.read { db in
            try SyncOutboxEntry.fetchAll(db, sql: "SELECT * FROM syncOutbox ORDER BY modifiedAt")
        }
    }

    public func fetchSyncMetadata(entity: SyncEntityType, id: String) throws -> SyncMetadata? {
        try writer.read { db in
            try SyncMetadata.fetchOne(
                db,
                sql: "SELECT * FROM syncMetadata WHERE entityType = ? AND entityID = ?",
                arguments: [entity.rawValue, id]
            )
        }
    }

    public func shouldAcceptRemoteChange(entity: SyncEntityType, id: String, modifiedAt: Date) throws -> Bool {
        try writer.read { db in
            try shouldAcceptRemote(entity, id: id, modifiedAt: modifiedAt, in: db)
        }
    }

    public func fetchBookForSync(id: String) throws -> Book? { try fetchBook(id: id) }

    public func fetchHighlightForSync(id: String) throws -> Highlight? {
        try writer.read { db in
            try Highlight.filter(Column("id") == id).fetchOne(db)
        }
    }

    public func fetchBookmarkForSync(id: String) throws -> Bookmark? {
        try writer.read { db in
            try Bookmark.filter(Column("id") == id).fetchOne(db)
        }
    }

    public func fetchNoteForSync(id: String) throws -> SyncedNote? {
        try writer.read { db in
            guard let note = try Note.filter(Column("id") == id).fetchOne(db) else { return nil }
            let tags = try NoteTag
                .filter(Column("noteId") == id)
                .order(Column("tag"))
                .fetchAll(db)
                .map(\.tag)
            return SyncedNote(note: note, tags: tags)
        }
    }

    /// Returns false when an unsent local edit is newer than the server record.
    @discardableResult
    public func applyRemoteBook(_ book: Book, modifiedAt: Date, systemFields: Data) throws -> Bool {
        try writer.write { db in
            guard try shouldAcceptRemote(.book, id: book.id, modifiedAt: modifiedAt, in: db) else {
                return false
            }
            try book.save(db)
            try indexBook(book, in: db)
            try storeRemoteMetadata(.book, id: book.id, modifiedAt: modifiedAt, systemFields: systemFields, in: db)
            return true
        }
    }

    @discardableResult
    public func applyRemoteHighlight(_ highlight: Highlight, modifiedAt: Date, systemFields: Data) throws -> Bool {
        try writer.write { db in
            guard try shouldAcceptRemote(.highlight, id: highlight.id, modifiedAt: modifiedAt, in: db) else {
                return false
            }
            var highlight = highlight
            let book = try Book.filter(Column("id") == highlight.bookId).fetchOne(db)
            // A record saved before this device's snapshot columns existed decodes with a nil
            // title/author; a book that is still around locally is the only place left to
            // recover them. A record that already carries its own snapshot is left alone.
            if let book {
                highlight.bookTitle = highlight.bookTitle ?? book.title
                highlight.bookAuthor = highlight.bookAuthor ?? book.author
            }
            try highlight.save(db)
            try indexHighlight(highlight, book: book, in: db)
            try storeRemoteMetadata(.highlight, id: highlight.id, modifiedAt: modifiedAt, systemFields: systemFields, in: db)
            return true
        }
    }

    @discardableResult
    public func applyRemoteBookmark(_ bookmark: Bookmark, modifiedAt: Date, systemFields: Data) throws -> Bool {
        try writer.write { db in
            guard try shouldAcceptRemote(.bookmark, id: bookmark.id, modifiedAt: modifiedAt, in: db) else {
                return false
            }
            try bookmark.save(db)
            try storeRemoteMetadata(.bookmark, id: bookmark.id, modifiedAt: modifiedAt, systemFields: systemFields, in: db)
            return true
        }
    }

    @discardableResult
    public func applyRemoteNote(_ syncedNote: SyncedNote, modifiedAt: Date, systemFields: Data) throws -> Bool {
        try writer.write { db in
            let note = syncedNote.note
            guard try shouldAcceptRemote(.note, id: note.id, modifiedAt: modifiedAt, in: db) else {
                return false
            }
            try note.save(db)
            _ = try NoteTag.filter(Column("noteId") == note.id).deleteAll(db)
            let tags = Set(syncedNote.tags.compactMap(NoteTag.normalized))
            for tag in tags {
                try NoteTag(noteId: note.id, tag: tag).insert(db)
            }
            try indexNote(note, tags: tags.sorted(), in: db)
            try storeRemoteMetadata(.note, id: note.id, modifiedAt: modifiedAt, systemFields: systemFields, in: db)
            return true
        }
    }

    /// Assets have their own record, so progress updates never upload a multi-megabyte EPUB.
    @discardableResult
    public func applyRemoteBookAssetMetadata(id: String, modifiedAt: Date, systemFields: Data) throws -> Bool {
        try writer.write { db in
            guard try shouldAcceptRemote(.bookAsset, id: id, modifiedAt: modifiedAt, in: db) else {
                return false
            }
            try storeRemoteMetadata(.bookAsset, id: id, modifiedAt: modifiedAt, systemFields: systemFields, in: db)
            return true
        }
    }

    @discardableResult
    public func applyRemoteSettingsMetadata(modifiedAt: Date, systemFields: Data) throws -> Bool {
        try writer.write { db in
            guard try shouldAcceptRemote(.settings, id: "current", modifiedAt: modifiedAt, in: db) else {
                return false
            }
            try storeRemoteMetadata(.settings, id: "current", modifiedAt: modifiedAt, systemFields: systemFields, in: db)
            return true
        }
    }

    /// Applies a server deletion unless the device has a newer unsent save for that object.
    @discardableResult
    public func applyRemoteDeletion(entity: SyncEntityType, id: String) throws -> Bool {
        try writer.write { db in
            let pendingSave = try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM syncOutbox WHERE entityType = ? AND entityID = ? AND operation = 'save')",
                arguments: [entity.rawValue, id]
            ) ?? false
            guard !pendingSave else { return false }

            switch entity {
            case .book:
                let linkedNoteIDs = try String.fetchAll(
                    db,
                    sql: "SELECT id FROM note WHERE bookId = ?",
                    arguments: [id]
                )
                // Only bookmarks are still cascade-deleted with the book; a remote book
                // deletion must leave the same trail as a local one — highlights survive it.
                let childKeys = try Row.fetchAll(
                    db,
                    sql: "SELECT 'bookmark' AS entityType, id AS entityID FROM bookmark WHERE bookId = ?",
                    arguments: [id]
                )
                let book = try Book.filter(Column("id") == id).fetchOne(db)
                _ = try Bookmark.filter(Column("bookId") == id).deleteAll(db)
                if let book {
                    let subtitle = [book.author, book.sourceURL].compactMap { $0 }.joined(separator: " ")
                    try db.execute(
                        sql: "UPDATE highlight SET bookTitle = ?, bookAuthor = ? WHERE bookId = ?",
                        arguments: [book.title, book.author, id]
                    )
                    try db.execute(
                        sql: "UPDATE searchIndex SET title = ?, subtitle = ? WHERE entityType = 'highlight' AND bookID = ?",
                        arguments: [book.title, subtitle, id]
                    )
                }
                try db.execute(sql: "UPDATE note SET bookId = NULL WHERE bookId = ?", arguments: [id])
                try db.execute(
                    sql: "UPDATE searchIndex SET bookID = '' WHERE entityType = 'note' AND bookID = ?",
                    arguments: [id]
                )
                try db.execute(
                    sql: "DELETE FROM searchIndex WHERE (entityType = 'book' AND entityID = ?) OR (entityType = 'article' AND bookID = ?)",
                    arguments: [id, id]
                )
                _ = try Book.filter(Column("id") == id).deleteAll(db)
                for row in childKeys {
                    let childEntity: String = row["entityType"]
                    let childID: String = row["entityID"]
                    try db.execute(
                        sql: "DELETE FROM syncOutbox WHERE entityType = ? AND entityID = ?",
                        arguments: [childEntity, childID]
                    )
                    try db.execute(
                        sql: "DELETE FROM syncMetadata WHERE entityType = ? AND entityID = ?",
                        arguments: [childEntity, childID]
                    )
                }
                for noteID in linkedNoteIDs {
                    let changedAt = Date()
                    try db.execute(
                        sql: "UPDATE note SET updatedAt = ? WHERE id = ?",
                        arguments: [changedAt, noteID]
                    )
                    try markLocalSave(.note, id: noteID, at: changedAt, in: db)
                }
            case .highlight:
                _ = try Highlight.filter(Column("id") == id).deleteAll(db)
                try deleteSearchDocument(type: .highlight, id: id, in: db)
            case .bookmark:
                _ = try Bookmark.filter(Column("id") == id).deleteAll(db)
            case .note:
                _ = try NoteTag.filter(Column("noteId") == id).deleteAll(db)
                _ = try Note.filter(Column("id") == id).deleteAll(db)
                try deleteSearchDocument(type: .note, id: id, in: db)
            case .bookAsset, .settings:
                break
            }
            try db.execute(
                sql: "DELETE FROM syncMetadata WHERE entityType = ? AND entityID = ?",
                arguments: [entity.rawValue, id]
            )
            return true
        }
    }

    public func acknowledgeSavedRecord(
        entity: SyncEntityType,
        id: String,
        modifiedAt: Date,
        systemFields: Data
    ) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO syncMetadata(entityType, entityID, modifiedAt, systemFields)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(entityType, entityID) DO UPDATE SET
                        modifiedAt = max(syncMetadata.modifiedAt, excluded.modifiedAt),
                        systemFields = excluded.systemFields
                    """,
                arguments: [entity.rawValue, id, modifiedAt, systemFields]
            )
            try db.execute(
                sql: "DELETE FROM syncOutbox WHERE entityType = ? AND entityID = ? AND modifiedAt <= ?",
                arguments: [entity.rawValue, id, modifiedAt]
            )
        }
    }

    public func acknowledgeDeletedRecord(entity: SyncEntityType, id: String) throws {
        try writer.write { db in
            try db.execute(
                sql: "DELETE FROM syncOutbox WHERE entityType = ? AND entityID = ? AND operation = 'delete'",
                arguments: [entity.rawValue, id]
            )
            try db.execute(
                sql: "DELETE FROM syncMetadata WHERE entityType = ? AND entityID = ?",
                arguments: [entity.rawValue, id]
            )
        }
    }

    public func clearServerSystemFields(entity: SyncEntityType, id: String) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE syncMetadata SET systemFields = NULL WHERE entityType = ? AND entityID = ?",
                arguments: [entity.rawValue, id]
            )
        }
    }

    private func markLocalSave(_ entity: SyncEntityType, id: String, at date: Date, in db: Database) throws {
        try markLocalChange(entity, id: id, operation: .save, at: date, in: db)
    }

    private func markLocalDelete(_ entity: SyncEntityType, id: String, at date: Date, in db: Database) throws {
        try markLocalChange(entity, id: id, operation: .delete, at: date, in: db)
    }

    private func markLocalChange(
        _ entity: SyncEntityType,
        id: String,
        operation: SyncOperation,
        at date: Date,
        in db: Database
    ) throws {
        guard syncEnabled else { return }
        try db.execute(
            sql: """
                INSERT INTO syncMetadata(entityType, entityID, modifiedAt, systemFields)
                VALUES (?, ?, ?, NULL)
                ON CONFLICT(entityType, entityID) DO UPDATE SET modifiedAt = excluded.modifiedAt
                """,
            arguments: [entity.rawValue, id, date]
        )
        try db.execute(
            sql: """
                INSERT INTO syncOutbox(entityType, entityID, operation, modifiedAt)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(entityType, entityID) DO UPDATE SET
                    operation = excluded.operation,
                    modifiedAt = excluded.modifiedAt
                """,
            arguments: [entity.rawValue, id, operation.rawValue, date]
        )
    }

    private func shouldAcceptRemote(
        _ entity: SyncEntityType,
        id: String,
        modifiedAt: Date,
        in db: Database
    ) throws -> Bool {
        let localDate = try Date.fetchOne(
            db,
            sql: "SELECT modifiedAt FROM syncMetadata WHERE entityType = ? AND entityID = ?",
            arguments: [entity.rawValue, id]
        )
        return localDate == nil || modifiedAt >= (localDate ?? .distantPast)
    }

    private func storeRemoteMetadata(
        _ entity: SyncEntityType,
        id: String,
        modifiedAt: Date,
        systemFields: Data,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT OR REPLACE INTO syncMetadata(entityType, entityID, modifiedAt, systemFields)
                VALUES (?, ?, ?, ?)
                """,
            arguments: [entity.rawValue, id, modifiedAt, systemFields]
        )
        try db.execute(
            sql: "DELETE FROM syncOutbox WHERE entityType = ? AND entityID = ? AND modifiedAt <= ?",
            arguments: [entity.rawValue, id, modifiedAt]
        )
    }

    private func signalSyncIfNeeded() {
        guard syncEnabled, signalsSyncService else { return }
        CloudSyncService.signalLocalChanges()
    }
}
