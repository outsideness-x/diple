import SwiftUI

/// Every quote from every book in one place. Picking a book opens its full quote list.
public struct HubView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
            }
            .navigationTitle("Hub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
