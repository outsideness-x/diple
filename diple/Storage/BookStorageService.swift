import Foundation

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
        let targetFolder = try bookDirectory(id: bookId)
        let fileName = sourceURL.lastPathComponent.isEmpty ? "book.epub" : sourceURL.lastPathComponent
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

    /// Deletes the book directory Documents/Books/<uuid>
    public func deleteBookFolder(id: String) throws {
        let booksURL = try booksDirectory()
        let folderURL = booksURL.appendingPathComponent(id, isDirectory: true)
        if fileManager.fileExists(atPath: folderURL.path) {
            try fileManager.removeItem(at: folderURL)
        }
    }

    /// Returns absolute URL for a given relative path inside Documents
    public func absoluteURL(for relativePath: String) -> URL {
        documentsDirectory.appendingPathComponent(relativePath)
    }
}
