import SwiftUI

/// Every quote from every book in one place. Picking a book opens its full quote list.
public struct HubView: View {
    @StateObject private var viewModel = HubViewModel()

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if viewModel.summaries.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(viewModel.summaries) { summary in
                                NavigationLink(value: summary.book) {
                                    HubBookRowView(summary: summary)
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(TapGesture().onEnded {
                                    HapticManager.shared.impact(.light)
                                })
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Hub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if viewModel.totalQuoteCount > 0 {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Text("\(viewModel.totalQuoteCount)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.58))
                            .monospacedDigit()
                    }
                }
            }
            .navigationDestination(for: Book.self) { book in
                BookQuotesView(book: book)
            }
            .alert("Error", isPresented: $viewModel.showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred.")
            }
            .onAppear {
                viewModel.load()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.dipleAccent.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: "quote.opening")
                    .font(.system(size: 30, weight: .thin))
                    .foregroundColor(Color.dipleAccent)
            }

            VStack(spacing: 8) {
                Text("No Quotes Yet")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))

                Text("Highlight a passage while reading and it will show up here, grouped by book.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.58))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
}

/// One book in the hub list: cover, metadata and how many quotes it holds.
public struct HubBookRowView: View {
    public let summary: BookQuoteSummary

    public init(summary: BookQuoteSummary) {
        self.summary = summary
    }

    public var body: some View {
        HStack(spacing: 14) {
            BookCoverView(
                coverPath: summary.book.coverPath,
                title: summary.book.title,
                author: summary.book.author
            )
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.book.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(summary.book.author ?? "Unknown Author")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.58))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(summary.quoteCount)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.dipleAccent)
                .monospacedDigit()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(red: 0.35, green: 0.35, blue: 0.4))
        }
        .padding(12)
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
        .cornerRadius(12)
    }
}
