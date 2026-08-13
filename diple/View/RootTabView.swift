import SwiftUI

/// Top-level shell of the app. Home owns the daily reading-to-thinking loop; the remaining
/// tabs are durable places for the material itself.
public struct RootTabView: View {
    public enum Tab: Hashable {
        case home
        case library
        case notes
        case search
    }

    @State private var selection: Tab = .home

    public init() {}

    public var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(Tab.home)

            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }
                .tag(Tab.library)

            NotesView()
                .tabItem {
                    Label("Notes", systemImage: "square.grid.2x2")
                }
                .tag(Tab.notes)

            GlobalSearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(Tab.search)
        }
        .tint(DipleColor.accent)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .onChange(of: selection) { _, _ in
            HapticManager.shared.selection()
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
}
