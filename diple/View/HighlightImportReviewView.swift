import SwiftUI

public struct HighlightImportCandidate: Identifiable, Sendable {
    public let id = UUID()
    public let document: HighlightImportDocument
    public let preview: HighlightImportPreview

    public init(document: HighlightImportDocument, preview: HighlightImportPreview) {
        self.document = document
        self.preview = preview
    }
}

/// The boundary between choosing somebody else's export and writing into the library.
///
/// It is the restore sheet's sibling by construction — the same hero, the same counted rows,
/// the same promise that nothing is deleted and the button is the last word — because the two
/// are the same act with a different file in hand. What is particular to this one is the
/// paragraph about where imported passages land: they arrive as their own groups rather than
/// on books already on the shelf, and a reader who is not told that will look for them under
/// the book and conclude the import failed.
public struct HighlightImportReviewView: View {
    public let candidate: HighlightImportCandidate
    public let importPassages: () async throws -> HighlightImportReport

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .review

    fileprivate enum Phase: Equatable {
        case review
        case importing
        case complete(HighlightImportReport)
        case failed(String)
    }

    public init(
        candidate: HighlightImportCandidate,
        importPassages: @escaping () async throws -> HighlightImportReport
    ) {
        self.candidate = candidate
        self.importPassages = importPassages
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
                            whereTheyLandedNote
                        } else {
                            changeSummary
                            whereTheyLandNote
                            safetyNote
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
            .navigationTitle("Import highlights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(phase.isComplete ? "Done" : "Cancel") { dismiss() }
                        .dipleType(.body, weight: .semibold)
                        .foregroundStyle(DipleColor.accentInk)
                        .disabled(phase == .importing)
                }
            }
        }
        .interactiveDismissDisabled(phase == .importing)
        .presentationDetents([.large])
    }

    private var hero: some View {
        ReviewHero(
            systemImage: "tray.and.arrow.down",
            isComplete: phase.isComplete,
            title: phase.isComplete ? "Your passages are here" : "Bring your reading with you",
            detail: phase.isComplete
                ? "They are in Highlights now, grouped by the book they came from."
                : "A \(candidate.document.kind.fileDescription). Review it before anything is written."
        )
    }

    private var changeSummary: some View {
        VStack(alignment: .leading, spacing: DipleSpace.l) {
            Text("THIS IMPORT")
                .dipleType(.micro, weight: .semibold)
                .foregroundStyle(DipleColor.textTertiary)
                .padding(.horizontal, DipleSpace.xs)

            VStack(spacing: 1) {
                ReviewCountRow(
                    icon: "quote.opening",
                    title: "Passages",
                    detail: "to add",
                    value: candidate.preview.passagesToAdd
                )
                ReviewCountRow(
                    icon: "books.vertical",
                    title: "Books",
                    detail: candidate.preview.sourceCount == 1 ? "in this file" : "in this file, grouped by title",
                    value: candidate.preview.sourceCount
                )
                if candidate.preview.passagesAlreadyHere > 0 {
                    ReviewCountRow(
                        icon: "checkmark.circle",
                        title: "Already here",
                        detail: "skipped, not duplicated",
                        value: candidate.preview.passagesAlreadyHere
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DipleRadius.m, style: .continuous))
        }
    }

    private var whereTheyLandNote: some View {
        ReviewNote(
            icon: "quote.opening",
            title: "They arrive as their own groups",
            detail: "\(candidate.document.kind.title) records the words, not a position inside your copy of the book, so imported passages are never attached to a book on your shelf — they would sit in its list unable to open the page. Find them in Highlights, under the title they came from."
        )
    }

    private var whereTheyLandedNote: some View {
        ReviewNote(
            icon: "magnifyingglass",
            title: "Searchable straight away",
            detail: "Every passage, its note and its tags are in search now, and they resurface with everything else you have saved."
        )
    }

    private var safetyNote: some View {
        ReviewNote(
            icon: "shield.checkered",
            title: "A safe import",
            detail: "Nothing already in your library is changed or deleted. A passage this file has brought before is skipped, so running the same export again adds nothing."
        )
    }

    private func failureNote(_ message: String) -> some View {
        ReviewNote(
            icon: "exclamationmark.triangle",
            title: "Import stopped safely",
            detail: message,
            colour: DipleColor.destructive
        )
    }

    private func completedSummary(_ report: HighlightImportReport) -> some View {
        ReviewOutcome(
            label: "IMPORTED",
            value: report.preview.passagesToAdd,
            detail: report.preview.passagesToAdd == 1 ? "passage joined your library" : "passages joined your library"
        )
    }

    @ViewBuilder
    private var action: some View {
        switch phase {
        case .complete:
            Button("Done") { dismiss() }
                .reviewPrimaryButton()

        case .importing:
            ReviewProgressCapsule("Importing…")

        case .review, .failed:
            Button(importButtonTitle) {
                beginImport()
            }
            .reviewPrimaryButton()
            .disabled(candidate.preview.isNoOp)
            .opacity(candidate.preview.isNoOp ? 0.45 : 1)
        }
    }

    private var importButtonTitle: String {
        if candidate.preview.isNoOp { return "Nothing New to Import" }
        let count = candidate.preview.passagesToAdd
        return count == 1 ? "Import 1 Passage" : "Import \(count) Passages"
    }

    private func beginImport() {
        guard phase != .importing, !candidate.preview.isNoOp else { return }
        phase = .importing
        Task {
            do {
                let report = try await importPassages()
                HapticManager.shared.notification(.success)
                withAnimation(DipleMotion.gentle) { phase = .complete(report) }
            } catch {
                HapticManager.shared.notification(.error)
                withAnimation(DipleMotion.standard) { phase = .failed(error.localizedDescription) }
            }
        }
    }
}

private extension HighlightImportReviewView.Phase {
    var isComplete: Bool {
        if case .complete = self { return true }
        return false
    }
}
