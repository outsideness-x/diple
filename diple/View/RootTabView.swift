import SwiftUI

/// Top-level shell of the app: library, the cross-book quote hub and user notes.
public struct RootTabView: View {
    public enum Tab: Hashable {
        case library
        case hub
        case notes
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
                    Label("Hub", systemImage: "quote.opening")
                }
                .tag(Tab.hub)

            NotesView()
                .tabItem {
                    Label("Notes", systemImage: "square.grid.2x2")
                }
                .tag(Tab.notes)
        }
        .tint(Color.dipleAccent)
        .toolbarBackground(Color.black, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .onChange(of: selection) { _, _ in
            HapticManager.shared.selection()
        }
    }
}
