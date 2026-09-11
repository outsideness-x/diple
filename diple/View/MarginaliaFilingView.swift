import SwiftUI

/// One pass over everything that was kept and never filed.
///
/// The `Unsorted` lens could already *find* them, and the board could already tag them — but
/// only one at a time, each through a row, a sheet and a dismissal. Filing twenty passages that
/// way is twenty round trips through a screen built for reading, and so it does not get done.
/// This is the same act with the reading taken out: one row at a time, the words the reader
/// actually uses under the thumb, and one button that means "next".
///
/// It walks a **snapshot** taken when it opens. Tagging a row files it, which by definition
/// removes it from the queue it is standing in; recomputing would make rows vanish under the
/// finger and turn a count of fourteen into a number that falls twice per tap.
public struct MarginaliaFilingView: View {
    @ObservedObject var model: MarginaliaViewModel
    @Environment(\.dismiss) private var dismiss

    /// Fixed at open. See the type's own note.
    private let queue: [MarginaliaEntry]

    @State private var index = 0
    /// The tags of the row on screen, written through on every change.
    @State private var tags: [String] = []
    @State private var isAddingTag = false
    @State private var tagDraft = ""
    @State private var filedCount = 0
    @State private var isConfirmingDelete = false

    /// How many words the row offers before the rest are left to the prompt. A filing pass is
    /// repetitive: the words that do the work are the ones already used, and a wall of sixty
    /// chips is a wall to read rather than a row to aim at.
    private let visibleVocabulary = 12

    public init(model: MarginaliaViewModel) {
        self.model = model
        self.queue = model.unsortedQueue
    }

    private var current: MarginaliaEntry? {
        index < queue.count ? queue[index] : nil
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                if let current {
                    pass(current)
                } else {
                    finished
                }
            }
            .navigationTitle("Unsorted")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DipleColor.accentInk)
                }
            }
            .alert("New tag", isPresented: $isAddingTag) {
                TextField("Tag", text: $tagDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add") { add(tagDraft) }
                Button("Cancel", role: .cancel) { tagDraft = "" }
            }
            .alert("Delete this?", isPresented: $isConfirmingDelete) {
                Button("Delete", role: .destructive) { deleteCurrent() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    current?.kind == .saved
                        ? "This passage and its comment will be removed."
                        : "It goes to Recently deleted in Notes for thirty days."
                )
            }
        }
        // The board reads the database again once, here, rather than on every chip tapped.
        .onDisappear { model.load() }
    }

    // MARK: - The pass

    private func pass(_ entry: MarginaliaEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            progress

            ScrollView {
                VStack(alignment: .leading, spacing: DipleSpace.xxl) {
                    subject(entry)
                    vocabulary(for: entry)
                }
                .padding(.horizontal, DipleSpace.xl)
                .padding(.top, DipleSpace.xl)
                .padding(.bottom, DipleSpace.xxxl)
            }
            .scrollDismissesKeyboard(.interactively)

            controls
        }
    }

    /// A rule that fills, not a row of numbers. The count is on it in the smallest type the app
    /// has, because the useful fact during a pass is *how much is left*, and a bar answers that
    /// without being read.
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

    @ViewBuilder
    private func subject(_ entry: MarginaliaEntry) -> some View {
        switch entry {
        case .passage(let passage):
            HStack(alignment: .top, spacing: DipleSpace.m) {
                Capsule()
                    .fill(Color(hex: passage.highlight.colorHex))
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: DipleSpace.s) {
                    Text(passage.highlight.text)
                        .dipleType(.editorialQuote)
                        .readingLineSpacing(for: passage.highlight.text)
                        .foregroundStyle(DipleColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let title = passage.book?.title ?? passage.highlight.bookTitle {
                        Text(title)
                            .dipleType(.caption)
                            .foregroundStyle(DipleColor.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .note(let item):
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
        }
    }

    private func vocabulary(for entry: MarginaliaEntry) -> some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            Text("FILE IT AS")
                .dipleType(.nano)
                .foregroundStyle(DipleColor.accentInk)

            FlowLayout(spacing: DipleSpace.s) {
                ForEach(offered(for: entry), id: \.self) { tag in
                    let isOn = tags.contains(tag)
                    Button {
                        HapticManager.shared.selection()
                        withAnimation(DipleMotion.snappy) { toggle(tag, on: entry) }
                    } label: {
                        Text("#\(tag)")
                            .dipleType(.micro)
                            .lineLimit(1)
                            .foregroundStyle(isOn ? DipleColor.accentInk : DipleColor.textTertiary)
                            .diplePadding(.chip)
                            .dipleSelected(isOn, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    tagDraft = ""
                    isAddingTag = true
                } label: {
                    HStack(spacing: DipleSpace.xs) {
                        Image(systemName: "plus")
                            .dipleIcon(10, weight: .semibold)
                        Text("New tag")
                            .dipleType(.micro)
                    }
                    .foregroundStyle(DipleColor.textTertiary)
                    .diplePadding(.chip)
                    .overlay(Capsule().stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The common words in their own fixed order, then anything this row carries that is not
    /// among them.
    ///
    /// Sorting what has been pressed to the front is the obvious move and the wrong one: the
    /// chip then leaves from under the finger that pressed it, and the next word the reader
    /// aimed at has moved too. The row has to stay where it was, which is also what lets a
    /// second and third tag be added without looking. A word typed into the prompt has no place
    /// in that order and joins at the end, where it was created.
    private func offered(for entry: MarginaliaEntry) -> [String] {
        let common = Array(model.vocabulary(for: entry.kind).prefix(visibleVocabulary))
        return common + tags.filter { !common.contains($0) }
    }

    /// One button, and its word is the state of the row. "Skip" and "Next" side by side would be
    /// two controls that do the identical thing, distinguished only by whether the reader had
    /// done something first — which the button can simply say.
    private var controls: some View {
        HStack(spacing: DipleSpace.m) {
            Button {
                isConfirmingDelete = true
            } label: {
                Image(systemName: "trash")
                    .dipleIcon(15, weight: .semibold)
                    .foregroundStyle(DipleColor.destructive)
                    .frame(width: 46, height: 46)
                    .background(DipleColor.surfaceOverlay, in: Circle())
            }
            .buttonStyle(.readerControl)
            .accessibilityLabel("Delete this")

            Spacer(minLength: 0)

            Button {
                HapticManager.shared.selection()
                withAnimation(DipleMotion.standard) { advance() }
            } label: {
                HStack(spacing: DipleSpace.s) {
                    Text(advanceTitle)
                        .dipleType(.footnote, weight: .semibold)
                    Image(systemName: index + 1 < queue.count ? "arrow.right" : "checkmark")
                        .dipleIcon(13, weight: .semibold)
                }
                .foregroundStyle(DipleColor.textOnAccent)
                .padding(.horizontal, DipleSpace.xl)
                .frame(minHeight: 46)
                .background(DipleColor.accent, in: Capsule())
            }
            .buttonStyle(.readerControl)
        }
        .padding(.horizontal, DipleSpace.xl)
        .padding(.vertical, DipleSpace.m)
        .background(.ultraThinMaterial)
    }

    private var advanceTitle: String {
        guard index + 1 < queue.count else { return "Finish" }
        return tags.isEmpty ? "Skip" : "Next"
    }

    private var finished: some View {
        VStack(spacing: DipleSpace.l) {
            Image(systemName: "tray")
                .dipleIcon(28, weight: .thin)
                .foregroundStyle(DipleColor.accentInk)

            Text(filedCount == 0 ? "Nothing filed" : "Filed \(filedCount) of \(queue.count)")
                .dipleType(.editorialTitle)
                .foregroundStyle(DipleColor.textPrimary)

            Text(
                filedCount == queue.count && queue.count > 0
                    ? "The inbox is clear."
                    : "What is left keeps its place in Unsorted."
            )
            .dipleType(.callout)
            .foregroundStyle(DipleColor.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DipleSpace.xxxl)

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

    // MARK: - Acting on the row

    private func toggle(_ tag: String, on entry: MarginaliaEntry) {
        if tags.contains(tag) {
            tags.removeAll { $0 == tag }
        } else {
            tags.append(tag)
        }
        // Written on the tap, not on the way to the next row. A pass abandoned halfway is the
        // normal way a pass ends, and everything pressed before that has to have counted.
        model.file(entry, tags: tags)
    }

    private func add(_ raw: String) {
        guard let tag = TagName.normalized(raw), let current else { return }
        tagDraft = ""
        guard !tags.contains(tag) else { return }
        tags.append(tag)
        model.file(current, tags: tags)
    }

    private func advance() {
        if !tags.isEmpty { filedCount += 1 }
        index += 1
        tags = current?.tags ?? []
    }

    private func deleteCurrent() {
        guard let current else { return }
        model.delete(current)
        index += 1
        tags = self.current?.tags ?? []
    }
}
