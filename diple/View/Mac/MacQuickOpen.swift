#if targetEnvironment(macCatalyst)
import SwiftUI

/// ⌘K: go to a book or a passage without leaving the keyboard.
///
/// A field and a short list over the window, the way a desktop app's go-to panel is. A few
/// letters of a title or of a passage, Return to open the line that is lit, ↑ and ↓ to move
/// the light, Escape or a click outside to put the window back. A book opens in the reader at
/// its saved place; a passage opens its book at the passage.
///
/// What it matches, and why it is not the search index, is `QuickOpen`'s business. This is
/// only the panel — and it adds no place to the app: nothing here exists that the shelves and
/// Search Everything do not already reach. It is a shorter way to them, which is what makes a
/// desktop app feel like a tool rather than a set of screens.
struct MacQuickOpen: View {
    let books: [Book]
    let passages: [PassageItem]
    let onOpen: (QuickOpenItem) -> Void
    let onDismiss: () -> Void

    @State private var query: String
    /// The line Return opens. Reset to the first on every keystroke, because the list under
    /// it has just changed and a light left on the fourth line would open something the
    /// reader is no longer looking at.
    @State private var lit = 0
    @FocusState private var isFieldFocused: Bool

    init(
        books: [Book],
        passages: [PassageItem],
        initialQuery: String = "",
        onOpen: @escaping (QuickOpenItem) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.books = books
        self.passages = passages
        self.onOpen = onOpen
        self.onDismiss = onDismiss
        _query = State(initialValue: initialQuery)
    }

    private func results(limit: Int) -> [QuickOpenItem] {
        QuickOpen.results(for: query, books: books, passages: passages, limit: limit)
    }

    /// As many lines as the window has room for, up to eight. A list that ran past the bottom
    /// of a short window would need a scroll of its own, and a go-to panel that has to be
    /// scrolled has stopped being one; a shorter list says the same thing with fewer guesses.
    private func limit(forHeight height: CGFloat) -> Int {
        let room = height - Self.topInset - 150
        return min(max(Int(room / 52), 3), 8)
    }

    private static let topInset: CGFloat = 88

    private var isQueryEmpty: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // The window held back, not hidden: the panel is a moment over it.
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)
                    .accessibilityHidden(true)

                panel(results(limit: limit(forHeight: geometry.size.height)))
                    .padding(.top, Self.topInset)
                    .padding(.horizontal, DipleSpace.xxl)
            }
        }
        .background {
            // Escape closes the panel. A button rather than a key handler on the field, so it
            // is answered wherever the focus has wandered to inside the panel.
            Button("Close", action: onDismiss)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .onAppear { isFieldFocused = true }
    }

    private func panel(_ results: [QuickOpenItem]) -> some View {
        VStack(spacing: 0) {
            field(results)

            if !results.isEmpty {
                Rectangle()
                    .fill(DipleColor.separator)
                    .frame(height: DipleStroke.hairline)

                list(results)
            } else if !isQueryEmpty {
                Text("No book called that, and no passage that says it.")
                    .dipleType(.callout)
                    .foregroundStyle(DipleColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DipleSpace.l)
                    .padding(.vertical, DipleSpace.l)
            }

            keys
        }
        .frame(maxWidth: 580)
        .background(DipleColor.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: DipleRadius.l, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DipleRadius.l, style: .continuous)
                .strokeBorder(DipleColor.hairline, lineWidth: DipleStroke.hairline)
        }
        .shadow(color: .black.opacity(0.3), radius: 30, y: 14)
    }

    private func field(_ results: [QuickOpenItem]) -> some View {
        HStack(spacing: DipleSpace.m) {
            Image(systemName: "magnifyingglass")
                .dipleIcon(15, weight: .medium)
                .foregroundStyle(DipleColor.textTertiary)

            TextField("Go to a book or a passage", text: $query)
                .textFieldStyle(.plain)
                .dipleType(.title)
                .foregroundStyle(DipleColor.textPrimary)
                .focused($isFieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { open(at: lit, in: results) }
                .onKeyPress(.downArrow) {
                    move(by: 1, in: results)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    move(by: -1, in: results)
                    return .handled
                }
                .onChange(of: query) { _, _ in lit = 0 }
                .accessibilityIdentifier("mac.quickOpen.field")
        }
        .padding(.horizontal, DipleSpace.l)
        .padding(.vertical, DipleSpace.m)
    }

    private func list(_ results: [QuickOpenItem]) -> some View {
        VStack(alignment: .leading, spacing: DipleSpace.hair) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                if let heading = heading(before: index, in: results) {
                    Text(heading)
                        .dipleType(.caption, weight: .semibold)
                        .foregroundStyle(DipleColor.textTertiary)
                        .padding(.horizontal, DipleSpace.m)
                        .padding(.top, index == 0 ? DipleSpace.xs : DipleSpace.m)
                        .padding(.bottom, DipleSpace.xs)
                }

                row(item, isLit: index == lit)
                    .contentShape(Rectangle())
                    .onTapGesture { onOpen(item) }
                    .onHover { if $0 { lit = index } }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAddTraits(index == lit ? .isSelected : [])
            }
        }
        .padding(DipleSpace.s)
    }

    /// The heading a run of results starts with: what they are, and with nothing typed, why
    /// they are there.
    private func heading(before index: Int, in results: [QuickOpenItem]) -> String? {
        let isBook: (QuickOpenItem) -> Bool = {
            if case .book = $0 { return true } else { return false }
        }
        if index > 0, isBook(results[index]) == isBook(results[index - 1]) { return nil }
        if isQueryEmpty { return "Recently opened" }
        return isBook(results[index]) ? "Books" : "Passages"
    }

    @ViewBuilder
    private func row(_ item: QuickOpenItem, isLit: Bool) -> some View {
        HStack(spacing: DipleSpace.m) {
            switch item {
            case .book(let book):
                BookCoverView(
                    coverPath: book.coverPath,
                    title: book.title,
                    author: book.author,
                    isCompact: true
                )
                .frame(width: 24, height: 36)

                VStack(alignment: .leading, spacing: DipleSpace.hair) {
                    Text(book.title)
                        .dipleType(.editorialItem)
                        .foregroundStyle(DipleColor.textPrimary)
                        .lineLimit(1)
                    if let byline = book.sourceHost ?? book.author, !byline.isEmpty {
                        Text(byline)
                            .dipleType(.caption)
                            .foregroundStyle(DipleColor.textTertiary)
                            .lineLimit(1)
                    }
                }

            case .passage(let passage):
                Capsule(style: .continuous)
                    .fill(DipleColor.Highlight.color(forHex: passage.highlight.colorHex))
                    .frame(width: 2.5)
                    .padding(.vertical, DipleSpace.hair)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DipleSpace.hair) {
                    Text(passage.highlight.text)
                        .dipleType(.editorialExcerpt)
                        .foregroundStyle(DipleColor.textPrimary)
                        .lineLimit(2)
                    if let title = passage.book?.title ?? passage.highlight.bookTitle {
                        Text(title)
                            .dipleType(.caption)
                            .foregroundStyle(DipleColor.textTertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: DipleSpace.m)

            if isLit {
                Text("↩")
                    .dipleType(.callout, weight: .medium)
                    .foregroundStyle(DipleColor.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, DipleSpace.m)
        .padding(.vertical, DipleSpace.s)
        .background(
            isLit ? DipleColor.accentSoft : Color.clear,
            in: RoundedRectangle(cornerRadius: DipleRadius.s, style: .continuous)
        )
    }

    /// The keys, printed once under the list — the panel teaches itself.
    private var keys: some View {
        HStack(spacing: DipleSpace.l) {
            key("↩", "open")
            key("↑↓", "move")
            key("esc", "close")
            Spacer()
        }
        .padding(.horizontal, DipleSpace.l)
        .padding(.vertical, DipleSpace.s)
        .background(DipleColor.surface.opacity(0.6))
        .accessibilityHidden(true)
    }

    private func key(_ glyph: String, _ meaning: String) -> some View {
        HStack(spacing: DipleSpace.xs) {
            Text(glyph)
                .dipleType(.nano)
                .foregroundStyle(DipleColor.textSecondary)
            Text(meaning)
                .dipleType(.nano)
                .foregroundStyle(DipleColor.textQuaternary)
        }
    }

    private func move(by step: Int, in results: [QuickOpenItem]) {
        guard !results.isEmpty else { return }
        lit = min(max(lit + step, 0), results.count - 1)
    }

    private func open(at index: Int, in results: [QuickOpenItem]) {
        guard results.indices.contains(index) else { return }
        onOpen(results[index])
    }
}
#endif
