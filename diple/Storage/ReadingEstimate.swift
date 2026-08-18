import Foundation

/// How long a book takes, and how much of it is left.
///
/// The single most useful thing an app can say about a text it is about to hand you, and diple
/// already stored everything needed for it: `bookContentIndex` knows how long each source is,
/// and `furthestProgress` knows how far the reader has got.
///
/// The rate is not this type's business. It used to be — two constants lived here, 6 characters
/// a word and 200 words a minute — and a constant is a claim about readers in general, which is
/// a claim about nobody in particular. What is left here is the arithmetic and the wording; the
/// rate comes from `ReadingSpeed`, which measures it from the reader's own reading, per script.
public enum ReadingEstimate {
    /// `nil` for anything under half a minute: rounding a two-line article up to "1 min left"
    /// is a claim, and rounding it down to "0 min left" is a wrong one.
    public static func minutes(characters: Int, charactersPerMinute: Double) -> Int? {
        guard characters > 0, charactersPerMinute > 0 else { return nil }
        let minutes = Int((Double(characters) / charactersPerMinute).rounded())
        return minutes >= 1 ? minutes : nil
    }

    /// `nil` when the length is unknown or the remainder rounds to nothing. Callers must show
    /// nothing at all in that case — a book the indexer has not reached must not claim to be
    /// finished, and a placeholder is just a slower way of saying the same wrong thing.
    public static func remaining(
        characters: Int?,
        progress: Double,
        charactersPerMinute: Double
    ) -> String? {
        guard let characters else { return nil }
        let left = Double(characters) * (1 - min(max(progress, 0), 1))
        guard let minutes = minutes(characters: Int(left), charactersPerMinute: charactersPerMinute) else {
            return nil
        }
        return "\(format(minutes: minutes)) left"
    }

    /// The whole length, for a source the reader has not started.
    public static func total(characters: Int?, charactersPerMinute: Double) -> String? {
        guard let characters,
              let minutes = minutes(characters: characters, charactersPerMinute: charactersPerMinute)
        else { return nil }
        return format(minutes: minutes)
    }

    /// `14 min`, `2 h 20 min`, `3 h`. Hours appear only once there are any, and the minute part
    /// is dropped when it is zero rather than printed as `3 h 0 min`.
    public static func format(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}

/// The same two answers, at the pace this reader actually reads that script at.
///
/// Every place in the interface that prints an estimate goes through these, so there is one
/// answer to "how fast does this person read" and not one per screen. `@MainActor` because
/// `ReadingSpeed.current` is — see the note there on why the pace is an ambient value rather
/// than something threaded through every row.
@MainActor
public extension ReadingEstimate {
    static func remaining(characters: Int?, progress: Double, script: ReaderScript) -> String? {
        remaining(
            characters: characters,
            progress: progress,
            charactersPerMinute: ReadingSpeed.current.rate(for: script)
        )
    }

    static func total(characters: Int?, script: ReaderScript) -> String? {
        total(characters: characters, charactersPerMinute: ReadingSpeed.current.rate(for: script))
    }
}
