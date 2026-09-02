import SwiftUI
import UIKit
import UniformTypeIdentifiers

public struct AppSettingsView: View {
    private static let privacyPolicyURL = URL(
        string: "https://diple-reader.vercel.app/privacy"
    )

    @StateObject private var settingsManager = AppSettingsManager.shared
    @StateObject private var syncStatusStore = CloudSyncStatusStore.shared
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
    @State private var dataErrorMessage: String?
    @State private var isRestorePickerPresented = false
    @State private var isReadingRestore = false
    @State private var restoreCandidate: DipleRestoreCandidate?

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
                                HStack(spacing: DipleSpace.s) {
                                    ForEach(DipleAppearance.allCases) { option in
                                        AppearanceOptionButton(
                                            option: option,
                                            isSelected: settingsManager.settings.appearance == option
                                        ) {
                                            HapticManager.shared.selection()
                                            withAnimation(DipleMotion.standard) {
                                                settingsManager.settings.appearance = option
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, DipleSpace.l)
                                .padding(.vertical, DipleSpace.m)
                                .background(DipleColor.surfaceRaised)

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
                                            .foregroundStyle(DipleColor.textPrimary)
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
                                            .foregroundStyle(DipleColor.textPrimary)

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
                                                        .foregroundColor(isSelected ? DipleColor.accentInk : DipleColor.textSecondary)
                                                        .frame(maxWidth: .infinity)
                                                        .padding(.vertical, DipleSpace.m)
                                                        .dipleSelected(
                                                            isSelected,
                                                            in: RoundedRectangle(cornerRadius: DipleRadius.s, style: .continuous)
                                                        )
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
                                                .foregroundStyle(DipleColor.textPrimary)
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
                                            .foregroundStyle(DipleColor.textPrimary)
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
                                            .foregroundStyle(DipleColor.textPrimary)
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
                                            .foregroundStyle(DipleColor.textPrimary)
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
                                                .foregroundStyle(DipleColor.textPrimary)
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
                                            .foregroundStyle(DipleColor.textPrimary)
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

                                if isICloudSyncEnabled {
                                    syncStatusRow(syncStatusStore.snapshot)
                                }
                            }
                            .cornerRadius(DipleRadius.m)
                        }

                        // DATA OWNERSHIP SECTION
                        VStack(alignment: .leading, spacing: DipleSpace.l) {
                            Text("YOUR DATA")
                                .dipleType(.micro, weight: .semibold)
                                .foregroundStyle(DipleColor.textTertiary)
                                .padding(.horizontal, DipleSpace.xs)

                            VStack(spacing: 1) {
                                dataAction(
                                    title: "Export Diple Data",
                                    detail: "Reading positions, highlights and notes in versioned JSON. Original EPUB and PDF files stay where they are.",
                                    systemImage: "square.and.arrow.up"
                                ) {
                                    do {
                                        exportDocument = DipleExportDocument(payload: try DipleExportPayload())
                                        isExportPresented = true
                                        HapticManager.shared.selection()
                                    } catch {
                                        dataErrorMessage = "Couldn’t prepare your export: \(error.localizedDescription)"
                                    }
                                }
                                .accessibilityIdentifier("settings.data.export")
                                .accessibilityHint("Creates a versioned JSON backup you can save or share")

                                dataAction(
                                    title: "Restore Diple Data",
                                    detail: "Review and safely merge a Diple JSON backup. Nothing already on this device is deleted.",
                                    systemImage: "arrow.counterclockwise",
                                    showsProgress: isReadingRestore
                                ) {
                                    isRestorePickerPresented = true
                                    HapticManager.shared.selection()
                                }
                                .disabled(isReadingRestore)
                                .accessibilityIdentifier("settings.data.restore")
                                .accessibilityHint("Choose a Diple JSON backup and review it before restoring")
                            }
                            .clipShape(RoundedRectangle(cornerRadius: DipleRadius.m, style: .continuous))
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
                                            .foregroundStyle(DipleColor.accentInk)
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

                        SettingsColophon()
                    }
                    .padding(.horizontal, DipleSpace.xl)
                    .padding(.top, DipleSpace.xl)
                    .padding(.bottom, DipleSpace.xxxl)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        HapticManager.shared.selection()
                        dismiss()
                    }
                    .dipleType(.body, weight: .semibold)
                    .foregroundStyle(DipleColor.accentInk)
                }
            }
            .onChange(of: dailyResurfacingTime) { _, newTime in
                Task {
                    await DailyResurfacingService.shared.setNotificationTime(newTime)
                }
            }
            .task {
                if isICloudSyncEnabled {
                    await CloudSyncService.shared.refreshStatus()
                }
            }
            .alert("Notifications Are Off", isPresented: $showDailyResurfacingPermissionAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Allow notifications for diple in iOS Settings to receive your daily quote.")
            }
            .alert("Data File Error", isPresented: Binding(
                get: { dataErrorMessage != nil },
                set: { if !$0 { dataErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(dataErrorMessage ?? "An unknown error occurred.")
            }
            .fileExporter(
                isPresented: $isExportPresented,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "diple-export-\(Date.now.formatted(.iso8601.year().month().day()))"
            ) { result in
                if case .failure(let error) = result {
                    dataErrorMessage = "Couldn’t save your export: \(error.localizedDescription)"
                }
            }
            .fileImporter(
                isPresented: $isRestorePickerPresented,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    prepareRestore(from: url)
                case .failure(let error):
                    dataErrorMessage = "Couldn’t open that backup: \(error.localizedDescription)"
                }
            }
            .sheet(item: $restoreCandidate) { candidate in
                DipleRestoreReviewView(candidate: candidate) {
                    try await Task.detached(priority: .userInitiated) {
                        try DipleBackupRestorer.shared.restore(candidate.payload)
                    }.value
                }
            }
        }
    }

    private func dataAction(
        title: String,
        detail: String,
        systemImage: String,
        showsProgress: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DipleSpace.m) {
                Image(systemName: systemImage)
                    .dipleIcon(17, weight: .medium)
                    .foregroundStyle(DipleColor.accentInk)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .dipleType(.body, weight: .medium)
                        .foregroundStyle(DipleColor.textPrimary)
                    Text(detail)
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showsProgress {
                    ProgressView().tint(DipleColor.accent)
                } else {
                    Image(systemName: "chevron.right")
                        .dipleIcon(11, weight: .semibold)
                        .foregroundStyle(DipleColor.textQuaternary)
                }
            }
            .padding(.horizontal, DipleSpace.l)
            .padding(.vertical, DipleSpace.m)
            .background(DipleColor.surfaceRaised)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func syncStatusRow(_ snapshot: CloudSyncSnapshot) -> some View {
        HStack(alignment: .top, spacing: DipleSpace.m) {
            Group {
                if snapshot.phase == .checking || snapshot.phase == .syncing {
                    ProgressView()
                        .tint(DipleColor.accent)
                } else {
                    Image(systemName: syncStatusIcon(snapshot.phase))
                        .dipleIcon(14, weight: .semibold)
                        .foregroundStyle(
                            snapshot.phase == .synced ? DipleColor.success : DipleColor.destructive
                        )
                }
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(syncStatusTitle(snapshot.phase))
                        .dipleType(.body, weight: .medium)
                        .foregroundStyle(DipleColor.textPrimary)

                    Spacer()

                    if snapshot.pendingCount > 0 {
                        Text("\(snapshot.pendingCount) waiting")
                            .dipleType(.nano)
                            .foregroundStyle(DipleColor.textTertiary)
                            .monospacedDigit()
                    }
                }

                if let message = snapshot.message {
                    Text(message)
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if snapshot.pendingCount > 0 {
                    Text(snapshot.pendingCount == 1 ? "One local change is waiting for iCloud." : "Local changes are queued safely until iCloud confirms them.")
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
                } else if let date = snapshot.lastSuccessfulAt {
                    HStack(spacing: DipleSpace.xs) {
                        Text("Last checked")
                        Text(date, style: .relative)
                    }
                    .dipleType(.caption)
                    .foregroundStyle(DipleColor.textTertiary)
                } else {
                    Text("Run a check to confirm this device can reach your private iCloud database.")
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
                }

                if snapshot.phase != .checking && snapshot.phase != .syncing {
                    Button {
                        HapticManager.shared.selection()
                        Task { await CloudSyncService.shared.retry() }
                    } label: {
                        Label(
                            snapshot.phase == .attention ? "Check Again" : "Check Now",
                            systemImage: "arrow.clockwise"
                        )
                        .dipleType(.footnote, weight: .semibold)
                        .foregroundStyle(DipleColor.accentInk)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.readerControl)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DipleSpace.l)
        .padding(.vertical, DipleSpace.m)
        .background(DipleColor.surfaceRaised)
        // The row is the one place in Settings whose height depends on something outside the
        // reader's control: an error message and the Check button come and go with the phase.
        // Easing that change keeps a real sync from snapping the sections below it up and down.
        .animation(.easeInOut(duration: 0.2), value: snapshot.phase)
        .accessibilityIdentifier("settings.sync.status")
        .accessibilityElement(children: .contain)
    }

    private func syncStatusTitle(_ phase: CloudSyncSnapshot.Phase) -> String {
        switch phase {
        case .disabled: return "Sync Off"
        case .checking: return "Checking iCloud"
        case .syncing: return "Syncing"
        case .synced: return "Up to Date"
        case .attention: return "Needs Attention"
        }
    }

    private func syncStatusIcon(_ phase: CloudSyncSnapshot.Phase) -> String {
        switch phase {
        case .disabled: return "icloud.slash"
        case .checking, .syncing: return "icloud"
        case .synced: return "checkmark.icloud"
        case .attention: return "exclamationmark.icloud"
        }
    }

    private func prepareRestore(from url: URL) {
        guard !isReadingRestore else { return }
        isReadingRestore = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Result {
                    let payload = try DipleBackupRestorer.shared.load(from: url)
                    let preview = try DipleBackupRestorer.shared.preview(payload)
                    return (payload, preview)
                }
            }.value
            isReadingRestore = false
            switch outcome {
            case .success(let loaded):
                restoreCandidate = DipleRestoreCandidate(payload: loaded.0, preview: loaded.1)
            case .failure(let error):
                dataErrorMessage = "Couldn’t read that backup: \(error.localizedDescription)"
            }
        }
    }
}

/// A quiet signature at the end of Settings. It deliberately has no card or divider: after
/// the functional rows, the open canvas makes this read like a note left in the margin rather
/// than one more setting. Caveat is a plain notebook hand rather than formal calligraphy, and
/// the relative text styles keep both lines responsive to Dynamic Type.
private struct SettingsColophon: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: DipleSpace.s) {
            HandDrawnHeart()
                .stroke(
                    DipleColor.textTertiary,
                    style: StrokeStyle(
                        lineWidth: 1.35,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: 17, height: 15)
                .rotationEffect(.degrees(5))
                .padding(.bottom, DipleSpace.hair)
                .accessibilityHidden(true)

            Text("designed and created by chemical pink.")
                .font(.custom("Caveat-Regular", size: 21, relativeTo: .title3))
                .foregroundStyle(DipleColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .rotationEffect(.degrees(-0.7))

            Text("diple. version \(appVersion)")
                .font(.custom("Caveat-Regular", size: 17, relativeTo: .body))
                .foregroundStyle(DipleColor.textTertiary)
                .padding(.top, DipleSpace.hair)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DipleSpace.xs)
        .padding(.vertical, DipleSpace.xxl)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("settings.colophon")
        .accessibilityLabel(
            "designed and created by chemical pink. diple. version \(appVersion)"
        )
    }
}

/// Slightly uneven Bézier lobes give the outline the warmth of a single pen stroke; an SF
/// Symbol would be too geometric beside the notebook hand.
private struct HandDrawnHeart: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()

        path.move(to: CGPoint(x: width * 0.51, y: height * 0.90))
        path.addCurve(
            to: CGPoint(x: width * 0.10, y: height * 0.39),
            control1: CGPoint(x: width * 0.40, y: height * 0.77),
            control2: CGPoint(x: width * 0.08, y: height * 0.62)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.30, y: height * 0.12),
            control1: CGPoint(x: width * 0.07, y: height * 0.22),
            control2: CGPoint(x: width * 0.18, y: height * 0.08)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.52, y: height * 0.32),
            control1: CGPoint(x: width * 0.41, y: height * 0.12),
            control2: CGPoint(x: width * 0.49, y: height * 0.21)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.73, y: height * 0.11),
            control1: CGPoint(x: width * 0.57, y: height * 0.19),
            control2: CGPoint(x: width * 0.63, y: height * 0.09)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.92, y: height * 0.39),
            control1: CGPoint(x: width * 0.85, y: height * 0.10),
            control2: CGPoint(x: width * 0.94, y: height * 0.23)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.51, y: height * 0.90),
            control1: CGPoint(x: width * 0.92, y: height * 0.59),
            control2: CGPoint(x: width * 0.67, y: height * 0.79)
        )

        return path
    }
}

/// Light / Dark / System, as three equal segments above the accent swatches.
///
/// A segmented row rather than a toggle: "System" is a real third choice, not the absence of
/// the other two, and a switch labelled "Dark mode" cannot say so. Selection is the app's one
/// ring (`dipleSelected`), the same mark the haptic row and every filter chip carry.
private struct AppearanceOptionButton: View {
    let option: DipleAppearance
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DipleSpace.xs) {
                Image(systemName: option.systemImage)
                    .dipleIcon(15, weight: .medium)
                Text(option.title)
                    .dipleType(.caption, weight: .medium)
            }
            .foregroundStyle(isSelected ? DipleColor.accentInk : DipleColor.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DipleSpace.m)
            .dipleSelected(
                isSelected,
                in: RoundedRectangle(cornerRadius: DipleRadius.s, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.readerControl)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
                    // Five swatches share the row, so a cell is about 76 pt wide and
                    // "Periwinkle" does not fit in it: it wrapped, mid-word, to "Periwinkl / e"
                    // and made that one swatch taller than the other four. Shrinking the label
                    // rather than pinning a width keeps the row honest under Dynamic Type — the
                    // name still grows with the system size, it just stops before it breaks.
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accent.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
