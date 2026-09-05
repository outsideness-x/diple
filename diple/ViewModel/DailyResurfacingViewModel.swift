import Foundation
import SwiftUI
import Combine

public struct DailyResurfacingItem: Identifiable, Equatable {
    public let quote: Highlight
    public let summary: BookQuoteSummary

    public var id: String { quote.id }
}

/// The day's passage, answered by one from a different book.
///
/// It carries a full `DailyResurfacingItem` rather than a bare `Highlight` so the card can hand
/// it to the *same* `onOpen` the day's passage uses. One route out of this card, not two.
public struct DailyResurfacingEcho: Identifiable, Equatable {
    public let item: DailyResurfacingItem
    public let sharedTerms: [String]

    public var id: String { item.id }
}

@MainActor
public final class DailyResurfacingViewModel: ObservableObject {
    @Published public private(set) var item: DailyResurfacingItem?
    /// Nil far more often than not, and that is the intended resting state: most passages do
    /// not answer anything, and a card that always found a connection would be inventing them.
    @Published public private(set) var echo: DailyResurfacingEcho?
    @Published public private(set) var canShowAnother = false
    @Published public var errorMessage: String?
    private var echoTask: Task<Void, Never>?

    public init() {
        load()
    }

    public func load() {
        do {
            guard let quote = try DailyResurfacingService.shared.quoteForToday() else {
                item = nil
                echo = nil
                return
            }
            item = makeItem(for: quote)
            canShowAnother = try DailyResurfacingService.shared.hasAnotherQuote()
            loadEcho(for: quote)
        } catch {
            item = nil
            echo = nil
            canShowAnother = false
            errorMessage = "Failed to resurface a quote: \(error.localizedDescription)"
        }
    }

    /// Asked for after the passage is already on screen, never before it.
    ///
    /// Building the corpus is real work on a large library, and the day's passage must not wait
    /// on a connection it probably does not have. The echo arrives late and quietly, or not at
    /// all — which is why it is cleared first: a card must never show yesterday's answer under
    /// today's question.
    private func loadEcho(for quote: Highlight) {
        echo = nil
        echoTask?.cancel()
        echoTask = Task { [weak self] in
            let found = await PassageEchoService.shared.echoes(
                for: quote,
                limit: 1,
                // "Somewhere else in your reading" means somewhere else. Two passages from one
                // book are usually two paragraphs of one argument.
                excludingSameSource: true
            )
            guard !Task.isCancelled, let self, let first = found.first else { return }
            guard self.item?.quote.id == quote.id else { return }
            self.echo = DailyResurfacingEcho(
                item: self.makeItem(for: first.passage),
                sharedTerms: first.sharedTerms
            )
        }
    }

    public func showAnother() {
        do {
            guard let quote = try DailyResurfacingService.shared.showAnotherQuote() else { return }
            item = makeItem(for: quote)
            canShowAnother = try DailyResurfacingService.shared.hasAnotherQuote()
            loadEcho(for: quote)
            // Another changes what *today* is, and the widget is showing today. Without this
            // the Home Screen would keep the passage the reader has just moved on from.
            DailyResurfacingService.shared.refreshWidgetSnapshot()
            HapticManager.shared.impact(.light)
        } catch {
            errorMessage = "Failed to show another highlight: \(error.localizedDescription)"
        }
    }

    private func makeItem(for quote: Highlight) -> DailyResurfacingItem {
        let book = try? AppDatabase.shared.fetchBook(id: quote.bookId)
        return DailyResurfacingItem(
            quote: quote,
            summary: BookQuoteSummary(
                bookId: quote.bookId,
                title: book?.title ?? quote.bookTitle ?? "A saved passage",
                author: book?.author ?? quote.bookAuthor,
                book: book,
                quoteCount: 0
            )
        )
    }
}
