import XCTest
@testable import diple

/// What the Desk means: which notes are in the Inbox, what order every list stands in, what
/// From reading lists, and which tasks are open.
@MainActor
final class NotesDeskTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func item(
        _ id: String,
        body: String = "a thought",
        book: Book? = nil,
        space: String? = nil,
        pinnedAt: Date? = nil,
        daily: String? = nil,
        updated: TimeInterval = 0,
        created: TimeInterval = 0,
        tags: [String] = []
    ) -> NoteItem {
        NoteItem(
            note: Note(
                id: id,
                body: body,
                bookId: book?.id,
                createdAt: base.addingTimeInterval(created),
                updatedAt: base.addingTimeInterval(updated),
                spaceId: space,
                pinnedAt: pinnedAt,
                dailyDate: daily
            ),
            tags: tags,
            book: book
        )
    }

    private let sapiens = Book(id: "b1", title: "Sapiens", author: "Harari", filePath: "Books/b1/b.epub")
    private let space = NoteSpace(id: "s1", name: "diple", sortIndex: 1)

    // MARK: - The Inbox

    func testTheInboxHoldsWhatNothingHasFiled() {
        let items = [
            item("loose"),
            item("filed", space: "s1"),
            item("about a book", book: sapiens),
            item("a day", daily: "2026-09-11")
        ]

        XCTAssertEqual(NotesDesk.inbox(items, spaces: [space]).map(\.id), ["loose"])
    }

    /// A space that has not arrived from iCloud yet is no space — for display. The note's
    /// pointer is kept; see `NoteSpace`.
    func testANoteWhoseSpaceHasNotArrivedWaitsInTheInbox() {
        let items = [item("early", space: "not-yet")]

        XCTAssertEqual(NotesDesk.inbox(items, spaces: [space]).map(\.id), ["early"])
        XCTAssertTrue(NotesDesk.notes(in: space, from: items).isEmpty)
    }

    // MARK: - Order

    func testEveryListIsPinnedFirstInPinOrderThenNewestFirst() {
        let items = [
            item("old", updated: 10),
            item("new", updated: 50),
            item("pinned second", pinnedAt: base.addingTimeInterval(20), updated: 1),
            item("pinned first", pinnedAt: base.addingTimeInterval(5), updated: 2)
        ]

        XCTAssertEqual(
            NotesDesk.ordered(items).map(\.id),
            ["pinned first", "pinned second", "new", "old"]
        )
    }

    // MARK: - From reading

    /// From reading is a view over the link to the book, not a folder: a note moved into a
    /// space still stands under its book.
    func testASourceKeepsItsNotesWhereverElseTheyAreFiled() {
        let items = [
            item("in a space", book: sapiens, space: "s1"),
            item("loose", book: sapiens)
        ]

        XCTAssertEqual(Set(NotesDesk.notes(about: "b1", from: items).map(\.id)), ["in a space", "loose"])
        XCTAssertEqual(NotesDesk.sources(items).first?.count, 2)
    }

    func testSourcesStandMostRecentlyWrittenAboutFirst() {
        let dune = Book(id: "b2", title: "Dune", author: nil, filePath: "Books/b2/b.epub")
        let items = [
            item("sapiens", book: sapiens, updated: 10),
            item("dune", book: dune, updated: 90)
        ]

        XCTAssertEqual(NotesDesk.sources(items).map(\.book.id), ["b2", "b1"])
    }

    // MARK: - Tasks

    func testOnlyOpenTasksAreListedGroupedByNote() {
        let items = [
            item("roadmap", body: "- [ ] Deploy\n- [x] Ship\n- [ ] Upload", updated: 5),
            item("done", body: "- [x] All of it"),
            item("prose", body: "No tasks here.")
        ]

        let groups = NotesDesk.openTasks(items)

        XCTAssertEqual(groups.map(\.id), ["roadmap"])
        XCTAssertEqual(groups.first?.tasks.map(\.text), ["Deploy", "Upload"])
        XCTAssertEqual(NotesDesk.openTaskCount(items), 2)
    }

    /// A task ticked a moment ago stays on the list for the beat it takes to see it land.
    func testAJustCompletedTaskLingersInItsPlace() {
        let items = [item("roadmap", body: "- [x] Deploy\n- [ ] Upload")]
        let lingering: Set = [NotesDesk.TaskKey(noteID: "roadmap", lineIndex: 0)]

        let tasks = NotesDesk.openTasks(items, lingering: lingering).first?.tasks

        XCTAssertEqual(tasks?.map(\.text), ["Deploy", "Upload"])
        XCTAssertEqual(tasks?.first?.isCompleted, true)
    }

    // MARK: - Finding and the journal

    func testFindingNeedsEveryWordSomewhereInTheNote() {
        let items = [
            item("both", body: "The garden of forking paths", tags: ["borges"]),
            item("one", body: "A garden")
        ]

        XCTAssertEqual(NotesDesk.search("garden borges", in: items).map(\.id), ["both"])
        XCTAssertTrue(NotesDesk.search("   ", in: items).isEmpty)
    }

    func testTheJournalIsNewestDayFirstAndTheDaysPageIsTheEarliest() {
        let items = [
            item("tenth", daily: "2026-09-10"),
            item("eleventh late", daily: "2026-09-11", created: 60),
            item("eleventh", daily: "2026-09-11", created: 0),
            item("not a day")
        ]

        XCTAssertEqual(NotesDesk.journal(items).first?.note.dailyDate, "2026-09-11")
        XCTAssertEqual(NotesDesk.journal(items).count, 3)
        XCTAssertEqual(NotesDesk.dailyPage(for: "2026-09-11", in: items)?.id, "eleventh")
    }
}
