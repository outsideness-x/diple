import Foundation

/// What ⌘K on the desk can go to: a book, or a passage in one.
public enum QuickOpenItem: Identifiable, Hashable, Sendable {
    case book(Book)
    case passage(PassageItem)

    public var id: String {
        switch self {
        case .book(let book): return "book:\(book.id)"
        case .passage(let passage): return "passage:\(passage.id)"
        }
    }
}

/// The matching behind ⌘K: instant, local and forgiving.
///
/// It does not go through the search index, and that is the point of it. The index answers
/// "where does this word occur in everything I have" — notes, article text, the paragraphs of
/// every book — and Search Everything (⌘7) is where that question is asked. ⌘K answers "take me
/// to the thing I am thinking of": a title half typed, the first words of a passage marked last
/// week. That has to answer between two keystrokes, and over the library's own titles and the
/// reader's own passages it is a filter, not a search.
public enum QuickOpen {
    /// Books before passages, because a title is what a reader most often means and a passage
    /// is what they mean when no title fits. Every word of the query has to appear, in any
    /// order, ignoring case and accents. A title that starts with the query outranks one with a
    /// word that does, which outranks one that merely contains it, which outranks a book found
    /// only by its byline; ties go to the book opened most recently.
    ///
    /// Passages take at most three of the places while books are still matching, so a common
    /// word cannot bury the book being looked for under its own quotations — and all of the
    /// places once no title matches at all.
    ///
    /// With nothing typed, the books most recently opened: where ⌘K is most often pressed to go.
    public static func results(
        for query: String,
        books: [Book],
        passages: [PassageItem],
        limit: Int = 8
    ) -> [QuickOpenItem] {
        let words = normalized(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else {
            let opened: [Book] = books.filter { $0.lastOpenedAt != nil }
            let recent: [Book] = opened.sorted {
                ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast)
            }
            return recent.prefix(limit).map { QuickOpenItem.book($0) }
        }
        let phrase = words.joined(separator: " ")

        let rankedBooks: [(rank: Int, book: Book)] = books.compactMap { book in
            let title = normalized(book.title)
            let byline = normalized([book.author, book.sourceHost].compactMap { $0 }.joined(separator: " "))
            guard words.allSatisfy({ title.contains($0) || byline.contains($0) }) else { return nil }
            let rank: Int
            if title.hasPrefix(phrase) {
                rank = 0
            } else if title.contains(" " + phrase) {
                rank = 1
            } else if words.allSatisfy(title.contains) {
                rank = 2
            } else {
                rank = 3
            }
            return (rank, book)
        }
        .sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return (lhs.book.lastOpenedAt ?? .distantPast) > (rhs.book.lastOpenedAt ?? .distantPast)
        }

        let matchedPassages = passages
            .filter { passage in
                let haystack = normalized(passage.highlight.text + " " + (passage.comment ?? ""))
                return words.allSatisfy(haystack.contains)
            }
            .sorted { $0.highlight.createdAt > $1.highlight.createdAt }

        let passageShare = min(matchedPassages.count, 3)
        let bookItems: [QuickOpenItem] = rankedBooks
            .prefix(max(limit - passageShare, 0))
            .map { QuickOpenItem.book($0.book) }
        let passageItems: [QuickOpenItem] = matchedPassages
            .prefix(max(limit - bookItems.count, 0))
            .map { QuickOpenItem.passage($0) }
        return bookItems + passageItems
    }

    /// One spelling for comparing: lower case, no accents, no full-width forms — `Brontë`
    /// answers to `bronte`, `Ёлка` to `елка`.
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
