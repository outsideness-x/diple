import Foundation
import UIKit
import ReadiumShared
import ReadiumStreamer

public nonisolated enum PublicationImportError: LocalizedError {
    case invalidFileURL
    case unreadablePublication
    case restrictedPublication

    public var errorDescription: String? {
        switch self {
        case .invalidFileURL:
            return "The selected file could not be opened."
        case .unreadablePublication:
            return "That file is not a readable EPUB or PDF."
        case .restrictedPublication:
            return "This publication is protected and cannot be opened."
        }
    }
}

public final class EPUBImporter {
    public static let shared = EPUBImporter()

    private let httpClient = DefaultHTTPClient()
    private lazy var assetRetriever = AssetRetriever(httpClient: httpClient)
    private lazy var publicationOpener = PublicationOpener(
        parser: DefaultPublicationParser(
            httpClient: httpClient,
            assetRetriever: assetRetriever,
            pdfFactory: DefaultPDFDocumentFactory()
        )
    )

    private init() {}

    /// Imports EPUB or PDF file at `sourceURL`, copies it into `Documents/Books/<uuid>/`, parses title/author & cover, saves to DB.
    public func importBook(from sourceURL: URL) async throws -> Book {
        try await importEPUB(from: sourceURL)
    }

    /// Imports EPUB or PDF file at `sourceURL`, copies it into `Documents/Books/<uuid>/`, parses title/author & cover, saves to DB.
    public func importEPUB(from sourceURL: URL) async throws -> Book {
        let shouldStopAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let bookId = UUID().uuidString
        var importCommitted = false
        defer {
            if !importCommitted {
                try? BookStorageService.shared.deleteBookFolder(id: bookId)
            }
        }

        // 1. Copy file to Documents/Books/<bookId>/
        let (localFileURL, relativeFilePath) = try BookStorageService.shared.importEPUB(from: sourceURL, bookId: bookId)

        // 2. Parse EPUB metadata using Readium Streamer
        var title = sourceURL.deletingPathExtension().lastPathComponent
        var author: String? = nil
        var coverRelativePath: String? = nil

        guard let absoluteURL = localFileURL.anyURL.absoluteURL else {
            throw PublicationImportError.invalidFileURL
        }

        let publication: Publication
        do {
            let asset = try await assetRetriever.retrieve(url: absoluteURL).get()
            publication = try await publicationOpener.open(asset: asset, allowUserInteraction: false).get()
        } catch {
            throw PublicationImportError.unreadablePublication
        }

        guard !publication.isRestricted else {
            throw PublicationImportError.restrictedPublication
        }

        // Extract title
        if let pubTitle = publication.metadata.title,
           !pubTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = pubTitle
        }

        // Extract author(s)
        let authors = publication.metadata.authors.map(\.name).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !authors.isEmpty {
            author = authors.joined(separator: ", ")
        }

        // A missing cover is recoverable; failure to open the publication itself is not.
        if let coverImage = try? await publication.cover().get(),
           let coverData = coverImage.pngData() {
            coverRelativePath = try BookStorageService.shared.saveCoverData(coverData, bookId: bookId)
        }

        // 3. Create Book record & save in GRDB database
        let book = Book(
            id: bookId,
            title: title,
            author: author,
            filePath: relativeFilePath,
            coverPath: coverRelativePath,
            addedAt: Date(),
            lastOpenedAt: nil,
            progress: 0.0,
            locator: nil
        )

        try AppDatabase.shared.saveBook(book)
        importCommitted = true
        // Every screen holding a library — Home's, the shelf's, the Mac shell's — reloads on
        // this, and the shelf uses it to stand where the new source landed. Posted here rather
        // than at the four call sites because this is the one line that makes the source exist.
        NotificationCenter.default.post(
            name: .dipleSourceDidImport,
            object: nil,
            userInfo: Notification.dipleImportPayload(book)
        )
        // Fire-and-forget: the reader is usable immediately, full-text indexing catches up
        // in the background (see `BookContentIndexer`).
        BookContentIndexer.shared.indexBook(book)
        return book
    }
}
