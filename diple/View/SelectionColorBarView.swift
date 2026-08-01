import SwiftUI

public struct SelectionColorBarView: View {
    public let onSelectColor: (String) -> Void
    public let onCancel: () -> Void

    private let colors: [(name: String, hex: String, color: Color)] = [
        ("Lilac", "#DF9BE1", Color.dipleAccent),
        ("Yellow", "#FFD60A", Color(red: 1.0, green: 0.84, blue: 0.04)),
        ("Green", "#30D158", Color(red: 0.19, green: 0.82, blue: 0.35)),
        ("Pink", "#FF375F", Color(red: 1.0, green: 0.22, blue: 0.37)),
        ("Blue", "#64D2FF", Color(red: 0.39, green: 0.82, blue: 1.0))
    ]

    public init(onSelectColor: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onSelectColor = onSelectColor
        self.onCancel = onCancel
    }

    public var body: some View {
        HStack(spacing: 14) {
            Text("Highlight Quote")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.dipleAccent)

            Spacer()

            HStack(spacing: 14) {
                ForEach(colors, id: \.hex) { item in
                    Button {
                        onSelectColor(item.hex)
                    } label: {
                        Circle()
                            .fill(item.color)
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.65))
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.readerControl)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.12, green: 0.12, blue: 0.14))
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 24)
    }
}
