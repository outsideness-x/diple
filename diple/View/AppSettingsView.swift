import SwiftUI

public struct AppSettingsView: View {
    @StateObject private var settingsManager = AppSettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        // APPEARANCE SECTION
                        VStack(alignment: .leading, spacing: DipleSpace.l) {
                            Text("APPEARANCE")
                                .dipleType(.micro, weight: .semibold)
                                .foregroundStyle(DipleColor.textTertiary)
                                .padding(.horizontal, DipleSpace.xs)

                            VStack(spacing: 1) {
                                HStack(spacing: DipleSpace.xl) {
                                    ForEach(DipleAccent.allCases, id: \.rawValue) { accent in
                                        AccentSwatchButton(
                                            accent: accent,
                                            isSelected: settingsManager.settings.accent == accent
                                        ) {
                                            settingsManager.settings.accent = accent
                                            AppIconManager.apply(accent)
                                            HapticManager.shared.selection()
                                        }
                                    }
                                }
                                .padding(.horizontal, DipleSpace.l)
                                .padding(.vertical, DipleSpace.m)
                                .background(DipleColor.surfaceRaised)
                            }
                            .cornerRadius(DipleRadius.m)
                        }

                        // HAPTICS SECTION
                        VStack(alignment: .leading, spacing: DipleSpace.l) {
                            Text("HAPTICS & VIBRATION")
                                .dipleType(.micro, weight: .semibold)
                                .foregroundStyle(DipleColor.textTertiary)
                                .padding(.horizontal, DipleSpace.xs)

                            VStack(spacing: 1) {
                                // Enable Haptics Toggle
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Enable Haptics")
                                            .dipleType(.body, weight: .medium)
                                            .foregroundColor(.white)
                                        Text("Vibrate on interactions and events")
                                            .dipleType(.caption)
                                            .foregroundStyle(DipleColor.textTertiary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { settingsManager.settings.isHapticsEnabled },
                                        set: { newValue in
                                            settingsManager.settings.isHapticsEnabled = newValue
                                            if newValue {
                                                HapticManager.shared.impact(.light)
                                            }
                                        }
                                    ))
                                    .tint(DipleColor.accent)
                                }
                                .padding(.horizontal, DipleSpace.l)
                                .padding(.vertical, DipleSpace.m)
                                .background(DipleColor.surfaceRaised)

                                if settingsManager.settings.isHapticsEnabled {
                                    // Intensity Selector
                                    VStack(alignment: .leading, spacing: DipleSpace.m) {
                                        Text("Haptic Intensity")
                                            .dipleType(.callout, weight: .medium)
                                            .foregroundColor(.white)

                                        HStack(spacing: DipleSpace.m) {
                                            ForEach(HapticIntensity.allCases) { intensity in
                                                let isSelected = settingsManager.settings.hapticIntensity == intensity
                                                Button {
                                                    settingsManager.settings.hapticIntensity = intensity
                                                    HapticManager.shared.impact(
                                                        intensity == .light ? .light : (intensity == .medium ? .medium : .heavy)
                                                    )
                                                } label: {
                                                    Text(intensity.rawValue)
                                                        .dipleType(.footnote)
                                                        .foregroundColor(isSelected ? .black : DipleColor.textSecondary)
                                                        .frame(maxWidth: .infinity)
                                                        .padding(.vertical, DipleSpace.m)
                                                        .background(isSelected ? DipleColor.accent : DipleColor.surfaceOverlay)
                                                        .cornerRadius(DipleRadius.s)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, DipleSpace.l)
                                    .padding(.vertical, DipleSpace.m)
                                    .background(DipleColor.surfaceRaised)

                                    // Chapter Transition Vibration Toggle
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Chapter Transition Vibration")
                                                .dipleType(.body, weight: .medium)
                                                .foregroundColor(.white)
                                            Text("Vibrate when moving to next chapter")
                                                .dipleType(.caption)
                                                .foregroundStyle(DipleColor.textTertiary)
                                        }
                                        Spacer()
                                        Toggle("", isOn: Binding(
                                            get: { settingsManager.settings.chapterHapticsEnabled },
                                            set: { newValue in
                                                settingsManager.settings.chapterHapticsEnabled = newValue
                                                HapticManager.shared.selection()
                                            }
                                        ))
                                        .tint(DipleColor.accent)
                                    }
                                    .padding(.horizontal, DipleSpace.l)
                                    .padding(.vertical, DipleSpace.m)
                                    .background(DipleColor.surfaceRaised)
                                }
                            }
                            .cornerRadius(DipleRadius.m)
                        }

                        // READER DEFAULTS SECTION
                        VStack(alignment: .leading, spacing: DipleSpace.l) {
                            Text("READER DEFAULTS")
                                .dipleType(.micro, weight: .semibold)
                                .foregroundStyle(DipleColor.textTertiary)
                                .padding(.horizontal, DipleSpace.xs)

                            VStack(spacing: 1) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Default Continuous Scroll")
                                            .dipleType(.body, weight: .medium)
                                            .foregroundColor(.white)
                                        Text("Open books in continuous vertical scrolling mode")
                                            .dipleType(.caption)
                                            .foregroundStyle(DipleColor.textTertiary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { settingsManager.settings.defaultScrollReadingMode },
                                        set: { newValue in
                                            settingsManager.settings.defaultScrollReadingMode = newValue
                                            settingsManager.settings.readerSettings.readingMode = newValue ? .scroll : .paginated
                                            HapticManager.shared.selection()
                                        }
                                    ))
                                    .tint(DipleColor.accent)
                                }
                                .padding(.horizontal, DipleSpace.l)
                                .padding(.vertical, DipleSpace.m)
                                .background(DipleColor.surfaceRaised)

                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Keep Screen Awake")
                                            .dipleType(.body, weight: .medium)
                                            .foregroundColor(.white)
                                        Text("Screen dims after 10 minutes without page turns instead of after a few seconds")
                                            .dipleType(.caption)
                                            .foregroundStyle(DipleColor.textTertiary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { settingsManager.settings.keepScreenAwakeWhileReading },
                                        set: { newValue in
                                            settingsManager.settings.keepScreenAwakeWhileReading = newValue
                                            HapticManager.shared.selection()
                                        }
                                    ))
                                    .tint(DipleColor.accent)
                                }
                                .padding(.horizontal, DipleSpace.l)
                                .padding(.vertical, DipleSpace.m)
                                .background(DipleColor.surfaceRaised)
                            }
                            .cornerRadius(DipleRadius.m)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, DipleSpace.xl)
                    .padding(.top, DipleSpace.xl)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        HapticManager.shared.selection()
                        dismiss()
                    }
                    .dipleType(.body, weight: .semibold)
                    .foregroundStyle(DipleColor.accent)
                }
            }
        }
    }
}

/// One accent swatch in the APPEARANCE section. Selection reads as a ring around the fill
/// plus a checkmark, matching how a selected haptic-intensity option reads as a filled pill —
/// each section in this screen marks "current choice" with its own shape, not a shared style.
private struct AccentSwatchButton: View {
    let accent: DipleAccent
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DipleSpace.s) {
                ZStack {
                    Circle()
                        .fill(accent.color)
                        .frame(width: 40, height: 40)
                    if isSelected {
                        Circle()
                            .stroke(DipleColor.textPrimary, lineWidth: DipleStroke.regular * 2)
                            .frame(width: 48, height: 48)
                        Image(systemName: "checkmark")
                            .dipleIcon(13, weight: .bold)
                            .foregroundStyle(DipleColor.textOnAccent)
                    }
                }
                Text(accent.title)
                    .dipleType(.caption)
                    .foregroundStyle(isSelected ? DipleColor.textPrimary : DipleColor.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accent.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
