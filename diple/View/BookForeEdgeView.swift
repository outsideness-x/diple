import SwiftUI
import ReadiumShared

/// One mark on the edge: a passage the reader saved, in the colour they saved it with.
public struct ForeEdgeMark: Identifiable, Equatable, Sendable {
    public let id: String
    public let progress: Double
    public let colorHex: String

    public init(id: String, progress: Double, colorHex: String) {
        self.id = id
        self.progress = progress
        self.colorHex = colorHex
    }
}

/// The book, seen from its edge.
///
/// A table of contents drawn as the object it describes: every chapter is a stretch of paper as
/// thick as it actually is, the reading position is a ribbon across it, and the passages the
/// reader marked are ticks in their own colours at the places they were marked. Three things a
/// list of rows cannot say at once — how long this chapter is, where I am in the book, and where
/// in it I have been leaving marks — said in one object without a single number.
///
/// Dragging along it opens a lens under the finger (see `ForeEdgeLens`): the pages fan apart
/// where the thumb is, the chapter there names itself, and releasing goes to it. That is what
/// makes an edge of two hundred chapters aimable, and it is also, not incidentally, what leafing
/// through a book with your thumb feels like.
public struct BookForeEdgeView: View {
    public let edge: BookForeEdge
    public let chapters: [ForeEdgeChapter]
    public let marks: [ForeEdgeMark]
    /// Where reading is now, in `totalProgression`.
    public let progress: Double
    public let onSelect: (ReadiumShared.Link) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focus: Double?
    @State private var focusedBandID: Int?

    /// The width of the paper itself. Wide enough for the fan to read as pages rather than as a
    /// hatched rectangle, narrow enough to leave the chapter names a real measure beside it.
    @ScaledMetric(relativeTo: .body) private var edgeWidth: CGFloat = 96
    /// One line per this many points at rest. Close enough to read as paper, far enough apart
    /// that a compressed chapter is still a texture and not a smear.
    private let pitch: CGFloat = 3.4

    public init(
        edge: BookForeEdge,
        chapters: [ForeEdgeChapter],
        marks: [ForeEdgeMark],
        progress: Double,
        onSelect: @escaping (ReadiumShared.Link) -> Void
    ) {
        self.edge = edge
        self.chapters = chapters
        self.marks = marks
        self.progress = progress
        self.onSelect = onSelect
    }

    public var body: some View {
        GeometryReader { geo in
            let height = max(geo.size.height - DipleSpace.xxl * 2, 1)
            let lens = ForeEdgeLens(focus: focus)
            let rects = bandRects(lens: lens, height: height)

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    draw(in: &context, size: size, rects: rects, lens: lens, height: height)
                }

                ForEach(labels(for: rects)) { label in
                    chapterLabel(label, width: geo.size.width)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(scrub(height: height))
        }
        .padding(.trailing, DipleSpace.l)
        .accessibilityRepresentation {
            // The canvas is a picture; VoiceOver gets the same chapters as an ordinary list,
            // which is the shape it can actually work with.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(edge.bands) { band in
                        Button {
                            select(band)
                        } label: {
                            Text(band.title)
                        }
                        .accessibilityValue(share(of: band))
                    }
                }
            }
        }
    }

    // MARK: - Geometry

    private struct BandRect {
        let band: ForeEdgeBand
        let minY: CGFloat
        let maxY: CGFloat
        var height: CGFloat { maxY - minY }
    }

    private func bandRects(lens: ForeEdgeLens, height: CGFloat) -> [BandRect] {
        edge.bands.map { band in
            BandRect(
                band: band,
                minY: CGFloat(lens.offset(for: band.start, height: Double(height))) + DipleSpace.xxl,
                maxY: CGFloat(lens.offset(for: band.end, height: Double(height))) + DipleSpace.xxl
            )
        }
    }

    /// Which chapters name themselves, and how.
    ///
    /// A book of sixty sections cannot label them all — at rest almost every band is a stripe
    /// too short to hold a line of type, and a column of nothing beside a block of paper is
    /// three quarters of the screen saying nothing. So at rest the edge names the parts (depth
    /// zero) that have room, and always names **the chapter being read**, which is the one label
    /// a reader mid-book actually wants. Under the thumb, the chapter there names itself
    /// whatever its depth and however thin it was a moment ago — that is what the lens is for.
    private func labels(for rects: [BandRect]) -> [Label] {
        if let focusedBandID, let rect = rects.first(where: { $0.band.id == focusedBandID }) {
            return [Label(rect: rect, kind: .focused)]
        }

        var placed: [Label] = []
        func place(_ rect: BandRect, _ kind: Label.Kind) {
            let y = anchor(of: rect)
            guard placed.allSatisfy({ abs(anchor(of: $0.rect) - y) >= Self.labelSpacing }) else { return }
            placed.append(Label(rect: rect, kind: kind))
        }

        // The chapter being read goes down first and keeps its place: it is the one name a
        // reader mid-book is looking for, and everything else arranges around it.
        if let current = edge.band(containing: progress)?.id,
           let rect = rects.first(where: { $0.band.id == current }) {
            place(rect, .reading)
        }

        // Then shallowest first, because a part is a better thing to print than the third
        // sub-section inside it. **Not depth zero only** — that rule read the publication's
        // nesting as if it meant something, and an article whose whole table of contents hangs
        // under one root printed exactly one name. Depth orders the candidates; spacing decides
        // how many there is room for.
        let depths = Set(rects.map(\.band.depth)).sorted()
        for depth in depths {
            for rect in rects where rect.band.depth == depth {
                place(rect, .resting)
            }
        }
        return placed
    }

    /// The closest two names may sit. One line of type plus air — below this they touch, and a
    /// column of overlapping chapter names is worse than a column of fewer of them.
    private static let labelSpacing: CGFloat = 24

    /// Where a chapter's name sits against its band: at the beginning of the chapter, like a
    /// tab, rather than floating in the middle of a stretch of paper it is naming the start of.
    private func anchor(of rect: BandRect) -> CGFloat {
        rect.minY + min(8, rect.height / 2)
    }

    private struct Label: Identifiable {
        enum Kind { case resting, reading, focused }
        let rect: BandRect
        let kind: Kind
        var id: Int { rect.band.id }
    }

    // MARK: - Drawing

    private func draw(
        in context: inout GraphicsContext,
        size: CGSize,
        rects: [BandRect],
        lens: ForeEdgeLens,
        height: CGFloat
    ) {
        let right = size.width
        let left = right - edgeWidth

        for rect in rects {
            // Depth as an inset on the inner edge: the contour of the paper block is the
            // book's own structure, which flattening a table of contents throws away.
            let inset = min(CGFloat(rect.band.depth) * 9, edgeWidth * 0.45)
            let x = left + inset
            // A hair of air at each end of a chapter is what makes a chapter legible as one
            // block of paper rather than as an unbroken hatch running the length of the book.
            // Proportional, because a fixed gap eats a third of a chapter that is ten points
            // tall and leaves nothing to see.
            let gap = min(1.5, rect.height * 0.12)
            let top = rect.minY + gap
            let bottom = max(top, rect.maxY - gap)
            guard bottom > top else { continue }

            let count = max(1, Int((bottom - top) / pitch))
            let step = (bottom - top) / CGFloat(count)
            let isFocused = rect.band.id == focusedBandID

            var lines = Path()
            for index in 0..<count {
                let y = top + step * (CGFloat(index) + 0.5)
                // A deterministic ragged outer edge. Paper is cut, not machined, and a block
                // of perfectly equal strokes reads as a barcode. Deterministic because a
                // texture that reshuffles on every frame of a drag is a shimmer, not paper.
                let jitter = Self.ragged(rect.band.id, index)
                lines.move(to: CGPoint(x: x, y: y))
                lines.addLine(to: CGPoint(x: right - jitter, y: y))
            }
            context.stroke(
                lines,
                with: .color(DipleColor.textPrimary.opacity(isFocused ? 0.5 : 0.26)),
                lineWidth: 0.75
            )
        }

        // The reader's own marks, on the inside of the block where they cannot be mistaken for
        // the paper. Their colours are the only colour on the edge apart from the ribbon.
        for mark in marks {
            let y = CGFloat(lens.offset(for: mark.progress, height: Double(height))) + DipleSpace.xxl
            var tick = Path()
            tick.move(to: CGPoint(x: left - 11, y: y))
            tick.addLine(to: CGPoint(x: left - 3, y: y))
            context.stroke(tick, with: .color(Color(hex: mark.colorHex)), lineWidth: 2)
        }

        // The ribbon: where reading is. It crosses the whole block and hangs a tail past the
        // outer edge, which is what a ribbon in a book does and what tells it apart from a
        // chapter rule at a glance.
        let ribbonY = CGFloat(lens.offset(for: min(max(progress, 0), 1), height: Double(height))) + DipleSpace.xxl
        var ribbon = Path()
        ribbon.move(to: CGPoint(x: left - 16, y: ribbonY))
        ribbon.addLine(to: CGPoint(x: right, y: ribbonY))
        context.stroke(ribbon, with: .color(DipleColor.accent), lineWidth: DipleStroke.progressLine)

        var tail = Path()
        tail.move(to: CGPoint(x: right, y: ribbonY - 4))
        tail.addLine(to: CGPoint(x: right, y: ribbonY + 4))
        tail.addLine(to: CGPoint(x: right - 5, y: ribbonY))
        tail.closeSubpath()
        context.fill(tail, with: .color(DipleColor.accent))
    }

    /// How far short of the outer edge this page line stops. A cheap, stable hash rather than a
    /// random number: the same line is the same length every frame of a drag.
    private static func ragged(_ band: Int, _ index: Int) -> CGFloat {
        let mixed = (band &* 2_654_435_761) &+ (index &* 40_503)
        return CGFloat((mixed >> 3) & 0x3) * 0.9
    }

    // MARK: - Labels

    @ViewBuilder
    private func chapterLabel(_ label: Label, width: CGFloat) -> some View {
        let column = max(width - edgeWidth - DipleSpace.l, 40)
        HStack(alignment: .firstTextBaseline, spacing: DipleSpace.s) {
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(label.rect.band.title)
                    .dipleType(label.kind == .focused ? .body : .caption, weight: label.kind == .resting ? .regular : .semibold)
                    .foregroundStyle(ink(for: label.kind))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(label.kind == .focused ? 3 : (label.kind == .reading ? 2 : 1))
                    .truncationMode(.tail)
                if label.kind != .resting, edge.isMeasured {
                    Text(share(of: label.rect.band))
                        .dipleType(.nano, weight: .medium)
                        .foregroundStyle(DipleColor.textQuaternary)
                }
            }
            // The chapter being read carries the same accent as the ribbon that marks it on the
            // paper, so the two halves of "you are here" are visibly one statement.
            if label.kind == .reading {
                Circle()
                    .fill(DipleColor.accent)
                    .frame(width: 5, height: 5)
                    .padding(.top, 5)
            }
        }
        .frame(width: column, alignment: .trailing)
        .position(
            x: column / 2,
            y: label.kind == .focused ? (label.rect.minY + label.rect.maxY) / 2 : anchor(of: label.rect)
        )
        .allowsHitTesting(false)
    }

    private func ink(for kind: Label.Kind) -> Color {
        switch kind {
        case .resting: return DipleColor.textTertiary
        case .reading: return DipleColor.accentInk
        case .focused: return DipleColor.textPrimary
        }
    }

    /// What share of the book this chapter is — the one number the edge is drawing, spelled out
    /// for the chapter the finger is on and for VoiceOver, which cannot see a thickness.
    private func share(of band: ForeEdgeBand) -> String {
        let percent = Int((band.span * 100).rounded())
        let position = Int((band.start * 100).rounded())
        guard edge.isMeasured else { return "Chapter \(band.id + 1)" }
        return percent >= 1 ? "\(percent)% of the book, from \(position)%" : "from \(position)%"
    }

    // MARK: - Scrubbing

    private func scrub(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // The finger is read in *resting* coordinates and the lens is then centred on
                // it, which is what keeps the chapter under the thumb from sliding out from
                // under it as the fan opens.
                let raw = (value.location.y - DipleSpace.xxl) / height
                let clamped = min(max(Double(raw), 0), 1)
                let band = edge.band(containing: clamped)
                if band?.id != focusedBandID {
                    HapticManager.shared.selection()
                }
                focus = clamped
                focusedBandID = band?.id
            }
            .onEnded { _ in
                defer { closeLens() }
                guard let id = focusedBandID, let band = edge.bands.first(where: { $0.id == id }) else { return }
                select(band)
            }
    }

    private func closeLens() {
        guard !reduceMotion else {
            focus = nil
            focusedBandID = nil
            return
        }
        // The fan closing is the one piece of motion here that is not the finger's own; the
        // tracking above is direct manipulation and stays live under Reduce Motion.
        withAnimation(DipleMotion.gentle) {
            focus = nil
            focusedBandID = nil
        }
    }

    private func select(_ band: ForeEdgeBand) {
        guard let chapter = chapters.first(where: { $0.id == band.id }) else { return }
        HapticManager.shared.impact(.light)
        onSelect(chapter.link)
    }
}
