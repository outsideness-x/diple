import Foundation
import SwiftUI
import Combine

public struct DailyResurfacingItem: Identifiable, Equatable {
    public let quote: Highlight
    public let summary: BookQuoteSummary

    public var id: String { quote.id }
}

@MainActor
public final class DailyResurfacingViewModel: ObservableObject {
    @Published public private(set) var item: DailyResurfacingItem?
    @Published public private(set) var canShowAnother = false
    @Published public var errorMessage: String?

    public init() {
        load()
    }

    public func load() {
        do {
            guard let quote = try DailyResurfacingService.shared.quoteForToday() else {
                item = nil
                return
            }
            item = makeItem(for: quote)
            canShowAnother = try DailyResurfacingService.shared.hasAnotherQuote()
        } catch {
            item = nil
            canShowAnother = false
            errorMessage = "Failed to resurface a quote: \(error.localizedDescription)"
        }
    }

    public func showAnother() {
        do {
            guard let quote = try DailyResurfacingService.shared.showAnotherQuote() else { return }
            item = makeItem(for: quote)
            canShowAnother = try DailyResurfacingService.shared.hasAnotherQuote()
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
