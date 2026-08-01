import Foundation
import Combine
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
    @Published public var targetLink: ReadiumShared.Link? = nil
    @Published public var targetLocator: Locator? = nil
    @Published public var tableOfContents: [ReadiumShared.Link] = []
    @Published public var highlights: [Highlight] = []
    @Published public var bookmarks: [Bookmark] = []
    @Published public var currentSelection: Selection? = nil
    @Published public var currentLocator: Locator? = nil
    @Published public var isAddBookmarkPresented: Bool = false
    @Published public var settings: ReaderSettings = ReaderSettings()
    @Published public var isLoading: Bool = true
    @Published public var errorMessage: String? = nil

    private let httpClient = DefaultHTTPClient()
    private lazy var assetRetriever = AssetRetriever(httpClient: httpClient)
    private lazy var publicationOpener = PublicationOpener(
        parser: DefaultPublicationParser(
            httpClient: httpClient,
            assetRetriever: assetRetriever,
            pdfFactory: DefaultPDFDocumentFactory()
        )
    )

    public init(book: Book) {
        self.book = book
        self.currentProgress = book.progress
        let defaultMode: ReadingMode = AppSettingsManager.shared.settings.defaultScrollReadingMode ? .scroll : .paginated
        self.settings = ReaderSettings(readingMode: defaultMode)
        loadHighlights()
        loadBookmarks()
    }

    public func loadHighlights() {
        do {
            self.highlights = try AppDatabase.shared.fetchHighlights(forBookId: book.id)
        } catch {
            print("Failed to fetch highlights: \(error)")
        }
    }

    public func loadBookmarks() {
        do {
            self.bookmarks = try AppDatabase.shared.fetchBookmarks(forBookId: book.id)
        } catch {
            print("Failed to fetch bookmarks: \(error)")
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

            var savedLocator: Locator? = nil
            if let locatorStr = book.locator, !locatorStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                savedLocator = try? Locator(jsonString: locatorStr)
            }

            let toc = (try? await pub.tableOfContents().get()) ?? pub.manifest.tableOfContents

            self.publication = pub
            self.tableOfContents = toc
            self.initialLocator = savedLocator
            self.currentLocator = savedLocator
            self.isLoading = false
        } catch {
            self.errorMessage = "Failed to open book: \(error.localizedDescription)"
            self.isLoading = false
        }
    }

    public func saveLocation(_ locator: Locator) {
        self.currentLocator = locator
        let progression = locator.locations.totalProgression ?? locator.locations.progression ?? self.currentProgress
        self.currentProgress = progression

        let locatorStr = try? locator.jsonString()
        do {
            try AppDatabase.shared.updateReadingProgress(
                id: book.id,
                progress: progression,
                locator: locatorStr
            )
        } catch {
            print("Failed to save reading progress: \(error)")
        }
    }

    public func navigateToLink(_ link: ReadiumShared.Link) {
        self.targetLink = link
    }

    public func navigateToLocator(_ locator: Locator) {
        self.targetLocator = locator
    }

    public func addBookmark(name: String, colorHex: String) {
        guard let locator = currentLocator ?? initialLocator,
              let locatorJson = try? locator.jsonString() else { return }

        let bookmark = Bookmark(
            bookId: book.id,
            locator: locatorJson,
            name: name,
            colorHex: colorHex,
            createdAt: Date()
        )

        do {
            try AppDatabase.shared.saveBookmark(bookmark)
            loadBookmarks()
        } catch {
            print("Failed to save bookmark: \(error)")
        }
    }

    public func deleteBookmark(_ bookmark: Bookmark) {
        do {
            try AppDatabase.shared.deleteBookmark(id: bookmark.id)
            loadBookmarks()
        } catch {
            print("Failed to delete bookmark: \(error)")
        }
    }

    public func createHighlight(colorHex: String) {
        guard let selection = currentSelection else { return }
        let text = selection.locator.text.highlight ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let locatorJson = try? selection.locator.jsonString() else { return }

        let highlight = Highlight(
            bookId: book.id,
            locator: locatorJson,
            text: text,
            colorHex: colorHex,
            createdAt: Date()
        )

        do {
            try AppDatabase.shared.saveHighlight(highlight)
            loadHighlights()
        } catch {
            print("Failed to save highlight: \(error)")
        }

        self.currentSelection = nil
    }

    public func deleteHighlight(_ highlight: Highlight) {
        do {
            try AppDatabase.shared.deleteHighlight(id: highlight.id)
            loadHighlights()
        } catch {
            print("Failed to delete highlight: \(error)")
        }
    }

    public func toggleOverlay() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isOverlayVisible.toggle()
        }
    }
}
