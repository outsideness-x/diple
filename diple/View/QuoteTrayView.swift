import SwiftUI

struct QuoteTrayToggleButton: View {
    let passage: PassageItem
    /// The ink to set the control in when it stands on something other than the app's own
    /// surfaces — the reader's glass, which takes the page's palette (`ReaderChrome`). `nil`
    /// keeps the interface's colours.
    var ink: Color? = nil
    @ObservedObject private var tray = QuoteTray.shared

    var body: some View {
        let collected = tray.contains(passage.id)
        Button {
            if collected { tray.remove(passage.id) } else { tray.collect([passage]) }
            HapticManager.shared.selection()
        } label: {
            Label(collected ? "In quote tray" : "Add to quote tray",
                  systemImage: collected ? "checkmark.rectangle.stack.fill" : "rectangle.stack.badge.plus")
                .dipleType(.caption, weight: .medium)
                .foregroundStyle(ink ?? (collected ? DipleColor.accentInk : DipleColor.textSecondary))
                .padding(.vertical, DipleSpace.s)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(collected ? "In quote tray" : "Add to quote tray")
        .accessibilityIdentifier("quoteTray.collect.\(passage.id)")
        .accessibilityHint(collected ? "Remove from the tray. The highlight stays in your library." : "Keep this passage beside your next note.")
    }
}

/// Available even with an empty tray, so material can also be gathered while writing.
struct QuoteTrayLibraryButton: View {
    @ObservedObject private var tray = QuoteTray.shared
    @State private var isPicking = false

    var body: some View {
        Button { isPicking = true } label: {
            Label("Quote tray", systemImage: "rectangle.stack")
                .labelStyle(.iconOnly)
                .dipleIcon(15)
                .foregroundStyle(DipleColor.accentInk)
        }
        .accessibilityLabel("Quote tray")
        .accessibilityValue("\(tray.pending.count)")
        .accessibilityIdentifier("quoteTray.open")
        .help("Choose passages for your note")
        .sheet(isPresented: $isPicking) { QuoteTrayPicker() }
    }
}

struct QuoteTrayLauncher: View {
    let onWrite: () -> Void
    @ObservedObject private var tray = QuoteTray.shared

    var body: some View {
        if !tray.pending.isEmpty {
            HStack(spacing: DipleSpace.m) {
                Image(systemName: "rectangle.stack.fill")
                    .dipleIcon(14, weight: .semibold)
                    .foregroundStyle(DipleColor.accentInk)
                VStack(alignment: .leading, spacing: DipleSpace.hair) {
                    Text("Quote tray")
                        .dipleType(.footnote, weight: .semibold)
                        .foregroundStyle(DipleColor.textPrimary)
                    Text("\(tray.pending.count) ready to weave into a note")
                        .dipleType(.caption)
                        .monospacedDigit()
                        .foregroundStyle(DipleColor.textSecondary)
                }
                Spacer(minLength: 0)
                Button(action: onWrite) {
                    Label("Write", systemImage: "square.and.pencil")
                        .dipleType(.footnote, weight: .semibold)
                        .padding(.horizontal, DipleSpace.m)
                        .frame(minHeight: 36)
                        .background(DipleColor.accentSoft, in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(DipleColor.accentInk.opacity(0.22), lineWidth: DipleStroke.hairline)
                        }
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DipleColor.accentInk)
                .accessibilityIdentifier("quoteTray.write")
            }
            .padding(.horizontal, DipleSpace.l)
            .padding(.vertical, DipleSpace.m)
            .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.m)
        }
    }
}

extension View {
    func quoteWorkbench(noteID: String, isPreviewing: Bool, onInsert: @escaping (QuoteClip) -> Void) -> some View {
        modifier(QuoteWorkbench(noteID: noteID, isPreviewing: isPreviewing, onInsert: onInsert))
    }
}

/// One editor hierarchy at every width: resizing never swaps out the live UITextView.
private struct QuoteWorkbench: ViewModifier {
    let noteID: String
    let isPreviewing: Bool
    let onInsert: (QuoteClip) -> Void
    @ObservedObject private var tray = QuoteTray.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var railWidth = 250.0

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            let beside = geometry.size.width >= railWidth + 420 && !typeSize.isAccessibilitySize
            let visible = !isPreviewing && (!tray.pending.isEmpty || tray.clips.contains { $0.usedInNoteID == noteID })
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if beside && visible {
                        QuoteTrayPanel(noteID: noteID, isRail: true, onInsert: onInsert)
                            .frame(width: railWidth)
                    }
                }
                if !beside && visible {
                    QuoteTrayPanel(noteID: noteID, isRail: false, onInsert: onInsert)
                }
            }
        }
    }
}

private struct QuoteTrayPanel: View {
    let noteID: String
    let isRail: Bool
    let onInsert: (QuoteClip) -> Void
    @ObservedObject private var tray = QuoteTray.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isCollapsed = false
    @State private var showsUsed = false
    @State private var preview: QuoteClip?
    @State private var stripHeight: CGFloat?
    @ScaledMetric(relativeTo: .body) private var cardWidth = 250.0

    private var used: [QuoteClip] { tray.clips.filter { $0.usedInNoteID == noteID } }
    private var cards: [QuoteClip] { showsUsed ? used : tray.pending }
    private var motion: Animation? { reduceMotion ? nil : DipleMotion.snappy }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DipleSpace.s) {
                Button {
                    withAnimation(motion) { isCollapsed.toggle() }
                } label: {
                    HStack(spacing: DipleSpace.s) {
                        Image(systemName: "rectangle.stack.fill")
                            .dipleIcon(13, weight: .semibold)
                            .foregroundStyle(DipleColor.accentInk)
                        Text("Quote tray")
                            .dipleType(.footnote, weight: .semibold)
                            .foregroundStyle(DipleColor.textPrimary)
                        Text("\(tray.pending.count)")
                            .dipleType(.micro, weight: .semibold)
                            .monospacedDigit()
                            .foregroundStyle(DipleColor.accentInk)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DipleColor.accentSoft, in: Capsule())
                            .contentTransition(.numericText())
                        Image(systemName: isCollapsed ? "chevron.up" : "chevron.down")
                            .dipleIcon(10, weight: .semibold)
                            .foregroundStyle(DipleColor.textTertiary)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCollapsed ? "Expand quote tray" : "Collapse quote tray")
                Spacer(minLength: 0)
                QuoteTrayLibraryButton()
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.horizontal, DipleSpace.m)

            if !isCollapsed {
                if !used.isEmpty {
                    HStack(spacing: DipleSpace.l) {
                        tab("Ready", selected: !showsUsed) { showsUsed = false }
                        tab("Used", selected: showsUsed) { showsUsed = true }
                        Spacer()
                    }
                    .padding(.horizontal, DipleSpace.m)
                }
                if cards.isEmpty {
                    Text("All woven in. Keep writing, or add more passages.")
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
                        .padding(DipleSpace.m)
                } else if isRail {
                    ScrollView {
                        LazyVStack(spacing: DipleSpace.m) {
                            ForEach(cards) { card($0) }
                        }
                        .padding(DipleSpace.m)
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: DipleSpace.m) {
                            ForEach(cards) { clip in
                                card(clip)
                                    .frame(width: min(cardWidth, 280))
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, DipleSpace.m)
                        .padding(.vertical, DipleSpace.s)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stripHeight = $0 }
                    }
                    .frame(height: stripHeight)
                    .scrollTargetBehavior(.viewAligned)
                    .accessibilityIdentifier("quoteTray.cards")
                }
            }
            if isRail { Spacer(minLength: 0) }
        }
        .background(DipleColor.surface)
        .overlay(alignment: isRail ? .leading : .top) {
            Rectangle().fill(DipleColor.separator)
                .frame(width: isRail ? DipleStroke.hairline : nil, height: isRail ? nil : DipleStroke.hairline)
        }
        .animation(motion, value: cards.map(\.id))
        .sheet(item: $preview) { clip in
            NavigationStack {
                ScrollView {
                    HStack(alignment: .top, spacing: DipleSpace.m) {
                        Capsule()
                            .fill(DipleColor.Highlight.color(forHex: clip.colorHex))
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: DipleSpace.m) {
                            Text(clip.text)
                                .dipleType(.editorialQuote)
                                .foregroundStyle(DipleColor.textPrimary)
                                .readingLineSpacing(for: clip.text)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let source = clip.source {
                                Text(source)
                                    .dipleType(.editorialItem)
                                    .foregroundStyle(DipleColor.textSecondary)
                            }
                        }
                    }
                    .padding(DipleSpace.xl)
                }
                .background(DipleColor.canvas.ignoresSafeArea())
                .navigationTitle("Passage")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(DipleColor.canvas, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { preview = nil }
                            .dipleType(.body, weight: .semibold)
                            .foregroundStyle(DipleColor.accentInk)
                    }
                }
            }
        }
    }

    private func tab(_ title: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(motion, action) } label: {
            VStack(spacing: DipleSpace.xs) {
                Text(title)
                    .dipleType(.caption, weight: selected ? .semibold : .regular)
                    .foregroundStyle(selected ? DipleColor.accentInk : DipleColor.textTertiary)
                Rectangle()
                    .fill(selected ? DipleColor.accentInk : Color.clear)
                    .frame(height: 1.5)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.top, DipleSpace.xs)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func card(_ clip: QuoteClip) -> some View {
        Button {
            if showsUsed {
                withAnimation(motion) { tray.restore(clip.id); showsUsed = false }
                HapticManager.shared.selection()
            } else {
                onInsert(clip)
            }
        } label: {
            VStack(alignment: .leading, spacing: DipleSpace.s) {
                HStack(alignment: .top, spacing: DipleSpace.s) {
                    Capsule()
                        .fill(DipleColor.Highlight.color(forHex: clip.colorHex))
                        .frame(width: 2.5)
                        .padding(.vertical, 2)
                    Text(clip.text)
                        .dipleType(.editorialExcerpt)
                        .foregroundStyle(DipleColor.textPrimary)
                        .readingLineSpacing(for: clip.text)
                        .lineLimit(isRail ? 6 : 2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: DipleSpace.s) {
                    Text(clip.source ?? String(localized: "Passage"))
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: showsUsed ? "arrow.uturn.backward" : "arrow.down.to.line")
                        .dipleIcon(11, weight: .semibold)
                        .foregroundStyle(DipleColor.accentInk)
                }
            }
            .padding(DipleSpace.m)
            .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.m)
            .contentShape(RoundedRectangle(cornerRadius: DipleRadius.m))
        }
        .buttonStyle(.readerControl)
        .help(showsUsed ? "Return to tray" : "Insert at cursor")
        .accessibilityLabel(clip.text)
        .accessibilityHint(showsUsed ? "Return to the tray. The text in your note stays." : "Insert this quotation and its source at the cursor.")
        .accessibilityIdentifier("quoteTray.insert.\(clip.id)")
        .contextMenu {
            Button("Read full passage") { preview = clip }
            Button("Remove from tray", role: .destructive) { tray.remove(clip.id) }
        }
        .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
    }
}

private struct QuoteTrayPicker: View {
    @StateObject private var model = MarginaliaViewModel(scope: .saved)
    @ObservedObject private var tray = QuoteTray.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DipleSpace.m) {
                    Text("Gather passages here, then tap their cards while writing. Your tray stays on this device.")
                        .dipleType(.callout)
                        .foregroundStyle(DipleColor.textSecondary)

                    DipleSearchField(
                        text: $model.rawQuery,
                        prompt: "Search passages · #tag · @source",
                        identifier: "quoteTray.search"
                    )

                    if !tray.pending.isEmpty {
                        VStack(alignment: .leading, spacing: DipleSpace.s) {
                            Text("ON THE TRAY")
                                .dipleType(.nano)
                                .foregroundStyle(DipleColor.textTertiary)
                                .padding(.top, DipleSpace.xs)

                            ForEach(tray.pending) { clip in
                                HStack(alignment: .top, spacing: DipleSpace.m) {
                                    Capsule()
                                        .fill(DipleColor.Highlight.color(forHex: clip.colorHex))
                                        .frame(width: 2.5)
                                        .padding(.vertical, 2)
                                    VStack(alignment: .leading, spacing: DipleSpace.xs) {
                                        Text(clip.text)
                                            .dipleType(.editorialExcerpt)
                                            .foregroundStyle(DipleColor.textPrimary)
                                            .readingLineSpacing(for: clip.text)
                                            .lineLimit(2)
                                        if let source = clip.source {
                                            Text(source)
                                                .dipleType(.caption)
                                                .foregroundStyle(DipleColor.textTertiary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    Button { tray.remove(clip.id) } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .dipleIcon(16)
                                            .foregroundStyle(DipleColor.textTertiary)
                                            .frame(minWidth: 44, minHeight: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove from tray")
                                }
                                .padding(DipleSpace.m)
                                .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.m)
                            }
                        }

                        Rectangle()
                            .fill(DipleColor.separator)
                            .frame(height: DipleStroke.hairline)
                            .padding(.vertical, DipleSpace.xs)
                    }

                    ForEach(model.results) { entry in
                        if case .passage(let passage) = entry {
                            pickerPassageRow(passage)
                        }
                    }

                    if model.results.isEmpty {
                        DipleEmptyText(
                            title: "No passages found",
                            message: "Try a different search, #tag, or @source."
                        )
                    }
                }
                .padding(.horizontal, DipleSpace.l)
                .padding(.vertical, DipleSpace.m)
            }
            .background(DipleColor.canvas.ignoresSafeArea())
            .navigationTitle("Quote tray")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .dipleType(.body, weight: .semibold)
                        .foregroundStyle(DipleColor.accentInk)
                }
            }
        }
    }

    private func pickerPassageRow(_ passage: PassageItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DipleSpace.m) {
                Capsule(style: .continuous)
                    .fill(DipleColor.Highlight.color(forHex: passage.highlight.colorHex))
                    .frame(width: 2.5)
                    .padding(.vertical, 2)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DipleSpace.s) {
                    Text(passage.highlight.text)
                        .dipleType(.editorialQuote)
                        .foregroundStyle(DipleColor.textPrimary)
                        .readingLineSpacing(for: passage.highlight.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(alignment: .center, spacing: DipleSpace.s) {
                        if let title = passage.book?.title ?? passage.highlight.bookTitle {
                            Text(title)
                                .dipleType(.editorialItem)
                                .foregroundStyle(DipleColor.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: DipleSpace.s)

                        QuoteTrayToggleButton(passage: passage)
                    }
                }
            }
            .padding(.vertical, DipleSpace.m)

            Rectangle()
                .fill(DipleColor.separator)
                .frame(height: DipleStroke.hairline)
        }
    }
}
