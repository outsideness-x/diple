import SwiftUI

/// Every quote saved from a single book.
public struct BookQuotesView: View {
    public let book: Book

    @StateObject private var viewModel: BookQuotesViewModel

    public init(book: Book) {
        self.book = book
        self._viewModel = StateObject(wrappedValue: BookQuotesViewModel(bookId: book.id))
    }

    public var body: some View {
        ZStack {
            DipleColor.canvas.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: DipleSpace.m) {
                    header

                    ForEach(viewModel.quotes) { quote in
                        QuoteCardView(quote: quote)
                    }
                }
                .padding(.horizontal, DipleSpace.xl)
                .padding(.top, DipleSpace.s)
                .padding(.bottom, DipleSpace.xxxl)
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DipleColor.canvas, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Error", isPresented: $viewModel.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
        .onAppear {
            viewModel.load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DipleSpace.xs) {
            Text(book.title)
                .dipleType(.readingTitle)
                .foregroundStyle(DipleColor.textPrimary)

            if let author = book.author, !author.isEmpty {
                Text(author)
                    .dipleType(.footnote, weight: .regular)
                    .foregroundStyle(DipleColor.textTertiary)
            }

            Text("\(viewModel.quotes.count) \(viewModel.quotes.count == 1 ? "quote" : "quotes")")
                .dipleType(.caption, weight: .medium)
                .foregroundStyle(DipleColor.accent)
                .padding(.top, DipleSpace.xs)
        }
        .padding(.bottom, DipleSpace.s)
    }
}
