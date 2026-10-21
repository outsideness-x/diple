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
                    .foregroundStyle(DipleColor.accentInk)
                VStack(alignment: .leading, spacing: DipleSpace.xs) {
                    Text("Quote tray").dipleType(.footnote, weight: .semibold)
                    Text("\(tray.pending.count) ready to weave into a note")
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textSecondary)
                }
                Spacer(minLength: 0)
                Button(action: onWrite) {
                    Label("Write", systemImage: "square.and.pencil")
                        .dipleType(.footnote, weight: .semibold)
                        .padding(.horizontal, DipleSpace.m)
                        .frame(minHeight: 44)
                        .background(DipleColor.accentSoft, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(DipleColor.accentInk)
                .accessibilityIdentifier("quoteTray.write")
            }
            .padding(DipleSpace.m)
            .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.l))
            .overlay {
                RoundedRectangle(cornerRadius: DipleRadius.l)
                    .stroke(DipleColor.accentInk.opacity(0.18), lineWidth: DipleStroke.hairline)
            }
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
                        Text("Quote tray").dipleType(.footnote, weight: .semibold)
                        Text("\(tray.pending.count)")
                            .dipleType(.caption, weight: .semibold)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Image(systemName: isCollapsed ? "chevron.up" : "chevron.down")
                            .dipleIcon(10, weight: .semibold)
                    }
                    .foregroundStyle(DipleColor.accentInk)
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
                    HStack(spacing: DipleSpace.m) {
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
        .background(.regularMaterial)
        .overlay(alignment: isRail ? .leading : .top) {
            Rectangle().fill(DipleColor.hairline)
                .frame(width: isRail ? DipleStroke.hairline : nil, height: isRail ? nil : DipleStroke.hairline)
        }
        .animation(motion, value: cards.map(\.id))
        .sheet(item: $preview) { clip in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: DipleSpace.l) {
                        Text(clip.text).dipleType(.editorialQuote).textSelection(.enabled)
                        if let source = clip.source {
                            Text(source).dipleType(.caption).foregroundStyle(DipleColor.textSecondary)
                        }
                    }
                    .padding(DipleSpace.xl)
                }
                .background(DipleColor.canvas)
                .navigationTitle("Passage")
                .toolbar { Button("Done") { preview = nil } }
            }
        }
    }

    private func tab(_ title: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(motion, action) } label: {
            Text(title).dipleType(.caption, weight: selected ? .semibold : .regular)
                .foregroundStyle(selected ? DipleColor.accentInk : DipleColor.textTertiary)
                .padding(.vertical, DipleSpace.s)
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
                    Image(systemName: "quote.opening")
                        .foregroundStyle(DipleColor.Highlight.color(forHex: clip.colorHex))
                    Text(clip.text)
                        .dipleType(.callout)
                        .foregroundStyle(DipleColor.textPrimary)
                        .lineLimit(isRail ? 6 : 2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: DipleSpace.s) {
                    Text(clip.source ?? String(localized: "Passage"))
                        .dipleType(.micro)
                        .foregroundStyle(DipleColor.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: showsUsed ? "arrow.uturn.backward" : "arrow.down.to.line")
                        .foregroundStyle(DipleColor.accentInk)
                }
            }
            .padding(DipleSpace.m)
            .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.m))
            // An edge, not a shadow: depth in this app is built from hairlines.
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: DipleRadius.m)
                    .stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline)
            }
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
                    if !tray.pending.isEmpty {
                        ForEach(tray.pending) { clip in
                            HStack {
                                VStack(alignment: .leading, spacing: DipleSpace.xs) {
                                    Text(clip.text).lineLimit(2).dipleType(.callout)
                                    if let source = clip.source { Text(source).dipleType(.caption).foregroundStyle(DipleColor.textTertiary) }
                                }
                                Spacer()
                                Button { tray.remove(clip.id) } label: {
                                    Image(systemName: "minus.circle").frame(minWidth: 44, minHeight: 44)
                                }
                                .accessibilityLabel("Remove from tray")
                            }
                            .padding(DipleSpace.m)
                            .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.m))
                        }
                        Divider()
                    }
                    ForEach(model.results) { entry in
                        if case .passage(let passage) = entry {
                            VStack(alignment: .leading, spacing: 0) {
                                PassageRowView(passage: passage)
                                QuoteTrayToggleButton(passage: passage)
                            }
                        }
                    }
                    if model.results.isEmpty {
                        Text("No passages found").foregroundStyle(DipleColor.textTertiary)
                    }
                }
                .padding(DipleSpace.l)
            }
            .background(DipleColor.canvas)
            .navigationTitle("Quote tray")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $model.rawQuery, prompt: "Search passages · #tag · @source")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
