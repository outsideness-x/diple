import GRDB
import XCTest
@testable import diple

/// Where a note lives: spaces, pins, Recently deleted and the day's page.
///
/// What has to hold: writing a note never moves it (every editor rebuilds a `Note` on each
/// autosave, and a page left open must not undo a move made meanwhile); moving, pinning and
/// deleting never count as writing it; what is deleted leaves the library, the vocabulary and
/// search, and comes back whole; and a space never takes its notes down with it.
@MainActor
final class NoteSpaceTests: XCTestCase {

    private func database() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(), syncEnabled: true)
    }

    private let past = Date(timeIntervalSince1970: 1_700_000_000)

    private func outboxDate(for id: String, in db: AppDatabase) throws -> Date? {
        try db.fetchSyncOutbox().first { $0.entityType == "note" && $0.entityID == id }?.modifiedAt
    }

    // MARK: - Writing never moves a note

    func testAnExistingNoteHasNowhereToLiveUntilItIsFiled() throws {
        let db = try database()
        try db.saveNote(Note(id: "n1", body: "a thought"), tags: [])

        let note = try XCTUnwrap(try db.fetchNote(id: "n1"))
        XCTAssertNil(note.spaceId)
        XCTAssertNil(note.pinnedAt)
        XCTAssertNil(note.trashedAt)
        XCTAssertNil(note.dailyDate)
    }

    /// The trap the whole split exists for: an editor saving what it has on screen.
    func testSavingWhatANoteSaysKeepsWhereItLives() throws {
        let db = try database()
        let space = try db.createSpace(named: "diple")
        try db.saveNote(Note(id: "n1", body: "a thought"), tags: [])
        try db.moveNotes(ids: ["n1"], toSpace: space.id)
        try db.setPinned(true, noteID: "n1")

        // Exactly what `NoteDetailView.save` builds: content only, organisation left at nil.
        try db.saveNote(Note(id: "n1", title: "Edited", body: "a better thought"), tags: [])

        let note = try XCTUnwrap(try db.fetchNote(id: "n1"))
        XCTAssertEqual(note.body, "a better thought")
        XCTAssertEqual(note.spaceId, space.id)
        XCTAssertNotNil(note.pinnedAt)
    }

    func testANewNoteIsBornWhereItWasStarted() throws {
        let db = try database()
        let space = try db.createSpace(named: "Journal")
        try db.saveNote(Note(id: "n1", body: "today", spaceId: space.id, dailyDate: "2026-09-11"), tags: [])

        let note = try XCTUnwrap(try db.fetchNote(id: "n1"))
        XCTAssertEqual(note.spaceId, space.id)
        XCTAssertEqual(note.dailyDate, "2026-09-11")
    }

    // MARK: - Filing is not writing

    func testFilingMovesTheSyncClockAndNotTheNote() throws {
        let db = try database()
        try db.saveNote(Note(id: "n1", body: "a thought", createdAt: past, updatedAt: past), tags: [])
        let space = try db.createSpace(named: "diple")
        let now = past.addingTimeInterval(3600)

        try db.moveNotes(ids: ["n1"], toSpace: space.id, changedAt: now)

        XCTAssertEqual(try db.fetchNote(id: "n1")?.updatedAt, past)
        XCTAssertEqual(try outboxDate(for: "n1", in: db), now)
    }

    func testPinningAgainKeepsItsPlaceAmongThePins() throws {
        let db = try database()
        try db.saveNote(Note(id: "n1", body: "a thought"), tags: [])
        try db.setPinned(true, noteID: "n1", changedAt: past)
        try db.setPinned(true, noteID: "n1", changedAt: past.addingTimeInterval(60))

        XCTAssertEqual(try db.fetchNote(id: "n1")?.pinnedAt, past)

        try db.setPinned(false, noteID: "n1")
        XCTAssertNil(try db.fetchNote(id: "n1")?.pinnedAt)
    }

    // MARK: - Recently deleted

    func testADeletedNoteLeavesTheLibraryAndSearchAndComesBackWhole() throws {
        let db = try database()
        let space = try db.createSpace(named: "diple")
        try db.saveNote(Note(id: "n1", body: "zebra crossing"), tags: ["animals"])
        try db.moveNotes(ids: ["n1"], toSpace: space.id)

        try db.trashNote(id: "n1")

        XCTAssertTrue(try db.fetchAllNotes().isEmpty)
        XCTAssertEqual(try db.fetchTrashedNotes().map(\.id), ["n1"])
        XCTAssertFalse(try db.search("zebra").contains { $0.kind == .note })
        XCTAssertFalse(try db.fetchAllTags().contains("animals"))

        try db.restoreNote(id: "n1")

        let note = try XCTUnwrap(try db.fetchAllNotes().first)
        XCTAssertEqual(note.spaceId, space.id)
        XCTAssertTrue(try db.search("zebra").contains { $0.kind == .note && $0.entityID == "n1" })
        XCTAssertTrue(try db.fetchAllTags().contains("animals"))
    }

    /// Saving a deleted note — an autosave landing late — must not bring it back.
    func testSavingADeletedNoteDoesNotRestoreIt() throws {
        let db = try database()
        try db.saveNote(Note(id: "n1", body: "a thought"), tags: [])
        try db.trashNote(id: "n1")

        try db.saveNote(Note(id: "n1", body: "a late keystroke"), tags: [])

        XCTAssertTrue(try db.fetchAllNotes().isEmpty)
        XCTAssertFalse(try db.search("keystroke").contains { $0.kind == .note })
    }

    func testTheTrashEmptiesAfterThirtyDaysAndNotBefore() throws {
        let db = try database()
        try db.saveNote(Note(id: "old", body: "gone"), tags: [])
        try db.saveNote(Note(id: "recent", body: "still here"), tags: [])
        let now = Date()
        try db.trashNote(id: "old", at: now.addingTimeInterval(-31 * 24 * 60 * 60))
        try db.trashNote(id: "recent", at: now.addingTimeInterval(-29 * 24 * 60 * 60))

        XCTAssertEqual(try db.purgeTrash(now: now), 1)

        XCTAssertNil(try db.fetchNote(id: "old"))
        XCTAssertEqual(try db.fetchTrashedNotes().map(\.id), ["recent"])
        let deletion = try db.fetchSyncOutbox().first { $0.entityID == "old" }
        XCTAssertEqual(deletion?.pendingOperation, .delete)
    }

    func testASourceOnlyListsItsLivingNotes() throws {
        let db = try database()
        try db.saveBook(Book(id: "b1", title: "Sapiens", author: nil, filePath: "Books/b1/b.epub"))
        try db.saveNote(Note(id: "n1", body: "kept", bookId: "b1"), tags: [])
        try db.saveNote(Note(id: "n2", body: "thrown away", bookId: "b1"), tags: [])
        try db.trashNote(id: "n2")

        XCTAssertEqual(try db.fetchNotes(forBookID: "b1").map(\.id), ["n1"])
    }

    // MARK: - Spaces

    func testSpacesStandInTheReadersOrder() throws {
        let db = try database()
        let first = try db.createSpace(named: "First")
        let third = try db.createSpace(named: "Third")
        var second = try db.createSpace(named: "Second")

        second.sortIndex = NoteSpace.sortIndex(between: first.sortIndex, and: third.sortIndex)
        try db.saveSpace(second)

        XCTAssertEqual(try db.fetchSpaces().map(\.name), ["First", "Second", "Third"])
    }

    func testSortIndexBetweenNeighboursAndAtTheEnds() {
        XCTAssertEqual(NoteSpace.sortIndex(between: 1, and: 2), 1.5)
        XCTAssertEqual(NoteSpace.sortIndex(between: 3, and: nil), 4)
        XCTAssertEqual(NoteSpace.sortIndex(between: nil, and: 1), 0)
        XCTAssertEqual(NoteSpace.sortIndex(between: nil, and: nil), 1)
    }

    /// A space never takes its notes down with it — the deleted ones included, so a note
    /// restored later does not come back pointing at nothing.
    func testDeletingASpaceSendsEverythingInItToTheInbox() throws {
        let db = try database()
        let space = try db.createSpace(named: "diple")
        try db.saveNote(Note(id: "n1", body: "alive", spaceId: space.id), tags: [])
        try db.saveNote(Note(id: "n2", body: "deleted", spaceId: space.id), tags: [])
        try db.trashNote(id: "n2")

        XCTAssertEqual(try db.deleteSpace(id: space.id), 2)

        XCTAssertTrue(try db.fetchSpaces().isEmpty)
        XCTAssertNil(try db.fetchNote(id: "n1")?.spaceId)
        XCTAssertNil(try db.fetchNote(id: "n2")?.spaceId)
        XCTAssertNotNil(try outboxDate(for: "n1", in: db))
    }

    // MARK: - iCloud

    func testASpaceIsQueuedForICloudWhenMadeAndWhenDeleted() throws {
        let db = try database()
        let space = try db.createSpace(named: "diple")
        XCTAssertEqual(
            try db.fetchSyncOutbox().first { $0.entityType == "space" }?.pendingOperation,
            .save
        )

        try db.deleteSpace(id: space.id)
        XCTAssertEqual(
            try db.fetchSyncOutbox().first { $0.entityType == "space" }?.pendingOperation,
            .delete
        )
    }

    /// A note that arrives before its space waits in the Inbox with its pointer intact, and is
    /// simply in the space once the space turns up.
    func testANoteArrivingBeforeItsSpaceKeepsItsFiling() throws {
        let db = try database()
        let note = Note(id: "n1", body: "from the phone", spaceId: "s1", pinnedAt: past)
        try db.applyRemoteNote(SyncedNote(note: note, tags: []), modifiedAt: past, systemFields: Data())

        XCTAssertEqual(try db.fetchNote(id: "n1")?.spaceId, "s1")
        XCTAssertTrue(try db.fetchSpaces().isEmpty)

        let space = NoteSpace(id: "s1", name: "diple", sortIndex: 1, createdAt: past, updatedAt: past)
        try db.applyRemoteSpace(space, modifiedAt: past, systemFields: Data())

        XCTAssertEqual(try db.fetchSpaces().map(\.id), ["s1"])
        XCTAssertEqual(try db.fetchNote(id: "n1")?.spaceId, "s1")
        XCTAssertEqual(try db.fetchNote(id: "n1")?.pinnedAt, past)
    }

    func testARemoteDeletionOfASpaceEmptiesItHere() throws {
        let db = try database()
        let space = NoteSpace(id: "s1", name: "diple", sortIndex: 1, createdAt: past, updatedAt: past)
        try db.applyRemoteSpace(space, modifiedAt: past, systemFields: Data())
        try db.applyRemoteNote(
            SyncedNote(note: Note(id: "n1", body: "x", spaceId: "s1"), tags: []),
            modifiedAt: past,
            systemFields: Data()
        )

        XCTAssertTrue(try db.applyRemoteDeletion(entity: .space, id: "s1"))

        XCTAssertTrue(try db.fetchSpaces().isEmpty)
        XCTAssertNil(try db.fetchNote(id: "n1")?.spaceId)
    }

    /// A remote note deleted into the trash on another device is not in the library here either.
    func testANoteDeletedOnAnotherDeviceLeavesTheLibraryHere() throws {
        let db = try database()
        let note = Note(id: "n1", body: "zebra", trashedAt: past)
        try db.applyRemoteNote(SyncedNote(note: note, tags: []), modifiedAt: past, systemFields: Data())

        XCTAssertTrue(try db.fetchAllNotes().isEmpty)
        XCTAssertFalse(try db.search("zebra").contains { $0.kind == .note })
    }

    func testTheFirstUploadCarriesTheSpaces() throws {
        let db = try database()
        try db.createSpace(named: "diple")
        // Forget what `createSpace` queued, so the bootstrap alone has to find it.
        let queued = try db.fetchSyncOutbox()
        for entry in queued {
            try db.acknowledgeSavedRecord(
                entity: try XCTUnwrap(entry.entity),
                id: entry.entityID,
                modifiedAt: entry.modifiedAt,
                systemFields: Data()
            )
        }
        XCTAssertTrue(try db.fetchSyncOutbox().isEmpty)

        try db.prepareInitialSync()

        XCTAssertTrue(try db.fetchSyncOutbox().contains { $0.entityType == "space" })
    }

    // MARK: - Backup

    /// A backup carries the spaces, where each note lives, and Recently deleted — a library
    /// restored onto a new device keeps its thirty days to change its mind in.
    func testABackupRestoresSpacesFilingAndTheTrash() throws {
        let source = try database()
        let space = try source.createSpace(named: "diple", symbol: "lightbulb")
        try source.saveNote(Note(id: "filed", body: "in a space", spaceId: space.id), tags: [])
        try source.setPinned(true, noteID: "filed")
        try source.saveNote(Note(id: "deleted", body: "thrown away"), tags: [])
        try source.trashNote(id: "deleted")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(try DipleExportPayload(database: source))
        let payload = try DipleBackupRestorer.shared.decode(data)
        XCTAssertEqual(payload.version, 4)

        let target = try database()
        XCTAssertEqual(try DipleBackupRestorer.shared.preview(payload, database: target).spacesAdded, 1)
        _ = try DipleBackupRestorer.shared.restore(payload, database: target)

        XCTAssertEqual(try target.fetchSpaces().map(\.symbol), ["lightbulb"])
        let filed = try XCTUnwrap(try target.fetchNote(id: "filed"))
        XCTAssertEqual(filed.spaceId, space.id)
        XCTAssertNotNil(filed.pinnedAt)
        XCTAssertEqual(try target.fetchTrashedNotes().map(\.id), ["deleted"])
        XCTAssertEqual(try target.fetchAllNotes().map(\.id), ["filed"])
    }

    // MARK: - The day's page

    func testTheDaysPageIsTheEarliestLivingOne() throws {
        let db = try database()
        try db.saveNote(Note(id: "phone", body: "morning", createdAt: past, dailyDate: "2026-09-11"), tags: [])
        try db.saveNote(Note(id: "mac", body: "also morning", createdAt: past.addingTimeInterval(60), dailyDate: "2026-09-11"), tags: [])

        XCTAssertEqual(try db.fetchDailyNote(forKey: "2026-09-11")?.id, "phone")

        try db.trashNote(id: "phone")
        XCTAssertEqual(try db.fetchDailyNote(forKey: "2026-09-11")?.id, "mac")
        XCTAssertNil(try db.fetchDailyNote(forKey: "2026-09-12"))
    }

    func testTheDailyKeyIsTheReadersDayWrittenTheSameWayEverywhere() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        // 2026-09-10 20:30 UTC is already the 11th in Seoul.
        let date = Date(timeIntervalSince1970: 1_789_072_200)

        XCTAssertEqual(Note.dailyKey(for: date, calendar: calendar), "2026-09-11")
    }
}
