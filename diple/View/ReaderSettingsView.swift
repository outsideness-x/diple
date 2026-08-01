import SwiftUI
import ReadiumNavigator

public struct ReaderSettingsView: View {
    @Binding public var settings: ReaderSettings
    @Environment(\.dismiss) private var dismiss

    public init(settings: Binding<ReaderSettings>) {
        self._settings = settings
    }

    public var body: some View {
        ScrollView {
            settingsContent
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.black.ignoresSafeArea())
        // A fixed height clips the controls as soon as the text size grows, so let the
        // sheet size itself instead.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var settingsContent: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Text("Reader Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
                Spacer()
                Button("Done") {
                    HapticManager.shared.selection()
                    dismiss()
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
            }
            .padding(.top, 16)

            // Theme selector
            VStack(alignment: .leading, spacing: 10) {
                Text("THEME")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))

                HStack(spacing: 12) {
                    themeButton(title: "Light", theme: .light, bg: Color.white, fg: Color.black)
                    themeButton(title: "Sepia", theme: .sepia, bg: Color(red: 0.98, green: 0.95, blue: 0.90), fg: Color(red: 0.2, green: 0.15, blue: 0.1))
                    themeButton(title: "Dark", theme: .dark, bg: Color(red: 0.12, green: 0.12, blue: 0.14), fg: Color.white)
                }
            }

            // Font size selector (5 steps)
            VStack(alignment: .leading, spacing: 10) {
                Text("FONT SIZE")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))

                HStack {
                    Button {
                        if settings.fontSizeStep > 0 {
                            HapticManager.shared.impact(.light)
                            settings.fontSizeStep -= 1
                        }
                    } label: {
                        Text("A")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(settings.fontSizeStep > 0 ? Color(red: 0.92, green: 0.92, blue: 0.92) : Color.gray.opacity(0.4))
                            .frame(width: 44, height: 44)
                            .background(Color(red: 0.12, green: 0.12, blue: 0.14))
                            .cornerRadius(8)
                    }
                    .disabled(settings.fontSizeStep <= 0)

                    Spacer()

                    // Step indicators
                    HStack(spacing: 8) {
                        ForEach(0..<5) { step in
                            Circle()
                                .fill(step == settings.fontSizeStep ? Color.dipleAccent : Color(red: 0.25, green: 0.25, blue: 0.28))
                                .frame(width: 8, height: 8)
                                .scaleEffect(step == settings.fontSizeStep ? 1.35 : 1)
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.65), value: settings.fontSizeStep)

                    Spacer()

                    Button {
                        if settings.fontSizeStep < 4 {
                            HapticManager.shared.impact(.light)
                            settings.fontSizeStep += 1
                        }
                    } label: {
                        Text("A")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(settings.fontSizeStep < 4 ? Color(red: 0.92, green: 0.92, blue: 0.92) : Color.gray.opacity(0.4))
                            .frame(width: 44, height: 44)
                            .background(Color(red: 0.12, green: 0.12, blue: 0.14))
                            .cornerRadius(8)
                    }
                    .disabled(settings.fontSizeStep >= 4)
                }
            }

            // Font Family selector (Serif / San Francisco)
            VStack(alignment: .leading, spacing: 10) {
                Text("TYPOGRAPHY")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))

                HStack(spacing: 12) {
                    ForEach(ReaderFont.allCases) { readerFont in
                        fontFamilyButton(fontOption: readerFont)
                    }
                }
            }

            // Reading Mode selector (Paginated vs Continuous Scroll)
            VStack(alignment: .leading, spacing: 10) {
                Text("READING MODE")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))

                HStack(spacing: 12) {
                    ForEach(ReadingMode.allCases) { mode in
                        let isSelected = settings.readingMode == mode
                        Button {
                            HapticManager.shared.selection()
                            settings.readingMode = mode
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(isSelected ? .black : Color(red: 0.85, green: 0.85, blue: 0.88))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(isSelected ? Color.dipleAccent : Color(red: 0.12, green: 0.12, blue: 0.14))
                                .cornerRadius(10)
                        }
                    }
                }
            }

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 24)
        .animation(.easeInOut(duration: 0.2), value: settings)
    }

    private func themeButton(title: String, theme: Theme, bg: SwiftUI.Color, fg: SwiftUI.Color) -> some View {
        Button {
            HapticManager.shared.selection()
            settings.theme = theme
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(fg)
                    .frame(width: 10, height: 10)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(fg)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(bg)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(settings.theme == theme ? Color.dipleAccent : Color.clear, lineWidth: 2)
            )
        }
    }

    private func fontFamilyButton(fontOption: ReaderFont) -> some View {
        let isSelected = settings.font == fontOption
        return Button {
            HapticManager.shared.selection()
            settings.font = fontOption
        } label: {
            Text(fontOption.rawValue)
                .font(fontOption == .serif ? .system(size: 15, weight: .medium, design: .serif) : .system(size: 15, weight: .medium, design: .default))
                .foregroundColor(isSelected ? .black : Color(red: 0.85, green: 0.85, blue: 0.88))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? Color.dipleAccent : Color(red: 0.12, green: 0.12, blue: 0.14))
                .cornerRadius(10)
        }
    }
}
