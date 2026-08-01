import Foundation
import GRDB

public final class AppDatabase: Sendable {
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

    public func deleteBook(id: String) throws {
        try writer.write { db in
            _ = try Highlight.filter(Column("bookId") == id).deleteAll(db)
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

    public func deleteHighlight(id: String) throws {
        try writer.write { db in
            _ = try Highlight.filter(Column("id") == id).deleteAll(db)
        }
    }
}
