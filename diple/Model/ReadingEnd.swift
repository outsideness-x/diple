import Foundation
import ReadiumShared

public struct ReadingEnd: Equatable, Sendable {
    /// The total publication progression (0...1) where the main text ends.
    public let progression: Double

    /// The authority for the boundary. This is shown to the reader when the app asks whether
    /// the remaining back matter should count as finishing the book.
    public let source: Source

    public enum Source: Equatable, Sendable {
        /// The publisher declared the boundary in the publication landmarks.
        case landmarks
        /// The boundary was inferred from a continuous back-matter tail in the contents.
        case contents
        /// The publication supplied no trustworthy boundary before its final position.
        case wholeBook
    }

    public var hasBackMatter: Bool { progression < 0.995 }

    public static let wholeBook = ReadingEnd(progression: 1.0, source: .wholeBook)

    public static func resolve(
        landmarks: [ReadiumShared.Link],
        tableOfContents: [ReadiumShared.Link],
        readingOrder: [ReadiumShared.Link],
        positions: [ReadiumShared.Locator]
    ) -> ReadingEnd {
        if let readingOrderIndex = earliestBackMatterLandmarkIndex(
            in: landmarks,
            readingOrder: readingOrder
        ),
            let progression = progression(
                at: readingOrderIndex,
                readingOrder: readingOrder,
                positions: positions
            ),
            isTrustworthy(progression)
        {
            return ReadingEnd(progression: progression, source: .landmarks)
        }

        if let firstBackMatterEntry = backMatterTail(in: tableOfContents).first,
           let readingOrderIndex = readingOrder.firstIndexWithHREF(firstBackMatterEntry),
           let progression = progression(
               at: readingOrderIndex,
               readingOrder: readingOrder,
               positions: positions
           ),
           isTrustworthy(progression)
        {
            return ReadingEnd(progression: progression, source: .contents)
        }

        return .wholeBook
    }

    private static let epubStructureRelationPrefix =
        "http://idpf.org/epub/vocab/structure/#"

    private static let backMatterLandmarkRelations: Set<LinkRelation> = [
        "endnotes",
        "footnotes",
        "rearnotes",
        "bibliography",
        "index",
        "glossary",
        "appendix",
        "colophon",
    ].reduce(into: []) { relations, type in
        relations.insert(LinkRelation("\(epubStructureRelationPrefix)\(type)"))
    }

    /// Publisher vocabulary is unreliable across languages, so contents inference recognizes
    /// only this explicit English, Russian, and Korean lexicon instead of guessing from locale.
    private static let backMatterLexiconByLanguage: [String: Set<String>] = [
        "en": [
            "notes", "endnotes", "footnotes", "bibliography", "works cited",
            "further reading", "index", "appendix", "appendices", "glossary",
            "about the author", "acknowledgements", "acknowledgments", "copyright",
            "colophon", "credits", "permissions",
        ],
        "ru": [
            "примечания", "комментарии", "сноски", "библиография", "список литературы",
            "литература", "указатель", "именной указатель", "предметный указатель",
            "приложение", "приложения", "глоссарий", "об авторе", "благодарности",
            "выходные данные", "источники",
        ],
        "ko": [
            "주석", "미주", "각주", "참고문헌", "찾아보기", "부록", "용어 해설", "저자 소개",
            "감사의 말", "판권",
        ],
    ]

    private static let backMatterTitles = Set(backMatterLexiconByLanguage.values.joined())

    private static func earliestBackMatterLandmarkIndex(
        in landmarks: [Link],
        readingOrder: [Link]
    ) -> Int? {
        landmarks.compactMap { landmark in
            guard landmark.rels.contains(where: backMatterLandmarkRelations.contains),
                  let index = readingOrder.firstIndexWithHREF(landmark)
            else { return nil }
            return index
        }
        .min()
    }

    private static func backMatterTail(in tableOfContents: [Link]) -> ArraySlice<Link> {
        var boundary = tableOfContents.endIndex
        while boundary > tableOfContents.startIndex {
            let previous = tableOfContents.index(before: boundary)
            guard isBackMatterTitle(tableOfContents[previous].title) else { break }
            boundary = previous
        }
        return tableOfContents[boundary...]
    }

    private static func isBackMatterTitle(_ title: String?) -> Bool {
        guard let title else { return false }
        let normalized = normalize(title)
        guard !normalized.isEmpty else { return false }
        return backMatterTitles.contains { term in
            normalized == term || normalized.hasPrefix("\(term) ")
        }
    }

    private static func normalize(_ title: String) -> String {
        let removed = CharacterSet.punctuationCharacters.union(.decimalDigits)
        let scalars = title.lowercased().unicodeScalars.map { scalar in
            removed.contains(scalar) ? " " : String(scalar)
        }
        return scalars.joined().split { $0.isWhitespace }.joined(separator: " ")
    }

    private static func progression(
        at readingOrderIndex: Int,
        readingOrder: [Link],
        positions: [Locator]
    ) -> Double? {
        let href = readingOrder[readingOrderIndex].url()
        return positions.first { $0.href.isEquivalentTo(href) }?.locations.totalProgression
    }

    private static func isTrustworthy(_ progression: Double) -> Bool {
        progression > 0.5 && progression <= 1.0
    }
}
