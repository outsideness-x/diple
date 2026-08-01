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
                    fontSizeButton(glyphSize: 14, isEnabled: settings.canDecreaseFontSize) {
                        settings.fontSizeStep -= 1
                    }

                    Spacer()

                    // A row of dots stopped scaling once the ladder grew past a handful of
                    // rungs. The percentage says more in less room — set in tabular figures
                    // so the readout does not jitter as the digits change.
                    Text("\(settings.fontSizePercentage)%")
                        .dipleType(.footnote, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(DipleColor.textPrimary)
                        .contentTransition(.numericText())

                    Spacer()

                    fontSizeButton(glyphSize: 20, isEnabled: settings.canIncreaseFontSize) {
                        settings.fontSizeStep += 1
                    }
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

    private func fontSizeButton(glyphSize: CGFloat, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard isEnabled else { return }
            HapticManager.shared.impact(.light)
            action()
        } label: {
            Text("A")
                .dipleIcon(glyphSize, weight: glyphSize > 16 ? .bold : .medium)
                .foregroundStyle(isEnabled ? DipleColor.textPrimary : DipleColor.textQuaternary)
                .frame(width: 44, height: 44)
                .background(DipleColor.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: DipleRadius.s))
        }
        .buttonStyle(.readerControl)
        .disabled(!isEnabled)
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
            Text(fontOption.title)
                .dipleType(fontOption == .serif ? .readingBody : .body, weight: .medium)
                .foregroundColor(isSelected ? .black : Color(red: 0.85, green: 0.85, blue: 0.88))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? Color.dipleAccent : Color(red: 0.12, green: 0.12, blue: 0.14))
                .cornerRadius(10)
        }
    }
}
