import XCTest
@testable import diple

/// What the notes widget is told: the Desk's own numbers, and today's page in words.
final class NotesWidgetSnapshotTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_789_300_800) // 2026-09-13 12:00 UTC
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func item(_ id: String, body: String, space: String? = nil, book: String? = nil, daily: String? = nil,
                      created: TimeInterval = 0) -> NoteItem {
        NoteItem(
            note: Note(id: id, body: body, bookId: book, createdAt: now.addingTimeInterval(created), spaceId: space, dailyDate: daily),
            tags: [],
            book: nil
        )
    }

    func testTheCountsAreTheDesksCounts() {
        let space = NoteSpace(id: "s1", name: "diple", symbol: "lightbulb", sortIndex: 1, createdAt: now, updatedAt: now)
        let items = [
            item("inbox-1", body: "- [ ] Call the printer\n- [x] Order paper"),
            item("inbox-2", body: "A thought"),
            item("filed", body: "- [ ] Ship", space: "s1"),
            item("orphan", body: "Filed in a space that has not arrived", space: "missing"),
            item("from-book", body: "About the book", book: "b1")
        ]
        let snapshot = NotesWidgetSnapshot.make(items: items, spaces: [space], now: now, calendar: calendar)
        XCTAssertEqual(snapshot.inboxCount, NotesDesk.inbox(items, spaces: [space]).count)
        XCTAssertEqual(snapshot.inboxCount, 3)
        XCTAssertEqual(snapshot.openTaskCount, 2)
        XCTAssertNil(snapshot.today)
    }

    func testTodaysPageArrivesAsWordsAndOnlyForToday() {
        let key = Note.dailyKey(for: now, calendar: calendar)
        let page = item("day", body: "## Morning\n\n- [ ] **Call** the printer\n\nПоля — это разговор.", daily: key)
        let snapshot = NotesWidgetSnapshot.make(items: [page], spaces: [], now: now, calendar: calendar)

        let today = try? XCTUnwrap(snapshot.today)
        XCTAssertEqual(today?.day, DailyQuoteDay.key(for: now, timeZone: calendar.timeZone))
        XCTAssertFalse(today?.preview.contains("#") ?? true)
        XCTAssertFalse(today?.preview.contains("**") ?? true)
        XCTAssertTrue(today?.preview.contains("Поля — это разговор.") ?? false)

        XCTAssertNotNil(snapshot.today(on: now))
        XCTAssertNil(snapshot.today(on: DailyQuoteDay.startOfNextDay(after: now, timeZone: calendar.timeZone)))
    }

    func testALongPageIsCutAtALineNotMidWord() {
        let long = (1...40).map { "Line number \($0) of a long day" }.joined(separator: "\n")
        let preview = NotesWidgetSnapshot.preview(of: long)
        XCTAssertLessThanOrEqual(preview.count, 220)
        XCTAssertTrue(preview.hasSuffix("of a long day"))
    }
}
