import SwiftUI
import Combine

/// The app's own tab bar: the mode on the left, a floating pill of places in the middle, and
/// the mode's verb on the right — all of it collapsing out of the way while the reader scrolls.
///
/// ```
/// Reading   ( ✎ )     (  ⌂    ▥    ❝  )     ( ⌕ )
/// Notes     ( ▥ )                           ( + )
/// ```
///
/// Glyphs only, at every width and on every device. There is no label, no branch that can
/// produce one, and nothing left to measure a label against.
///
/// The system bar this replaces spanned the full width and sat on top of the content rather
/// than over it: on the library shelf the "Library" label landed on a book cover, and on the
/// notes board it landed on note text. Home, Library and Highlights are *where things are*;
/// search is something you do to them, and it stands beside the pill, not as a fourth room.
///
/// **Switching mode moves nothing sideways.** The two circles stand at the two edges in both
/// modes, so the mode circle is the one thing that never changes and the verb circle changes
/// only what it says: in Reading you search, in Notes you write, and the glass under the
/// magnifier turns to accent under the `+`. The pill closes into the centre by width, the same
/// number the scroll collapse already walks along, so there is no second animation to drift out
/// of step with the first.
///
/// Collapsing is the part that matters most. While a page of covers or rows is moving under the
/// thumb, the bar has nothing to say, so it shrinks to the icon of wherever you already are and
/// the content behind it comes back. Scrolling up brings it back, because that is the gesture of
/// going somewhere rather than reading on.
public struct DipleTabBar: View {
    let mode: RootTabView.Mode
    @Binding var selection: RootTabView.Tab
    let isCollapsed: Bool
    let onSwitchMode: () -> Void
    let onCompose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The last place the lens stood on. Search is a verb beside the pill, not a seat in it, so
    /// while it is selected the lens stays over the place it came from and fades out there.
    @State private var lastPlace: RootTabView.Tab = .home

    /// Reading's three places. Search is deliberately not among them, and neither is Notes any
    /// more: it stopped being a room of the reading app and became the other workshop, reached
    /// by the circle on the left.
    ///
    /// That also restores the row's original grammar — three places and one verb. The fourth
    /// seat was added on 2026-09-07 because the bar named the smaller pile and hid the bigger
    /// one; with notes in a mode of their own there is no pile left for it to misname.
    private var places: [RootTabView.Tab] { [.home, .library, .highlights] }

    private var isReading: Bool { mode == .reading }

    /// One seat: a glyph and its tap target, square.
    ///
    /// Above the 44 pt minimum on purpose. With the labels gone the pill is four glyphs and
    /// nothing else, and 44 pt around an 18 pt glyph read as a row that had lost something
    /// rather than one that had been simplified.
    ///
    /// It grows with the reader's text size and then stops. Three seats and two circles have to
    /// stand on a 393 pt phone at every setting — capped, that is 58 × 5 plus the pill's padding
    /// and the gutters, well inside it; unclamped, one seat alone is past 60 pt by the first
    /// accessibility size.
    /// Capping the seat is the honest end of that — the alternative is a seat that stops
    /// growing under a glyph that does not, which is a clipped icon rather than a small one.
    @ScaledMetric(relativeTo: .body) private var scaledSeat: CGFloat = 50
    private var seat: CGFloat { min(scaledSeat, 58) }

    /// The seat plus the hair of air after it. The row carries its own gaps rather than taking
    /// them from `HStack(spacing:)`, because a seat collapsed to nothing has to take its gap
    /// with it — three stray hairlines are enough to make the collapsed pill visibly wider than
    /// the one icon standing in it.
    private var seatStride: CGFloat { seat + DipleSpace.hair }

    /// In fixed proportion to the seat, so the two can never disagree about how much room the
    /// glyph has. Set straight on the font rather than through `dipleIcon`, which scales what
    /// it is handed — and this number has already been scaled by the seat it came from.
    private var glyph: CGFloat { seat * 0.4 }

    /// The pill's own height: seat plus its padding on both sides. Both circles take it, because
    /// two round things of nearly the same size beside a capsule read as a mistake in one of them.
    private var circle: CGFloat { seat + DipleSpace.xs * 2 }

    public init(
        mode: RootTabView.Mode,
        selection: Binding<RootTabView.Tab>,
        isCollapsed: Bool,
        onSwitchMode: @escaping () -> Void,
        onCompose: @escaping () -> Void
    ) {
        self.mode = mode
        self._selection = selection
        self.isCollapsed = isCollapsed
        self.onSwitchMode = onSwitchMode
        self.onCompose = onCompose
    }

    public var body: some View {
        HStack(spacing: 0) {
            modeButton
            Spacer(minLength: DipleSpace.m)
            pill
            Spacer(minLength: DipleSpace.m)
            verbButton
        }
        .padding(.horizontal, DipleSpace.l)
    }

    // MARK: - The mode

    /// The way to the other workshop, showing the workshop it leads *to* — the page in Reading,
    /// the shelf in Notes — the way a camera's flip button shows the other lens.
    ///
    /// It steps aside while the bar is collapsed. A collapsed bar is the place you stand in and
    /// the verb you might want next; leaving the workshop is neither, and three blobs of glass
    /// strung along the bottom of a page being read is two more than it needs. It fades rather
    /// than narrowing, so the circle keeps its width and the pill between the two stays exactly
    /// centred while it goes.
    private var modeButton: some View {
        let destination = mode.other
        let isShown = !isCollapsed
        return Button(action: onSwitchMode) {
            Image(systemName: destination.symbol)
                .font(.system(size: glyph, weight: .medium))
                .foregroundStyle(DipleColor.textSecondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: circle, height: circle)
                .background { glass(Circle()) }
                .contentShape(Circle())
        }
        .buttonStyle(.dipleTabItem)
        .scaleEffect(isShown || reduceMotion ? 1 : 0.6)
        .opacity(isShown ? 1 : 0)
        .allowsHitTesting(isShown)
        .accessibilityHidden(!isShown)
        .accessibilityLabel(destination.title)
        .accessibilityHint("Switches to \(destination.title)")
        .accessibilityIdentifier("shell.mode")
    }

    // MARK: - The pill

    /// Three glyphs, and never a word.
    ///
    /// The row used to carry labels and give them all up together through `ViewThatFits` when a
    /// fourth place stopped fitting on the narrowest phone still shipping. It is icons at every
    /// width now, and there is no branch left that could put a word back. A house, a shelf and a
    /// quotation mark are already the plainest names those places have; the labels were a
    /// second, longer name printed under each one, and they cost the bar a second height that
    /// had to be got rid of at exactly the moment it was also being collapsed.
    ///
    /// In Notes it closes altogether: every seat narrows to nothing and the glass goes with
    /// them. Notes is one stack, the way Things is one list, and a pill with nothing in it is a
    /// control that says "there is somewhere else to go" when there is not.
    private var pill: some View {
        HStack(spacing: 0) {
            ForEach(places, id: \.self) { tab in
                placeButton(tab)
                    // Collapsing is a width, not an insertion. Taking the other three buttons
                    // out of the row made the pill jump between two sizes rather than travel
                    // between them: a transition inside `ViewThatFits` is not interpolated at
                    // all — it re-measures and swaps whole subtrees — so the spring had nothing
                    // to carry. A seat that narrows to nothing is a number, and a number is
                    // what a spring can walk along.
                    .frame(width: isShown(tab) ? seatStride : 0)
                    .opacity(isShown(tab) ? 1 : 0)
                    .clipped()
                    // A zero-width frame does not stop the label overflowing it, and an
                    // overflowing button is still tappable: without this, the three collapsed
                    // seats went on catching thumbs aimed at the content behind them.
                    .allowsHitTesting(isShown(tab))
                    .accessibilityHidden(!isShown(tab))
            }
        }
        .background(alignment: .leading) { lens }
        .padding(isReading ? DipleSpace.xs : 0)
        .background { glass(Capsule(style: .continuous)) }
        .opacity(isReading ? 1 : 0)
        .onChange(of: selection, initial: true) { _, tab in
            if places.contains(tab) { lastPlace = tab }
        }
    }

    /// Collapsed, only the place the reader is already standing in keeps its seat. In Notes
    /// there is no place to stand in, and none keeps one.
    private func isShown(_ tab: RootTabView.Tab) -> Bool {
        isReading && (!isCollapsed || tab == selection)
    }

    // MARK: - The lens

    /// The mark of where you are: one capsule under the whole row, not one inside each seat.
    ///
    /// It used to be a `matchedGeometryEffect` in the background of the selected button, and
    /// that put it inside the seat's `.clipped()` — the clip the collapse cannot do without. A
    /// lens flying between two seats was cut by the edges of both: it wiped across the row with
    /// a hard vertical edge instead of travelling, and what arrived was a second capsule
    /// cross-fading in over the first. Drawn once beneath the row it has nothing to be cut by,
    /// and its place is a number — the seats before it times their stride — which the spring
    /// walks along like any other.
    ///
    /// The same number carries the collapse. Collapsed, the selected seat is the only one with
    /// a width and stands first; the seats before it close with the same spring that brings the
    /// lens's inset to zero, so the two cannot drift apart.
    ///
    /// Drawn while collapsed too. The mark of where you are is the whole point of a bar reduced
    /// to a single icon.
    private var lens: some View {
        Capsule(style: .continuous)
            .fill(DipleColor.accentSoft)
            .frame(width: seat, height: seat)
            .padding(.leading, lensInset)
            .opacity(isReading && places.contains(selection) ? 1 : 0)
    }

    /// Where the lens starts along the row. A seat's glyph is centred in its stride, so it
    /// stands half a hair in from the seat's own edge. Leading rather than an offset, so a
    /// right-to-left row carries the lens the right way without a branch here.
    private var lensInset: CGFloat {
        let lensPlace = places.contains(selection) ? selection : lastPlace
        let index = isCollapsed ? 0 : places.firstIndex(of: lensPlace) ?? 0
        return CGFloat(index) * seatStride + DipleSpace.hair / 2
    }

    private func placeButton(_ tab: RootTabView.Tab) -> some View {
        let isSelected = selection == tab
        return Button {
            select(tab)
        } label: {
            Image(systemName: isSelected ? tab.selectedSymbol : tab.symbol)
                .font(.system(size: glyph, weight: .medium))
                .foregroundStyle(isSelected ? DipleColor.accentInk : DipleColor.textSecondary)
                // The outline and the filled glyph are two different drawings. Cross-faded,
                // they stood on top of each other for the length of the lens's travel — a
                // double-exposed shelf under a lens that had just stopped being crooked.
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                .frame(width: seat, height: seat)
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.dipleTabItem)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - The verb

    /// What the open workshop is *for*: search in Reading, a new note in Notes.
    ///
    /// One circle that changes what it says rather than two circles taking turns, so the thumb
    /// that knows where search is already knows where writing is. The glyph is replaced as a
    /// symbol, and the glass fills with accent underneath it — the one filled control in the
    /// notes workshop, because writing is the one thing that workshop is for. The fill is the
    /// bar's own glass turning colour, not a floating button with a shadow of its own: the
    /// redesign's rule of no third shadow still holds.
    private var verbButton: some View {
        let isSearchSelected = isReading && selection == .search
        return Button {
            if isReading {
                select(.search)
            } else {
                onCompose()
            }
        } label: {
            Image(systemName: isReading ? RootTabView.Tab.search.symbol : "plus")
                .font(.system(size: glyph, weight: isReading ? .medium : .semibold))
                .foregroundStyle(
                    isReading
                        ? (isSearchSelected ? DipleColor.accentInk : DipleColor.textSecondary)
                        : DipleColor.textOnAccent
                )
                .contentTransition(.symbolEffect(.replace))
                .frame(width: circle, height: circle)
                .background {
                    ZStack {
                        glass(Circle())
                        Circle()
                            .fill(DipleColor.accentSoft)
                            .opacity(isSearchSelected ? 1 : 0)
                        Circle()
                            .fill(DipleColor.accent)
                            .opacity(isReading ? 0 : 1)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.dipleTabItem)
        .accessibilityLabel(isReading ? RootTabView.Tab.search.title : "New note")
        .accessibilityAddTraits(isSearchSelected ? [.isSelected] : [])
        .accessibilityIdentifier(isReading ? "shell.search" : "notes.new")
    }

    // MARK: - Material

    /// Real glass, not a tinted plate. The bar sits *over* the shelf, so what is behind it has
    /// to stay visible and blurred rather than be covered — that is the whole reason the label
    /// stopped landing on a book cover. The hairline is what keeps the capsule's edge findable
    /// once the material has taken the tone of whatever is under it.
    private func glass<S: InsettableShape>(_ shape: S) -> some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape.fill(DipleColor.canvas.opacity(0.35))
            }
            .overlay {
                shape.strokeBorder(DipleColor.hairline, lineWidth: DipleStroke.hairline)
            }
            .clipShape(shape)
            .shadow(color: Color.black.opacity(0.22), radius: 14, y: 4)
    }

    private func select(_ tab: RootTabView.Tab) {
        guard selection != tab else { return }
        HapticManager.shared.selection()
        withAnimation(reduceMotion ? nil : DipleMotion.standard) {
            selection = tab
        }
    }
}

/// Press feedback for a bar that has no fill of its own to darken: the target shrinks slightly
/// under the finger, the way the reader's own controls already do.
public struct DipleTabItemButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .animation(DipleMotion.snappy, value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == DipleTabItemButtonStyle {
    static var dipleTabItem: DipleTabItemButtonStyle { DipleTabItemButtonStyle() }
}

// MARK: - Hiding

/// Set by any screen that owns the whole display while it is up.
///
/// The system bar hid itself on a push when a destination asked it to (`.toolbar(.hidden, for:
/// .tabBar)`); a bar drawn by the app has to be told. A preference rather than a flag on a
/// shared object because it is a property of *what is on screen*: it goes away with the view
/// that set it, including when the reader is closed by a back-swipe that no code ran for.
private struct HidesDipleTabBarKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct HidesDipleTabBarModifier: ViewModifier {
    @Environment(\.dipleTabIsActive) private var isActive

    func body(content: Content) -> some View {
        // A pushed destination remains mounted when its whole tab root is hidden. Its
        // preference must not hide the bar of whichever root is visible now.
        content.preference(key: HidesDipleTabBarKey.self, value: isActive)
    }
}

public extension View {
    /// Takes the tab bar down for as long as this view is on screen.
    func hidesDipleTabBar() -> some View {
        modifier(HidesDipleTabBarModifier())
    }

    /// Watches for any descendant asking for the bar to be hidden.
    func onDipleTabBarHiddenChange(_ action: @escaping (Bool) -> Void) -> some View {
        onPreferenceChange(HidesDipleTabBarKey.self) { hidden in
            Task { @MainActor in action(hidden) }
        }
    }
}

// MARK: - Activation

/// Whether the tab this view belongs to is the one on screen.
///
/// Defaults to `true` so a root rendered outside the shell — a `#Preview`, the Mac shell —
/// behaves as it always did.
private struct DipleTabIsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

public extension EnvironmentValues {
    var dipleTabIsActive: Bool {
        get { self[DipleTabIsActiveKey.self] }
        set { self[DipleTabIsActiveKey.self] = newValue }
    }
}

private struct TabActivationRefresh: ViewModifier {
    @Environment(\.dipleTabIsActive) private var isActive
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { if isActive { action() } }
            .onChange(of: isActive) { _, active in
                if active { action() }
            }
    }
}

public extension View {
    /// Runs `action` when this tab first appears and every time the reader comes back to it.
    ///
    /// `TabView` used to give this for free: it added and removed each tab's content as the
    /// selection moved, so `onAppear` fired on every return. The shell keeps all four roots
    /// alive instead — that is what preserves a half-written note and a scrolled shelf — and
    /// the cost is that `onAppear` fires exactly once, at launch. A screen that loaded its data
    /// there then showed whatever was true when the app started: a book imported and opened
    /// would not appear in Continue, and a new import would not appear on the shelf, until the
    /// app was quit and reopened.
    func refreshesOnTabActivation(_ action: @escaping () -> Void) -> some View {
        modifier(TabActivationRefresh(action: action))
    }
}

// MARK: - Collapse

/// Whether the bar is currently out of the way, and the scroll arithmetic that decides it.
///
/// Owned by `RootTabView` and handed to the scroll views through the environment, because the
/// four tab roots are the only things that know they are being scrolled and the bar is the only
/// thing that cares.
@MainActor
public final class DipleTabBarState: ObservableObject {
    @Published public private(set) var isCollapsed = false

    private var lastOffset: CGFloat = 0

    /// Distance travelled in the current direction, reset whenever the direction changes.
    ///
    /// Deciding on the *last* delta alone does not survive a flick: the scroll decelerates and
    /// rubber-bands, so the final few reports can point back the way they came and the bar
    /// springs open again the moment it should have stayed shut. Accumulating gives the gesture
    /// as a whole a say, which is what the reader means by it.
    private var travel: CGFloat = 0

    /// How far in one direction counts as a deliberate scroll rather than a tremor under a
    /// resting thumb. A scroll view reports a new offset for every pixel.
    private let threshold: CGFloat = 24

    /// How far down the page the bar is allowed to hide at all. Near the top there is nothing
    /// gained by hiding it — the content it would uncover is the header — and collapsing during
    /// the first flick of a bounce looks like a glitch.
    private let engageAfter: CGFloat = 40

    /// Below this much scrollable height the bar simply stays put. Hiding it would uncover less
    /// than its own height, which is not a trade worth an animation.
    private let minimumScrollableHeight: CGFloat = 160

    public init() {}

    public func report(_ scroll: ScrollSnapshot) {
        // A page with barely more content than screen has nothing to uncover, and on one the
        // rubber band alone is enough to swing the accumulator past the threshold — the bar
        // would flap on every flick without a single row being revealed.
        guard scroll.travelRange > minimumScrollableHeight else {
            setCollapsed(false)
            return
        }

        // Clamped to the real range, so overscroll at either end is not read as scrolling.
        // Without this the bounce back from the bottom is a large negative run and the bar
        // springs open the instant the finger lifts, which is exactly when it should not.
        let offset = min(max(scroll.offset, 0), scroll.travelRange)
        let delta = offset - lastOffset
        lastOffset = offset
        guard abs(delta) > 0.5 else { return }

        // Direction changed: the previous gesture is over, start counting this one.
        if (delta > 0) != (travel > 0) { travel = 0 }
        travel += delta

        // Back at the top the bar always comes back, whatever the accumulator says: a screen
        // scrolled to its own beginning is not one being read through.
        if offset <= engageAfter {
            setCollapsed(false)
        } else if travel > threshold {
            setCollapsed(true)
        } else if travel < -threshold {
            setCollapsed(false)
        }
    }

    /// Switching tabs lands on a screen at its own scroll position, which says nothing about
    /// where the last one was: the arithmetic starts over and the bar comes back.
    public func reset() {
        lastOffset = 0
        travel = 0
        setCollapsed(false)
    }

    /// `gentle` rather than `standard`. This is something crossing the screen — three seats
    /// leaving and the pill closing over them — not a control taking a new value, and the
    /// tighter spring made an animation that was already being cut short by `ViewThatFits`
    /// read as no animation at all.
    private func setCollapsed(_ collapsed: Bool) {
        guard collapsed != isCollapsed else { return }
        withAnimation(DipleMotion.gentle) { isCollapsed = collapsed }
    }
}

/// The state is carried as an *optional* environment value rather than an `EnvironmentObject`.
/// The tab roots are also the roots of their own `#Preview`s, where nothing supplies a tab bar,
/// and an `EnvironmentObject` that is missing is a crash rather than a no-op.
private struct DipleTabBarStateKey: EnvironmentKey {
    static let defaultValue: DipleTabBarState? = nil
}

public extension EnvironmentValues {
    var dipleTabBarState: DipleTabBarState? {
        get { self[DipleTabBarStateKey.self] }
        set { self[DipleTabBarStateKey.self] = newValue }
    }
}

/// Where a scroll view is, and how far it can go. Both are needed: the position alone cannot
/// tell scrolling apart from the rubber band at either end, and that difference is the whole
/// behaviour.
public struct ScrollSnapshot: Equatable, Sendable {
    public let offset: CGFloat
    public let travelRange: CGFloat

    /// Geometry can settle through several slightly different content sizes in one layout
    /// pass. The bar only reacts after 24 points of travel, so publishing every sub-point
    /// sample creates a SwiftUI feedback warning without adding any useful precision.
    private static let reportingStep: CGFloat = 8
    private static let minimumRelevantRange: CGFloat = 160

    public init(offset: CGFloat, travelRange: CGFloat) {
        self.offset = offset
        self.travelRange = travelRange
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.reportingBucket == rhs.reportingBucket
            && lhs.isMeaningfullyScrollable == rhs.isMeaningfullyScrollable
    }

    private var reportingBucket: Int {
        let clamped = min(max(offset, 0), max(travelRange, 0))
        return Int((clamped / Self.reportingStep).rounded(.towardZero))
    }

    private var isMeaningfullyScrollable: Bool {
        travelRange > Self.minimumRelevantRange
    }
}

/// Hands the latest geometry sample to the bar after SwiftUI has finished its current layout
/// pass. Reporting synchronously can collapse the overlay while its scroll view is still being
/// measured, which asks the same geometry modifier to update twice in one frame.
@MainActor
private final class TabBarCollapseDelivery {
    private var pending: ScrollSnapshot?
    private var deliveryTask: Task<Void, Never>?

    func submit(_ snapshot: ScrollSnapshot?, to state: DipleTabBarState?) {
        pending = snapshot

        // `nil` means this root just became inactive. It also clears a sample queued while the
        // root was visible, so a tab switch cannot deliver one stale offset a moment later.
        guard snapshot != nil, deliveryTask == nil else { return }

        deliveryTask = Task { @MainActor [weak self, weak state] in
            await Task.yield()
            guard let self else { return }
            let latest = pending
            pending = nil
            deliveryTask = nil
            if let latest { state?.report(latest) }
        }
    }
}

private struct TabBarCollapseTracker: ViewModifier {
    @Environment(\.dipleTabBarState) private var state
    @Environment(\.dipleTabIsActive) private var isActive
    @State private var delivery = TabBarCollapseDelivery()

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: ScrollSnapshot?.self) { geometry in
            // Returning a stable value matters as much as ignoring the action below. SwiftUI
            // still evaluates a geometry transform for an opacity-hidden scroll view, and four
            // mounted roots can otherwise make the modifier publish several changes in one
            // frame before our action gets a chance to discard them.
            guard isActive else { return nil }
            let insets = geometry.contentInsets
            return ScrollSnapshot(
                offset: geometry.contentOffset.y + insets.top,
                travelRange: max(
                    0,
                    geometry.contentSize.height + insets.top + insets.bottom
                        - geometry.containerSize.height
                )
            )
        } action: { _, snapshot in
            delivery.submit(snapshot, to: state)
        }
    }
}

public extension View {
    /// Reports this scroll view's vertical position to the tab bar, so it can get out of the
    /// way while the reader is scrolling down and come back on the way up.
    ///
    /// `onScrollGeometryChange` rather than a `GeometryReader` sentinel in the content: the
    /// sentinel measures where a view *ended up*, so it is a frame behind and it fires during
    /// layout as well as during scrolling. This reads the scroll view itself.
    func tracksTabBarCollapse() -> some View {
        modifier(TabBarCollapseTracker())
    }
}


/// Choosing takes the tab bar's seat, so the bar has to go while it lasts. It is a preference,
/// which means it leaves with the mode rather than having to be put back by hand — the same
/// mechanism the note editor uses for the formatting bar.
///
/// Shared by the board and the shelf. Both hold the same mode, entered the same way and left by
/// the same Done, and a second copy of eight lines is how two identical modes start behaving
/// differently.
struct HidesTabBarWhileSelecting: ViewModifier {
    let isSelecting: Bool

    func body(content: Content) -> some View {
        if isSelecting {
            content.hidesDipleTabBar()
        } else {
            content
        }
    }
}
