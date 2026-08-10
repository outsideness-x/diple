import SwiftUI

/// The first thing in Highlights: one familiar idea, given enough room to feel like reading
/// rather than another row in a database. The secondary action is deliberately gentle — it
/// offers another passage without turning the daily prompt into a feed.
public struct DailyResurfacingCard: View {
    public let onOpen: (BookQuoteSummary) -> Void

    @StateObject private var viewModel = DailyResurfacingViewModel()

    public init(onOpen: @escaping (BookQuoteSummary) -> Void) {
        self.onOpen = onOpen
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
                        Text("TODAY'S RESURFACE")
                            .dipleType(.micro, weight: .semibold)
                            .foregroundStyle(DipleColor.accent)
                        Spacer()
                        Text("FROM YOUR LIBRARY")
                            .dipleType(.nano)
                            .foregroundStyle(DipleColor.textQuaternary)
                    }

                    Text(item.quote.text)
                        .dipleType(.readingBody)
                        .readingLineSpacing(for: item.quote.text)
                        .foregroundStyle(DipleColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

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
                            onOpen(item.summary)
                            HapticManager.shared.selection()
                        } label: {
                            Label("Open Quotes", systemImage: "arrow.right")
                                .dipleType(.footnote, weight: .semibold)
                                .foregroundStyle(DipleColor.textOnAccent)
                                .diplePadding(.button)
                                .background(DipleColor.accent, in: Capsule())
                        }
                        .buttonStyle(.plain)

                        if viewModel.canShowAnother {
                            Button("Another", action: viewModel.showAnother)
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
