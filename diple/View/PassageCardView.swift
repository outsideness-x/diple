import SwiftUI
import UIKit

/// A saved passage, set as a card that can leave the app as a picture.
///
/// This is the one thing readers do with a quotation that diple could not do: a passage shared
/// as text arrives in someone else's typeface, with the book's name lost somewhere in the
/// paragraph. Set on a page it becomes a quotation *from a book*, and the book is named under it
/// where an attribution belongs.
///
/// Everything on it already exists in the app's own language and nothing is invented for the
/// occasion: the ground is one of the reader's page themes, the passage is set in the editorial
/// face that sets passages everywhere else, the rule under it is drawn in the colour the reader
/// marked it with — the same rule that closes the row in the catalogue — and the wordmark signs
/// it exactly as the front page prints it.
struct PassageCardView: View {
    let passage: PassageItem
    let theme: ReaderPageTheme

    /// 360 points, rendered at 3×, is 1080 across — the width every messaging app and every
    /// social network resamples to. Fixed rather than fitted: a card whose width depended on
    /// the phone it was made on would come out a different picture on an iPad.
    static let width: CGFloat = 360

    private var ground: Color { Color(hex: theme.backgroundHex) }
    private var ink: Color { Color(hex: theme.inkHex) }
    private var markColor: Color { Color(hex: passage.highlight.colorHex) }

    private var sourceTitle: String? {
        let title = passage.book?.title ?? passage.highlight.bookTitle
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    private var sourceAuthor: String? {
        let author = passage.book?.author ?? passage.highlight.bookAuthor
        let trimmed = author?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(passage.highlight.text)
                .dipleType(.editorialLead)
                // The reader's own leading, because this card exists to be *read* — the
                // catalogue row is the place that had to give it up to stay scannable.
                .lineSpacing(7)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)

            // The mark, as the catalogue draws it: a fine stain of the colour the passage was
            // saved in, closing what it belongs to.
            Rectangle()
                .fill(markColor)
                .frame(width: 64, height: 2)
                .padding(.top, DipleSpace.xxl)

            if let sourceTitle {
                Text(sourceTitle)
                    .dipleType(.footnote, weight: .semibold)
                    .foregroundStyle(ink.opacity(0.85))
                    .padding(.top, DipleSpace.l)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let sourceAuthor {
                Text(sourceAuthor)
                    .dipleType(.caption)
                    .foregroundStyle(ink.opacity(0.55))
                    .padding(.top, DipleSpace.xs)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: DipleSpace.xxl)

            // The signature, at the size a colophon signs with rather than the size the front
            // page announces with: this card is about the passage, and the app is the last
            // thing on it.
            Text("diple.")
                .dipleType(.editorialTitle)
                .foregroundStyle(ink.opacity(0.28))
        }
        .padding(DipleSpace.xxxl)
        .frame(width: Self.width, alignment: .leading)
        // Square is the floor, not the shape: a two-line quotation on a tall card is a card of
        // empty paper, and a long one has to be allowed to grow rather than be cut off.
        .frame(minHeight: Self.width, alignment: .top)
        .background(ground)
    }
}

/// Turns the card into a picture.
///
/// `ImageRenderer` rather than a snapshot of a live view: this has to produce the same image
/// whether the sheet is on screen or not, at a scale that has nothing to do with the display it
/// was made on.
@MainActor
enum PassageCardRenderer {
    /// 3×, so the 360-point card lands at 1080 across whatever device made it — see
    /// `PassageCardView.width`.
    private static let scale: CGFloat = 3

    static func image(for passage: PassageItem, theme: ReaderPageTheme) -> UIImage? {
        let renderer = ImageRenderer(content: PassageCardView(passage: passage, theme: theme))
        renderer.scale = scale
        return renderer.uiImage
    }
}

/// The card, before it is sent.
///
/// A preview rather than a share sheet raised straight off the menu, and for one reason: what
/// leaves is a *picture*, and a picture is the one thing the reader cannot check afterwards.
/// The grounds are here for the same reason — a quotation posted onto a bright timeline and one
/// sent into a dark chat are not the same picture, and the reader is the only one who knows
/// which they are making.
struct PassageCardSheet: View {
    let passage: PassageItem

    @Environment(\.dismiss) private var dismiss
    /// Paper and Ink, not all four page themes: Sepia and Carbon are the same two answers a
    /// shade warmer, and a row of four swatches on a sheet with one job is a choice made to
    /// look thorough.
    @State private var theme: ReaderPageTheme = .paper

    private var rendered: UIImage? {
        PassageCardRenderer.image(for: passage, theme: theme)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DipleSpace.xxl) {
                    PassageCardView(passage: passage, theme: theme)
                        .clipShape(RoundedRectangle(cornerRadius: DipleRadius.m, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: DipleRadius.m, style: .continuous)
                                .stroke(DipleColor.separator, lineWidth: DipleStroke.hairline)
                        }
                        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 8)
                        .padding(.top, DipleSpace.l)

                    // The reader's own theme swatch, down to the exception it makes: the
                    // ground is the answer, so it keeps its colour and takes only the ring —
                    // laying `accentSoft` under it would show a paper the card will not have.
                    HStack(spacing: DipleSpace.m) {
                        ForEach([ReaderPageTheme.paper, .ink], id: \.self) { option in
                            let isSelected = theme == option
                            Button {
                                HapticManager.shared.selection()
                                theme = option
                            } label: {
                                HStack(spacing: DipleSpace.s) {
                                    Circle()
                                        .fill(Color(hex: option.inkHex))
                                        .frame(width: 10, height: 10)
                                    Text(option.title)
                                        .dipleType(.callout, weight: .medium)
                                        .foregroundColor(Color(hex: option.inkHex))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DipleSpace.m)
                                .background(Color(hex: option.backgroundHex))
                                .clipShape(RoundedRectangle(cornerRadius: DipleRadius.m, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: DipleRadius.m, style: .continuous)
                                        .stroke(
                                            isSelected ? DipleColor.accent : Color.clear,
                                            lineWidth: DipleStroke.selection
                                        )
                                }
                            }
                            .buttonStyle(.readerControl)
                            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, DipleSpace.xl)
                .padding(.bottom, DipleSpace.scrollBottom)
            }
            .background(DipleColor.canvas)
            .navigationTitle("Share as a card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    if let rendered {
                        let image = Image(uiImage: rendered)
                        ShareLink(
                            item: image,
                            preview: SharePreview(passage.highlight.text, image: image)
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share the card")
                    }
                }
            }
        }
    }
}
