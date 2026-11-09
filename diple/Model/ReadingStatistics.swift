import Foundation

/// A year of reading, arranged for the page that prints it.
///
/// A pure function over the sittings, the shelf and the log's memory of deleted sources, for the
/// reason `ReadingLog` and `MarginaliaBoard` record about themselves: inside an
/// `ObservableObject` it could only be checked by running the app against a real library, and
/// this app does not write fixtures. Everything `ReadingStatisticsView` prints comes out of
/// `make(...)`.
///
/// **Facts, not a scoreboard.** The ledger's rule holds here too: no streak, no goal, no badge,
/// no comparison with last year. Every figure is something that happened — time measured by
/// `ReadingSpeedSampler`, books finished, the hours a reader sits down in — and none of them is
/// a grade. A year with three sittings prints three sittings and says nothing about a habit.
public nonisolated struct ReadingStatistics: Equatable, Sendable {
    /// A source as the statistics know it: the live book while it is on the shelf, the log's
    /// memory of it once it is not (`ReadingLogSource`). Its cover is whichever of the two
    /// still exists, so a deleted book keeps its artwork on the page.
    public struct Source: Identifiable, Equatable, Hashable, Sendable {
        public let id: String
        public let title: String
        public let author: String?
        public let coverPath: String?
        /// When it was finished, if it ever was. See `finishDate(for:remembered:lastSitting:)`.
        public let finishedAt: Date?
        public let isOnShelf: Bool
    }

    /// Time spent with one source over the year.
    public struct SourceTime: Identifiable, Equatable, Sendable {
        public let source: Source
        public let seconds: Double
        public let sittings: Int

        public var id: String { source.id }
        public var minutes: Int { Int((seconds / 60).rounded()) }
    }

    /// One day of the year that has reading in it.
    public struct Day: Identifiable, Equatable, Sendable {
        public let date: Date
        public let seconds: Double
        /// What the day went on, longest first.
        public let sources: [SourceTime]

        public var id: Date { date }
        public var minutes: Int { Int((seconds / 60).rounded()) }
    }

    public struct Sitting: Equatable, Sendable {
        public let seconds: Double
        public let date: Date
        public let title: String

        public var minutes: Int { Int((seconds / 60).rounded()) }
    }

    /// The year this describes.
    public let year: Int
    /// Every year with a sitting or a finish in it, newest first.
    public let years: [Int]
    /// The first sitting ever recorded, in any year. The log begins the day it begins, and a
    /// page that does not say so reads a short year as an idle one.
    public let recordedSince: Date?
    /// The days of `year` with reading in them, oldest first.
    public let days: [Day]
    public let totalSeconds: Double
    public let totalCharacters: Double
    public let sittingCount: Int
    /// Every source read in the year, longest first.
    public let sources: [SourceTime]
    /// Every source finished in the year, in the order it was finished — a shelf of the year is
    /// read left to right the way the year went.
    public let finished: [Source]
    /// Seconds by the hour a sitting began, 0…23 — the question is when a reader sits down.
    public let hoursOfDay: [Double]
    /// Seconds by the weekday a sitting ended on, starting from the calendar's first weekday.
    public let weekdays: [Double]
    /// The calendar's `weekday` value (1 = Sunday) of `weekdays[0]`.
    public let firstWeekday: Int
    public let longestSitting: Sitting?

    // MARK: - Derived figures

    public var totalMinutes: Int { Int((totalSeconds / 60).rounded()) }

    public var readingDayCount: Int { days.count }

    /// Nothing to print for the year: no sitting and no finish.
    public var isEmpty: Bool { days.isEmpty && finished.isEmpty }

    public var averageSittingMinutes: Int? {
        guard sittingCount > 0 else { return nil }
        return Int((totalSeconds / Double(sittingCount) / 60).rounded())
    }

    /// Characters in a page. 1 800 is the standard typescript page — the "Normseite" a
    /// translator is paid by, and the «стандартная страница» of a Russian editor — chosen
    /// because it is a convention a reader can look up rather than a number made up here. A
    /// book's own pages are no use: a reflowed EPUB has none, and two editions of one novel
    /// disagree by hundreds.
    public static let charactersPerPage: Double = 1_800

    public var pages: Int { Int((totalCharacters / Self.charactersPerPage).rounded()) }

    /// Pages an hour, at the same page. `nil` under ten minutes of reading, where a rate is noise.
    public var pagesPerHour: Int? {
        guard totalSeconds >= 600 else { return nil }
        return Int((Double(pages) / (totalSeconds / 3600)).rounded())
    }

    /// The busiest hour, when the year has enough sittings to have a shape. Eight, the
    /// ledger's own threshold: three sittings do not describe a habit.
    public var settledHour: Int? {
        guard sittingCount >= ReadingStatistics.habitThreshold else { return nil }
        guard let best = hoursOfDay.enumerated().max(by: { $0.element < $1.element }),
              best.element > 0
        else { return nil }
        return best.offset
    }

    /// The index into `weekdays` of the busiest one, under the same threshold.
    public var settledWeekdayIndex: Int? {
        guard sittingCount >= ReadingStatistics.habitThreshold else { return nil }
        guard let best = weekdays.enumerated().max(by: { $0.element < $1.element }),
              best.element > 0
        else { return nil }
        return best.offset
    }

    public static let habitThreshold = 8

    /// The day with the most reading in it.
    public var fullestDay: Day? {
        days.max { ($0.seconds, $1.date) < ($1.seconds, $0.date) }
    }

    public func day(on date: Date, calendar: Calendar = .current) -> Day? {
        let start = calendar.startOfDay(for: date)
        return days.first { $0.date == start }
    }

    // MARK: - Finishing

    /// When a source was finished, or `nil` if it was not.
    ///
    /// A recorded `finishedAt` wins: it is the moment the reader said so, and it stays true when
    /// the book is reread from the start and its position falls back below the end. A book
    /// finished before finishes were recorded is dated by inference.
    public static func finishDate(for book: Book, remembered: ReadingLogSource?, lastSitting: Date?) -> Date? {
        if let recorded = remembered?.finishedAt { return recorded }
        guard book.progress >= 0.995 else { return nil }
        return ReadingLogSource.inferredFinishDate(of: book, lastSitting: lastSitting)
    }

    // MARK: - Building

    /// The fallback title for a sitting whose book was deleted before the log kept titles.
    public static let unknownTitle = "A source no longer in the library"

    public static func make(
        sessions: [ReadingSession],
        books: [Book],
        remembered: [ReadingLogSource],
        year requestedYear: Int? = nil,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> ReadingStatistics {
        let rememberedByID = Dictionary(remembered.map { ($0.bookId, $0) }, uniquingKeysWith: { first, _ in first })
        let booksByID = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let lastSittingByBook = sessions.reduce(into: [String: Date]()) { result, session in
            result[session.bookId] = max(result[session.bookId] ?? .distantPast, session.endedAt)
        }

        func source(for id: String) -> Source {
            if let book = booksByID[id] {
                return Source(
                    id: id,
                    title: book.title,
                    author: book.author,
                    // The book's own cover while it lives; the kept one if, somehow, the row
                    // has none and the log does.
                    coverPath: book.coverPath ?? rememberedByID[id]?.coverPath,
                    finishedAt: finishDate(for: book, remembered: rememberedByID[id], lastSitting: lastSittingByBook[id]),
                    isOnShelf: true
                )
            }
            if let kept = rememberedByID[id] {
                return Source(
                    id: id,
                    title: kept.title,
                    author: kept.author,
                    coverPath: kept.coverPath,
                    finishedAt: kept.finishedAt,
                    isOnShelf: false
                )
            }
            return Source(id: id, title: unknownTitle, author: nil, coverPath: nil, finishedAt: nil, isOnShelf: false)
        }

        // Every source that was ever finished — on the shelf or only remembered.
        let finishedSources = Set(booksByID.keys).union(rememberedByID.keys)
            .map(source(for:))
            .filter { $0.finishedAt != nil }

        let yearOf: (Date) -> Int = { calendar.component(.year, from: $0) }
        // A sitting belongs to the day it **ended** on — the ledger's rule, so a dot on the page
        // and a line in the ledger never disagree about which day a late sitting was.
        let years = Set(sessions.map { yearOf($0.endedAt) })
            .union(finishedSources.compactMap { $0.finishedAt.map(yearOf) })
            .sorted(by: >)

        let currentYear = yearOf(now)
        let year = requestedYear
            ?? (years.contains(currentYear) ? currentYear : (years.first ?? currentYear))

        let ofYear = sessions.filter { yearOf($0.endedAt) == year }

        var hours = [Double](repeating: 0, count: 24)
        var weekdays = [Double](repeating: 0, count: 7)
        let firstWeekday = calendar.firstWeekday
        for session in ofYear {
            let hour = calendar.component(.hour, from: session.startedAt)
            if hours.indices.contains(hour) { hours[hour] += session.seconds }
            let weekday = calendar.component(.weekday, from: session.endedAt)
            let index = (weekday - firstWeekday + 7) % 7
            if weekdays.indices.contains(index) { weekdays[index] += session.seconds }
        }

        func times(of group: [ReadingSession]) -> [SourceTime] {
            Dictionary(grouping: group, by: \.bookId)
                .map { id, sittings in
                    SourceTime(
                        source: source(for: id),
                        seconds: sittings.reduce(0) { $0 + $1.seconds },
                        sittings: sittings.count
                    )
                }
                // Longest first, and the title breaks a tie so the order is stable.
                .sorted { ($0.seconds, $1.source.title) > ($1.seconds, $0.source.title) }
        }

        let days = Dictionary(grouping: ofYear) { calendar.startOfDay(for: $0.endedAt) }
            .map { date, sittings in
                Day(
                    date: date,
                    seconds: sittings.reduce(0) { $0 + $1.seconds },
                    sources: times(of: sittings)
                )
            }
            .sorted { $0.date < $1.date }

        let longest = ofYear.max { $0.seconds < $1.seconds }.map {
            Sitting(seconds: $0.seconds, date: $0.endedAt, title: source(for: $0.bookId).title)
        }

        let finished = finishedSources
            .filter { $0.finishedAt.map(yearOf) == year }
            .sorted { ($0.finishedAt ?? .distantPast, $0.title) < ($1.finishedAt ?? .distantPast, $1.title) }

        return ReadingStatistics(
            year: year,
            years: years,
            recordedSince: sessions.map(\.startedAt).min(),
            days: days,
            totalSeconds: ofYear.reduce(0) { $0 + $1.seconds },
            totalCharacters: ofYear.reduce(0) { $0 + $1.characters },
            sittingCount: ofYear.count,
            sources: times(of: ofYear),
            finished: finished,
            hoursOfDay: hours,
            weekdays: weekdays,
            firstWeekday: firstWeekday,
            longestSitting: longest
        )
    }
}
