import SwiftUI

public struct EmptyLibraryView: View {
    public let onImportTap: () -> Void

    public init(onImportTap: @escaping () -> Void) {
        self.onImportTap = onImportTap
    }

    public var body: some View {
        VStack(spacing: DipleSpace.xxl) {
            Spacer()

            ZStack {
                AccentWash()

                Image(systemName: "book")
                    .dipleIcon(32, weight: .thin)
                    .foregroundStyle(DipleColor.accent)
                    .craftGlow(DipleColor.accent.opacity(0.5), radius: 18)
            }

            VStack(spacing: DipleSpace.s) {
                Text("Library is Empty")
                    .dipleType(.title)
                    .foregroundStyle(DipleColor.textPrimary)

                Text("Import your EPUB or PDF books to start reading in a distraction-free environment.")
                    .dipleType(.callout)
                    .foregroundStyle(DipleColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DipleSpace.xxxl)
            }

            Button {
                HapticManager.shared.impact(.light)
                onImportTap()
            } label: {
                HStack(spacing: DipleSpace.s) {
                    Image(systemName: "plus")
                        .dipleIcon(14, weight: .semibold)
                    Text("Import a Book")
                        .dipleType(.body, weight: .semibold)
                }
                .foregroundStyle(DipleColor.textOnAccent)
                .diplePadding(.buttonLarge)
                .background(DipleColor.accent, in: Capsule())
                .craftGlow(radius: 16)
            }
            .buttonStyle(.readerControl)
            .padding(.top, DipleSpace.s)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DipleColor.canvas.ignoresSafeArea())
    }
}
