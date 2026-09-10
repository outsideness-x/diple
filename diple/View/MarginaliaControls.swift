import SwiftUI

/// One name in the filter row.
///
/// Chosen, it carries a cross and no number: the count of a chip you have already pressed is
/// the count of the board, and that is printed in the masthead. Unchosen, it
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

    /// Every chip rests on the same neutral overlay, chosen or not.
    ///
    /// A source used to rest on `accentSoft` so the tint would tell a shelf from a word — the
    /// trade `TagChipView` still makes on a note, where a book chip stands among three tags and
    /// nothing else. On a filter row it cost more than it bought: `dipleSelected` marks the
    /// chosen chip with *the same* `accentSoft` plus a ring, so an untouched shelf and a
    /// pressed word were the same amber capsule differing by a hairline, and a row of eight
    /// shelves was eight amber capsules that all looked switched on. The kinds are told apart
    /// here by where they stand — the row prints marks, then shelves, then words, with a rule
    /// between the runs — and by the glyph the shelf carries. That leaves the accent free to
    /// mean one thing on this row: chosen.
    private var resting: Color { DipleColor.surfaceOverlay }

    private var foreground: Color {
        if isSelected { return DipleColor.accentInk }
        if case .source = kind { return DipleColor.textSecondary }
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
                    //
                    // It carries its own hairline ring. Lilac and yellow are light enough to
                    // float free of the dark overlay and dark enough to disappear into the
                    // light one; a ring in the same ink as every other edge in the app gives
                    // the dot a border on both instead of a shape that changes with the theme.
                    Circle()
                        .fill(Color(hex: hex))
                        .overlay(Circle().strokeBorder(DipleColor.hairlineStrong, lineWidth: DipleStroke.hairline))
                        .frame(width: 12, height: 12)
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
            // A resting height, so the run of capsules reads as one band rather than as a
            // dot, a word and a book at three different sizes — and so a swatch chip, whose
            // content is 12 pt tall, is not a third of the target its neighbours offer.
            .frame(minHeight: 28)
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
