import Foundation
import SwiftSoup

/// Turns Readium's two strings about a tapped note into something a page can print.
///
/// Readium has already done the reading. `EPUBNavigatorViewController.getNoteData` recognises
/// the anchor as a `noteref`, opens the resource it points at through the publication's own
/// resource API and hands the delegate the note element's **inner HTML** together with the
/// marker anchor's inner HTML. Nothing here re-reads the file, and nothing here decides what
/// counts as a note — that is the publisher's `epub:type`, and Readium's to interpret.
enum FootnoteParser {
    /// A marker is `1`, `*`, `a` or `[12]`. Anything longer is not a marker but a phrase the
    /// publisher used as a link, and printing it as one would put a sentence where a numeral
    /// belongs.
    private static let maximumMarkerLength = 6

    /// What a publisher sets between a repeated note number and the note itself.
    private static let markerSeparators: Set<Character> = [".", ")", "]", ":", ";", ",", "—", "–", "-"]

    /// The note, or `nil` when there is nothing worth raising a card for — in which case the
    /// caller must let the link be followed as it always was, rather than swallowing a tap and
    /// showing an empty card.
    static func footnote(id: String, content: String, referrer: String?) -> Footnote? {
        guard let document = try? SwiftSoup.parse(content) else { return nil }

        // The way back is a control, not a sentence. Publishers write it as an
        // `epub:type="backlink"` anchor rendering as `↩`, `‹` or the note's own number, and it
        // exists because the reader was taken away from the text — which is the very thing this
        // card does instead of. Printed here it would be a stray glyph at the end of the last
        // paragraph with nothing behind it to press.
        //
        // The attribute is written with its colon, as Readium writes it in `getNoteData` when
        // it selects `a[epub:type=noteref]` against the same books.
        _ = try? document.select("a[epub:type*=backlink]").remove()

        let marker = markerText(referrer)
        // The app's one definition of a paragraph, shared with the content index and Second
        // Read. A note is prose in a resource like any other; a second parser for it would be
        // a second set of rules about what a paragraph is.
        var paragraphs = BookContentExtractor.extractParagraphs(from: document)

        if let first = paragraphs.first {
            let stripped = strippingRepeatedMarker(first, marker: marker)
            if stripped.isEmpty {
                paragraphs.removeFirst()
            } else {
                paragraphs[0] = stripped
            }
        }

        guard !paragraphs.isEmpty else { return nil }
        return Footnote(id: id, marker: marker, paragraphs: paragraphs)
    }

    /// The marker as text. `<sup>1</sup>` is the common shape; `[1]` and `(1)` are common
    /// enough that the brackets are dropped, since the card draws its own relationship to the
    /// page and does not need the publisher's punctuation to stand in for it.
    private static func markerText(_ referrer: String?) -> String? {
        guard let referrer,
              let text = try? SwiftSoup.parse(referrer).text(),
              case let trimmed = text
                  .trimmingCharacters(in: .whitespacesAndNewlines)
                  .trimmingCharacters(in: CharacterSet(charactersIn: "[](){}")),
              !trimmed.isEmpty,
              trimmed.count <= maximumMarkerLength
        else { return nil }

        return trimmed
    }

    /// Notes very often begin by repeating their own number, because in print the number is how
    /// you find the note in a list of them. Here the marker is already printed beside the text,
    /// and a note reading `1 1 The lanterns were paper` is the seam showing.
    ///
    /// The boundary check is the whole of the care this needs: a note that genuinely opens
    /// `1938 was the year` begins with the marker `1` and must not lose its century.
    private static func strippingRepeatedMarker(_ paragraph: String, marker: String?) -> String {
        guard let marker, !marker.isEmpty, paragraph.hasPrefix(marker) else { return paragraph }

        let remainder = paragraph.dropFirst(marker.count)
        if let next = remainder.first, next.isLetter || next.isNumber { return paragraph }

        // Only what a publisher puts *between* a number and its note is dropped. Not any
        // punctuation: a note that opens on a quotation opens with a quotation mark, and it is
        // the first thing the note says.
        return remainder
            .drop(while: { $0.isWhitespace || Self.markerSeparators.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
