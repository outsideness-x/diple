import Foundation
import NaturalLanguage

/// One passage that answers another.
public nonisolated struct PassageEcho: Identifiable, Sendable, Equatable {
    public let passage: Highlight
    /// The words the two passages have in common, most distinctive first.
    ///
    /// Shown, not hidden. A connection the reader cannot check is a connection they have to
    /// take on trust, and this one is cheap to check: these are the words. It also means a bad
    /// echo is visibly bad rather than mysteriously bad.
    public let sharedTerms: [String]
    public let weight: Double

    public var id: String { passage.id }

    public init(passage: Highlight, sharedTerms: [String], weight: Double) {
        self.passage = passage
        self.sharedTerms = sharedTerms
        self.weight = weight
    }
}

/// Passages that share the words which are rare *in this reader's library*.
///
/// **What it does and does not claim.** This finds passages built from the same uncommon
/// vocabulary. It does not know that `свобода` and `liberty` are the same idea, and it does not
/// pretend to: no model, no embedding, no download, no language it silently fails at. What it
/// does know is the one corpus that matters here — the reader's own saved passages — and that
/// is what makes it worth reading. A word appearing in half of somebody's highlights carries
/// almost no weight; the same word in a library that has never used it before is the whole
/// connection. Nobody has to write a stop-word list, because every library writes its own.
///
/// It is deliberately a **deterministic, explainable** rule rather than a good guess. Two
/// passages are joined only when they share at least two distinctive words, and the words are
/// printed alongside. A reader can disagree with an echo, which is more than they can do with a
/// similarity score.
public nonisolated struct PassageEchoCorpus: Sendable {
    /// Below this, term rarity is not a measurement, it is noise: in a library of four
    /// passages every word is rare. Silence is the honest output.
    public static let minimumCorpusSize = 8
    /// One shared word is a coincidence — two people can both say "attention". Two shared rare
    /// words is a subject.
    public static let minimumSharedTerms = 2
    /// How rare a shared word has to be, as a fraction of the rarest a word can be in this
    /// corpus, before it counts towards the two.
    ///
    /// Without it the cosine alone says two passages made entirely of everyday words are a
    /// perfect match — which is true and useless: cosine measures direction, and two pieces of
    /// boilerplate do point the same way. Scaling to the corpus rather than fixing a number
    /// keeps the rule the same sentence in a library of ten passages and one of ten thousand:
    /// *shared words that are rare in your library*.
    public static let distinctivenessFraction = 0.5
    /// A floor under the cosine, so a long passage that happens to touch two of a short one's
    /// words does not count as an answer to it.
    public static let minimumWeight = 0.08

    private struct Document {
        let passage: Highlight
        let terms: Set<String>
        /// Comparison key → the word as this passage actually wrote it.
        let written: [String: String]
        let norm: Double
    }

    private let documents: [Document]
    private let idf: [String: Double]
    /// The `idf` a word has to reach to count as one of the two. Derived from the corpus: the
    /// rarest a word can be here is one that appears in exactly one passage.
    private let distinctivenessFloor: Double

    public var isUsable: Bool { documents.count >= Self.minimumCorpusSize }

    public init(_ passages: [Highlight]) {
        // The comment counts as part of the passage. The most valuable connection in a reading
        // library is not between two authors' sentences — it is between the two moments the
        // reader wrote something down, and dropping their words would throw exactly that away.
        let tokenized = passages.map { ($0, PassageEchoCorpus.index([$0.text, $0.comment].compactMap { $0 }.joined(separator: " "))) }

        var documentFrequency: [String: Int] = [:]
        for (_, written) in tokenized {
            for term in written.keys { documentFrequency[term, default: 0] += 1 }
        }

        let total = Double(tokenized.count)
        // `log((N + 1) / (df + 1))` rather than the textbook `log(N / df)`: it never goes
        // negative, and it decays to nothing for a word that is in everything — which is what
        // lets the library define its own stop words instead of a list somebody maintains.
        var weights: [String: Double] = [:]
        weights.reserveCapacity(documentFrequency.count)
        for (term, frequency) in documentFrequency {
            weights[term] = log((total + 1) / (Double(frequency) + 1))
        }

        self.idf = weights
        self.distinctivenessFloor = Self.distinctivenessFraction * log((total + 1) / 2)
        self.documents = tokenized.map { passage, written in
            let terms = Set(written.keys)
            let norm = sqrt(terms.reduce(0.0) { partial, term in
                let weight = weights[term] ?? 0
                return partial + weight * weight
            })
            return Document(passage: passage, terms: terms, written: written, norm: norm)
        }
    }

    /// The passages that answer this one, strongest first.
    ///
    /// `excludingSameSource` is not a preference toggle: two passages from one book are usually
    /// two paragraphs of the same argument, and a page that offers them as a discovery is
    /// telling the reader something they already know. Where the promise is "somewhere else in
    /// your reading", the same book is excluded; where the reader is exploring one passage,
    /// a neighbour is a fair answer.
    public func echoes(
        for passage: Highlight,
        limit: Int = 3,
        excludingSameSource: Bool = false
    ) -> [PassageEcho] {
        guard isUsable else { return [] }
        guard let subject = documents.first(where: { $0.passage.id == passage.id }) ?? makeDocument(for: passage),
              subject.norm > 0
        else { return [] }

        return documents
            .compactMap { candidate -> PassageEcho? in
                guard candidate.passage.id != passage.id, candidate.norm > 0 else { return nil }
                if excludingSameSource, candidate.passage.bookId == passage.bookId { return nil }

                let shared = subject.terms.intersection(candidate.terms)
                    .filter { (idf[$0] ?? 0) >= distinctivenessFloor }
                guard shared.count >= Self.minimumSharedTerms else { return nil }

                // The cosine is taken over *everything* the two share, not only the
                // distinctive words: the filter above decides whether there is a connection,
                // and this decides how strong it is.
                let dot = subject.terms.intersection(candidate.terms).reduce(0.0) { partial, term in
                    let weight = idf[term] ?? 0
                    return partial + weight * weight
                }
                let weight = dot / (subject.norm * candidate.norm)
                guard weight >= Self.minimumWeight else { return nil }

                let ordered = shared
                    .sorted { (idf[$0] ?? 0, $1) > (idf[$1] ?? 0, $0) }
                    .prefix(4)
                    // Printed as the *subject* wrote them: the reader is looking at that
                    // passage, and its wording is the one they will recognise.
                    .map { subject.written[$0] ?? candidate.written[$0] ?? $0 }
                return PassageEcho(passage: candidate.passage, sharedTerms: Array(ordered), weight: weight)
            }
            // Ties broken by id so the same library always produces the same page. A list that
            // reshuffles between two identical scores reads as a bug the reader cannot report.
            .sorted { ($0.weight, $1.passage.id) > ($1.weight, $0.passage.id) }
            .prefix(max(0, limit))
            .map { $0 }
    }

    private func makeDocument(for passage: Highlight) -> Document? {
        let written = Self.index([passage.text, passage.comment].compactMap { $0 }.joined(separator: " "))
        guard !written.isEmpty else { return nil }
        let terms = Set(written.keys)
        let norm = sqrt(terms.reduce(0.0) { partial, term in
            let weight = idf[term] ?? 0
            return partial + weight * weight
        })
        return Document(passage: passage, terms: terms, written: written, norm: norm)
    }

    /// The words of one passage, keyed by the form two inflections of them share.
    ///
    /// Returns stem → the word as it was actually written, because both halves are needed: the
    /// stem is what two passages are compared on, and the written word is what gets printed
    /// under the echo. Showing the reader `карнавальн` would be showing them the machinery.
    ///
    /// **Two normalisations, because one is not available.** `NLTagger`'s lemma scheme answers
    /// for English (`carnivals` → `carnival`, `were` → `be`) and returns **nothing at all** for
    /// Russian — measured, with the language set explicitly and correctly detected as `ru`, not
    /// assumed. Left there, the feature would have been useful in English and useless in a
    /// Russian library: `карнавальном` and `карнавальное` are one word to a reader and two
    /// strings to a tokenizer, and a rule that asks for two shared words would have found
    /// almost nothing.
    ///
    /// So a Cyrillic token that came back without a lemma is stemmed by stripping the longest
    /// matching inflectional ending, and only while four characters remain. It is a light
    /// stemmer, not a morphological analyser: `держится` and `держаться` still part ways, and
    /// that is the accepted cost of not carrying a Russian morphology table. Every other script
    /// keeps its token as it is — a badly-guessed Korean stemmer would be worse than none.
    ///
    /// The unit is the system's word, not a split on spaces, because Korean does not put spaces
    /// where a splitter would want them. Case and diacritics are folded, so `Свобода` and
    /// `свободa` are one word and `ё` collapses onto `е`.
    ///
    /// A term needs at least one letter and at least two characters. There is no stop-word
    /// list: that job belongs to the corpus, and a list would be a claim about a language
    /// rather than about this reader.
    static func index(_ text: String) -> [String: String] {
        guard !text.isEmpty else { return [:] }
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text

        var index: [String: String] = [:]
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lemma,
            options: [.omitPunctuation, .omitWhitespace, .omitOther]
        ) { tag, range in
            let written = String(text[range])
                .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: nil)
            guard written.count >= 2, written.contains(where: { $0.isLetter }) else { return true }

            // An empty lemma is the tagger saying "no idea", not "no word".
            let lemma = tag?.rawValue
                .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: nil)
            // Stemmed either way. Whether the tagger offers a lemma for a Russian word turns
            // out to depend on the language it detects for the *surrounding* text — a passage
            // with one English sentence in it can come back with the raw word as its own
            // "lemma" — and two passages that key the same word differently would never meet.
            // `stemmed` only touches Cyrillic, so an English lemma passes through untouched.
            let key = stemmed((lemma?.isEmpty == false ? lemma! : written))
            // First writing wins, so the printed word is the one nearest the top of the passage.
            if index[key] == nil { index[key] = written }
            return true
        }
        return index
    }

    /// The comparison keys of one passage.
    public static func terms(in text: String) -> Set<String> {
        Set(index(text).keys)
    }

    /// A light Russian stemmer, applied only to a token that is entirely Cyrillic.
    ///
    /// Endings are tried longest first — `карнавальном` must lose `ом`, not `м` — and only
    /// while four characters would remain, so short words are not filed down to nothing.
    static func stemmed(_ word: String) -> String {
        guard word.unicodeScalars.allSatisfy({ Self.cyrillic.contains($0) || $0 == "-" }) else { return word }
        for ending in Self.russianEndings where word.count - ending.count >= 4 && word.hasSuffix(ending) {
            return String(word.dropLast(ending.count))
        }
        return word
    }

    private static let cyrillic = CharacterSet(charactersIn: "\u{0400}"..."\u{04FF}")

    /// Inflectional endings, longest first. Nouns and adjectives carry most of the meaning in a
    /// saved passage, so they are covered thoroughly; verbs get the endings that are unambiguous.
    private static let russianEndings: [String] = [
        "иями", "ями", "ами", "ыми", "ими", "ому", "ему", "ого", "его", "ться",
        "ешь", "ишь", "ете", "ите", "ают", "яют", "уют", "юют", "тся",
        "ов", "ев", "ой", "ий", "ый", "ая", "яя", "ое", "ее", "ые", "ие",
        "ых", "их", "ом", "ем", "ах", "ях", "ую", "юю", "ей", "ам", "ям",
        "ут", "ют", "ат", "ят", "ил", "ыл", "ла", "ло", "ли", "ть",
        // A bare "л" is deliberately absent. It is a past-tense ending, but it is also the last
        // letter of a great many nouns — it turned `карнавал` into `карнава` and would have
        // kept the noun from ever meeting itself. The past tense is covered by `ил`/`ыл`/`ла`.
        "а", "я", "о", "е", "у", "ю", "ы", "и", "ь", "й"
    ]
}
