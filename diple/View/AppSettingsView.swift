import SwiftUI
import UIKit
import UniformTypeIdentifiers

public struct AppSettingsView: View {
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
    @State private var isPickerPresented = false
    /// What the one file picker was opened for. See `FilePickerRequest`.
    @State private var pickerRequest: FilePickerRequest = .restore
    @State private var isReadingRestore = false
    @State private var restoreCandidate: DipleRestoreCandidate?
    @State private var isReadingImport = false
    @State private var importCandidate: HighlightImportCandidate?
    @State private var isWritingMarkdown = false
    @State private var markdownReport: MarkdownExportReport?

    public init() {}

    public var body: some View {
        NavigationStack {
            settingsPage
                .alert("Notifications are off", isPresented: $showDailyResurfacingPermissionAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Allow notifications for diple in iOS Settings to receive your daily passage.")
                }
                .alert("Data file error", isPresented: Binding(
                    get: { dataErrorMessage != nil },
                    set: { if !$0 { dataErrorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(dataErrorMessage ?? "An unknown error occurred.")
                }
                .alert("Markdown written", isPresented: Binding(
                    get: { markdownReport != nil },
                    set: { if !$0 { markdownReport = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(markdownReport.map(Self.markdownSummary) ?? "")
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
                // **One importer, not three.** SwiftUI presents a single `fileImporter` per
                // view: with three of them chained here only the last one ever opened, which
                // silently took Restore — a feature that had worked for months — down with the
                // two new rows. Nothing in a build or a test says so; the picker simply does
                // not appear. So the request is state and the presentation is one modifier.
                .fileImporter(
                    isPresented: $isPickerPresented,
                    allowedContentTypes: pickerRequest.contentTypes,
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        guard let url = urls.first else { return }
                        switch pickerRequest {
                        case .restore: prepareRestore(from: url)
                        case .importHighlights: prepareHighlightImport(from: url)
                        case .markdownFolder: writeMarkdown(into: url)
                        }
                    case .failure(let error):
                        dataErrorMessage = "\(pickerRequest.failure): \(error.localizedDescription)"
                    }
                }
                .sheet(item: $restoreCandidate) { candidate in
                    DipleRestoreReviewView(candidate: candidate) {
                        try await Task.detached(priority: .userInitiated) {
                            try DipleBackupRestorer.shared.restore(candidate.payload)
                        }.value
                    }
                }
                .sheet(item: $importCandidate) { candidate in
                    HighlightImportReviewView(candidate: candidate) {
                        try await Task.detached(priority: .userInitiated) {
                            try HighlightImporter.shared.commit(candidate.document)
                        }.value
                    }
                }
        }
    }

    /// The page itself. Everything that *presents* something — the pickers, the sheets and
    /// the alerts — is chained onto it in `body` instead, because the whole screen in one
    /// expression is more than the type checker will solve in reasonable time.
    ///
    /// Set the way the platform's own Settings is (2026-10-01): one line a row, and what a
    /// section's rows mean said once, in a footnote under it. Every row used to carry a grey
    /// subtitle of its own — "Vibrate on interactions and events" under "Enable haptics" —
    /// which doubled the height of the page and made a handful of switches read as a form.
    /// Fewer of them, too: haptic strength and a separate chapter vibration are gone (see
    /// `HapticManager`), because a reading app that asks how hard it should tap is asking the
    /// reader to finish designing it.
    @ViewBuilder
    private var settingsPage: some View {
        ZStack {
            DipleColor.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: DipleSpace.xxxl) {
                    appearanceSection
                    readerSection
                    dailyPassageSection
                    iCloudSection
                    readingSection
                    dataSection
                    privacySection
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
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        settingsSection("APPEARANCE") {
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
                ForEach(DipleAccent.pickerChoices(current: settingsManager.settings.accent), id: \.rawValue) { accent in
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
    }

    /// How a book opens and behaves while it is open — and haptics, which are almost all the
    /// reader's: a selection, a saved passage, a new chapter.
    private var readerSection: some View {
        settingsSection(
            "READER",
            footer: "Continuous scroll opens books as one long page. A screen kept awake dims after ten minutes without a page turn. Haptics are the light taps under a selection, a saved passage and a new chapter."
        ) {
            settingsToggle("Continuous scroll", isOn: Binding(
                get: { settingsManager.settings.defaultScrollReadingMode },
                set: { newValue in
                    settingsManager.settings.defaultScrollReadingMode = newValue
                    settingsManager.settings.readerSettings.readingMode = newValue ? .scroll : .paginated
                    HapticManager.shared.selection()
                }
            ))

            settingsToggle("Keep screen awake", isOn: Binding(
                get: { settingsManager.settings.keepScreenAwakeWhileReading },
                set: { newValue in
                    settingsManager.settings.keepScreenAwakeWhileReading = newValue
                    HapticManager.shared.selection()
                }
            ))

            settingsToggle("Haptics", isOn: Binding(
                get: { settingsManager.settings.isHapticsEnabled },
                set: { newValue in
                    settingsManager.settings.isHapticsEnabled = newValue
                    if newValue {
                        HapticManager.shared.impact(.light)
                    }
                }
            ))
        }
    }

    private var dailyPassageSection: some View {
        settingsSection(
            "DAILY PASSAGE",
            footer: "One saved passage a day, as a quiet notification at the time you choose."
        ) {
            settingsToggle("Daily passage", isOn: Binding(
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

            if isDailyResurfacingEnabled {
                HStack {
                    Text("Time")
                        .dipleType(.body)
                        .foregroundStyle(DipleColor.textPrimary)
                    Spacer()
                    DatePicker(
                        "Reminder time",
                        selection: $dailyResurfacingTime,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .tint(DipleColor.accentInk)
                }
                .padding(.horizontal, DipleSpace.l)
                .padding(.vertical, DipleSpace.s)
                .background(DipleColor.surfaceRaised)
            }
        }
    }

    private var iCloudSection: some View {
        settingsSection(
            "ICLOUD",
            footer: "Your library, highlights and notes on every device signed in to your iCloud account."
        ) {
            settingsToggle("iCloud sync", isOn: Binding(
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

            if isICloudSyncEnabled {
                syncStatusRow(syncStatusStore.snapshot)
            }
        }
    }

    /// The way to the log, and the only one.
    ///
    /// Settings rather than a tab or a row on Home, and not for want of anywhere better: the
    /// front page was deliberately cut back to reading and the next move, the shelf is for
    /// choosing, and a ledger is looked at a few times a year. A rare, reflective screen costs
    /// nothing here and would cost a permanent row of a page anywhere else. That it sits above
    /// `YOUR DATA` is the argument for the placement — it is a record of the reader, kept beside
    /// the export that would carry it away.
    private var readingSection: some View {
        settingsSection(
            "YOUR READING",
            footer: "Every sitting since the log began, and when in the day you read."
        ) {
            NavigationLink {
                ReadingLogView()
            } label: {
                settingsRowLabel("Reading log")
            }
            .buttonStyle(.plain)
        }
    }

    private var dataSection: some View {
        settingsSection(
            "YOUR DATA",
            footer: "A backup holds positions, highlights and notes, not the books, and restoring one deletes nothing. Markdown writes a file per book and per note. Highlights import from Kindle’s My Clippings.txt or a Readwise CSV."
        ) {
            dataAction("Export Backup") {
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

            dataAction("Restore Backup", showsProgress: isReadingRestore) {
                present(.restore)
            }
            .disabled(isReadingRestore)
            .accessibilityIdentifier("settings.data.restore")
            .accessibilityHint("Choose a diple backup and review it before restoring")

            dataAction("Export as Markdown", showsProgress: isWritingMarkdown) {
                present(.markdownFolder)
            }
            .disabled(isWritingMarkdown)
            .accessibilityIdentifier("settings.data.markdown")
            .accessibilityHint("Choose a folder to write your highlights and notes into as Markdown")

            dataAction("Import Highlights", showsProgress: isReadingImport) {
                present(.importHighlights)
            }
            .disabled(isReadingImport)
            .accessibilityIdentifier("settings.data.import")
            .accessibilityHint("Choose a Kindle or Readwise export and review it before importing")
        }
    }

    private var privacySection: some View {
        settingsSection("PRIVACY") {
            Link(destination: DipleLinks.privacy) {
                settingsRowLabel("Privacy policy", mark: "arrow.up.right")
            }
            .accessibilityHint("Opens the privacy policy in your browser")
        }
    }

    // MARK: - Rows

    /// A section as Settings sets one: a heading in capitals — Settings is the one form in the
    /// app, and capitals are how a form labels its parts — its rows in a single card, and what
    /// they mean once, in a footnote under the card.
    private func settingsSection<Rows: View>(
        _ title: String,
        footer: String? = nil,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: DipleSpace.s) {
            Text(title)
                .dipleType(.micro, weight: .semibold)
                .foregroundStyle(DipleColor.textTertiary)
                .padding(.horizontal, DipleSpace.xs)

            VStack(spacing: 1) {
                rows()
            }
            .clipShape(RoundedRectangle(cornerRadius: DipleRadius.m, style: .continuous))

            if let footer {
                Text(footer)
                    .dipleType(.caption)
                    .foregroundStyle(DipleColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DipleSpace.xs)
            }
        }
    }

    /// A switch on one line. The name is the toggle's own label, so VoiceOver reads the switch
    /// by name — it used to sit in a separate `Text` beside a `Toggle("")`, and was announced as
    /// an unnamed switch.
    private func settingsToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .dipleType(.body)
                .foregroundStyle(DipleColor.textPrimary)
        }
        .tint(DipleColor.accentInk)
        .padding(.horizontal, DipleSpace.l)
        .padding(.vertical, DipleSpace.m)
        .background(DipleColor.surfaceRaised)
    }

    /// A row that leads somewhere or does something: its name, and the mark of which — a
    /// chevron for a page, an arrow for the web, a spinner while it works.
    private func settingsRowLabel(
        _ title: String,
        mark: String = "chevron.right",
        showsProgress: Bool = false
    ) -> some View {
        HStack(spacing: DipleSpace.m) {
            Text(title)
                .dipleType(.body)
                .foregroundStyle(DipleColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsProgress {
                ProgressView().tint(DipleColor.accentInk)
            } else {
                Image(systemName: mark)
                    .dipleIcon(12, weight: .semibold)
                    .foregroundStyle(DipleColor.textQuaternary)
            }
        }
        .padding(.horizontal, DipleSpace.l)
        .padding(.vertical, DipleSpace.m)
        .background(DipleColor.surfaceRaised)
        .contentShape(Rectangle())
    }

    private func dataAction(
        _ title: String,
        showsProgress: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            settingsRowLabel(title, showsProgress: showsProgress)
        }
        .buttonStyle(.plain)
    }

    private func syncStatusRow(_ snapshot: CloudSyncSnapshot) -> some View {
        HStack(alignment: .top, spacing: DipleSpace.m) {
            Group {
                if snapshot.phase == .checking || snapshot.phase == .syncing {
                    ProgressView()
                        .tint(DipleColor.accentInk)
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
        .animation(DipleMotion.gentle, value: snapshot.phase)
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

    /// What the single file picker is being opened for.
    ///
    /// It exists because there can only be one: three `fileImporter` modifiers on one view
    /// leave two of them dead, and the dead ones fail by doing nothing at all.
    private enum FilePickerRequest {
        case restore
        case importHighlights
        case markdownFolder

        var contentTypes: [UTType] {
            switch self {
            case .restore: return [.json]
            case .importHighlights: return HighlightImporter.readableTypes
            case .markdownFolder: return [.folder]
            }
        }

        var failure: String {
            switch self {
            case .restore: return "Couldn’t open that backup"
            case .importHighlights: return "Couldn’t open that file"
            case .markdownFolder: return "Couldn’t open that folder"
            }
        }
    }

    private func present(_ request: FilePickerRequest) {
        pickerRequest = request
        isPickerPresented = true
        HapticManager.shared.selection()
    }

    /// The folder is chosen every time rather than remembered.
    ///
    /// A stored security-scoped bookmark is a permission that can quietly die — the folder is
    /// moved, iCloud Drive evicts it, the vault is restored from a backup — and repairing it
    /// needs a second row in Settings whose only job is to explain a failure. The picker already
    /// reopens where it was last used, so choosing again costs one tap and can never be stale.
    private func writeMarkdown(into folder: URL) {
        guard !isWritingMarkdown else { return }
        isWritingMarkdown = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Result { try MarkdownLibraryExporter.shared.export(to: folder) }
            }.value
            isWritingMarkdown = false
            switch outcome {
            case .success(let report):
                HapticManager.shared.notification(.success)
                markdownReport = report
            case .failure(let error):
                dataErrorMessage = "Couldn’t write into that folder: \(error.localizedDescription)"
            }
        }
    }

    /// Counts, then the two things a reader would otherwise have to discover by diffing the
    /// folder: what was already there, and what diple refused to touch.
    private static func markdownSummary(_ report: MarkdownExportReport) -> String {
        var lines = [
            "\(report.passagesWritten) \(report.passagesWritten == 1 ? "passage" : "passages") across \(report.fileCount) \(report.fileCount == 1 ? "file" : "files")."
        ]
        if report.passagesAlreadyThere > 0 {
            lines.append("\(report.passagesAlreadyThere) were already in the folder and were left alone.")
        }
        if report.skippedForeignFiles > 0 {
            lines.append("\(report.skippedForeignFiles) \(report.skippedForeignFiles == 1 ? "file was" : "files were") not written by diple, so they were written beside rather than over.")
        }
        return lines.joined(separator: "\n\n")
    }

    /// Reading a clippings file with a decade of highlights in it is real work — parsing, then a
    /// full pass over the library to see what is already here — so it happens off the main actor
    /// exactly as a backup does, and the row spins while it runs.
    private func prepareHighlightImport(from url: URL) {
        guard !isReadingImport else { return }
        isReadingImport = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Result {
                    let document = try HighlightImporter.shared.load(from: url)
                    let preview = try HighlightImporter.shared.preview(document)
                    return (document, preview)
                }
            }.value
            isReadingImport = false
            switch outcome {
            case .success(let loaded):
                importCandidate = HighlightImportCandidate(document: loaded.0, preview: loaded.1)
            case .failure(let error):
                dataErrorMessage = error.localizedDescription
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
/// ring (`dipleSelected`), the same mark every filter chip carries.
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
/// plus a checkmark — a colour is chosen by looking at it, so the mark goes round the colour
/// rather than over it.
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
                    // Five swatches share the row, so a cell is about 76 pt wide. "Periwinkle",
                    // before Ink replaced it, did not fit: it wrapped mid-word to
                    // "Periwinkl / e" and made one swatch taller than the other four. Every name
                    // fits today, but only at the default size — shrinking the label rather than
                    // pinning a width keeps the row honest under Dynamic Type: the name still
                    // grows with the system size, it just stops before it breaks.
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
