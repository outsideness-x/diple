import Foundation
import Combine
import OSLog
import SwiftUI
import ReadiumShared
import ReadiumStreamer
import ReadiumNavigator

@MainActor
public final class ReaderViewModel: ObservableObject {
    public let book: Book
    @Published public var publication: Publication? = nil
    @Published public var initialLocator: Locator? = nil
    @Published public var currentProgress: Double = 0.0
    @Published public var isOverlayVisible: Bool = false
    @Published public var isSettingsPresented: Bool = false
    @Published public var isOutlinePresented: Bool = false
    @Published public var isSearchPresented: Bool = false
    @Published public var targetLink: ReadiumShared.Link? = nil
    @Published public var targetLocator: Locator? = nil
    @Published public var tableOfContents: [ReadiumShared.Link] = []
    @Published public var highlights: [Highlight] = []
    @Published public var bookmarks: [Bookmark] = []
    @Published public var currentSelection: Selection? = nil
    @Published public var currentLocator: Locator? = nil
    @Published public var isAddBookmarkPresented: Bool = false
    @Published public var backLocationStack: [Locator] = []
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

    private var persistTask: Task<Void, Never>? = nil
    private var toastTask: Task<Void, Never>? = nil
    /// The reading position is written on a timer as the page scrolls, so a failing write
    /// fails repeatedly. The reader is told once and then left to read.
    private var hasReportedProgressFailure = false

    /// `print` goes nowhere in a shipped build. These are the failures behind a quote that
    /// did not save or a position that did not stick, which is exactly what a bug report
    /// needs to name.
    fileprivate static let log = Logger(
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

    public init(book: Book, startingLocator: Locator? = nil) {
        self.book = book
        self.startingLocator = startingLocator
        self.currentProgress = book.progress
        self.settings = AppSettingsManager.shared.settings.readerSettings
        loadHighlights()
        loadBookmarks()
    }

    public func loadHighlights() {
        do {
            self.highlights = try AppDatabase.shared.fetchHighlights(forBookId: book.id)
        } catch {
            // Saying nothing would show the book with none of its quotes on it, which reads
            // as "they are gone" rather than "they could not be read".
            Self.log.error("Failed to fetch highlights: \(error, privacy: .public)")
            showToast("Could not load your quotes")
        }
    }

    public func loadBookmarks() {
        do {
            self.bookmarks = try AppDatabase.shared.fetchBookmarks(forBookId: book.id)
        } catch {
            Self.log.error("Failed to fetch bookmarks: \(error, privacy: .public)")
            showToast("Could not load your bookmarks")
        }
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

            // Computing positions can take a moment on large books; the reader is usable
            // without them, only the progress bar cannot be dragged yet.
            self.positions = (try? await pub.positions().get()) ?? []
        } catch {
            self.errorMessage = "Failed to open book: \(error.localizedDescription)"
            self.isLoading = false
        }
    }

    public func saveLocation(_ locator: Locator) {
        self.currentLocator = locator
        self.currentProgress = progress(for: locator)
        schedulePersist()
    }

    /// Reading progress in `0...1` for the given locator.
    ///
    /// The script the book is set in, resolved once the publication is open. Metadata is the
    /// reliable signal; the title is the fallback for the many EPUBs that declare no language
    /// or declare the wrong one.
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
        persistTask?.cancel()
        persistTask = nil
        guard let payload = progressPayload() else { return }
        // Called as the reader closes: there is no longer a page to put a toast on, and the
        // failure is already in the log.
        _ = Self.write(payload)
    }

    private func persistProgress() {
        guard let payload = progressPayload() else { return }
        Task.detached(priority: .utility) { [weak self] in
            guard !Self.write(payload) else { return }
            await self?.reportProgressFailure()
        }
    }

    private func progressPayload() -> ProgressPayload? {
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
    private nonisolated static func write(_ payload: ProgressPayload) -> Bool {
        do {
            try AppDatabase.shared.updateReadingProgress(
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

    public func pushBackLocation(_ locator: Locator) {
        self.backLocationStack.append(locator)
    }

    public func goBackInHistory() {
        guard let previousLocator = backLocationStack.popLast() else { return }
        self.targetLocator = previousLocator
    }

    public func navigateToLink(_ link: ReadiumShared.Link) {
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
            self.targetLocator = nearest
            return
        }

        // No position list: fall back to the resource containing that fraction.
        guard let pub = publication, !pub.readingOrder.isEmpty else { return }
        let index = min(Int(clamped * Double(pub.readingOrder.count)), pub.readingOrder.count - 1)
        self.targetLink = pub.readingOrder[index]
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

    public func navigateToLocator(_ locator: Locator) {
        self.targetLocator = locator
    }

    /// The in-book search sheet's own entry into the same `navigateToLocator` path the outline
    /// sheet uses — the only difference is that a search jump also remembers where reading was,
    /// so the existing "Return to text" button (`backLocationStack`) can bring the reader home.
    /// An outline/bookmark/highlight jump does not push, because those already describe a place
    /// *in* the book the reader chose to visit, not a detour away from where they were reading.
    public func navigateToSearchResult(_ locator: Locator) {
        if let origin = currentLocator ?? initialLocator {
            pushBackLocation(origin)
        }
        navigateToLocator(locator)
    }

    public func clearTargetLocator() {
        self.targetLocator = nil
    }

    public func clearTargetLink() {
        self.targetLink = nil
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
            try AppDatabase.shared.saveBookmark(bookmark)
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
            try AppDatabase.shared.deleteBookmark(id: bookmark.id)
            loadBookmarks()
        } catch {
            // The row stays on screen when this fails, so silence reads as an ignored tap.
            Self.log.error("Failed to delete bookmark: \(error, privacy: .public)")
            showToast("Could not delete bookmark")
        }
    }

    public func createHighlight(colorHex: String, comment: String? = nil) {
        guard let selection = currentSelection else { return }
        let text = selection.locator.text.highlight ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let locatorJson = try? selection.locator.jsonString() else { return }

        let highlight = Highlight(
            bookId: book.id,
            locator: locatorJson,
            text: text,
            comment: comment,
            colorHex: colorHex,
            createdAt: Date()
        )

        do {
            try AppDatabase.shared.saveHighlight(highlight)
            loadHighlights()
            HapticManager.shared.impact(.light)
            showToast(comment == nil ? "Highlight saved" : "Thought saved")
        } catch {
            Self.log.error("Failed to save highlight: \(error, privacy: .public)")
            showToast("Could not save quote")
        }

        self.currentSelection = nil
    }

    public func deleteHighlight(_ highlight: Highlight) {
        do {
            try AppDatabase.shared.deleteHighlight(id: highlight.id)
            loadHighlights()
        } catch {
            Self.log.error("Failed to delete highlight: \(error, privacy: .public)")
            showToast("Could not delete quote")
        }
    }

    public func toggleOverlay() {
        withAnimation(DipleMotion.standard) {
            isOverlayVisible.toggle()
        }
    }
}
