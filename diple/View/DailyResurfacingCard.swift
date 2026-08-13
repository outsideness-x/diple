import SwiftUI

/// A preview of the next due idea, not a feed. Home and iPhone Highlights start a focused
/// review session; the Mac fallback can still open the source's quote collection directly.
public struct DailyResurfacingCard: View {
    public let onOpen: (BookQuoteSummary) -> Void
    public let onReview: (() -> Void)?

    @StateObject private var viewModel = DailyResurfacingViewModel()

    public init(onOpen: @escaping (BookQuoteSummary) -> Void) {
        self.onOpen = onOpen
        self.onReview = nil
    }

    public init(
        onReview: @escaping () -> Void,
        onOpen: @escaping (BookQuoteSummary) -> Void
    ) {
        self.onOpen = onOpen
        self.onReview = onReview
    }

    public var body: some View {
        if let item = viewModel.item {
            ZStack(alignment: .topTrailing) {
                AccentWash(diameter: 250)
                    .offset(x: 64, y: -76)

                VStack(alignment: .leading, spacing: DipleSpace.l) {
                    HStack(spacing: DipleSpace.s) {
                        Image(systemName: "sparkles")
                            .dipleIcon(12, weight: .semibold)
                            .foregroundStyle(DipleColor.accent)
                        Text("DUE FOR REVIEW")
                            .dipleType(.micro, weight: .semibold)
                            .foregroundStyle(DipleColor.accent)
                        Spacer()
                        Text("\(viewModel.dueCount) \(viewModel.dueCount == 1 ? "IDEA" : "IDEAS")")
                            .dipleType(.nano)
                            .foregroundStyle(DipleColor.textQuaternary)
                    }

                    Text(item.quote.text)
                        .dipleType(.readingBody)
                        .readingLineSpacing(for: item.quote.text)
                        .foregroundStyle(DipleColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let comment = item.quote.comment, !comment.isEmpty {
                        HStack(alignment: .top, spacing: DipleSpace.s) {
                            Image(systemName: "bubble.left")
                                .dipleIcon(10, weight: .medium)
                                .foregroundStyle(DipleColor.accent)
                            Text(comment)
                                .dipleType(.caption)
                                .foregroundStyle(DipleColor.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                    }

                    VStack(alignment: .leading, spacing: DipleSpace.xs) {
                        Text(item.summary.title)
                            .dipleType(.footnote, weight: .semibold)
                            .foregroundStyle(DipleColor.textSecondary)
                        if let author = item.summary.author, !author.isEmpty {
                            Text(author)
                                .dipleType(.caption)
                                .foregroundStyle(DipleColor.textTertiary)
                        }
                    }

                    HStack(spacing: DipleSpace.m) {
                        Button {
                            if let onReview {
                                onReview()
                            } else {
                                onOpen(item.summary)
                            }
                            HapticManager.shared.selection()
                        } label: {
                            Label(onReview == nil ? "Open Quotes" : "Start Review", systemImage: "arrow.right")
                                .dipleType(.footnote, weight: .semibold)
                                .foregroundStyle(DipleColor.textOnAccent)
                                .diplePadding(.button)
                                .background(DipleColor.accent, in: Capsule())
                        }
                        .buttonStyle(.plain)

                        if onReview != nil {
                            Button("All from source") {
                                onOpen(item.summary)
                                HapticManager.shared.selection()
                            }
                            .dipleType(.footnote, weight: .semibold)
                            .foregroundStyle(DipleColor.textSecondary)
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(DipleSpace.l)
            }
            .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.l)
            .accessibilityElement(children: .contain)
            .onAppear(perform: viewModel.load)
        }
    }
}
