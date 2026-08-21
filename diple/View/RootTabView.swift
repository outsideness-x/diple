import SwiftUI

/// Top-level shell of the app. Home owns the daily reading-to-thinking loop; the remaining
/// tabs are durable places for the material itself.
///
/// Not a `TabView`. The system bar spans the full width and sits *on* the content rather than
/// over it — on the shelf its "Library" label landed on a book cover, on the board it landed on
/// note text — and it cannot collapse while the reader scrolls, which is the behaviour this
/// shell exists to get. The four tab roots are held in a `ZStack` instead, all alive, so
/// switching tabs keeps each one's navigation stack and scroll position exactly as `TabView`
/// did.
public struct RootTabView: View {
    public enum Tab: Hashable, CaseIterable {
        case home
        case library
        case notes
        case search

        var title: String {
            switch self {
            case .home: return "Home"
            case .library: return "Library"
            case .notes: return "Notes"
            case .search: return "Search"
            }
        }

        /// One family of metaphors: places made of paper, and a verb. The board used to be four
        /// squares, which says "grid" — a layout, not a thing you keep — while the layout is a
        /// choice the reader can change. A page with writing on it is what a note is whichever
        /// way the board is laid out.
        var symbol: String {
            switch self {
            case .home: return "house"
            case .library: return "books.vertical"
            case .notes: return "note.text"
            case .search: return "magnifyingglass"
            }
        }

        var selectedSymbol: String {
            switch self {
            case .home: return "house.fill"
            case .library: return "books.vertical.fill"
            case .notes: return "note.text"
            case .search: return "magnifyingglass"
            }
        }
    }

    @State private var selection: Tab = .home
    @StateObject private var tabBarState = DipleTabBarState()

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            tabContent

            DipleTabBar(selection: $selection, isCollapsed: tabBarState.isCollapsed)
                .padding(.bottom, DipleSpace.s)
        }
        .environment(\.dipleTabBarState, tabBarState)
        .tint(DipleColor.accent)
        .onChange(of: selection) { _, _ in
            tabBarState.reset()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dipleOpenDailyResurfacing)) { _ in
            selection = .home
        }
        .onAppear {
            if DailyResurfacingService.shared.consumeOpenRequest() {
                selection = .home
            }
        }
    }

    /// All four roots stay in the tree. Hiding by opacity rather than rebuilding is what keeps a
    /// half-written note, a scrolled shelf and a pushed detail screen where the reader left
    /// them; `allowsHitTesting` stops the hidden three from swallowing touches, and
    /// `accessibilityHidden` stops VoiceOver from reading four screens at once.
    private var tabContent: some View {
        ZStack {
            tabRoot(.home) { HomeView() }
            tabRoot(.library) { LibraryView() }
            tabRoot(.notes) { NotesView() }
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
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
            .zIndex(isActive ? 1 : 0)
    }
}
