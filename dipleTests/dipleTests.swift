import XCTest
import GRDB
import ReadiumNavigator
@testable import diple

@MainActor
final class DipleTests: XCTestCase {

    // MARK: - Settings merge

    /// The case the whole per-field merge exists for: two devices change two different
    /// settings, and both changes have to survive.
    func testMergeKeepsEachDeviceSeparateFieldChange() {
        let base = AppSettings()
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 2_000)

        var phone = base
        phone.accent = .clay
        phone.stampChanges(against: base, at: early)

        var mac = base
        mac.appearance = .light
        mac.stampChanges(against: base, at: late)

        let merged = phone.merging(remote: mac)
        XCTAssertEqual(merged.accent, .clay, "the phone's accent must survive")
        XCTAssertEqual(merged.appearance, .light, "the Mac's appearance must survive")
    }

    /// When both devices touch the *same* field, the later stamp wins regardless of which side
    /// is local.
    func testMergeTakesTheNewerValueOfAContestedField() {
        let base = AppSettings()
        var mine = base
        mine.accent = .clay
        mine.stampChanges(against: base, at: Date(timeIntervalSince1970: 1_000))

        var theirs = base
        theirs.accent = .mint
        theirs.stampChanges(against: base, at: Date(timeIntervalSince1970: 2_000))

        XCTAssertEqual(mine.merging(remote: theirs).accent, .mint)
        XCTAssertEqual(theirs.merging(remote: mine).accent, .mint)
    }

    /// A tie keeps what the reader is already looking at.
    func testMergePrefersLocalOnEqualStamps() {
        let base = AppSettings()
        let sameMoment = Date(timeIntervalSince1970: 1_000)

        var mine = base
        mine.accent = .clay
        mine.stampChanges(against: base, at: sameMoment)

        var theirs = base
        theirs.accent = .mint
        theirs.stampChanges(against: base, at: sameMoment)

        XCTAssertEqual(mine.merging(remote: theirs).accent, .clay)
    }

    /// A payload written before stamps existed carries none, so it must not overwrite a value
    /// this device is known to have chosen.
    func testMergeIgnoresUnstampedRemoteValues() {
        let base = AppSettings()
        var mine = base
        mine.accent = .clay
        mine.stampChanges(against: base, at: Date(timeIntervalSince1970: 1_000))

        var legacy = base
        legacy.accent = .mint
        legacy.fieldStamps = [:]

        XCTAssertEqual(mine.merging(remote: legacy).accent, .clay)
    }

    /// Stamps survive the round trip that actually carries them between devices.
    func testFieldStampsSurviveCoding() throws {
        var settings = AppSettings()
        settings.appearance = .light
        settings.stampChanges(against: AppSettings(), at: Date(timeIntervalSince1970: 1_234))

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: try JSONEncoder().encode(settings)
        )
        XCTAssertEqual(decoded.fieldStamps[AppSettings.Field.appearance.rawValue],
                       Date(timeIntervalSince1970: 1_234))
    }

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
        // Compared field by field rather than by whole-value equality: a `NoteTask` also
        // carries the source line it was parsed from, so a task built here would have to guess
        // a line number to match — which is asserting on the fixture's formatting, not on the
        // parser. Text and completion are what this test is actually about.
        let tasks = blocks.compactMap { block -> [NoteTask]? in
            if case .tasks(let items) = block { return items }
            return nil
        }.first
        XCTAssertEqual(tasks?.map(\.text), ["Search", "Backlinks"])
        XCTAssertEqual(tasks?.map(\.isCompleted), [true, false])
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

    func testNoteMarkdownParsesInlineAndDisplayMathWithoutLosingSource() {
        let markdown = #"""
        Energy is $E = mc^2$.

        $$
        \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}
        $$

        \[\sum_{i=1}^{n} i = \frac{n(n+1)}{2}\]
        """#

        let blocks = NoteMarkdown.parse(markdown)
        XCTAssertTrue(blocks.contains(.paragraph("Energy is $E = mc^2$.")))
        XCTAssertTrue(blocks.contains(.math(#"\frac{-b \pm \sqrt{b^2 - 4ac}}{2a}"#)))
        XCTAssertTrue(blocks.contains(.math(#"\sum_{i=1}^{n} i = \frac{n(n+1)}{2}"#)))
        XCTAssertFalse(NoteMarkdown.plainText(markdown).contains("$$"))
        XCTAssertTrue(NoteMarkdown.plainText(markdown).contains("E = mc^2"))
    }

    func testNoteMathParserHonorsEscapesAndBothInlineDelimiters() {
        let source = #"Price \$5 and $x^2$ plus \(y_1 + y_2\)"#
        XCTAssertEqual(NoteMathParser.inlineSegments(in: source), [
            .text(#"Price \$5 and "#),
            .formula("x^2"),
            .text(" plus "),
            .formula("y_1 + y_2")
        ])
        XCTAssertEqual(
            NoteMathParser.removingDelimiters(from: source),
            #"Price \$5 and x^2 plus y_1 + y_2"#
        )
    }

    func testFormulaComposerRoundTripsSelectionsAndBlockSpacing() {
        XCTAssertEqual(NoteMathParser.formulaSelection(from: "$E = mc^2$").latex, "E = mc^2")
        XCTAssertEqual(NoteMathParser.formulaSelection(from: "$E = mc^2$").mode, .inline)
        XCTAssertEqual(NoteMathParser.formulaSelection(from: "$$\n\\frac{a}{b}\n$$").mode, .block)

        var text = "Energy: "
        var selection = NSRange(location: (text as NSString).length, length: 0)
        NoteEditing.insertFormula("E = mc^2", mode: .inline, in: &text, selection: &selection)
        XCTAssertEqual(text, "Energy: $E = mc^2$")
        XCTAssertEqual((text as NSString).substring(with: selection), "E = mc^2")

        text = "Before\nAfter"
        selection = NSRange(location: 7, length: 0)
        NoteEditing.insertFormula(#"\sum_{i=1}^{n} i"#, mode: .block, in: &text, selection: &selection)
        XCTAssertEqual(text, "Before\n$$\n\\sum_{i=1}^{n} i\n$$\n\nAfter")
        XCTAssertEqual((text as NSString).substring(with: selection), #"\sum_{i=1}^{n} i"#)
    }

    func testNoteKnowledgeResolvesWikiLinksAndBacklinksByTitle() {
        let source = NoteItem(
            note: Note(id: "source", title: "Source", body: "See [[Deep Work]] and [[Кафе]]."),
            tags: [],
            book: nil
        )
        let deepWork = NoteItem(
            note: Note(id: "deep", title: "deep work", body: "Focus."),
            tags: [],
            book: nil
        )
        let cafe = NoteItem(
            note: Note(id: "cafe", title: "КАФЕ", body: "A place."),
            tags: [],
            book: nil
        )

        XCTAssertEqual(NoteKnowledge.wikiLinks(in: source.note.body), ["Deep Work", "Кафе"])
        XCTAssertEqual(Set(NoteKnowledge.outgoing(from: source.note.body, among: [source, deepWork, cafe]).map(\.id)), ["deep", "cafe"])
        XCTAssertEqual(NoteKnowledge.backlinks(to: deepWork, among: [source, deepWork, cafe]).map(\.id), ["source"])
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
        XCTAssertEqual(fetchedBook.sourceKind, .epub)
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

    func testPublicationKindIsInferredAndPersistedForEverySource() throws {
        let database = try AppDatabase(DatabaseQueue())
        let epub = Book(id: "epub", title: "Book", filePath: "Books/epub/book.epub")
        let pdf = Book(id: "pdf", title: "Paper", filePath: "Books/pdf/paper.PDF")
        let article = Book(
            id: "article",
            title: "Essay",
            filePath: "Books/article/article.epub",
            sourceURL: "https://example.org/essay"
        )

        try database.saveBook(epub)
        try database.saveBook(pdf)
        try database.saveBook(article)

        let saved = try database.fetchAllBooks().reduce(into: [String: PublicationKind]()) {
            $0[$1.id] = $1.sourceKind
        }
        XCTAssertEqual(saved[epub.id], .epub)
        XCTAssertEqual(saved[pdf.id], .pdf)
        XCTAssertEqual(saved[article.id], .article)
        XCTAssertTrue(LibraryTypeFilter.books.includes(epub))
        XCTAssertFalse(LibraryTypeFilter.books.includes(pdf))
        XCTAssertTrue(LibraryTypeFilter.pdfs.includes(pdf))
        XCTAssertTrue(LibraryTypeFilter.articles.includes(article))

        // The point of the split: type and status are independent, so "unread articles" —
        // unaskable while both lived in one enum — is now an ordinary pair of selections.
        var unreadArticle = article
        unreadArticle.progress = 0
        var finishedArticle = article
        finishedArticle.progress = 1
        XCTAssertTrue(LibraryTypeFilter.articles.includes(unreadArticle)
                      && LibraryStatusFilter.unread.includes(unreadArticle))
        XCTAssertFalse(LibraryStatusFilter.unread.includes(finishedArticle))
        XCTAssertTrue(LibraryStatusFilter.finished.includes(finishedArticle))
        XCTAssertNil(LibraryStatusFilter.any.compactTitle, "a default filter has nothing to announce")
        XCTAssertEqual(LibraryStatusFilter.unread.compactTitle, "Unread")
    }

    /// `v14_addBookFurthestProgress` has to run against libraries that already have reading
    /// history: a row saved before the column existed carries only `progress`, and the
    /// migration's backfill (`UPDATE book SET furthestProgress = progress`) is what keeps that
    /// history from silently resetting to 0. Seeding through a throwaway migrator that only
    /// knows `v1_createBookTable` — under the identical name and schema `AppDatabase` itself
    /// registers it under — marks that one migration as already applied in GRDB's own ledger,
    /// so `AppDatabase`'s real migrator skips recreating the table and runs its own v2…v14
    /// (including the real backfill) against this pre-existing, pre-v14 row.
    func testFurthestProgressMigrationBackfillsExistingRows() throws {
        let dbQueue = try DatabaseQueue()
        var seedMigrator = DatabaseMigrator()
        seedMigrator.registerMigration("v1_createBookTable") { db in
            try db.create(table: "book") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("author", .text)
                t.column("filePath", .text).notNull()
                t.column("coverPath", .text)
                t.column("addedAt", .datetime).notNull()
                t.column("lastOpenedAt", .datetime)
                t.column("progress", .double).notNull().defaults(to: 0.0)
                t.column("locator", .text)
            }
        }
        try seedMigrator.migrate(dbQueue)
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO book (id, title, filePath, addedAt, progress) VALUES (?, ?, ?, ?, ?)",
                arguments: ["legacy-book", "Legacy Book", "Books/legacy-book/book.epub", Date(timeIntervalSince1970: 1_000), 0.73]
            )
        }

        let database = try AppDatabase(dbQueue)
        let migrated = try XCTUnwrap(database.fetchBook(id: "legacy-book"))
        XCTAssertEqual(migrated.progress, 0.73, accuracy: 0.0001)
        XCTAssertEqual(migrated.furthestProgress, 0.73, accuracy: 0.0001)
    }

    func testFurthestProgressIsAHighWaterMarkThatSurvivesScrollingBack() throws {
        // `Book.init` itself must never let the mark sit below the live position, whether the
        // caller (a CloudKit record predating this field, an importer, a test fixture) passes
        // no value at all or an explicit one that is already stale.
        XCTAssertEqual(Book(id: "a", title: "A", filePath: "f").furthestProgress, 0)
        XCTAssertEqual(Book(id: "b", title: "B", filePath: "f", progress: 0.5).furthestProgress, 0.5, accuracy: 0.0001)
        XCTAssertEqual(
            Book(id: "c", title: "C", filePath: "f", progress: 0.5, furthestProgress: 0.2).furthestProgress,
            0.5, accuracy: 0.0001
        )
        XCTAssertEqual(
            Book(id: "d", title: "D", filePath: "f", progress: 0.2, furthestProgress: 0.9).furthestProgress,
            0.9, accuracy: 0.0001
        )

        let database = try AppDatabase(DatabaseQueue())
        let book = Book(id: "scrollback-book", title: "Scrollback", filePath: "Books/scrollback-book/book.epub")
        try database.saveBook(book)

        try database.updateReadingProgress(id: book.id, progress: 0.62, locator: nil)
        var fetched = try XCTUnwrap(database.fetchBook(id: book.id))
        XCTAssertEqual(fetched.progress, 0.62, accuracy: 0.0001)
        XCTAssertEqual(fetched.furthestProgress, 0.62, accuracy: 0.0001)

        // Scrolling back to reread an earlier chapter moves the live position backwards, same
        // as always, but must not erase how far the book has already been read.
        try database.updateReadingProgress(id: book.id, progress: 0.2, locator: nil)
        fetched = try XCTUnwrap(database.fetchBook(id: book.id))
        XCTAssertEqual(fetched.progress, 0.2, accuracy: 0.0001)
        XCTAssertEqual(fetched.furthestProgress, 0.62, accuracy: 0.0001, "the high-water mark must not decrease")

        // Reading past the old high-water mark moves it forward again.
        try database.updateReadingProgress(id: book.id, progress: 0.9, locator: nil)
        fetched = try XCTUnwrap(database.fetchBook(id: book.id))
        XCTAssertEqual(fetched.progress, 0.9, accuracy: 0.0001)
        XCTAssertEqual(fetched.furthestProgress, 0.9, accuracy: 0.0001)
    }

    /// `v15_addBookLocation` must not use its own column default for the backfill. Dumping an
    /// existing library into an inbox turns the feature into a chore on first launch, and
    /// filing an already-finished book as unsorted is simply false.
    func testLocationMigrationSortsAnExistingLibraryRatherThanInboxingIt() throws {
        let dbQueue = try DatabaseQueue()
        var seedMigrator = DatabaseMigrator()
        seedMigrator.registerMigration("v1_createBookTable") { db in
            try db.create(table: "book") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("author", .text)
                t.column("filePath", .text).notNull()
                t.column("coverPath", .text)
                t.column("addedAt", .datetime).notNull()
                t.column("lastOpenedAt", .datetime)
                t.column("progress", .double).notNull().defaults(to: 0.0)
                t.column("locator", .text)
            }
        }
        try seedMigrator.migrate(dbQueue)
        try dbQueue.write { db in
            for (id, progress) in [("finished-book", 1.0), ("half-read-book", 0.4), ("untouched-book", 0.0)] {
                try db.execute(
                    sql: "INSERT INTO book (id, title, filePath, addedAt, progress) VALUES (?, ?, ?, ?, ?)",
                    arguments: [id, id, "Books/\(id)/book.epub", Date(timeIntervalSince1970: 1_000), progress]
                )
            }
        }

        let database = try AppDatabase(dbQueue)
        XCTAssertEqual(try XCTUnwrap(database.fetchBook(id: "finished-book")).location, .archive)
        XCTAssertEqual(try XCTUnwrap(database.fetchBook(id: "half-read-book")).location, .later)
        // Never opened is not the same as newly saved: it predates the queue, so it waits in
        // Later with the rest of the backlog rather than appearing as something to triage.
        XCTAssertEqual(try XCTUnwrap(database.fetchBook(id: "untouched-book")).location, .later)
    }

    func testNewSourcesLandInTheInboxAndCanBeMovedOut() throws {
        let database = try AppDatabase(DatabaseQueue())
        let book = Book(id: "fresh-save", title: "Fresh Save", filePath: "Books/fresh-save/article.epub")
        XCTAssertEqual(book.location, .inbox, "a new save is the one thing that belongs in the inbox")
        try database.saveBook(book)

        try database.updateBookLocation(id: book.id, location: .later)
        XCTAssertEqual(try XCTUnwrap(database.fetchBook(id: book.id)).location, .later)

        // Filing is about intention only — archiving something half-read must not also throw
        // away where the reader stopped.
        let locator = #"{"href":"chapter-3.xhtml","locations":{"progression":0.31}}"#
        try database.updateReadingProgress(id: book.id, progress: 0.31, locator: locator)
        try database.updateBookLocation(id: book.id, location: .archive)
        let archived = try XCTUnwrap(database.fetchBook(id: book.id))
        XCTAssertEqual(archived.location, .archive)
        XCTAssertEqual(archived.locator, locator)
        XCTAssertEqual(archived.furthestProgress, 0.31, accuracy: 0.0001)
    }

    /// A record saved before the queue existed carries no `location`. `Book.init` defaults to
    /// `.inbox`, which is right for a fresh save and wrong here: this is a book from a library
    /// that predates the concept, so sync must apply the same rule the v15 backfill does rather
    /// than filling someone's inbox from another device.
    func testRemoteBookWithoutALocationIsSortedRatherThanInboxed() throws {
        XCTAssertEqual(BookLocation.inferred(progress: 1.0), .archive)
        XCTAssertEqual(BookLocation.inferred(progress: 0.4), .later)
        XCTAssertEqual(BookLocation.inferred(progress: 0.0), .later)
    }

    func testSourceTagsAreNormalizedSearchableAndSurviveRemoteRecordsThatPredateThem() throws {
        let database = try AppDatabase(DatabaseQueue(), syncEnabled: true)
        let book = Book(id: "tagged-book", title: "Пиранези", filePath: "Books/tagged-book/book.epub")
        try database.saveBook(book)

        // One rule for what a tag is, shared with notes: case folded, `#` stripped, blanks
        // dropped, duplicates collapsed.
        try database.setTags(["#Fiction", "fiction", "  Долгое чтение ", "#", ""], forBookId: book.id)
        XCTAssertEqual(try database.fetchTags(forBookId: book.id), ["fiction", "долгое чтение"].sorted())
        XCTAssertEqual(try database.fetchAllBookTags(), ["fiction", "долгое чтение"].sorted())
        XCTAssertEqual(try database.fetchTagsByBook()[book.id]?.sorted(), ["fiction", "долгое чтение"].sorted())

        // A tag is a way back to the source, so it belongs in the source's search document.
        XCTAssertEqual(try database.search("fiction").first?.entityID, book.id)

        // Both incoming records have to be *newer* than the local edit made a moment ago, or
        // `shouldAcceptRemote` rejects them on the timestamp and the assertions below would
        // pass for the wrong reason.
        let laterThanLocal = Date().addingTimeInterval(60)

        // A record saved before sources could be tagged carries no `tags` key at all. Treating
        // that as "no tags" would let one un-upgraded device strip the whole library.
        XCTAssertTrue(try database.applyRemoteBook(
            Book(id: book.id, title: "Piranesi", filePath: book.filePath, addedAt: book.addedAt),
            tags: nil,
            modifiedAt: laterThanLocal,
            systemFields: Data()
        ))
        XCTAssertEqual(try database.fetchTags(forBookId: book.id), ["fiction", "долгое чтение"].sorted())
        XCTAssertEqual(try database.search("fiction").first?.entityID, book.id)

        // An explicit set does replace them, and the index follows.
        XCTAssertTrue(try database.applyRemoteBook(
            Book(id: book.id, title: "Piranesi", filePath: book.filePath, addedAt: book.addedAt),
            tags: ["Reference"],
            modifiedAt: laterThanLocal.addingTimeInterval(60),
            systemFields: Data()
        ))
        XCTAssertEqual(try database.fetchTags(forBookId: book.id), ["reference"])
        XCTAssertTrue(try database.search("fiction").isEmpty)

        // Tags go with the source: there is no shelf left to label once the book is gone.
        try database.deleteBook(id: book.id)
        XCTAssertEqual(try database.fetchAllBookTags(), [])
    }

    /// The failure this guards against is silent: drop a font file from the bundle and the
    /// picker still offers the option, the page still renders — in the fallback — and nothing
    /// anywhere says the family was never declared.
    func testShippedReadingFacesResolveToRealFilesInTheBundle() {
        for font in ReaderFont.allCases {
            for face in font.bundledFaces {
                XCTAssertNotNil(
                    Bundle.main.url(forResource: face.file, withExtension: "otf"),
                    "\(face.file).otf is declared by \(font.rawValue) but missing from the bundle"
                )
            }
        }

        let bundled = ReaderFont.allCases.filter { !$0.bundledFaces.isEmpty }
        XCTAssertEqual(bundled.map(\.rawValue), ["Atkinson Hyperlegible", "OpenDyslexic"])

        // New York and San Francisco have no files of their own — they resolve through a guard
        // family in ReaderFontDeclarations instead of a bundled fontFaces list — but every one
        // of the four options the picker offers is still genuinely backed by a declaration.
        XCTAssertTrue(ReaderFont.serif.bundledFaces.isEmpty)
        XCTAssertTrue(ReaderFont.sanFrancisco.bundledFaces.isEmpty)
        XCTAssertNil(ReaderFont.sanFrancisco.registeredFamilyName)
        XCTAssertEqual(ReaderFontDeclarations.all.count, ReaderFont.allCases.count)
    }

    /// The guard mechanism only works if New York and San Francisco produce genuinely different
    /// stacks: the same guard family for both would mean picking either one sets the identical
    /// Readium preference, and the page could not tell the two choices apart.
    func testSystemFontGuardsResolveToDistinctStacks() throws {
        let declarations = ReaderFontDeclarations.all

        let newYork = try XCTUnwrap(
            declarations.first { $0.fontFamily == ReaderFont.serif.fontFamily },
            "No declaration for the New York guard family"
        )
        let sanFrancisco = try XCTUnwrap(
            declarations.first { $0.fontFamily == ReaderFont.sanFrancisco.fontFamily },
            "No declaration for the San Francisco guard family"
        )

        XCTAssertNotEqual(newYork.fontFamily, sanFrancisco.fontFamily)
        XCTAssertEqual(newYork.alternates, [FontFamily(rawValue: "ui-serif")])
        XCTAssertEqual(sanFrancisco.alternates, [FontFamily(rawValue: "-apple-system")])

        // A bare CSS identifier, no space and no quote: Readium's own `String.css()` only
        // quotes a family that contains one, and an unquoted guard name reaching the page as an
        // identifier is what the whole approach depends on.
        XCTAssertFalse(newYork.fontFamily.rawValue.contains(" "))
        XCTAssertFalse(sanFrancisco.fontFamily.rawValue.contains(" "))
    }

    /// `HTMLInjection` is internal to the Readium module, so the guard writes its own `<style>`
    /// splice with plain string search. Confirms the splice lands before `</head>` and that a
    /// document with no `<head>` at all — malformed XHTML, but not impossible — comes back
    /// untouched instead of the search being force-unwrapped into a crash.
    func testSystemFontGuardInjectsStyleBeforeHeadClose() throws {
        let declarations = ReaderFontDeclarations.all
        let newYork = try XCTUnwrap(
            declarations.first { $0.fontFamily == ReaderFont.serif.fontFamily }
        )

        let html = "<html><head><title>x</title></head><body></body></html>"
        let injected = try newYork.inject(in: html) { _ in
            XCTFail("The guard never serves a file; servingFile should not be called")
            throw CocoaError(.fileNoSuchFile)
        }
        XCTAssertTrue(injected.contains("@font-face"))
        XCTAssertTrue(injected.contains(ReaderFont.serif.fontFamily.rawValue))
        XCTAssertNotNil(injected.range(of: "</style></head>", options: .caseInsensitive))

        let malformed = "<html><body>no head here</body></html>"
        let unchanged = try newYork.inject(in: malformed) { _ in
            throw CocoaError(.fileNoSuchFile)
        }
        XCTAssertEqual(unchanged, malformed)
    }

    func testReadingEstimateStaysSilentWhenItDoesNotKnow() {
        let latin = ReadingSpeed.latinDefault

        // A book nobody has measured must say nothing — not "0 min", which is a claim.
        XCTAssertNil(ReadingEstimate.remaining(characters: nil, progress: 0.5, charactersPerMinute: latin))
        XCTAssertNil(ReadingEstimate.total(characters: nil, charactersPerMinute: latin))
        XCTAssertNil(ReadingEstimate.minutes(characters: 0, charactersPerMinute: latin))
        // And neither must a two-line article round up into a claim of its own.
        XCTAssertNil(ReadingEstimate.minutes(characters: 200, charactersPerMinute: latin))

        XCTAssertEqual(ReadingEstimate.format(minutes: 14), "14 min")
        XCTAssertEqual(ReadingEstimate.format(minutes: 140), "2 h 20 min")
        XCTAssertEqual(ReadingEstimate.format(minutes: 180), "3 h", "no trailing zero minutes")

        // 12 000 characters ÷ 1200 a minute = 10 minutes; half read leaves five.
        XCTAssertEqual(ReadingEstimate.total(characters: 12_000, charactersPerMinute: latin), "10 min")
        XCTAssertEqual(
            ReadingEstimate.remaining(characters: 12_000, progress: 0.5, charactersPerMinute: latin),
            "5 min left"
        )
        XCTAssertNil(
            ReadingEstimate.remaining(characters: 12_000, progress: 1, charactersPerMinute: latin),
            "a finished book has nothing left to promise"
        )
    }

    // MARK: - Measured reading speed

    /// The whole point: a reader who is faster than the shipped constant must end up being told
    /// a shorter time, and the figure must be *theirs* rather than a nudge towards theirs.
    func testMeasuredSpeedReplacesTheDefaultOnceThereIsEvidence() {
        var speed = ReadingSpeed()
        XCTAssertEqual(speed.rate(for: .latin), ReadingSpeed.latinDefault, accuracy: 0.001,
                       "with nothing measured the answer is the shipped default")

        // Twice the default pace, over comfortably more than the evidence needed to be trusted.
        let characters = ReadingSpeed.trustedCharacters * 2
        speed.record(characters: characters, seconds: characters / (ReadingSpeed.latinDefault * 2) * 60,
                     script: .latin)

        XCTAssertEqual(speed.rate(for: .latin), ReadingSpeed.latinDefault * 2, accuracy: 1)
        XCTAssertEqual(speed.rate(for: .cjk), ReadingSpeed.cjkDefault, accuracy: 0.001,
                       "reading Russian says nothing about how fast this person reads Korean")
    }

    /// A first, small sample must move the estimate without hijacking it: the reader has read a
    /// couple of pages, not proven anything.
    func testAShortFirstSampleOnlyPartlyDisplacesTheDefault() {
        var speed = ReadingSpeed()
        let characters = ReadingSpeed.trustedCharacters / 4
        speed.record(characters: characters, seconds: characters / (ReadingSpeed.latinDefault * 2) * 60,
                     script: .latin)

        let rate = speed.rate(for: .latin)
        XCTAssertGreaterThan(rate, ReadingSpeed.latinDefault)
        XCTAssertLessThan(rate, ReadingSpeed.latinDefault * 2)
    }

    /// Skimming for a half-remembered passage, and a page left open on the kitchen table, are
    /// both rates — and neither is a reading speed.
    func testImplausibleSamplesAreRefused() {
        var speed = ReadingSpeed()
        speed.record(characters: 50_000, seconds: 60, script: .latin)
        XCTAssertNil(speed.measuredPace(for: .latin), "skimming is not reading")

        speed.record(characters: 1_000, seconds: 60 * 60, script: .latin)
        XCTAssertNil(speed.measuredPace(for: .latin), "an abandoned page is not reading either")

        XCTAssertEqual(speed.rate(for: .latin), ReadingSpeed.latinDefault, accuracy: 0.001)
    }

    /// The sampler exists to throw things away. These are the things.
    func testSamplerRefusesEverythingThatIsNotReading() throws {
        let start = Date(timeIntervalSince1970: 0)
        var sampler = try XCTUnwrap(ReadingSpeedSampler(totalCharacters: 100_000))

        // The first report is only an anchor; nothing has been observed yet.
        XCTAssertNil(sampler.observe(progress: 0.0, now: start))

        // A jump from the table of contents: a fifth of the book in a moment. The caller is
        // expected to say so, and after that the ground covered is not counted.
        sampler.invalidate()
        XCTAssertNil(sampler.observe(progress: 0.2, now: start.addingTimeInterval(0.04)))

        // Reading on from there, far enough to be worth something. The step has to stay under
        // the idle timeout: it is the gap between two *reports* that says somebody left, so a
        // single silent jump of five minutes is by definition not five minutes of reading.
        let sample = try XCTUnwrap(
            sampler.observe(progress: 0.25, now: start.addingTimeInterval(0.04 + 150))
        )
        XCTAssertEqual(sample.characters, 5_000, accuracy: 0.001)
        XCTAssertEqual(sample.seconds, 150, accuracy: 0.001)

        // Put the phone down for an hour, then move: the gap is not reading time.
        XCTAssertNil(sampler.observe(progress: 0.30, now: start.addingTimeInterval(4_000)))
        // And going backwards to re-read is not new ground.
        XCTAssertNil(sampler.observe(progress: 0.28, now: start.addingTimeInterval(4_100)))
    }

    /// A scrolled pixel is not a sample. The window has to keep growing across reports rather
    /// than restarting at each one, or nothing would ever be measured in scroll mode.
    func testSamplerAccumulatesAcrossManySmallReports() throws {
        let start = Date(timeIntervalSince1970: 0)
        var sampler = try XCTUnwrap(ReadingSpeedSampler(totalCharacters: 100_000))
        XCTAssertNil(sampler.observe(progress: 0, now: start))

        var emitted: ReadingSpeedSampler.Sample?
        for step in 1 ... 20 {
            let progress = Double(step) * 0.002 // 200 characters a step
            if let sample = sampler.observe(progress: progress, now: start.addingTimeInterval(Double(step) * 10)) {
                emitted = sample
            }
        }

        let sample = try XCTUnwrap(emitted, "twenty small reports add up to a real one")
        XCTAssertEqual(sample.characters, ReadingSpeedSampler.minimumSampleCharacters, accuracy: 1)
    }

    /// A source the indexer has never measured cannot be sampled at all — there is no length to
    /// turn a fraction into characters against.
    func testSamplerRefusesASourceOfUnknownLength() {
        XCTAssertNil(ReadingSpeedSampler(totalCharacters: nil))
        XCTAssertNil(ReadingSpeedSampler(totalCharacters: 0))
    }

    /// The pace is a field of the settings like any other, so it has to survive the same merge.
    func testReadingSpeedMergesLikeAnyOtherField() {
        let base = AppSettings()
        var phone = base
        phone.readingSpeed.record(characters: 30_000, seconds: 30_000 / 1_500 * 60, script: .latin)
        phone.stampChanges(against: base, at: Date(timeIntervalSince1970: 2_000))

        var mac = base
        mac.accent = .clay
        mac.stampChanges(against: base, at: Date(timeIntervalSince1970: 1_000))

        let merged = mac.merging(remote: phone)
        XCTAssertEqual(merged.accent, .clay, "the Mac's accent survives")
        XCTAssertNotNil(merged.readingSpeed.measuredPace(for: .latin),
                        "and the phone brings the pace it measured")
    }

    func testContentLengthFallsBackToChunksAndReadsArticlesFromTheirOwnDocument() throws {
        // The queue is created here rather than inline so the test can reach past `AppDatabase`
        // to simulate a row written before v17 — the column is nullable precisely because such
        // rows exist in the wild.
        let dbQueue = try DatabaseQueue()
        let database = try AppDatabase(dbQueue)
        let book = Book(id: "measured-book", title: "Measured", filePath: "Books/measured-book/book.epub")
        try database.saveBook(book)

        // Unindexed is not the same as empty.
        XCTAssertNil(try database.contentCharacterCount(bookID: book.id, isArticle: false))

        try database.indexBookContent(
            book: book,
            chunks: [
                BookContentChunk(href: "c1.xhtml", chapterTitle: "One", locatorJSON: "{}", body: String(repeating: "а", count: 900)),
                BookContentChunk(href: "c2.xhtml", chapterTitle: "Two", locatorJSON: "{}", body: String(repeating: "b", count: 600)),
            ]
        )
        XCTAssertEqual(try database.contentCharacterCount(bookID: book.id, isArticle: false), 1_500)
        XCTAssertEqual(try database.contentCharacterCounts()[book.id], 1_500)

        // A row written before v17 has no `characterCount`, and falls back to the old estimate
        // rather than reporting a book of zero length.
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE bookContentIndex SET characterCount = NULL WHERE bookID = ?",
                arguments: [book.id]
            )
        }
        XCTAssertEqual(
            try database.contentCharacterCount(bookID: book.id, isArticle: false),
            2 * BookContentExtractor.targetChunkSize
        )

        // Articles are deliberately absent from `bookContent`, so they are measured from the
        // single `article` document they do have in `searchIndex`.
        let article = Book(
            id: "measured-article",
            title: "Measured Article",
            filePath: "Books/measured-article/article.epub",
            sourceURL: "https://example.com/a"
        )
        try database.saveArticle(article, searchableText: String(repeating: "x", count: 4_200))
        XCTAssertEqual(try database.contentCharacterCount(bookID: article.id, isArticle: true), 4_200)
        XCTAssertEqual(try database.contentCharacterCounts()[article.id], 4_200)
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

    func testEditingHighlightUpdatesColorCommentSearchAndSync() throws {
        let database = try AppDatabase(DatabaseQueue(), syncEnabled: true)
        let book = Book(id: "edit-highlight-book", title: "Source", filePath: "Books/source.epub")
        let highlight = Highlight(
            id: "editable-highlight",
            bookId: book.id,
            locator: "{}",
            text: "A selected passage",
            colorHex: DipleColor.Highlight.yellow
        )
        try database.saveBook(book)
        try database.saveHighlight(highlight)

        try database.updateHighlight(
            id: highlight.id,
            colorHex: DipleColor.Highlight.blue,
            comment: "  New context  "
        )

        let updated = try XCTUnwrap(database.fetchHighlights(forBookId: book.id).first)
        XCTAssertEqual(updated.colorHex, DipleColor.Highlight.blue)
        XCTAssertEqual(updated.comment, "New context")
        XCTAssertEqual(try database.search("context").map(\.entityID), [highlight.id])
        XCTAssertEqual(
            try database.fetchSyncOutbox().first { $0.entity == .highlight }?.entityID,
            highlight.id
        )
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

    func testPortableExportPreservesRelationshipsWithoutPrivateFilePaths() throws {
        let database = try AppDatabase(DatabaseQueue())
        let book = Book(
            id: "export-book",
            title: "Source",
            filePath: "Books/private/internal.epub",
            sourceURL: "https://example.org/source"
        )
        let highlight = Highlight(
            id: "export-highlight",
            bookId: book.id,
            locator: "{\"href\":\"chapter.xhtml\"}",
            text: "A passage",
            comment: "My thought"
        )
        let note = Note(id: "export-note", title: "Idea", body: "Connected", bookId: book.id)
        try database.saveBook(book)
        try database.saveHighlight(highlight)
        try database.saveNote(note, tags: ["idea"])
        let payload = try DipleExportPayload(database: database)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = try XCTUnwrap(String(data: encoder.encode(payload), encoding: .utf8))

        XCTAssertEqual(payload.sources.map(\.id), [book.id])
        XCTAssertEqual(payload.highlights.map(\.bookId), [book.id])
        XCTAssertEqual(payload.notes.first?.tags, ["idea"])
        XCTAssertFalse(json.contains("Books/private/internal.epub"))
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

        try database.updateHighlightComment(
            id: highlight.id,
            comment: "Мой комментарий о структуре доказательства"
        )
        XCTAssertEqual(
            try database.fetchHighlights(forBookId: book.id).first?.comment,
            "Мой комментарий о структуре доказательства"
        )
        XCTAssertEqual(try database.search("структур").map(\.kind), [.highlight])

        try database.updateBookMetadata(id: book.id, title: "Геометрия", author: "Борис")
        XCTAssertTrue(try database.search("Алгебра").isEmpty)
        XCTAssertEqual(try database.search("Геометр").map(\.kind), [.book])

        try database.deleteHighlight(id: highlight.id)
        XCTAssertTrue(try database.search("полином").isEmpty)
    }

    func testHighlightCommentNormalizesBlankTextAndQueuesSync() throws {
        let database = try AppDatabase(DatabaseQueue(), syncEnabled: true)
        let book = Book(
            id: "comment-book",
            title: "Commented Book",
            filePath: "Books/comment-book/book.epub",
            addedAt: Date(timeIntervalSince1970: 50)
        )
        try database.saveBook(book)
        let highlight = Highlight(
            id: "comment-highlight",
            bookId: book.id,
            locator: "{}",
            text: "A passage",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try database.saveHighlight(highlight)

        let changedAt = Date(timeIntervalSince1970: 200)
        try database.updateHighlightComment(
            id: highlight.id,
            comment: "  A personal connection.  ",
            changedAt: changedAt
        )
        XCTAssertEqual(
            try database.fetchHighlightForSync(id: highlight.id)?.comment,
            "A personal connection."
        )
        XCTAssertEqual(
            try database.fetchSyncOutbox().first { $0.entity == .highlight }?.modifiedAt,
            changedAt
        )

        try database.updateHighlightComment(id: highlight.id, comment: " \n ")
        XCTAssertNil(try database.fetchHighlightForSync(id: highlight.id)?.comment)
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

        // Reader search may build precise navigable chunks for an article on demand. Global
        // search must still return its original article document only once.
        try database.indexBookContent(book: article, chunks: [
            BookContentChunk(
                href: "article.xhtml",
                chapterTitle: article.title,
                locatorJSON: #"{"href":"article.xhtml","type":"application/xhtml+xml","locations":{"progression":0}}"#,
                body: "A distinctive passage about compositional architecture."
            )
        ])
        XCTAssertEqual(try database.searchBookContent(bookID: article.id, query: "compositional").count, 1)
        XCTAssertEqual(try database.search("compositional").map(\.kind), [.article])

        try database.deleteBook(id: article.id)
        XCTAssertTrue(try database.search("compositional").isEmpty)
    }

    func testBookContentIndexIsResumableAndSearchableSeparatelyFromMetadata() throws {
        let database = try AppDatabase(DatabaseQueue())
        let book = Book(
            id: "content-book",
            title: "Пиранези",
            filePath: "Books/content-book/Пиранези — Сюзанна Кларк.epub"
        )
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
        // The passage is labelled with the book's own title — the name the library, the hub and
        // the reader's bar all use — not with the file it happens to be stored in.
        XCTAssertEqual(results.first?.title, "Пиранези")
        XCTAssertEqual(results.first?.subtitle, "Зала Первая")
        XCTAssertNotNil(results.first?.parsedLocator)

        // A blank title has nothing to show, so the filename remains the fallback.
        let untitled = Book(
            id: "untitled-book",
            title: "",
            filePath: "Books/untitled-book/anonymous.epub"
        )
        try database.saveBook(untitled)
        try database.indexBookContent(
            book: untitled,
            chunks: [
                BookContentChunk(
                    href: "chapter1.xhtml",
                    chapterTitle: "",
                    locatorJSON: #"{"href":"chapter1.xhtml","type":"application/xhtml+xml","locations":{"progression":0}}"#,
                    body: "Дворы и Лестницы без числа."
                ),
            ]
        )
        XCTAssertEqual(
            try database.search("Дворы").first(where: { $0.bookID == untitled.id })?.title,
            "anonymous.epub"
        )
        try database.indexBookContent(book: untitled, chunks: [])

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

    /// A remote book record is accepted or rejected as a whole on `modifiedAt` — right for
    /// title/author/locator, which really do belong to whichever edit is newest. But
    /// `furthestProgress` is a high-water mark shared across every device that has ever opened
    /// the book, not a field like any other: a device that only renamed the book, and syncs
    /// that rename after this device finished a long reading session elsewhere, must not roll
    /// the mark back down to its own, lower value just because its edit happens to be newest.
    func testCloudSyncKeepsFurthestProgressAsAHighWaterMarkAcrossDevices() throws {
        let database = try AppDatabase(DatabaseQueue(), syncEnabled: true)
        let book = Book(
            id: "furthest-merge-book",
            title: "Original Title",
            filePath: "Books/furthest-merge-book/book.epub",
            addedAt: Date(timeIntervalSince1970: 100)
        )
        try database.saveBook(book)
        try database.updateReadingProgress(
            id: book.id,
            progress: 0.8,
            locator: nil,
            lastOpenedAt: Date(timeIntervalSince1970: 200)
        )
        XCTAssertEqual(
            try XCTUnwrap(database.fetchBook(id: book.id)).furthestProgress, 0.8, accuracy: 0.0001
        )

        // The incoming record: renamed on another device, whose own furthest read is genuinely
        // only 30%. Its `modifiedAt` is newer, so the whole-record accept check must let it in.
        let remoteBook = Book(
            id: book.id,
            title: "Renamed Elsewhere",
            filePath: book.filePath,
            addedAt: book.addedAt,
            progress: 0.3,
            furthestProgress: 0.3
        )
        let accepted = try database.applyRemoteBook(
            remoteBook,
            tags: nil,
            modifiedAt: Date(timeIntervalSince1970: 300),
            systemFields: Data()
        )
        XCTAssertTrue(accepted)

        let merged = try XCTUnwrap(database.fetchBook(id: book.id))
        XCTAssertEqual(merged.title, "Renamed Elsewhere")
        XCTAssertEqual(merged.progress, 0.3, accuracy: 0.0001)
        XCTAssertEqual(
            merged.furthestProgress, 0.8, accuracy: 0.0001,
            "a lower remote high-water mark must not roll back a higher local one"
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
