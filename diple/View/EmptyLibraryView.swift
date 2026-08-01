import SwiftUI

public struct EmptyLibraryView: View {
    public let onImportTap: () -> Void

    public init(onImportTap: @escaping () -> Void) {
        self.onImportTap = onImportTap
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.dipleAccent.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: "book")
                    .font(.system(size: 32, weight: .thin))
                    .foregroundColor(Color.dipleAccent)
            }

            VStack(spacing: 8) {
                Text("Library is Empty")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))

                Text("Import your EPUB or PDF books to start reading in a distraction-free environment.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.58))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                HapticManager.shared.impact(.light)
                onImportTap()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Import a Book")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.black)
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .background(Color.dipleAccent)
                .cornerRadius(20)
            }
            .buttonStyle(.readerControl)
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}
