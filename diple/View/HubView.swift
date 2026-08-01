import SwiftUI

/// Every quote from every book in one place. Picking a book opens its full quote list.
public struct HubView: View {
    @StateObject private var viewModel = HubViewModel()

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                if viewModel.summaries.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: DipleSpace.s) {
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
                        .padding(.horizontal, DipleSpace.xl)
                        .padding(.top, DipleSpace.m)
                        .padding(.bottom, DipleSpace.xxxl)
                    }
                }
            }
            .navigationTitle("Hub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if viewModel.totalQuoteCount > 0 {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Text("\(viewModel.totalQuoteCount)")
                            .dipleType(.footnote, weight: .semibold)
                            .foregroundStyle(DipleColor.textTertiary)
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
        VStack(spacing: DipleSpace.xl) {
            ZStack {
                Circle()
                    .fill(DipleColor.accent.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: "quote.opening")
                    .dipleIcon(30, weight: .thin)
                    .foregroundStyle(DipleColor.accent)
            }

            VStack(spacing: DipleSpace.s) {
                Text("No Quotes Yet")
                    .dipleType(.title)
                    .foregroundStyle(DipleColor.textPrimary)

                Text("Highlight a passage while reading and it will show up here, grouped by book.")
                    .dipleType(.callout)
                    .foregroundStyle(DipleColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DipleSpace.xxxl)
            }
        }
    }
}

/// One book in the hub list: cover, metadata and how many quotes it holds.
public struct HubBookRowView: View {
    public let summary: BookQuoteSummary

    /// The thumbnail grows with the text beside it, so the row keeps its proportions under
    /// Dynamic Type instead of leaving a stamp next to giant titles.
    @ScaledMetric(relativeTo: .subheadline) private var thumbnailWidth: CGFloat = 44

    public init(summary: BookQuoteSummary) {
        self.summary = summary
    }

    public var body: some View {
        HStack(spacing: DipleSpace.m) {
            BookCoverView(
                coverPath: summary.book.coverPath,
                title: summary.book.title,
                author: summary.book.author,
                isCompact: true
            )
            .frame(width: thumbnailWidth, height: thumbnailWidth * 1.5)

            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                Text(summary.book.title)
                    .dipleType(.body, weight: .semibold)
                    .foregroundStyle(DipleColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(summary.book.author ?? "Unknown Author")
                    .dipleType(.caption)
                    .foregroundStyle(DipleColor.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(summary.quoteCount)")
                .dipleType(.footnote, weight: .semibold)
                .foregroundStyle(DipleColor.accent)
                .monospacedDigit()

            Image(systemName: "chevron.right")
                .dipleIcon(12, weight: .semibold)
                .foregroundStyle(DipleColor.textQuaternary)
        }
        .padding(DipleSpace.m)
        .background(DipleColor.surface, in: RoundedRectangle(cornerRadius: DipleRadius.m))
    }
}
