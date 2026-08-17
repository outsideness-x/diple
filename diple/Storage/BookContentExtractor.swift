import Foundation
import PDFKit
import SwiftSoup
import ReadiumShared
import ReadiumStreamer

/// A damaged or DRM-protected book must not crash the backfill; the indexer turns any of these
/// into "skip this book" rather than propagating a specific failure reason.
public nonisolated enum BookContentExtractionError: Error {
    case invalidFileURL
    case unreadablePublication
    case restrictedPublication
}

/// One indexable slice of a book: roughly a paragraph cluster (EPUB) or a page (PDF), small
/// enough to read as a coherent passage and carrying its own ready-to-navigate locator.
public nonisolated struct BookContentChunk: Sendable {
    public let href: String
    public let chapterTitle: String
    public let locatorJSON: String
    public let body: String
}

/// Reads a publication's own prose for full-text search. EPUB resources go through the same
/// Readium `AssetRetriever`/`PublicationOpener` pair `EPUBImporter` uses, then SwiftSoup strips
/// markup the same way `ArticleSearchIndexer` does for imported articles. PDFs go through
/// PDFKit page by page instead: Readium exposes a PDF publication as a single opaque resource,
/// not per-page text, and PDFKit already reads the same file directly.
///
/// - Important: Every entry point here does real parsing work — SwiftSoup, PDFKit — that must
///   never land on the main thread. `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` means a plain
///   `nonisolated async` function still runs on the *caller's* executor, so this alone would
///   not keep it off the main actor; `BookContentIndexer` is the caller, and it wraps every
///   call here in `Task.detached`.
public nonisolated enum BookContentExtractor {
    /// Target chunk size in characters. ~1.5 kB reads as two or three paragraphs — enough for
    /// a snippet to carry real context, small enough that a search hit lands close to the
    /// actual passage instead of "somewhere in this chapter."
    /// Also read by `AppDatabase.contentCharacterCount` as the fallback length of a book
    /// indexed before `characterCount` was stored.
    static let targetChunkSize = 1500

    public static func extractChunks(from book: Book) async throws -> [BookContentChunk] {
        let fileURL = BookStorageService.shared.absoluteURL(for: book.filePath)
        let publication = try await openPublication(fileURL: fileURL)

        guard !publication.isRestricted else {
            throw BookContentExtractionError.restrictedPublication
        }

        if book.isPDF {
            return try extractPDFChunks(publication: publication, fileURL: fileURL)
        }
        return try await extractEPUBChunks(publication: publication)
    }

    private static func openPublication(fileURL: URL) async throws -> Publication {
        guard let assetURL = fileURL.anyURL.absoluteURL else {
            throw BookContentExtractionError.invalidFileURL
        }

        let httpClient = DefaultHTTPClient()
        let assetRetriever = AssetRetriever(httpClient: httpClient)
        let publicationOpener = PublicationOpener(
            parser: DefaultPublicationParser(
                httpClient: httpClient,
                assetRetriever: assetRetriever,
                pdfFactory: DefaultPDFDocumentFactory()
            )
        )

        do {
            let asset = try await assetRetriever.retrieve(url: assetURL).get()
            return try await publicationOpener.open(asset: asset, allowUserInteraction: false).get()
        } catch {
            throw BookContentExtractionError.unreadablePublication
        }
    }

    // MARK: - EPUB

    private static func extractEPUBChunks(publication: Publication) async throws -> [BookContentChunk] {
        var chunks: [BookContentChunk] = []
        for link in publication.readingOrder {
            try Task.checkCancellation()
            guard let resource = publication.get(link),
                  let data = try? await resource.read().get(),
                  let markup = String(data: data, encoding: .utf8),
                  let document = try? SwiftSoup.parse(markup)
            else { continue }

            let paragraphs = extractParagraphs(from: document)
            guard !paragraphs.isEmpty else { continue }

            let chapterTitle = link.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            chunks.append(contentsOf: chunkParagraphs(
                paragraphs,
                href: link.url(),
                hrefString: link.href,
                mediaType: link.mediaType ?? .xhtml,
                chapterTitle: chapterTitle
            ))
        }
        return chunks
    }

    /// Block-level elements only, in document order — this is what keeps a chunk boundary from
    /// falling mid-sentence. `document.text()` (used for articles) flattens the whole resource
    /// into one string and would lose paragraph breaks entirely.
    private static func extractParagraphs(from document: SwiftSoup.Document) -> [String] {
        let selector = "p, h1, h2, h3, h4, h5, h6, li, blockquote, td, dd, figcaption"
        if let blocks = try? document.select(selector) {
            let texts = blocks.array().compactMap { element -> String? in
                guard let text = try? element.text().trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty
                else { return nil }
                return text
            }
            if !texts.isEmpty { return texts }
        }

        // A resource with no recognizable block tags (a bare title page, malformed XHTML) still
        // deserves to be searchable, just without paragraph-level granularity.
        guard let flat = try? document.text().trimmingCharacters(in: .whitespacesAndNewlines),
              !flat.isEmpty
        else { return [] }
        return [flat]
    }

    /// Groups paragraphs into ~`targetChunkSize` chunks without ever splitting one apart, and
    /// records each chunk's character offset in the resource so `locations.progression` lands
    /// on the passage instead of drifting to wherever the chapter happens to end.
    private static func chunkParagraphs(
        _ paragraphs: [String],
        href: AnyURL,
        hrefString: String,
        mediaType: MediaType,
        chapterTitle: String
    ) -> [BookContentChunk] {
        var paragraphOffsets: [Int] = []
        var runningOffset = 0
        for paragraph in paragraphs {
            paragraphOffsets.append(runningOffset)
            runningOffset += paragraph.count + 2 // matches the "\n\n" join below
        }
        let resourceLength = max(runningOffset, 1)

        var result: [BookContentChunk] = []
        var current: [String] = []
        var currentOffset = 0
        var currentLength = 0

        func flush() {
            guard !current.isEmpty else { return }
            let progression = min(max(Double(currentOffset) / Double(resourceLength), 0), 1)
            let locator = Locator(
                href: href,
                mediaType: mediaType,
                title: chapterTitle.isEmpty ? nil : chapterTitle,
                locations: .init(progression: progression)
            )
            if let locatorJSON = try? locator.jsonString() {
                result.append(BookContentChunk(
                    href: hrefString,
                    chapterTitle: chapterTitle,
                    locatorJSON: locatorJSON,
                    body: current.joined(separator: "\n\n")
                ))
            }
            current = []
            currentLength = 0
        }

        for (index, paragraph) in paragraphs.enumerated() {
            if current.isEmpty {
                currentOffset = paragraphOffsets[index]
            }
            current.append(paragraph)
            currentLength += paragraph.count + 2
            if currentLength >= targetChunkSize {
                flush()
            }
        }
        flush()

        return result
    }

    // MARK: - PDF

    /// A Readium PDF publication has exactly one link in `readingOrder` representing the whole
    /// file (see `PDFPositionsService`, which builds its per-page locators the same way: same
    /// href, `locations.position` as the page number). Page text comes from PDFKit directly —
    /// Readium's PDF resource is the raw file, not per-page text.
    private static func extractPDFChunks(publication: Publication, fileURL: URL) throws -> [BookContentChunk] {
        guard let link = publication.readingOrder.first else { return [] }
        guard let document = PDFDocument(url: fileURL) else {
            throw BookContentExtractionError.unreadablePublication
        }

        let pageCount = document.pageCount
        guard pageCount > 0 else { return [] }

        var chunks: [BookContentChunk] = []
        for pageIndex in 0 ..< pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            guard let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { continue }

            let pageNumber = pageIndex + 1
            let progression = Double(pageIndex) / Double(pageCount)
            let locator = Locator(
                href: link.url(),
                mediaType: link.mediaType ?? .pdf,
                locations: .init(
                    fragments: ["page=\(pageNumber)"],
                    progression: progression,
                    position: pageNumber
                )
            )
            guard let locatorJSON = try? locator.jsonString() else { continue }

            chunks.append(BookContentChunk(
                href: link.href,
                chapterTitle: "Page \(pageNumber)",
                locatorJSON: locatorJSON,
                body: text
            ))
        }
        return chunks
    }
}
