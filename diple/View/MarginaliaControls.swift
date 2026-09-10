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

/// How the sheet orders a list of names.
///
/// Two orders, because they answer two different questions. By count answers "what is this
/// board mostly made of", which is the right opening for a library of thirty names and the
/// order the chip row is built on. A–Z answers "where is the one I am thinking of", which is
/// the only question a list of three hundred can be asked: past the first screenful, a ranking
/// by size is an unordered list, and the reader is reduced to typing.
public enum MarginaliaFacetOrder: String, CaseIterable, Identifiable {
    case most
    case alphabetical

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .most: return "Most used"
        case .alphabetical: return "A–Z"
        }
    }
}

/// Every source and every tag standing under the current narrowing, uncapped and searchable.
///
/// The row on the board shows what would narrow the most and stops; a library with sixty tags
/// still needs somewhere the sixtieth can be found, and scrolling a chip row sideways past
/// fifty-nine of them is not it.
///
/// **At three hundred books this is not a list, it is the finder**, and it is built for that
/// reader rather than for the demo library. What that changed: the field takes the keyboard on
/// its own once the lists are long enough that scrolling is hopeless; what is already in force
/// stands at the top instead of sitting at its own rank among three hundred rows, where a
/// filter you switched on is a filter you cannot find to switch off; a source answers to its
/// author as well as to its title, because a reader looks for *Harari* at least as often as
/// for *Sapiens*; and the order can be turned to A–Z, with the initial standing over each run,
/// so a long list can be thumbed instead of only typed at.
///
/// Every one of those appears only when it is earned. A library with nine tags gets the sheet
/// it always had: no order control, no keyboard, no letters.
public struct MarginaliaFilterSheet: View {
    @ObservedObject var model: MarginaliaViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @FocusState private var isSearchFocused: Bool
    /// Bound, not merely offered. A bare `presentationDetents([.large, .medium])` opens on the
    /// *smallest* detent whatever the order of the set, so the finder came up half height with
    /// the keyboard over it — a search field and two rows.
    @State private var detent: PresentationDetent = .medium

    /// Remembered, because it is a statement about the size of the reader's library rather
    /// than about this visit. Somebody who needs A–Z needs it every time.
    @AppStorage("diple_marginalia_facet_order") private var storedOrder = MarginaliaFacetOrder.most.rawValue

    /// Above this many names in the longest list, the sheet stops being a list you read.
    ///
    /// It gates all three of the large-library affordances at once, deliberately: they answer
    /// the same problem, and a sheet that grew a segmented control at twelve names, a keyboard
    /// at twenty and letters at forty would be three different sheets on the way up.
    private static let finderThreshold = 24

    /// Under this, letters cost more than they give — a heading over one row is a heading per
    /// row. It is separate from `finderThreshold` because a library can be long in tags and
    /// short in sources, and the letters are per list.
    private static let letteringThreshold = 12

    public init(model: MarginaliaViewModel) {
        self.model = model
    }

    private var order: MarginaliaFacetOrder {
        get { MarginaliaFacetOrder(rawValue: storedOrder) ?? .most }
        nonmutating set { storedOrder = newValue.rawValue }
    }

    private var orderBinding: Binding<MarginaliaFacetOrder> {
        Binding(get: { order }, set: { newValue in
            HapticManager.shared.selection()
            withAnimation(DipleMotion.standard) { order = newValue }
        })
    }

    /// The longest list the sheet is holding — what decides whether this is a list or a finder.
    private var longestRun: Int {
        max(model.sourceOptions.count, model.tagOptions.count)
    }

    private var isFinder: Bool { longestRun > Self.finderThreshold }

    /// Matched against every name the option answers to, so a source is found by its author.
    private func matching(_ options: [MarginaliaFacetOption]) -> [MarginaliaFacetOption] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return ordered(options) }
        return ordered(options.filter { option in
            option.searchableNames.contains { $0.localizedStandardContains(needle) }
        })
    }

    /// The board hands these over ranked by count. A–Z re-sorts; `most` leaves them alone.
    private func ordered(_ options: [MarginaliaFacetOption]) -> [MarginaliaFacetOption] {
        guard order == .alphabetical else { return options }
        return options.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    /// The initial a name files under. Everything that is not a letter files under `#`, so a
    /// title opening on a digit or a quotation mark still has a heading to stand under rather
    /// than one heading each.
    private func initial(of option: MarginaliaFacetOption) -> String {
        guard let first = option.label.first(where: { !$0.isWhitespace }) else { return "#" }
        let folded = String(first).folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: .current
        )
        return folded.first?.isLetter == true ? folded.uppercased() : "#"
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DipleSpace.xl) {
                        DipleSearchField(
                            text: $search,
                            prompt: searchPrompt,
                            identifier: "marginalia.filter.search"
                        )
                        .focused($isSearchFocused)

                        if model.isNarrowed {
                            inForce
                        }

                        if isFinder {
                            orderControl
                        }

                        let sources = matching(model.sourceOptions)
                        if !sources.isEmpty {
                            section("SOURCES", count: sources.count) {
                                list(sources)
                            }
                        }

                        let tags = matching(model.tagOptions)
                        if !tags.isEmpty {
                            section("TAGS", count: tags.count) {
                                list(tags)
                            }
                        }

                        // Not searchable by name, and so not run through `matching`: a colour
                        // is picked by looking at it, and typing "yellow" to find yellow is the
                        // long way round a row of four dots. It keeps its own order too — four
                        // swatches have no alphabet.
                        if !model.colorOptions.isEmpty, search.isEmpty {
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
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Narrow to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DipleColor.accentInk)
                }
            }
            // Half height while it is a list you glance at; full height once it is the finder,
            // because a finder opens with the keyboard up and half a sheet minus a keyboard is
            // a search field over two rows. Medium stays available on the way back down.
            .presentationDetents([.medium, .large], selection: $detent)
            .presentationDragIndicator(.visible)
            // Only where scrolling has stopped being an option. On a library of nine tags the
            // keyboard would cover the very list the reader came to look at, to save them a tap
            // they were not going to make.
            .onAppear {
                guard isFinder else { return }
                detent = .large
                isSearchFocused = true
            }
        }
    }

    /// The field says what it can be asked. Two names on a source is worth advertising —
    /// nobody types an author into a box labelled "Find a source".
    private var searchPrompt: String {
        model.sourceOptions.contains { $0.detail != nil }
            ? "Find a source, an author or a tag"
            : "Find a source or a tag"
    }

    // MARK: - What is already on

    /// Everything in force, at the top, whatever kind it is — and the one control that takes it
    /// all off.
    ///
    /// A chosen name used to keep its rank among the others, which is survivable in a list of
    /// twelve and is the sheet's worst failure in a list of three hundred: the filter emptying
    /// the board is somewhere below the fold, indistinguishable from the ones that are off, and
    /// the reader has to search for a word they have already chosen in order to unchoose it.
    /// It is also the answer to "what am I even looking at" — the question a narrowed board
    /// with nothing in it always raises.
    ///
    /// `Clear` lives here rather than in the toolbar, where it used to sit opposite `Done`.
    /// A control that empties something belongs beside the something.
    private var inForce: some View {
        VStack(alignment: .leading, spacing: DipleSpace.s) {
            HStack {
                Text("IN FORCE")
                    .dipleType(.nano)
                    .foregroundStyle(DipleColor.accentInk)

                Spacer()

                Button {
                    HapticManager.shared.selection()
                    withAnimation(DipleMotion.standard) {
                        model.clearNarrowing()
                        search = ""
                    }
                } label: {
                    Text("Clear")
                        .dipleType(.micro, weight: .semibold)
                        .foregroundStyle(DipleColor.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear every filter")
            }

            FlowLayout(spacing: DipleSpace.s) {
                ForEach(chosenOptions) { option in
                    MarginaliaChip(
                        label: option.label,
                        kind: chipKind(for: option),
                        count: option.count,
                        isSelected: true
                    ) {
                        model.toggle(option)
                    }
                }

                ForEach(Array(model.lenses).sorted { $0.title < $1.title }, id: \.self) { lens in
                    MarginaliaChip(
                        label: lens.title,
                        kind: .lens(lens.systemImage),
                        count: 0,
                        isSelected: true
                    ) {
                        model.toggle(lens)
                    }
                }

                // The typed part of the narrowing is as much a reason the board is short as any
                // chip, and it is the one the reader cannot see from here at all — the board's
                // own field is behind this sheet.
                if !model.rawQuery.isEmpty {
                    Button {
                        HapticManager.shared.selection()
                        withAnimation(DipleMotion.standard) { model.rawQuery = "" }
                    } label: {
                        HStack(spacing: DipleSpace.xs) {
                            Image(systemName: "magnifyingglass")
                                .dipleIcon(9)
                            Text(MarginaliaEntry.shortened(model.rawQuery, limit: 24))
                                .dipleType(.micro)
                                .lineLimit(1)
                            Image(systemName: "xmark")
                                .dipleIcon(8, weight: .bold)
                        }
                        .foregroundStyle(DipleColor.accentInk)
                        .diplePadding(.chip)
                        .frame(minHeight: 28)
                        .dipleSelected(true, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Searching for \(model.rawQuery). Clear the search")
                }
            }
        }
    }

    /// Every chosen facet, marks first, in the order the row would print them.
    private var chosenOptions: [MarginaliaFacetOption] {
        model.facetOptions.filter(\.isSelected)
    }

    private func chipKind(for option: MarginaliaFacetOption) -> MarginaliaChip.Kind {
        switch option.kind {
        case .source: return .source
        case .tag: return .tag
        case .color(let hex): return .color(hex)
        }
    }

    // MARK: - Order

    private var orderControl: some View {
        Picker("Order", selection: orderBinding) {
            ForEach(MarginaliaFacetOrder.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Order the names")
    }

    // MARK: - Lists

    /// A run of names, under its initials once there are enough of them to lose one in.
    ///
    /// The letters scroll rather than pin. Pinning them would be better still — it is what
    /// Contacts does with the same list — but this stack carries its gutter as padding on the
    /// stack itself, so a pinned header cannot paint the full width and the rows would slide
    /// visibly through its margins. Widening a header past its own container is the kind of
    /// hand-tuned inset CLAUDE.md rules out, and doing it properly means re-cutting the sheet's
    /// layout. A scrolling initial is most of the scanning gain for none of that.
    @ViewBuilder
    private func list(_ options: [MarginaliaFacetOption]) -> some View {
        if order == .alphabetical, options.count > Self.letteringThreshold {
            let runs = Dictionary(grouping: options, by: initial)
                .sorted { lhs, rhs in
                    // `#` after the alphabet: it is the drawer for everything that has no
                    // letter, and a list opening on it opens on its own exceptions.
                    if (lhs.key == "#") != (rhs.key == "#") { return rhs.key == "#" }
                    return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
                }

            ForEach(runs, id: \.key) { initial, run in
                letterHeading(initial)

                ForEach(run) { option in
                    optionRow(option)
                }
            }
        } else {
            ForEach(options) { option in
                optionRow(option)
            }
        }
    }

    /// The initial, with the rule that carries it across the page.
    ///
    /// Set at `footnote` rather than at the `nano` the other headings use. A section heading is
    /// read once on the way past; an index letter is aimed at while the list is moving, and one
    /// 10 pt glyph at `textQuaternary` is not something a thumb can steer by — it disappeared
    /// into the rows on the first library big enough to need it. The rule does the rest: it is
    /// what makes the letter read as a division of the list rather than as a very short row.
    private func letterHeading(_ letter: String) -> some View {
        HStack(spacing: DipleSpace.s) {
            Text(letter)
                .dipleType(.footnote, weight: .semibold)
                .foregroundStyle(DipleColor.textTertiary)

            Rectangle()
                .fill(DipleColor.hairline)
                .frame(height: DipleStroke.hairline)
        }
        .padding(.top, DipleSpace.m)
        // Spoken headings would put a letter between every few rows of an already long list.
        // VoiceOver navigates this by name, not by initial.
        .accessibilityHidden(true)
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
                        .overlay(Circle().strokeBorder(DipleColor.hairlineStrong, lineWidth: DipleStroke.hairline))
                        .frame(width: 13, height: 13)
                }

                // Two lines for a source that has an author, one for everything else. The
                // author is not decoration: it is the other name this row answers to, and a
                // finder that matches a word it never shows looks broken when it hits.
                VStack(alignment: .leading, spacing: 1) {
                    Text(label(for: option))
                        .dipleType(.body)
                        .foregroundStyle(DipleColor.textPrimary)
                        .lineLimit(1)

                    if let detail = option.detail {
                        Text(detail)
                            .dipleType(.caption)
                            .foregroundStyle(DipleColor.textTertiary)
                            .lineLimit(1)
                    }
                }

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
        .accessibilityAddTraits(option.isSelected ? [.isSelected] : [])
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
