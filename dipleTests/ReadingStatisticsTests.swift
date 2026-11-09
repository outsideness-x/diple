import XCTest
@testable import diple

/// Everything the statistics page prints comes out of `ReadingStatistics.make`, so it is tested
/// with rows and a fixed calendar rather than by opening the page against a real library.
final class ReadingStatisticsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow") ?? .gmt
        calendar.firstWeekday = 2 // Monday
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func sitting(_ book: String, from start: Date, minutes: Double, characters: Double = 9_000) -> ReadingSession {
        ReadingSession(
            bookId: book,
            startedAt: start,
            endedAt: start.addingTimeInterval(minutes * 60),
            characters: characters,
            seconds: minutes * 60
        )
    }

    private func book(
        _ id: String,
        _ title: String,
        progress: Double = 0.3,
        lastOpenedAt: Date? = nil,
        coverPath: String? = nil
    ) -> Book {
        Book(
            id: id,
            title: title,
            author: "Author of \(title)",
            filePath: "Books/\(id)/book.epub",
            coverPath: coverPath,
            addedAt: date(2025, 1, 1),
            lastOpenedAt: lastOpenedAt,
            progress: progress
        )
    }

    private func make(
        _ sessions: [ReadingSession],
        books: [Book] = [],
        remembered: [ReadingLogSource] = [],
        year: Int? = nil
    ) -> ReadingStatistics {
        ReadingStatistics.make(
            sessions: sessions,
            books: books,
            remembered: remembered,
            year: year,
            calendar: calendar,
            now: date(2026, 11, 9)
        )
    }

    func testNothingReadIsEmptyAndDescribesThisYear() {
        let stats = make([])
        XCTAssertTrue(stats.isEmpty)
        XCTAssertEqual(stats.year, 2026)
        XCTAssertTrue(stats.years.isEmpty)
        XCTAssertNil(stats.averageSittingMinutes)
        XCTAssertNil(stats.pagesPerHour)
        XCTAssertNil(stats.fullestDay)
    }

    /// A year's figures are that year's: a sitting from last December is not this year's hour.
    func testFiguresBelongToTheChosenYear() {
        let sessions = [
            sitting("dune", from: date(2025, 12, 20, 21), minutes: 90),
            sitting("dune", from: date(2026, 10, 1, 21), minutes: 30),
            sitting("dune", from: date(2026, 10, 2, 21), minutes: 30),
        ]

        let thisYear = make(sessions, books: [book("dune", "Дюна")])
        XCTAssertEqual(thisYear.year, 2026)
        XCTAssertEqual(thisYear.years, [2026, 2025])
        XCTAssertEqual(thisYear.totalMinutes, 60)
        XCTAssertEqual(thisYear.sittingCount, 2)
        XCTAssertEqual(thisYear.readingDayCount, 2)
        XCTAssertEqual(thisYear.averageSittingMinutes, 30)

        let lastYear = make(sessions, books: [book("dune", "Дюна")], year: 2025)
        XCTAssertEqual(lastYear.totalMinutes, 90)
        XCTAssertEqual(lastYear.sittingCount, 1)
    }

    /// The ledger's rule: a sitting belongs to the day it ended on, so a dot on the page and a
    /// line in the journal agree about a late night.
    func testASittingBelongsToTheDayItEndedOn() {
        let stats = make([sitting("dune", from: date(2026, 10, 1, 23, 30), minutes: 60)])

        XCTAssertEqual(stats.days.map(\.date), [calendar.startOfDay(for: date(2026, 10, 2))])
        XCTAssertNotNil(stats.day(on: date(2026, 10, 2, 9), calendar: calendar))
        XCTAssertNil(stats.day(on: date(2026, 10, 1, 9), calendar: calendar))
        // …while the hour is the hour it began, which is when the reader sat down.
        XCTAssertEqual(stats.hoursOfDay[23], 3_600)
    }

    func testTheFullestDayIsTheLongest() {
        let stats = make([
            sitting("dune", from: date(2026, 10, 1, 9), minutes: 20),
            sitting("dune", from: date(2026, 10, 3, 9), minutes: 70),
            sitting("dune", from: date(2026, 10, 3, 20), minutes: 10),
            sitting("dune", from: date(2026, 10, 5, 9), minutes: 40),
        ])

        XCTAssertEqual(stats.fullestDay?.date, calendar.startOfDay(for: date(2026, 10, 3)))
        XCTAssertEqual(stats.fullestDay?.minutes, 80)
        XCTAssertEqual(stats.longestSitting?.minutes, 70)
    }

    /// Sources longest first; a deleted one is printed under the title and cover the log kept.
    func testSourcesRunLongestFirstAndADeletedOneKeepsItsNameAndCover() {
        let stats = make(
            [
                sitting("dune", from: date(2026, 10, 1, 9), minutes: 20),
                sitting("gone", from: date(2026, 10, 2, 9), minutes: 50),
                sitting("lost", from: date(2026, 10, 3, 9), minutes: 5),
            ],
            books: [book("dune", "Дюна", coverPath: "Books/dune/cover.png")],
            remembered: [ReadingLogSource(bookId: "gone", title: "Dracula", author: "Bram Stoker", coverPath: "Covers/gone.jpg")]
        )

        XCTAssertEqual(stats.sources.map(\.source.title), ["Dracula", "Дюна", ReadingStatistics.unknownTitle])
        XCTAssertEqual(stats.sources[0].source.coverPath, "Covers/gone.jpg")
        XCTAssertFalse(stats.sources[0].source.isOnShelf)
        XCTAssertEqual(stats.sources[1].source.coverPath, "Books/dune/cover.png")
        XCTAssertTrue(stats.sources[1].source.isOnShelf)
        XCTAssertEqual(stats.longestSitting?.title, "Dracula")
    }

    /// A recorded finish is the moment the reader said so, and stays true after the position
    /// falls back below the end on a reread.
    func testARecordedFinishWinsOverThePosition() {
        let finish = date(2026, 3, 14)
        let stats = make(
            [],
            books: [book("dune", "Дюна", progress: 0.1, lastOpenedAt: date(2026, 11, 1))],
            remembered: [ReadingLogSource(bookId: "dune", title: "Дюна", finishedAt: finish)]
        )

        XCTAssertEqual(stats.finished.map(\.title), ["Дюна"])
        XCTAssertEqual(stats.finished.first?.finishedAt, finish)
        XCTAssertFalse(stats.isEmpty)
    }

    /// A book finished before finishes were recorded is dated by its last opening.
    func testAnUnrecordedFinishIsDatedByTheLastOpening() {
        let stats = make([], books: [book("dune", "Дюна", progress: 1, lastOpenedAt: date(2026, 6, 2))])

        XCTAssertEqual(stats.finished.first?.finishedAt, date(2026, 6, 2))
    }

    /// The shelf of the year: only that year's finishes, in the order they were finished, and a
    /// deleted book among them.
    func testTheShelfHoldsTheYearsFinishesInOrder() {
        let stats = make(
            [],
            books: [
                book("late", "Late", progress: 1, lastOpenedAt: date(2026, 9, 1)),
                book("early", "Early", progress: 1, lastOpenedAt: date(2026, 2, 1)),
                book("old", "Old", progress: 1, lastOpenedAt: date(2025, 8, 1)),
                book("open", "Unfinished", progress: 0.5, lastOpenedAt: date(2026, 5, 1)),
            ],
            remembered: [ReadingLogSource(bookId: "gone", title: "Gone", finishedAt: date(2026, 4, 1))]
        )

        XCTAssertEqual(stats.finished.map(\.title), ["Early", "Gone", "Late"])
        XCTAssertEqual(stats.years, [2026, 2025])

        let lastYear = make(
            [],
            books: [book("old", "Old", progress: 1, lastOpenedAt: date(2025, 8, 1))],
            year: 2025
        )
        XCTAssertEqual(lastYear.finished.map(\.title), ["Old"])
    }

    /// The week starts where the reader's calendar starts it.
    func testWeekdaysStartOnTheCalendarsFirstDay() {
        // 2026-11-09 is a Monday, 2026-11-08 a Sunday.
        let stats = make([
            sitting("dune", from: date(2026, 11, 9, 9), minutes: 10),
            sitting("dune", from: date(2026, 11, 8, 9), minutes: 30),
        ])

        XCTAssertEqual(stats.firstWeekday, 2)
        XCTAssertEqual(stats.weekdays[0], 600)
        XCTAssertEqual(stats.weekdays[6], 1_800)
    }

    /// Fewer than eight sittings do not describe a habit, and the page says nothing of one.
    func testAThinYearClaimsNoHabit() {
        let few = (0 ..< 7).map { sitting("dune", from: date(2026, 10, $0 + 1, 22), minutes: 20) }
        XCTAssertNil(make(few).settledHour)
        XCTAssertNil(make(few).settledWeekdayIndex)

        let enough = few + [sitting("dune", from: date(2026, 10, 20, 22), minutes: 20)]
        XCTAssertEqual(make(enough).settledHour, 22)
        XCTAssertNotNil(make(enough).settledWeekdayIndex)
    }

    /// Pages are the standard typescript page of 1,800 characters.
    func testPagesAndPaceAreCountedInStandardPages() {
        let stats = make([
            sitting("dune", from: date(2026, 10, 1, 9), minutes: 60, characters: 90_000),
        ])

        XCTAssertEqual(stats.pages, 50)
        XCTAssertEqual(stats.pagesPerHour, 50)
    }

    func testAPaceIsNotClaimedFromAFewMinutes() {
        let stats = make([sitting("dune", from: date(2026, 10, 1, 9), minutes: 5, characters: 9_000)])
        XCTAssertNil(stats.pagesPerHour)
    }
}
