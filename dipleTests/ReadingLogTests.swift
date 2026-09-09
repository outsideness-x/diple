import XCTest
@testable import diple

/// The grouping is the whole of what the ledger prints, so it is tested with rows and a fixed
/// calendar rather than by opening the screen against a real library.
final class ReadingLogTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow") ?? .gmt
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func session(
        book: String,
        from start: Date,
        minutes: Double,
        characters: Double = 4000
    ) -> ReadingSession {
        ReadingSession(
            bookId: book,
            startedAt: start,
            endedAt: start.addingTimeInterval(minutes * 60),
            characters: characters,
            seconds: minutes * 60
        )
    }

    private let titles = ["dune": "Дюна", "carnival": "The Carnival of the Animals"]

    func testAnEmptyLogIsEmpty() {
        let log = ReadingLog.make(from: [], titles: [:], calendar: calendar)
        XCTAssertTrue(log.isEmpty)
        XCTAssertEqual(log.totalMinutes, 0)
        XCTAssertNil(log.settledHour)
    }

    /// The same book picked up three times in a day is one line in the ledger, with the day's
    /// total on it — a log file prints three.
    func testSittingsWithOneBookOnOneDayBecomeOneEntry() {
        let log = ReadingLog.make(
            from: [
                session(book: "dune", from: date(2026, 9, 9, 8), minutes: 10),
                session(book: "dune", from: date(2026, 9, 9, 13), minutes: 20),
                session(book: "dune", from: date(2026, 9, 9, 22), minutes: 30),
            ],
            titles: titles,
            calendar: calendar
        )

        XCTAssertEqual(log.months.count, 1)
        XCTAssertEqual(log.months[0].days.count, 1)
        let entries = log.months[0].days[0].entries
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].title, "Дюна")
        XCTAssertEqual(entries[0].sittings, 3)
        XCTAssertEqual(entries[0].minutes, 60)
        XCTAssertEqual(log.sittingCount, 3)
        XCTAssertEqual(log.bookCount, 1)
    }

    func testTheDayIsDescribedByWhatMostOfItWentOn() {
        let log = ReadingLog.make(
            from: [
                session(book: "carnival", from: date(2026, 9, 9, 9), minutes: 12),
                session(book: "dune", from: date(2026, 9, 9, 21), minutes: 48),
            ],
            titles: titles,
            calendar: calendar
        )

        XCTAssertEqual(log.months[0].days[0].entries.map(\.title), ["Дюна", "The Carnival of the Animals"])
    }

    /// The ledger is read from the end, which is where the reader is.
    func testMonthsAndDaysRunNewestFirst() {
        let log = ReadingLog.make(
            from: [
                session(book: "dune", from: date(2026, 7, 4, 20), minutes: 15),
                session(book: "dune", from: date(2026, 9, 1, 20), minutes: 15),
                session(book: "dune", from: date(2026, 9, 9, 20), minutes: 15),
            ],
            titles: titles,
            calendar: calendar
        )

        XCTAssertEqual(log.months.count, 2)
        XCTAssertEqual(calendar.component(.month, from: log.months[0].date), 9)
        XCTAssertEqual(calendar.component(.month, from: log.months[1].date), 7)
        XCTAssertEqual(log.months[0].days.map { calendar.component(.day, from: $0.date) }, [9, 1])
    }

    /// Someone who starts at half past eleven and reads until one has read *tonight*.
    func testASittingBelongsToTheDayItEndedOn() {
        let log = ReadingLog.make(
            from: [session(book: "dune", from: date(2026, 9, 9, 23, 30), minutes: 90)],
            titles: titles,
            calendar: calendar
        )

        XCTAssertEqual(calendar.component(.day, from: log.months[0].days[0].date), 10)
    }

    /// The hour strip answers when a reader *sits down*, so the seconds go to the hour the
    /// sitting began in — one decision, not two.
    func testHoursAreAttributedToTheHourTheSittingBegan() {
        let log = ReadingLog.make(
            from: [session(book: "dune", from: date(2026, 9, 9, 23, 30), minutes: 90)],
            titles: titles,
            calendar: calendar
        )

        XCTAssertEqual(log.hoursOfDay[23], 90 * 60)
        XCTAssertEqual(log.hoursOfDay[0], 0)
    }

    /// Three sittings do not describe a habit, and a screen that announced one from them would
    /// be making it up.
    func testAThinLogClaimsNoHabit() {
        let thin = ReadingLog.make(
            from: (0 ..< 3).map { session(book: "dune", from: date(2026, 9, 1 + $0, 21), minutes: 20) },
            titles: titles,
            calendar: calendar
        )
        XCTAssertNil(thin.settledHour)

        let settled = ReadingLog.make(
            from: (0 ..< 10).map { session(book: "dune", from: date(2026, 9, 1 + $0, 21), minutes: 20) },
            titles: titles,
            calendar: calendar
        )
        XCTAssertEqual(settled.settledHour, 21)
    }

    /// A book deleted since is still something that was read.
    func testASittingWithABookNoLongerInTheLibraryKeepsItsLine() {
        let log = ReadingLog.make(
            from: [session(book: "gone", from: date(2026, 9, 9, 20), minutes: 25)],
            titles: titles,
            calendar: calendar
        )

        XCTAssertEqual(log.months[0].days[0].entries.count, 1)
        XCTAssertEqual(log.months[0].days[0].entries[0].minutes, 25)
    }
}
