import GRDB
import XCTest
@testable import diple

/// A thought written down from outside the app — Add to Today, the share sheet — and the
/// addresses the widget and Control Center open.
@MainActor
final class NoteCaptureTests: XCTestCase {

    private func database() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(), syncEnabled: true)
    }

    private let morning = Date(timeIntervalSince1970: 1_757_660_400) // 2025-09-12, 07:00 UTC
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    func testALineStartsItsOwnParagraphAndNeverJoinsAListAboveIt() {
        XCTAssertEqual(NoteCapture.appending("  Call the printer \n", to: ""), "Call the printer")
        XCTAssertEqual(NoteCapture.appending("Call the printer", to: "- [ ] Paper\n"), "- [ ] Paper\n\nCall the printer")
        XCTAssertEqual(NoteCapture.appending("   ", to: "Kept as it was\n"), "Kept as it was\n")
    }

    func testTheFirstLineOfTheDayBeginsTheDaysPage() throws {
        let db = try database()
        let title = try NoteCapture.addToToday("Позвонить в типографию", in: db, now: morning, calendar: calendar)

        let key = Note.dailyKey(for: morning, calendar: calendar)
        let page = try XCTUnwrap(db.fetchDailyNote(forKey: key))
        XCTAssertEqual(page.body, "Позвонить в типографию")
        XCTAssertEqual(page.title, title)
        XCTAssertEqual(title, Note.dailyTitle(forKey: key, calendar: calendar))
        XCTAssertNil(page.spaceId)
    }

    func testLaterLinesGoOnTheSamePageAndItsTagsStay() throws {
        let db = try database()
        try NoteCapture.addToToday("First", in: db, now: morning, calendar: calendar)
        let key = Note.dailyKey(for: morning, calendar: calendar)
        let page = try XCTUnwrap(db.fetchDailyNote(forKey: key))
        try db.saveNote(page, tags: ["journal"])

        try NoteCapture.addToToday("오늘 책을 읽었다", in: db, now: morning.addingTimeInterval(3600), calendar: calendar)

        let pages = try db.fetchAllNotes().filter { $0.dailyDate == key }
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages.first?.body, "First\n\n오늘 책을 읽었다")
        XCTAssertEqual(try db.fetchTags(forNoteID: page.id), ["journal"])
    }

    func testADeletedPageLeavesTheDayToBeginAgain() throws {
        let db = try database()
        try NoteCapture.addToToday("Gone", in: db, now: morning, calendar: calendar)
        let key = Note.dailyKey(for: morning, calendar: calendar)
        let first = try XCTUnwrap(db.fetchDailyNote(forKey: key))
        try db.trashNote(id: first.id)

        try NoteCapture.addToToday("Again", in: db, now: morning, calendar: calendar)
        XCTAssertEqual(try db.fetchDailyNote(forKey: key)?.body, "Again")
    }

    func testNothingIsNotAThought() throws {
        let db = try database()
        XCTAssertThrowsError(try NoteCapture.addToToday(" \n", in: db, now: morning, calendar: calendar))
        XCTAssertThrowsError(try NoteCapture.addToInbox("", id: "x", in: db))
        XCTAssertTrue(try db.fetchAllNotes().isEmpty)
    }

    func testAnInboxCaptureIsWrittenOnceWhateverTheRetries() throws {
        let db = try database()
        try NoteCapture.addToInbox("A shared thought", id: "share-1", in: db, now: morning)
        try NoteCapture.addToInbox("A shared thought", id: "share-1", in: db, now: morning)

        let notes = try db.fetchAllNotes()
        XCTAssertEqual(notes.map(\.id), ["share-1"])
        XCTAssertNil(notes.first?.spaceId)
        XCTAssertNil(notes.first?.dailyDate)
    }

    func testTheAddressesTheWidgetOpensNameTheirPages() {
        XCTAssertEqual(URL(string: "diple://new-note").flatMap(DipleShortcut.init(url:)), .newNote)
        XCTAssertEqual(URL(string: "diple://today").flatMap(DipleShortcut.init(url:)), .today)
        XCTAssertEqual(URL(string: "diple://inbox").flatMap(DipleShortcut.init(url:)), .inbox)
        XCTAssertNil(URL(string: "diple://daily").flatMap(DipleShortcut.init(url:)))
        XCTAssertNil(URL(string: "https://today").flatMap(DipleShortcut.init(url:)))
    }
}
