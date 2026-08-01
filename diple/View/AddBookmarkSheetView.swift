import SwiftUI
import ReadiumShared

public struct AddBookmarkSheetView: View {
    public let defaultName: String
    public let onAdd: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var bookmarkName: String
    @State private var selectedColorHex: String = "#DF9BE1"

    public static let availableColors: [(name: String, hex: String)] = [
        ("Lilac", "#DF9BE1"),
        ("Yellow", "#FFE066"),
        ("Blue", "#4D96FF"),
        ("Green", "#6BCB77"),
        ("Orange", "#FFB03A"),
        ("Red", "#FF6B6B")
    ]

    public init(defaultName: String, onAdd: @escaping (String, String) -> Void) {
        self.defaultName = defaultName
        self.onAdd = onAdd
        self._bookmarkName = State(initialValue: defaultName)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                VStack(spacing: DipleSpace.xxl) {
                    // Bookmark Name field
                    VStack(alignment: .leading, spacing: DipleSpace.s) {
                        Text("BOOKMARK NAME")
                            .dipleType(.micro, weight: .semibold)
                            .foregroundStyle(DipleColor.textTertiary)
                            .padding(.horizontal, DipleSpace.xs)

                        TextField("Enter bookmark title", text: $bookmarkName)
                            .dipleType(.body)
                            .foregroundColor(.white)
                            .diplePadding(.field)
                            .background(DipleColor.surfaceRaised)
                            .cornerRadius(DipleRadius.m)
                    }

                    // Color Selector
                    VStack(alignment: .leading, spacing: DipleSpace.m) {
                        Text("COLOR TAG")
                            .dipleType(.micro, weight: .semibold)
                            .foregroundStyle(DipleColor.textTertiary)
                            .padding(.horizontal, DipleSpace.xs)

                        HStack(spacing: DipleSpace.l) {
                            ForEach(Self.availableColors, id: \.hex) { colorOption in
                                let isSelected = selectedColorHex == colorOption.hex
                                Circle()
                                    .fill(Color(hex: colorOption.hex))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: isSelected ? 3 : 0)
                                    )
                                    .scaleEffect(isSelected ? 1.15 : 1.0)
                                    .contentShape(Circle())
                                    .onTapGesture {
                                        HapticManager.shared.selection()
                                        selectedColorHex = colorOption.hex
                                    }
                                    .accessibilityLabel(colorOption.name)
                            }
                        }
                        .padding(.vertical, DipleSpace.s)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedColorHex)
                    }

                    Spacer()
                }
                .padding(.horizontal, DipleSpace.xxl)
                .padding(.top, DipleSpace.xxl)
            }
            .navigationTitle("Add Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        HapticManager.shared.selection()
                        dismiss()
                    }
                    .dipleType(.body)
                    .foregroundStyle(DipleColor.textSecondary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        var finalName = bookmarkName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if finalName.isEmpty {
                            finalName = defaultName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Bookmark" : defaultName
                        }
                        HapticManager.shared.notification(.success)
                        onAdd(finalName, selectedColorHex)
                        dismiss()
                    }
                    .dipleType(.body, weight: .semibold)
                    .foregroundStyle(DipleColor.accent)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
