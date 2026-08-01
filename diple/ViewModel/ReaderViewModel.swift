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

            self.publication = pub
            self.initialLocator = savedLocator
            self.isLoading = false
        } catch {
            self.errorMessage = "Failed to open book: \(error.localizedDescription)"
            self.isLoading = false
        }
    }

    public func saveLocation(_ locator: Locator) {
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

    public func toggleOverlay() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isOverlayVisible.toggle()
        }
    }
}
