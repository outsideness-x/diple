import Foundation

public nonisolated enum ArticleImportError: LocalizedError {
    case unsupportedScheme
    case requestFailed(status: Int)
    case notHTML
    case pageTooLarge

    public var errorDescription: String? {
        switch self {
        case .unsupportedScheme:
            return "Only http and https links can be imported."
        case let .requestFailed(status):
            return "The site answered with error \(status)."
        case .notHTML:
            return "That link doesn't point to a web page."
        case .pageTooLarge:
            return "That page is too large to import."
        }
    }
}

/// Fetches a web page and files it in the library as an EPUB.
///
/// Runs entirely off the main actor. `SWIFT_APPROACHABLE_CONCURRENCY` makes a `nonisolated
/// async` function run on its *caller's* executor, so being nonisolated is not by itself
/// enough to keep HTML parsing off the main thread — the work is explicitly detached.
public nonisolated final class ArticleImporter {
    public static let shared = ArticleImporter()

    /// Ceilings so that one hostile or merely enormous page cannot fill the device or hang the
    /// import. Every one of them degrades rather than fails: an article past the image budget
    /// still imports, with the images that fit.
    private static let maximumHTMLBytes = 8 * 1024 * 1024
    static let maximumImageBytes = 24 * 1024 * 1024
    private static let maximumSingleImageBytes = 6 * 1024 * 1024
    private static let maximumImageCount = 40
    private static let concurrentImageDownloads = 4

    /// What the import is doing, for the sheet that is watching.
    public enum Stage: Sendable, Equatable {
        case fetching
        case reading
        case images(completed: Int, total: Int)
        case packaging

        public var label: String {
            switch self {
            case .fetching:
                return "Fetching the page…"
            case .reading:
                return "Finding the article…"
            case let .images(completed, total):
                return total > 0 ? "Saving images \(completed) of \(total)…" : "Saving images…"
            case .packaging:
                return "Adding to your library…"
            }
        }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        configuration.httpAdditionalHeaders = [
            // Sites routinely serve a stripped page, or nothing, to a client that does not look
            // like a browser. This is the same page the reader would see if they opened the
            // link themselves, which is exactly what was asked for.
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": Locale.preferredLanguages.prefix(3).joined(separator: ", ")
        ]
        return URLSession(configuration: configuration)
    }()

    private init() {}

    // MARK: - Entry point

    public func importArticle(
        from url: URL,
        progress: @escaping @Sendable (Stage) -> Void
    ) async throws -> Book {
        try await Task.detached(priority: .userInitiated) {
            try await Self.perform(url: url, progress: progress)
        }.value
    }

    private static func perform(url: URL, progress: @Sendable (Stage) -> Void) async throws -> Book {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ArticleImportError.unsupportedScheme
        }

        progress(.fetching)
        let page = try await fetchPage(at: url)

        progress(.reading)
        let article = try ArticleExtractor(html: page.html, url: page.finalURL)

        let bookId = UUID().uuidString
        var assets: [ArticleEPUBBuilder.Asset] = []

        // The lead image doubles as the library cover, so it is fetched even when the article
        // body has no images of its own.
        var coverPath: String? = nil
        var coverImage: DownloadedImage? = nil
        if let leadImageURL = article.metadata.leadImageURL {
            progress(.images(completed: 0, total: article.images.count + 1))
            if let downloaded = await downloadImage(at: leadImageURL) {
                let path = "images/cover.\(downloaded.fileExtension)"
                assets.append(
                    ArticleEPUBBuilder.Asset(path: path, mediaType: downloaded.mediaType, data: downloaded.data)
                )
                coverPath = path
                coverImage = downloaded
            }
        }

        let bodyImages = try await downloadBodyImages(article.images, progress: progress)
        var resolvedPaths: [Int: String] = [:]
        for slot in article.images {
            guard let image = bodyImages[slot.index] else { continue }
            let path = "images/img-\(slot.index + 1).\(image.fileExtension)"
            assets.append(
                ArticleEPUBBuilder.Asset(path: path, mediaType: image.mediaType, data: image.data)
            )
            resolvedPaths[slot.index] = path
        }

        progress(.packaging)
        let builder = ArticleEPUBBuilder(
            bookId: bookId,
            metadata: article.metadata,
            sections: article.sections,
            bodyXHTML: try article.bodyXHTML(resolvedImages: resolvedPaths),
            assets: assets,
            coverPath: coverPath
        )

        let (_, relativePath) = try BookStorageService.shared.writeEPUB(builder.epubData(), bookId: bookId)

        // The grid reads the cover straight from disk rather than out of the EPUB, the same way
        // it does for an imported file.
        var coverRelativePath: String? = nil
        if let coverImage {
            coverRelativePath = try? BookStorageService.shared.saveCoverData(
                coverImage.data,
                bookId: bookId,
                extension: coverImage.fileExtension
            )
        }

        let book = Book(
            id: bookId,
            title: article.metadata.title,
            author: article.metadata.author,
            filePath: relativePath,
            coverPath: coverRelativePath,
            addedAt: Date(),
            sourceURL: article.metadata.canonicalURL.absoluteString
        )

        try AppDatabase.shared.saveBook(book)
        return book
    }

    // MARK: - Fetching

    private struct Page {
        let html: String
        /// Where the page actually came from after redirects — every relative link and image in
        /// it resolves against this, not against what was pasted.
        let finalURL: URL
    }

    private static func fetchPage(at url: URL) async throws -> Page {
        let (data, response) = try await session.data(from: url)

        if let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else {
                throw ArticleImportError.requestFailed(status: http.statusCode)
            }
            if let mimeType = http.mimeType?.lowercased(),
               !mimeType.contains("html"), !mimeType.contains("xml") {
                throw ArticleImportError.notHTML
            }
        }

        guard data.count <= maximumHTMLBytes else { throw ArticleImportError.pageTooLarge }

        return Page(
            html: decode(data, textEncodingName: response.textEncodingName),
            finalURL: response.url ?? url
        )
    }

    /// Decodes the page with the charset the server declared, then UTF-8, then Latin-1.
    /// Latin-1 maps every possible byte, so the last step cannot fail — a page with a wrong
    /// charset header imports with mangled accents instead of not importing at all.
    private static func decode(_ data: Data, textEncodingName: String?) -> String {
        if let textEncodingName {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(textEncodingName as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
                if let text = String(data: data, encoding: encoding) { return text }
            }
        }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        return String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self)
    }

    // MARK: - Images

    private struct DownloadedImage: Sendable {
        let data: Data
        let mediaType: String
        let fileExtension: String
    }

    private struct DownloadResult: Sendable {
        let index: Int
        let image: DownloadedImage?
    }

    /// Downloads the body images a few at a time, so a gallery-heavy piece does not open forty
    /// sockets at once, and reports each completion to the sheet.
    private static func downloadBodyImages(
        _ slots: [ArticleImageSlot],
        progress: @Sendable (Stage) -> Void
    ) async -> [Int: DownloadedImage] {
        let queue = Array(slots.prefix(maximumImageCount))
        guard !queue.isEmpty else { return [:] }

        var results: [Int: DownloadedImage] = [:]
        var budget = maximumImageBytes
        var completed = 0

        await withTaskGroup(of: DownloadResult.self) { group in
            var next = 0
            while next < min(concurrentImageDownloads, queue.count) {
                let slot = queue[next]
                group.addTask { DownloadResult(index: slot.index, image: await downloadImage(at: slot.url)) }
                next += 1
            }

            for await result in group {
                completed += 1
                progress(.images(completed: completed, total: queue.count))

                if let image = result.image, image.data.count <= budget {
                    budget -= image.data.count
                    results[result.index] = image
                }

                if next < queue.count {
                    let slot = queue[next]
                    group.addTask { DownloadResult(index: slot.index, image: await downloadImage(at: slot.url)) }
                    next += 1
                }
            }
        }

        return results
    }

    /// A failed image is not a failed import: it returns nil and its `<img>` is dropped from
    /// the markup, which is why nothing here throws.
    private static func downloadImage(at url: URL) async -> DownloadedImage? {
        guard let (data, response) = try? await session.data(from: url) else { return nil }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return nil
        }
        guard data.count <= maximumSingleImageBytes, !data.isEmpty else { return nil }
        guard let mediaType = imageMediaType(of: data) else { return nil }

        return DownloadedImage(
            data: data,
            mediaType: mediaType,
            fileExtension: fileExtension(forMediaType: mediaType)
        )
    }

    /// Identifies the image by its bytes rather than by its URL or its `Content-Type`.
    /// The manifest has to declare what the file actually is: a `.jpg` URL serving a PNG is
    /// common, and an EPUB whose manifest disagrees with its contents is invalid.
    private static func imageMediaType(of data: Data) -> String? {
        let header = [UInt8](data.prefix(16))
        guard header.count >= 12 else { return nil }

        if header.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if header.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if header.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "image/gif" }
        if header.starts(with: [0x52, 0x49, 0x46, 0x46]),
           Array(header[8..<12]) == [0x57, 0x45, 0x42, 0x50] { return "image/webp" }

        // SVG is text, so it is recognised by its root element instead of a magic number.
        if let text = String(data: data.prefix(512), encoding: .utf8),
           text.contains("<svg") { return "image/svg+xml" }

        return nil
    }

    private static func fileExtension(forMediaType mediaType: String) -> String {
        switch mediaType {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/svg+xml": return "svg"
        default: return "img"
        }
    }
}
