import SwiftUI

/// Every highlight from every book in one place. Picking a book opens its full list.
///
/// The stack belongs to Home. SwiftUI keeps only the `navigationDestination` for a given type
/// that is declared closest to the stack's root, so a second declaration here would be
/// silently discarded — and it was: every book row was dead because Home's own declaration
/// for `BookQuoteSummary` won and only answered to its own binding. Routes are therefore
/// registered once, at the root, and this screen pushes onto the shared path.
public struct HubView: View {
    @Binding public var path: NavigationPath

    @StateObject private var viewModel = HubViewModel()

    public init(path: Binding<NavigationPath>) {
        _path = path
    }

    public var body: some View {
        ZStack {
            DipleColor.canvas.ignoresSafeArea()

            if viewModel.summaries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: DipleSpace.s) {
                        DailyResurfacingCard { path.append($0) }
                            .padding(.bottom, DipleSpace.m)

                        ForEach(viewModel.summaries) { summary in
                            NavigationLink(value: summary) {
                                HubBookRowView(summary: summary)
                            }
                            .buttonStyle(.bookCard)
                        }
                    }
                    .padding(.horizontal, DipleSpace.xl)
                    .padding(.top, DipleSpace.m)
                    .padding(.bottom, DipleSpace.xxxl)
                }
            }
        }
        // Home already owns this tab's NavigationStack. A second stack here made the
        // book route compete with its parent, briefly render black, then reset to Home.
        .navigationTitle("Highlights")
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
        .alert("Error", isPresented: $viewModel.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
        .onAppear {
            viewModel.load()
        }
    }

    private var emptyState: some View {
        VStack(spacing: DipleSpace.xl) {
            Image(systemName: "quote.opening")
                .dipleIcon(30, weight: .thin)
                .foregroundStyle(DipleColor.accent)

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
                coverPath: summary.book?.coverPath,
                title: summary.title,
                author: summary.author,
                isCompact: true
            )
            .frame(width: thumbnailWidth, height: thumbnailWidth * 1.5)

            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                Text(summary.title)
                    .dipleType(.body, weight: .semibold)
                    .foregroundStyle(DipleColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let book = summary.book {
                    BookSubtitleView(book: book)
                } else {
                    Text(summary.subtitle)
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
                        .lineLimit(1)
                }
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
        .craftSurface()
    }
}
