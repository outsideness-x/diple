import SwiftUI

/// Saving a web page into the library by pasting its address.
///
/// The failure path is the reason this is a sheet and not an alert: a link that does not
/// import is usually a link with a typo in it, and an alert throws the typed text away to say
/// so. Here the error appears under the field the reader can still fix.
public struct ImportLinkSheetView: View {
    @StateObject private var viewModel = ImportLinkViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFieldFocused: Bool

    public let onImported: (Book) -> Void

    public init(onImported: @escaping (Book) -> Void) {
        self.onImported = onImported
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DipleSpace.xxl) {
                        header
                        field
                        action
                    }
                    .padding(.horizontal, DipleSpace.xl)
                    .padding(.top, DipleSpace.xl)
                    .padding(.bottom, DipleSpace.scrollBottom)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Save a Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        HapticManager.shared.selection()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .dipleIcon(14, weight: .semibold)
                            .foregroundStyle(DipleColor.textSecondary)
                    }
                    .buttonStyle(.readerControl)
                    .disabled(viewModel.isImporting)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            viewModel.refreshPasteAvailability()
            isFieldFocused = true
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: DipleSpace.l) {
            ZStack {
                AccentWash(diameter: 140)

                Image(systemName: "link")
                    .dipleIcon(26, weight: .light)
                    .foregroundStyle(DipleColor.accent)
                    .craftGlow(DipleColor.accent.opacity(0.5), radius: 16)
            }

            Text("Paste the address of an article. diple keeps the text, the images and the headings — and leaves the banners behind.")
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: DipleSpace.s) {
            HStack(spacing: DipleSpace.s) {
                TextField("https://", text: $viewModel.urlText)
                    .dipleType(.body)
                    .foregroundStyle(DipleColor.textPrimary)
                    .tint(DipleColor.accent)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .focused($isFieldFocused)
                    .disabled(viewModel.isImporting)
                    .onSubmit(startImport)

                if !viewModel.urlText.isEmpty && !viewModel.isImporting {
                    Button {
                        HapticManager.shared.selection()
                        viewModel.urlText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .dipleIcon(14)
                            .foregroundStyle(DipleColor.textQuaternary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .diplePadding(.field)
            .padding(.vertical, DipleSpace.xs)
            .craftSurface(DipleColor.surface, radius: DipleRadius.s)
            .opacity(viewModel.isImporting ? 0.5 : 1)

            if let errorMessage = viewModel.errorMessage {
                HStack(alignment: .firstTextBaseline, spacing: DipleSpace.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .dipleIcon(10, weight: .semibold)
                    Text(errorMessage)
                        .dipleType(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(DipleColor.destructive)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if viewModel.canPaste && viewModel.urlText.isEmpty && !viewModel.isImporting {
                Button {
                    HapticManager.shared.selection()
                    viewModel.pasteFromClipboard()
                } label: {
                    HStack(spacing: DipleSpace.xs) {
                        Image(systemName: "doc.on.clipboard")
                            .dipleIcon(10, weight: .semibold)
                        Text("Paste from clipboard")
                            .dipleType(.micro, weight: .semibold)
                    }
                    .foregroundStyle(DipleColor.accent)
                    .diplePadding(.chip)
                    .background(DipleColor.accentSoft, in: Capsule())
                }
                .buttonStyle(.readerControl)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: viewModel.errorMessage)
    }

    @ViewBuilder
    private var action: some View {
        if let stage = viewModel.stage {
            HStack(spacing: DipleSpace.m) {
                ProgressView()
                    .tint(DipleColor.accent)

                Text(stage.label)
                    .dipleType(.footnote, weight: .medium)
                    .foregroundStyle(DipleColor.textSecondary)
                    // Stage labels differ in length; without a fixed side the row jumps as
                    // each one replaces the last.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.opacity)
            }
            .padding(DipleSpace.m)
            .craftSurface(DipleColor.surface, radius: DipleRadius.s)
            .animation(.easeInOut(duration: 0.2), value: stage)
        } else {
            Button(action: startImport) {
                Text("Save to Library")
                    .dipleType(.body, weight: .semibold)
                    .foregroundStyle(DipleColor.textOnAccent)
                    .frame(maxWidth: .infinity)
                    .diplePadding(.buttonLarge)
                    .background(DipleColor.accent, in: Capsule())
                    .craftGlow(radius: 16)
            }
            .buttonStyle(.readerControl)
            .disabled(viewModel.resolvedURL == nil)
            .opacity(viewModel.resolvedURL == nil ? 0.4 : 1)
            .animation(.easeOut(duration: 0.18), value: viewModel.resolvedURL)
        }
    }

    private func startImport() {
        guard viewModel.resolvedURL != nil else { return }
        HapticManager.shared.impact(.light)
        isFieldFocused = false
        viewModel.importArticle { book in
            onImported(book)
            dismiss()
        }
    }
}

#Preview("Save a link") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ImportLinkSheetView { _ in }
        }
        .preferredColorScheme(.dark)
}
