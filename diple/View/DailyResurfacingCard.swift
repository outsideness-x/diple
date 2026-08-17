import SwiftUI

/// One saved highlight, given enough room to feel like reading rather than another database
/// row. It is a rediscovery shortcut only — no scores, scheduling or learning workflow.
public struct DailyResurfacingCard: View {
    public let onOpen: (DailyResurfacingItem) -> Void

    @StateObject private var viewModel = DailyResurfacingViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var swapDirection: CGFloat = -1
    @State private var isSwapping = false

    public init(onOpen: @escaping (DailyResurfacingItem) -> Void) {
        self.onOpen = onOpen
    }

    public var body: some View {
        if let item = viewModel.item {
            ZStack(alignment: .topTrailing) {
                cardContent(for: item)
                    .id(item.id)
                    .offset(x: dragOffset)
                    .scaleEffect(dragOffset == 0 ? 1 : 0.985)
                    .blur(radius: min(abs(dragOffset) / 18, 2.5))
                    .opacity(1 - Double(min(abs(dragOffset) / CGFloat(280), CGFloat(0.22))))
                    .transition(highlightTransition)
            }
            .contentShape(Rectangle())
            // The block was the only thing on the page that could not be acted on, and it was
            // the largest. Tapping it now opens the passage where it was written — which is
            // what resurfacing is for, and what the old "Open Highlights" button did not do
            // (it led to a list, duplicating the All highlights row right underneath).
            .onTapGesture {
                HapticManager.shared.selection()
                onOpen(item)
            }
            .simultaneousGesture(swipeGesture, including: viewModel.canShowAnother ? .all : .subviews)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DipleColor.hairline)
                    .frame(height: DipleStroke.hairline)
            }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Show another highlight") {
                if viewModel.canShowAnother { showAnother(moving: -1) }
            }
            .onAppear(perform: viewModel.load)
        }
    }

    /// `A SIMPLIFIED VIEW OF THE JACOBIAN CONJECTURE · JAMES O'BRIEN` — the same dateline the
    /// library's entries use, so a quote is attributed the way a source is identified.
    private func attribution(for item: DailyResurfacingItem) -> String {
        [item.summary.title, item.summary.author]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
            .uppercased()
    }

    private func cardContent(for item: DailyResurfacingItem) -> some View {
        VStack(alignment: .leading, spacing: DipleSpace.l) {
            // No label of its own. The section above already says HIGHLIGHTS; a second heading
            // saying TODAY'S HIGHLIGHT under it is the same word twice, and FROM YOUR LIBRARY
            // answered a question nobody had — there is nowhere else a highlight could be from.
            Text(item.quote.text)
                .dipleType(.readingBody)
                .readingLineSpacing(for: item.quote.text)
                .foregroundStyle(DipleColor.textPrimary)
                .multilineTextAlignment(.leading)
                // A ceiling, because an unclamped quote is not a block on the page — it *is*
                // the page. Eight lines of a long passage pushed everything else below the fold
                // and gave the largest mass on a reading app's front page to the one thing that
                // could not be acted on. Five lines is enough to recognise an idea; the rest is
                // one tap away, in the book, where it was written.
                .lineLimit(5)

            if let comment = item.quote.comment, !comment.isEmpty {
                HStack(alignment: .top, spacing: DipleSpace.s) {
                    Image(systemName: "bubble.left")
                        .dipleIcon(10, weight: .medium)
                        .foregroundStyle(DipleColor.textQuaternary)
                    Text(comment)
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textSecondary)
                        .multilineTextAlignment(.leading)
                }
            }

            Text(attribution(for: item))
                .dipleType(.nano, weight: .medium)
                .foregroundStyle(DipleColor.textTertiary)
                .lineLimit(2)

            HStack(spacing: DipleSpace.m) {
                if viewModel.canShowAnother {
                    Button {
                        showAnother(moving: -1)
                    } label: {
                        Label("Another", systemImage: "arrow.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .dipleType(.footnote, weight: .semibold)
                    .foregroundStyle(DipleColor.textSecondary)
                    .buttonStyle(.plain)
                    .disabled(isSwapping)
                }
            }
        }
        .padding(DipleSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard viewModel.canShowAnother, !isSwapping,
                      abs(value.translation.width) > abs(value.translation.height) * 1.15
                else { return }
                dragOffset = max(-72, min(72, value.translation.width * 0.42))
            }
            .onEnded { value in
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.15
                guard viewModel.canShowAnother, !isSwapping, isHorizontal, abs(value.translation.width) > 58 else {
                    withAnimation(DipleMotion.snappy) { dragOffset = 0 }
                    return
                }
                showAnother(moving: value.translation.width < 0 ? -1 : 1)
            }
    }

    private var highlightTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(
                active: HighlightSwapModifier(offset: -swapDirection * 44, opacity: 0, scale: 0.975, blur: 3),
                identity: HighlightSwapModifier(offset: 0, opacity: 1, scale: 1, blur: 0)
            ),
            removal: .modifier(
                active: HighlightSwapModifier(offset: swapDirection * 44, opacity: 0, scale: 0.975, blur: 3),
                identity: HighlightSwapModifier(offset: 0, opacity: 1, scale: 1, blur: 0)
            )
        )
    }

    private func showAnother(moving direction: CGFloat) {
        guard !isSwapping else { return }
        swapDirection = direction
        dragOffset = 0

        if reduceMotion {
            viewModel.showAnother()
        } else {
            isSwapping = true
            withAnimation(DipleMotion.gentle) {
                viewModel.showAnother()
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(520))
                isSwapping = false
            }
        }
    }
}

private struct HighlightSwapModifier: ViewModifier {
    let offset: CGFloat
    let opacity: Double
    let scale: CGFloat
    let blur: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .opacity(opacity)
            .scaleEffect(scale)
            .blur(radius: blur)
    }
}
