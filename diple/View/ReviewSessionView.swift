import SwiftUI
import Combine

@MainActor
public final class ReviewSessionViewModel: ObservableObject {
    @Published public private(set) var items: [DailyResurfacingItem] = []
    @Published public private(set) var currentIndex = 0
    @Published public var quoteForComment: Highlight?
    @Published public var errorMessage: String?

    public init() {
        load()
    }

    public var current: DailyResurfacingItem? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    public var reviewedCount: Int { min(currentIndex, items.count) }
    public var isComplete: Bool { !items.isEmpty && currentIndex >= items.count }

    public func load() {
        do {
            items = try AppDatabase.shared.fetchDueHighlights(limit: 5).map(Self.makeItem)
            currentIndex = 0
        } catch {
            items = []
            errorMessage = "Failed to load your review: \(error.localizedDescription)"
        }
    }

    public func respond(_ response: HighlightReviewResponse) {
        guard let current else { return }
        do {
            try AppDatabase.shared.recordHighlightReview(
                highlightId: current.quote.id,
                response: response
            )
            currentIndex += 1
            HapticManager.shared.notification(.success)
        } catch {
            errorMessage = "Failed to save review progress: \(error.localizedDescription)"
        }
    }

    public func beginCommenting() {
        quoteForComment = current?.quote
    }

    public func saveComment(_ comment: String) {
        guard let quote = quoteForComment else { return }
        do {
            try AppDatabase.shared.updateHighlightComment(id: quote.id, comment: comment)
            if items.indices.contains(currentIndex) {
                var updatedQuote = quote
                let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                updatedQuote.comment = trimmed.isEmpty ? nil : trimmed
                items[currentIndex] = DailyResurfacingItem(
                    quote: updatedQuote,
                    summary: items[currentIndex].summary
                )
            }
            quoteForComment = nil
        } catch {
            errorMessage = "Failed to save your thought: \(error.localizedDescription)"
        }
    }

    private static func makeItem(_ quote: Highlight) -> DailyResurfacingItem {
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

/// A quiet five-passage session. The reader makes only one decision per passage; optional
/// reflection is available without blocking progress or turning review into a form to fill.
public struct ReviewSessionView: View {
    @StateObject private var viewModel = ReviewSessionViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        ZStack {
            DipleColor.canvas.ignoresSafeArea()

            if let item = viewModel.current {
                review(item)
                    .id(item.id)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            } else if viewModel.isComplete {
                completion
            } else {
                caughtUp
            }
        }
        .animation(DipleMotion.gentle, value: viewModel.current?.id)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DipleColor.canvas, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $viewModel.quoteForComment) { quote in
            QuoteCommentEditorView(
                quote: quote,
                onSave: viewModel.saveComment,
                onCancel: { viewModel.quoteForComment = nil }
            )
        }
        .alert("Review Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
    }

    private func review(_ item: DailyResurfacingItem) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: DipleSpace.s) {
                HStack {
                    Text("A MOMENT TO RECALL")
                        .dipleType(.micro, weight: .semibold)
                        .foregroundStyle(DipleColor.textTertiary)
                    Spacer()
                    Text("\(viewModel.currentIndex + 1) OF \(viewModel.items.count)")
                        .dipleType(.micro, weight: .semibold)
                        .foregroundStyle(DipleColor.accent)
                        .monospacedDigit()
                }

                ProgressView(
                    value: Double(viewModel.currentIndex),
                    total: Double(max(viewModel.items.count, 1))
                )
                .tint(DipleColor.accent)
            }
            .padding(.horizontal, DipleSpace.xl)
            .padding(.top, DipleSpace.m)

            ScrollView {
                VStack(alignment: .leading, spacing: DipleSpace.xl) {
                    Text(item.quote.text)
                        .dipleType(.readingTitle)
                        .readingLineSpacing(for: item.quote.text)
                        .foregroundStyle(DipleColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let comment = item.quote.comment, !comment.isEmpty {
                        HStack(alignment: .top, spacing: DipleSpace.s) {
                            Image(systemName: "bubble.left.fill")
                                .dipleIcon(11, weight: .medium)
                                .foregroundStyle(DipleColor.accent)
                            Text(comment)
                                .dipleType(.callout)
                                .foregroundStyle(DipleColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(DipleSpace.m)
                        .background(DipleColor.accentSoft, in: RoundedRectangle(cornerRadius: DipleRadius.m))
                    }

                    VStack(alignment: .leading, spacing: DipleSpace.xs) {
                        Text(item.summary.title)
                            .dipleType(.body, weight: .semibold)
                            .foregroundStyle(DipleColor.textSecondary)
                        if let author = item.summary.author, !author.isEmpty {
                            Text(author)
                                .dipleType(.caption)
                                .foregroundStyle(DipleColor.textTertiary)
                        }
                    }

                    Button(action: viewModel.beginCommenting) {
                        Label(
                            item.quote.comment == nil ? "Add a thought" : "Edit your thought",
                            systemImage: "square.and.pencil"
                        )
                        .dipleType(.footnote, weight: .semibold)
                        .foregroundStyle(DipleColor.textSecondary)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.readerControl)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DipleSpace.xl)
                .padding(.top, DipleSpace.xxxl)
                .padding(.bottom, DipleSpace.xl)
            }

            HStack(spacing: DipleSpace.s) {
                reviewButton(
                    title: "Again soon",
                    systemImage: "arrow.counterclockwise",
                    isPrimary: false
                ) { viewModel.respond(.againSoon) }

                reviewButton(
                    title: "Remembered",
                    systemImage: "checkmark",
                    isPrimary: true
                ) { viewModel.respond(.remembered) }
            }
            .padding(.horizontal, DipleSpace.xl)
            .padding(.top, DipleSpace.m)
            .padding(.bottom, DipleSpace.scrollBottom)
            .background(.ultraThinMaterial)
        }
    }

    private func reviewButton(
        title: String,
        systemImage: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .dipleType(.footnote, weight: .semibold)
                .foregroundStyle(isPrimary ? DipleColor.textOnAccent : DipleColor.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .background(
                    isPrimary ? DipleColor.accent : DipleColor.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: DipleRadius.m)
                )
                .overlay {
                    if !isPrimary {
                        RoundedRectangle(cornerRadius: DipleRadius.m)
                            .stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline)
                    }
                }
        }
        .buttonStyle(.readerControl)
    }

    private var completion: some View {
        ReviewEmptyState(
            systemImage: "checkmark.circle.fill",
            title: "Review complete",
            message: "You returned to \(viewModel.reviewedCount) \(viewModel.reviewedCount == 1 ? "idea" : "ideas"). They’ll come back when there’s enough distance to be useful.",
            actionTitle: "Done",
            action: { dismiss() }
        )
    }

    private var caughtUp: some View {
        ReviewEmptyState(
            systemImage: "sun.max",
            title: "You’re caught up",
            message: "Nothing needs review today. Keep reading or add a thought to something you’ve already saved.",
            actionTitle: "Done",
            action: { dismiss() }
        )
    }
}

private struct ReviewEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: DipleSpace.l) {
            Image(systemName: systemImage)
                .dipleIcon(34, weight: .light)
                .foregroundStyle(DipleColor.accent)
            VStack(spacing: DipleSpace.s) {
                Text(title)
                    .dipleType(.title)
                    .foregroundStyle(DipleColor.textPrimary)
                Text(message)
                    .dipleType(.callout)
                    .foregroundStyle(DipleColor.textTertiary)
                    .multilineTextAlignment(.center)
            }
            Button(actionTitle, action: action)
                .dipleType(.footnote, weight: .semibold)
                .foregroundStyle(DipleColor.textOnAccent)
                .padding(.horizontal, DipleSpace.xl)
                .frame(minHeight: 44)
                .background(DipleColor.accent, in: Capsule())
                .buttonStyle(.readerControl)
        }
        .padding(DipleSpace.xxxl)
    }
}
