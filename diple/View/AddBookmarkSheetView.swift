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
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Bookmark Name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BOOKMARK NAME")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
                            .padding(.horizontal, 4)

                        TextField("Enter bookmark title", text: $bookmarkName)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(red: 0.12, green: 0.12, blue: 0.14))
                            .cornerRadius(10)
                    }

                    // Color Selector
                    VStack(alignment: .leading, spacing: 10) {
                        Text("COLOR TAG")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
                            .padding(.horizontal, 4)

                        HStack(spacing: 16) {
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
                                    .onTapGesture {
                                        HapticManager.shared.selection()
                                        selectedColorHex = colorOption.hex
                                    }
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }
            .navigationTitle("Add Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        HapticManager.shared.selection()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color(red: 0.7, green: 0.7, blue: 0.75))
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.dipleAccent)
                }
            }
        }
        .presentationDetents([.height(280)])
    }
}
