import SwiftUI

/// Top-level shell of the app: three places and one verb.
///
/// Home, the library and Highlights are where things are; search is what the reader does to
/// them. Notes are kept in Highlights, as its second half: a note is what the reader made of a
/// book, the same as a passage is, and it stands beside the passages it was written about.
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
        case search

        var title: String {
            switch self {
            case .home: return "Home"
            case .library: return "Library"
            case .highlights: return "Highlights"
            case .search: return "Search"
            }
        }

        /// One family of metaphors: places made of paper, and a verb.
        var symbol: String {
            switch self {
            case .home: return "house"
            case .library: return "books.vertical"
            case .highlights: return "quote.opening"
            case .search: return "magnifyingglass"
            }
        }

        var selectedSymbol: String {
            switch self {
            case .home: return "house.fill"
            case .library: return "books.vertical.fill"
            case .highlights: return "quote.opening"
            case .search: return "magnifyingglass"
            }
        }
    }

    @State private var selection: Tab = .home
    @State private var isBarHidden = false
    @StateObject private var tabBarState = DipleTabBarState()

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            tabContent

            if !isBarHidden {
                DipleTabBar(selection: $selection, isCollapsed: tabBarState.isCollapsed)
                    .padding(.bottom, DipleSpace.s)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onDipleTabBarHiddenChange { hidden in
            withAnimation(DipleMotion.gentle) { isBarHidden = hidden }
        }
        .environment(\.dipleTabBarState, tabBarState)
        .tint(DipleColor.accent)
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
    /// them; `allowsHitTesting` stops the hidden roots from swallowing touches, and
    /// `accessibilityHidden` stops VoiceOver from reading four screens at once.
    private var tabContent: some View {
        ZStack {
            tabRoot(.home) { HomeView() }
            tabRoot(.library) { LibraryView() }
            tabRoot(.highlights) { MarginaliaView() }
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
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
            .zIndex(isActive ? 1 : 0)
    }
}
