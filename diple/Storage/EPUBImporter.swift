import Foundation
import UIKit
import ReadiumShared
import ReadiumStreamer

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

    /// Imports EPUB file at `sourceURL`, copies it into `Documents/Books/<uuid>/`, parses title/author & cover, saves to DB.
    public func importEPUB(from sourceURL: URL) async throws -> Book {
        let shouldStopAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let bookId = UUID().uuidString

        // 1. Copy file to Documents/Books/<bookId>/
        let (localFileURL, relativeFilePath) = try BookStorageService.shared.importEPUB(from: sourceURL, bookId: bookId)

        // 2. Parse EPUB metadata using Readium Streamer
        var title = sourceURL.deletingPathExtension().lastPathComponent
        var author: String? = nil
        var coverRelativePath: String? = nil

        if let absoluteURL = localFileURL.anyURL.absoluteURL {
            do {
                let asset = try await assetRetriever.retrieve(url: absoluteURL).get()
                let publication = try await publicationOpener.open(asset: asset, allowUserInteraction: false).get()

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

                // Extract cover image
                if let coverImage = try? await publication.cover().get(),
                   let coverData = coverImage.pngData() {
                    coverRelativePath = try BookStorageService.shared.saveCoverData(coverData, bookId: bookId)
                }
            } catch {
                print("Readium metadata extraction failed for \(localFileURL.lastPathComponent): \(error)")
            }
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
        return book
    }
}
