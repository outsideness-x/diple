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

        public init(
            id: String,
            title: String,
            author: String?,
            kind: PublicationKind,
            originalURL: String?,
            addedAt: Date,
            lastOpenedAt: Date?,
            progress: Double,
            readingPosition: String?
        ) {
            self.id = id
            self.title = title
            self.author = author
            self.kind = kind
            self.originalURL = originalURL
            self.addedAt = addedAt
            self.lastOpenedAt = lastOpenedAt
            self.progress = progress
            self.readingPosition = readingPosition
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, author, kind, originalURL, addedAt, lastOpenedAt, progress, readingPosition
        }

        /// Version 1 exports predate `PublicationKind`. They remain restorable: a URL is the
        /// only durable signal that the source was an article, while a file-backed source falls
        /// back to EPUB. The kind is informational during restore — no missing source row is
        /// invented without its publication file — so an old PDF cannot become a broken book.
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            title = try values.decode(String.self, forKey: .title)
            author = try values.decodeIfPresent(String.self, forKey: .author)
            originalURL = try values.decodeIfPresent(String.self, forKey: .originalURL)
            kind = try values.decodeIfPresent(PublicationKind.self, forKey: .kind)
                ?? (originalURL == nil ? .epub : .article)
            addedAt = try values.decode(Date.self, forKey: .addedAt)
            lastOpenedAt = try values.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
            progress = try values.decode(Double.self, forKey: .progress)
            readingPosition = try values.decodeIfPresent(String.self, forKey: .readingPosition)
        }
    }

    public nonisolated struct TaggedNote: Codable, Sendable {
        public let note: Note
        public let tags: [String]

        public init(note: Note, tags: [String]) {
            self.note = note
            self.tags = tags
        }
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

    public init(
        format: String = "diple-export",
        version: Int = currentVersion,
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

}

public nonisolated enum DipleBackupError: LocalizedError {
    case tooLarge
    case wrongFormat
    case unsupportedVersion(Int)
    case invalidIdentifier
    case duplicateIdentifier
    case unreasonableItemCount

    public var errorDescription: String? {
        switch self {
        case .tooLarge:
            return "That backup is larger than diple can safely restore."
        case .wrongFormat:
            return "That file isn’t a diple data export."
        case .unsupportedVersion(let version):
            return "This backup uses format version \(version), which this version of diple can’t restore."
        case .invalidIdentifier:
            return "The backup contains an item without a valid identifier."
        case .duplicateIdentifier:
            return "The backup contains the same item more than once."
        case .unreasonableItemCount:
            return "The backup contains too many items to restore safely."
        }
    }
}

public nonisolated struct DipleRestorePreview: Equatable, Sendable {
    public let sourcePositionsUpdated: Int
    public let sourceReferencesMissing: Int
    public let sourcePositionsKept: Int
    public let highlightsAdded: Int
    public let highlightsKept: Int
    public let notesAdded: Int
    public let notesUpdated: Int
    public let notesKept: Int

    public var changeCount: Int {
        sourcePositionsUpdated + highlightsAdded + notesAdded + notesUpdated
    }

    public var isNoOp: Bool { changeCount == 0 }
}

public nonisolated struct DipleRestoreReport: Equatable, Sendable {
    public let preview: DipleRestorePreview
    public let restoredAt: Date
}

/// Validates, previews and restores a versioned diple export. File access and JSON decoding are
/// deliberately separate from the Settings view so a large notes archive never blocks SwiftUI's
/// main actor, and so tests can exercise exactly the same contract from in-memory `Data`.
public nonisolated final class DipleBackupRestorer: Sendable {
    public static let shared = DipleBackupRestorer()
    public static let maximumFileBytes = 64 * 1024 * 1024
    private static let maximumItemsPerKind = 100_000

    private init() {}

    public func load(from url: URL) throws -> DipleExportPayload {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile != false else { throw CocoaError(.fileReadUnsupportedScheme) }
        if let size = values.fileSize, size > Self.maximumFileBytes { throw DipleBackupError.tooLarge }
        return try decode(Data(contentsOf: url, options: .mappedIfSafe))
    }

    public func decode(_ data: Data) throws -> DipleExportPayload {
        guard data.count <= Self.maximumFileBytes else { throw DipleBackupError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(DipleExportPayload.self, from: data)
        try validate(payload)
        return payload
    }

    public func preview(
        _ payload: DipleExportPayload,
        database: AppDatabase = .shared
    ) throws -> DipleRestorePreview {
        try validate(payload)
        return try database.previewRestore(payload)
    }

    public func restore(
        _ payload: DipleExportPayload,
        database: AppDatabase = .shared,
        at date: Date = Date()
    ) throws -> DipleRestoreReport {
        try validate(payload)
        return try database.restore(payload, at: date)
    }

    private func validate(_ payload: DipleExportPayload) throws {
        guard payload.format == "diple-export" else { throw DipleBackupError.wrongFormat }
        guard (1...DipleExportPayload.currentVersion).contains(payload.version) else {
            throw DipleBackupError.unsupportedVersion(payload.version)
        }
        guard payload.sources.count <= Self.maximumItemsPerKind,
              payload.highlights.count <= Self.maximumItemsPerKind,
              payload.notes.count <= Self.maximumItemsPerKind
        else { throw DipleBackupError.unreasonableItemCount }

        let sourceIDs = payload.sources.map(\.id)
        let highlightIDs = payload.highlights.map(\.id)
        let noteIDs = payload.notes.map(\.note.id)
        guard (sourceIDs + highlightIDs + noteIDs).allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw DipleBackupError.invalidIdentifier
        }
        guard Set(sourceIDs).count == sourceIDs.count,
              Set(highlightIDs).count == highlightIDs.count,
              Set(noteIDs).count == noteIDs.count
        else { throw DipleBackupError.duplicateIdentifier }
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
