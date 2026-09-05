import XCTest
@testable import diple

@MainActor
final class DailyQuoteWidgetTests: XCTestCase {
    private func quote(_ id: String, day: Int) -> Highlight {
        Highlight(
            id: id,
            bookId: "book",
            locator: "",
            text: "Passage \(id)",
            createdAt: Date(timeIntervalSince1970: TimeInterval(day) * 86_400),
            bookTitle: "A Book",
            bookAuthor: "An Author"
        )
    }

    /// The promise the widget makes: what the Lock Screen shows on a given day is what Home
    /// will show when it is opened on that day. Both come from `candidate(for:from:)`, so the
    /// test is that the snapshot really is that function applied a fortnight forward.
    func testEachDayInTheSnapshotIsTheDayTheAppWouldHaveChosen() {
        let quotes = (1...5).map { quote("q\($0)", day: $0) }
        let now = Date(timeIntervalSince1970: 1_000 * 86_400)

        let entries = DailyResurfacingService.entries(
            from: quotes,
            startingAt: now,
            pinnedQuoteID: nil,
            horizon: 5
        )
        XCTAssertEqual(entries.count, 5)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        for (offset, entry) in entries.enumerated() {
            let midnight = try? XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)))
            let day = offset == 0 ? now : (midnight ?? now)
            let expected = DailyResurfacingService.candidate(for: day, from: quotes)
            XCTAssertEqual(entry.quoteID, expected?.id, "day \(offset) must match what the app would pick")
            XCTAssertEqual(entry.day, DailyQuoteDay.key(for: day))
        }
    }

    /// "Another" moves today's passage, and today is what the widget is showing. A pinned id
    /// wins for day zero and for day zero only — tomorrow is still the rule's answer.
    func testAPinnedQuoteWinsTodayAndOnlyToday() {
        let quotes = (1...5).map { quote("q\($0)", day: $0) }
        let now = Date(timeIntervalSince1970: 1_000 * 86_400)

        let entries = DailyResurfacingService.entries(
            from: quotes,
            startingAt: now,
            pinnedQuoteID: "q4",
            horizon: 3
        )
        XCTAssertEqual(entries.first?.quoteID, "q4")

        let unpinned = DailyResurfacingService.entries(
            from: quotes,
            startingAt: now,
            pinnedQuoteID: nil,
            horizon: 3
        )
        XCTAssertEqual(
            Array(entries.dropFirst()).map(\.quoteID),
            Array(unpinned.dropFirst()).map(\.quoteID)
        )
    }

    /// A pinned id that is no longer in the library — the passage was deleted on another
    /// device between the pick and the refresh — falls back to the rule rather than to nothing.
    func testAPinnedQuoteThatIsGoneFallsBackToTheRule() {
        let quotes = (1...3).map { quote("q\($0)", day: $0) }
        let now = Date(timeIntervalSince1970: 1_000 * 86_400)
        let entries = DailyResurfacingService.entries(
            from: quotes,
            startingAt: now,
            pinnedQuoteID: "deleted-elsewhere",
            horizon: 1
        )
        XCTAssertEqual(entries.first?.quoteID, DailyResurfacingService.candidate(for: now, from: quotes)?.id)
    }

    func testTheSnapshotSurvivesTheTripThroughDiskAndAnswersByDay() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("diple-snapshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = DailyQuoteSnapshotStore(directoryURL: directory)
        XCTAssertNil(store.read(), "a fresh install has no file, and that is not an error")

        let now = Date(timeIntervalSince1970: 1_000 * 86_400)
        let snapshot = DailyQuoteSnapshot(
            generatedAt: now,
            entries: DailyResurfacingService.entries(
                from: (1...3).map { quote("q\($0)", day: $0) },
                startingAt: now,
                pinnedQuoteID: nil,
                horizon: 3
            ),
            totalQuoteCount: 3
        )
        try store.write(snapshot)

        let read = try XCTUnwrap(store.read())
        XCTAssertEqual(read, snapshot)
        XCTAssertEqual(read.entry(for: DailyQuoteDay.key(for: now))?.quoteID, snapshot.entries.first?.quoteID)
        XCTAssertNil(read.entry(for: "1999-01-01"))

        store.clear()
        XCTAssertNil(store.read())
    }

    /// The day key is a key, not a date anybody reads, so it must not move with the reader's
    /// calendar preference — but it must move with their time zone, because the day a passage
    /// belongs to is their day.
    func testTheDayKeyIsStableAcrossCalendarsAndFollowsTheTimeZone() {
        let instant = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(DailyQuoteDay.key(for: instant, timeZone: TimeZone(identifier: "UTC")!), "2023-11-14")
        XCTAssertEqual(DailyQuoteDay.key(for: instant, timeZone: TimeZone(identifier: "Asia/Seoul")!), "2023-11-15")

        let midnight = DailyQuoteDay.startOfNextDay(after: instant, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(DailyQuoteDay.key(for: midnight, timeZone: TimeZone(identifier: "UTC")!), "2023-11-15")
    }
}
