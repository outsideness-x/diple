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
            Color.black.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    header

                    ForEach(viewModel.quotes) { quote in
                        QuoteCardView(quote: quote)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
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
        VStack(alignment: .leading, spacing: 4) {
            Text(book.title)
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundColor(Color(red: 0.94, green: 0.94, blue: 0.95))

            if let author = book.author, !author.isEmpty {
                Text(author)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.58))
            }

            Text("\(viewModel.quotes.count) \(viewModel.quotes.count == 1 ? "quote" : "quotes")")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.dipleAccent)
                .padding(.top, 4)
        }
        .padding(.bottom, 8)
    }
}
