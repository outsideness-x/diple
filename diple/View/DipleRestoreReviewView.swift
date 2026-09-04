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
            .navigationTitle("Restore backup")
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
        ReviewHero(
            systemImage: "arrow.counterclockwise",
            isComplete: phase.isComplete,
            title: phase.isComplete ? "Your library is restored" : "Bring your work back",
            detail: phase.isComplete
                ? "The backup was merged without deleting anything already on this device."
                : "Exported \(candidate.payload.exportedAt.formatted(date: .abbreviated, time: .shortened)). Review the merge before anything changes."
        )
    }

    private var changeSummary: some View {
        VStack(alignment: .leading, spacing: DipleSpace.l) {
            Text("THIS RESTORE")
                .dipleType(.micro, weight: .semibold)
                .foregroundStyle(DipleColor.textTertiary)
                .padding(.horizontal, DipleSpace.xs)

            VStack(spacing: 1) {
                ReviewCountRow(
                    icon: "book.closed",
                    title: "Reading positions",
                    detail: candidate.preview.sourcePositionsUpdated == 1 ? "newer position" : "newer positions",
                    value: candidate.preview.sourcePositionsUpdated
                )
                ReviewCountRow(
                    icon: "quote.opening",
                    title: "Highlights",
                    detail: candidate.preview.highlightsAdded == 1 ? "passage to add" : "passages to add",
                    value: candidate.preview.highlightsAdded
                )
                ReviewCountRow(
                    icon: "note.text",
                    title: "Notes",
                    detail: noteDetail,
                    value: candidate.preview.notesAdded + candidate.preview.notesUpdated
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

    private var safetyNote: some View {
        ReviewNote(
            icon: "shield.checkered",
            title: "A safe merge",
            detail: "Nothing local is deleted. Newer local notes and reading positions stay exactly as they are; matching items are never duplicated."
        )
    }

    private var missingSourcesNote: some View {
        let count = candidate.preview.sourceReferencesMissing
        return ReviewNote(
            icon: "doc.badge.ellipsis",
            title: count == 1 ? "1 source file is not on this device" : "\(count) source files are not on this device",
            detail: "Portable backups contain your positions, highlights and notes, not the original EPUB or PDF files. Their highlights and linked notes will still return. Import the original files before restoring if you also want their reading positions reconnected."
        )
    }

    private func failureNote(_ message: String) -> some View {
        ReviewNote(
            icon: "exclamationmark.triangle",
            title: "Restore stopped safely",
            detail: message,
            colour: DipleColor.destructive
        )
    }

    private func completedSummary(_ report: DipleRestoreReport) -> some View {
        ReviewOutcome(
            label: "RESTORED",
            value: report.preview.changeCount,
            detail: report.preview.changeCount == 1
                ? "item returned to your library"
                : "items returned to your library"
        )
    }

    @ViewBuilder
    private var action: some View {
        switch phase {
        case .complete:
            Button("Done") { dismiss() }
                .reviewPrimaryButton()

        case .restoring:
            ReviewProgressCapsule("Restoring…")

        case .review, .failed:
            Button(restoreButtonTitle) {
                beginRestore()
            }
            .reviewPrimaryButton()
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
