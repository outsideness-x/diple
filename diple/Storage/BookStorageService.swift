import Foundation
import ImageIO
import UniformTypeIdentifiers

/// File-system access is independent of the UI actor. `FileManager` provides its own
/// thread-safe operations, while callers coordinate writes through unique book directories.
public nonisolated final class BookStorageService: Sendable {
    public static let shared = BookStorageService()

    /// Keeping the Foundation reference computed leaves the service itself stateless and
    /// therefore safely shareable across executors.
    private var fileManager: FileManager { FileManager.default }

    public var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    public func booksDirectory() throws -> URL {
        let booksURL = documentsDirectory.appendingPathComponent("Books", isDirectory: true)
        if !fileManager.fileExists(atPath: booksURL.path) {
            try fileManager.createDirectory(at: booksURL, withIntermediateDirectories: true)
        }
        return booksURL
    }

    public func bookDirectory(id: String) throws -> URL {
        let booksURL = try booksDirectory()
        let folderURL = booksURL.appendingPathComponent(id, isDirectory: true)
        if !fileManager.fileExists(atPath: folderURL.path) {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        return folderURL
    }

    /// Copies EPUB file from external URL into Documents/Books/<uuid>/<filename>
    /// Returns local file URL and relative path (e.g. "Books/<uuid>/<filename>")
    public func importEPUB(from sourceURL: URL, bookId: String) throws -> (fileURL: URL, relativePath: String) {
        try importFile(
            from: sourceURL,
            bookId: bookId,
            fileName: sourceURL.lastPathComponent.isEmpty ? "book.epub" : sourceURL.lastPathComponent
        )
    }

    /// Copies any publication into Documents/Books/<uuid>/<fileName>.
    ///
    /// The name is given rather than taken from `sourceURL` because a downloaded publication
    /// arrives in a temporary file whose name is a UUID; what it should be called on the shelf
    /// comes from the server's `Content-Disposition` or from the address it was fetched from.
    /// `fileName` is reduced to a single path component, so nothing can be written outside the
    /// book's own folder.
    public func importFile(
        from sourceURL: URL,
        bookId: String,
        fileName: String
    ) throws -> (fileURL: URL, relativePath: String) {
        let targetFolder = try bookDirectory(id: bookId)
        let sanitized = URL(fileURLWithPath: fileName).lastPathComponent
        let fileName = sanitized.isEmpty || sanitized == "." ? "book" : sanitized
        let targetFileURL = targetFolder.appendingPathComponent(fileName)
        let temporaryURL = targetFolder.appendingPathComponent(".import-\(UUID().uuidString)")

        defer {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        if fileManager.fileExists(atPath: targetFileURL.path) {
            try fileManager.removeItem(at: targetFileURL)
        }

        // Copy into a private temporary name and reveal the publication with one rename, so a
        // cancelled or failed copy never leaves a partially written book at its final path.
        try fileManager.copyItem(at: sourceURL, to: temporaryURL)
        try fileManager.moveItem(at: temporaryURL, to: targetFileURL)
        let relativePath = "Books/\(bookId)/\(fileName)"
        return (targetFileURL, relativePath)
    }

    /// Writes a generated publication into Documents/Books/<uuid>/<fileName>.
    /// Returns local file URL and relative path, matching `importEPUB(from:bookId:)` so that a
    /// synthesised article and a copied file are indistinguishable to everything downstream.
    public func writeEPUB(_ data: Data, bookId: String, fileName: String = "article.epub") throws -> (fileURL: URL, relativePath: String) {
        let targetFolder = try bookDirectory(id: bookId)
        let targetFileURL = targetFolder.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: targetFileURL.path) {
            try fileManager.removeItem(at: targetFileURL)
        }

        try data.write(to: targetFileURL, options: .atomic)
        return (targetFileURL, "Books/\(bookId)/\(fileName)")
    }

    /// Saves extracted cover image data to Documents/Books/<uuid>/cover.<ext>
    /// Returns relative cover path (e.g. "Books/<uuid>/cover.png")
    public func saveCoverData(_ data: Data, bookId: String, extension ext: String = "png") throws -> String {
        let targetFolder = try bookDirectory(id: bookId)
        let fileName = "cover.\(ext)"
        let targetCoverURL = targetFolder.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: targetCoverURL.path) {
            try fileManager.removeItem(at: targetCoverURL)
        }

        try data.write(to: targetCoverURL, options: .atomic)
        return "Books/\(bookId)/\(fileName)"
    }

    /// Installs a downloaded CloudKit asset with an atomic reveal. `suggestedName` is reduced
    /// to its final path component so server data can never escape the book's private folder.
    public func installSyncedFile(
        from sourceURL: URL,
        bookId: String,
        suggestedName: String,
        fallbackName: String
    ) throws -> String {
        let sanitized = URL(fileURLWithPath: suggestedName).lastPathComponent
        let fileName = sanitized.isEmpty || sanitized == "." ? fallbackName : sanitized
        let targetFolder = try bookDirectory(id: bookId)
        let targetURL = targetFolder.appendingPathComponent(fileName)
        let temporaryURL = targetFolder.appendingPathComponent(".sync-\(UUID().uuidString)")

        defer {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        try fileManager.copyItem(at: sourceURL, to: temporaryURL)
        if fileManager.fileExists(atPath: targetURL.path) {
            _ = try fileManager.replaceItemAt(targetURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: targetURL)
        }
        return "Books/\(bookId)/\(fileName)"
    }

    /// Deletes the book directory Documents/Books/<uuid>.
    ///
    /// `keptCoverPath` is where the reading log wants the cover kept (see `ReadingLogSource`),
    /// or `nil` when it has nothing to say about the source. The cover is kept **before** the
    /// folder goes and a failure to keep it never stops the deletion: the reader asked for the
    /// book to be removed, and a statistics page drawing a cloth cover instead of the artwork
    /// is a much smaller fault than a book that would not delete.
    public func deleteBookFolder(id: String, keepingCoverAt keptCoverPath: String? = nil) throws {
        let booksURL = try booksDirectory()
        let folderURL = booksURL.appendingPathComponent(id, isDirectory: true)
        guard fileManager.fileExists(atPath: folderURL.path) else { return }
        if let keptCoverPath {
            keepCover(from: folderURL, at: keptCoverPath)
        }
        try fileManager.removeItem(at: folderURL)
    }

    /// The longest side of a kept cover, in pixels. The largest place the log draws a cover is a
    /// shelf tile about 120 pt wide — 360 px on a 3× phone, 540 px tall — so this keeps every
    /// pixel the page can show and drops the rest. A publisher's cover arrives as a PNG of a
    /// megabyte or more; the thumbnail is a few dozen kilobytes.
    static let keptCoverMaxPixelSize = 600

    /// Copies the book's cover out of its folder as a JPEG thumbnail at `relativePath`.
    ///
    /// The folder is searched for `cover.*` rather than handed `Book.coverPath`: a deletion that
    /// arrived from iCloud has already removed the row that held the path, and every writer of a
    /// cover — the importer, the metadata editor, the sync — names it `cover.<ext>`.
    ///
    /// ImageIO rather than `UIImage`: this runs off the main actor, and a thumbnail is what
    /// `CGImageSourceCreateThumbnailAtIndex` exists to make without decoding the full image. If
    /// the image cannot be re-encoded, the original bytes are copied as they are — `UIImage`
    /// decodes by content, not by extension, so the `.jpg` name does no harm.
    private func keepCover(from folderURL: URL, at relativePath: String) {
        let contents = (try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)) ?? []
        guard let coverURL = contents.first(where: {
            $0.deletingPathExtension().lastPathComponent == "cover"
        }) else { return }

        let targetURL = absoluteURL(for: relativePath)
        do {
            try fileManager.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
        } catch {
            return
        }

        if let data = Self.thumbnailJPEG(of: coverURL, maxPixelSize: Self.keptCoverMaxPixelSize) {
            try? data.write(to: targetURL, options: .atomic)
        } else {
            try? fileManager.copyItem(at: coverURL, to: targetURL)
        }
    }

    static func thumbnailJPEG(of url: URL, maxPixelSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Returns absolute URL for a given relative path inside Documents
    public func absoluteURL(for relativePath: String) -> URL {
        documentsDirectory.appendingPathComponent(relativePath)
    }
}
