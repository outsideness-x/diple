import Foundation
import ReadiumShared

/// A passage kept for the lifetime of one open reader.
///
/// This is intentionally a value, not a database record. The semantic Readium locator is the
/// source of truth after reflow or rotation; the copied text is only what lets the shelf remain
/// useful when a renderer can no longer resolve that locator.
public struct QuoteReference: Identifiable, Equatable, Hashable, Sendable {
    /// Stable identity for one source range inside one book.
    ///
    /// EPUB selections carry a DOM range in `locations`; PDFKit currently supplies the page
    /// locator but no character-range locator, so normalized selected text is the narrowest
    /// stable discriminator available there. Screen geometry never enters this key.
    public struct SourceKey: Hashable, Sendable {
        public let bookID: String
        public let href: AnyURL
        public let locations: Locator.Locations
        public let normalizedText: String

        public init(bookID: String, locator: Locator, text: String) {
            self.bookID = bookID
            self.href = locator.href
            self.locations = locator.locations
            self.normalizedText = Self.normalize(text)
        }

        private static func normalize(_ text: String) -> String {
            text.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
        }
    }

    public let sourceKey: SourceKey
    public let bookID: String
    public let locator: Locator
    public let text: String
    public let chapterTitle: String?

    public var id: SourceKey { sourceKey }

    public init?(bookID: String, locator: Locator, text: String, chapterTitle: String? = nil) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        self.sourceKey = SourceKey(bookID: bookID, locator: locator, text: text)
        self.bookID = bookID
        self.locator = locator
        self.text = text

        let title = (chapterTitle ?? locator.title)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.chapterTitle = title?.isEmpty == false ? title : nil
    }

    public init?(book: Book, selection: PendingSelection) {
        self.init(
            bookID: book.id,
            locator: selection.locator,
            text: selection.quote,
            chapterTitle: selection.locator.title
        )
    }

    public init?(book: Book, highlight: Highlight) {
        guard let locator = highlight.parsedLocator else { return nil }
        self.init(
            bookID: book.id,
            locator: locator,
            text: highlight.text,
            chapterTitle: locator.title
        )
    }
}

/// Small, in-memory working set owned by one `ReaderViewModel`.
///
/// It has no persistence or sync dependency by construction. Insertion order is retained so
/// the shelf reads as the sequence in which passages were put down, not reconstructed book
/// order.
public struct ReadingSessionQuoteStore: Equatable, Sendable {
    public private(set) var references: [QuoteReference] = []

    public init(references: [QuoteReference] = []) {
        for reference in references where !contains(reference) {
            self.references.append(reference)
        }
    }

    @discardableResult
    public mutating func add(_ reference: QuoteReference) -> Bool {
        guard !contains(reference) else { return false }
        references.append(reference)
        return true
    }

    public func contains(_ reference: QuoteReference) -> Bool {
        references.contains { $0.sourceKey == reference.sourceKey }
    }

    @discardableResult
    public mutating func remove(_ reference: QuoteReference) -> Bool {
        guard let index = references.firstIndex(where: { $0.sourceKey == reference.sourceKey }) else {
            return false
        }
        references.remove(at: index)
        return true
    }

    public mutating func clear() {
        references.removeAll(keepingCapacity: false)
    }
}
