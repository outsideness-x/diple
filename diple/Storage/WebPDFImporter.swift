import Foundation

/// Downloads a PDF a link points at and files it in the library as the PDF it is.
///
/// The library already knows how to open, read, highlight and index a PDF picked from Files —
/// `EPUBImporter.importPublication` is that path — so nothing here re-implements any of it.
/// What is genuinely different about a PDF that arrived over the network is the three things
/// this type does: get the bytes onto disk without letting an enormous file through, decide
/// what the file should be called, and remember the address it came from.
public nonisolated enum WebPDFImporter {

    /// One ceiling, in the same spirit as the article importer's: a link must not be able to
    /// fill the device. Scanned books do run past this, and they will be refused with a plain
    /// message rather than downloaded for ten minutes and then found to be unreadable.
    static let maximumPDFBytes: Int64 = 96 * 1024 * 1024

    static func importPDF(
        from url: URL,
        requestedURL: URL,
        bookID: String?,
        suggestedFilename: String?,
        progress: @escaping @Sendable (LinkImporter.Stage) -> Void
    ) async throws -> Book {
        progress(.downloading(fraction: nil))

        let downloader = PDFDownloader(limit: maximumPDFBytes) { fraction in
            progress(.downloading(fraction: fraction))
        }
        let fileURL = try await downloader.download(from: url)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        // The classifying request read the response headers, or five bytes at most. This is a
        // different request, and its result is what actually lands in the library, so the
        // signature is checked against the file that was really written.
        guard try isPDF(at: fileURL) else {
            throw LinkImportError.unsupportedContent
        }

        progress(.packaging)
        let fileName = fileName(suggested: suggestedFilename, url: url, requestedURL: requestedURL)

        // `requestedURL` rather than the address the download ended at: the reader shared the
        // former, and it is the one that will still work when they tap through to the source.
        return try await EPUBImporter.shared.importPublication(
            from: fileURL,
            fileName: fileName,
            fallbackTitle: (fileName as NSString).deletingPathExtension,
            bookId: bookID ?? UUID().uuidString,
            sourceURL: requestedURL,
            sourceKind: .pdf
        )
    }

    private static func isPDF(at fileURL: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: LinkImporter.pdfSignature.count)
        return header == LinkImporter.pdfSignature
    }

    /// What the file should be called on disk.
    ///
    /// The server's `Content-Disposition` is preferred because it is the only party that knows
    /// the document's own name — `arxiv.org/pdf/2609.01064` offers `2609.01064v1.pdf` there and
    /// nothing but an identifier in its path. The extension is added rather than assumed: a
    /// publication filed without one is a publication `PublicationKind.inferred` would later
    /// read as an EPUB.
    static func fileName(suggested: String?, url: URL, requestedURL: URL) -> String {
        for candidate in [suggested, url.lastPathComponent, requestedURL.lastPathComponent] {
            guard let candidate else { continue }
            let name = URL(fileURLWithPath: candidate).lastPathComponent
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != ".", name != "/", name.lowercased() != "unknown" else {
                continue
            }
            return name.lowercased().hasSuffix(".pdf") ? name : name + ".pdf"
        }
        return "document.pdf"
    }
}

/// A download that reports how far it has come and stops itself if the file turns out to be
/// larger than the ceiling.
///
/// Written against `URLSessionDownloadTask` rather than `URLSession.download(from:delegate:)`
/// because the ceiling has to be enforced from `didWriteData`, which belongs to
/// `URLSessionDownloadDelegate` — and a delegate implementing that protocol's own
/// `didFinishDownloadingTo` alongside the async convenience would be two owners of one
/// temporary file.
private final class PDFDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let limit: Int64
    private let onProgress: @Sendable (Double?) -> Void

    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var exceededLimit = false
    private var session: URLSession?

    init(limit: Int64, onProgress: @escaping @Sendable (Double?) -> Void) {
        self.limit = limit
        self.onProgress = onProgress
    }

    func download(from url: URL) async throws -> URL {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        // A paper over a hotel connection is a legitimate several minutes; the article
        // importer's 90 seconds is a ceiling for a page, not for a file.
        configuration.timeoutIntervalForResource = 300
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            "Accept": "application/pdf,*/*;q=0.8"
        ]
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        defer { session.finishTasksAndInvalidate() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                lock.unlock()
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesWritten > limit {
            lock.lock()
            exceededLimit = true
            lock.unlock()
            downloadTask.cancel()
            return
        }
        guard totalBytesExpectedToWrite > 0 else {
            onProgress(nil)
            return
        }
        onProgress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let response = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            finish(.failure(LinkImportError.requestFailed(status: response.statusCode)))
            return
        }

        // The system deletes `location` as soon as this method returns, so the file is claimed
        // here rather than handed back and moved by the caller.
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("diple-download-\(UUID().uuidString).pdf")
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        lock.lock()
        let cancelledForSize = exceededLimit
        lock.unlock()
        finish(.failure(cancelledForSize ? LinkImportError.fileTooLarge : error))
    }

    /// Both delegate callbacks can arrive for one task — a completed download reports success
    /// and then completion — so whoever gets here first resumes and the other finds nothing.
    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
