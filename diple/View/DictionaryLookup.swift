import SwiftUI
import UIKit

/// A passage short enough to be a dictionary entry, on its way to the panel.
///
/// `Identifiable` so it can be the subject of a `.sheet(item:)` raised from the reader itself
/// rather than from the actions bar — for the reason already recorded on the translator's
/// presentation: the bar exists only while something is selected, and every route into a
/// lookup ends by clearing that.
struct DictionaryTerm: Identifiable, Equatable {
    let text: String

    var id: String { text }
}

/// The system dictionary, asked about a passage.
///
/// `UIReferenceLibraryViewController` is the panel the system's own Look Up raises, and it
/// reads whichever dictionaries the reader has switched on in Settings — the bilingual ones
/// included. That is the whole reason this is worth a control: a reader of an English book
/// gets a gloss in their own language without diple shipping a word list, asking the network,
/// or having to know which language this library is in. It exists on Mac Catalyst too, where
/// `Translation` has no slice at all, so the Mac gains a lookup it never had.
enum DictionaryLookup {
    /// A dictionary answers about a word, not about a paragraph, and the honest signal that a
    /// passage is not a term is its length. Three words rather than one because `ad hoc`,
    /// `carry on` and `дать дуба` are single entries; the character ceiling is what stops
    /// three long words from being asked about at all.
    private static let maximumWords = 3
    private static let maximumCharacters = 48

    /// The term a passage would be looked up under, or `nil` when the passage is prose.
    ///
    /// **`UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm:)` is deliberately
    /// not consulted here**, though it is the obvious thing to reach for. Two measurements
    /// against it, in order of how much they cost:
    ///
    /// 1. It is `false` for *everything* until a dictionary asset is installed, and iOS ships
    ///    none — measured on a clean simulator, where `ephemeral`, `carnival`, `свобода` and
    ///    `자유` all came back `false`. The only route to installing one is the Manage screen
    ///    inside the panel itself, so a control gated on that answer would never appear on the
    ///    device that needs it most, and the reader would have no way to reach the screen that
    ///    would fix it.
    /// 2. Even once dictionaries are installed the answer is per *word*, not per language:
    ///    a headword is found and an inflection beside it is not. A control that is a
    ///    dictionary on one word and a translator on the next word of the same sentence cannot
    ///    be learned, and an unlearnable control is worse than a panel that occasionally says
    ///    it found nothing — which is exactly what the system's own Look Up does, and what it
    ///    offers to fix on the spot.
    ///
    /// So the rule is structural: a term goes to the dictionary, prose goes to the translator,
    /// and the same passage always goes to the same place.
    ///
    /// Punctuation is trimmed from both ends after the whitespace is, in that order: a
    /// selection that ends a sentence arrives as `word.`, one lifted out of dialogue as
    /// `“word,”`, and the dictionary has an entry for neither. Nothing inside the term is
    /// touched — the hyphen in `well-being` and the apostrophe in `don't` are the word.
    static func term(in passage: String) -> String? {
        let trimmed = passage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
        let words = trimmed.split(whereSeparator: \.isWhitespace)

        guard !trimmed.isEmpty,
              trimmed.count <= maximumCharacters,
              words.count <= maximumWords,
              // A number, a bare `§` or a run of ellipses is short enough to pass everything
              // above and is not a word in any dictionary.
              trimmed.contains(where: \.isLetter)
        else { return nil }

        return trimmed
    }
}

/// The definition panel, presented as it comes.
///
/// It brings its own navigation bar, its own Done button and its own Manage screen, and
/// dismissing from inside it dismisses the sheet it was presented in — so there is nothing to
/// wire back. Anything drawn around it would be diple restating what the system already says,
/// and the Manage screen in particular has to stay reachable: it is where a reader with no
/// dictionaries installed gets one.
struct DictionaryDefinitionView: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ uiViewController: UIReferenceLibraryViewController, context: Context) {}
}
