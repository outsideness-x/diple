import SwiftUI

/// The reader chrome's palette, derived from the page the reader is looking at.
///
/// The bars used to be a fixed dark slab whatever the book looked like, because a bare
/// material takes its tone from the page and light-grey controls on it stop being legible
/// over a light or sepia page. Tinting the material black solved the legibility and created
/// a worse problem: two hard black bands clamped onto a warm paper page, which is the one
/// thing in the app that looks stuck on rather than built in.
///
/// The fix is to stop fighting the page. Chrome takes the page's own tone — bright over
/// paper, dark over night — and the controls invert with it, so contrast is correct in every
/// theme without a slab anywhere.
public struct ReaderChrome: Equatable {
    /// Drives the material's own light/dark rendering.
    public let colorScheme: ColorScheme
    /// Laid under the material to pull it towards the page and hold contrast steady.
    public let tint: SwiftUI.Color
    /// Icons and the title.
    public let control: SwiftUI.Color
    /// Chapter name, and anything subordinate to the title.
    public let secondary: SwiftUI.Color
    /// The single hairline where chrome meets page.
    public let separator: SwiftUI.Color
    /// Unfilled part of the progress track.
    public let track: SwiftUI.Color
    /// The page's own ground, opaque.
    ///
    /// The navigator stops at the safe area, so two bands of screen are not the page and have
    /// to be painted as if they were: the one the status bar sits in and the one the resting
    /// progress line sits on. Filling them with the app canvas put a dark strip above a white
    /// page; filling them with `tint` — which is translucent by design, since it works by
    /// pulling a material towards the page — put a paler one there instead.
    public let page: SwiftUI.Color

    public static func forTheme(_ theme: ReaderPageTheme) -> ReaderChrome {
        switch theme {
        case .carbon:
            return ReaderChrome(
                colorScheme: .dark,
                tint: DipleColor.canvas.opacity(0.55),
                control: DipleColor.textPrimary,
                secondary: DipleColor.textSecondary,
                separator: SwiftUI.Color.white.opacity(0.10),
                track: SwiftUI.Color.white.opacity(0.18),
                page: DipleColor.Page.carbonBackground
            )
        case .ink:
            // Same tint/control recipe as Carbon — both are the night register and #121214
            // vs. #000000 reads identically once behind a blur — but `page` has to be its own
            // theme's background, not Carbon's, or the bar would draw a seam against the page
            // the moment a reader picks true black.
            return ReaderChrome(
                colorScheme: .dark,
                tint: DipleColor.canvas.opacity(0.55),
                control: DipleColor.textPrimary,
                secondary: DipleColor.textSecondary,
                separator: SwiftUI.Color.white.opacity(0.10),
                track: SwiftUI.Color.white.opacity(0.18),
                page: DipleColor.Page.inkBackground
            )
        case .paper:
            return ReaderChrome(
                colorScheme: .light,
                tint: SwiftUI.Color.white.opacity(0.55),
                control: SwiftUI.Color.black.opacity(0.85),
                secondary: SwiftUI.Color.black.opacity(0.5),
                separator: SwiftUI.Color.black.opacity(0.10),
                track: SwiftUI.Color.black.opacity(0.14),
                page: DipleColor.Page.paperBackground
            )
        case .sepia:
            return ReaderChrome(
                colorScheme: .light,
                tint: DipleColor.Page.sepiaBackground.opacity(0.6),
                control: DipleColor.Page.sepiaText.opacity(0.9),
                secondary: DipleColor.Page.sepiaText.opacity(0.6),
                separator: DipleColor.Page.sepiaText.opacity(0.15),
                track: DipleColor.Page.sepiaText.opacity(0.18),
                page: DipleColor.Page.sepiaBackground
            )
        }
    }
}

/// Draggable reading-progress bar.
///
/// The visible line stays thin while reading and thickens with a handle under the finger,
/// so the control reads as decoration until it is touched. Dragging previews the target
/// position locally and only jumps once the finger lifts, which keeps the navigator from
/// churning through intermediate locations.
public struct ReadingProgressSlider: View {
    public let progress: Double
    public let isEnabled: Bool
    public let chrome: ReaderChrome
    public let onSeek: (Double) -> Void

    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0
    @State private var lastTickStep: Int = -1

    private static let trackHeight: CGFloat = 3
    private static let activeTrackHeight: CGFloat = 6
    private static let handleSize: CGFloat = 14

    public init(
        progress: Double,
        isEnabled: Bool,
        chrome: ReaderChrome,
        onSeek: @escaping (Double) -> Void
    ) {
        self.progress = progress
        self.isEnabled = isEnabled
        self.chrome = chrome
        self.onSeek = onSeek
    }

    private var displayedProgress: Double {
        min(max(isScrubbing ? scrubProgress : progress, 0), 1)
    }

    public var body: some View {
        GeometryReader { geo in
            let height = isScrubbing ? Self.activeTrackHeight : Self.trackHeight
            let filled = geo.size.width * displayedProgress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(chrome.track)
                    .frame(height: height)

                Capsule()
                    .fill(DipleColor.accent)
                    .frame(width: filled, height: height)

                Circle()
                    .fill(DipleColor.accent)
                    .frame(width: Self.handleSize, height: Self.handleSize)
                    .shadow(color: Color.black.opacity(0.5), radius: 4, y: 1)
                    .offset(x: filled - Self.handleSize / 2)
                    .opacity(isScrubbing ? 1 : 0)
                    .scaleEffect(isScrubbing ? 1 : 0.4)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .animation(DipleMotion.snappy, value: isScrubbing)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled, geo.size.width > 0 else { return }
                        if !isScrubbing {
                            isScrubbing = true
                            lastTickStep = -1
                            HapticManager.shared.impact(.light)
                        }
                        scrubProgress = min(max(value.location.x / geo.size.width, 0), 1)

                        // A tick every 2% turns the drag into something you can feel.
                        let step = Int(scrubProgress * 50)
                        if step != lastTickStep {
                            lastTickStep = step
                            HapticManager.shared.selection()
                        }
                    }
                    .onEnded { _ in
                        guard isEnabled, isScrubbing else { return }
                        isScrubbing = false
                        HapticManager.shared.impact(.medium)
                        onSeek(scrubProgress)
                    }
            )
        }
        .frame(height: 26)
        .opacity(isEnabled ? 1 : 0.6)
        // A drag gesture on a `GeometryReader` is invisible to VoiceOver: without this the
        // only control that moves through the whole book could be read but never operated.
        // The adjustable action reuses `onSeek`, so a swipe up and a dragged handle land in
        // exactly the same place — `seek(toProgress:)`, one jump, one return point.
        .accessibilityElement()
        .accessibilityLabel("Reading position")
        .accessibilityValue("\(Int((displayedProgress * 100).rounded()))%")
        .accessibilityHint(isEnabled ? "Adjust to move through the book" : "")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment:
                onSeek(min(displayedProgress + Self.accessibilityStep, 1))
            case .decrement:
                onSeek(max(displayedProgress - Self.accessibilityStep, 0))
            @unknown default:
                break
            }
        }
    }

    /// One swipe moves a twentieth of the book — a chapter or so in a novel. Smaller steps
    /// turn "go back a bit" into a minute of swiping; larger ones overshoot the chapter.
    private static let accessibilityStep: Double = 0.05
}

/// Background for the reader's top and bottom bars.
///
/// Glass rather than paint: the page stays faintly visible through the blur, so the chrome
/// reads as a layer above the book instead of a lid on top of it. The tint under the material
/// is the page's own tone (see `ReaderChrome`), which is what keeps contrast honest without
/// resorting to a flat slab.
///
/// **The bar floats; it is not a plate across the screen.** It used to be a full-width rectangle
/// pinned to its edge with a hairline on the inner side, and the page stopped dead at that line —
/// so raising the bars sliced a line of type in half along the top of the screen and another
/// along the bottom, mid-word. A card inset from the edges leaves the page continuous underneath
/// and blurred through the glass, which is what makes the chrome read as lying *over* the book
/// rather than as walls the text has been fitted between.
///
/// Its own edge is a hairline stroke all the way round rather than a single rule, because a card
/// has four sides. The shadow is the one place in the app depth comes from a blur rather than an
/// edge, and it earns it: the card sits on an unpredictable background — paper, sepia or night,
/// with text of any darkness behind it — where a stroke alone can vanish.
public struct ReaderBarBackground: ViewModifier {
    let chrome: ReaderChrome
    /// Which screen edge the bar sits nearest. Only the direction of its inset depends on it now.
    let edge: VerticalEdge

    public func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: DipleRadius.l, style: .continuous)
                ZStack {
                    shape.fill(.regularMaterial)
                    shape.fill(chrome.tint)
                }
                .environment(\.colorScheme, chrome.colorScheme)
                .overlay {
                    shape.strokeBorder(chrome.separator, lineWidth: DipleStroke.hairline)
                }
                .shadow(color: Color.black.opacity(0.18), radius: 12, y: edge == .top ? 4 : -4)
            }
            .padding(.horizontal, DipleSpace.m)
            .padding(edge == .top ? .top : .bottom, DipleSpace.s)
    }
}

public extension View {
    func readerBarBackground(_ chrome: ReaderChrome, edge: VerticalEdge) -> some View {
        modifier(ReaderBarBackground(chrome: chrome, edge: edge))
    }
}

/// Brief confirmation pill shown over the page after an action such as saving a bookmark.
///
/// Takes its colours from the page rather than the app. The pill used to force a dark scheme
/// and then print `DipleColor.textPrimary` on it, which was the same colour twice over while
/// the app had one appearance. Now that the app has two, that pairing would put dark ink on a
/// dark blur the moment a reader chose the light interface — and the toast sits over the
/// *page*, whose theme is a separate choice from the app's anyway.
public struct ReaderToastView: View {
    public let message: String
    public let chrome: ReaderChrome

    public init(message: String, chrome: ReaderChrome) {
        self.message = message
        self.chrome = chrome
    }

    public var body: some View {
        Text(message)
            .dipleType(.footnote, weight: .semibold)
            .foregroundStyle(chrome.control)
            .padding(.horizontal, 18)
            .padding(.vertical, DipleSpace.m)
            .background {
                ZStack {
                    Capsule().fill(.thinMaterial)
                    Capsule().fill(chrome.tint)
                }
                .environment(\.colorScheme, chrome.colorScheme)
            }
            .overlay(Capsule().stroke(chrome.separator, lineWidth: DipleStroke.hairline))
            .shadow(color: Color.black.opacity(0.35), radius: 10, y: 4)
    }
}

/// The band along the bottom of the page that the reader's floating chrome shares: the toast
/// and the way back.
///
/// One modifier rather than a padding repeated at each site, so the two are placed by the same
/// rule and a fixture can put the real band on screen instead of an approximation of it.
///
/// The low resting inset is the whole point of it. `DipleSpace.m` above the safe area drops the
/// contracted pill into the gutter Readium already leaves below the last line — see
/// `navigatorContentInset` — rather than onto the line itself, which is the failure the top-left
/// placement had at the other end of the page.
public struct ReaderBottomBand: ViewModifier {
    let isOverlayVisible: Bool

    /// Enough to clear the raised bottom bar, which is two rows and its own edge inset tall.
    /// Measured against the thing it has to sit above, not chosen for the look of the gap.
    private static let clearingTheBar: CGFloat = 110

    public func body(content: Content) -> some View {
        content
            .padding(.horizontal, DipleSpace.xl)
            .padding(.bottom, isOverlayVisible ? Self.clearingTheBar : DipleSpace.m)
    }
}

public extension View {
    func readerBottomBand(isOverlayVisible: Bool) -> some View {
        modifier(ReaderBottomBand(isOverlayVisible: isOverlayVisible))
    }
}

/// The way back, after a jump.
///
/// One control with two registers, and the difference between them is the whole design.
///
/// **Spoken.** For a few seconds after a jump it says where it leads — "Back to Chapter 5", or
/// a percentage where the publication names nothing. That is the moment the reader needs to be
/// told their place is kept, and a named destination is a promise they can check rather than an
/// arrow they have to trust.
///
/// **Quiet.** Then it contracts to its glyph and stays, for as long as there is anywhere to
/// return to. It does not leave. The version this replaced withdrew after ninety seconds and
/// took the only route back with it, which turned every jump the reader did not immediately
/// undo into a lost place; the cost of that fix is a control on the page for the rest of the
/// sitting, and the contracted form is what makes it payable — smaller, unshadowed, in the
/// chrome's secondary ink, reading as a tab rather than a button.
///
/// **It sits at the bottom, and to the trailing side.** It used to sit at the top left, which
/// is exactly where a page begins and therefore where a reader's eye lands: on the footnote
/// page in the report that started this, the pill covered the one line the note consisted of.
/// The bottom trailing corner is the last place read rather than the first, it is where a
/// paragraph most often stops short of the margin, and the page's chrome — the resting progress
/// line, the toast — already lives along that edge.
public struct ReadingTrailPill: View {
    /// Which way the control is currently offering to go.
    public enum Direction {
        case back
        case forward

        var glyph: String {
            switch self {
            case .back: return "arrow.uturn.backward"
            case .forward: return "arrow.uturn.forward"
            }
        }

        var verb: String {
            switch self {
            case .back: return "Back to"
            case .forward: return "Forward to"
            }
        }
    }

    public let direction: Direction
    /// Where it leads, when it is saying so. `nil` is the contracted form — the whole of the
    /// difference between the two registers, so neither can be set without the other following.
    public let destination: String?
    public let chrome: ReaderChrome
    public let action: () -> Void

    public init(
        direction: Direction,
        destination: String?,
        chrome: ReaderChrome,
        action: @escaping () -> Void
    ) {
        self.direction = direction
        self.destination = destination
        self.chrome = chrome
        self.action = action
    }

    /// The smallest a control is allowed to be, from the interface guidelines rather than from
    /// the look of it — the contracted pill is drawn by its padding like everything else here,
    /// and this only stops that padding from producing something too small to hit.
    private static let minimumTouchTarget: CGFloat = 44

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DipleSpace.s) {
                Image(systemName: direction.glyph)
                    .dipleIcon(13, weight: .semibold)

                if let destination {
                    Text("\(direction.verb) \(destination)")
                        .dipleType(.footnote, weight: .semibold)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(destination == nil ? chrome.secondary : chrome.control)
            .diplePadding(.button)
            .frame(minWidth: Self.minimumTouchTarget, minHeight: Self.minimumTouchTarget)
            .background {
                ZStack {
                    Capsule().fill(.thinMaterial)
                    Capsule().fill(chrome.tint)
                }
                .environment(\.colorScheme, chrome.colorScheme)
            }
            .overlay(Capsule().stroke(chrome.separator, lineWidth: DipleStroke.hairline))
            // Depth while it is speaking, none once it is not: a shadow is what separates a
            // control from the page it interrupts, and the contracted form is not interrupting.
            .shadow(
                color: Color.black.opacity(destination == nil ? 0 : 0.35),
                radius: 10,
                y: 4
            )
        }
        // Touch-down, not tap-end: see `ReaderControlButtonStyle`.
        .buttonStyle(.readerControl)
        .accessibilityLabel(
            direction == .back
                ? "Go back to where you were reading"
                : "Go forward to where you jumped from"
        )
        .accessibilityValue(destination ?? "")
    }
}

#if DEBUG
/// A deterministic UI-test surface for the way back.
///
/// The rules behind the control — what a jump records, what a step back undoes, how a stop names
/// itself — are covered against real locators in `ReadingTrailTests`. What cannot be asserted
/// about a value is the thing this host exists for: *where the control sits on a page of type*,
/// and that it is still sitting there once the words on it have gone. So it drives the real
/// `ReadingTrailPill` through the real `readerBottomBand` with the only two inputs the pill has,
/// over a page laid out like the sparse footnote page in the report that started this — a
/// screenshot of it is a screenshot of the reader's own geometry, not of an approximation.
struct ReadingTrailUITestFixture: View {
    @State private var direction = ReadingTrailPill.Direction.back
    @State private var isLabelVisible = true

    private let chrome = ReaderChrome.forTheme(.paper)

    private var destination: String? {
        guard isLabelVisible else { return nil }
        return direction == .back ? "The Inland Sea" : "Notes"
    }

    var body: some View {
        ZStack {
            chrome.page.ignoresSafeArea()

            // A note, alone at the top of its page: the exact shape the old top-left pill
            // landed on and covered.
            VStack(alignment: .leading, spacing: DipleSpace.s) {
                Text("8")
                Text("The Inland Sea of Japan.")
                Spacer()
            }
            .font(.system(.title3, design: .serif))
            .foregroundStyle(chrome.control)
            .padding(.horizontal, DipleSpace.xl)

            VStack(spacing: DipleSpace.s) {
                Spacer(minLength: 0)

                ReadingTrailPill(
                    direction: direction,
                    destination: destination,
                    chrome: chrome
                ) {
                    // Stepping back off the end of the trail is what leaves a way forward, and
                    // that flip is the one piece of behaviour worth driving from here.
                    direction = direction == .back ? .forward : .back
                }
                .accessibilityIdentifier("readingTrail.pill")
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .readerBottomBand(isOverlayVisible: false)

            // Stands in for the countdown, which XCUI has no business waiting out: the point
            // under test is that retiring the words leaves the control standing. Parked in the
            // opposite corner from the pill so it is never what a placement assertion measures.
            VStack {
                Spacer()
                HStack {
                    Button("Retire the label") { isLabelVisible = false }
                        .dipleType(.caption)
                        .foregroundStyle(chrome.secondary)
                        .accessibilityIdentifier("readingTrail.retireLabel")
                    Spacer()
                }
            }
            .padding(DipleSpace.xl)
        }
    }
}
#endif

/// Gives the reader's icon buttons a tactile press response — SwiftUI's plain buttons
/// have none, which makes the overlay feel dead on a dark background.
///
/// The haptic fires on `isPressed`, which is touch-down. Hanging it off the tap instead
/// delays the only immediate confirmation the reader gets until the finger lifts, and a
/// response that waits for the end of a gesture is the difference between an interface that
/// answers and one that catches up.
public struct ReaderControlButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(DipleMotion.snappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { HapticManager.shared.impact(.light) }
            }
    }
}

public extension ButtonStyle where Self == ReaderControlButtonStyle {
    static var readerControl: ReaderControlButtonStyle { ReaderControlButtonStyle() }
}

/// Press feedback for the library grid. `.plain` leaves the cards completely inert, which
/// makes a tap feel like it was lost until the reader finishes opening.
///
/// Scale, fade and haptic all key off `isPressed` — touch-down — so the card answers under
/// the finger rather than when it lifts.
public struct BookCardButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(DipleMotion.snappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { HapticManager.shared.impact(.light) }
            }
    }
}

public extension ButtonStyle where Self == BookCardButtonStyle {
    static var bookCard: BookCardButtonStyle { BookCardButtonStyle() }
}
