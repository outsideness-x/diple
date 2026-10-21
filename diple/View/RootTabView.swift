import SwiftUI

/// Top-level shell of the app: four places and one verb.
///
/// Home, the library and Highlights are where things are; search is what the reader does to
/// them. Notes are kept in Highlights, as its second half: a note is what the reader made of a
/// book, the same as a passage is, and it stands beside the passages it was written about.
///
/// The feed (2026-10-21) is the fourth place: what the writers and journals the reader follows
/// have published lately, three pieces each and nothing counted. It stands last, after the
/// places that hold what the reader has kept and made — it is the door to what has not been
/// kept yet — and so that the three seats already learnt by thumb did not move.
///
/// For two weeks (2026-09-11 to 2026-09-27) notes were a second workshop, reached by a circle at
/// the left of the bar — a desk of spaces, an Inbox, Today and Tasks, in the manner of Things and
/// Bear. It was taken out again because the app had turned into a combine: a reading app with a
/// notes app bolted beside it. The bridges it was careful to keep are what remain — a note
/// written in a book carries the book, and a note can be linked to one from its page.
///
/// Not a `TabView`. The system bar spans the full width and sits *on* the content rather than
/// over it — on the shelf its "Library" label landed on a book cover, on the board it landed on
/// a passage — and it cannot collapse while the reader scrolls, which is the behaviour this
/// shell exists to get. Every root is held in one `ZStack` instead, all alive, so switching a
/// tab keeps each one's navigation stack and scroll position exactly as `TabView` did — a
/// half-written note survives a trip to the shelf and back.
public struct RootTabView: View {
    public enum Tab: Hashable, CaseIterable {
        case home
        case library
        case highlights
        case feed
        case search

        var title: String {
            switch self {
            case .home: return "Home"
            case .library: return "Library"
            case .highlights: return "Highlights"
            case .feed: return "Feed"
            case .search: return "Search"
            }
        }

        /// One family of metaphors: places made of paper, and a verb.
        var symbol: String {
            switch self {
            case .home: return "house"
            case .library: return "books.vertical"
            case .highlights: return "quote.opening"
            case .feed: return "newspaper"
            case .search: return "magnifyingglass"
            }
        }

        var selectedSymbol: String {
            switch self {
            case .home: return "house.fill"
            case .library: return "books.vertical.fill"
            case .highlights: return "quote.opening"
            case .feed: return "newspaper.fill"
            case .search: return "magnifyingglass"
            }
        }
    }

    @State private var selection: Tab = .home
    @State private var isBarHidden = false
    @State private var tabBarState = DipleTabBarState()

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            tabContent

            if !isBarHidden {
                CollapsingTabBar(selection: $selection, state: tabBarState)
                    .padding(.bottom, DipleSpace.s)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onDipleTabBarHiddenChange { hidden in
            withAnimation(DipleMotion.gentle) { isBarHidden = hidden }
        }
        .environment(\.dipleTabBarState, tabBarState)
        .tint(DipleColor.accentInk)
        .onChange(of: selection) { _, _ in
            tabBarState.reset()
        }
        // The daily notification and the widget both land on the day's passage, which stands at
        // the top of its own room.
        .onReceive(NotificationCenter.default.publisher(for: .dipleOpenDailyResurfacing)) { _ in
            selection = .highlights
        }
        .onAppear {
            if DailyResurfacingService.shared.consumeOpenRequest() {
                selection = .highlights
            }
        }
    }

    /// Every root stays in the tree. Hiding by opacity rather than rebuilding is what keeps a
    /// half-written note, a scrolled shelf and a pushed detail screen where the reader left
    /// them; `allowsHitTesting` stops the hidden roots from swallowing touches, and switching
    /// accessibility off in their environment stops VoiceOver from reading four screens at once.
    private var tabContent: some View {
        ZStack {
            tabRoot(.home) { HomeView() }
            tabRoot(.library) { LibraryView() }
            tabRoot(.highlights) { MarginaliaView() }
            tabRoot(.feed) { FeedView() }
            tabRoot(.search) { GlobalSearchView() }
        }
    }

    @ViewBuilder
    private func tabRoot<Content: View>(
        _ tab: Tab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isActive = selection == tab
        content()
            .environment(\.dipleTabIsActive, isActive)
            // Not `accessibilityHidden`, which stood here and did nothing: it stops at the first
            // UIKit boundary, and every root begins with one — a `NavigationStack` is a
            // navigation controller with a hosting controller per screen, and the shelf's list
            // hosts each row on its own. The hidden roots stayed in the accessibility tree whole:
            // VoiceOver could walk into all four screens, and XCUITest found the shelf's Settings
            // gear under Home's. The environment is what SwiftUI does carry across those
            // boundaries, and a subtree told that accessibility is off builds no elements at
            // all — down to the search root's navigation bar and a reader left open in a hidden
            // tab. The root on screen keeps the system's value untouched. Kept beside this,
            // `accessibilityHidden` left an empty, unlabelled element the size of the screen for
            // every hidden root.
            .transformEnvironment(\.accessibilityEnabled) { enabled in
                if !isActive { enabled = false }
            }
            // Instantly, even though the tab bar changes the selection inside an animation for
            // its lens. Animated, the two roots cross-faded through each other for a tenth of a
            // second — "diple." over "Library", one shelf over another (seen frame by frame on
            // 2026-10-15). The lens travels; the page cuts, as the system's own tab bar does.
            .animation(nil) { $0.opacity(isActive ? 1 : 0) }
            .allowsHitTesting(isActive)
            .zIndex(isActive ? 1 : 0)
    }
}

/// Only the overlay observes collapse changes. Observing them at the shell would rebuild
/// all four mounted roots (including both Highlights boards) in the middle of a scroll.
private struct CollapsingTabBar: View {
    @Binding var selection: RootTabView.Tab
    @ObservedObject var state: DipleTabBarState

    var body: some View {
        DipleTabBar(selection: $selection, isCollapsed: state.isCollapsed)
    }
}
