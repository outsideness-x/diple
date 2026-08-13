import SwiftUI

/// One saved highlight, given enough room to feel like reading rather than another database
/// row. It is a rediscovery shortcut only — no scores, scheduling or learning workflow.
public struct DailyResurfacingCard: View {
    public let onOpen: (BookQuoteSummary) -> Void

    @StateObject private var viewModel = DailyResurfacingViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var swapDirection: CGFloat = -1
    @State private var accentPhase: CGFloat = 1
    @State private var isSwapping = false

    public init(onOpen: @escaping (BookQuoteSummary) -> Void) {
        self.onOpen = onOpen
    }

    public var body: some View {
        if let item = viewModel.item {
            ZStack(alignment: .topTrailing) {
                AccentWash(diameter: 250)
                    .offset(x: 64 + accentPhase * 16, y: -76)
                    .animation(DipleMotion.gentle, value: accentPhase)

                cardContent(for: item)
                    .id(item.id)
                    .offset(x: dragOffset)
                    .scaleEffect(dragOffset == 0 ? 1 : 0.985)
                    .blur(radius: min(abs(dragOffset) / 18, 2.5))
                    .opacity(1 - Double(min(abs(dragOffset) / CGFloat(280), CGFloat(0.22))))
                    .transition(highlightTransition)
            }
            .contentShape(RoundedRectangle(cornerRadius: DipleRadius.l))
            .simultaneousGesture(swipeGesture, including: viewModel.canShowAnother ? .all : .subviews)
            .clipShape(RoundedRectangle(cornerRadius: DipleRadius.l, style: .continuous))
            .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.l)
            .background(alignment: .bottom) { deck }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Show another highlight") {
                if viewModel.canShowAnother { showAnother(moving: -1) }
            }
            .onAppear(perform: viewModel.load)
        }
    }

    /// The edge of the next card, showing under the current one.
    ///
    /// Swiping used to replace the quote in place, which reads as a value changing in a field —
    /// nothing about the card said there was more behind it, so the gesture had to be
    /// discovered from the "Another" button. A sliver of a second card underneath says "stack"
    /// before anything is touched, and rises as the top card is dragged away.
    ///
    /// It carries no content on purpose. The view model resurfaces one quote at a time and has
    /// no next item to show, and inventing one would mean reading ahead in a sequence the
    /// service is entitled to change. An edge is honest about being an edge.
    @ViewBuilder
    private var deck: some View {
        if viewModel.canShowAnother {
            let progress = min(abs(dragOffset) / 72, 1)
            RoundedRectangle(cornerRadius: DipleRadius.l, style: .continuous)
                .fill(DipleColor.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DipleRadius.l, style: .continuous)
                        .strokeBorder(DipleColor.hairline, lineWidth: DipleStroke.hairline)
                )
                // Sits a little narrower and a little lower, and closes both gaps as the top
                // card leaves — the next one coming forward rather than a border appearing.
                .padding(.horizontal, 14 - 14 * progress)
                .offset(y: 10 - 4 * progress)
                .allowsHitTesting(false)
        }
    }

    private func cardContent(for item: DailyResurfacingItem) -> some View {
        VStack(alignment: .leading, spacing: DipleSpace.l) {
            HStack(spacing: DipleSpace.s) {
                Image(systemName: "sparkles")
                    .dipleIcon(12, weight: .semibold)
                    .foregroundStyle(DipleColor.accent)
                Text("TODAY'S HIGHLIGHT")
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
                    onOpen(item.summary)
                    HapticManager.shared.selection()
                } label: {
                    Label("Open Highlights", systemImage: "arrow.right")
                        .dipleType(.footnote, weight: .semibold)
                        .foregroundStyle(DipleColor.textOnAccent)
                        .diplePadding(.button)
                        .background(DipleColor.accent, in: Capsule())
                }
                .buttonStyle(.plain)

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
                accentPhase *= -1
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
