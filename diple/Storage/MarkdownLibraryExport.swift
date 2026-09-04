import Foundation

/// What one run wrote.
public nonisolated struct MarkdownExportReport: Equatable, Sendable {
    public let sourceFiles: Int
    public let passagesWritten: Int
    public let passagesAlreadyThere: Int
    public let noteFiles: Int
    public let skippedForeignFiles: Int

    public var fileCount: Int { sourceFiles + noteFiles }

    public init(
        sourceFiles: Int,
        passagesWritten: Int,
        passagesAlreadyThere: Int,
        noteFiles: Int,
        skippedForeignFiles: Int
    ) {
        self.sourceFiles = sourceFiles
        self.passagesWritten = passagesWritten
        self.passagesAlreadyThere = passagesAlreadyThere
        self.noteFiles = noteFiles
        self.skippedForeignFiles = skippedForeignFiles
    }
}

/// One note, as Markdown.
///
/// It lived as a private computed property inside `NoteDetailView`, which is where the Share
/// and Copy actions needed it and nowhere else could reach it. A folder full of notes needs the
/// identical bytes, and two serialisers for one format is how a fix to one of them ships alone.
public nonisolated enum NoteMarkdownExport {
    public static func document(title: String, body: String, tags: [String]) -> String {
        var parts: [String] = []
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { parts.append("# \(trimmedTitle)") }
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty { parts.append(trimmedBody) }
        if !tags.isEmpty { parts.append(tags.map { "#\($0)" }.joined(separator: " ")) }
        return parts.joined(separator: "\n\n")
    }
}

/// Writes the library into a folder of Markdown, one file per source and one per note.
///
/// **An export, not a sync.** diple is the source of truth and there is no path back: nothing
/// read from that folder ever re-enters the database. What the folder gets is a copy that
/// Obsidian, a grep or a text editor can read — which is the whole point of owning your reading.
///
/// Two rules make it safe to run more than once:
///
/// - a file diple did not write is **never** touched. Ownership is claimed by an id in the
///   front matter, and a name collision with a foreign file is resolved by writing beside it;
/// - a passage file is **appended to**, never rewritten. Each passage carries an invisible
///   marker, so a second run adds only what is new and leaves whatever the reader wrote between
///   the quotes exactly where it was.
///
/// A note is the exception, and deliberately: it is one document that diple owns rather than a
/// growing log, so its file is replaced. Editing an exported note in another app and running
/// this again loses that edit — which is what "export" means, and what the row in Settings says.
public nonisolated final class MarkdownLibraryExporter: Sendable {
    public static let shared = MarkdownLibraryExporter()

    /// The two subfolders. Named, not mixed into one flat directory: a vault with four hundred
    /// files in its root is a vault nobody opens twice.
    public static let highlightsFolderName = "Highlights"
    public static let notesFolderName = "Notes"

    private static let sourceIDKey = "diple_source"
    private static let noteIDKey = "diple_note"

    private init() {}

    public func export(
        to folder: URL,
        database: AppDatabase = .shared,
        fileManager: FileManager = .default
    ) throws -> MarkdownExportReport {
        let didAccess = folder.startAccessingSecurityScopedResource()
        defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }

        let highlights = try database.fetchAllHighlights()
        let tagsByHighlight = try database.fetchTagsByHighlight()
        let booksByID = Dictionary(uniqueKeysWithValues: try database.fetchAllBooks().map { ($0.id, $0) })
        let notes = try database.fetchAllNotes()
        let tagsByNote = try database.fetchTagsByNote()

        var report = MarkdownExportReport(
            sourceFiles: 0,
            passagesWritten: 0,
            passagesAlreadyThere: 0,
            noteFiles: 0,
            skippedForeignFiles: 0
        )

        if !highlights.isEmpty {
            let highlightsFolder = folder.appendingPathComponent(Self.highlightsFolderName, isDirectory: true)
            try fileManager.createDirectory(at: highlightsFolder, withIntermediateDirectories: true)
            report = try writeSources(
                highlights: highlights,
                tagsByHighlight: tagsByHighlight,
                booksByID: booksByID,
                into: highlightsFolder,
                fileManager: fileManager,
                report: report
            )
        }

        if !notes.isEmpty {
            let notesFolder = folder.appendingPathComponent(Self.notesFolderName, isDirectory: true)
            try fileManager.createDirectory(at: notesFolder, withIntermediateDirectories: true)
            report = try writeNotes(
                notes: notes,
                tagsByNote: tagsByNote,
                booksByID: booksByID,
                into: notesFolder,
                fileManager: fileManager,
                report: report
            )
        }

        return report
    }

    // MARK: - Sources

    private func writeSources(
        highlights: [Highlight],
        tagsByHighlight: [String: [String]],
        booksByID: [String: Book],
        into folder: URL,
        fileManager: FileManager,
        report: MarkdownExportReport
    ) throws -> MarkdownExportReport {
        var files = 0
        var written = 0
        var alreadyThere = 0
        var skipped = report.skippedForeignFiles
        var takenNames: Set<String> = []

        let grouped = Dictionary(grouping: highlights, by: \.bookId)
        // Sorted by title so a diffed folder reads the same way twice and a run does not
        // reshuffle which colliding title gets the plain filename.
        for bookID in grouped.keys.sorted(by: { title(for: $0, grouped: grouped, booksByID: booksByID) < title(for: $1, grouped: grouped, booksByID: booksByID) }) {
            guard let passages = grouped[bookID]?.sorted(by: { $0.createdAt < $1.createdAt }) else { continue }
            let book = booksByID[bookID]
            let title = book?.title ?? passages.first?.bookTitle ?? "Untitled"
            let author = book?.author ?? passages.first?.bookAuthor

            guard let destination = try claim(
                name: title,
                key: Self.sourceIDKey,
                value: bookID,
                in: folder,
                fileManager: fileManager,
                taken: &takenNames,
                skipped: &skipped
            ) else { continue }

            let existing = (try? String(contentsOf: destination, encoding: .utf8)) ?? ""
            var body = existing
            if body.isEmpty {
                body = frontMatter(
                    [
                        Self.sourceIDKey: bookID,
                        "title": title,
                        "author": author ?? ""
                    ]
                )
                body += "# \(title)\n"
                if let author, !author.isEmpty { body += "*\(author)*\n" }
            }

            var added = 0
            for passage in passages {
                let marker = Self.marker(passage.id)
                if existing.contains(marker) {
                    alreadyThere += 1
                    continue
                }
                body += "\n" + block(for: passage, tags: tagsByHighlight[passage.id] ?? [])
                added += 1
            }

            guard added > 0 || existing.isEmpty else { continue }
            try Data(body.utf8).write(to: destination, options: .atomic)
            files += 1
            written += added
        }

        return MarkdownExportReport(
            sourceFiles: files,
            passagesWritten: written,
            passagesAlreadyThere: alreadyThere,
            noteFiles: report.noteFiles,
            skippedForeignFiles: skipped
        )
    }

    private func title(for bookID: String, grouped: [String: [Highlight]], booksByID: [String: Book]) -> String {
        booksByID[bookID]?.title ?? grouped[bookID]?.first?.bookTitle ?? "Untitled"
    }

    /// One passage: the quote, the reader's thought under it, its tags as real Obsidian tags,
    /// and the marker that lets the next run recognise it. The marker is an HTML comment, which
    /// every Markdown renderer worth the name draws as nothing at all.
    private func block(for passage: Highlight, tags: [String]) -> String {
        var lines: [String] = []
        let quote = passage.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { "> \($0)" }
            .joined(separator: "\n")
        lines.append(quote)

        if let comment = passage.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !comment.isEmpty {
            lines.append(comment)
        }
        if !tags.isEmpty {
            lines.append(tags.map { "#\($0)" }.joined(separator: " "))
        }
        lines.append(Self.marker(passage.id))
        return lines.joined(separator: "\n\n") + "\n"
    }

    private static func marker(_ id: String) -> String {
        "<!-- diple:\(id) -->"
    }

    // MARK: - Notes

    private func writeNotes(
        notes: [Note],
        tagsByNote: [String: [String]],
        booksByID: [String: Book],
        into folder: URL,
        fileManager: FileManager,
        report: MarkdownExportReport
    ) throws -> MarkdownExportReport {
        var files = 0
        var skipped = report.skippedForeignFiles
        var takenNames: Set<String> = []

        for note in notes.sorted(by: { $0.createdAt < $1.createdAt }) {
            let item = NoteItem(note: note, tags: tagsByNote[note.id] ?? [], book: note.bookId.flatMap { booksByID[$0] })
            // The file is named after `displayTitle` — the same string a `[[Wiki link]]`
            // resolves on inside diple. Obsidian resolves its links on filenames, so the links
            // the reader already wrote arrive working rather than as literal brackets.
            guard let destination = try claim(
                name: item.displayTitle,
                key: Self.noteIDKey,
                value: note.id,
                in: folder,
                fileManager: fileManager,
                taken: &takenNames,
                skipped: &skipped
            ) else { continue }

            var body = frontMatter([Self.noteIDKey: note.id, "created": Self.dateFormatter.string(from: note.createdAt), "updated": Self.dateFormatter.string(from: note.updatedAt)])
            body += NoteMarkdownExport.document(
                title: note.title ?? "",
                body: note.body,
                tags: item.tags
            )
            if let book = item.book {
                body += "\n\n---\n\nFrom *\(book.title)*"
            }
            try Data((body + "\n").utf8).write(to: destination, options: .atomic)
            files += 1
        }

        return MarkdownExportReport(
            sourceFiles: report.sourceFiles,
            passagesWritten: report.passagesWritten,
            passagesAlreadyThere: report.passagesAlreadyThere,
            noteFiles: files,
            skippedForeignFiles: skipped
        )
    }

    // MARK: - Files

    /// Finds the file this record owns, or a free name to create it under.
    ///
    /// Ownership is the front-matter id, not the filename, so a file diple wrote and the reader
    /// renamed is still found and a file diple never wrote is never opened for writing. When the
    /// name is taken by someone else's file, a numbered neighbour is used instead — losing a
    /// pretty filename is an acceptable price; overwriting somebody's own notes is not.
    ///
    /// Returns `nil` only when no free name could be found at all.
    private func claim(
        name: String,
        key: String,
        value: String,
        in folder: URL,
        fileManager: FileManager,
        taken: inout Set<String>,
        skipped: inout Int
    ) throws -> URL? {
        let base = Self.safeFileName(name)
        for attempt in 0..<50 {
            let candidate = attempt == 0 ? base : "\(base) \(attempt + 1)"
            guard !taken.contains(candidate.lowercased()) else { continue }
            let url = folder.appendingPathComponent(candidate).appendingPathExtension("md")

            guard fileManager.fileExists(atPath: url.path) else {
                taken.insert(candidate.lowercased())
                return url
            }
            let head = (try? String(contentsOf: url, encoding: .utf8))?.prefix(512) ?? ""
            if head.contains("\(key): \(value)") {
                taken.insert(candidate.lowercased())
                return url
            }
            skipped += 1
        }
        return nil
    }

    /// Everything a file name may not carry on any of the filesystems these folders live on —
    /// iCloud Drive, a synced vault, an SMB share — plus a length that stays under the limits
    /// of all of them. A title that survives none of it becomes "Untitled" rather than "".
    static func safeFileName(_ raw: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]").union(.newlines).union(.controlCharacters)
        let cleaned = raw
            .components(separatedBy: forbidden)
            .joined(separator: " ")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        guard !cleaned.isEmpty else { return "Untitled" }
        return String(cleaned.prefix(80)).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    private func frontMatter(_ fields: [String: String]) -> String {
        var lines = ["---"]
        for key in fields.keys.sorted() {
            let value = fields[key] ?? ""
            guard !value.isEmpty else { continue }
            lines.append("\(key): \(Self.yamlScalar(value))")
        }
        lines.append("---")
        lines.append("")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Quoted only when it has to be. An unquoted scalar is what a hand-written vault looks
    /// like; a quoted one is what a title with a colon in it needs to stay one field.
    private static func yamlScalar(_ value: String) -> String {
        let needsQuotes = value.contains(":") || value.contains("#") || value.contains("\"")
            || value.hasPrefix(" ") || value.hasSuffix(" ")
        guard needsQuotes else { return value }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
