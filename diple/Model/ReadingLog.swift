import Foundation

/// The sittings, arranged the way a ledger is read.
///
/// A pure function over the rows, for the reason `MarginaliaBoard` records about itself: inside
/// an `ObservableObject` the grouping could only be checked by running the app against a real
/// library, and this app does not write fixtures. Everything the screen prints comes out of
/// `make(from:titles:calendar:)`, so all of it is checkable with a handful of rows and a fixed
/// calendar.
public struct ReadingLog: Equatable {
    /// One book, on one day. Sittings with the same book on the same day are summed: a reader
    /// who picked a book up three times between breakfast and midnight had one day with that
    /// book, and a ledger printing the same title three times under one date is a log file.
    public struct Entry: Identifiable, Equatable {
        public let bookId: String
        public let title: String
        public let seconds: Double
        public let characters: Double
        /// How many separate times it was picked up. Printed only when it is more than one,
        /// because "1 sitting" is a fact about the format rather than about the day.
        public let sittings: Int

        public var id: String { bookId }
        public var minutes: Int { Int((seconds / 60).rounded()) }
    }

    public struct Day: Identifiable, Equatable {
        public let date: Date
        public let entries: [Entry]

        public var id: Date { date }
        public var seconds: Double { entries.reduce(0) { $0 + $1.seconds } }
        public var minutes: Int { Int((seconds / 60).rounded()) }
    }

    public struct Month: Identifiable, Equatable {
        public let date: Date
        public let days: [Day]

        public var id: Date { date }
        public var seconds: Double { days.reduce(0) { $0 + $1.seconds } }
        public var minutes: Int { Int((seconds / 60).rounded()) }
        public var sittingCount: Int { days.reduce(0) { $0 + $1.entries.reduce(0) { $0 + $1.sittings } } }
        public var bookCount: Int { Set(days.flatMap { $0.entries.map(\.bookId) }).count }
    }

    /// Newest month first, and newest day first inside it — the ledger is read from the end,
    /// which is where the reader is.
    public let months: [Month]
    /// Seconds read in each hour of the day, 0…23, over the whole log. Attributed to the hour a
    /// sitting **began**: the question this answers is when a reader sits down with a book, and
    /// a session split across midnight is one decision, not two.
    public let hoursOfDay: [Double]
    public let totalSeconds: Double
    public let totalCharacters: Double
    public let sittingCount: Int
    public let bookCount: Int

    public var totalMinutes: Int { Int((totalSeconds / 60).rounded()) }

    public var isEmpty: Bool { months.isEmpty }

    /// The busiest hour, when one stands out. `nil` for a log too thin to have a shape — three
    /// sittings do not describe a habit, and a screen that announced one from them would be
    /// making it up.
    public var settledHour: Int? {
        guard sittingCount >= 8 else { return nil }
        guard let best = hoursOfDay.enumerated().max(by: { $0.element < $1.element }),
              best.element > 0
        else { return nil }
        return best.offset
    }

    public static func make(
        from sessions: [ReadingSession],
        titles: [String: String],
        calendar: Calendar = .current
    ) -> ReadingLog {
        guard !sessions.isEmpty else {
            return ReadingLog(
                months: [],
                hoursOfDay: Array(repeating: 0, count: 24),
                totalSeconds: 0,
                totalCharacters: 0,
                sittingCount: 0,
                bookCount: 0
            )
        }

        var hours = [Double](repeating: 0, count: 24)
        for session in sessions {
            let hour = calendar.component(.hour, from: session.startedAt)
            guard hours.indices.contains(hour) else { continue }
            hours[hour] += session.seconds
        }

        // A sitting belongs to the day it **ended** on, which is the day the reader would say
        // they read: someone who starts at half past eleven and reads until one has read
        // tonight, not yesterday.
        let byDay = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.endedAt) }

        let days: [Day] = byDay
            .map { date, sessionsOfDay in
                let byBook = Dictionary(grouping: sessionsOfDay, by: \.bookId)
                let entries = byBook
                    .map { bookId, sessionsOfBook -> Entry in
                        Entry(
                            bookId: bookId,
                            // A book deleted since is still something that was read, and the
                            // log is a record of what happened rather than of what is on the
                            // shelf now.
                            title: titles[bookId] ?? "A source no longer in the library",
                            seconds: sessionsOfBook.reduce(0) { $0 + $1.seconds },
                            characters: sessionsOfBook.reduce(0) { $0 + $1.characters },
                            sittings: sessionsOfBook.count
                        )
                    }
                    // Longest first: the day is described by what most of it was spent on.
                    .sorted { ($0.seconds, $0.title) > ($1.seconds, $1.title) }

                return Day(date: date, entries: entries)
            }
            .sorted { $0.date > $1.date }

        let byMonth = Dictionary(grouping: days) { day -> Date in
            let parts = calendar.dateComponents([.year, .month], from: day.date)
            return calendar.date(from: parts) ?? day.date
        }

        let months = byMonth
            .map { Month(date: $0.key, days: $0.value) }
            .sorted { $0.date > $1.date }

        return ReadingLog(
            months: months,
            hoursOfDay: hours,
            totalSeconds: sessions.reduce(0) { $0 + $1.seconds },
            totalCharacters: sessions.reduce(0) { $0 + $1.characters },
            sittingCount: sessions.count,
            bookCount: Set(sessions.map(\.bookId)).count
        )
    }
}
