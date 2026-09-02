import SwiftUI

/// The app's search field. One implementation, used wherever a collection is filtered in place.
///
/// The library used `.searchable` and the board used a hand-built field, so the same act looked
/// like two different things one tab apart — a system bar that appears and collapses on its own
/// against a field that sits in the page. `.searchable` is the one that loses: it draws chrome
/// the app cannot bring onto its own material, and it needs a navigation bar to live in, which
/// these screens no longer have.
///
/// This is not a search *screen*. It narrows what is already on the page, which is why it sits
/// under the heading of the collection it narrows rather than above it — a field placed over
/// the thing it searches reads as a way to somewhere else, and there is a whole tab for that.
public struct DipleSearchField: View {
    @Binding var text: String
    let prompt: String
    /// For the UI tests, which need to find this field on two different screens.
    let identifier: String

    public init(text: Binding<String>, prompt: String, identifier: String) {
        self._text = text
        self.prompt = prompt
        self.identifier = identifier
    }

    public var body: some View {
        HStack(spacing: DipleSpace.s) {
            Image(systemName: "magnifyingglass")
                .dipleIcon(14)
                .foregroundStyle(DipleColor.textQuaternary)

            TextField(prompt, text: $text)
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textPrimary)
                // A query is not a sentence. Sentence capitalisation turned "house" into
                // "House" in the field, and autocorrect is worse than useless over a library
                // that mixes Russian, Korean and English in one index.
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier(identifier)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .dipleIcon(13)
                        .foregroundStyle(DipleColor.textQuaternary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .diplePadding(.field)
        .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.m))
        .overlay {
            RoundedRectangle(cornerRadius: DipleRadius.m)
                .stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline)
        }
    }
}

#Preview("Search field") {
    VStack(spacing: DipleSpace.l) {
        DipleSearchField(
            text: .constant(""),
            prompt: "Title, author or source",
            identifier: "preview.empty"
        )
        DipleSearchField(
            text: .constant("Пиранези"),
            prompt: "Search every note",
            identifier: "preview.filled"
        )
    }
    .padding(DipleSpace.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(DipleColor.canvas)
}
