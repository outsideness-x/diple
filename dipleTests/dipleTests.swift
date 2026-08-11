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

    func testNoteMarkdownPreservesTasksCalloutsAndCleanPreviews() {
        let markdown = """
        # Release plan

        - [x] Search
        - [ ] Backlinks

        > [!TIP] Keep it focused
        > Ship the smallest excellent thing.

        ```swift
        let quality = "high"
        ```
        """

        let blocks = NoteMarkdown.parse(markdown)
        XCTAssertTrue(blocks.contains(.tasks([
            NoteTask(text: "Search", isCompleted: true),
            NoteTask(text: "Backlinks", isCompleted: false)
        ])))
        XCTAssertTrue(blocks.contains(.callout(
            kind: .tip,
            title: "Keep it focused",
            body: "Ship the smallest excellent thing."
        )))
        XCTAssertTrue(blocks.contains(.code(language: "swift", body: "let quality = \"high\"")))
        XCTAssertEqual(NoteMarkdown.taskProgress(in: markdown)?.completed, 1)
        XCTAssertFalse(NoteMarkdown.plainText(markdown).contains("[!TIP]"))
        XCTAssertFalse(NoteMarkdown.plainText(markdown).contains("```"))
    }

    func testNoteEditingWrapsSelectionsAndPrefixesWholeLines() {
        var text = "A useful idea"
        var selection = NSRange(location: 2, length: 6)
        NoteEditing.apply(
            to: &text,
            selection: &selection,
            prefix: "**",
            suffix: "**",
            placeholder: "bold text"
        )
        XCTAssertEqual(text, "A **useful** idea")
        XCTAssertEqual(selection, NSRange(location: 4, length: 6))

        text = "first\nsecond\nthird"
        selection = NSRange(location: 8, length: 0)
        NoteEditing.apply(
            to: &text,
            selection: &selection,
            prefix: "- [ ] ",
            placeholder: "Task",
            isLineCommand: true
        )
        XCTAssertEqual(text, "first\n- [ ] second\nthird")
        XCTAssertEqual((text as NSString).substring(with: selection), "second")
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
        let groups = try database.fetchHighlightGroups()
        XCTAssertEqual(groups.map(\.bookId), [book.id])
        XCTAssertEqual(groups.first?.quoteCount, 1)
        XCTAssertEqual(try database.fetchHighlights(forBookId: book.id).map(\.id), [highlight.id])
        XCTAssertEqual(try database.fetchBookmarks(forBookId: book.id).map(\.id), [bookmark.id])
        XCTAssertEqual(try database.fetchTagsByNote()[note.id], ["ideas", "한국어"])

        try database.deleteBook(id: book.id)

        XCTAssertTrue(try database.fetchAllBooks().isEmpty)
        // The book is gone, but the quote survives with the title/author frozen onto it, and
        // stays searchable under that snapshot instead of being dropped from the index.
        let survivingHighlights = try database.fetchHighlights(forBookId: book.id)
        XCTAssertEqual(survivingHighlights.map(\.id), [highlight.id])
        XCTAssertEqual(survivingHighlights.first?.bookTitle, book.title)
        XCTAssertEqual(try database.search("Цитата").map(\.kind), [.highlight])
        XCTAssertTrue(try database.fetchBookmarks(forBookId: book.id).isEmpty)
        XCTAssertNil(try XCTUnwrap(database.fetchAllNotes().first).bookId)
        XCTAssertEqual(try database.fetchTagsByNote()[note.id], ["ideas", "한국어"])
    }

    func testMarkingBookFinishedPreservesItsSavedLocation() throws {
        let database = try AppDatabase(DatabaseQueue())
        let originalLocator = #"{"href":"chapter-8.xhtml","locations":{"progression":0.42}}"#
        let book = Book(
            id: "finished-book",
            title: "Almost There",
            filePath: "Books/finished-book/book.epub",
            progress: 0.42,
            locator: originalLocator
        )
        try database.saveBook(book)

        try database.updateReadingProgress(id: book.id, progress: 1, locator: book.locator)

        let finishedBook = try XCTUnwrap(database.fetchBook(id: book.id))
        XCTAssertEqual(finishedBook.progress, 1)
        XCTAssertEqual(finishedBook.locator, originalLocator)
        XCTAssertNotNil(finishedBook.lastOpenedAt)
    }

    func testDailyResurfacingPrefersAnOlderQuoteAndIsStableForTheDay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let today = Calendar.current.startOfDay(for: now)
        let quotes = [
            Highlight(id: "old-a", bookId: "book", locator: "{}", text: "Old A", createdAt: today.addingTimeInterval(-86_400)),
            Highlight(id: "old-b", bookId: "book", locator: "{}", text: "Old B", createdAt: today.addingTimeInterval(-172_800)),
            Highlight(id: "new", bookId: "book", locator: "{}", text: "New", createdAt: today.addingTimeInterval(60))
        ]

        let first = DailyResurfacingService.candidate(for: now, from: quotes)
        let second = DailyResurfacingService.candidate(for: now, from: quotes)
        XCTAssertEqual(first?.id, second?.id)
        XCTAssertNotEqual(first?.id, "new")
    }

    func testGlobalSearchIndexesAndSynchronizesNotesHighlightsAndMetadata() throws {
        let database = try AppDatabase(DatabaseQueue())
        let book = Book(
            id: "search-book",
            title: "Алгебра",
            author: "Анна",
            filePath: "Books/search-book/book.epub",
            sourceURL: "https://example.org/article"
        )
        try database.saveBook(book)

        let note = Note(id: "search-note", title: "Идея", body: "Своя математическая мысль")
        try database.saveNote(note, tags: ["한국어"])

        let highlight = Highlight(
            id: "search-highlight",
            bookId: book.id,
            locator: "{}",
            text: "Сохранённая цитата о полиномах"
        )
        try database.saveHighlight(highlight)

        XCTAssertEqual(try database.search("мысль").map(\.kind), [.note])
        XCTAssertEqual(try database.search("цитат").map(\.kind), [.highlight])
        XCTAssertEqual(try database.search("example").map(\.kind), [.book])
        XCTAssertEqual(try database.search("한국").map(\.kind), [.note])
        XCTAssertNoThrow(try database.search(#"\"quoted-value\""#))

        try database.updateBookMetadata(id: book.id, title: "Геометрия", author: "Борис")
        XCTAssertTrue(try database.search("Алгебра").isEmpty)
        XCTAssertEqual(try database.search("Геометр").map(\.kind), [.book])

        try database.deleteHighlight(id: highlight.id)
        XCTAssertTrue(try database.search("полином").isEmpty)
    }

    func testFTSMatchQueryTreatsOnlyTheLastTokenAsAPrefix() throws {
        let database = try AppDatabase(DatabaseQueue())
        let note = Note(id: "prefix-note", body: "Продолжаем программирование и игра")
        try database.saveNote(note, tags: [])

        // "игр" is an unfinished last word while the user is still typing, so a trailing
        // prefix still finds "игра".
        XCTAssertEqual(try database.search("программирование игр").map(\.kind), [.note])
        // "программ" is not a real word in this body, only a prefix of "программирование".
        // Treating every token as a prefix (the previous behaviour) would have matched this
        // anyway; only the last token should still be unfinished once a second word starts.
        XCTAssertTrue(try database.search("программ игра").isEmpty)
    }

    func testGlobalSearchIndexesImportedArticleTextSeparatelyFromMetadata() throws {
        let database = try AppDatabase(DatabaseQueue())
        let article = Book(
            id: "article-book",
            title: "Readable Systems",
            author: "Ada",
            filePath: "Books/article-book/article.epub",
            sourceURL: "https://example.org/readable-systems"
        )

        try database.saveArticle(
            article,
            searchableText: "A distinctive passage about compositional architecture."
        )

        let bodyResults = try database.search("compositional")
        XCTAssertEqual(bodyResults.map(\.kind), [.article])
        XCTAssertEqual(bodyResults.first?.bookID, article.id)
        XCTAssertTrue(try database.fetchArticlesMissingTextIndex().isEmpty)

        try database.deleteBook(id: article.id)
        XCTAssertTrue(try database.search("compositional").isEmpty)
    }

    func testBookContentIndexIsResumableAndSearchableSeparatelyFromMetadata() throws {
        let database = try AppDatabase(DatabaseQueue())
        let book = Book(id: "content-book", title: "Пиранези", filePath: "Books/content-book/book.epub")
        try database.saveBook(book)
        let article = Book(
            id: "content-article",
            title: "An Article",
            filePath: "Books/content-article/article.epub",
            sourceURL: "https://example.org/piece"
        )
        try database.saveBook(article)

        // Both books start unindexed, but the article — already covered by `searchIndex` as an
        // `article` document — must never be offered to the content backfill, or the same
        // prose would be found twice.
        XCTAssertEqual(try database.fetchBooksMissingContentIndex().map(\.id), [book.id])

        let chunks = [
            BookContentChunk(
                href: "chapter1.xhtml",
                chapterTitle: "Зала Первая",
                locatorJSON: #"{"href":"chapter1.xhtml","type":"application/xhtml+xml","locations":{"progression":0}}"#,
                body: "Дом бесконечен, Залы, Лестницы и Дворы в нём без числа."
            ),
        ]
        try database.indexBookContent(book: book, chunks: chunks)

        // A finished book must never come back from the resumable-backfill query — that is
        // what makes the sweep a one-time cost instead of a per-launch re-parse.
        XCTAssertTrue(try database.fetchBooksMissingContentIndex().isEmpty)

        let results = try database.search("Дворы")
        XCTAssertEqual(results.map(\.kind), [.bookContent])
        XCTAssertEqual(results.first?.bookID, book.id)
        XCTAssertEqual(results.first?.title, "Зала Первая")
        XCTAssertNotNil(results.first?.parsedLocator)

        // Re-indexing (the resumable sweep landing on a book a second time, or a future
        // edition) replaces the old chunks wholesale rather than appending duplicates.
        try database.indexBookContent(book: book, chunks: [])
        XCTAssertTrue(try database.search("Дворы").isEmpty)
    }

    func testCloudSyncOutboxIsDurableCoalescedAndAcknowledgedPerRecord() throws {
        let database = try AppDatabase(DatabaseQueue(), syncEnabled: true)
        let addedAt = Date(timeIntervalSince1970: 100)
        let book = Book(
            id: "sync-book",
            title: "Синхронизация",
            filePath: "Books/sync-book/book.epub",
            addedAt: addedAt
        )
        try database.saveBook(book)

        var outbox = try database.fetchSyncOutbox()
        XCTAssertEqual(Set(outbox.compactMap(\.entity)), [.book, .bookAsset])

        let progressDate = Date(timeIntervalSince1970: 200)
        try database.updateReadingProgress(
            id: book.id,
            progress: 0.5,
            locator: #"{"href":"chapter.xhtml"}"#,
            lastOpenedAt: progressDate
        )
        outbox = try database.fetchSyncOutbox()
        XCTAssertEqual(outbox.count, 2, "Progress must coalesce into the existing book save")
        XCTAssertEqual(outbox.first { $0.entity == .book }?.modifiedAt, progressDate)
        XCTAssertEqual(outbox.first { $0.entity == .bookAsset }?.modifiedAt, addedAt)

        try database.acknowledgeSavedRecord(
            entity: .book,
            id: book.id,
            modifiedAt: progressDate,
            systemFields: Data("server-fields".utf8)
        )
        outbox = try database.fetchSyncOutbox()
        XCTAssertEqual(outbox.compactMap(\.entity), [.bookAsset])
        XCTAssertEqual(
            try database.fetchSyncMetadata(entity: .book, id: book.id)?.systemFields,
            Data("server-fields".utf8)
        )
    }

    func testCloudSyncRemoteMergeUsesModificationDateAndKeepsNotesWhenBookIsDeleted() throws {
        let database = try AppDatabase(DatabaseQueue(), syncEnabled: true)
        let book = Book(id: "remote-book", title: "Book", author: "Remote Author", filePath: "Books/remote-book/book.epub")
        try database.saveBook(book)

        let highlight = Highlight(id: "remote-highlight", bookId: book.id, locator: "{}", text: "Remote quote")
        try database.saveHighlight(highlight)

        let localDate = Date(timeIntervalSince1970: 200)
        let localNote = Note(
            id: "remote-note",
            body: "new local text",
            bookId: book.id,
            createdAt: Date(timeIntervalSince1970: 50),
            updatedAt: localDate
        )
        try database.saveNote(localNote, tags: ["local"])

        let staleRemote = SyncedNote(
            note: Note(
                id: localNote.id,
                body: "stale cloud text",
                bookId: book.id,
                createdAt: localNote.createdAt,
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            tags: ["cloud"]
        )
        XCTAssertFalse(
            try database.applyRemoteNote(
                staleRemote,
                modifiedAt: Date(timeIntervalSince1970: 100),
                systemFields: Data()
            )
        )
        XCTAssertEqual(try database.fetchNote(id: localNote.id)?.body, "new local text")

        let freshRemoteDate = Date(timeIntervalSince1970: 300)
        let freshRemote = SyncedNote(
            note: Note(
                id: localNote.id,
                body: "fresh cloud text",
                bookId: book.id,
                createdAt: localNote.createdAt,
                updatedAt: freshRemoteDate
            ),
            tags: ["cloud"]
        )
        XCTAssertTrue(
            try database.applyRemoteNote(
                freshRemote,
                modifiedAt: freshRemoteDate,
                systemFields: Data("note-fields".utf8)
            )
        )
        XCTAssertEqual(try database.fetchNote(id: localNote.id)?.body, "fresh cloud text")
        XCTAssertEqual(try database.fetchTags(forNoteID: localNote.id), ["cloud"])

        try database.acknowledgeSavedRecord(
            entity: .book,
            id: book.id,
            modifiedAt: .distantFuture,
            systemFields: Data()
        )
        XCTAssertTrue(try database.applyRemoteDeletion(entity: .book, id: book.id))
        XCTAssertNil(try database.fetchNote(id: localNote.id)?.bookId)
        XCTAssertNotNil(try database.fetchSyncOutbox().first { $0.entity == .note })

        // A book deletion that arrives from another device must leave the same trail as a
        // local one: the highlight survives with its snapshot, and no delete is queued for it.
        let survivingHighlight = try XCTUnwrap(database.fetchHighlightForSync(id: highlight.id))
        XCTAssertEqual(survivingHighlight.bookTitle, book.title)
        XCTAssertEqual(survivingHighlight.bookAuthor, book.author)
        XCTAssertFalse(
            try database.fetchSyncOutbox().contains { $0.entity == .highlight && $0.pendingOperation == .delete }
        )
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
        XCTAssertEqual(
            String(data: try XCTUnwrap(StoredZIPReader.entry(named: "EPUB/article.xhtml", in: archive)), encoding: .utf8)?.contains("Текст"),
            true
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
        XCTAssertTrue(extractor.searchableText.contains(paragraph))
        XCTAssertFalse(extractor.searchableText.contains("Меню сайта"))

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
