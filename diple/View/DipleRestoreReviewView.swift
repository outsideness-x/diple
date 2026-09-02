import SwiftUI

public struct DipleRestoreCandidate: Identifiable, Sendable {
    public let id = UUID()
    public let payload: DipleExportPayload
    public let preview: DipleRestorePreview

    public init(payload: DipleExportPayload, preview: DipleRestorePreview) {
        self.payload = payload
        self.preview = preview
    }
}

/// The boundary between choosing a JSON file and mutating the library. The sheet says exactly
/// what will merge, spells out what the portable export does not contain, and keeps the local
/// side as the winner whenever it is newer.
public struct DipleRestoreReviewView: View {
    public let candidate: DipleRestoreCandidate
    public let restore: () async throws -> DipleRestoreReport

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .review

    fileprivate enum Phase: Equatable {
        case review
        case restoring
        case complete(DipleRestoreReport)
        case failed(String)
    }

    public init(
        candidate: DipleRestoreCandidate,
        restore: @escaping () async throws -> DipleRestoreReport
    ) {
        self.candidate = candidate
        self.restore = restore
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DipleSpace.xxl) {
                        hero
                        if case .complete(let report) = phase {
                            completedSummary(report)
                        } else {
                            changeSummary
                            safetyNote
                            if candidate.preview.sourceReferencesMissing > 0 {
                                missingSourcesNote
                            }
                            if case .failed(let message) = phase {
                                failureNote(message)
                            }
                        }
                        action
                    }
                    .padding(.horizontal, DipleSpace.xl)
                    .padding(.top, DipleSpace.xl)
                    .padding(.bottom, DipleSpace.xxxl)
                }
            }
            .navigationTitle("Restore Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(phase.isComplete ? "Done" : "Cancel") { dismiss() }
                        .dipleType(.body, weight: .semibold)
                        .foregroundStyle(DipleColor.accentInk)
                        .disabled(phase == .restoring)
                }
            }
        }
        .interactiveDismissDisabled(phase == .restoring)
        .presentationDetents([.large])
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: DipleSpace.l) {
            ZStack {
                RoundedRectangle(cornerRadius: DipleRadius.l, style: .continuous)
                    .fill(DipleColor.surfaceRaised)
                    .overlay {
                        RoundedRectangle(cornerRadius: DipleRadius.l, style: .continuous)
                            .stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline)
                    }

                VStack(spacing: DipleSpace.s) {
                    Image(systemName: phase.isComplete ? "checkmark" : "arrow.counterclockwise")
                        .dipleIcon(24, weight: .medium)
                        .foregroundStyle(phase.isComplete ? DipleColor.textOnAccent : DipleColor.textPrimary)
                        .frame(width: 52, height: 52)
                        .background(phase.isComplete ? DipleColor.accent : DipleColor.surfaceOverlay, in: Circle())

                    Capsule()
                        .fill(DipleColor.accent)
                        .frame(width: 28, height: 2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 154)

            VStack(alignment: .leading, spacing: DipleSpace.s) {
                Text(phase.isComplete ? "Your library is restored" : "Bring your work back")
                    .dipleType(.display)
                    .foregroundStyle(DipleColor.textPrimary)

                Text(
                    phase.isComplete
                        ? "The backup was merged without deleting anything already on this device."
                        : "Exported \(candidate.payload.exportedAt.formatted(date: .abbreviated, time: .shortened)). Review the merge before anything changes."
                )
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var changeSummary: some View {
        VStack(alignment: .leading, spacing: DipleSpace.l) {
            Text("THIS RESTORE")
                .dipleType(.micro, weight: .semibold)
                .foregroundStyle(DipleColor.textTertiary)
                .padding(.horizontal, DipleSpace.xs)

            VStack(spacing: 1) {
                restoreRow(
                    icon: "book.closed",
                    title: "Reading positions",
                    value: candidate.preview.sourcePositionsUpdated,
                    detail: candidate.preview.sourcePositionsUpdated == 1 ? "newer position" : "newer positions"
                )
                restoreRow(
                    icon: "quote.opening",
                    title: "Highlights",
                    value: candidate.preview.highlightsAdded,
                    detail: candidate.preview.highlightsAdded == 1 ? "passage to add" : "passages to add"
                )
                restoreRow(
                    icon: "note.text",
                    title: "Notes",
                    value: candidate.preview.notesAdded + candidate.preview.notesUpdated,
                    detail: noteDetail
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: DipleRadius.m, style: .continuous))
        }
    }

    private var noteDetail: String {
        let added = candidate.preview.notesAdded
        let updated = candidate.preview.notesUpdated
        switch (added, updated) {
        case (0, 0): return "nothing newer"
        case (_, 0): return "\(added) new"
        case (0, _): return "\(updated) newer"
        default: return "\(added) new · \(updated) newer"
        }
    }

    private func restoreRow(icon: String, title: String, value: Int, detail: String) -> some View {
        HStack(spacing: DipleSpace.m) {
            Image(systemName: icon)
                .dipleIcon(15, weight: .medium)
                .foregroundStyle(DipleColor.accentInk)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .dipleType(.body, weight: .medium)
                    .foregroundStyle(DipleColor.textPrimary)
                Text(detail)
                    .dipleType(.caption)
                    .foregroundStyle(DipleColor.textTertiary)
            }

            Spacer()

            Text("\(value)")
                .dipleType(.title)
                .foregroundStyle(value > 0 ? DipleColor.textPrimary : DipleColor.textQuaternary)
                .monospacedDigit()
        }
        .padding(.horizontal, DipleSpace.l)
        .padding(.vertical, DipleSpace.m)
        .background(DipleColor.surfaceRaised)
    }

    private var safetyNote: some View {
        noteSurface(
            icon: "shield.checkered",
            title: "A safe merge",
            detail: "Nothing local is deleted. Newer local notes and reading positions stay exactly as they are; matching items are never duplicated."
        )
    }

    private var missingSourcesNote: some View {
        let count = candidate.preview.sourceReferencesMissing
        return noteSurface(
            icon: "doc.badge.ellipsis",
            title: count == 1 ? "1 source file is not on this device" : "\(count) source files are not on this device",
            detail: "Portable backups contain your positions, highlights and notes, not the original EPUB or PDF files. Their highlights and linked notes will still return. Import the original files before restoring if you also want their reading positions reconnected."
        )
    }

    private func failureNote(_ message: String) -> some View {
        noteSurface(
            icon: "exclamationmark.triangle",
            title: "Restore stopped safely",
            detail: message,
            colour: DipleColor.destructive
        )
    }

    private func noteSurface(
        icon: String,
        title: String,
        detail: String,
        colour: Color = DipleColor.accent
    ) -> some View {
        HStack(alignment: .top, spacing: DipleSpace.m) {
            Image(systemName: icon)
                .dipleIcon(16, weight: .medium)
                .foregroundStyle(colour)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                Text(title)
                    .dipleType(.body, weight: .medium)
                    .foregroundStyle(DipleColor.textPrimary)
                Text(detail)
                    .dipleType(.caption)
                    .foregroundStyle(DipleColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DipleSpace.l)
        .craftSurface(DipleColor.surface, radius: DipleRadius.m)
    }

    private func completedSummary(_ report: DipleRestoreReport) -> some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            Text("RESTORED")
                .dipleType(.micro, weight: .semibold)
                .foregroundStyle(DipleColor.textTertiary)
            Text("\(report.preview.changeCount)")
                .dipleType(.hero)
                .foregroundStyle(DipleColor.textPrimary)
                .monospacedDigit()
            Text(report.preview.changeCount == 1 ? "item returned to your library" : "items returned to your library")
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DipleSpace.l)
        .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.m)
    }

    @ViewBuilder
    private var action: some View {
        switch phase {
        case .complete:
            Button("Done") { dismiss() }
                .primaryRestoreButton()

        case .restoring:
            HStack(spacing: DipleSpace.m) {
                ProgressView().tint(DipleColor.textOnAccent)
                Text("Restoring…")
                    .dipleType(.body, weight: .semibold)
            }
            .foregroundStyle(DipleColor.textOnAccent)
            .frame(maxWidth: .infinity)
            .diplePadding(.buttonLarge)
            .background(DipleColor.accent, in: Capsule())
            .accessibilityElement(children: .combine)

        case .review, .failed:
            Button(restoreButtonTitle) {
                beginRestore()
            }
            .primaryRestoreButton()
            .disabled(candidate.preview.isNoOp)
            .opacity(candidate.preview.isNoOp ? 0.45 : 1)
        }
    }

    private var restoreButtonTitle: String {
        if candidate.preview.isNoOp { return "Nothing New to Restore" }
        let count = candidate.preview.changeCount
        return count == 1 ? "Restore 1 Item" : "Restore \(count) Items"
    }

    private func beginRestore() {
        guard phase != .restoring, !candidate.preview.isNoOp else { return }
        phase = .restoring
        Task {
            do {
                let report = try await restore()
                HapticManager.shared.notification(.success)
                withAnimation(DipleMotion.gentle) { phase = .complete(report) }
            } catch {
                HapticManager.shared.notification(.error)
                withAnimation(DipleMotion.standard) { phase = .failed(error.localizedDescription) }
            }
        }
    }
}

private extension DipleRestoreReviewView.Phase {
    var isComplete: Bool {
        if case .complete = self { return true }
        return false
    }
}

private extension View {
    func primaryRestoreButton() -> some View {
        self
            .dipleType(.body, weight: .semibold)
            .foregroundStyle(DipleColor.textOnAccent)
            .frame(maxWidth: .infinity)
            .diplePadding(.buttonLarge)
            .background(DipleColor.accent, in: Capsule())
            .buttonStyle(.readerControl)
    }
}
