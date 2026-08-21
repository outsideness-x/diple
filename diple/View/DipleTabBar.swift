import SwiftUI
import Combine

/// The app's own tab bar: a floating pill of places, with search kept beside it rather than
/// inside it, and both collapsing out of the way while the reader is scrolling.
///
/// The system bar this replaces spanned the full width and sat on top of the content rather
/// than over it: on the library shelf the "Library" label landed on a book cover, and on the
/// notes board it landed on note text. It also gave four equal seats to three places and one
/// verb. Home, Library and Notes are *where things are*; search is something you do to them,
/// and it belongs next to the pill, not as a fourth room.
///
/// Collapsing is the part that matters most. While a page of covers or rows is moving under the
/// thumb, the bar has nothing to say, so it shrinks to the icon of wherever you already are and
/// the content behind it comes back. Scrolling up brings it back, because that is the gesture of
/// going somewhere rather than reading on.
public struct DipleTabBar: View {
    @Binding var selection: RootTabView.Tab
    let isCollapsed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicator

    /// The three places. Search is deliberately not among them.
    private var places: [RootTabView.Tab] { [.home, .library, .notes] }

    public init(selection: Binding<RootTabView.Tab>, isCollapsed: Bool) {
        self._selection = selection
        self.isCollapsed = isCollapsed
    }

    public var body: some View {
        HStack(spacing: DipleSpace.m) {
            pill
            searchButton
        }
        .padding(.horizontal, DipleSpace.l)
    }

    // MARK: - The pill

    private var pill: some View {
        HStack(spacing: DipleSpace.hair) {
            ForEach(places, id: \.self) { tab in
                if !isCollapsed || tab == selection {
                    placeButton(tab)
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                }
            }
        }
        .padding(DipleSpace.xs)
        .background { glass(Capsule(style: .continuous)) }
    }

    private func placeButton(_ tab: RootTabView.Tab) -> some View {
        let isSelected = selection == tab
        return Button {
            select(tab)
        } label: {
            VStack(spacing: DipleSpace.hair) {
                Image(systemName: isSelected ? tab.selectedSymbol : tab.symbol)
                    .dipleIcon(18, weight: .medium)
                // The label goes with the collapse. An icon alone is legible for the place you
                // are already standing in — which is the only one left when collapsed — but not
                // for the two you might go to.
                if !isCollapsed {
                    Text(tab.title)
                        .dipleType(.tag, weight: .semibold)
                }
            }
            .foregroundStyle(isSelected ? DipleColor.accent : DipleColor.textSecondary)
            .frame(minWidth: 44)
            .frame(height: 44)
            .padding(.horizontal, isCollapsed ? 0 : DipleSpace.m)
            .background {
                if isSelected && !isCollapsed {
                    Capsule(style: .continuous)
                        .fill(DipleColor.accentSoft)
                        .matchedGeometryEffect(id: "selected", in: indicator)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.dipleTabItem)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Search

    private var searchButton: some View {
        let isSelected = selection == .search
        return Button {
            select(.search)
        } label: {
            Image(systemName: RootTabView.Tab.search.symbol)
                .dipleIcon(18, weight: .medium)
                .foregroundStyle(isSelected ? DipleColor.accent : DipleColor.textSecondary)
                .frame(width: 52, height: 52)
                .background { glass(Circle()) }
                .overlay {
                    if isSelected {
                        Circle().fill(DipleColor.accentSoft)
                        Image(systemName: RootTabView.Tab.search.symbol)
                            .dipleIcon(18, weight: .medium)
                            .foregroundStyle(DipleColor.accent)
                    }
                }
                .clipShape(Circle())
        }
        .buttonStyle(.dipleTabItem)
        .accessibilityLabel(RootTabView.Tab.search.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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

    private func setCollapsed(_ collapsed: Bool) {
        guard collapsed != isCollapsed else { return }
        withAnimation(DipleMotion.standard) { isCollapsed = collapsed }
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

    public init(offset: CGFloat, travelRange: CGFloat) {
        self.offset = offset
        self.travelRange = travelRange
    }
}

private struct TabBarCollapseTracker: ViewModifier {
    @Environment(\.dipleTabBarState) private var state

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: ScrollSnapshot.self) { geometry in
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
            state?.report(snapshot)
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
