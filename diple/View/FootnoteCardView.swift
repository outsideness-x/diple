import SwiftUI

/// A note, printed at the foot of the page it was referred from.
///
/// **Why the foot of the page and not a popover at the marker.** Readium hands a tapped note to
/// the delegate as the note and its marker and nothing else — no point, no rect — and it cannot
/// do otherwise: a tap that lands on an interactive element never reaches `didTapAt` at all
/// (`EPUBSpreadView` forwards the tap only when `interactiveElement == nil`), so by the time the
/// note is in hand, where it was touched is already gone. A popover would have to invent an
/// anchor. The foot of the page needs none, and it is where the note was printed to begin with.
///
/// The short rule above the note is the printer's fillet, which is what separates notes from
/// text on a set page. It does the work a full-width border would do — saying where the text
/// stops — without drawing a second line across a page that already has one at its bottom edge.
struct FootnoteCardView: View {
    let footnote: Footnote
    let chrome: ReaderChrome
    let settings: ReaderSettings
    /// How much of the page the note may take before it starts scrolling inside itself.
    let maximumHeight: CGFloat
    let onClose: () -> Void

    @AccessibilityFocusState private var noteIsFocused: Bool

    /// A third of the measure, as a fillet is set. Not the full width: the rule is a mark on the
    /// page, not the edge of a panel.
    private static let filletWidth: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: DipleSpace.l) {
            Rectangle()
                .fill(chrome.separator)
                .frame(width: Self.filletWidth, height: DipleStroke.hairline)
                .accessibilityHidden(true)

            ScrollView {
                HStack(alignment: .firstTextBaseline, spacing: DipleSpace.s) {
                    if let marker = footnote.marker {
                        // Chrome ink, not accent — the same rule the percentage in the bottom bar
                        // follows. A note's number is a fact, not an action.
                        Text(marker)
                            .dipleType(.micro, weight: .semibold)
                            .foregroundStyle(chrome.secondary)
                            .monospacedDigit()
                            // The reader hears the note, not the numeral it was filed under.
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: DipleSpace.m) {
                        ForEach(Array(footnote.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph)
                                .readerProse(.readingBody, settings: settings)
                                .foregroundStyle(chrome.control)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            // A note is usually three lines, and a card that bounces for three lines reads as
            // something the reader failed to open properly.
            .scrollBounceBehavior(.basedOnSize)
            // A `ScrollView` takes every point it is offered, so a three-line note left a card
            // half a page tall with the note stranded at the top of it. `fixedSize` proposes no
            // height at all, which is what makes a scroll view report its *content's* height
            // instead; the ceiling above then clamps that, and only a note taller than the
            // ceiling scrolls. The card is as tall as the note, and no taller.
            .frame(maxHeight: maximumHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DipleSpace.xxl)
        .padding(.top, DipleSpace.l)
        .padding(.bottom, DipleSpace.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The page's own ground, opaque: this is still the page, and it has to continue Paper,
        // Sepia, Carbon or Ink byte for byte. The shadow above it is what says the note is lying
        // over running text rather than the paragraph having simply stopped there.
        .background(chrome.page)
        .shadow(color: Color.black.opacity(0.20), radius: 14, y: -4)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let vertical = value.predictedEndTranslation.height
                    guard vertical > 60, vertical > abs(value.predictedEndTranslation.width) else { return }
                    onClose()
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Footnote"))
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(named: Text("Close footnote"), onClose)
        .accessibilityFocused($noteIsFocused)
        .task(id: footnote.id) {
            noteIsFocused = true
        }
    }
}
