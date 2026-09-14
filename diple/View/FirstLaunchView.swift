import SwiftUI

enum FirstLaunchStorage {
    static let completionKey = "diple_has_completed_first_launch"

    /// What the invitation at the foot of the intro says once the mark has been written.
    ///
    /// There is nothing to tap on a Mac. The word is the first thing the app ever says to a
    /// desktop reader, and it was telling them to do something their machine cannot do.
    static var invitation: String {
        #if targetEnvironment(macCatalyst)
        return "CLICK TO BEGIN"
        #else
        return "TAP TO BEGIN"
        #endif
    }
}

/// The one-time opening title for a new installation.
///
/// This is intentionally a short piece of identity rather than onboarding: there are no
/// permissions to ask for and no controls to teach before someone has a book. The reader has
/// just tapped `>d.` on the Home Screen, and the app opens by writing that same mark by hand,
/// stroke by stroke, then sets one sentence under it and waits. A tap during the writing ends
/// it; the invitation to begin appears only once there is nothing left to skip, so no word on
/// the screen ever describes something the tap will not do.
public struct FirstLaunchGate<Content: View>: View {
    @AppStorage(FirstLaunchStorage.completionKey) private var hasCompletedFirstLaunch = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLeaving = false
    @State private var hasCompletedForcedRun = false

    private let content: Content
    /// UI tests need to reproduce an installation without deleting the simulator's real
    /// library. Unlike overriding the UserDefaults key through the argument domain, this flag
    /// does not keep forcing the persisted value back to `false` after the intro finishes.
    private let isForcedForTesting = ProcessInfo.processInfo.arguments.contains("-diple-test-first-launch")

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ZStack {
            content
                .opacity(!isPresenting || isLeaving ? 1 : 0)
                .scaleEffect(!isPresenting || isLeaving || reduceMotion ? 1 : 0.985)
                .allowsHitTesting(!isPresenting)
                .accessibilityHidden(isPresenting)

            if isPresenting {
                FirstLaunchView(onFinish: finish)
                    .opacity(isLeaving ? 0 : 1)
                    .scaleEffect(isLeaving && !reduceMotion ? 1.035 : 1)
                    .allowsHitTesting(!isLeaving)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .background(DipleColor.canvas.ignoresSafeArea())
        .statusBarHidden(isPresenting)
    }

    private var isPresenting: Bool {
        !hasCompletedForcedRun && (!hasCompletedFirstLaunch || isForcedForTesting)
    }

    private func finish() {
        guard !isLeaving else { return }

        if reduceMotion {
            hasCompletedFirstLaunch = true
            hasCompletedForcedRun = true
            return
        }

        withAnimation(DipleMotion.gentle) {
            isLeaving = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(520))
            hasCompletedFirstLaunch = true
            hasCompletedForcedRun = true
        }
    }
}

private struct FirstLaunchView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = PenClock()
    @State private var hasFinishedStory = false

    var body: some View {
        GeometryReader { proxy in
            let shortestSide = min(proxy.size.width, proxy.size.height)
            let markWidth = min(max(shortestSide * 0.42, 148), 220)
            let elapsed = hasFinishedStory ? LaunchScript.duration : clock.elapsed
            let tagline = Self.segment(elapsed, from: LaunchScript.taglineStart, to: LaunchScript.taglineEnd)

            ZStack {
                DipleColor.canvas

                VStack(spacing: DipleSpace.xxl) {
                    LaunchMarkView(clock: elapsed, width: markWidth)

                    Text("A place for what stays with you.")
                        .dipleType(.callout)
                        .foregroundStyle(DipleColor.textTertiary)
                        .multilineTextAlignment(.center)
                        .opacity(tagline)
                        .offset(y: (1 - tagline) * 6)
                }
                .padding(.horizontal, DipleSpace.xl)

                VStack {
                    Spacer()

                    Text(FirstLaunchStorage.invitation)
                        .dipleType(.nano)
                        .foregroundStyle(DipleColor.textQuaternary)
                        .opacity(hasFinishedStory ? 1 : 0)
                        .padding(.bottom, max(proxy.safeAreaInsets.bottom, DipleSpace.xxl))
                }
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: onFinish)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Welcome to diple. A place for what stays with you.")
            .accessibilityHint(hasFinishedStory ? "Double tap to begin" : "Double tap to skip the introduction")
            .accessibilityAddTraits(.isButton)
        }
        .onAppear(perform: playStory)
        .onDisappear(perform: clock.stop)
        .onChange(of: clock.elapsed >= LaunchScript.duration) { _, hasArrived in
            guard hasArrived else { return }
            withAnimation(DipleMotion.gentle) {
                hasFinishedStory = true
            }
        }
    }

    private func playStory() {
        guard !hasFinishedStory else { return }

        if reduceMotion {
            hasFinishedStory = true
        } else {
            clock.start()
        }
    }

    fileprivate static func segment(_ value: Double, from: Double, to: Double) -> Double {
        guard to > from else { return value >= to ? 1 : 0 }
        let normalized = min(max((value - from) / (to - from), 0), 1)
        return normalized * normalized * (3 - 2 * normalized)
    }
}

/// When each beat happens, in seconds of `PenClock` time.
///
/// The pen moves at roughly handwriting pace — about 1100 font units a second, a little faster
/// on the downstroke of the `d` — and lifts between strokes for as long as a hand takes to
/// travel to the next one. The silence before the first stroke is what lets the system launch
/// screen, which is the same canvas, read as the page the mark is about to be written on.
private enum LaunchScript {
    static let taglineStart = 2.75
    static let taglineEnd = 3.35
    static let duration = 3.35
}

/// The intro's clock, which moves only as frames are actually drawn.
///
/// **A wall clock skips strokes on a first launch.** The first build of this intro timed itself
/// from `Date`, and recorded on the simulator the whole wedge was missing: the main thread stood
/// still for 0.42 s while the library underneath loaded, and when frames resumed the pen was
/// already past the end of `>`. A stall is certain on exactly this launch — it is the one that
/// runs every migration — so a gap between frames longer than `stall` advances the clock by a
/// single frame, and reads as the pen pausing rather than as ink that was never seen written.
/// Ordinary gaps count in full: capping *every* step instead turned a busy Debug build's steady
/// 15 frames a second into a hand writing at a third of its speed.
@Observable
private final class PenClock: NSObject {
    private(set) var elapsed: Double = 0

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var previousTimestamp: CFTimeInterval?

    /// Six frames at 60 Hz. Anything shorter is a slow frame and is kept; anything longer is
    /// the main thread doing something else, and the hand waits for it.
    private static let stall = 0.1

    func start() {
        guard link == nil, elapsed < LaunchScript.duration else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// The display link holds its target, so this is also what lets the clock go.
    func stop() {
        link?.invalidate()
        link = nil
        previousTimestamp = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        if let previousTimestamp {
            let gap = max(link.timestamp - previousTimestamp, 0)
            let step = gap > Self.stall ? 1.0 / 60 : gap
            elapsed = min(elapsed + step, LaunchScript.duration)
        }
        previousTimestamp = link.timestamp
        if elapsed >= LaunchScript.duration {
            stop()
        }
    }
}

/// `>d.`, the icon's mark, as geometry: the Caveat outlines the icon is set from and the path a
/// pen takes through each of them.
///
/// **The ink is the face's own outline; the pen only uncovers it.** A written reveal drawn by
/// stroking the centre lines would be a different, rounder mark than the icon. Instead each
/// stroke's centre line is trimmed to how far the pen has got, stroked wider than the ink
/// (`penWidth`), and used as a mask over the real glyphs — so the finished frame is exactly
/// the icon's letters, and only the order they arrive in is authored.
///
/// The centre lines were measured, not drawn by eye: the midpoints of the glyphs' horizontal
/// ink runs, in font units, rasterised from `Caveat-Variable.ttf` at weight 400. At a pen of
/// 80 units every pixel of the thinned glyphs is under some stroke; at 70 the joint where the
/// bowl of the `d` meets its stem is left bare.
private struct LaunchMark {
    struct Stroke {
        enum Kind {
            /// A pen moving along a centre line.
            case line
            /// A pen set down once: the mask grows from the centre as the ink spreads.
            case dot
        }

        let kind: Kind
        /// Centre line in mark space; a single point for a dot.
        let path: Path
        let centre: CGPoint
        let start: Double
        let duration: Double

        func progress(at clock: Double) -> Double {
            let local = min(max((clock - start) / duration, 0), 1)
            switch kind {
            case .line:
                // Half smoothstep, half constant speed: a hand gathers pace and settles into
                // the end of a stroke, but never crawls through the start of one.
                return 0.5 * local + 0.5 * local * local * (3 - 2 * local)
            case .dot:
                return 1 - pow(1 - local, 3)
            }
        }
    }

    /// The thinned glyph outlines, y down, in font units at 1000 per em.
    let ink: Path
    let strokes: [Stroke]
    /// Where the mark is stood when it is centred — see `MASS_PULL` in `Scripts/generate_icons.py`.
    let anchor: CGPoint
    /// The ink's larger dimension, which is what the icon sizes the mark by.
    let span: CGFloat

    static let penWidth: CGFloat = 80
    /// The thinned full stop is about 40 units across its radius; the rest is antialiasing room.
    static let dotReach: CGFloat = 56

    /// Nil only if the bundled face could not be loaded, in which case there is no mark to write.
    static let shared = LaunchMark.make()

    /// Mirrors `Scripts/generate_icons.py`, so the intro writes the icon rather than a relative.
    private static let kern: CGFloat = -50
    /// `THINNING` in the icon script is 6 px a side on a mark spanning `INK_SPAN` (56%) of 1024.
    private static let thinningShareOfSpan: CGFloat = 6 / (1024 * 0.56)
    private static let massPull: CGFloat = 0.33

    private static func make() -> LaunchMark? {
        let font = CTFontCreateWithName("Caveat-Regular" as CFString, 1000, nil)
        // CoreText substitutes a system face for a missing one without saying so, and a
        // Helvetica `d` under Caveat's pen paths would be a mark written by nobody.
        guard CTFontCopyPostScriptName(font) as String == "Caveat-Regular" else { return nil }

        var characters: [UniChar] = Array(">d.".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count) else { return nil }

        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)

        var origins: [CGFloat] = []
        var pen: CGFloat = 0
        for index in glyphs.indices {
            origins.append(pen)
            pen += advances[index].width + (index == 0 ? kern : 0)
        }

        var outline = Path()
        for (index, glyph) in glyphs.enumerated() {
            guard let glyphPath = CTFontCreatePathForGlyph(font, glyph, nil) else { return nil }
            outline.addPath(Path(glyphPath), transform: glyphSpace(origin: origins[index]))
        }

        let box = outline.boundingRect
        let span = max(box.width, box.height)
        let thinning = span * thinningShareOfSpan
        let ink = outline.subtracting(
            outline.strokedPath(StrokeStyle(lineWidth: thinning * 2, lineCap: .round, lineJoin: .round))
        )

        let strokes = script.map { entry in
            let transform = glyphSpace(origin: origins[entry.glyph])
            let points = entry.points.map { $0.applying(transform) }
            return Stroke(
                kind: entry.kind,
                path: centreLine(through: points),
                centre: points.first ?? .zero,
                start: entry.start,
                duration: entry.duration
            )
        }

        return LaunchMark(ink: ink, strokes: strokes, anchor: opticalAnchor(of: ink), span: span)
    }

    /// Glyph space is y up from the baseline; mark space is y down, glyphs side by side.
    private static func glyphSpace(origin: CGFloat) -> CGAffineTransform {
        CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: origin, ty: 0)
    }

    private struct ScriptEntry {
        let glyph: Int
        let kind: Stroke.Kind
        let start: Double
        let duration: Double
        let points: [CGPoint]
    }

    /// The order a hand writes `>d.` in: the wedge in one stroke that turns at its point, the
    /// bowl of the `d` anticlockwise from where it meets the stem, the stem from the top down,
    /// and the full stop pressed in last. Points are font units relative to each glyph's origin.
    ///
    /// The bowl starts a pen's width short of the stem, and the stem runs along the left of its
    /// own ink past the joint: starting the bowl *at* the joint put the round tip of the pen on
    /// the stem, and for two frames the first thing written read as `~`.
    private static let script: [ScriptEntry] = [
        ScriptEntry(glyph: 0, kind: .line, start: 0.40, duration: 0.32, points: [
            CGPoint(x: 172, y: 382), CGPoint(x: 282, y: 340), CGPoint(x: 358, y: 300),
            CGPoint(x: 409, y: 260), CGPoint(x: 445, y: 225), CGPoint(x: 464, y: 204)
        ]),
        ScriptEntry(glyph: 0, kind: .line, start: 0.72, duration: 0.30, points: [
            CGPoint(x: 464, y: 204), CGPoint(x: 400, y: 180), CGPoint(x: 324, y: 140),
            CGPoint(x: 235, y: 100), CGPoint(x: 185, y: 68), CGPoint(x: 172, y: 54)
        ]),
        ScriptEntry(glyph: 1, kind: .line, start: 1.16, duration: 0.52, points: [
            CGPoint(x: 315, y: 314), CGPoint(x: 290, y: 316), CGPoint(x: 235, y: 302),
            CGPoint(x: 190, y: 264), CGPoint(x: 155, y: 210), CGPoint(x: 132, y: 150),
            CGPoint(x: 126, y: 100), CGPoint(x: 150, y: 62), CGPoint(x: 195, y: 60),
            CGPoint(x: 251, y: 100), CGPoint(x: 300, y: 134), CGPoint(x: 338, y: 160)
        ]),
        ScriptEntry(glyph: 1, kind: .line, start: 1.74, duration: 0.44, points: [
            CGPoint(x: 490, y: 630), CGPoint(x: 488, y: 600), CGPoint(x: 481, y: 575),
            CGPoint(x: 466, y: 540), CGPoint(x: 431, y: 460), CGPoint(x: 400, y: 380),
            CGPoint(x: 374, y: 300), CGPoint(x: 358, y: 210), CGPoint(x: 347, y: 120),
            CGPoint(x: 346, y: 50), CGPoint(x: 358, y: -10)
        ]),
        ScriptEntry(glyph: 2, kind: .dot, start: 2.34, duration: 0.20, points: [
            CGPoint(x: 137, y: 95)
        ])
    ]

    /// A Catmull-Rom curve through the measured points, so the pen turns rather than kinks.
    private static func centreLine(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }

        let padded = [first] + points + [points[points.count - 1]]
        for index in 1..<(padded.count - 2) {
            let (p0, p1, p2, p3) = (padded[index - 1], padded[index], padded[index + 1], padded[index + 2])
            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            )
        }
        return path
    }

    /// A third of the way from the ink's box centre to its centre of mass, as the icon does.
    /// The mass is read from a small rasterisation because the thinned outline is the result of
    /// a boolean operation whose contour directions are not something to integrate over.
    private static func opticalAnchor(of ink: Path) -> CGPoint {
        let box = ink.boundingRect
        let boxCentre = CGPoint(x: box.midX, y: box.midY)
        let scale = 256 / max(box.width, box.height, 1)
        let width = Int((box.width * scale).rounded(.up)) + 2
        let height = Int((box.height * scale).rounded(.up)) + 2

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return boxCentre }

        // Flip so that memory row 0 is the top of the mark, as mark space has it; one pixel of
        // margin on each side, taken back out (with the half pixel to its centre) below.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 1, y: 1)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.addPath(ink.cgPath)
        context.setFillColor(gray: 1, alpha: 1)
        context.fillPath()

        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return boxCentre }
        var total = 0.0, sumX = 0.0, sumY = 0.0
        for row in 0..<height {
            for column in 0..<width {
                let value = Double(data[row * width + column])
                guard value > 0 else { continue }
                total += value
                sumX += Double(column) * value
                sumY += Double(row) * value
            }
        }
        guard total > 0 else { return boxCentre }

        let massCentre = CGPoint(
            x: box.minX + (CGFloat(sumX / total) - 0.5) / scale,
            y: box.minY + (CGFloat(sumY / total) - 0.5) / scale
        )
        return CGPoint(
            x: boxCentre.x + (massCentre.x - boxCentre.x) * massPull,
            y: boxCentre.y + (massCentre.y - boxCentre.y) * massPull
        )
    }
}

private struct LaunchMarkView: View {
    let clock: Double
    let width: CGFloat

    var body: some View {
        if let mark = LaunchMark.shared {
            let scale = width / mark.span
            let box = mark.ink.boundingRect

            Canvas { context, size in
                let transform = CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
                    .scaledBy(x: scale, y: scale)
                    .translatedBy(x: -mark.anchor.x, y: -mark.anchor.y)
                let ink = mark.ink.applying(transform)
                let progress = mark.strokes.map { $0.progress(at: clock) }

                if progress.allSatisfy({ $0 >= 1 }) {
                    context.fill(ink, with: .color(DipleColor.accentInk))
                    return
                }

                // The pen strokes are only a mask: what is filled is always the face's outline.
                context.clipToLayer { mask in
                    for (stroke, amount) in zip(mark.strokes, progress) where amount > 0 {
                        switch stroke.kind {
                        case .line:
                            mask.stroke(
                                stroke.path.trimmedPath(from: 0, to: amount).applying(transform),
                                with: .color(.black),
                                style: StrokeStyle(lineWidth: LaunchMark.penWidth * scale, lineCap: .round, lineJoin: .round)
                            )
                        case .dot:
                            let radius = LaunchMark.dotReach * amount
                            let centre = stroke.centre
                            mask.fill(
                                Path(ellipseIn: CGRect(
                                    x: centre.x - radius,
                                    y: centre.y - radius,
                                    width: radius * 2,
                                    height: radius * 2
                                )).applying(transform),
                                with: .color(.black)
                            )
                        }
                    }
                }
                context.fill(ink, with: .color(DipleColor.accentInk))
            }
            // The frame is the ink's own box around the optical anchor, doubled on each axis
            // by the anchor's distance from the box centre, so nothing is clipped.
            .frame(
                width: (box.width + abs(mark.anchor.x - box.midX) * 2) * scale,
                height: (box.height + abs(mark.anchor.y - box.midY) * 2) * scale
            )
            .accessibilityHidden(true)
        }
    }
}

#Preview("First launch") {
    FirstLaunchView(onFinish: {})
        .preferredColorScheme(.dark)
}
