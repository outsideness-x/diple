import Foundation
import ReadiumShared

/// Where the reader has been inside this book, so that no jump is a one-way door.
///
/// Browser semantics, deliberately. `back` holds the places jumps departed from, newest last;
/// `forward` holds what stepping back undid. A footnote followed by reflex and returned from by
/// reflex is the commonest pair of taps in the reader, and while there was only a back stack the
/// second of those taps was destructive: the note was gone, and the only way to it was to find
/// the marker in the text again.
///
/// A value type with no knowledge of the view model or of Readium's navigator, so the rules
/// below can be exercised without opening a publication.
///
/// **Session-scoped, and that is the whole of its lifetime.** The trail is never written to
/// SQLite or to CloudKit: it describes one sitting with a book, not anything about the book. The
/// reading position is a different thing, is persisted, and is unaffected by any of this.
public struct ReadingTrail: Equatable {
    /// Places a jump departed from, oldest first. `last` is the next step back.
    public private(set) var back: [Locator] = []
    /// Places a step back left behind, oldest first. `last` is the next step forward.
    public private(set) var forward: [Locator] = []

    public init() {}

    /// The deepest trail kept.
    ///
    /// A long sitting through an annotated edition can follow hundreds of notes, and a stack
    /// that grows with every one of them holds locators nobody remembers leaving. Fifty steps
    /// is far past any chain a reader will actually walk back and still a bounded amount of
    /// memory. The oldest entries are dropped, never the newest, because the way back from
    /// *here* is the one that is about to be asked for.
    static let depthLimit = 50

    /// How close two positions have to be before the trail treats them as one place.
    ///
    /// This is not "the same page" — it is "the same report, twice". Readium can announce a
    /// single footnote tap through both `shouldNavigateToLink` and `shouldNavigateToNoteAt`,
    /// and a reader who follows two markers from one line departs from what is, for this
    /// purpose, the same spot. Without this the way back is a row of taps that all land within
    /// a sentence of each other. It is kept deliberately tight — five ten-thousandths of a
    /// book is a paragraph or two, well inside one screen — so that two genuinely different
    /// return points are never folded into one.
    static let sameSpotTolerance = 0.0005

    public var canGoBack: Bool { !back.isEmpty }
    public var canGoForward: Bool { !forward.isEmpty }

    /// Where a step back would land, without taking it.
    public var backDestination: Locator? { back.last }
    /// Where a step forward would land, without taking it.
    public var forwardDestination: Locator? { forward.last }

    /// Remembers where a jump departed from, and returns whether anything was added.
    ///
    /// Clearing `forward` here is what makes the two stacks a trail rather than two unrelated
    /// lists: once the reader has gone somewhere new, the branch they had stepped back out of
    /// is no longer anywhere they can get to by walking forwards, and offering it would take
    /// them to a page they never asked twice for.
    @discardableResult
    public mutating func record(_ origin: Locator) -> Bool {
        forward.removeAll()
        guard !Self.isSameSpot(origin, as: back.last) else { return false }
        back.append(origin)
        if back.count > Self.depthLimit {
            back.removeFirst(back.count - Self.depthLimit)
        }
        return true
    }

    /// Takes one step back and reports where to go, or `nil` when there is nowhere behind.
    ///
    /// `current` is where the step is being taken *from*, and it becomes the forward step. It
    /// is dropped when it is the destination itself, which is what stops a stale return point
    /// — one recorded for a jump the navigator never completed — from putting the page the
    /// reader is already on into the forward stack.
    public mutating func stepBack(leaving current: Locator?) -> Locator? {
        guard let destination = back.popLast() else { return nil }
        if let current, !Self.isSameSpot(current, as: destination) {
            forward.append(current)
            if forward.count > Self.depthLimit {
                forward.removeFirst(forward.count - Self.depthLimit)
            }
        }
        return destination
    }

    /// Takes one step forward and reports where to go, or `nil` when there is nothing to redo.
    public mutating func stepForward(leaving current: Locator?) -> Locator? {
        guard let destination = forward.popLast() else { return nil }
        if let current, !Self.isSameSpot(current, as: destination) {
            back.append(current)
            if back.count > Self.depthLimit {
                back.removeFirst(back.count - Self.depthLimit)
            }
        }
        return destination
    }

    /// How a stop names itself on the control that offers it.
    ///
    /// The chapter first, because "Back to Chapter 5" is a promise a reader can check against
    /// what they remember; the percentage only when the publication names nothing, because a
    /// number is at least verifiable against the bar. Neither is available for a locator with
    /// no title and no progression — a bare fragment from a hand-written manifest — and the
    /// generic phrase is still true, which is the bar every string on a control has to clear.
    public static func label(for locator: Locator) -> String {
        if let title = locator.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        if let progression = locator.locations.totalProgression {
            return "\(Int((min(max(progression, 0), 1) * 100).rounded()))%"
        }
        return "where you were"
    }

    /// Whether two locators point at a place the reader would not tell apart.
    ///
    /// Resource first: two positions in different files are never the same spot, whatever their
    /// progressions happen to be. Within one resource the comparison walks the locations from
    /// the most global measure to the most local, because a locator carries whichever of them
    /// its source could supply — the navigator reports `totalProgression`, a table of contents
    /// entry often carries neither, and a position index is all a PDF has.
    static func isSameSpot(_ lhs: Locator, as rhs: Locator?) -> Bool {
        // `isEquivalentTo`, not `==`: it normalises the URL first, so the same resource
        // reached once from a manifest and once from the navigator compares equal.
        guard let rhs, lhs.href.isEquivalentTo(rhs.href) else { return false }
        if let left = lhs.locations.totalProgression, let right = rhs.locations.totalProgression {
            return abs(left - right) <= sameSpotTolerance
        }
        if let left = lhs.locations.progression, let right = rhs.locations.progression {
            return abs(left - right) <= sameSpotTolerance
        }
        if let left = lhs.locations.position, let right = rhs.locations.position {
            return left == right
        }
        // Nothing but a resource to compare: two locators into the same file, neither of which
        // says where. Treating them as one place is the safer answer — the alternative is a
        // stack of identical steps back to the top of the same chapter.
        return lhs.locations.fragments == rhs.locations.fragments
    }
}
