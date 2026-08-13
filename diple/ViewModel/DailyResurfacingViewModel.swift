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
    @Published public private(set) var dueCount = 0
    @Published public var errorMessage: String?

    public init() {
        load()
    }

    public func load() {
        do {
            let due = try AppDatabase.shared.fetchDueHighlights(limit: 5)
            dueCount = due.count
            guard let quote = due.first else {
                item = nil
                return
            }
            item = makeItem(for: quote)
        } catch {
            item = nil
            dueCount = 0
            errorMessage = "Failed to resurface a quote: \(error.localizedDescription)"
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
