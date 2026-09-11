import SwiftUI

/// One pass over the Inbox: a note at a time, the spaces under the thumb.
///
/// The same ritual the board's `Unsorted` pass already is (`MarginaliaFilingView`), with a
/// different vocabulary. There a passage can carry several words, so the pass waits for the reader
/// to say "next"; here a note lives in one place, so choosing the place *is* next — one tap files
/// the note and brings up the one after it. Skipping is a button, deleting is a button, and
/// nothing asks.
///
/// It walks a **snapshot** taken when it opens: filing a note takes it out of the Inbox by
/// definition, and a queue recomputed under the finger would lose its place on every tap.
struct NotesFilingView: View {
    @ObservedObject var model: NotesWorkshopModel
    @Environment(\.dismiss) private var dismiss

    private let queue: [NoteItem]
    /// The spaces in the order the pass offers them, fixed at open for the reason the board's
    /// pass fixes its words: a chip that moves after it is pressed moves the next one too.
    private let spaces: [NoteSpace]

    @State private var index = 0
    @State private var filedCount = 0
    @State private var isCreatingSpace = false
    /// Spaces made during the pass, appended at the end of the row where they were made.
    @State private var madeHere: [NoteSpace] = []

    init(model: NotesWorkshopModel) {
        self.model = model
        self.queue = model.inbox
        // Most used first — filing is repetitive and the same few places do most of it — and by
        // the reader's own order among equals.
        let counts = model.spaceCounts
        self.spaces = model.spaces.enumerated()
            .sorted { lhs, rhs in
                let left = counts[lhs.element.id] ?? 0
                let right = counts[rhs.element.id] ?? 0
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private var current: NoteItem? {
        index < queue.count ? queue[index] : nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()
                if let current {
                    pass(current)
                } else {
                    finished
                }
            }
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DipleColor.accentInk)
                }
            }
            .sheet(isPresented: $isCreatingSpace) {
                NoteSpaceEditor { name, symbol in
                    guard let space = model.createSpace(named: name, symbol: symbol) else { return }
                    madeHere.append(space)
                    file(into: space)
                }
            }
        }
        // The workshop reads the database again once, here, rather than on every note filed.
        .onDisappear { model.load() }
    }

    // MARK: - The pass

    private func pass(_ item: NoteItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            progress

            ScrollView {
                VStack(alignment: .leading, spacing: DipleSpace.xxl) {
                    VStack(alignment: .leading, spacing: DipleSpace.s) {
                        Text(item.displayTitle)
                            .dipleType(.title)
                            .foregroundStyle(item.isUntitled ? DipleColor.textTertiary : DipleColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !item.previewText.isEmpty {
                            Text(item.previewText)
                                .dipleType(.callout)
                                .readingLineSpacing(for: item.previewText)
                                .foregroundStyle(DipleColor.textSecondary)
                                .lineLimit(8)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .id(item.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))

                    destinations
                }
                .padding(.horizontal, DipleSpace.xl)
                .padding(.top, DipleSpace.xl)
                .padding(.bottom, DipleSpace.xxxl)
            }

            controls
        }
    }

    /// A rule that fills, and the count in the smallest type: the useful fact during a pass is
    /// how much is left, and a bar answers that without being read.
    private var progress: some View {
        VStack(alignment: .leading, spacing: DipleSpace.xs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(DipleColor.separator)
                    Rectangle()
                        .fill(DipleColor.accent)
                        .frame(width: geo.size.width * (Double(index) / Double(max(queue.count, 1))))
                }
            }
            .frame(height: DipleStroke.progressLine)
            .animation(DipleMotion.standard, value: index)

            Text("\(index + 1) of \(queue.count)")
                .dipleType(.nano)
                .monospacedDigit()
                .foregroundStyle(DipleColor.textQuaternary)
                .padding(.horizontal, DipleSpace.xl)
        }
        .padding(.top, DipleSpace.s)
    }

    private var destinations: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            Text("PUT IT IN")
                .dipleType(.nano)
                .foregroundStyle(DipleColor.accentInk)

            FlowLayout(spacing: DipleSpace.s) {
                ForEach(spaces + madeHere) { space in
                    Button {
                        file(into: space)
                    } label: {
                        HStack(spacing: DipleSpace.xs) {
                            Image(systemName: space.symbol)
                                .dipleIcon(11)
                            Text(space.name)
                                .dipleType(.footnote)
                                .lineLimit(1)
                        }
                        .foregroundStyle(DipleColor.textSecondary)
                        .diplePadding(.chip)
                        .frame(minHeight: 36)
                        .background(DipleColor.surfaceOverlay, in: Capsule())
                    }
                    .buttonStyle(.readerControl)
                }

                Button {
                    HapticManager.shared.selection()
                    isCreatingSpace = true
                } label: {
                    HStack(spacing: DipleSpace.xs) {
                        Image(systemName: "plus")
                            .dipleIcon(10, weight: .semibold)
                        Text("New space")
                            .dipleType(.footnote)
                    }
                    .foregroundStyle(DipleColor.textTertiary)
                    .diplePadding(.chip)
                    .frame(minHeight: 36)
                    .overlay(Capsule().stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: DipleSpace.m) {
            Button {
                guard let current else { return }
                HapticManager.shared.impact(.light)
                // No question: it goes to Recently deleted, like every note deleted anywhere.
                model.trash([current])
                advance(filed: false)
            } label: {
                Image(systemName: "trash")
                    .dipleIcon(15, weight: .semibold)
                    .foregroundStyle(DipleColor.destructive)
                    .frame(width: 46, height: 46)
                    .background(DipleColor.surfaceOverlay, in: Circle())
            }
            .buttonStyle(.readerControl)
            .accessibilityLabel("Delete this note")

            Spacer(minLength: 0)

            Button {
                HapticManager.shared.selection()
                advance(filed: false)
            } label: {
                Text(index + 1 < queue.count ? "Leave in Inbox" : "Finish")
                    .dipleType(.footnote, weight: .semibold)
                    .foregroundStyle(DipleColor.textSecondary)
                    .padding(.horizontal, DipleSpace.xl)
                    .frame(minHeight: 46)
                    .background(DipleColor.surfaceOverlay, in: Capsule())
            }
            .buttonStyle(.readerControl)
        }
        .padding(.horizontal, DipleSpace.xl)
        .padding(.vertical, DipleSpace.m)
        .background(.ultraThinMaterial)
    }

    private var finished: some View {
        VStack(spacing: DipleSpace.l) {
            Image(systemName: "tray")
                .dipleIcon(28, weight: .thin)
                .foregroundStyle(DipleColor.accentInk)

            Text(filedCount == 0 ? "Nothing filed" : "Filed \(filedCount) of \(queue.count)")
                .dipleType(.editorialTitle)
                .foregroundStyle(DipleColor.textPrimary)

            Text(filedCount == queue.count && queue.count > 0
                ? "The Inbox is clear."
                : "What is left waits in the Inbox.")
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
                .multilineTextAlignment(.center)

            Button("Done") { dismiss() }
                .dipleType(.body, weight: .semibold)
                .foregroundStyle(DipleColor.textOnAccent)
                .diplePadding(.buttonLarge)
                .background(DipleColor.accent, in: Capsule())
                .buttonStyle(.plain)
                .padding(.top, DipleSpace.s)
        }
        .frame(maxWidth: .infinity)
        .padding(DipleSpace.xl)
    }

    // MARK: - Acting on the note

    /// Written on the tap, and without reloading the workshop: a pass abandoned halfway is the
    /// normal way a pass ends, and everything filed before that must have counted — but a full
    /// re-read of every note per tap is what would make filing twenty feel like work.
    private func file(into space: NoteSpace) {
        guard let current else { return }
        HapticManager.shared.impact(.light)
        model.move([current], to: space, reload: false)
        advance(filed: true)
    }

    private func advance(filed: Bool) {
        if filed { filedCount += 1 }
        withAnimation(DipleMotion.standard) { index += 1 }
    }
}
