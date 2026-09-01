import Foundation

/// The one definition of what a tag *is*.
///
/// Notes and sources are tagged independently — they are different vocabularies over different
/// things, and a shared table would force one on the other. What they must not have is two
/// different answers to "are `#Physics`, `physics ` and `Physics` the same tag", because two
/// such rules drift apart at the first edit to either one. So the tables stay separate and the
/// normalisation lives here.
public enum TagName {
    /// Tags are matched case-insensitively and written with or without a leading `#`, so they
    /// are stored in a single normalized form. Returns `nil` for anything that normalizes to
    /// nothing, which is what keeps a stray `#` out of the tag list.
    public static func normalized(_ raw: String) -> String? {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }

    /// The tag a note is born with when it is written inside a source.
    ///
    /// The `bookId` link already records which source a note came from, and it is the better
    /// answer to "show me everything from this book" — it is exact, and it survives a rename.
    /// It is also invisible everywhere the note is not a row in this app's own database: in the
    /// exported Markdown, in a tag search, in any other client. A note written in the reader is
    /// *about* the book it was written in, so it carries the book's name as a word of its own
    /// as well as a foreign key. Both, not either.
    ///
    /// The subtitle is dropped. Catalogues write `Sapiens: A Brief History of Humankind`, and a
    /// chip carrying all of that is a paragraph in a capsule; what precedes the colon is the
    /// name the reader actually says out loud. The head has to be substantial to be taken —
    /// `1: The Beginning` must not become `#1` — and everything else goes through the same
    /// `normalized` as a hand-typed tag, so a book tag and a tag someone types by hand are the
    /// same tag.
    ///
    /// Two books whose names agree up to the colon collapse onto one tag. That is accepted: a
    /// tag is a name and names collide, while the `bookId` beside it stays exact.
    public static func forSource(titled title: String) -> String? {
        guard let colon = title.firstIndex(of: ":") else { return normalized(title) }
        let head = title[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized(head.count >= 3 ? head : title)
    }
}
