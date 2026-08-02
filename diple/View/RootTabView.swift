import SwiftUI

/// Top-level shell of the app: library, cross-book highlights and user notes.
public struct RootTabView: View {
    public enum Tab: Hashable {
        case library
        case highlights
        case notes
        case search
    }

    @State private var selection: Tab = .library

    public init() {}

    public var body: some View {
        TabView(selection: $selection) {
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }
                .tag(Tab.library)

            HubView()
                .tabItem {
                    Label("Highlights", systemImage: "quote.opening")
                }
                .tag(Tab.highlights)

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
    }
}
