import Foundation

/// Turns the navigator's stream of positions into honest `(characters, seconds)` samples.
///
/// Measuring reading speed sounds like subtraction — how far did the position move, over how
/// long — and almost everything that arrives here is not reading. The page sits open while the
/// kettle boils. The reader jumps to a chapter from the table of contents and covers a fifth of
/// the book in 40 milliseconds. They scrub the progress bar to check how far in they are, then
/// scrub back. They put the phone down mid-paragraph and pick it up the next evening. Every one
/// of those produces a rate, and a rate is worthless unless the things that are not reading
/// have been thrown away first.
///
/// So this type's whole job is refusal. It holds an anchor — a position and the moment it was
/// reached — and only ever emits when the distance from that anchor is large enough to mean
/// something and was covered without a gap that says nobody was there. Everything else resets
/// the anchor and returns nothing.
///
/// It is a value type with no dependencies on purpose: what it does is arithmetic on a stream
/// of positions, which is exactly the kind of thing that should be testable without a book, a
/// navigator or a clock.
public struct ReadingSpeedSampler {
    /// One stretch of reading believed to be real.
    public struct Sample: Equatable {
        public let characters: Double
        public let seconds: Double
    }

    /// A sample is only emitted once this much has been covered — a page or two.
    ///
    /// In scroll mode the navigator reports a location on *every scrolled pixel*, so without a
    /// floor the samples would be a few characters over a few milliseconds each: all rounding
    /// error, and a rate computed from them says more about the scroll physics than about the
    /// reader. Falling short does not reset the anchor, it simply waits — the window keeps
    /// growing until it is worth something.
    static let minimumSampleCharacters: Double = 2_000

    /// A gap longer than this between two reports means nobody was reading, and the window
    /// that spans it is discarded rather than counted.
    ///
    /// It has to clear the slowest honest interval between reports, which is a page turn in
    /// paginated mode — a dense page at an unhurried pace is well over a minute. Three minutes
    /// clears that with room to spare while still catching the phone going into a pocket. The
    /// bias this leaves is knowable and one-sided: genuine reading slower than a page every
    /// three minutes is dropped, so the figure errs slightly fast. Counting the pocket would
    /// err in the same direction as an *unbounded* error, which is worse than a bounded one.
    static let idleTimeout: TimeInterval = 180

    /// Prose length of the source being read. A book the indexer has not measured cannot be
    /// sampled at all — there is no way to turn a fraction into characters.
    private let totalCharacters: Double

    private var anchorProgress: Double?
    private var anchorAt: Date?
    /// Kept apart from `anchorAt`: the anchor is where the window *starts*, this is when the
    /// reader was last known to be present. A window may legitimately be several reports long,
    /// and it is the gap between consecutive reports that says somebody left — not the age of
    /// the window itself.
    private var lastReportAt: Date?

    /// `nil` for a source whose length is unknown, so the caller cannot accidentally sample one.
    public init?(totalCharacters: Int?) {
        guard let totalCharacters, totalCharacters > 0 else { return nil }
        self.totalCharacters = Double(totalCharacters)
    }

    /// Drops the window in progress without emitting it.
    ///
    /// Called for every move that is not reading: a jump from the table of contents, a search
    /// result, a bookmark, a drag of the progress bar, a step back through link history, and
    /// the app leaving the foreground. Each of those covers ground in no time at all, and while
    /// the plausibility band in `ReadingSpeed` would reject the resulting rate anyway, letting
    /// it get that far means relying on a backstop to catch something already known at the call
    /// site. Naming the cause here is cheaper and does not depend on the numbers.
    public mutating func invalidate() {
        anchorProgress = nil
        anchorAt = nil
        lastReportAt = nil
    }

    /// Folds in one reported position, and returns a sample when one has been earned.
    public mutating func observe(progress: Double, now: Date = Date()) -> Sample? {
        defer { lastReportAt = now }

        // Nobody was here for the last stretch, so whatever it spans is not reading.
        if let lastReportAt, now.timeIntervalSince(lastReportAt) > Self.idleTimeout {
            restart(at: progress, now: now)
            return nil
        }

        guard let anchorProgress, let anchorAt else {
            restart(at: progress, now: now)
            return nil
        }

        let delta = progress - anchorProgress
        // Standing still, or re-reading backwards. Neither is progress through the book, and
        // the second is real reading whose characters have already been counted once.
        guard delta > 0 else {
            restart(at: progress, now: now)
            return nil
        }

        let characters = totalCharacters * delta
        // Not enough yet — hold the anchor and let the window grow.
        guard characters >= Self.minimumSampleCharacters else { return nil }

        let seconds = now.timeIntervalSince(anchorAt)
        restart(at: progress, now: now)
        guard seconds > 0 else { return nil }
        return Sample(characters: characters, seconds: seconds)
    }

    private mutating func restart(at progress: Double, now: Date) {
        anchorProgress = progress
        anchorAt = now
    }
}
