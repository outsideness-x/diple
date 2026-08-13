import SwiftUI
import UIKit
import UniformTypeIdentifiers

public struct AppSettingsView: View {
    private static let privacyPolicyURL = URL(
        string: "https://github.com/outsideness-x/diple/blob/main/README.md"
    )

    @StateObject private var settingsManager = AppSettingsManager.shared
    @Environment(\.dismiss) private var dismiss
    // Device-local (`CloudSyncService.isEnabled` reads/writes `UserDefaults` directly, not
    // `AppSettings`), so this needs its own `@State` mirror to drive the toggle — nothing
    // publishes changes to it the way `settingsManager` does for synced settings.
    @State private var isICloudSyncEnabled = CloudSyncService.isEnabled
    @State private var isDailyResurfacingEnabled = DailyResurfacingService.shared.isNotificationEnabled
    @State private var dailyResurfacingTime = DailyResurfacingService.shared.notificationTime
    @State private var showDailyResurfacingPermissionAlert = false
    @State private var exportDocument = DipleExportDocument()
    @State private var isExportPresented = false
    @State private var exportErrorMessage: String?

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

                        // DAILY RESURFACING SECTION
                        VStack(alignment: .leading, spacing: DipleSpace.l) {
                            Text("DAILY RESURFACING")
                                .dipleType(.micro, weight: .semibold)
                                .foregroundStyle(DipleColor.textTertiary)
                                .padding(.horizontal, DipleSpace.xs)

                            VStack(spacing: 1) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Daily Quote")
                                            .dipleType(.body, weight: .medium)
                                            .foregroundColor(.white)
                                        Text("Return to one saved passage each day")
                                            .dipleType(.caption)
                                            .foregroundStyle(DipleColor.textTertiary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { isDailyResurfacingEnabled },
                                        set: { newValue in
                                            Task {
                                                let isEnabled = await DailyResurfacingService.shared.setNotificationsEnabled(newValue)
                                                isDailyResurfacingEnabled = isEnabled
                                                if newValue && !isEnabled {
                                                    showDailyResurfacingPermissionAlert = true
                                                } else {
                                                    HapticManager.shared.selection()
                                                }
                                            }
                                        }
                                    ))
                                    .tint(DipleColor.accent)
                                }
                                .padding(.horizontal, DipleSpace.l)
                                .padding(.vertical, DipleSpace.m)
                                .background(DipleColor.surfaceRaised)

                                if isDailyResurfacingEnabled {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Reminder Time")
                                                .dipleType(.body, weight: .medium)
                                                .foregroundColor(.white)
                                            Text("A quiet nudge to revisit a saved thought")
                                                .dipleType(.caption)
                                                .foregroundStyle(DipleColor.textTertiary)
                                        }
                                        Spacer()
                                        DatePicker(
                                            "Reminder Time",
                                            selection: $dailyResurfacingTime,
                                            displayedComponents: .hourAndMinute
                                        )
                                        .labelsHidden()
                                        .tint(DipleColor.accent)
                                    }
                                    .padding(.horizontal, DipleSpace.l)
                                    .padding(.vertical, DipleSpace.m)
                                    .background(DipleColor.surfaceRaised)
                                }
                            }
                            .cornerRadius(DipleRadius.m)
                        }

                        // ICLOUD SECTION
                        VStack(alignment: .leading, spacing: DipleSpace.l) {
                            Text("ICLOUD")
                                .dipleType(.micro, weight: .semibold)
                                .foregroundStyle(DipleColor.textTertiary)
                                .padding(.horizontal, DipleSpace.xs)

                            VStack(spacing: 1) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("iCloud Sync")
                                            .dipleType(.body, weight: .medium)
                                            .foregroundColor(.white)
                                        Text("Sync your library, quotes and notes across your devices")
                                            .dipleType(.caption)
                                            .foregroundStyle(DipleColor.textTertiary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { isICloudSyncEnabled },
                                        set: { newValue in
                                            isICloudSyncEnabled = newValue
                                            CloudSyncService.isEnabled = newValue
                                            HapticManager.shared.selection()
                                            Task {
                                                if newValue {
                                                    UIApplication.shared.registerForRemoteNotifications()
                                                    await CloudSyncService.shared.start()
                                                } else {
                                                    await CloudSyncService.shared.stop()
                                                }
                                            }
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

                        // DATA OWNERSHIP SECTION
                        VStack(alignment: .leading, spacing: DipleSpace.l) {
                            Text("YOUR DATA")
                                .dipleType(.micro, weight: .semibold)
                                .foregroundStyle(DipleColor.textTertiary)
                                .padding(.horizontal, DipleSpace.xs)

                            Button {
                                do {
                                    exportDocument = DipleExportDocument(payload: try DipleExportPayload())
                                    isExportPresented = true
                                    HapticManager.shared.selection()
                                } catch {
                                    exportErrorMessage = "Couldn’t prepare your export: \(error.localizedDescription)"
                                }
                            } label: {
                                HStack(spacing: DipleSpace.m) {
                                    Image(systemName: "square.and.arrow.up")
                                        .dipleIcon(17, weight: .medium)
                                        .foregroundStyle(DipleColor.accent)
                                        .frame(width: 28)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Export Diple Data")
                                            .dipleType(.body, weight: .medium)
                                            .foregroundStyle(DipleColor.textPrimary)
                                        Text("Sources, reading positions, highlights, thoughts and notes in portable JSON")
                                            .dipleType(.caption)
                                            .foregroundStyle(DipleColor.textTertiary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Image(systemName: "chevron.right")
                                        .dipleIcon(11, weight: .semibold)
                                        .foregroundStyle(DipleColor.textQuaternary)
                                }
                                .padding(.horizontal, DipleSpace.l)
                                .padding(.vertical, DipleSpace.m)
                                .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.m))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Creates a JSON file you can save or share")
                        }

                        // PRIVACY SECTION
                        if let privacyPolicyURL = Self.privacyPolicyURL {
                            VStack(alignment: .leading, spacing: DipleSpace.l) {
                                Text("PRIVACY")
                                    .dipleType(.micro, weight: .semibold)
                                    .foregroundStyle(DipleColor.textTertiary)
                                    .padding(.horizontal, DipleSpace.xs)

                                Link(destination: privacyPolicyURL) {
                                    HStack(spacing: DipleSpace.m) {
                                        Image(systemName: "hand.raised.fill")
                                            .dipleIcon(17, weight: .medium)
                                            .foregroundStyle(DipleColor.accent)
                                            .frame(width: 28)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Privacy Policy")
                                                .dipleType(.body, weight: .medium)
                                                .foregroundStyle(DipleColor.textPrimary)
                                            Text("How diple handles your library and iCloud sync")
                                                .dipleType(.caption)
                                                .foregroundStyle(DipleColor.textTertiary)
                                                .multilineTextAlignment(.leading)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                        Spacer(minLength: DipleSpace.s)

                                        Image(systemName: "arrow.up.right")
                                            .dipleIcon(13, weight: .semibold)
                                            .foregroundStyle(DipleColor.textTertiary)
                                    }
                                    .padding(.horizontal, DipleSpace.l)
                                    .padding(.vertical, DipleSpace.m)
                                    .background(DipleColor.surfaceRaised)
                                    .contentShape(Rectangle())
                                }
                                .accessibilityHint("Opens the privacy policy in your browser")
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
            .onChange(of: dailyResurfacingTime) { _, newTime in
                Task {
                    await DailyResurfacingService.shared.setNotificationTime(newTime)
                }
            }
            .alert("Notifications Are Off", isPresented: $showDailyResurfacingPermissionAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Allow notifications for diple in iOS Settings to receive your daily quote.")
            }
            .alert("Export Failed", isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportErrorMessage ?? "An unknown error occurred.")
            }
            .fileExporter(
                isPresented: $isExportPresented,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "diple-export-\(Date.now.formatted(.iso8601.year().month().day()))"
            ) { result in
                if case .failure(let error) = result {
                    exportErrorMessage = "Couldn’t save your export: \(error.localizedDescription)"
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
