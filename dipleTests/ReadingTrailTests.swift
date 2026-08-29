import GRDB
import ReadiumShared
import XCTest
@testable import diple

final class ReadingTrailTests: XCTestCase {
    // MARK: - The trail itself

    func testAJumpLeavesSomewhereToGoBackTo() {
        var trail = ReadingTrail()
        XCTAssertFalse(trail.canGoBack)

        trail.record(locator("chapter-3.xhtml", at: 0.31))

        XCTAssertTrue(trail.canGoBack)
        XCTAssertEqual(trail.backDestination?.locations.totalProgression, 0.31)
    }

    /// One footnote tap can reach the app as both `shouldNavigateToLink` and
    /// `shouldNavigateToNoteAt`, and two markers on one line depart from the same place. Without
    /// folding those the way back is a row of taps that all land within a sentence.
    func testTheSameDepartureReportedTwiceIsOneStepBack() {
        var trail = ReadingTrail()

        XCTAssertTrue(trail.record(locator("chapter-3.xhtml", at: 0.31)))
        XCTAssertFalse(trail.record(locator("chapter-3.xhtml", at: 0.31)))

        XCTAssertEqual(trail.back.count, 1)
    }

    func testTwoDeparturesFromTheSameResourceButDifferentPlacesAreBothKept() {
        var trail = ReadingTrail()

        trail.record(locator("chapter-3.xhtml", at: 0.31))
        trail.record(locator("chapter-3.xhtml", at: 0.44))

        XCTAssertEqual(trail.back.count, 2)
    }

    func testTheSameProgressionInAnotherResourceIsNotTheSameSpot() {
        var trail = ReadingTrail()

        trail.record(locator("chapter-3.xhtml", at: 0.31))
        trail.record(locator("endnotes.xhtml", at: 0.31))

        XCTAssertEqual(trail.back.count, 2)
    }

    /// The pair of taps this exists for: follow a note, come back, then find the note again.
    func testAStepBackCanBeUndone() {
        var trail = ReadingTrail()
        let reading = locator("chapter-3.xhtml", at: 0.31)
        let note = locator("endnotes.xhtml", at: 0.88)

        trail.record(reading)

        XCTAssertEqual(trail.stepBack(leaving: note)?.locations.totalProgression, 0.31)
        XCTAssertFalse(trail.canGoBack)
        XCTAssertTrue(trail.canGoForward)

        XCTAssertEqual(trail.stepForward(leaving: reading)?.locations.totalProgression, 0.88)
        XCTAssertTrue(trail.canGoBack)
        XCTAssertFalse(trail.canGoForward)
    }

    /// Browser semantics, and the reason for them: the branch stepped out of is no longer
    /// anywhere the reader can walk forwards to, so offering it would open a page nobody asked
    /// twice for.
    func testANewJumpDiscardsTheWayForward() {
        var trail = ReadingTrail()
        trail.record(locator("chapter-3.xhtml", at: 0.31))
        _ = trail.stepBack(leaving: locator("endnotes.xhtml", at: 0.88))
        XCTAssertTrue(trail.canGoForward)

        trail.record(locator("chapter-5.xhtml", at: 0.52))

        XCTAssertFalse(trail.canGoForward)
        XCTAssertEqual(trail.backDestination?.locations.totalProgression, 0.52)
    }

    /// A stale return point — recorded for a jump the navigator never completed — must not put
    /// the page the reader is already standing on into the forward stack.
    func testSteppingBackToWhereYouAlreadyAreCreatesNoForwardStep() {
        var trail = ReadingTrail()
        let here = locator("chapter-3.xhtml", at: 0.31)
        trail.record(here)

        XCTAssertNotNil(trail.stepBack(leaving: here))

        XCTAssertFalse(trail.canGoForward)
    }

    func testTheTrailIsBoundedAndKeepsTheNewestSteps() {
        var trail = ReadingTrail()
        for step in 0...ReadingTrail.depthLimit {
            trail.record(locator("chapter.xhtml", at: Double(step) / 1_000))
        }

        XCTAssertEqual(trail.back.count, ReadingTrail.depthLimit)
        XCTAssertEqual(
            trail.backDestination?.locations.totalProgression,
            Double(ReadingTrail.depthLimit) / 1_000,
            "the way back from here is the one about to be asked for"
        )
        XCTAssertEqual(
            trail.back.first?.locations.totalProgression,
            0.001,
            "the oldest step is the one dropped"
        )
    }

    // MARK: - What the control says

    func testAStopNamesItsChapterWhenThePublicationNamesOne() {
        let stop = Locator(
            href: AnyURL(string: "chapter-5.xhtml")!,
            mediaType: .xhtml,
            title: "  The Inland Sea  ",
            locations: Locator.Locations(totalProgression: 0.34)
        )

        XCTAssertEqual(ReadingTrail.label(for: stop), "The Inland Sea")
    }

    func testAStopWithoutATitleNamesItsPosition() {
        XCTAssertEqual(ReadingTrail.label(for: locator("chapter-5.xhtml", at: 0.336)), "34%")
    }

    func testAStopWithNeitherStillSaysSomethingTrue() {
        let stop = Locator(href: AnyURL(string: "chapter-5.xhtml")!, mediaType: .xhtml)

        XCTAssertEqual(ReadingTrail.label(for: stop), "where you were")
    }

    // MARK: - The reader

    /// The report this was built from: jump, read for a while, and the way back is gone.
    ///
    /// The offer used to be the control, so the timer that retired the words retired the route
    /// with them — while the stack that could have taken the reader back was still in memory
    /// with nothing left to press. The label is allowed to expire. The way back is not.
    @MainActor
    func testTheWayBackOutlivesTheWordsOnIt() throws {
        let viewModel = try makeReader()

        viewModel.saveLocation(locator("chapter-3.xhtml", at: 0.31))
        viewModel.pushBackLocation(locator("chapter-3.xhtml", at: 0.31))

        XCTAssertTrue(viewModel.isTrailLabelVisible)
        XCTAssertEqual(viewModel.backDestinationLabel, "31%")

        viewModel.hideTrailLabel()

        XCTAssertFalse(viewModel.isTrailLabelVisible, "the sentence is over")
        XCTAssertTrue(viewModel.trail.canGoBack, "the way back is not")
    }

    /// The other half of the report: a jump to a place picked on the progress bar has to be
    /// undoable in exactly the way a followed link is.
    @MainActor
    func testDraggingTheProgressBarLeavesAWayBack() throws {
        let viewModel = try makeReader()
        viewModel.saveLocation(locator("chapter-1.xhtml", at: 0.08))

        viewModel.navigateToLocator(locator("chapter-9.xhtml", at: 0.77))

        XCTAssertTrue(viewModel.trail.canGoBack)
        XCTAssertEqual(viewModel.backDestinationLabel, "8%")
    }

    @MainActor
    func testTheTrailEndsWithTheSitting() throws {
        let viewModel = try makeReader()
        viewModel.saveLocation(locator("chapter-1.xhtml", at: 0.08))
        viewModel.navigateToLocator(locator("chapter-9.xhtml", at: 0.77))

        viewModel.endReadingSession()

        XCTAssertFalse(viewModel.trail.canGoBack)
        XCTAssertFalse(viewModel.trail.canGoForward)
    }

    /// An in-memory database, so persisting a location in these tests touches nothing real.
    @MainActor
    private func makeReader() throws -> ReaderViewModel {
        let database = try AppDatabase(DatabaseQueue())
        let book = Book(id: "trail-book", title: "Source", filePath: "Books/trail/book.epub")
        try database.saveBook(book)
        return ReaderViewModel(book: book, database: database)
    }

    private func locator(_ href: String, at totalProgression: Double) -> Locator {
        Locator(
            href: AnyURL(string: href)!,
            mediaType: .xhtml,
            locations: Locator.Locations(
                progression: totalProgression,
                totalProgression: totalProgression
            )
        )
    }
}
