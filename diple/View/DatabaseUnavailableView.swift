import SwiftUI

/// Shown in place of the app when the library database could not be opened.
///
/// The alternative was the crash this replaces, which told the reader nothing and left them
/// with deleting the app as the only move — taking the library with it. This screen says what
/// happened, and keeps the destructive option behind an explicit choice: the unreadable file
/// is never touched until someone asks for it to be.
public struct DatabaseUnavailableView: View {
    public let failure: AppDatabase.StartupFailure

    @State private var isConfirmingReset = false
    @State private var resetResult: ResetResult? = nil

    private enum ResetResult {
        case done
        case failed(String)
    }

    public init(failure: AppDatabase.StartupFailure) {
        self.failure = failure
    }

    public var body: some View {
        ZStack {
            DipleColor.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DipleSpace.xl) {
                    Image(systemName: "exclamationmark.triangle")
                        .dipleIcon(32)
                        .foregroundStyle(DipleColor.accent)

                    VStack(alignment: .leading, spacing: DipleSpace.m) {
                        Text("Your library didn't open")
                            .dipleType(.display, weight: .semibold)
                            .foregroundStyle(DipleColor.textPrimary)

                        Text("diple could not read the file that holds your books, quotes and notes. Nothing has been deleted — the file is still on this device exactly as it was.")
                            .dipleType(.callout)
                            .foregroundStyle(DipleColor.textSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    switch resetResult {
                    case .none:
                        VStack(alignment: .leading, spacing: DipleSpace.m) {
                            Text("Reopening the app is worth trying first. If it keeps failing, you can start a new empty library; the unreadable file is kept beside it, so a future version may still be able to recover it.")
                                .dipleType(.footnote)
                                .foregroundStyle(DipleColor.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button(role: .destructive) {
                                HapticManager.shared.impact(.light)
                                isConfirmingReset = true
                            } label: {
                                Text("Start a New Library")
                                    .dipleType(.callout, weight: .semibold)
                                    .foregroundStyle(DipleColor.textOnAccent)
                                    .frame(maxWidth: .infinity)
                                    .diplePadding(.buttonLarge)
                                    .background(DipleColor.accent, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                    case .done:
                        Text("Done. Close diple and open it again to start with an empty library.")
                            .dipleType(.callout, weight: .medium)
                            .foregroundStyle(DipleColor.accent)
                            .fixedSize(horizontal: false, vertical: true)

                    case let .failed(message):
                        Text("The file could not be moved: \(message)")
                            .dipleType(.footnote)
                            .foregroundStyle(DipleColor.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Kept visible rather than hidden behind a "details" affordance: this is
                    // the only description of the failure that exists anywhere the reader can
                    // reach, and it is what makes a bug report actionable.
                    VStack(alignment: .leading, spacing: DipleSpace.s) {
                        Text("Details")
                            .dipleType(.micro, weight: .semibold)
                            .foregroundStyle(DipleColor.textQuaternary)

                        Text(failure.reason)
                            .dipleType(.footnote)
                            .monospaced()
                            .foregroundStyle(DipleColor.textTertiary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(DipleSpace.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DipleColor.surface, in: RoundedRectangle(cornerRadius: DipleRadius.m))
                }
                .padding(.horizontal, DipleSpace.xl)
                .padding(.vertical, DipleSpace.xxxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .alert("Start a new library?", isPresented: $isConfirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Start New Library", role: .destructive) { reset() }
        } message: {
            Text("diple will open with an empty library next time. The unreadable file stays on this device.")
        }
    }

    private func reset() {
        do {
            _ = try AppDatabase.quarantineDatabaseFile()
            resetResult = .done
        } catch {
            resetResult = .failed(error.localizedDescription)
        }
    }
}

#Preview("Database unavailable") {
    DatabaseUnavailableView(
        failure: AppDatabase.StartupFailure(
            fileURL: URL(fileURLWithPath: "/tmp/diple.sqlite"),
            reason: "SQLite error 11: database disk image is malformed"
        )
    )
    .preferredColorScheme(.dark)
}
