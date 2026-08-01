import SwiftUI

public struct SelectionColorBarView: View {
    public let onSelectColor: (String) -> Void
    public let onCancel: () -> Void

    private let colors = DipleColor.Highlight.all

    public init(onSelectColor: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onSelectColor = onSelectColor
        self.onCancel = onCancel
    }

    public var body: some View {
        HStack(spacing: DipleSpace.m) {
            Text("Highlight Quote")
                .dipleType(.footnote, weight: .semibold)
                .foregroundStyle(DipleColor.accent)

            Spacer()

            HStack(spacing: DipleSpace.m) {
                ForEach(colors, id: \.hex) { item in
                    Button {
                        onSelectColor(item.hex)
                    } label: {
                        Circle()
                            .fill(DipleColor.Highlight.color(forHex: item.hex))
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.readerControl)
                    .accessibilityLabel(item.name)
                }
            }

            Button {
                HapticManager.shared.impact(.light)
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .dipleIcon(13)
                    .foregroundStyle(DipleColor.textTertiary)
                    .padding(DipleSpace.s)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.readerControl)
        }
        .padding(.horizontal, DipleSpace.l)
        .padding(.vertical, DipleSpace.m)
        .background(DipleColor.surfaceRaised)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 4)
        .padding(.horizontal, DipleSpace.xxl)
    }
}
