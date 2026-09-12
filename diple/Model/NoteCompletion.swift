import Foundation

/// What `[[` and `#` offer while they are being typed, and in what order.
///
/// A pure ranking over plain strings, kept apart from the menu and the text view for the same
/// reason `NoteSyntax` is: the rules are the product, and they are only worth trusting if they
/// can be checked without a keyboard.
public enum NoteCompletion {
    /// A row the `#` menu can offer.
    public enum TagPick: Equatable, Sendable {
        /// A word already in the note vocabulary.
        case existing(String)
        /// The word being typed, which no note carries yet.
        case new(String)

        public var tag: String {
            switch self {
            case .existing(let tag), .new(let tag): return tag
            }
        }
    }

    /// A row the `[[` menu can offer.
    public enum LinkPick: Equatable, Sendable {
        /// A note that exists, by the title the link will name.
        case note(String)
        /// A link to a title no note has yet. `[[A later thought]]` is ordinary Markdown in every
        /// vault that reads it, and the note it names can be written afterwards.
        case unwritten(String)

        public var title: String {
            switch self {
            case .note(let title), .unwritten(let title): return title
            }
        }
    }

    /// Titles first by prefix, then by containment, each group in the order given — which is the
    /// host's own order, most recently touched first. A duplicate title is offered once: two notes
    /// called the same are one link, and `NoteKnowledge` already resolves it to both.
    public static func links(matching query: String, in titles: [String], limit: Int = 6) -> [LinkPick] {
        let typed = query.trimmingCharacters(in: .whitespaces)
        let needle = fold(typed)
        var seen = Set<String>()
        var byPrefix: [String] = []
        var byContent: [String] = []

        for title in titles {
            let key = fold(title)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            if needle.isEmpty || key.hasPrefix(needle) {
                byPrefix.append(title)
            } else if key.contains(needle) {
                byContent.append(title)
            }
        }

        var picks = (byPrefix + byContent).prefix(limit).map(LinkPick.note)
        // The typed title is offered as a link of its own only when nothing is called exactly
        // that: offering `[[Roadmap]]` twice — once as the note, once as an unwritten one — is
        // one row too many.
        if !needle.isEmpty, !seen.contains(needle) {
            if picks.count == limit { picks.removeLast() }
            picks.append(.unwritten(typed))
        }
        return picks
    }

    /// Words from the vocabulary that start with what has been typed, in the vocabulary's order,
    /// and the typed word itself when it is new. Matching is on the normalised form, so `#Физ`
    /// finds `физика`, because the tag it would add is the normalised one anyway.
    public static func tags(matching query: String, in vocabulary: [String], limit: Int = 6) -> [TagPick] {
        guard let typed = TagName.normalized(query) else { return [] }
        let needle = fold(typed)
        let known = vocabulary.compactMap(TagName.normalized)
        var seen = Set<String>()
        var picks: [TagPick] = []

        for tag in known where seen.insert(tag).inserted && fold(tag).hasPrefix(needle) {
            picks.append(.existing(tag))
            if picks.count == limit { break }
        }

        if !known.contains(typed) {
            if picks.count == limit { picks.removeLast() }
            picks.append(.new(typed))
        }
        return picks
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
