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
        .background(DipleColor.canvas.opacity(0.6).ignoresSafeArea())
        .presentationBackground(.regularMaterial)
        // A fixed height clips the controls as soon as the text size grows, so let the
        // sheet size itself instead.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var settingsContent: some View {
        VStack(spacing: DipleSpace.xxl) {
            // Header
            HStack {
                Text("Reader Settings")
                    .dipleType(.headline)
                    .foregroundStyle(DipleColor.textPrimary)
                Spacer()
                Button("Done") {
                    HapticManager.shared.selection()
                    dismiss()
                }
                .dipleType(.body, weight: .medium)
                .foregroundStyle(DipleColor.textPrimary)
            }
            .padding(.top, DipleSpace.l)

            // Theme selector
            VStack(alignment: .leading, spacing: DipleSpace.m) {
                Text("THEME")
                    .dipleType(.micro, weight: .semibold)
                    .foregroundStyle(DipleColor.textTertiary)

                HStack(spacing: DipleSpace.m) {
                    themeButton(title: "Light", theme: .light, bg: Color.white, fg: Color.black)
                    themeButton(title: "Sepia", theme: .sepia, bg: DipleColor.Page.sepiaBackground, fg: DipleColor.Page.sepiaText)
                    themeButton(title: "Dark", theme: .dark, bg: DipleColor.surfaceRaised, fg: Color.white)
                }
            }

            // Font size selector
            VStack(alignment: .leading, spacing: DipleSpace.m) {
                Text("FONT SIZE")
                    .dipleType(.micro, weight: .semibold)
                    .foregroundStyle(DipleColor.textTertiary)

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

            // Page margins selector
            VStack(alignment: .leading, spacing: DipleSpace.m) {
                Text("PAGE MARGINS")
                    .dipleType(.micro, weight: .semibold)
                    .foregroundStyle(DipleColor.textTertiary)

                HStack {
                    marginsButton(systemName: "minus", isEnabled: settings.canDecreasePageMargins) {
                        settings.pageMarginsStep -= 1
                    }

                    Spacer()

                    Text("\(settings.pageMarginsPercentage)%")
                        .dipleType(.footnote, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(DipleColor.textPrimary)
                        .contentTransition(.numericText())

                    Spacer()

                    marginsButton(systemName: "plus", isEnabled: settings.canIncreasePageMargins) {
                        settings.pageMarginsStep += 1
                    }
                }
            }

            // Font Family selector (Serif / San Francisco)
            VStack(alignment: .leading, spacing: DipleSpace.m) {
                Text("TYPOGRAPHY")
                    .dipleType(.micro, weight: .semibold)
                    .foregroundStyle(DipleColor.textTertiary)

                // Four options do not fit one row, and squeezing them there would truncate the
                // labels — which are the specimens. `FlowLayout` wraps instead, and keeps
                // wrapping as Dynamic Type grows.
                FlowLayout(spacing: DipleSpace.m) {
                    ForEach(ReaderFont.allCases) { readerFont in
                        fontFamilyButton(fontOption: readerFont)
                    }
                }
            }

            // Reading Mode selector (Paginated vs Continuous Scroll)
            VStack(alignment: .leading, spacing: DipleSpace.m) {
                Text("READING MODE")
                    .dipleType(.micro, weight: .semibold)
                    .foregroundStyle(DipleColor.textTertiary)

                HStack(spacing: DipleSpace.m) {
                    ForEach(ReadingMode.allCases) { mode in
                        let isSelected = settings.readingMode == mode
                        Button {
                            HapticManager.shared.selection()
                            settings.readingMode = mode
                        } label: {
                            Text(mode.rawValue)
                                .dipleType(.callout, weight: .medium)
                                .foregroundStyle(isSelected ? DipleColor.textOnAccent : DipleColor.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DipleSpace.m)
                                .background(isSelected ? DipleColor.accent : DipleColor.surfaceRaised)
                                .cornerRadius(DipleRadius.m)
                        }
                    }
                }
            }

            Spacer(minLength: 24)
        }
        .padding(.horizontal, DipleSpace.xxl)
        .animation(DipleMotion.standard, value: settings)
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

    private func marginsButton(systemName: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard isEnabled else { return }
            HapticManager.shared.impact(.light)
            action()
        } label: {
            Image(systemName: systemName)
                .dipleIcon(16, weight: .semibold)
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
            HStack(spacing: DipleSpace.s) {
                Circle()
                    .fill(fg)
                    .frame(width: 10, height: 10)
                Text(title)
                    .dipleType(.callout, weight: .medium)
                    .foregroundColor(fg)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DipleSpace.m)
            .background(bg)
            .cornerRadius(DipleRadius.m)
            .overlay(
                RoundedRectangle(cornerRadius: DipleRadius.m)
                    .stroke(settings.theme == theme ? DipleColor.accent : Color.clear, lineWidth: 2)
            )
        }
    }

    /// A specimen of the family it selects. The two generics have no app-side font to name, so
    /// they take a system face; the shipped ones are named through `UIAppFonts`, which is a
    /// separate registration from the one Readium performs for the page itself.
    private func fontOptionLabel(_ fontOption: ReaderFont) -> Text {
        guard let family = fontOption.registeredFamilyName else {
            return Text(fontOption.title)
                .font(.system(
                    .subheadline,
                    design: fontOption == .serif ? .serif : .default,
                    weight: .medium
                ))
        }
        return Text(fontOption.title).font(.custom(family, size: 15, relativeTo: .subheadline))
    }

    private func fontFamilyButton(fontOption: ReaderFont) -> some View {
        let isSelected = settings.font == fontOption
        return Button {
            HapticManager.shared.selection()
            settings.font = fontOption
        } label: {
            // The only place in the app that leaves San Francisco, and it has to: this
            // label is a swatch for the family the page itself will be set in. Taking the
            // size from a `TextStyle` rather than a point size keeps it on Dynamic Type —
            // including for the shipped faces, where `Font.custom(_:relativeTo:)` is the
            // scaling form and the bare `Font.custom(_:size:)` is not.
            fontOptionLabel(fontOption)
                .foregroundStyle(isSelected ? DipleColor.textOnAccent : DipleColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 88)
                .padding(.horizontal, DipleSpace.m)
                .padding(.vertical, DipleSpace.m)
                .background(isSelected ? DipleColor.accent : DipleColor.surfaceRaised)
                .cornerRadius(DipleRadius.m)
        }
    }
}
