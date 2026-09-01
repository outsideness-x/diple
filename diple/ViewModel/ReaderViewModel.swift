import Foundation
import Combine
import OSLog
import SwiftUI
import ReadiumShared
import ReadiumStreamer
import ReadiumNavigator

/// The live selection, reduced to the three things the app actually does anything with.
///
/// Readium's own `Selection` would say the same, but it is a `public struct` with no public
/// initialiser, so nothing outside ReadiumNavigator can make one — a navigator is the only
/// source of a selection in the entire process, tests included. That was survivable while a
/// settled selection wrote a highlight on the spot, because there was no state in between to
/// examine. Deferred creation puts one there: a passage the reader is looking at with nothing
/// written for it, whose defining property is that it has touched neither SQLite nor the
/// CloudKit outbox. Snapshotting at the navigator boundary is what makes that property
/// checkable rather than merely intended.
public struct PendingSelection: Equatable {
    /// The selected text, already trimmed. Never empty — see `init?(_:)`.
    public let quote: String
    public let locator: Locator
    /// Bounding rect of the selection in the navigator view's coordinate space, which is what
    /// the actions bar reads to choose the far edge of the page.
    public let frame: CGRect?

    public init(quote: String, locator: Locator, frame: CGRect?) {
        self.quote = quote
        self.locator = locator
        self.frame = frame
    }

    /// `nil` for a selection with no readable text in it, which is not worth raising a bar for.
    public init?(_ selection: Selection) {
        let quote = (selection.locator.text.highlight ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quote.isEmpty else { return nil }
        self.init(quote: quote, locator: selection.locator, frame: selection.frame)
    }
}

/// The notes side of an open book, in the one shape the note editor asks for.
///
/// Four lists rather than four `@Published` properties, because they are read together and
/// written together: a save reloads all of them, and four separate publishes would send the
/// reader four renders for one write.
///
/// It carries the **whole** library's notes and books, not only this source's. The editor the
/// reader raises is `NoteDetailView` itself — the app's one note editor — and it resolves
/// `[[Wiki links]]`, offers a link menu and lists backlinks out of `all`. Handed only this
/// book's notes it would quietly be a lesser editor than the same screen in the notes tab: a
/// link written there would stop resolving here, which is exactly the kind of drift keeping one
/// editor exists to prevent.
public struct ReaderNotes: Equatable {
    /// Written about the source now open, newest first. This is the list the book's own
    /// apparatus shows.
    public var forThisBook: [NoteItem] = []
    /// Every note in the library, for wiki links, backlinks and related notes.
    public var all: [NoteItem] = []
    /// Every source, so the editor's "Change source" picker offers the same shelf it does in
    /// the notes tab.
    public var books: [Book] = []
    /// Every tag already in use, offered as suggestions. A tag typed in the reader and one
    /// typed on the board have to be the same word.
    public var tagSuggestions: [String] = []

    public init(
        forThisBook: [NoteItem] = [],
        all: [NoteItem] = [],
        books: [Book] = [],
        tagSuggestions: [String] = []
    ) {
        self.forThisBook = forThisBook
        self.all = all
        self.books = books
        self.tagSuggestions = tagSuggestions
    }
}

/// Everything the final page prints, captured at the moment it appears.
///
/// Keeping this as a value means the colophon never reaches back into SQLite while SwiftUI is
/// laying it out. The quote count in particular is a snapshot of the reader's already-loaded
/// highlights, not a query performed from `body`.
public struct FinishedColophon: Equatable, Sendable {
    public let title: String
    public let author: String
    public let date: Date
    public let quoteCount: Int
    public let readingEnd: ReadingEnd

    public init(
        title: String,
        author: String,
        date: Date,
        quoteCount: Int,
        readingEnd: ReadingEnd
    ) {
        self.title = title
        self.author = author
        self.date = date
        self.quoteCount = quoteCount
        self.readingEnd = readingEnd
    }
}

@MainActor
public final class ReaderViewModel: ObservableObject {
    public let book: Book
    @Published public var publication: Publication? = nil
    @Published public var initialLocator: Locator? = nil
    @Published public var currentProgress: Double = 0.0
    /// The publication-derived boundary between the main text and its back matter.
    @Published public private(set) var readingEnd: ReadingEnd = .wholeBook
    /// A frozen description of the final page while it is on screen.
    @Published public var finishedColophon: FinishedColophon?
    /// Navigation is owned by the container; the view model only raises this signal after the
    /// completion write succeeds.
    @Published public var isSecondReadPresented = false
    /// Prose length of this source, resolved once when the book opens.
    ///
    /// The navigator reports a location on every scrolled pixel (see the Readium notes in
    /// CLAUDE.md), so this cannot be a lookup the bottom bar performs while rendering — that
    /// would be a database read per pixel. `nil` means the indexer has not measured this source
    /// yet, and the bar must then print nothing rather than a placeholder.
    @Published public private(set) var contentCharacters: Int?
    @Published public var isOverlayVisible: Bool = false
    @Published public var isSettingsPresented: Bool = false
    @Published public var isOutlinePresented: Bool = false
    @Published public var isSearchPresented: Bool = false
    // Every deliberate move through the book — outline, search hit, bookmark, a drag of the
    // progress bar, a step back through link history — ends by setting one of these two. That
    // makes them the one place the speed sampler has to be told, instead of five call sites a
    // sixth can be added beside without noticing. Clearing them back to nil is the navigator
    // reporting the jump handled, which is not itself a jump.
    @Published public var targetLink: ReadiumShared.Link? = nil {
        didSet {
            if targetLink != nil {
                abandonSpeedSample()
                canOfferColophonAfterCrossing = false
            }
        }
    }
    @Published public var targetLocator: Locator? = nil {
        didSet {
            if targetLocator != nil {
                abandonSpeedSample()
                canOfferColophonAfterCrossing = false
            }
        }
    }
    @Published public var tableOfContents: [ReadiumShared.Link] = []
    @Published public var highlights: [Highlight] = [] {
        didSet { synchronizeLivingMargins() }
    }
    /// A transient projection of highlights carrying personal writing. Readium receives this
    /// list as semantic locator decorations; no marker position is persisted.
    @Published public private(set) var livingMarginAnnotations: [LivingMarginAnnotation] = []
    @Published public private(set) var activeLivingMarginID: String? = nil
    @Published public var bookmarks: [Bookmark] = []
    /// The notes workspace, as the reader sees it.
    @Published public private(set) var notes = ReaderNotes()
    /// Passages kept beside this one open reader. This value has no database or CloudKit path;
    /// releasing the view model releases the shelf.
    @Published public private(set) var quoteStore = ReadingSessionQuoteStore()
    /// The in-process native drag currently originating from the page. The drop destination
    /// uses this semantic value rather than trying to reconstruct a locator from plain text.
    @Published public private(set) var activeQuoteDrag: QuoteReference? = nil
    /// A short-lived Readium decoration after a shelf jump. It never enters `highlights`.
    @Published public private(set) var sourceEmphasisLocator: Locator? = nil
    /// The passage under the reader's finger, before any decision about it.
    ///
    /// Non-nil is the bar's `pending` state: something is selected and **nothing has been
    /// written**. It is cleared by `createHighlight` — the tap that saves — by a tap away, and
    /// by dismissing the bar; each of those also takes the blue span and its handles off the
    /// page, because the navigator mirrors this through `hasSelection`.
    @Published public var currentSelection: PendingSelection? = nil
    /// The highlight the reader has tapped, and the rect it occupies on the page.
    ///
    /// A selection no longer raises anything — it saves a highlight and gets out of the way —
    /// so this is what the actions bar hangs on instead. The rect comes from Readium's
    /// decoration-activated event and is in the navigator's own coordinate space, the same
    /// space `Selection.frame` used to arrive in, which is what lets the bar pick its edge the
    /// same way it always did.
    @Published public var activeHighlight: Highlight? = nil
    @Published public var activeHighlightRect: CGRect? = nil
    @Published public var currentLocator: Locator? = nil
    @Published public var isAddBookmarkPresented: Bool = false
    /// Everywhere this sitting has jumped from, and everywhere a step back has undone.
    @Published public private(set) var trail = ReadingTrail()
    /// Whether the way back is currently naming where it leads.
    ///
    /// **The label is transient; the control is not.** This was `isReturnOfferVisible`, and it
    /// took the whole control away with it after ninety seconds — so a reader who jumped, read
    /// a page and only then wanted to go back had nothing left to press, while the stack that
    /// could have taken them there was still in memory with no way in. Losing your place is the
    /// one failure this part of the reader exists to prevent, so the timer now retires only the
    /// words: the control stands for as long as there is somewhere to return to, contracted to
    /// a quiet tab (see `ReadingTrailPill`).
    @Published public private(set) var isTrailLabelVisible: Bool = false
    @Published public var settings: ReaderSettings {
        didSet {
            AppSettingsManager.shared.settings.readerSettings = settings
            AppSettingsManager.shared.settings.defaultScrollReadingMode = (settings.readingMode == .scroll)
        }
    }
    @Published public var isLoading: Bool = true
    @Published public var errorMessage: String? = nil
    /// Short confirmation shown over the page, e.g. after saving a bookmark.
    @Published public var toast: String? = nil
    /// Flat position list, used to turn a progress-bar drag into a real location.
    @Published public private(set) var positions: [Locator] = []

    /// Whether the note editor has written anything since it was raised. Read and cleared by
    /// `announceSavedNote` when the editor leaves.
    private var hasSavedNoteWhileEditing = false

    private var persistTask: Task<Void, Never>? = nil
    private var progressWriteTask: Task<Void, Never>? = nil
    private var toastTask: Task<Void, Never>? = nil
    private var trailLabelTask: Task<Void, Never>? = nil
    private var sourceEmphasisTask: Task<Void, Never>? = nil
    /// The offer is session-scoped: dismissing it never turns the next locator callback into a
    /// second offer.
    private var hasOfferedColophon = false
    /// True only after this session has genuinely occupied a position before the resolved end.
    /// Deliberate targets clear it in their shared `didSet`; arriving below the boundary arms it
    /// again, while arriving beyond the boundary stays silent.
    private var canOfferColophonAfterCrossing = false
    /// Once completion has been written, ordinary reader teardown must not immediately replace
    /// `progress = 1` with the locator's fractional progression.
    private var hasFinishedReading = false

    /// A shelf jump is a detour, not reading progress. The origin payload is kept separately so
    /// a reader closed while looking at an earlier passage still reopens where reading stopped.
    private struct NearbySourceDetour {
        let originLocator: Locator
        let originProgress: Double
    }
    private var nearbySourceDetour: NearbySourceDetour? = nil
    /// How long the way back spells out where it leads before contracting to its glyph.
    ///
    /// Long enough to read six words without hurrying, short enough that the page is the page
    /// again by the time the next paragraph is. It ends the *sentence*, not the offer — the
    /// control itself has no lifetime, see `isTrailLabelVisible`.
    private static let trailLabelLifetime: Duration = .seconds(7)
    private var isReturningFromNearbySource = false

    /// Watches the positions the navigator reports and picks out the stretches that were
    /// actually read. `nil` until the book's length is known, and for sources the indexer has
    /// never measured — there is no way to turn a fraction of an unknown length into
    /// characters.
    private var speedSampler: ReadingSpeedSampler? = nil
    /// This session's accepted samples, summed rather than written one at a time.
    ///
    /// Folding each sample into `AppSettings` as it arrived would put a UserDefaults write and
    /// a CloudKit outbox row on roughly every two pages, for a number nobody is waiting on. One
    /// session is also the better statistical unit: its average is taken over the whole sitting
    /// instead of over whichever two pages happened to close a window.
    private var sessionCharacters: Double = 0
    private var sessionSeconds: Double = 0
    /// The reading position is written on a timer as the page scrolls, so a failing write
    /// fails repeatedly. The reader is told once and then left to read.
    private var hasReportedProgressFailure = false

    /// `print` goes nowhere in a shipped build. These are the failures behind a quote that
    /// did not save or a position that did not stick, which is exactly what a bug report
    /// needs to name.
    fileprivate nonisolated static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "diple",
        category: "reader"
    )

    private let httpClient = DefaultHTTPClient()
    private lazy var assetRetriever = AssetRetriever(httpClient: httpClient)
    private lazy var publicationOpener = PublicationOpener(
        parser: DefaultPublicationParser(
            httpClient: httpClient,
            assetRetriever: assetRetriever,
            pdfFactory: DefaultPDFDocumentFactory()
        )
    )

    /// A search-result locator that wins over the book's saved position for this one
    /// presentation only. It is never written into `currentLocator`/`currentProgress` up
    /// front — `openBook()` hands it to the navigator as where to open, and the saved
    /// position only actually moves once the navigator's own `onLocationChanged` confirms it
    /// got there (see `saveLocation`). A bounce back out before that never touches progress.
    private let startingLocator: Locator?

    /// The library this reader reads and writes.
    ///
    /// Injected rather than reached for, and defaulted to the singleton so no call site
    /// changes. The one thing worth proving about deferred creation — that a pending selection
    /// leaves no row and no outbox entry behind — cannot be proved against a database that
    /// resolves itself once per process and lives in Application Support.
    private let database: AppDatabase

    /// Releasing this object must not need the main actor.
    ///
    /// The project compiles with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so every class in
    /// it — this one included — gets an *isolated* deinit, and the runtime routes that through
    /// `swift_task_deinitOnExecutorMainActorBackDeploy`. Released from a plain synchronous main
    /// thread rather than from inside a task, that shim aborts in libmalloc
    /// ("pointer being freed was not allocated") before a single stored property is touched.
    /// Nothing here needs isolation to be torn down — the tasks are cancelled by their own
    /// `deinit`, and the rest are values and `Sendable` references — so the isolation is
    /// declined rather than back-deployed.
    nonisolated deinit {}

    public init(book: Book, startingLocator: Locator? = nil, database: AppDatabase = .shared) {
        self.book = book
        self.startingLocator = startingLocator
        self.database = database
        self.currentProgress = book.progress
        self.settings = AppSettingsManager.shared.settings.readerSettings
        loadHighlights()
        loadBookmarks()
        loadNotes()
    }

    public func loadHighlights() {
        do {
            self.highlights = try database.fetchHighlights(forBookId: book.id)
        } catch {
            // Saying nothing would show the book with none of its quotes on it, which reads
            // as "they are gone" rather than "they could not be read".
            Self.log.error("Failed to fetch highlights: \(error, privacy: .public)")
            showToast("Could not load your quotes")
        }
    }

    public var activeLivingMargin: LivingMarginAnnotation? {
        guard let activeLivingMarginID else { return nil }
        return livingMarginAnnotations.first { $0.id == activeLivingMarginID }
    }

    /// Opens the marker's thought, or closes it when the same marker is activated again.
    public func toggleLivingMargin(id: String) {
        guard livingMarginAnnotations.contains(where: { $0.id == id }) else {
            closeLivingMargin()
            return
        }
        if activeLivingMarginID == id {
            closeLivingMargin()
        } else {
            prepareForLivingMargin()
            activeLivingMarginID = id
        }
    }

    /// Edge swipes do not guess from screen geometry. They compare the current Readium locator
    /// with the same locators the markers use and open the nearest thought in book order.
    public func openNearestLivingMargin() {
        guard let nearest = LivingMarginAnnotations.nearest(
            to: currentLocator ?? initialLocator,
            in: livingMarginAnnotations
        ) else {
            closeLivingMargin()
            return
        }
        prepareForLivingMargin()
        activeLivingMarginID = nearest.id
    }

    /// A further left swipe while the margin is open walks forward without wrapping the last
    /// thought back to the first one.
    public func advanceLivingMargin() {
        guard let activeLivingMarginID,
              let index = livingMarginAnnotations.firstIndex(where: { $0.id == activeLivingMarginID }),
              livingMarginAnnotations.indices.contains(index + 1)
        else { return }
        self.activeLivingMarginID = livingMarginAnnotations[index + 1].id
    }

    public func retreatLivingMargin() {
        guard let activeLivingMarginID,
              let index = livingMarginAnnotations.firstIndex(where: { $0.id == activeLivingMarginID }),
              index > livingMarginAnnotations.startIndex
        else { return }
        self.activeLivingMarginID = livingMarginAnnotations[index - 1].id
    }

    public func closeLivingMargin() {
        activeLivingMarginID = nil
    }

    public func highlightForActiveLivingMargin() -> Highlight? {
        guard let activeLivingMarginID else { return nil }
        return highlights.first { $0.id == activeLivingMarginID }
    }

    private func synchronizeLivingMargins() {
        let annotations = LivingMarginAnnotations.make(from: highlights)
        livingMarginAnnotations = annotations
        if let activeLivingMarginID,
           !annotations.contains(where: { $0.id == activeLivingMarginID }) {
            self.activeLivingMarginID = nil
        }
    }

    private func prepareForLivingMargin() {
        dismissHighlightActions()
        currentSelection = nil
        isOverlayVisible = false
    }

    public func loadBookmarks() {
        do {
            self.bookmarks = try database.fetchBookmarks(forBookId: book.id)
        } catch {
            Self.log.error("Failed to fetch bookmarks: \(error, privacy: .public)")
            showToast("Could not load your bookmarks")
        }
    }

    // MARK: - Notes

    /// The tag every note written inside this book is born with. `nil` for a source whose title
    /// normalises to nothing, which is the same answer a hand-typed `#` gets.
    public var noteTag: String? {
        TagName.forSource(titled: book.title)
    }

    public func loadNotes() {
        do {
            let tagsByNote = try database.fetchTagsByNote()
            let books = try database.fetchAllBooks()
            let booksByID = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
            notes = ReaderNotes(
                forThisBook: try database.fetchNotes(forBookID: book.id).map {
                    NoteItem(note: $0, tags: tagsByNote[$0.id] ?? [], book: book)
                },
                all: try database.fetchAllNotes().map {
                    NoteItem(note: $0, tags: tagsByNote[$0.id] ?? [], book: $0.bookId.flatMap { booksByID[$0] })
                },
                books: books,
                tagSuggestions: try database.fetchAllTags()
            )
        } catch {
            // Same reasoning as the quotes above: an empty list reads as "they are gone"
            // rather than "they could not be read".
            Self.log.error("Failed to fetch notes: \(error, privacy: .public)")
            showToast("Could not load your notes")
        }
    }

    /// Writes a note from the editor raised over the page.
    ///
    /// The editor autosaves on a debounce and reports whether the row actually landed, so the
    /// result is passed straight back rather than swallowed — a failed write must not look
    /// like a save. Nothing is announced here for the same reason: this runs every few
    /// keystrokes, behind a sheet the toast could not be seen through. The page says it once,
    /// when the editor leaves — see `announceSavedNote`.
    @discardableResult
    public func saveNote(_ note: Note, tags: [String]) -> Bool {
        do {
            var updated = note
            updated.updatedAt = Date()
            try database.saveNote(updated, tags: tags)
            hasSavedNoteWhileEditing = true
            loadNotes()
            return true
        } catch {
            Self.log.error("Failed to save note: \(error, privacy: .public)")
            showToast("Could not save your note")
            return false
        }
    }

    public func deleteNote(_ item: NoteItem) {
        do {
            try database.deleteNote(id: item.id)
            loadNotes()
        } catch {
            Self.log.error("Failed to delete note: \(error, privacy: .public)")
            showToast("Could not delete your note")
        }
    }

    /// Confirms, on the page, that the thought was kept — once per editing session, and only
    /// if something was actually written.
    public func announceSavedNote() {
        guard hasSavedNoteWhileEditing else { return }
        hasSavedNoteWhileEditing = false
        showToast("Note saved")
    }

    public func openBook() async {
        isLoading = true
        let absoluteFileURL = BookStorageService.shared.absoluteURL(for: book.filePath)
        guard let absoluteURL = absoluteFileURL.anyURL.absoluteURL else {
            errorMessage = "Invalid book file path"
            isLoading = false
            return
        }

        do {
            let asset = try await assetRetriever.retrieve(url: absoluteURL).get()
            let pub = try await publicationOpener.open(asset: asset, allowUserInteraction: true).get()

            // The navigators throw on restricted publications; catch it here so the reader
            // shows an error instead of trapping inside `makeUIViewController`.
            guard !pub.isRestricted else {
                self.errorMessage = "This book is protected and cannot be opened."
                self.isLoading = false
                return
            }

            var savedLocator: Locator? = nil
            if let locatorStr = book.locator {
                savedLocator = Locator.from(jsonString: locatorStr)
            }

            let toc = (try? await pub.tableOfContents().get()) ?? pub.manifest.tableOfContents

            self.publication = pub
            self.tableOfContents = toc
            self.initialLocator = startingLocator ?? savedLocator
            // A search hit is a presentation-time override the navigator has not confirmed
            // yet: seeding `currentLocator` from it here, before the navigator has actually
            // rendered there, would let a close-before-render persist a position the reader
            // never really showed. Without an override this matches the previous behaviour
            // exactly — saved locator in, saved locator back out.
            if startingLocator == nil {
                self.currentLocator = savedLocator
                if let savedLocator {
                    self.currentProgress = progress(for: savedLocator)
                }
            }
            self.isLoading = false
            self.contentCharacters = try? database.contentCharacterCount(
                bookID: book.id,
                isArticle: book.isArticle
            )
            self.speedSampler = ReadingSpeedSampler(totalCharacters: self.contentCharacters)

            // Computing positions can take a moment on large books; the reader is usable
            // without them, only the progress bar cannot be dragged yet.
            self.positions = (try? await pub.positions().get()) ?? []
            self.readingEnd = ReadingEnd.resolve(
                landmarks: pub.landmarks,
                tableOfContents: toc,
                readingOrder: pub.readingOrder,
                positions: positions
            )
            let openingProgress = initialLocator.map(progress(for:)) ?? currentProgress
            self.canOfferColophonAfterCrossing = openingProgress < readingEnd.progression
        } catch {
            self.errorMessage = "Failed to open book: \(error.localizedDescription)"
            self.isLoading = false
        }
    }

    public func saveLocation(_ locator: Locator) {
        self.currentLocator = locator
        self.currentProgress = progress(for: locator)
        if currentProgress < readingEnd.progression {
            canOfferColophonAfterCrossing = true
        }
        offerFinishedColophonIfNeeded()
        guard finishedColophon == nil else {
            abandonSpeedSample()
            return
        }
        guard nearbySourceDetour == nil else {
            abandonSpeedSample()
            return
        }
        if let sample = speedSampler?.observe(progress: currentProgress) {
            sessionCharacters += sample.characters
            sessionSeconds += sample.seconds
        }
        schedulePersist()
    }

    private func offerFinishedColophonIfNeeded() {
        guard currentProgress >= readingEnd.progression,
              book.progress < 0.995,
              !hasOfferedColophon,
              canOfferColophonAfterCrossing
        else { return }

        hasOfferedColophon = true
        canOfferColophonAfterCrossing = false
        cancelPendingProgressWrites()
        isOverlayVisible = false
        currentSelection = nil
        dismissHighlightActions()
        closeLivingMargin()
        finishedColophon = FinishedColophon(
            title: book.title,
            author: book.author ?? "Unknown Author",
            date: Date(),
            quoteCount: highlights.count,
            readingEnd: readingEnd
        )
    }

    /// Accepts the proposed boundary and keeps the saved locator exactly where it is.
    public func finishReading() {
        _ = completeReading()
    }

    /// Accepts completion first; Second Read is opened only after that write succeeds.
    public func finishAndOpenSecondRead() {
        guard completeReading() else { return }
        isSecondReadPresented = true
    }

    /// Rejects the proposal for this session. Ordinary location persistence continues.
    public func keepReading() {
        finishedColophon = nil
    }

    @discardableResult
    private func completeReading() -> Bool {
        cancelPendingProgressWrites()
        flushReadingSpeed()

        do {
            try database.markBookAsFinished(id: book.id)
            hasFinishedReading = true
            currentProgress = 1
            finishedColophon = nil
            return true
        } catch {
            Self.log.error("Failed to mark book as finished: \(error, privacy: .public)")
            showToast("Could not finish this book")
            return false
        }
    }

    /// Drops the stretch being measured without counting it. Every deliberate move through the
    /// book is one of these: it covers ground in no time and would read as impossibly fast.
    private func abandonSpeedSample() {
        speedSampler?.invalidate()
    }

    /// Writes this session's measured pace into the reader's own figure.
    ///
    /// Called when the reader closes and when the app leaves the foreground, which are the two
    /// moments the session is over — the second because a session that ends by being killed in
    /// the background would otherwise be lost. Safe to call repeatedly: the totals are cleared
    /// as they are spent, so a second call with nothing new folds nothing.
    public func flushReadingSpeed() {
        abandonSpeedSample()
        guard sessionCharacters > 0, sessionSeconds > 0 else { return }
        let characters = sessionCharacters
        let seconds = sessionSeconds
        sessionCharacters = 0
        sessionSeconds = 0
        AppSettingsManager.shared.settings.readingSpeed.record(
            characters: characters,
            seconds: seconds,
            // The publication's own metadata, not the title heuristic the shelf falls back to:
            // a sample filed under the wrong script is wrong for the whole library, where a row
            // guessed wrong is wrong for one row. See `Book.script`.
            script: script
        )
    }

    /// The script the book is set in, resolved once the publication is open.
    ///
    /// Metadata is the reliable signal; the title is the fallback for the many EPUBs that
    /// declare no language or declare the wrong one. This is the precise answer, and it is what
    /// a *measurement* is filed under — what the interface prints estimates with is the shelf's
    /// own `Book.script`, for the reasons recorded there.
    public var script: ReaderScript {
        ReaderScript.detect(
            languages: publication?.metadata.languages ?? [],
            sample: book.title
        )
    }

    /// Preferences with the book's own script folded in. Views read this rather than
    /// `settings.epubPreferences`, which cannot see the publication.
    public var epubPreferences: EPUBPreferences {
        settings.epubPreferences(for: script)
    }

    /// Reading-system CSS for this book's script — line breaking, link colour and selection
    /// colour, none of which is a user preference and none of which has an `EPUBPreferences`
    /// field. Read once, when the navigator is built; a book does not change the script it is
    /// written in halfway through, and colour here cannot follow a live theme switch on its own
    /// (see the "Readium" note in CLAUDE.md).
    ///
    /// **The four named page themes ended up not needing this file touched at all.** Selection
    /// colour is a fixed brass regardless of theme, and link colour is `currentColor` — not a
    /// snapshot, a live reference that tracks whatever `--USER__textColor`/`--RS__textColor`
    /// currently resolves to, so it already follows a theme switch for free. The page's own
    /// background/ink went through `EPUBPreferences.backgroundColor`/`.textColor` instead, set
    /// in `ReaderSettings.epubPreferences(for:)`: unlike RS properties, those are
    /// live-updatable through `submitPreferences` (see "Вёрстка страницы читалки" in
    /// CLAUDE.md).
    ///
    /// **Link colour turned out not to be publisher CSS.** Turning off publisher styles was
    /// checked first, per the reasoning that a book which keeps writing its own alignment and
    /// leading might also be painting its own links — it does not: `ReadiumCSS-after.css`'s own
    /// night/sepia presets set `--RS__linkColor` to a WebKit-native blue
    /// (`readium-css/ReadiumCSS-after.css`, `:root[style*="readium-night-on"] a:link`) with
    /// `!important`, regardless of `publisherStyles`. Verified live: Dorian Gray's front matter
    /// still showed the same blue with publisher styles off. So the colour is set here.
    /// `currentColor` — legal CSS, and per spec treated as `inherit` when used for `color`
    /// itself — makes a link read as the surrounding ink rather than a UI hyperlink; the
    /// underline WebKit already draws is what marks it tappable. This also keeps links out of
    /// the accent budget in CLAUDE.md (progress fill / control selection / one primary action
    /// per screen — a link is none of the three).
    public var readiumCSSRSProperties: CSSRSProperties {
        CSSRSProperties(
            selectionBackgroundColor: CSSHexColor(Self.selectionBackgroundColorCSS),
            linkColor: CSSHexColor("currentColor"),
            visitedColor: CSSHexColor("currentColor"),
            overrides: script.cssOverrides
        )
    }

    /// Brass at low opacity, not iOS's system blue — the selection is the gesture the whole
    /// highlight feature starts from, and it is the one place the platform's own palette showed
    /// through onto the page. 35% keeps the selected words legible through the tint rather than
    /// painting over them; `CSSRGBColor` has no alpha channel, so the value is written as a raw
    /// `rgba()` string through `CSSHexColor`, which — despite the name — just forwards whatever
    /// CSS text it is given (see `CSSHexColor.css()` in `CSSProperties.swift`).
    private static let selectionBackgroundColorCSS = "rgba(200, 164, 92, 0.35)"

    /// `totalProgression` is only present when the publication exposes a position list.
    /// Otherwise we approximate it from the resource index inside the reading order.
    private func progress(for locator: Locator) -> Double {
        let calculated: Double
        if let totalProgression = locator.locations.totalProgression {
            calculated = totalProgression
        } else if let pub = publication, !pub.readingOrder.isEmpty,
                  let index = pub.readingOrder.firstIndexWithHREF(locator.href) {
            let chapterProgression = locator.locations.progression ?? 0.0
            calculated = (Double(index) + chapterProgression) / Double(pub.readingOrder.count)
        } else if let chapterProgression = locator.locations.progression {
            calculated = chapterProgression
        } else {
            calculated = currentProgress
        }
        return min(max(calculated, 0.0), 1.0)
    }

    /// The navigator reports a new location on every scrolled pixel. Writing to SQLite that
    /// often stutters the reading experience, so persistence is coalesced and moved off the
    /// main actor. `flushPendingProgress()` forces the last value out when the reader closes.
    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self?.persistProgress()
        }
    }

    /// Writes the last known position immediately. Called when the reader closes so the
    /// library grid can be refreshed with a value that is already in the database.
    public func flushPendingProgress() {
        cancelPendingProgressWrites()
        flushReadingSpeed()
        guard let payload = progressPayload() else { return }
        // Called as the reader closes: there is no longer a page to put a toast on, and the
        // failure is already in the log.
        _ = Self.write(payload, to: database)
    }

    private func cancelPendingProgressWrites() {
        persistTask?.cancel()
        persistTask = nil
        progressWriteTask?.cancel()
        progressWriteTask = nil
    }

    private func persistProgress() {
        guard let payload = progressPayload() else { return }
        progressWriteTask?.cancel()
        progressWriteTask = Task.detached(priority: .utility) { [weak self, database] in
            guard !Task.isCancelled else { return }
            guard !Self.write(payload, to: database) else { return }
            await self?.reportProgressFailure()
        }
    }

    private func progressPayload() -> ProgressPayload? {
        guard !hasFinishedReading else { return nil }
        if let detour = nearbySourceDetour {
            return ProgressPayload(
                bookId: book.id,
                progress: detour.originProgress,
                locator: try? detour.originLocator.jsonString()
            )
        }
        guard let locator = currentLocator else { return nil }
        return ProgressPayload(
            bookId: book.id,
            progress: currentProgress,
            locator: try? locator.jsonString()
        )
    }

    private struct ProgressPayload: Sendable {
        let bookId: String
        let progress: Double
        let locator: String?
    }

    /// Returns whether the position actually reached the database.
    @discardableResult
    /// Takes the database as an argument rather than reading the instance's own: this is
    /// `nonisolated static` on purpose — position writes must not run on the main actor — and
    /// a static has no instance to ask. `AppDatabase` is `Sendable`, so it crosses with the
    /// payload.
    private nonisolated static func write(_ payload: ProgressPayload, to database: AppDatabase) -> Bool {
        do {
            try database.updateReadingProgress(
                id: payload.bookId,
                progress: payload.progress,
                locator: payload.locator
            )
            return true
        } catch {
            log.error("Failed to save reading progress: \(error, privacy: .public)")
            return false
        }
    }

    /// Losing the reading position is worth knowing about — reopening the book somewhere
    /// else is otherwise inexplicable — but only once: the write repeats as the page scrolls.
    private func reportProgressFailure() {
        guard !hasReportedProgressFailure else { return }
        hasReportedProgressFailure = true
        showToast("Could not save your place")
    }

    /// Remembers a place a jump is departing from, and offers the way back to it.
    ///
    /// Called straight from the navigators, which is why it stays public and keeps its name:
    /// following a link inside the book is the one jump the app does not initiate and cannot
    /// record for itself.
    public func pushBackLocation(_ locator: Locator) {
        trail.record(locator)
        showTrailLabel()
    }

    /// Remembers where reading was, so the jump about to happen can be undone.
    ///
    /// Called by every deliberate move through the book. Only a link jump used to record one,
    /// which left the accidents unrecoverable: a progress bar brushed on the way to the toolbar,
    /// or the wrong line tapped in the outline, overwrote the reading position and kept no copy
    /// of it, so there was nowhere to go but hunt for the page by hand.
    private func recordReturnPoint() {
        guard let origin = currentLocator ?? initialLocator else { return }
        pushBackLocation(origin)
    }

    /// Lets the way back say where it leads, and restarts the countdown on those words.
    ///
    /// It retires the sentence, never the trail: the stack is what `goBackInHistory` walks, and
    /// clearing it on a timer is precisely the bug this replaced.
    private func showTrailLabel() {
        guard trail.canGoBack || trail.canGoForward else { return }
        isTrailLabelVisible = true
        trailLabelTask?.cancel()
        trailLabelTask = Task { [weak self] in
            try? await Task.sleep(for: Self.trailLabelLifetime)
            guard !Task.isCancelled else { return }
            self?.isTrailLabelVisible = false
        }
    }

    /// Takes the words off the control, and nothing else.
    ///
    /// Not `private`: this is the whole of what the countdown does, and a test that calls it
    /// directly is asserting what it does *not* touch — the trail — without waiting out a
    /// lifetime to do so.
    func hideTrailLabel() {
        trailLabelTask?.cancel()
        trailLabelTask = nil
        isTrailLabelVisible = false
    }

    /// One step back along the trail, and the step just taken becomes the way forward.
    public func goBackInHistory() {
        guard let destination = trail.stepBack(leaving: currentLocator) else { return }
        // Arriving at the origin is what ends a shelf detour, and the origin is recognised by
        // where it is rather than by how deep the stack was when it was pushed. Counting was
        // exact only while every jump pushed exactly one entry; the trail now folds a locator
        // that repeats a report it has already taken, so a depth is no longer an identity.
        if let detour = nearbySourceDetour,
           ReadingTrail.isSameSpot(destination, as: detour.originLocator) {
            isReturningFromNearbySource = true
        }
        self.targetLocator = destination
        // Every step names the next one. Walking back out of a chain of notes is the moment a
        // reader most needs to be told what one more tap would do — and the step that empties
        // the trail behind is answered by the forward step it has just created, so the note
        // they may have overshot says so rather than becoming a bare arrow.
        showTrailLabel()
    }

    /// What the way back promises, in words: the chapter it leads to, or the position when the
    /// publication names none. `nil` when there is nowhere behind.
    public var backDestinationLabel: String? {
        trail.backDestination.map(ReadingTrail.label(for:))
    }

    /// The same, for the step that undoes a step back.
    public var forwardDestinationLabel: String? {
        trail.forwardDestination.map(ReadingTrail.label(for:))
    }

    /// One step forward, undoing a step back.
    ///
    /// A chain of jumps is walked back a step at a time, and a reader who overshoots — the
    /// commonest single mistake in the reader, one reflex tap past the note they were reading —
    /// gets the note back for one tap instead of hunting for its marker in the text again.
    ///
    /// Deliberately ordinary navigation, including out of a shelf detour: by the time a step
    /// back has landed on the origin the detour is over, and a reader who then presses forward
    /// is choosing to be at the held passage rather than glancing at it.
    public func goForwardInHistory() {
        guard let destination = trail.stepForward(leaving: currentLocator) else { return }
        self.targetLocator = destination
        showTrailLabel()
    }

    public func navigateToLink(_ link: ReadiumShared.Link) {
        recordReturnPoint()
        self.targetLink = link
    }

    /// Whether the progress bar can be dragged to jump through the book.
    public var canSeek: Bool {
        !positions.isEmpty || (publication.map { $0.readingOrder.count > 1 } ?? false)
    }

    /// Jumps to a fraction of the whole publication, as picked on the progress bar.
    public func seek(toProgress target: Double) {
        let clamped = min(max(target, 0), 1)

        let nearest = positions.min { lhs, rhs in
            abs((lhs.locations.totalProgression ?? 0) - clamped)
                < abs((rhs.locations.totalProgression ?? 0) - clamped)
        }
        if let nearest {
            navigateToLocator(nearest)
            return
        }

        // No position list: fall back to the resource containing that fraction.
        guard let pub = publication, !pub.readingOrder.isEmpty else { return }
        let index = min(Int(clamped * Double(pub.readingOrder.count)), pub.readingOrder.count - 1)
        navigateToLink(pub.readingOrder[index])
    }

    public func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    /// Moves to a place in the book, remembering where reading was.
    ///
    /// `recordingReturn: false` is for the one caller that has already recorded the origin
    /// itself — `navigateToNearbySource`, which has to capture the stack depth *before* the
    /// push — and would otherwise put the same locator on the stack twice.
    public func navigateToLocator(_ locator: Locator, recordingReturn: Bool = true) {
        if recordingReturn {
            recordReturnPoint()
        }
        self.targetLocator = locator
    }

    /// Clears a target once Readium has completed the jump. Returning from the shelf origin is
    /// the precise moment a temporary detour becomes ordinary reading again.
    ///
    /// **The only way to report a jump handled**, and it has to stay the only one. It used to
    /// sit beside a `clearTargetLocator`/`clearTargetLink` pair that did the first two lines and
    /// nothing else, and the navigators called that pair — so this ran never, the shelf detour
    /// was never torn down, and `saveLocation` went on refusing to persist for the rest of the
    /// session. A second entry point that does most of the work is the shape of that bug.
    public func finishTargetNavigation() {
        targetLocator = nil
        targetLink = nil
        if isReturningFromNearbySource {
            isReturningFromNearbySource = false
            nearbySourceDetour = nil
            sourceEmphasisTask?.cancel()
            sourceEmphasisLocator = nil
        }
    }

    // MARK: - Keep Nearby

    public func quoteReference(for selection: PendingSelection) -> QuoteReference? {
        QuoteReference(book: book, selection: selection)
    }

    public func quoteReference(for highlight: Highlight) -> QuoteReference? {
        QuoteReference(book: book, highlight: highlight)
    }

    public func isKeptNearby(_ reference: QuoteReference) -> Bool {
        quoteStore.contains(reference)
    }

    @discardableResult
    public func keepNearby(_ reference: QuoteReference) -> Bool {
        guard reference.bookID == book.id else { return false }
        return quoteStore.add(reference)
    }

    @discardableResult
    public func removeFromNearby(_ reference: QuoteReference) -> Bool {
        quoteStore.remove(reference)
    }

    public func setActiveQuoteDrag(_ reference: QuoteReference?) {
        activeQuoteDrag = reference
    }

    /// Opens a held source without promoting the visited location to the reader's saved place.
    public func navigateToNearbySource(_ reference: QuoteReference) {
        guard reference.bookID == book.id else { return }

        if nearbySourceDetour == nil,
           let origin = currentLocator ?? initialLocator {
            nearbySourceDetour = NearbySourceDetour(
                originLocator: origin,
                originProgress: currentProgress
            )
            pushBackLocation(origin)
        }

        sourceEmphasisTask?.cancel()
        sourceEmphasisLocator = reference.locator
        sourceEmphasisTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_200))
            guard !Task.isCancelled else { return }
            self?.sourceEmphasisLocator = nil
        }
        navigateToLocator(reference.locator, recordingReturn: false)
        // Re-offer on every hop between held passages, not only on the one that opened the
        // detour: the origin is already on the trail and is still where reading left off.
        showTrailLabel()
    }

    /// Resolves the permanent annotation, if any, for a temporary reference.
    public func highlight(matching reference: QuoteReference) -> Highlight? {
        highlights.first { highlight in
            quoteReference(for: highlight)?.sourceKey == reference.sourceKey
        }
    }

    /// The explicit Add Note boundary: this is the only shelf action allowed to promote a
    /// temporary passage into the existing permanent highlight/note system.
    @discardableResult
    public func promoteToHighlight(
        _ reference: QuoteReference,
        colorHex: String
    ) -> Highlight? {
        if let existing = highlight(matching: reference) {
            return existing
        }
        guard reference.bookID == book.id,
              let locatorJSON = try? reference.locator.jsonString()
        else { return nil }

        let highlight = Highlight(
            bookId: book.id,
            locator: locatorJSON,
            text: reference.text,
            colorHex: colorHex,
            createdAt: Date()
        )
        do {
            try database.saveHighlight(highlight)
            loadHighlights()
            return highlight
        } catch {
            Self.log.error("Failed to promote nearby passage: \(error, privacy: .public)")
            showToast("Could not add a note")
            return nil
        }
    }

    /// Ends the session only when the reader itself leaves the hierarchy. Backgrounding and
    /// sheets call neither this method nor `clear`, so a short interruption keeps the shelf.
    public func endReadingSession() {
        flushPendingProgress()
        activeQuoteDrag = nil
        sourceEmphasisTask?.cancel()
        sourceEmphasisLocator = nil
        hideTrailLabel()
        // The trail ends with the sitting it describes. It is not persisted anywhere, so this
        // is not a discarded copy of something — it is the whole of it, and keeping it across a
        // close would offer to return to a page from a session the reader has already left.
        trail = ReadingTrail()
        quoteStore.clear()
    }

    /// A bookmark can only be anchored once the navigator has reported a position.
    public var canAddBookmark: Bool {
        (currentLocator ?? initialLocator) != nil
    }

    /// True when a bookmark already exists within ~0.5% of the current position, so the
    /// reader can show a filled bookmark icon instead of an outline.
    public var isCurrentPositionBookmarked: Bool {
        guard let current = (currentLocator ?? initialLocator) else { return false }
        return bookmarks.contains { bookmark in
            guard let locator = bookmark.parsedLocator,
                  locator.href.isEquivalentTo(current.href) else { return false }
            let saved = locator.locations.progression ?? 0
            let now = current.locations.progression ?? 0
            return abs(saved - now) < 0.005
        }
    }

    public func addBookmark(name: String, colorHex: String) {
        // Both of these end a tap on "Save" with nothing on screen unless they say so.
        guard let locator = currentLocator ?? initialLocator else {
            Self.log.error("Cannot add bookmark: no current locator")
            showToast("Could not save bookmark")
            return
        }
        guard let locatorJson = (try? locator.jsonString()) else {
            Self.log.error("Cannot add bookmark: failed to serialize locator")
            showToast("Could not save bookmark")
            return
        }

        let bookmark = Bookmark(
            bookId: book.id,
            locator: locatorJson,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Bookmark" : name,
            colorHex: colorHex,
            createdAt: Date()
        )

        do {
            try database.saveBookmark(bookmark)
            loadBookmarks()
            HapticManager.shared.impact(.medium)
            showToast("Bookmark saved")
        } catch {
            Self.log.error("Failed to save bookmark: \(error, privacy: .public)")
            showToast("Could not save bookmark")
        }
    }

    public func deleteBookmark(_ bookmark: Bookmark) {
        do {
            try database.deleteBookmark(id: bookmark.id)
            loadBookmarks()
        } catch {
            // The row stays on screen when this fails, so silence reads as an ignored tap.
            Self.log.error("Failed to delete bookmark: \(error, privacy: .public)")
            showToast("Could not delete bookmark")
        }
    }

    /// Saves the live selection as a highlight. The **only** thing in the reader that writes
    /// one: a selection on its own no longer does, and the bar's colour swatch is what calls
    /// this.
    ///
    /// `announce` is off for that swatch. The bar does not close on it — it turns from pending
    /// into committed on the spot, with the tapped colour ringed, the note lit and the delete
    /// button appearing — and a toast would both restate that and land on top of the bar
    /// saying it. It stays on for a thought, which is written in a sheet and so lands with the
    /// page out of sight.
    @discardableResult
    public func createHighlight(
        colorHex: String,
        comment: String? = nil,
        announce: Bool = true
    ) -> Highlight? {
        guard let selection = currentSelection else { return nil }
        let text = selection.quote
        guard let locatorJson = try? selection.locator.jsonString() else { return nil }

        let highlight = Highlight(
            bookId: book.id,
            locator: locatorJson,
            text: text,
            comment: comment,
            colorHex: colorHex,
            createdAt: Date()
        )

        var saved: Highlight?
        do {
            try database.saveHighlight(highlight)
            loadHighlights()
            HapticManager.shared.impact(.light)
            if announce {
                showToast(comment == nil ? "Highlight saved" : "Thought saved")
            }
            saved = highlight
        } catch {
            Self.log.error("Failed to save highlight: \(error, privacy: .public)")
            showToast("Could not save quote")
        }

        self.currentSelection = nil
        return saved
    }

    /// Recolours a highlight already on the page, leaving whatever thought is attached to it
    /// alone. `updateHighlight` takes the comment as a parameter and writes what it is given,
    /// so passing anything but the existing one here would quietly erase it.
    public func setHighlightColor(_ highlight: Highlight, to colorHex: String) {
        guard highlight.colorHex.caseInsensitiveCompare(colorHex) != .orderedSame else { return }
        updateHighlight(highlight, colorHex: colorHex, comment: highlight.comment)
    }

    /// Drops the actions bar. Separate from clearing `activeHighlight` at a call site so the
    /// rect goes with it — a stale rect would put the next bar on the wrong edge of the page.
    public func dismissHighlightActions() {
        activeHighlight = nil
        activeHighlightRect = nil
    }

    /// Always announced. It used to take an `announce:` flag for one caller that was not a
    /// reader deleting anything — the de-duplicator behind save-on-selection, which quietly
    /// removed the passage a resumed drag had already written. Deferred creation writes nothing
    /// mid-drag, so there is nothing to quietly remove, and every remaining call to this is a
    /// reader deliberately throwing a quote away.
    public func deleteHighlight(_ highlight: Highlight) {
        do {
            try database.deleteHighlight(id: highlight.id)
            loadHighlights()
            HapticManager.shared.notification(.success)
            showToast("Highlight deleted")
        } catch {
            Self.log.error("Failed to delete highlight: \(error, privacy: .public)")
            showToast("Could not delete quote")
        }
    }

    public func updateHighlight(_ highlight: Highlight, colorHex: String, comment: String?) {
        do {
            try database.updateHighlight(
                id: highlight.id,
                colorHex: colorHex,
                comment: comment
            )
            loadHighlights()
            HapticManager.shared.impact(.light)
            showToast("Highlight updated")
        } catch {
            Self.log.error("Failed to update highlight: \(error, privacy: .public)")
            showToast("Could not update highlight")
        }
    }

    public func toggleOverlay() {
        withAnimation(DipleMotion.standard) {
            isOverlayVisible.toggle()
        }
    }
}
