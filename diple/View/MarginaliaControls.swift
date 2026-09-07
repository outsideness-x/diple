import SwiftUI

/// Whose words the board is showing, with the count each segment would produce.
///
/// The number is not decoration and not a vanity metric: it is the promise the segment makes,
/// taken with every other narrowing already applied, so pressing `Saved 12` shows twelve rows.
/// A scope with nothing in it at all is not drawn — an app holding only notes should not spend
/// a third of its control band offering a room that does not exist yet.
public struct MarginaliaScopeBar: View {
    @Binding var scope: MarginaliaScope
    let counts: (MarginaliaScope) -> Int
    let isAvailable: (MarginaliaScope) -> Bool

    public init(
        scope: Binding<MarginaliaScope>,
        counts: @escaping (MarginaliaScope) -> Int,
        isAvailable: @escaping (MarginaliaScope) -> Bool
    ) {
        _scope = scope
        self.counts = counts
        self.isAvailable = isAvailable
    }

    private var scopes: [MarginaliaScope] {
        MarginaliaScope.allCases.filter { isAvailable($0) || $0 == scope }
    }

    public var body: some View {
        // One room is not a choice.
        if scopes.count > 1 {
            HStack(spacing: DipleSpace.xs) {
                ForEach(scopes) { option in
                    Button {
                        HapticManager.shared.selection()
                        withAnimation(DipleMotion.snappy) { scope = option }
                    } label: {
                        segment(option)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.title), \(counts(option))")
                    .accessibilityAddTraits(scope == option ? [.isSelected] : [])
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func segment(_ option: MarginaliaScope) -> some View {
        let isSelected = scope == option
        return HStack(spacing: DipleSpace.xs) {
            Text(option.title)
                .dipleType(.footnote, weight: .semibold)
            Text("\(counts(option))")
                .dipleType(.footnote, weight: .regular)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(isSelected ? DipleColor.accentInk.opacity(0.7) : DipleColor.textQuaternary)
        }
        .foregroundStyle(isSelected ? DipleColor.accentInk : DipleColor.textTertiary)
        .padding(.horizontal, DipleSpace.m)
        .padding(.vertical, DipleSpace.s)
        .dipleSelected(isSelected, in: Capsule())
        .animation(DipleMotion.standard, value: counts(option))
    }
}

/// One name in the filter row.
///
/// Chosen, it carries a cross and no number: the count of a chip you have already pressed is
/// the count of the board, and that is printed on the scope segment two rows up. Unchosen, it
/// carries the number and no cross. One glyph or one number, never both — a capsule this small
/// has room for the label and one more thing.
public struct MarginaliaChip: View {
    public enum Kind {
        case lens(String)
        case source
        case tag
        /// A mark colour, carried as its stored hex. The chip is the swatch itself.
        case color(String)
    }

    let label: String
    let kind: Kind
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    public init(label: String, kind: Kind, count: Int, isSelected: Bool, action: @escaping () -> Void) {
        self.label = label
        self.kind = kind
        self.count = count
        self.isSelected = isSelected
        self.action = action
    }

    private var glyph: String? {
        switch kind {
        case .lens(let systemImage): return systemImage
        case .source: return "book.closed"
        case .tag, .color: return nil
        }
    }

    /// What a colour is called, resolved here rather than in `MarginaliaBoard`: naming one means
    /// reading the palette, and the transform is deliberately reachable without the theme. An
    /// imported or retired colour has no name to give and answers with itself.
    private var colorName: String {
        guard case .color(let hex) = kind else { return label }
        return DipleColor.Highlight.selectable.first { $0.hex == hex }?.name ?? hex
    }

    /// A source chip prints a name, not a catalogue entry.
    ///
    /// Shelves write `Sapiens: A Brief History of Humankind`, and a capsule carrying all of it
    /// is a paragraph — the same complaint `TagName.forSource` already answers for the tag a
    /// note is born with. Here it is cut rather than folded at the colon: two books whose names
    /// agree up to the colon are two different chips with two different counts, and folding
    /// would print them identically with nothing to tell them apart.
    private var isColor: Bool {
        if case .color = kind { return true }
        return false
    }

    private var text: String {
        if case .tag = kind { return "#\(label)" }
        return MarginaliaEntry.shortened(label, limit: 24)
    }

    /// A source is tinted even when it is not chosen — that tint is what tells a shelf from a
    /// word at a glance — so it rests on `accentSoft` rather than on the neutral overlay, the
    /// same trade `TagChipView` already makes.
    private var resting: Color {
        if case .source = kind { return DipleColor.accentSoft }
        return DipleColor.surfaceOverlay
    }

    private var foreground: Color {
        if isSelected { return DipleColor.accentInk }
        if case .source = kind { return DipleColor.accentInk }
        return DipleColor.textTertiary
    }

    public var body: some View {
        Button {
            HapticManager.shared.selection()
            withAnimation(DipleMotion.snappy) { action() }
        } label: {
            HStack(spacing: DipleSpace.xs) {
                if let glyph {
                    Image(systemName: glyph)
                        .dipleIcon(9)
                }

                if case .color(let hex) = kind {
                    // The swatch is the label. A colour has a name, but the reader chose it as
                    // a colour and recognises it as one; printing "Yellow" beside a yellow dot
                    // is the word for the thing next to the thing.
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 11, height: 11)
                } else {
                    Text(text)
                        .dipleType(.micro)
                        .lineLimit(1)
                }

                if isSelected {
                    Image(systemName: "xmark")
                        .dipleIcon(8, weight: .bold)
                } else if count > 0 {
                    Text("\(count)")
                        .dipleType(.micro, weight: .regular)
                        .monospacedDigit()
                        .foregroundStyle(DipleColor.textQuaternary)
                }
            }
            .foregroundColor(foreground)
            .diplePadding(.chip)
            .dipleSelected(isSelected, in: Capsule(), resting: resting)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isSelected
                ? "\(isColor ? colorName : text), selected. Remove"
                : "\(isColor ? colorName : text), \(count)"
        )
    }
}

/// Every source and every tag standing under the current narrowing, uncapped and searchable.
///
/// The row on the board shows what would narrow the most and stops; a library with sixty tags
/// still needs somewhere the sixtieth can be found, and scrolling a chip row sideways past
/// fifty-nine of them is not it.
public struct MarginaliaFilterSheet: View {
    @ObservedObject var model: MarginaliaViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    public init(model: MarginaliaViewModel) {
        self.model = model
    }

    private func matching(_ options: [MarginaliaFacetOption]) -> [MarginaliaFacetOption] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return options }
        return options.filter { $0.label.localizedStandardContains(needle) }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DipleSpace.xl) {
                        DipleSearchField(
                            text: $search,
                            prompt: "Find a source or a tag",
                            identifier: "marginalia.filter.search"
                        )

                        let sources = matching(model.sourceOptions)
                        if !sources.isEmpty {
                            section("SOURCES", count: sources.count) {
                                ForEach(sources) { option in
                                    optionRow(option)
                                }
                            }
                        }

                        let tags = matching(model.tagOptions)
                        if !tags.isEmpty {
                            section("TAGS", count: tags.count) {
                                ForEach(tags) { option in
                                    optionRow(option)
                                }
                            }
                        }

                        // Not searchable by name, and so not run through `matching`: a colour
                        // is picked by looking at it, and typing "yellow" to find yellow is the
                        // long way round a row of four dots.
                        if !model.colorOptions.isEmpty {
                            section("MARK", count: model.colorOptions.count) {
                                ForEach(model.colorOptions) { option in
                                    optionRow(option)
                                }
                            }
                        }

                        if sources.isEmpty && tags.isEmpty {
                            Text(
                                search.isEmpty
                                    ? "Nothing here carries a source or a tag yet."
                                    : "No source or tag matches that."
                            )
                            .dipleType(.callout)
                            .foregroundStyle(DipleColor.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DipleSpace.xxxl)
                        }
                    }
                    .padding(.horizontal, DipleSpace.xl)
                    .padding(.top, DipleSpace.l)
                    .padding(.bottom, DipleSpace.scrollBottom)
                }
            }
            .navigationTitle("Narrow to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if model.isNarrowed {
                        Button("Clear") {
                            HapticManager.shared.selection()
                            model.clearNarrowing()
                        }
                        .foregroundStyle(DipleColor.textTertiary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DipleColor.accentInk)
                }
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DipleSpace.s) {
            HStack {
                Text(title)
                    .dipleType(.nano)
                    .foregroundStyle(DipleColor.accentInk)
                Spacer()
                Text("\(count)")
                    .dipleType(.nano)
                    .monospacedDigit()
                    .foregroundStyle(DipleColor.textQuaternary)
            }
            content()
        }
    }

    private func optionRow(_ option: MarginaliaFacetOption) -> some View {
        Button {
            HapticManager.shared.selection()
            model.toggle(option)
        } label: {
            HStack(spacing: DipleSpace.m) {
                Image(systemName: option.isSelected ? "checkmark.circle.fill" : "circle")
                    .dipleIcon(15, weight: .regular)
                    .foregroundStyle(option.isSelected ? DipleColor.accentInk : DipleColor.textQuaternary)

                if case .color(let hex) = option.kind {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 13, height: 13)
                }

                Text(label(for: option))
                    .dipleType(.body)
                    .foregroundStyle(DipleColor.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: DipleSpace.s)

                Text("\(option.count)")
                    .dipleType(.footnote, weight: .regular)
                    .monospacedDigit()
                    .foregroundStyle(DipleColor.textQuaternary)
            }
            .padding(.vertical, DipleSpace.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func label(for option: MarginaliaFacetOption) -> String {
        switch option.kind {
        case .tag: return "#\(option.label)"
        case .color(let hex):
            return DipleColor.Highlight.selectable.first { $0.hex == hex }?.name ?? "Marked"
        case .source: return option.label
        }
    }
}
