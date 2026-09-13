import GRDB
import XCTest
@testable import diple

/// Words shared from another app: queued by the share sheet, made notes by the app.
@MainActor
final class SharedNoteInboxTests: XCTestCase {

    private func inbox() -> (SharedNoteInbox, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("diple-shared-notes-\(UUID().uuidString)", isDirectory: true)
        return (SharedNoteInbox(directoryURL: directory), directory)
    }

    func testTheSameWordsSharedTwiceWaitAsOne() throws {
        let (inbox, directory) = inbox()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try inbox.enqueue("  Поля — это разговор с книгой.\n")
        let again = try inbox.enqueue("Поля — это разговор с книгой.")
        XCTAssertEqual(first.id, again.id)
        XCTAssertEqual(try inbox.pending().map(\.text), ["Поля — это разговор с книгой."])
        XCTAssertThrowsError(try inbox.enqueue(" \n "))
    }

    func testOnlyABareAddressIsALink() {
        XCTAssertEqual(SharedNoteInbox.linkOnly(in: " http://Example.com/essay \n")?.absoluteString, "https://example.com/essay")
        XCTAssertNil(SharedNoteInbox.linkOnly(in: "Read this: https://example.com/essay"))
        XCTAssertNil(SharedNoteInbox.linkOnly(in: "오늘 책을 읽었다"))
        XCTAssertNil(SharedNoteInbox.linkOnly(in: "ftp://example.com/file"))
    }

    func testDrainingMakesInboxNotesOnceAndEmptiesTheQueue() throws {
        let (inbox, directory) = inbox()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try AppDatabase(DatabaseQueue(), syncEnabled: true)

        let entry = try inbox.enqueue("A paragraph from Mail", at: Date(timeIntervalSince1970: 1_000))
        try inbox.enqueue("오늘 책을 읽었다", at: Date(timeIntervalSince1970: 2_000))

        XCTAssertEqual(SharedNoteDrain.drain(inbox, into: database), 2)
        XCTAssertTrue(try inbox.pending().isEmpty)

        let notes = try database.fetchAllNotes()
        XCTAssertEqual(Set(notes.map(\.body)), ["A paragraph from Mail", "오늘 책을 읽었다"])
        XCTAssertTrue(notes.allSatisfy { $0.spaceId == nil && $0.bookId == nil && $0.dailyDate == nil })
        XCTAssertEqual(notes.first { $0.body == "A paragraph from Mail" }?.id, entry.id.uuidString)
        XCTAssertEqual(notes.first { $0.body == "A paragraph from Mail" }?.createdAt, Date(timeIntervalSince1970: 1_000))

        // A pass that wrote the note but crashed before forgetting the entry finds it written.
        let replay = SharedNoteInbox(directoryURL: directory)
        _ = try AppGroupJSONFile<SharedNoteInbox.Entry>(directoryURL: directory, fileName: SharedNoteInbox.fileName)
            .mutate { $0.append(entry) }
        XCTAssertEqual(SharedNoteDrain.drain(replay, into: database), 1)
        XCTAssertEqual(try database.fetchAllNotes().count, 2)
    }
}
