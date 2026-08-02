import XCTest
import GRDB
@testable import diple

@MainActor
final class DipleTests: XCTestCase {

    // MARK: - Small persisted values

    func testTagNormalizationHandlesHashesCaseAndUnicode() {
        XCTAssertEqual(NoteTag.normalized("  ##Ideas  "), "ideas")
        XCTAssertEqual(NoteTag.normalized("  КНИГИ  "), "книги")
        XCTAssertEqual(NoteTag.normalized("#한국어"), "한국어")
        XCTAssertNil(NoteTag.normalized(" ## "))
    }

    func testLinkNormalizationAcceptsPastedAddressesAndRejectsUnsafeInput() {
        XCTAssertEqual(
            ImportLinkViewModel.normalize(" example.com/article ")?.absoluteString,
            "https://example.com/article"
        )
        XCTAssertEqual(
            ImportLinkViewModel.normalize("HTTP://example.com")?.scheme?.lowercased(),
            "http"
        )
        XCTAssertNil(ImportLinkViewModel.normalize("javascript:alert(1)"))
        XCTAssertNil(ImportLinkViewModel.normalize("not a url"))
        XCTAssertNil(ImportLinkViewModel.normalize("localhost/path"))
    }

    func testReaderSettingsMigratesLegacyStepAndRoundTripsCurrentScale() throws {
        let legacy = Data(#"{"fontSizeStep":3}"#.utf8)
        let migrated = try JSONDecoder().decode(ReaderSettings.self, from: legacy)
        XCTAssertEqual(migrated.fontSizeScale, 1.15, accuracy: 0.0001)

        var current = migrated
        current.fontSizeStep = ReaderSettings.maximumFontSizeStep
        let roundTripped = try JSONDecoder().decode(
            ReaderSettings.self,
            from: JSONEncoder().encode(current)
        )
        XCTAssertEqual(roundTripped.fontSizeScale, 1.35, accuracy: 0.0001)
        XCTAssertEqual(roundTripped.fontSizePercentage, 135)
    }

    func testReaderScriptUsesMetadataThenFallsBackToText() {
        assertScript(.cjk, ReaderScript.detect(languages: ["ko-KR"], sample: "English title"))
        assertScript(.cjk, ReaderScript.detect(languages: [], sample: "한국어로 쓴 제목"))
        assertScript(.cjk, ReaderScript.detect(languages: [], sample: "A mixed 제목 for testing"))
        assertScript(.latin, ReaderScript.detect(languages: ["ru"], sample: "Русский текст"))
    }

    // MARK: - Database contract

    func testDatabaseMigrationsCRUDAndDeleteSemantics() throws {
        let database = try AppDatabase(DatabaseQueue())
        let book = Book(id: "book-1", title: "Книга", filePath: "Books/book-1/book.epub")
        try database.saveBook(book)

        let highlight = Highlight(
            id: "highlight-1",
            bookId: book.id,
            locator: "{}",
            text: "Цитата"
        )
        let bookmark = Bookmark(
            id: "bookmark-1",
            bookId: book.id,
            locator: "{}",
            name: "Глава"
        )
        try database.saveHighlight(highlight)
        try database.saveBookmark(bookmark)

        let note = Note(id: "note-1", body: "Своя мысль", bookId: book.id)
        try database.saveNote(note, tags: [" #Ideas ", "IDEAS", "한국어"])

        let fetchedBook = try XCTUnwrap(database.fetchAllBooks().first)
        XCTAssertEqual(fetchedBook.id, book.id)
        XCTAssertEqual(fetchedBook.title, book.title)
        XCTAssertEqual(fetchedBook.filePath, book.filePath)
        XCTAssertEqual(try database.fetchHighlightCountsByBook(), [book.id: 1])
        XCTAssertEqual(try database.fetchHighlights(forBookId: book.id).map(\.id), [highlight.id])
        XCTAssertEqual(try database.fetchBookmarks(forBookId: book.id).map(\.id), [bookmark.id])
        XCTAssertEqual(try database.fetchTagsByNote()[note.id], ["ideas", "한국어"])

        try database.deleteBook(id: book.id)

        XCTAssertTrue(try database.fetchAllBooks().isEmpty)
        XCTAssertTrue(try database.fetchHighlights(forBookId: book.id).isEmpty)
        XCTAssertTrue(try database.fetchBookmarks(forBookId: book.id).isEmpty)
        XCTAssertNil(try XCTUnwrap(database.fetchAllNotes().first).bookId)
        XCTAssertEqual(try database.fetchTagsByNote()[note.id], ["ideas", "한국어"])
    }

    // MARK: - Generated EPUB

    func testZIPWriterUsesStoredEntriesAndCorrectCRC32() throws {
        var writer = ZIPWriter(modified: Date(timeIntervalSince1970: 315_532_800))
        try writer.append(path: "check.txt", data: Data("123456789".utf8))
        let archive = try writer.finalize()

        XCTAssertEqual(littleEndianUInt32(in: archive, at: 0), 0x0403_4B50)
        XCTAssertEqual(littleEndianUInt16(in: archive, at: 8), 0)
        XCTAssertEqual(littleEndianUInt32(in: archive, at: 14), 0xCBF4_3926)
        XCTAssertEqual(String(decoding: archive[30..<39], as: UTF8.self), "check.txt")
        XCTAssertEqual(littleEndianUInt32(in: archive, at: archive.count - 22), 0x0605_4B50)
    }

    func testGeneratedEPUBStartsWithUncompressedMimetype() throws {
        let metadata = ArticleMetadata(
            title: "Статья",
            author: "Автор",
            siteName: "Example",
            publishedAt: nil,
            language: "ru",
            canonicalURL: try XCTUnwrap(URL(string: "https://example.com/article")),
            leadImageURL: nil,
            wordCount: 120
        )
        let builder = ArticleEPUBBuilder(
            bookId: "book-epub",
            metadata: metadata,
            sections: [],
            bodyXHTML: "<p>Текст</p>",
            assets: [],
            coverPath: nil
        )

        let archive = try builder.epubData()
        XCTAssertEqual(littleEndianUInt32(in: archive, at: 0), 0x0403_4B50)
        XCTAssertEqual(littleEndianUInt16(in: archive, at: 8), 0)
        XCTAssertEqual(String(decoding: archive[30..<38], as: UTF8.self), "mimetype")
        XCTAssertEqual(
            String(decoding: archive[38..<(38 + "application/epub+zip".utf8.count)], as: UTF8.self),
            "application/epub+zip"
        )
    }

    // MARK: - Article extraction

    func testArticleExtractorKeepsProseAndRemovesPageChromeAndScripts() throws {
        let paragraph = String(
            repeating: "Это содержательный абзац статьи с нормальными предложениями и пунктуацией. ",
            count: 8
        )
        let html = """
            <html lang="ru">
              <head>
                <meta property="og:title" content="Тестовая статья | Example"/>
                <meta property="og:site_name" content="Example"/>
                <meta name="author" content="Автор"/>
                <link rel="canonical" href="https://example.com/canonical"/>
              </head>
              <body>
                <nav><p>Меню сайта, которое не относится к тексту.</p></nav>
                <article class="article-content" style="color:red">
                  <h1>Тестовая статья</h1>
                  <p class="prose">\(paragraph)</p>
                  <script>alert('bad')</script>
                  <h2>Раздел</h2>
                  <p>\(paragraph)</p>
                  <img src="https://cdn.example.com/meaningful-image.jpg" alt="Схема"/>
                </article>
              </body>
            </html>
            """

        let extractor = try ArticleExtractor(
            html: html,
            url: try XCTUnwrap(URL(string: "https://example.com/original"))
        )
        XCTAssertEqual(extractor.metadata.title, "Тестовая статья")
        XCTAssertEqual(extractor.metadata.author, "Автор")
        XCTAssertEqual(extractor.metadata.canonicalURL.absoluteString, "https://example.com/canonical")
        XCTAssertEqual(extractor.sections.map(\.title), ["Раздел"])
        XCTAssertEqual(extractor.images.count, 1)

        let body = try extractor.bodyXHTML(resolvedImages: [0: "images/article.jpg"])
        XCTAssertTrue(body.contains(paragraph))
        XCTAssertTrue(body.contains(#"id="section-1""#))
        XCTAssertTrue(body.contains(#"src="images/article.jpg""#))
        XCTAssertFalse(body.contains("<script"))
        XCTAssertFalse(body.contains("class="))
        XCTAssertFalse(body.contains("style="))
        XCTAssertFalse(body.contains("Меню сайта"))
    }

    // MARK: - Helpers

    private func assertScript(
        _ expected: ReaderScript,
        _ actual: ReaderScript,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (expected, actual) {
        case (.latin, .latin), (.cjk, .cjk):
            break
        default:
            XCTFail("Expected \(expected), got \(actual)", file: file, line: line)
        }
    }

    private func littleEndianUInt16(in data: Data, at offset: Int) -> UInt16 {
        let bytes = [UInt8](data[offset..<(offset + 2)])
        return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
    }

    private func littleEndianUInt32(in data: Data, at offset: Int) -> UInt32 {
        let bytes = [UInt8](data[offset..<(offset + 4)])
        return UInt32(bytes[0])
            | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 24)
    }
}
