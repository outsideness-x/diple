import Foundation

/// A publisher's note, on its way to the foot of the page it was referred from.
///
/// The whole reason the type exists is that a note has **two** places in a book — the marker in
/// the sentence and the text kept somewhere else — and only the first of them is where a reader
/// wants to be. Following the link is what a book has to make you do; an app does not.
public struct Footnote: Identifiable, Equatable {
    /// The note's own address in the publication, which is what the marker linked to. Stable
    /// for the same note and different for every other one, so reopening the same note is the
    /// same card and the page beneath it never has to be consulted.
    public let id: String
    /// What the marker in the text said — `1`, `*`, `a`. `nil` when the publisher drew it as an
    /// image, or set it to something too long to be a marker at all.
    public let marker: String?
    /// The note's paragraphs, in document order. Never empty: a note that parsed to nothing is
    /// not a `Footnote`, it is a link that still has to be followed.
    public let paragraphs: [String]
}
