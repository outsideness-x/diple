import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A documented, dependency-free snapshot of everything the reader created in diple. Source
/// files are intentionally not copied: EPUB/PDF imports already belong to the user, while the
/// portable value here is reading position, saved passages, reflections and
/// notes. Stable ids preserve relationships for a future importer or any outside script.
public nonisolated struct DipleExportPayload: Codable, Sendable {
    public static let currentVersion = 2

    public nonisolated struct Source: Codable, Sendable {
        public let id: String
        public let title: String
        public let author: String?
        public let kind: PublicationKind
        public let originalURL: String?
        public let addedAt: Date
        public let lastOpenedAt: Date?
        public let progress: Double
        public let readingPosition: String?
    }

    public nonisolated struct TaggedNote: Codable, Sendable {
        public let note: Note
        public let tags: [String]
    }

    public let format: String
    public let version: Int
    public let exportedAt: Date
    public let sources: [Source]
    public let highlights: [Highlight]
    public let notes: [TaggedNote]

    public init(database: AppDatabase = .shared, exportedAt: Date = Date()) throws {
        let books = try database.fetchAllBooks()
        let tagsByNote = try database.fetchTagsByNote()
        self.format = "diple-export"
        self.version = Self.currentVersion
        self.exportedAt = exportedAt
        self.sources = books.map {
            Source(
                id: $0.id,
                title: $0.title,
                author: $0.author,
                kind: $0.sourceKind,
                originalURL: $0.sourceURL,
                addedAt: $0.addedAt,
                lastOpenedAt: $0.lastOpenedAt,
                progress: $0.progress,
                readingPosition: $0.locator
            )
        }
        self.highlights = try database.fetchAllHighlights()
        self.notes = try database.fetchAllNotes().map {
            TaggedNote(note: $0, tags: tagsByNote[$0.id] ?? [])
        }
    }

    public static var empty: Self {
        Self(
            format: "diple-export",
            version: currentVersion,
            exportedAt: Date(),
            sources: [],
            highlights: [],
            notes: []
        )
    }

    private init(
        format: String,
        version: Int,
        exportedAt: Date,
        sources: [Source],
        highlights: [Highlight],
        notes: [TaggedNote]
    ) {
        self.format = format
        self.version = version
        self.exportedAt = exportedAt
        self.sources = sources
        self.highlights = highlights
        self.notes = notes
    }
}

public nonisolated struct DipleExportDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.json] }

    public var payload: DipleExportPayload

    public init(payload: DipleExportPayload = .empty) {
        self.payload = payload
    }

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.payload = try decoder.decode(DipleExportPayload.self, from: data)
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return FileWrapper(regularFileWithContents: try encoder.encode(payload))
    }
}
