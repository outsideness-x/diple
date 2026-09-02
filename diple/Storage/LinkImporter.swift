import Foundation

public nonisolated enum LinkImportError: LocalizedError {
    case unsupportedScheme
    case requestFailed(status: Int)
    case unsupportedContent
    case pageTooLarge
    case fileTooLarge

    public var errorDescription: String? {
        switch self {
        case .unsupportedScheme:
            return "Only secure HTTPS links can be imported."
        case let .requestFailed(status):
            return "The site answered with error \(status)."
        case .unsupportedContent:
            return "That link points to neither a web page nor a PDF."
        case .pageTooLarge:
            return "That page is too large to import."
        case .fileTooLarge:
            return "That PDF is too large to import."
        }
    }
}

/// Fetches whatever a saved link points at and files it in the library.
///
/// A reader shares an address, not a format. What is behind it decides how it is filed: a web
/// page becomes an article packaged as EPUB, a PDF is stored as the PDF it already is. That
/// decision is made from the response rather than from the address, because the two most
/// common ways to link a paper — `arxiv.org/pdf/2609.01064` and `example.com/paper` — carry no
/// `.pdf` extension at all.
///
/// Runs entirely off the main actor. `SWIFT_APPROACHABLE_CONCURRENCY` makes a `nonisolated
/// async` function run on its *caller's* executor, so being nonisolated is not by itself
/// enough to keep HTML parsing off the main thread — the work is explicitly detached.
public nonisolated final class LinkImporter {
    public static let shared = LinkImporter()

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
        /// `fraction` is nil while the server has not said how big the file is. A download is
        /// the one stage that can run for a minute on a slow connection, so it reports how far
        /// it has come rather than repeating one motionless line.
        case downloading(fraction: Double?)
        case packaging

        public var label: String {
            switch self {
            case .fetching:
                return "Fetching the page…"
            case .reading:
                return "Finding the article…"
            case let .images(completed, total):
                return total > 0 ? "Saving images \(completed) of \(total)…" : "Saving images…"
            case let .downloading(fraction):
                guard let fraction else { return "Downloading the PDF…" }
                return "Downloading the PDF — \(Int((fraction * 100).rounded()))%"
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

    public func importLink(
        from url: URL,
        bookID: String? = nil,
        progress: @escaping @Sendable (Stage) -> Void
    ) async throws -> Book {
        try await Task.detached(priority: .userInitiated) {
            try await Self.perform(url: url, bookID: bookID, progress: progress)
        }.value
    }

    private static func perform(
        url: URL,
        bookID: String?,
        progress: @escaping @Sendable (Stage) -> Void
    ) async throws -> Book {
        guard url.scheme?.lowercased() == "https" else {
            throw LinkImportError.unsupportedScheme
        }

        progress(.fetching)
        let page: Page
        switch try await fetch(at: url) {
        case let .html(fetched):
            page = fetched
        case let .pdf(finalURL, suggestedFilename):
            return try await WebPDFImporter.importPDF(
                from: finalURL,
                requestedURL: url,
                bookID: bookID,
                suggestedFilename: suggestedFilename,
                progress: progress
            )
        }

        progress(.reading)
        let article = try ArticleExtractor(html: page.html, url: page.finalURL)

        // A queued system share supplies its durable queue UUID. If the process is terminated
        // after the database commit but before the queue acknowledgement, the next activation
        // finds this exact book instead of downloading a duplicate. In-app imports keep their
        // existing fresh-UUID behaviour through the nil default.
        let bookId = bookID ?? UUID().uuidString
        var importCommitted = false
        defer {
            if !importCommitted {
                try? BookStorageService.shared.deleteBookFolder(id: bookId)
            }
        }
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

        let bodyImages = await downloadBodyImages(article.images, progress: progress)
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

        try AppDatabase.shared.saveArticle(book, searchableText: article.searchableText)
        importCommitted = true
        // Same signal as a file import: a saved link is a source arriving on the shelf too.
        // Hopped onto the main actor explicitly — unlike `EPUBImporter`, this whole function
        // runs in a detached task, and a notification posted from it would be delivered on that
        // thread, straight into SwiftUI `onReceive` handlers that write view state.
        await MainActor.run {
            NotificationCenter.default.post(
                name: .dipleSourceDidImport,
                object: nil,
                userInfo: Notification.dipleImportPayload(book)
            )
        }
        return book
    }

    // MARK: - Fetching

    private struct Page {
        let html: String
        /// Where the page actually came from after redirects — every relative link and image in
        /// it resolves against this, not against what was pasted.
        let finalURL: URL
    }

    private enum ResponseSizeError: Error {
        case limitExceeded
    }

    /// What the address turned out to be.
    private enum Fetched {
        case html(Page)
        /// The PDF is *not* carried out of here as bytes. Its body is fetched again, by
        /// `WebPDFImporter`, straight to a file: this request only ever reads response
        /// headers and at most a five-byte prefix, and is cancelled before its body is
        /// touched. One extra round trip buys a download that never passes through memory
        /// and that can be capped while it is still arriving.
        case pdf(finalURL: URL, suggestedFilename: String?)
    }

    private static func fetch(at url: URL) async throws -> Fetched {
        let (bytes, response) = try await session.bytes(from: url)
        var completed = false
        defer {
            // An unconsumed `AsyncBytes` holds its task open. Cancelling on the PDF and error
            // paths releases the connection instead of leaving the body streaming into nothing.
            if !completed { bytes.task.cancel() }
        }

        if let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else {
                throw LinkImportError.requestFailed(status: http.statusCode)
            }
        }

        let finalURL = response.url ?? url
        let mimeType = (response as? HTTPURLResponse)?.mimeType?.lowercased()

        if let mimeType, mimeType.contains("pdf") {
            return .pdf(finalURL: finalURL, suggestedFilename: response.suggestedFilename)
        }

        let isDeclaredHTML = mimeType.map { $0.contains("html") || $0.contains("xml") } ?? true
        if !isDeclaredHTML {
            // A generic `application/octet-stream` says nothing, and plenty of servers send a
            // PDF under it. The file says what it is in its own first five bytes, so the
            // decision is taken from those rather than from a header or a file extension.
            let signature = try await readPrefix(bytes, count: pdfSignature.count)
            guard signature != pdfSignature else {
                return .pdf(finalURL: finalURL, suggestedFilename: response.suggestedFilename)
            }
            throw LinkImportError.unsupportedContent
        }

        let data: Data
        do {
            data = try await collect(bytes, response: response, limit: maximumHTMLBytes)
        } catch ResponseSizeError.limitExceeded {
            throw LinkImportError.pageTooLarge
        }
        completed = true

        return .html(
            Page(
                html: decode(data, textEncodingName: response.textEncodingName),
                finalURL: finalURL
            )
        )
    }

    /// `%PDF-`, the header every PDF is required to open with.
    static let pdfSignature = Data([0x25, 0x50, 0x44, 0x46, 0x2D])

    /// Reads at most `limit` bytes and then cancels the task by throwing. Checking both the
    /// declared length and the stream itself covers honest servers and chunked/misreported
    /// responses without ever buffering an unbounded body first.
    private static func collect(
        _ bytes: URLSession.AsyncBytes,
        response: URLResponse,
        limit: Int
    ) async throws -> Data {
        let expectedLength = response.expectedContentLength
        if expectedLength > Int64(limit) {
            throw ResponseSizeError.limitExceeded
        }

        var data = Data()
        if expectedLength > 0 {
            data.reserveCapacity(Int(expectedLength))
        }

        for try await byte in bytes {
            guard data.count < limit else {
                throw ResponseSizeError.limitExceeded
            }
            data.append(byte)
        }
        return data
    }

    /// Takes the first `count` bytes off a stream whose kind is not yet known, without the
    /// size ceiling `collect` applies: a response is not too large just because it is longer
    /// than its own signature.
    private static func readPrefix(_ bytes: URLSession.AsyncBytes, count: Int) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= count { break }
        }
        return data
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
        guard let (bytes, response) = try? await session.bytes(from: url) else { return nil }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return nil
        }
        guard let data = try? await collect(bytes, response: response, limit: maximumSingleImageBytes),
              !data.isEmpty
        else { return nil }
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
