import Foundation

/// Everything the reader has made out of a text, as one kind of thing.
///
/// A note and a saved passage were two databases with two screens, two view models and two
/// card languages — and the reader's own question is never "was this a note or a highlight",
/// it is "what did I make of this book". Both carry the same four facts: a source, a set of
/// tags, a date, and some words. So they are filtered, grouped and read as one catalogue, and
/// the two remaining differences are printed rather than structural: whose words they are
/// (`kind`) and, for a passage, the place in the book it can be opened at.
public nonisolated enum MarginaliaKind: String, Hashable, Sendable, CaseIterable {
    /// A note: words the reader wrote.
    case written
    /// A passage: words the reader saved, with or without a comment of their own on it.
    case saved
}

/// A saved passage with everything a row needs to draw it, resolved once at load time —
/// the same trade `NoteItem` makes, and for the same reason: a card that fetched its own tags
/// would put a query behind every row of a scroll.
public nonisolated struct PassageItem: Identifiable, Equatable, Hashable, Sendable {
    public let highlight: Highlight
    public let tags: [String]
    /// `nil` once the book has been deleted, or when the passage was imported from Kindle or
    /// Readwise for a book that was never here. `highlight.bookTitle` still names it.
    public let book: Book?

    public var id: String { highlight.id }

    public init(highlight: Highlight, tags: [String], book: Book?) {
        self.highlight = highlight
        self.tags = tags
        self.book = book
    }

    /// The reader's own words on this passage, or `nil` — blank is normalized away at the
    /// database boundary, but an imported record can still arrive holding whitespace.
    public var comment: String? {
        let trimmed = highlight.comment?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// The Markdown a note expanded out of this passage is born holding.
    ///
    /// A portable blockquote, not a stored relation: it survives the folder export, CloudKit
    /// and any other Markdown client, which is the same trade `[[Wiki link]]` already makes.
    /// Consecutive `>` lines are folded into one quotation by the parser, so the attribution
    /// sits inside the quotation rather than under it as a stray paragraph.
    public var noteSeed: String {
        quotation(attributed: true).joined(separator: "\n") + "\n\n"
    }

    /// The passage as Markdown blockquote lines. `attributed` adds the source's name as the
    /// quotation's last line — wanted when the quotation stands alone, noise when a heading
    /// above it has already said where it came from.
    public func quotation(attributed: Bool) -> [String] {
        var lines = highlight.text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> " + $0.trimmingCharacters(in: .whitespaces) }
        if attributed, let attribution = book?.title ?? highlight.bookTitle {
            lines.append("> — \(attribution)")
        }
        return lines
    }

    /// What the passage is called when it has to be named rather than quoted — the A–Z sort,
    /// and the accessibility label of its row. The opening words, cut at a word boundary.
    public var displayTitle: String {
        MarginaliaEntry.shortened(
            highlight.text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

/// One entry in the catalogue: a note, or a passage.
public nonisolated enum MarginaliaEntry: Identifiable, Equatable, Hashable {
    case note(NoteItem)
    case passage(PassageItem)

    /// Namespaced, because a note and a passage are separate tables and nothing stops the two
    /// UUID spaces from meeting. A duplicate id in a `ForEach` is a silently dropped row.
    public var id: String {
        switch self {
        case .note(let item): return "note:\(item.id)"
        case .passage(let item): return "passage:\(item.id)"
        }
    }

    public var kind: MarginaliaKind {
        switch self {
        case .note: return .written
        case .passage: return .saved
        }
    }

    public var noteItem: NoteItem? {
        if case .note(let item) = self { return item }
        return nil
    }

    public var passageItem: PassageItem? {
        if case .passage(let item) = self { return item }
        return nil
    }

    /// When this entry last moved. A note carries an edit date; a passage is saved once and
    /// never rewritten in place, so its creation *is* its last movement.
    public var touchedAt: Date {
        switch self {
        case .note(let item): return item.note.updatedAt
        case .passage(let item): return item.highlight.createdAt
        }
    }

    public var createdAt: Date {
        switch self {
        case .note(let item): return item.note.createdAt
        case .passage(let item): return item.highlight.createdAt
        }
    }

    /// The source this entry belongs to, if any. A note's link is optional by design; a
    /// passage always has one, though the book behind it may be gone.
    public var bookId: String? {
        switch self {
        case .note(let item): return item.note.bookId
        case .passage(let item): return item.highlight.bookId
        }
    }

    /// The name of that source. For a passage this falls back to the title snapshotted when it
    /// was saved, which is the only name left once the book has been deleted.
    public var bookTitle: String? {
        switch self {
        case .note(let item): return item.book?.title
        case .passage(let item): return item.book?.title ?? item.highlight.bookTitle
        }
    }

    public var book: Book? {
        switch self {
        case .note(let item): return item.book
        case .passage(let item): return item.book
        }
    }

    public var tags: [String] {
        switch self {
        case .note(let item): return item.tags
        case .passage(let item): return item.tags
        }
    }

    public var displayTitle: String {
        switch self {
        case .note(let item): return item.displayTitle
        case .passage(let item): return item.displayTitle
        }
    }

    /// Nothing has been done with this entry yet beyond keeping it: no tag, and — for a note —
    /// no source; for a passage, no comment. It is the inbox of the board.
    ///
    /// The two halves of the test are different on purpose. A note without a source is not
    /// unfiled: plenty of thinking starts from nothing, and the board must not nag about it.
    /// What makes a note unsorted is having neither a word nor a shelf. A passage always has a
    /// shelf, so the question there is whether the reader ever came back to it — a tag or a
    /// comment is the evidence that they did.
    public var isUnsorted: Bool {
        switch self {
        case .note(let item): return item.tags.isEmpty && item.book == nil
        case .passage(let item): return item.tags.isEmpty && item.comment == nil
        }
    }

    /// Everything a plain-text search should be able to find this entry by.
    ///
    /// Built once per load rather than per keystroke: it is joined from up to six fields, and
    /// rebuilding it inside the filter made every character typed re-serialise the whole board.
    public var haystack: String {
        switch self {
        case .note(let item):
            return [
                item.note.title ?? "",
                item.note.body,
                item.tags.joined(separator: " "),
                item.book?.title ?? "",
                item.book?.author ?? ""
            ].joined(separator: "\n")
        case .passage(let item):
            return [
                item.highlight.text,
                item.comment ?? "",
                item.tags.joined(separator: " "),
                item.book?.title ?? item.highlight.bookTitle ?? "",
                item.book?.author ?? item.highlight.bookAuthor ?? ""
            ].joined(separator: "\n")
        }
    }

    /// A headline, not a paragraph: cut at a word boundary so it reads as a name rather than a
    /// sentence that ran out of room. The same rule `NoteItem` applies to an untitled note,
    /// shared so a note and a passage are never shortened two different ways in one list.
    static func shortened(_ text: String, limit: Int = 60) -> String {
        guard text.count > limit else { return text }
        let clipped = text.prefix(limit)
        if let lastSpace = clipped.lastIndex(of: " "),
           clipped.distance(from: clipped.startIndex, to: lastSpace) > limit / 2 {
            return clipped[..<lastSpace].trimmingCharacters(in: .whitespaces) + "…"
        }
        return clipped.trimmingCharacters(in: .whitespaces) + "…"
    }
}

// MARK: - Scope

/// Whose words the board is showing. The one axis that cannot be a filter chip: it decides
/// what the other chips are even offered over.
public nonisolated enum MarginaliaScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case written
    case saved

    public var id: Self { self }

    /// "Written" and "Saved" rather than "Notes" and "Passages".
    ///
    /// The tab is already called Notes, so a segment inside it called Notes says either
    /// "everything here" or "half of what is here" depending on which label you read first.
    /// Whose words they are is the actual difference and the one a reader can answer without
    /// being taught the app's vocabulary: a note is what you wrote, a passage is what you kept.
    public var title: String {
        switch self {
        case .all: return "All"
        case .written: return "Written"
        case .saved: return "Saved"
        }
    }

    public var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .written: return "square.and.pencil"
        case .saved: return "quote.opening"
        }
    }

    public func includes(_ kind: MarginaliaKind) -> Bool {
        switch self {
        case .all: return true
        case .written: return kind == .written
        case .saved: return kind == .saved
        }
    }
}

// MARK: - Smart views

/// The handful of narrowings that are not a name. They stay in front of the source and tag
/// chips because they answer "what have I been doing", which is asked far more often than any
/// one tag.
public nonisolated enum MarginaliaLens: String, CaseIterable, Identifiable, Sendable {
    case recent
    case fromLibrary
    case unsorted

    public var id: Self { self }

    public var title: String {
        switch self {
        case .recent: return "This week"
        case .fromLibrary: return "From library"
        case .unsorted: return "Unsorted"
        }
    }

    public var systemImage: String {
        switch self {
        case .recent: return "clock"
        case .fromLibrary: return "book.closed"
        case .unsorted: return "tray"
        }
    }

    public func matches(_ entry: MarginaliaEntry, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .recent:
            return calendar.isDate(entry.touchedAt, equalTo: now, toGranularity: .weekOfYear)
        case .fromLibrary:
            return entry.bookId != nil
        case .unsorted:
            return entry.isUnsorted
        }
    }
}

// MARK: - Facets

/// What the board has been narrowed to by name: any of these sources, and all of these tags.
///
/// **Sources are OR and tags are AND**, which is not an oversight and not a setting. Two
/// sources selected is "either shelf" — a source is a place, and no entry is in two places at
/// once, so AND across sources can only ever return nothing. Two tags selected is "both
/// words", because a tag is a description and an entry can carry many; `#objection` plus
/// `#for-the-essay` is a real question and `#objection` *or* `#for-the-essay` is barely a
/// narrowing at all.
///
/// The reader is never told this rule, and does not have to be: every offered chip carries the
/// number of entries standing under that name inside the current narrowing, so the count under
/// the thumb has already answered the question the rule would have raised.
public nonisolated struct MarginaliaFacets: Equatable, Hashable, Sendable {
    public var bookIds: Set<String> = []
    public var tags: Set<String> = []
    /// Mark colours, as stored hex. OR-ed for the reason sources are: a passage carries exactly
    /// one, so intersecting two could only ever return nothing.
    public var colors: Set<String> = []

    public init(bookIds: Set<String> = [], tags: Set<String> = [], colors: Set<String> = []) {
        self.bookIds = bookIds
        self.tags = tags
        self.colors = colors
    }

    public var isEmpty: Bool { bookIds.isEmpty && tags.isEmpty && colors.isEmpty }
    public var count: Int { bookIds.count + tags.count + colors.count }

    public func matches(_ entry: MarginaliaEntry) -> Bool {
        matchesSources(entry) && matchesTags(entry) && matchesColors(entry)
    }

    /// A note carries no mark and therefore no colour, so asking about colour excludes every
    /// note. That is the honest answer rather than an oversight: "which of these did I mark in
    /// green" is a question only a passage can be asked, and quietly keeping the notes in would
    /// make the number on the chip a lie.
    public func matchesColors(_ entry: MarginaliaEntry) -> Bool {
        guard !colors.isEmpty else { return true }
        guard case .passage(let passage) = entry else { return false }
        return colors.contains(passage.highlight.colorHex)
    }

    public func matchesSources(_ entry: MarginaliaEntry) -> Bool {
        guard !bookIds.isEmpty else { return true }
        guard let bookId = entry.bookId else { return false }
        return bookIds.contains(bookId)
    }

    public func matchesTags(_ entry: MarginaliaEntry) -> Bool {
        guard !tags.isEmpty else { return true }
        return tags.isSubset(of: Set(entry.tags))
    }

    public mutating func toggleTag(_ tag: String) {
        if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
    }

    public mutating func toggleSource(_ bookId: String) {
        if bookIds.contains(bookId) { bookIds.remove(bookId) } else { bookIds.insert(bookId) }
    }

    public mutating func toggleColor(_ hex: String) {
        if colors.contains(hex) { colors.remove(hex) } else { colors.insert(hex) }
    }
}

/// One chip in the filter row: a name, how many entries it would leave, and whether it is
/// already part of the narrowing.
public nonisolated struct MarginaliaFacetOption: Identifiable, Equatable, Hashable {
    public nonisolated enum Kind: Hashable {
        case source(String)
        case tag(String)
        case color(String)
    }

    public let kind: Kind
    /// What the chip prints — a book's title, or a tag without its `#`.
    public let label: String
    /// How many entries stand under this name inside the current narrowing. For a tag, which
    /// is AND-ed, that is exactly what would remain if it were added; for a source, which is
    /// OR-ed, it is what that source contributes.
    public let count: Int
    public let isSelected: Bool

    public var id: Kind { kind }

    public init(kind: Kind, label: String, count: Int, isSelected: Bool) {
        self.kind = kind
        self.label = label
        self.count = count
        self.isSelected = isSelected
    }
}

// MARK: - Order

/// Deliberately three, for the reason already recorded for the notes board: this is a thinking
/// space, not a spreadsheet, and the orders that matter are "where I left off", "how it
/// happened" and "find it by name".
public nonisolated enum MarginaliaSort: String, CaseIterable, Identifiable, Sendable {
    case recent
    case created
    case title

    public var id: Self { self }

    public var title: String {
        switch self {
        case .recent: return "Last touched"
        case .created: return "Date created"
        case .title: return "Title"
        }
    }

    public var systemImage: String {
        switch self {
        case .recent: return "clock.arrow.circlepath"
        case .created: return "calendar"
        case .title: return "textformat.abc"
        }
    }
}

/// How the catalogue is broken into sections.
///
/// Grouping by tag is absent on purpose. An entry carries several tags, so it would appear in
/// several sections, and a list where the same row is present three times is a list you cannot
/// count. What "browse by tag" actually wants is one tag at a time with everything under it,
/// and that is a place — `TagOverviewView` — not a sort order.
public nonisolated enum MarginaliaGrouping: String, CaseIterable, Identifiable, Sendable {
    case none
    case source
    case month

    public var id: Self { self }

    public var title: String {
        switch self {
        case .none: return "No groups"
        case .source: return "By source"
        case .month: return "By month"
        }
    }

    public var systemImage: String {
        switch self {
        case .none: return "list.bullet"
        case .source: return "book.closed"
        case .month: return "calendar"
        }
    }
}

/// A run of entries under one heading.
public nonisolated struct MarginaliaGroup: Identifiable, Equatable {
    public let id: String
    public let title: String
    /// The book behind a source group, when it is still in the library — the heading draws its
    /// cover. `nil` for every other grouping, and for a source that has been deleted.
    public let book: Book?
    public let entries: [MarginaliaEntry]

    public init(id: String, title: String, book: Book? = nil, entries: [MarginaliaEntry]) {
        self.id = id
        self.title = title
        self.book = book
        self.entries = entries
    }
}

// MARK: - Query

/// What was typed into the one search field.
///
/// `#word` and `@word` are read as constraints rather than as text, so the field is also the
/// fast way to narrow by tag or source on a board holding more chips than a thumb wants to
/// scroll past. They keep working when the reader ignores the suggestion menu and simply types
/// `#obj` — the token narrows by prefix on its own — which is what stops the operator from
/// being a trick you have to know.
public nonisolated struct MarginaliaQuery: Equatable, Sendable {
    public let text: String
    public let tagPrefixes: [String]
    public let sourcePrefixes: [String]

    public var isEmpty: Bool {
        text.isEmpty && tagPrefixes.isEmpty && sourcePrefixes.isEmpty
    }

    /// A token the caret is still inside, if the raw string ends in one. This is what the
    /// suggestion menu completes; a token followed by a space is finished and is not offered.
    public nonisolated enum Token: Equatable, Sendable {
        case tag(String)
        case source(String)
    }

    public static func parse(_ raw: String) -> MarginaliaQuery {
        var words: [String] = []
        var tags: [String] = []
        var sources: [String] = []

        for word in raw.split(whereSeparator: { $0.isWhitespace }) {
            if word.hasPrefix("#"), word.count > 1 {
                tags.append(String(word.dropFirst()).lowercased())
            } else if word.hasPrefix("@"), word.count > 1 {
                sources.append(String(word.dropFirst()).lowercased())
            } else {
                words.append(String(word))
            }
        }

        return MarginaliaQuery(
            text: words.joined(separator: " "),
            tagPrefixes: tags,
            sourcePrefixes: sources
        )
    }

    /// The unfinished token at the end of `raw`, for the suggestion menu.
    ///
    /// Only at the end, and only when it opens a word: a `#` in the middle of a URL or an `@`
    /// in an email address is text the reader is searching *for*, not an operator, and popping
    /// a menu over either is the behaviour that makes people stop using the field.
    public static func activeToken(in raw: String) -> Token? {
        guard let last = raw.split(whereSeparator: { $0.isWhitespace }).last,
              raw.last?.isWhitespace != true else { return nil }
        if last.hasPrefix("#") { return .tag(String(last.dropFirst()).lowercased()) }
        if last.hasPrefix("@") { return .source(String(last.dropFirst()).lowercased()) }
        return nil
    }

    /// `raw` with its trailing token removed, for the moment a suggestion is chosen and the
    /// token becomes a chip instead.
    public static func removingActiveToken(from raw: String) -> String {
        guard activeToken(in: raw) != nil else { return raw }
        var trimmed = raw
        while let last = trimmed.last, !last.isWhitespace {
            trimmed.removeLast()
        }
        return trimmed.trimmingCharacters(in: .whitespaces)
    }

    public func matches(_ entry: MarginaliaEntry) -> Bool {
        if !text.isEmpty, !entry.haystack.localizedStandardContains(text) {
            return false
        }
        for prefix in tagPrefixes {
            guard entry.tags.contains(where: { $0.hasPrefix(prefix) }) else { return false }
        }
        for prefix in sourcePrefixes {
            guard let title = entry.bookTitle?.lowercased(), title.contains(prefix) else {
                return false
            }
        }
        return true
    }
}
