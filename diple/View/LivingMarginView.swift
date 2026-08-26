import SwiftUI
import ReadiumShared

/// The page's revealed margin. It is an unbroken continuation of the reader surface — no card,
/// radius, material or metadata — and deliberately renders only the reader's own words.
///
/// Those words are set in Caveat, the same notebook hand as the Settings colophon, because this
/// is the one surface in the app showing what the reader wrote rather than what a publisher
/// typeset. Legibility is what the size, line spacing and tracking here are paying for: Caveat's
/// x-height is small for its point size, so it is set larger than the serif it replaces, given
/// more air between lines than running text needs, and opened up very slightly — the letters are
/// drawn unjoined, and the extra separation keeps them that way at reading distance. No
/// `.italic()`: a synthetic slant on a hand that already leans only smears it.
struct LivingMarginPanel: View {
    let annotation: LivingMarginAnnotation
    let chrome: ReaderChrome
    let reduceMotion: Bool
    let onClose: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onEdit: () -> Void

    @State private var revealsNote = false
    @AccessibilityFocusState private var noteIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Button(action: onClose) {
                    LivingMarginButtonLabel(color: chrome.control)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Note attached"))
                .accessibilityHint(Text("Close note"))
                .accessibilityIdentifier("livingMargins.close")
            }

            ScrollView {
                Button(action: onEdit) {
                    Text(annotation.note)
                        .font(.custom("Caveat-Regular", size: 25, relativeTo: .title3))
                        .lineSpacing(9)
                        .tracking(0.2)
                        .foregroundStyle(chrome.control.opacity(0.96))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(revealsNote ? 1 : 0)
                .offset(x: reduceMotion || revealsNote ? 0 : 8)
                .accessibilityLabel(Text(annotation.note))
                .accessibilityHint(Text("Edit note"))
                .accessibilityFocused($noteIsFocused)
                .accessibilityIdentifier("livingMargins.note")
            }
            .scrollIndicators(.hidden)
            .contentMargins(.vertical, DipleSpace.xl, for: .scrollContent)

            Spacer(minLength: DipleSpace.xl)
        }
        .padding(.horizontal, DipleSpace.xxl)
        .padding(.vertical, DipleSpace.m)
        .background(chrome.page)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(chrome.separator)
                .frame(width: DipleStroke.hairline)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 22)
                .onEnded { value in
                    let horizontal = value.predictedEndTranslation.width
                    let vertical = value.predictedEndTranslation.height
                    guard abs(horizontal) > abs(vertical), abs(horizontal) > 54 else { return }
                    if horizontal > 0 {
                        onClose()
                    } else {
                        onNext()
                    }
                }
        )
        .accessibilityAction(named: Text("Next note"), onNext)
        .accessibilityAction(named: Text("Previous note"), onPrevious)
        .accessibilityAction(named: Text("Close note"), onClose)
        .task(id: annotation.id) {
            revealsNote = false
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(85))
                guard !Task.isCancelled else { return }
            }
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.24)) {
                revealsNote = true
            }
            noteIsFocused = true
        }
    }
}

/// The same handwritten diple as the HTML marker, drawn natively where the open field needs a
/// second activation target. Its 22-point visible footprint sits inside the button's 44 points.
private struct LivingMarginStroke: View {
    let color: Color

    var body: some View {
        ZStack {
            Capsule()
                .fill(color.opacity(0.52))
                .frame(width: 18, height: 1.25)
                .rotationEffect(.degrees(-28))
                .offset(x: 1, y: -4)
            Capsule()
                .fill(color.opacity(0.42))
                .frame(width: 14, height: 1.25)
                .rotationEffect(.degrees(28))
                .offset(y: 4)
        }
        .rotationEffect(.degrees(-2))
        .accessibilityHidden(true)
    }
}

/// SwiftUI otherwise reports only the pencil pixels as the button's accessibility frame even
/// when a later `.frame` is 44 points. The nearly transparent fill makes the full target a real
/// rendered shape for hit testing and assistive technologies without drawing a button surface.
private struct LivingMarginButtonLabel: View {
    let color: Color

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.primary.opacity(0.001))

            LivingMarginStroke(color: color)
                .frame(width: 22, height: 18)
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
}

#if DEBUG
/// A deterministic UI-test surface for the interaction layer. The semantic anchoring itself is
/// covered against real Readium decorations in `LivingMarginTests`; this host lets XCUI verify
/// tap, edge swipe, next-note, edit refresh and every closing route without depending on a
/// developer's personal library.
struct LivingMarginsUITestFixture: View {
    @State private var noteTexts = [
        "This thought stayed beside the first passage.",
        "A second thought, further into the book."
    ]
    @State private var activeIndex: Int?

    private let chrome = ReaderChrome.forTheme(.carbon)

    var body: some View {
        ZStack(alignment: .trailing) {
            chrome.page.ignoresSafeArea()

            VStack(alignment: .leading, spacing: DipleSpace.xl) {
                Text("The page remembers where the reader paused, and the words continue in their own quiet measure.")
                Text("Another paragraph leaves enough paper at the right edge for a small human trace.")
            }
            .font(.system(.title3, design: .serif))
            .lineSpacing(7)
            .foregroundStyle(chrome.control)
            .padding(.horizontal, 44)

            Button {
                activeIndex = activeIndex == 0 ? nil : 0
            } label: {
                LivingMarginButtonLabel(color: chrome.control)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Note attached"))
            .accessibilityHint(Text("Show note"))
            .accessibilityIdentifier("livingMargins.marker.fixture")
            .padding(.trailing, 2)

            if let activeIndex {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { self.activeIndex = nil }
                            .accessibilityHidden(true)

                        LivingMarginPanel(
                            annotation: annotation(at: activeIndex),
                            chrome: chrome,
                            reduceMotion: false,
                            onClose: { self.activeIndex = nil },
                            onNext: {
                                self.activeIndex = min(activeIndex + 1, noteTexts.count - 1)
                            },
                            onPrevious: {
                                self.activeIndex = max(activeIndex - 1, 0)
                            },
                            onEdit: {
                                noteTexts[activeIndex] += " Revised."
                            }
                        )
                        .frame(width: min(430, geometry.size.width * 0.66))
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 22)
                .onEnded { value in
                    guard activeIndex == nil,
                          value.startLocation.x > UIScreen.main.bounds.width - 54,
                          value.translation.width < -44,
                          abs(value.translation.width) > abs(value.translation.height)
                    else { return }
                    activeIndex = 0
                }
        )
        .animation(.spring(response: 0.38, dampingFraction: 0.92), value: activeIndex != nil)
    }

    private func annotation(at index: Int) -> LivingMarginAnnotation {
        LivingMarginAnnotation(
            id: "fixture-\(index)",
            note: noteTexts[index],
            locator: Locator(
                href: AnyURL(string: "chapter.xhtml")!,
                mediaType: .xhtml,
                locations: .init(progression: Double(index) * 0.5)
            )
        )
    }
}
#endif
