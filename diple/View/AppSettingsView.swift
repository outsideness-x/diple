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
