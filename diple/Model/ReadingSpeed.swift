import Foundation

/// How fast this reader actually reads, measured from their own reading.
///
/// The app used to answer "how much is left?" from two constants — 200 words a minute at 6
/// characters a word — which is a statement about readers in general and therefore about
/// nobody. Someone who reads at 300 wpm was told a book was half again as long as it is, every
/// time, and the error never got smaller. The figure here is the same shape as the old
/// constant, characters a minute, but it is *this* reader's, taken from positions the navigator
/// already reports while they read.
///
/// **One figure per script, and that is the second half of the fix.** A Hangul syllable block
/// carries about as much as an English word, so the same person moves through Korean at a
/// fraction of the characters a minute they manage in Cyrillic — that was recorded in
/// CLAUDE.md as a known wrong answer for years. A single measured average over a mixed library
/// would not remove that error, it would spread it: both languages would be estimated from a
/// number that is right for neither. Two buckets cost two doubles.
///
/// It is not a preference, but it lives in `AppSettings` because that is what already syncs
/// field by field, and reading speed is a fact about the person rather than about the device —
/// the iPad should not have to learn it a second time.
public struct ReadingSpeed: Codable, Equatable {
    /// One script's figure, and how much reading stands behind it.
    public struct Pace: Codable, Equatable {
        /// Characters a minute.
        public var charactersPerMinute: Double
        /// Characters of measured reading folded into the figure above. This is what separates
        /// "one lucky page" from "a fortnight of evenings", and it is what the blend below
        /// leans on rather than a bare sample count.
        public var observedCharacters: Double

        public init(charactersPerMinute: Double, observedCharacters: Double) {
            self.charactersPerMinute = charactersPerMinute
            self.observedCharacters = observedCharacters
        }
    }

    /// Keyed by `ReaderScript.rawValue` rather than held in two named fields: a script that
    /// nobody has read in must be *absent*, not present at zero, and a dictionary says that
    /// without a second optional per bucket.
    private var paces: [String: Pace]

    public init(paces: [String: Pace] = [:]) {
        self.paces = paces
    }

    // MARK: - Constants

    /// 1200 characters a minute: 200 words at 6 characters each, the pair the app shipped with.
    /// Kept exactly, so a reader who has just installed diple sees what they saw yesterday and
    /// the number only moves once there is a reason for it to.
    static let latinDefault: Double = 1_200

    /// The starting figure for Hangul, kana and han, where 1200 was not a rough answer but a
    /// wrong one — off by roughly a factor of three in the direction that promises a Korean
    /// book is far shorter than it is. It is a midpoint of the range these scripts are read at
    /// and it is frankly approximate; unlike the old constant it is only a starting point, and
    /// a fortnight of real reading replaces it entirely.
    static let cjkDefault: Double = 500

    /// Measured fully displaces the default after this much observed reading — roughly twenty
    /// minutes. Below it the two are blended in proportion, so the estimate walks towards the
    /// truth over a first session instead of lurching the moment some threshold is crossed.
    static let trustedCharacters: Double = 20_000

    /// The figure is a moving average over about this much reading — a novel's worth. Without
    /// a ceiling on the evidence every later sample would weigh less than the one before it,
    /// and a reader who got faster, or moved from thrillers to philosophy, would be estimated
    /// from a habit they no longer have.
    static let windowCharacters: Double = 120_000

    /// A sample outside this band of the script's default is not someone reading. Below it lies
    /// a page left open while the kettle boils that the sampler failed to catch; above it lies
    /// skimming for a half-remembered passage. Neither is the pace at which this book will
    /// actually be finished, which is the only question the estimate answers.
    static let slowestPlausibleFactor: Double = 0.25
    static let fastestPlausibleFactor: Double = 3

    static func defaultRate(for script: ReaderScript) -> Double {
        switch script {
        case .latin: return latinDefault
        case .cjk: return cjkDefault
        }
    }

    // MARK: - Reading

    /// The rate to estimate with: the default until there is evidence, this reader's own once
    /// there is, and a proportional blend of the two in between.
    public func rate(for script: ReaderScript) -> Double {
        let base = Self.defaultRate(for: script)
        guard let pace = paces[script.rawValue], pace.observedCharacters > 0 else { return base }
        let confidence = min(pace.observedCharacters / Self.trustedCharacters, 1)
        return base * (1 - confidence) + pace.charactersPerMinute * confidence
    }

    /// What has been measured for a script, or `nil` where nothing has. For tests and for
    /// anything that needs to tell "no evidence" from "evidence that matches the default".
    public func measuredPace(for script: ReaderScript) -> Pace? {
        paces[script.rawValue]
    }

    // MARK: - Writing

    /// Folds one session of real reading into the figure.
    ///
    /// The weight a sample carries is its size against the evidence already held, so the first
    /// session all but sets the figure and the hundredth nudges it — which is the behaviour
    /// wanted at both ends. Because the evidence is capped at `windowCharacters`, the weight
    /// stops shrinking there and the average keeps following the reader instead of freezing.
    public mutating func record(characters: Double, seconds: Double, script: ReaderScript) {
        guard characters > 0, seconds > 0 else { return }
        let sampleRate = characters / (seconds / 60)
        let base = Self.defaultRate(for: script)
        guard sampleRate >= base * Self.slowestPlausibleFactor,
              sampleRate <= base * Self.fastestPlausibleFactor
        else { return }

        var pace = paces[script.rawValue] ?? Pace(charactersPerMinute: base, observedCharacters: 0)
        let weight = characters / (pace.observedCharacters + characters)
        pace.charactersPerMinute = pace.charactersPerMinute * (1 - weight) + sampleRate * weight
        pace.observedCharacters = min(pace.observedCharacters + characters, Self.windowCharacters)
        paces[script.rawValue] = pace
    }

    // MARK: - Ambient value

    /// The speed every estimate in the interface is printed with.
    ///
    /// A mirror of `AppSettings.readingSpeed`, kept in lockstep by `AppSettingsManager` for the
    /// same reason `DipleAccent.current` is: the readers are library rows and the reader's own
    /// bar, dozens of them, none of which has any other business with the settings object, and
    /// handing each one an `@ObservedObject` on a global would rebuild the whole library
    /// whenever any unrelated setting changed. `@MainActor` because that is where every reader
    /// and the one writer already are, so the actor is the synchronisation.
    @MainActor
    public static var current: ReadingSpeed = ReadingSpeed()
}
