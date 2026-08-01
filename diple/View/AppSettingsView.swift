import SwiftUI

public struct AppSettingsView: View {
    @StateObject private var settingsManager = AppSettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        // HAPTICS SECTION
                        VStack(alignment: .leading, spacing: 16) {
                            Text("HAPTICS & VIBRATION")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
                                .padding(.horizontal, 4)

                            VStack(spacing: 1) {
                                // Enable Haptics Toggle
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Enable Haptics")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.white)
                                        Text("Vibrate on interactions and events")
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.65))
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
                                    .tint(Color.dipleAccent)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color(red: 0.12, green: 0.12, blue: 0.14))

                                if settingsManager.settings.isHapticsEnabled {
                                    // Intensity Selector
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Haptic Intensity")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.white)

                                        HStack(spacing: 10) {
                                            ForEach(HapticIntensity.allCases) { intensity in
                                                let isSelected = settingsManager.settings.hapticIntensity == intensity
                                                Button {
                                                    settingsManager.settings.hapticIntensity = intensity
                                                    HapticManager.shared.impact(
                                                        intensity == .light ? .light : (intensity == .medium ? .medium : .heavy)
                                                    )
                                                } label: {
                                                    Text(intensity.rawValue)
                                                        .font(.system(size: 13, weight: .medium))
                                                        .foregroundColor(isSelected ? .black : Color(red: 0.85, green: 0.85, blue: 0.88))
                                                        .frame(maxWidth: .infinity)
                                                        .padding(.vertical, 10)
                                                        .background(isSelected ? Color.dipleAccent : Color(red: 0.18, green: 0.18, blue: 0.20))
                                                        .cornerRadius(8)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(red: 0.12, green: 0.12, blue: 0.14))

                                    // Chapter Transition Vibration Toggle
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Chapter Transition Vibration")
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundColor(.white)
                                            Text("Vibrate when moving to next chapter (Readwise Reader style)")
                                                .font(.system(size: 12, weight: .regular))
                                                .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.65))
                                        }
                                        Spacer()
                                        Toggle("", isOn: Binding(
                                            get: { settingsManager.settings.chapterHapticsEnabled },
                                            set: { newValue in
                                                settingsManager.settings.chapterHapticsEnabled = newValue
                                                HapticManager.shared.selection()
                                            }
                                        ))
                                        .tint(Color.dipleAccent)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(red: 0.12, green: 0.12, blue: 0.14))
                                }
                            }
                            .cornerRadius(12)
                        }

                        // READER DEFAULTS SECTION
                        VStack(alignment: .leading, spacing: 16) {
                            Text("READER DEFAULTS")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
                                .padding(.horizontal, 4)

                            VStack(spacing: 1) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Default Continuous Scroll")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.white)
                                        Text("Open books in continuous vertical scrolling mode")
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.65))
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { settingsManager.settings.defaultScrollReadingMode },
                                        set: { newValue in
                                            settingsManager.settings.defaultScrollReadingMode = newValue
                                            HapticManager.shared.selection()
                                        }
                                    ))
                                    .tint(Color.dipleAccent)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color(red: 0.12, green: 0.12, blue: 0.14))
                            }
                            .cornerRadius(12)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        HapticManager.shared.selection()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.dipleAccent)
                }
            }
        }
    }
}
