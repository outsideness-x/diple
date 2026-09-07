import SwiftUI
import ReadiumShared

/// One saved passage, as the contents list shows it: a dot in the colour it was marked with,
/// against the chapter it falls in.
public struct ContentsMark: Identifiable, Equatable, Sendable {
    public let id: String
    public let progress: Double
    public let colorHex: String

    public init(id: String, progress: Double, colorHex: String) {
        self.id = id
        self.progress = progress
        self.colorHex = colorHex
    }
}

/// The book's table of contents, as a table of contents.
///
/// A column of names is what this is for, and the names are the whole point: a chapter is found
/// by reading down the list, which is a thing a reader already knows how to do. What the list
/// adds — the one thing a bare list of rows cannot say — is **where the reader is**: the current
/// chapter is marked in the accent, carries the only bar on the screen for how far through it
/// reading has got, and the list opens scrolled to it rather than at the top.
///
/// Everything else is a column: the depth is an indent, the place a chapter begins is a
/// right-aligned percentage in the app's own unit, and the passages saved inside a chapter are
/// dots in their own colours. Percentages are printed only when the publication actually said
/// where its chapters begin — see `BookContents.isMeasured`.
public struct BookContentsView: View {
    public let contents: BookContents
    /// The chapter reading is in, decided by the sheet from the reader's own locator.
    public let currentID: Int?
    /// Where reading is, in `totalProgression` — the same 0…1 every locator carries.
    public let progress: Double
    public let marks: [ContentsMark]
    public let onSelect: (ReadiumShared.Link) -> Void

    public init(
        contents: BookContents,
        currentID: Int?,
        progress: Double,
        marks: [ContentsMark],
        onSelect: @escaping (ReadiumShared.Link) -> Void
    ) {
        self.contents = contents
        self.currentID = currentID
        self.progress = progress
        self.marks = marks
        self.onSelect = onSelect
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(contents.chapters) { chapter in
                        ContentsRowView(
                            chapter: chapter,
                            isCurrent: chapter.id == currentID,
                            isMeasured: contents.isMeasured,
                            progression: chapter.id == currentID && contents.isMeasured
                                ? chapter.progression(at: progress)
                                : nil,
                            isEstimated: chapter.id == currentID && !contents.isMeasured,
                            marks: marks(in: chapter),
                            onSelect: { onSelect(chapter.link) }
                        )
                        .id(chapter.id)
                    }

                }
                .padding(.horizontal, DipleSpace.l)
                .padding(.vertical, DipleSpace.m)
            }
            .onAppear {
                guard let currentID else { return }
                // Not animated and not deferred by a timer: the sheet should already be showing
                // the reader's own place when it finishes coming up, the way a book opens at the
                // ribbon rather than at the first page and scrolling from there.
                proxy.scrollTo(currentID, anchor: .center)
            }
        }
    }

    /// The passages saved inside a chapter, in the order they were marked.
    ///
    /// Dropped whole in a book that would not say where its chapters begin. The passages are
    /// real and their places in the book are exact; it is the *chapters* that are a guess there,
    /// so a dot would be claiming a passage was marked in a section it may be two sections away
    /// from. Same rule as the percentages, for the same reason.
    private func marks(in chapter: ContentsChapter) -> [ContentsMark] {
        guard contents.isMeasured else { return [] }
        return marks.filter { chapter.contains(min(max($0.progress, 0), 1)) }
    }
}

/// One chapter in the list.
private struct ContentsRowView: View {
    let chapter: ContentsChapter
    let isCurrent: Bool
    let isMeasured: Bool
    /// How far through this chapter reading has got, 0…1. Only ever set for the current chapter,
    /// and only in a book that measured itself.
    let progression: Double?
    /// Set on the current chapter of a book that would not say where its chapters begin, where
    /// the mark is the best guess available rather than a measurement.
    let isEstimated: Bool
    let marks: [ContentsMark]
    let onSelect: () -> Void

    /// Depth as an indent, capped: a table of contents nested five deep would otherwise spend
    /// half the width of a phone on air and truncate every title it holds.
    @ScaledMetric(relativeTo: .body) private var step: CGFloat = 14

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: DipleSpace.s) {
                HStack(alignment: .firstTextBaseline, spacing: DipleSpace.m) {
                    Text(chapter.title)
                        .dipleType(style, weight: weight)
                        .foregroundStyle(ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: DipleSpace.s)

                    if !marks.isEmpty {
                        markDots
                    }

                    trailing
                }

                if let progression {
                    reading(progression)
                }

                if isEstimated {
                    // Said out loud, and said *here*, under the mark it qualifies: a note at the
                    // foot of sixty rows is a note nobody reads, and this is the one row the
                    // list is guaranteed to have scrolled to. The percentages are dropped for
                    // the same reason — a fabricated number is worse than no number.
                    Text("Estimated — this book doesn\u{2019}t say where its chapters begin.")
                        .dipleType(.nano, weight: .regular)
                        .foregroundStyle(DipleColor.textTertiary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, chapter.depth == 0 ? DipleSpace.l : DipleSpace.m)
            .padding(.bottom, DipleSpace.m)
            .padding(.trailing, DipleSpace.m)
            .padding(.leading, DipleSpace.m + indent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                DipleColor.accentSoft.opacity(isCurrent ? 1 : 0),
                in: RoundedRectangle(cornerRadius: DipleRadius.s, style: .continuous)
            )
            // The tab down the leading edge, which is the half of "you are here" that survives
            // being glanced at: the eye finds an edge in a column faster than it reads a label.
            .overlay(alignment: .leading) {
                if isCurrent {
                    Capsule(style: .continuous)
                        .fill(DipleColor.accent)
                        .frame(width: 3)
                        .padding(.vertical, DipleSpace.s)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.bookCard)
        .accessibilityLabel(chapter.title)
        .accessibilityValue(accessibilityValue)
    }

    private var indent: CGFloat { CGFloat(min(chapter.depth, 3)) * step }

    /// Depth as type, so the shape of the book is legible without reading a single title: a part
    /// is set at the interface's own body size, a section under it a step down and a step
    /// lighter. Below the third level everything is one voice — a book that nests deeper than
    /// that is not saying anything more with the extra level.
    private var style: DipleTextStyle {
        switch chapter.depth {
        case 0: return .body
        case 1: return .callout
        default: return .footnote
        }
    }

    private var weight: Font.Weight {
        if isCurrent { return .semibold }
        return chapter.depth == 0 ? .medium : .regular
    }

    private var ink: Color {
        if isCurrent { return DipleColor.accentInk }
        switch chapter.depth {
        case 0: return DipleColor.textPrimary
        case 1: return DipleColor.textSecondary
        default: return DipleColor.textTertiary
        }
    }

    /// The right-hand column: `READING` on the chapter being read, and where a chapter begins on
    /// every other one — the nearest thing an EPUB has to a page number, in the unit the reader
    /// already sees at the bottom of the page.
    @ViewBuilder
    private var trailing: some View {
        if isCurrent {
            Text("READING")
                .dipleType(.nano, weight: .semibold)
                .foregroundStyle(DipleColor.accentInk)
        } else if isMeasured {
            Text("\(Int((chapter.start * 100).rounded()))%")
                .dipleType(.nano, weight: .regular)
                .monospacedDigit()
                .foregroundStyle(DipleColor.textQuaternary)
        }
    }

    /// The passages saved in this chapter, as dots in the colours they were marked with. Three
    /// at most, and one per colour: past that it is a texture rather than a count, and the
    /// Highlights tab is one tap away and holds them all.
    private var markDots: some View {
        HStack(spacing: 3) {
            ForEach(colours.prefix(3), id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 4, height: 4)
            }
        }
        .opacity(0.85)
        .accessibilityHidden(true)
    }

    /// How far through this chapter reading has got. The one bar on the screen, on the one row
    /// it is true of — the question a reader mid-book actually has, and the one a column of
    /// names has never been able to answer.
    private func reading(_ progression: Double) -> some View {
        HStack(spacing: DipleSpace.s) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(DipleColor.hairlineStrong)
                    Capsule(style: .continuous)
                        .fill(DipleColor.accent)
                        .frame(width: max(2, geo.size.width * progression))
                }
            }
            .frame(height: 2)

            Text("\(Int((progression * 100).rounded()))%")
                .dipleType(.nano, weight: .medium)
                .monospacedDigit()
                .foregroundStyle(DipleColor.accentInk)
        }
    }

    /// One dot per colour, in the order the passages were marked.
    private var colours: [String] {
        var seen = Set<String>()
        return marks.compactMap { seen.insert($0.colorHex).inserted ? $0.colorHex : nil }
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if isCurrent {
            parts.append("Reading")
            if let progression { parts.append("\(Int((progression * 100).rounded()))% through this chapter") }
            if isEstimated { parts.append("estimated position") }
        } else if isMeasured {
            parts.append("from \(Int((chapter.start * 100).rounded()))%")
        }
        if !marks.isEmpty { parts.append(marks.count == 1 ? "1 saved passage" : "\(marks.count) saved passages") }
        return parts.joined(separator: ", ")
    }
}
