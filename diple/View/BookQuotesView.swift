import SwiftUI

/// Every quote saved from a single book — or, once the book has been removed from the
/// library, every quote that still remembers it by the title and author snapshotted at save
/// time.
public struct BookQuotesView: View {
    public let summary: BookQuoteSummary

    @StateObject private var viewModel: BookQuotesViewModel

    public init(summary: BookQuoteSummary) {
        self.summary = summary
        self._viewModel = StateObject(wrappedValue: BookQuotesViewModel(bookId: summary.bookId))
    }

    public var body: some View {
        ZStack {
            DipleColor.canvas.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: DipleSpace.m) {
                    header

                    ForEach(viewModel.quotes) { quote in
                        QuoteCardView(
                            quote: quote,
                            onCommentRequest: { viewModel.beginEditingComment(quote) },
                            onDeleteRequest: { viewModel.confirmDelete(quote) }
                        )
                    }
                }
                .padding(.horizontal, DipleSpace.xl)
                .padding(.top, DipleSpace.s)
                .padding(.bottom, DipleSpace.xxxl)
            }
        }
        .navigationTitle(summary.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DipleColor.canvas, for: .navigationBar)
        .alert("Error", isPresented: $viewModel.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
        .alert("Delete Quote?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                viewModel.deleteConfirmedQuote()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This quote will be removed.")
        }
        .sheet(item: $viewModel.quoteForComment) { quote in
            QuoteCommentEditorView(
                quote: quote,
                onSave: viewModel.saveComment,
                onCancel: viewModel.cancelCommentEditing
            )
        }
        .onAppear {
            viewModel.load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DipleSpace.xs) {
            Text(summary.title)
                .dipleType(.readingTitle)
                .foregroundStyle(DipleColor.textPrimary)

            if let author = summary.author, !author.isEmpty {
                Text(author)
                    .dipleType(.footnote, weight: .regular)
                    .foregroundStyle(DipleColor.textTertiary)
            }

            if summary.isRemovedFromLibrary {
                Text("Removed from library")
                    .dipleType(.footnote, weight: .regular)
                    .foregroundStyle(DipleColor.textQuaternary)
            }

            Text("\(viewModel.quotes.count) \(viewModel.quotes.count == 1 ? "quote" : "quotes")")
                .dipleType(.caption, weight: .medium)
                .foregroundStyle(DipleColor.textTertiary)
                .padding(.top, DipleSpace.xs)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(DipleMotion.standard, value: viewModel.quotes.count)
        }
        .padding(.bottom, DipleSpace.s)
    }
}
