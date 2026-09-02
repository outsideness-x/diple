import SwiftUI

public struct EmptyLibraryView: View {
    public let onImportFile: () -> Void
    public let onSaveLink: () -> Void

    public init(onImportFile: @escaping () -> Void, onSaveLink: @escaping () -> Void) {
        self.onImportFile = onImportFile
        self.onSaveLink = onSaveLink
    }

    public var body: some View {
        VStack(spacing: DipleSpace.xxl) {
            Spacer()

            DipleMark(size: 56)

            VStack(spacing: DipleSpace.s) {
                Text("Library is empty")
                    .dipleType(.editorialTitle)
                    .foregroundStyle(DipleColor.textPrimary)

                Text("Import an EPUB or a PDF, or paste the link to an article and read it here without the page around it.")
                    .dipleType(.callout)
                    .foregroundStyle(DipleColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DipleSpace.xxxl)
            }

            VStack(spacing: DipleSpace.m) {
                Button {
                    HapticManager.shared.impact(.light)
                    onImportFile()
                } label: {
                    HStack(spacing: DipleSpace.s) {
                        Image(systemName: "plus")
                            .dipleIcon(14, weight: .semibold)
                        Text("Import a book")
                            .dipleType(.body, weight: .semibold)
                    }
                    .foregroundStyle(DipleColor.textOnAccent)
                    .diplePadding(.buttonLarge)
                    .background(DipleColor.accent, in: Capsule())
                }
                .buttonStyle(.readerControl)

                // The second path is offered quietly: pasting a link is the newer habit, and a
                // matching filled button beside the first would leave neither reading as the
                // thing to do.
                Button {
                    HapticManager.shared.impact(.light)
                    onSaveLink()
                } label: {
                    HStack(spacing: DipleSpace.s) {
                        Image(systemName: "link")
                            .dipleIcon(12, weight: .semibold)
                        Text("Save a link")
                            .dipleType(.footnote, weight: .semibold)
                    }
                    .foregroundStyle(DipleColor.textSecondary)
                    .diplePadding(.button)
                }
                .buttonStyle(.readerControl)
            }
            .padding(.top, DipleSpace.s)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DipleColor.canvas.ignoresSafeArea())
    }
}
