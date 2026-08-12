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
            // One Text with a break rather than two stacked ones: `minimumScaleFactor` is
            // resolved per Text, so as separate views the words shrank by different amounts
            // and the label came out as a small "Highli…" above a full-size "Quote".
            Text("Highlight\nQuote")
                .dipleType(.footnote, weight: .semibold)
                .foregroundStyle(DipleColor.accent)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                // Horizontally compressible on purpose. Held at its ideal width, the label
                // gave the bar a minimum wider than a narrow phone at large Dynamic Type
                // sizes, and a sibling in the reader's ZStack that cannot shrink widens the
                // stack — which used to drag the page itself wider (see ReaderContainerView).
                // The colours are the control and keep their size; the label is what gives
                // way, and it shrinks rather than truncating so it stays words, not fragments.
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Highlight Quote")

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
                                    .stroke(DipleColor.hairlineStrong, lineWidth: DipleStroke.regular)
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.readerControl)
                    .accessibilityLabel(item.name)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

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
                .stroke(DipleColor.hairlineStrong, lineWidth: DipleStroke.hairline)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 4)
        .padding(.horizontal, DipleSpace.xxl)
    }
}
