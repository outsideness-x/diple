import Foundation
import CryptoKit
import UniformTypeIdentifiers

/// One passage read out of somebody else's file, before diple has decided anything about it.
///
/// Deliberately not a `Highlight`: a `Highlight` needs a `bookId`, an id and a locator, and all
/// three are answers this type does not have. It carries what the file said and nothing more.
public nonisolated struct ImportedPassage: Equatable, Sendable {
    public let text: String
    /// The reader's own writing about this passage — a Kindle note that sat under it, or the
    /// `Note` column of a Readwise export. It becomes `Highlight.comment`.
    public let note: String?
    public let bookTitle: String
    public let bookAuthor: String?
    public let tags: [String]
    /// A colour name as the exporting app wrote it, not a hex: the file's vocabulary is not
    /// diple's, and the translation between them belongs in one place.
    public let colorName: String?
    public let createdAt: Date?

    public init(
        text: String,
        note: String? = nil,
        bookTitle: String,
        bookAuthor: String? = nil,
        tags: [String] = [],
        colorName: String? = nil,
        createdAt: Date? = nil
    ) {
        self.text = text
        self.note = note
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.tags = tags
        self.colorName = colorName
        self.createdAt = createdAt
    }
}

/// Which file this was, for the review sheet to say so in the reader's language rather than
/// making them remember what they picked two taps ago.
public nonisolated enum HighlightImportKind: String, Sendable {
    case kindle
    case readwise

    public var title: String {
        switch self {
        case .kindle: return "Kindle"
        case .readwise: return "Readwise"
        }
    }

    public var fileDescription: String {
        switch self {
        case .kindle: return "My Clippings.txt"
        case .readwise: return "Readwise CSV export"
        }
    }
}

/// A parsed file: what it was, and every passage in it.
public nonisolated struct HighlightImportDocument: Sendable {
    public let kind: HighlightImportKind
    public let passages: [ImportedPassage]

    public init(kind: HighlightImportKind, passages: [ImportedPassage]) {
        self.kind = kind
        self.passages = passages
    }

    /// Distinct titles, which is what the reader counts in — "1,240 passages from 37 books".
    public var sourceCount: Int {
        Set(passages.map { HighlightImportIdentity.sourceKey(title: $0.bookTitle, author: $0.bookAuthor) }).count
    }
}

/// What the import will actually do, measured against the library before anything is written.
public nonisolated struct HighlightImportPreview: Equatable, Sendable {
    public let passagesToAdd: Int
    public let passagesAlreadyHere: Int
    public let sourceCount: Int

    public var isNoOp: Bool { passagesToAdd == 0 }

    public init(passagesToAdd: Int, passagesAlreadyHere: Int, sourceCount: Int) {
        self.passagesToAdd = passagesToAdd
        self.passagesAlreadyHere = passagesAlreadyHere
        self.sourceCount = sourceCount
    }
}

public nonisolated struct HighlightImportReport: Equatable, Sendable {
    public let preview: HighlightImportPreview
    public let importedAt: Date

    public init(preview: HighlightImportPreview, importedAt: Date) {
        self.preview = preview
        self.importedAt = importedAt
    }
}

public nonisolated enum HighlightImportError: LocalizedError {
    case tooLarge
    case unreadableText
    case unrecognizedFormat
    case emptyFile
    case unreasonableItemCount

    public var errorDescription: String? {
        switch self {
        case .tooLarge:
            return "That file is larger than diple can safely read."
        case .unreadableText:
            return "That file isn’t text diple can read. Kindle writes My Clippings.txt in UTF-8."
        case .unrecognizedFormat:
            return "diple didn’t recognise that file as a Kindle My Clippings.txt or a Readwise CSV export."
        case .emptyFile:
            return "There were no passages in that file."
        case .unreasonableItemCount:
            return "That file holds too many passages to import safely."
        }
    }
}

// MARK: - Identity

/// Where an imported passage's id comes from.
///
/// The ids are **derived from the file's own content, not invented**, and that single decision
/// is what makes importing the same `My Clippings.txt` twice a no-op instead of a library with
/// everything in it twice. Kindle rewrites that file on every sync and readers re-export from
/// Readwise routinely; an import that could only be run once safely would be an import nobody
/// dares run.
public nonisolated enum HighlightImportIdentity {
    /// Title and author, folded to one comparable string. Case and surrounding punctuation are
    /// noise here: `Sapiens` and `sapiens ` are the same book by any reading.
    public static func sourceKey(title: String, author: String?) -> String {
        [normalize(title), normalize(author ?? "")].joined(separator: "\u{1F}")
    }

    /// The group a set of imported passages forms.
    ///
    /// It is deliberately **not** matched against a book already in the library, even when the
    /// titles agree. An imported passage has no locator — nothing in a Kindle file describes a
    /// position inside *this* EPUB — so hanging it on a real publication would put quotes in a
    /// book's list that cannot open the page they came from. Its own group tells the truth: the
    /// words are here, the book is not.
    public static func bookID(title: String, author: String?) -> String {
        "import:" + digest(sourceKey(title: title, author: author))
    }

    /// One passage's id: its book and its own words.
    ///
    /// Position is left out on purpose, even though both formats carry one. Kindle's location
    /// numbers and Readwise's are different numbers for the same sentence, so including them
    /// would import the same passage twice for anyone who has used both. The cost is that the
    /// very same sentence highlighted twice in one book collapses into one passage — which is
    /// the better error of the two, and arguably not an error.
    public static func passageID(bookID: String, text: String) -> String {
        "import:" + digest(bookID + "\u{1F}" + normalize(text))
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

// MARK: - Colour

/// The exporting app's colour words, translated once.
///
/// This is not the `switch` over diple's own palette that `DipleColor.Highlight` warns against:
/// nothing here classifies a stored hex. It reads a *foreign* vocabulary — six English words
/// another product prints in a CSV — and answers with six bytes. An unknown word is yellow,
/// which is what a passage marked with no colour at all already is.
public nonisolated enum ImportedHighlightColor {
    public static func hex(forName name: String?) -> String {
        switch name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "blue":
            // The retired swatch, and exactly the right home for one: it is still drawn, still
            // synced and still exported. What retiring it meant was only that nothing offers it
            // for a *new* mark — and an imported passage was marked somewhere else.
            return DipleColor.Highlight.blue
        case "green": return DipleColor.Highlight.green
        case "pink", "red": return DipleColor.Highlight.pink
        case "purple", "violet": return DipleColor.Highlight.lilac
        default: return DipleColor.Highlight.yellow
        }
    }
}

// MARK: - CSV

/// A small RFC 4180 reader, because a Readwise export contains quoted commas and quoted
/// newlines in nearly every row, and splitting on `,` would tear passages in half.
public nonisolated enum CSVReader {
    public static func rows(from text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.startIndex

        func endField() {
            row.append(field)
            field = ""
        }

        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while iterator < text.endIndex {
            let character = text[iterator]
            if inQuotes {
                if character == "\"" {
                    let next = text.index(after: iterator)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        iterator = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    inQuotes = true
                case ",":
                    endField()
                case "\n":
                    endRow()
                case "\r":
                    break // A CRLF file ends its rows on the \n that follows.
                default:
                    field.append(character)
                }
            }
            iterator = text.index(after: iterator)
        }

        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}

// MARK: - Readwise

public nonisolated enum ReadwiseCSVParser {
    /// Header names are matched leniently — lowercased and stripped of spaces — because the
    /// same export has shipped as `Book Title`, `book title` and `Title` over the years, and a
    /// reader whose file is one revision old should not be told it is the wrong file.
    private static let textKeys = ["highlight", "text", "highlighttext"]
    private static let titleKeys = ["booktitle", "title", "documenttitle"]
    private static let authorKeys = ["bookauthor", "author", "documentauthor"]
    private static let noteKeys = ["note", "notes", "annotation"]
    private static let colorKeys = ["color", "colour"]
    private static let tagKeys = ["tags", "highlighttags"]
    private static let dateKeys = ["highlightedat", "date", "created", "createdat"]

    public static func canParse(_ text: String) -> Bool {
        guard let header = CSVReader.rows(from: String(text.prefix(4096))).first else { return false }
        let keys = header.map(normalizedKey)
        return keys.contains { textKeys.contains($0) } && keys.contains { titleKeys.contains($0) }
    }

    public static func parse(_ text: String) -> [ImportedPassage] {
        let rows = CSVReader.rows(from: text)
        guard let header = rows.first else { return [] }
        let keys = header.map(normalizedKey)

        func column(_ candidates: [String]) -> Int? {
            keys.firstIndex { candidates.contains($0) }
        }

        guard let textIndex = column(textKeys), let titleIndex = column(titleKeys) else { return [] }
        let authorIndex = column(authorKeys)
        let noteIndex = column(noteKeys)
        let colorIndex = column(colorKeys)
        let tagIndex = column(tagKeys)
        let dateIndex = column(dateKeys)

        return rows.dropFirst().compactMap { row in
            func value(_ index: Int?) -> String? {
                guard let index, index < row.count else { return nil }
                let trimmed = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

            guard let passage = value(textIndex), let title = value(titleIndex) else { return nil }
            return ImportedPassage(
                text: passage,
                note: value(noteIndex),
                bookTitle: title,
                bookAuthor: value(authorIndex),
                tags: splitTags(value(tagIndex)),
                colorName: value(colorIndex),
                createdAt: value(dateIndex).flatMap(ImportedDate.parse)
            )
        }
    }

    /// Readwise separates tags with spaces, other exporters with commas, and a tag with a space
    /// in it exists in neither. Commas win when there are any; otherwise whitespace.
    private static func splitTags(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        let parts = raw.contains(",")
            ? raw.components(separatedBy: ",")
            : raw.components(separatedBy: .whitespacesAndNewlines)
        return parts.compactMap(TagName.normalized)
    }

    private static func normalizedKey(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .filter { !$0.isWhitespace && $0 != "_" }
    }
}

// MARK: - Kindle

public nonisolated enum KindleClippingsParser {
    private static let separator = "=========="

    public static func canParse(_ text: String) -> Bool {
        text.contains(separator)
    }

    /// Read structurally, never by the words in the metadata line.
    ///
    /// Kindle writes that line in the device's language — `Your Highlight`, `Ihre Markierung`,
    /// `Votre surlignement`, `Ваша заметка` — so a parser built on a list of keywords is correct
    /// for the languages someone remembered and silently wrong for the next one. Position
    /// numbers are digits in every locale, and that is enough to tell the three kinds apart:
    ///
    /// - no body at all is a bookmark, and is dropped: there is nothing of the reader's in it;
    /// - a single position that falls inside the previous passage's range is a note on it;
    /// - anything else is a passage.
    ///
    /// The known cost: a note whose position lands outside the passage it belongs to arrives as
    /// a passage of its own. The reader's words are kept either way, which is the part that
    /// must not be lost.
    public static func parse(_ text: String) -> [ImportedPassage] {
        var passages: [ImportedPassage] = []
        var lastRange: (bookKey: String, start: Int, end: Int)?

        for entry in text.components(separatedBy: separator) {
            let lines = entry.components(separatedBy: .newlines)
            let cleaned = lines.map { $0.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespaces) }
            guard let titleIndex = cleaned.firstIndex(where: { !$0.isEmpty }) else { continue }
            let titleLine = cleaned[titleIndex]

            let metaIndex = cleaned.index(after: titleIndex)
            guard metaIndex < cleaned.endIndex, cleaned[metaIndex].hasPrefix("-") else { continue }
            let metaLine = cleaned[metaIndex]

            let body = cleaned[cleaned.index(after: metaIndex)...]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }

            let (title, author) = splitTitleAndAuthor(titleLine)
            let bookKey = HighlightImportIdentity.sourceKey(title: title, author: author)
            let position = self.position(in: metaLine)

            if let last = lastRange,
               last.bookKey == bookKey,
               let position,
               position.end == nil,
               position.start >= last.start,
               position.start <= last.end,
               let previous = passages.last {
                passages[passages.count - 1] = ImportedPassage(
                    text: previous.text,
                    // Two notes on one passage is rare and legal; joining beats dropping one.
                    note: [previous.note, body].compactMap { $0 }.joined(separator: "\n\n"),
                    bookTitle: previous.bookTitle,
                    bookAuthor: previous.bookAuthor,
                    tags: previous.tags,
                    colorName: previous.colorName,
                    createdAt: previous.createdAt
                )
                continue
            }

            passages.append(
                ImportedPassage(
                    text: body,
                    bookTitle: title,
                    bookAuthor: author,
                    createdAt: date(in: metaLine)
                )
            )
            if let position {
                lastRange = (bookKey, position.start, position.end ?? position.start)
            } else {
                lastRange = nil
            }
        }

        return passages
    }

    /// `Sapiens: A Brief History of Humankind (Yuval Noah Harari)`. The byline is the last
    /// parenthesised group on the line, so a title with brackets of its own survives.
    static func splitTitleAndAuthor(_ line: String) -> (String, String?) {
        guard line.hasSuffix(")"), let open = line.lastIndex(of: "(") else {
            return (line.trimmingCharacters(in: .whitespaces), nil)
        }
        let title = String(line[line.startIndex..<open]).trimmingCharacters(in: .whitespaces)
        let author = String(line[line.index(after: open)..<line.index(before: line.endIndex)])
            .trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, !author.isEmpty else {
            return (line.trimmingCharacters(in: .whitespaces), nil)
        }
        return (title, flipSurname(author))
    }

    /// Kindle files a byline as `Harari, Yuval Noah`. It is the same person either way, but the
    /// name a reader says out loud is the other order, and it is the order every other screen in
    /// this app prints. Only a single comma is flipped: two of them are two authors, or a suffix.
    private static func flipSurname(_ author: String) -> String {
        let parts = author.components(separatedBy: ",")
        guard parts.count == 2 else { return author }
        let surname = parts[0].trimmingCharacters(in: .whitespaces)
        let given = parts[1].trimmingCharacters(in: .whitespaces)
        guard !surname.isEmpty, !given.isEmpty else { return author }
        return "\(given) \(surname)"
    }

    /// The last `|`-separated segment is the date; the position is the last of the others that
    /// carries digits. Works for `page 42 | Location 640-642 | Added on …` and for the files
    /// that omit one of the two.
    static func position(in metaLine: String) -> (start: Int, end: Int?)? {
        let segments = metaLine.components(separatedBy: "|")
        guard segments.count > 1 else { return nil }
        for segment in segments.dropLast().reversed() {
            let numbers = segment.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap { Int($0) }
            if let first = numbers.first {
                return (first, numbers.count > 1 ? numbers[1] : nil)
            }
        }
        return nil
    }

    static func date(in metaLine: String) -> Date? {
        guard let segment = metaLine.components(separatedBy: "|").last else { return nil }
        return ImportedDate.parse(segment)
    }
}

// MARK: - Dates

/// Best-effort date reading, and honestly named as such.
///
/// Kindle stamps its clippings in the device's language and regional format, so there is no one
/// pattern that reads them all. What matters is that failing to read a date never fails an
/// import: the caller stamps such a passage with the moment it arrived, which is a true
/// statement about it, if a less interesting one than the day it was first marked.
public nonisolated enum ImportedDate {
    public static func parse(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let iso = isoFormatter.date(from: trimmed) { return iso }
        if let iso = isoFractionalFormatter.date(from: trimmed) { return iso }

        // "Added on Monday, 12 August 2024 21:03:17" — the label and the weekday are localised
        // and useless; everything after the first comma is the part with a pattern.
        var candidates = [trimmed]
        if let comma = trimmed.firstIndex(of: ",") {
            candidates.append(String(trimmed[trimmed.index(after: comma)...]).trimmingCharacters(in: .whitespaces))
        }

        for candidate in candidates {
            for formatter in formatters where formatter.date(from: candidate) != nil {
                return formatter.date(from: candidate)
            }
        }
        return nil
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// English first because Kindle's own default is English and a Readwise CSV is always
    /// English; then the device's own locale, which is the other language a clippings file on
    /// this phone is likely to be in.
    private static let formatters: [DateFormatter] = {
        let patterns = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
            "d MMMM yyyy HH:mm:ss",
            "MMMM d, yyyy h:mm:ss a",
            "MMMM d, yyyy HH:mm:ss",
            "d MMMM yyyy 'г'., HH:mm:ss",
            "d MMMM yyyy 'г'. HH:mm:ss"
        ]
        let locales = [Locale(identifier: "en_US_POSIX"), Locale.current]
        return locales.flatMap { locale in
            patterns.map { pattern -> DateFormatter in
                let formatter = DateFormatter()
                formatter.locale = locale
                formatter.dateFormat = pattern
                return formatter
            }
        }
    }()
}

// MARK: - The importer

/// Reads a file somebody else's app wrote, and hands the result to the database.
///
/// Shaped after `DipleBackupRestorer` on purpose: file access and parsing stay off the main
/// actor and away from the view, and the same three steps — load, preview, commit — mean the
/// review sheet can promise exactly what the write will do.
public nonisolated final class HighlightImporter: Sendable {
    public static let shared = HighlightImporter()
    public static let maximumFileBytes = 64 * 1024 * 1024
    private static let maximumPassages = 100_000

    /// The file types offered in the picker. Kindle writes `.txt`; Readwise writes `.csv`.
    public static var readableTypes: [UTType] { [.plainText, .commaSeparatedText, .text] }

    private init() {}

    public func load(from url: URL) throws -> HighlightImportDocument {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile != false else { throw CocoaError(.fileReadUnsupportedScheme) }
        if let size = values.fileSize, size > Self.maximumFileBytes { throw HighlightImportError.tooLarge }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= Self.maximumFileBytes else { throw HighlightImportError.tooLarge }
        return try parse(data)
    }

    public func parse(_ data: Data) throws -> HighlightImportDocument {
        // Kindle has shipped UTF-8 with a BOM for years, but a device that has been through a
        // Windows round trip can hand back UTF-16 or Latin-1, and a decode that returns nil
        // would look to the reader like an empty file rather than a wrong encoding.
        guard let text = decode(data) else { throw HighlightImportError.unreadableText }

        let document: HighlightImportDocument
        if KindleClippingsParser.canParse(text) {
            document = HighlightImportDocument(kind: .kindle, passages: KindleClippingsParser.parse(text))
        } else if ReadwiseCSVParser.canParse(text) {
            document = HighlightImportDocument(kind: .readwise, passages: ReadwiseCSVParser.parse(text))
        } else {
            throw HighlightImportError.unrecognizedFormat
        }

        guard !document.passages.isEmpty else { throw HighlightImportError.emptyFile }
        guard document.passages.count <= Self.maximumPassages else {
            throw HighlightImportError.unreasonableItemCount
        }
        return document
    }

    public func preview(
        _ document: HighlightImportDocument,
        database: AppDatabase = .shared
    ) throws -> HighlightImportPreview {
        try database.previewHighlightImport(document)
    }

    public func commit(
        _ document: HighlightImportDocument,
        database: AppDatabase = .shared,
        at date: Date = Date()
    ) throws -> HighlightImportReport {
        try database.importHighlights(document, at: date)
    }

    private func decode(_ data: Data) -> String? {
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .isoLatin1] {
            if let text = String(data: data, encoding: encoding), !text.isEmpty {
                return text.replacingOccurrences(of: "\u{FEFF}", with: "")
            }
        }
        return nil
    }
}
