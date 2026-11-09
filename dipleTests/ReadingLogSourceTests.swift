import XCTest
import GRDB
import ImageIO
import UniformTypeIdentifiers
@testable import diple

/// The reading log's memory of a source: what survives the book, and when it is written.
final class ReadingLogSourceTests: XCTestCase {
    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    private func book(
        id: String = "dracula",
        title: String = "Dracula",
        author: String? = "Bram Stoker",
        coverPath: String? = "Books/dracula/cover.png",
        progress: Double = 0.4,
        lastOpenedAt: Date? = nil
    ) -> Book {
        Book(
            id: id,
            title: title,
            author: author,
            filePath: "Books/\(id)/book.epub",
            coverPath: coverPath,
            addedAt: Date(timeIntervalSince1970: 1_780_000_000),
            lastOpenedAt: lastOpenedAt,
            progress: progress
        )
    }

    private func sitting(_ bookId: String, endingAt end: Date) -> ReadingSession {
        ReadingSession(
            bookId: bookId,
            startedAt: end.addingTimeInterval(-1_800),
            endedAt: end,
            characters: 30_000,
            seconds: 1_800
        )
    }

    /// The point of the table: a book that was read keeps its name and its cover once it has
    /// gone from the shelf, and its sittings are still there to be printed under them.
    func testDeletingABookThatWasReadRemembersItsTitleAndCover() throws {
        let database = try makeDatabase()
        try database.saveBook(book())
        try database.recordReadingSession(sitting("dracula", endingAt: Date(timeIntervalSince1970: 1_790_000_000)))

        try database.deleteBook(id: "dracula")

        let remembered = try database.fetchReadingLogSources()
        XCTAssertEqual(remembered.count, 1)
        XCTAssertEqual(remembered.first?.title, "Dracula")
        XCTAssertEqual(remembered.first?.author, "Bram Stoker")
        XCTAssertEqual(remembered.first?.coverPath, "Covers/dracula.jpg")
        XCTAssertNil(remembered.first?.finishedAt)
        XCTAssertEqual(try database.keptCoverPath(forBookId: "dracula"), "Covers/dracula.jpg")
        XCTAssertEqual(try database.fetchReadingSessions().count, 1)
    }

    /// A source deleted unread is not part of anyone's reading, and keeping its cover would be
    /// a file nothing could ever show.
    func testDeletingAnUnreadBookLeavesNothingBehind() throws {
        let database = try makeDatabase()
        try database.saveBook(book(progress: 0))

        try database.deleteBook(id: "dracula")

        XCTAssertTrue(try database.fetchReadingLogSources().isEmpty)
        XCTAssertNil(try database.keptCoverPath(forBookId: "dracula"))
    }

    func testABookWithoutACoverIsRememberedWithoutOne() throws {
        let database = try makeDatabase()
        try database.saveBook(book(coverPath: nil))
        try database.recordReadingSession(sitting("dracula", endingAt: Date(timeIntervalSince1970: 1_790_000_000)))

        try database.deleteBook(id: "dracula")

        XCTAssertEqual(try database.fetchReadingLogSources().first?.title, "Dracula")
        XCTAssertNil(try database.keptCoverPath(forBookId: "dracula"))
    }

    /// `progress = 1` says a book was finished, never when; the finish is dated as it happens.
    func testMarkingABookFinishedDatesTheFinish() throws {
        let database = try makeDatabase()
        try database.saveBook(book())
        let finish = Date(timeIntervalSince1970: 1_791_000_000)

        try database.markBookAsFinished(id: "dracula", lastOpenedAt: finish)

        let remembered = try XCTUnwrap(try database.fetchReadingLogSources().first)
        XCTAssertEqual(remembered.finishedAt, finish)
        // While the book lives its own cover is drawn, so none is kept yet.
        XCTAssertNil(remembered.coverPath)

        try database.deleteBook(id: "dracula")

        let afterDeletion = try XCTUnwrap(try database.fetchReadingLogSources().first)
        XCTAssertEqual(afterDeletion.finishedAt, finish)
        XCTAssertEqual(afterDeletion.coverPath, "Covers/dracula.jpg")
    }

    /// A book finished before finishes were recorded is dated when it is deleted, by the same
    /// inference the statistics use while it lives — afterwards there is nothing to infer from.
    func testDeletingAnUndatedFinishedBookFreezesTheInferredDate() throws {
        let database = try makeDatabase()
        let lastOpened = Date(timeIntervalSince1970: 1_792_000_000)
        try database.saveBook(book(progress: 1, lastOpenedAt: lastOpened))

        try database.deleteBook(id: "dracula")

        XCTAssertEqual(try database.fetchReadingLogSources().first?.finishedAt, lastOpened)
    }

    /// A deletion that arrives from iCloud leaves the same trail as a local one.
    func testARemoteDeletionRemembersTheBookToo() throws {
        let database = try makeDatabase()
        try database.saveBook(book())
        try database.recordReadingSession(sitting("dracula", endingAt: Date(timeIntervalSince1970: 1_790_000_000)))

        XCTAssertTrue(try database.applyRemoteDeletion(entity: .book, id: "dracula"))

        XCTAssertEqual(try database.fetchReadingLogSources().first?.title, "Dracula")
        XCTAssertEqual(try database.keptCoverPath(forBookId: "dracula"), "Covers/dracula.jpg")
    }

    /// The kept cover is a thumbnail, not the publisher's full-size PNG.
    func testAKeptCoverIsAThumbnail() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("kept-cover-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let source = folder.appendingPathComponent("cover.png")
        try writePNG(width: 1_200, height: 1_800, to: source)

        let data = try XCTUnwrap(BookStorageService.thumbnailJPEG(of: source, maxPixelSize: 600))
        let image = try XCTUnwrap(
            CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        )
        XCTAssertEqual(image.height, 600)
        XCTAssertEqual(image.width, 400)
    }

    private func writePNG(width: Int, height: Int, to url: URL) throws {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.5, green: 0.3, blue: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
