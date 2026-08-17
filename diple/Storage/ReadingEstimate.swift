import Foundation

/// How long a book takes, and how much of it is left.
///
/// The single most useful thing an app can say about a text it is about to hand you, and diple
/// already stored everything needed for it: `bookContentIndex` knows how long each source is,
/// and `furthestProgress` knows how far the reader has got.
public enum ReadingEstimate {
    /// One constant for Latin, Cyrillic and Hangul alike, and that is a deliberate
    /// simplification rather than an oversight. Reading rates measured in *characters* differ
    /// enormously by script — a Hangul syllable block carries roughly as much as an English
    /// word — so a Korean book will read as longer than this claims. Three tuned constants
    /// would be three numbers nobody can check against their own reading, while one honest
    /// rough figure is wrong in a direction the reader can learn. If this is ever refined, it
    /// should be refined per book from observed reading speed, not per script from a table.
    static let averageCharactersPerWord = 6
    static let wordsPerMinute = 200

    /// `nil` for anything under half a minute: rounding a two-line article up to "1 min left"
    /// is a claim, and rounding it down to "0 min left" is a wrong one.
    public static func minutes(characters: Int) -> Int? {
        guard characters > 0 else { return nil }
        let words = Double(characters) / Double(averageCharactersPerWord)
        let minutes = Int((words / Double(wordsPerMinute)).rounded())
        return minutes >= 1 ? minutes : nil
    }

    /// `nil` when the length is unknown or the remainder rounds to nothing. Callers must show
    /// nothing at all in that case — a book the indexer has not reached must not claim to be
    /// finished, and a placeholder is just a slower way of saying the same wrong thing.
    public static func remaining(characters: Int?, progress: Double) -> String? {
        guard let characters else { return nil }
        let left = Double(characters) * (1 - min(max(progress, 0), 1))
        guard let minutes = minutes(characters: Int(left)) else { return nil }
        return "\(format(minutes: minutes)) left"
    }

    /// The whole length, for a source the reader has not started.
    public static func total(characters: Int?) -> String? {
        guard let characters, let minutes = minutes(characters: characters) else { return nil }
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
