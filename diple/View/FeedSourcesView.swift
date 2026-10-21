import SwiftUI

/// One of diple's suggestions, as an entry: its mark, its name, one line of why, and Follow.
///
/// arXiv is the one with a choice in it. Following "arXiv" means nothing — it publishes a few
/// hundred papers a day across a hundred and fifty fields — so its row carries the fields as
/// chips, two of them already pressed, and Follow takes whichever are pressed when it is tapped.
struct FeedRecommendationRow: View {
    let recommendation: FeedRecommendation

    @ObservedObject private var store = FeedStore.shared
    @State private var fields: Set<String> = Set(ArxivField.suggested)
    @State private var failure: String?
    @ScaledMetric(relativeTo: .body) private var sealSize: CGFloat = 34

    private var followed: FeedSource? { store.source(for: recommendation) }
    private var isArriving: Bool { store.arriving.contains(recommendation.id) }

    var body: some View {
        HStack(alignment: .top, spacing: DipleSpace.m) {
            FeedSeal(title: recommendation.title, mark: recommendation.seal, size: sealSize)

            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                Text(recommendation.title)
                    .dipleType(.editorialItem)
                    .foregroundStyle(DipleColor.textPrimary)

                Text(recommendation.pitch)
                    .dipleType(.callout)
                    .foregroundStyle(DipleColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if recommendation.isArxiv, followed == nil {
                    ArxivFieldPicker(selection: $fields)
                        .padding(.top, DipleSpace.s)
                }

                if let failure {
                    Text(failure)
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            FollowButton(isFollowing: followed != nil, isArriving: isArriving) {
                follow()
            }
            .disabled(recommendation.isArxiv && fields.isEmpty)
        }
        .padding(.vertical, DipleSpace.l)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DipleColor.hairline).frame(height: DipleStroke.hairline)
        }
        .animation(DipleMotion.standard, value: followed != nil)
        .accessibilityElement(children: .contain)
    }

    private func follow() {
        guard followed == nil else { return }
        failure = nil
        // In the order arXiv lists them, so the source's name reads the same whichever chip
        // was pressed first.
        let chosen = ArxivField.offered.map(\.code).filter(fields.contains)
        Task {
            do {
                try await store.follow(recommendation, arxivFields: recommendation.isArxiv ? chosen : nil)
                HapticManager.shared.notification(.success)
            } catch {
                HapticManager.shared.notification(.error)
                withAnimation(DipleMotion.standard) {
                    failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }
}

/// `Follow`, then a spinner while the first look happens, then `Following`.
///
/// An outline, not a fill: a page of six recommendations with six filled buttons has no
/// primary action, and this one is not the page's.
struct FollowButton: View {
    let isFollowing: Bool
    let isArriving: Bool
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.shared.impact(.light)
            action()
        } label: {
            ZStack {
                if isArriving {
                    ProgressView()
                        .controlSize(.small)
                        .tint(DipleColor.textSecondary)
                } else if isFollowing {
                    Label("Following", systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(DipleColor.textTertiary)
                } else {
                    Text("Follow")
                        .foregroundStyle(DipleColor.textPrimary)
                }
            }
            .dipleType(.footnote, weight: .semibold)
            .lineLimit(1)
            .fixedSize()
            .diplePadding(.button)
            .frame(minHeight: 36)
            .background {
                Capsule().strokeBorder(
                    isFollowing ? Color.clear : DipleColor.separator,
                    lineWidth: DipleStroke.regular
                )
            }
            .contentShape(Capsule())
            .animation(DipleMotion.standard, value: isFollowing)
            .animation(DipleMotion.standard, value: isArriving)
        }
        .buttonStyle(.readerControl)
        .disabled(isFollowing || isArriving)
        .accessibilityLabel(isFollowing ? "Following" : "Follow")
    }
}

/// The fields of arXiv to follow, as chips; the chosen ones carry the app's one ring.
struct ArxivFieldPicker: View {
    @Binding var selection: Set<String>

    var body: some View {
        FlowLayout(spacing: DipleSpace.xs) {
            ForEach(ArxivField.offered) { field in
                let isChosen = selection.contains(field.code)
                Button {
                    HapticManager.shared.selection()
                    withAnimation(DipleMotion.snappy) {
                        if isChosen { selection.remove(field.code) } else { selection.insert(field.code) }
                    }
                } label: {
                    Text(field.name)
                        .dipleType(.micro, weight: isChosen ? .semibold : .medium)
                        .foregroundStyle(isChosen ? DipleColor.accentInk : DipleColor.textSecondary)
                        .diplePadding(.chip)
                        .padding(.vertical, DipleSpace.hair)
                        .dipleSelected(isChosen, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.readerControl)
                .accessibilityAddTraits(isChosen ? .isSelected : [])
            }
        }
    }
}

/// The sources: what the reader follows, the way to follow something new, and what diple
/// suggests.
///
/// One sheet for all three because they are one question — what comes into the feed — and a
/// masthead with three glyphs for it would spend the head of the page on a page that is opened
/// a few times a year.
struct FeedSourcesSheet: View {
    @ObservedObject private var store = FeedStore.shared
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFieldFocused: Bool
    @State private var address = ""
    @State private var isLooking = false
    @State private var found: FeedDiscovery.Found?
    @State private var failure: String?
    @State private var canPaste = false
    @State private var editingFields: FeedSource?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DipleSpace.xxxl) {
                    addSection
                    if !store.sources.isEmpty { followingSection }
                    if !store.unfollowedRecommendations.isEmpty { recommendationsSection }
                }
                .padding(.horizontal, DipleSpace.xl)
                .padding(.top, DipleSpace.l)
                .padding(.bottom, DipleSpace.scrollBottom)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DipleColor.canvas.ignoresSafeArea())
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        HapticManager.shared.selection()
                        dismiss()
                    }
                    .dipleType(.body, weight: .semibold)
                    .foregroundStyle(DipleColor.accentInk)
                }
            }
            .sheet(item: $editingFields) { source in
                ArxivFieldsSheet(source: source)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            canPaste = UIPasteboard.general.hasURLs || UIPasteboard.general.hasStrings
        }
    }

    // MARK: - Adding

    private var addSection: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            Text("Follow a blog, a journal or a newsletter. Its three newest pieces wait in the feed; older ones leave on their own.")
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DipleSpace.s) {
                Image(systemName: "dot.radiowaves.up.forward")
                    .dipleIcon(13, weight: .medium)
                    .foregroundStyle(DipleColor.textQuaternary)

                TextField("Address of a site or its feed", text: $address)
                    .dipleType(.body)
                    .foregroundStyle(DipleColor.textPrimary)
                    .tint(DipleColor.accentInk)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.search)
                    .focused($isFieldFocused)
                    .onSubmit(look)
                    .onChange(of: address) { _, _ in
                        found = nil
                        failure = nil
                    }
                    .accessibilityIdentifier("feed.address")

                if isLooking {
                    ProgressView().controlSize(.small).tint(DipleColor.textTertiary)
                } else if !address.isEmpty {
                    Button {
                        HapticManager.shared.selection()
                        address = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .dipleIcon(14)
                            .foregroundStyle(DipleColor.textQuaternary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
            }
            .diplePadding(.field)
            .padding(.vertical, DipleSpace.xs)
            .craftSurface(DipleColor.surface, radius: DipleRadius.s)

            if let failure {
                HStack(alignment: .firstTextBaseline, spacing: DipleSpace.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .dipleIcon(10, weight: .semibold)
                    Text(failure)
                        .dipleType(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(DipleColor.destructive)
                .transition(.opacity)
            } else if let found {
                FoundSourcePreview(found: found) {
                    store.follow(found)
                    HapticManager.shared.notification(.success)
                    withAnimation(DipleMotion.standard) {
                        self.found = nil
                        address = ""
                    }
                    isFieldFocused = false
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if address.isEmpty, canPaste {
                Button {
                    HapticManager.shared.selection()
                    if let url = UIPasteboard.general.url {
                        address = url.absoluteString
                    } else if let string = UIPasteboard.general.string {
                        address = string.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    look()
                } label: {
                    Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                        .dipleType(.micro, weight: .semibold)
                        .foregroundStyle(DipleColor.accentInk)
                        .diplePadding(.chip)
                        .background(DipleColor.accentSoft, in: Capsule())
                }
                .buttonStyle(.readerControl)
            }
        }
        .animation(DipleMotion.standard, value: found?.feedURL)
        .animation(DipleMotion.standard, value: failure)
    }

    private func look() {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLooking else { return }
        isLooking = true
        failure = nil
        found = nil
        Task {
            do {
                let result = try await FeedDiscovery.find(text)
                found = result
                HapticManager.shared.impact(.light)
            } catch {
                HapticManager.shared.notification(.error)
                failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isLooking = false
        }
    }

    // MARK: - Following

    private var followingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Following")
                .dipleSectionHeading()
                .padding(.bottom, DipleSpace.xs)

            ForEach(store.sources) { source in
                FollowedSourceRow(source: source) {
                    editingFields = source
                }
            }
        }
    }

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Worth following")
                .dipleSectionHeading()
                .padding(.bottom, DipleSpace.xs)

            ForEach(store.unfollowedRecommendations) { recommendation in
                FeedRecommendationRow(recommendation: recommendation)
                    .transition(.opacity)
            }
        }
    }
}

/// What was found at an address, before it is followed: the source and its three newest
/// titles — exactly what following it will put in the feed.
private struct FoundSourcePreview: View {
    let found: FeedDiscovery.Found
    let onFollow: () -> Void

    private var title: String {
        if let fields = found.arxivFields { return ArxivField.title(for: fields) }
        return found.feed.title.isEmpty ? (found.feedURL.host ?? "") : found.feed.title
    }

    private var newest: [FeedItem] {
        FeedRack.merge(sourceID: "preview", fetched: found.feed.items, existing: [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            HStack(spacing: DipleSpace.m) {
                FeedSeal(title: title, mark: found.arxivFields == nil ? nil : "χ", size: 34)
                VStack(alignment: .leading, spacing: DipleSpace.hair) {
                    Text(title)
                        .dipleType(.editorialItem)
                        .foregroundStyle(DipleColor.textPrimary)
                        .lineLimit(2)
                    Text(found.feed.siteURL?.host ?? found.feedURL.host ?? "")
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: DipleSpace.s)
            }

            VStack(alignment: .leading, spacing: DipleSpace.s) {
                ForEach(newest) { item in
                    HStack(alignment: .firstTextBaseline, spacing: DipleSpace.s) {
                        Circle()
                            .fill(DipleColor.textQuaternary)
                            .frame(width: 3, height: 3)
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                        Text(item.title)
                            .dipleType(.editorialExcerpt)
                            .foregroundStyle(DipleColor.textSecondary)
                            .lineLimit(2)
                    }
                }
            }

            Button(action: onFollow) {
                Text("Follow")
                    .dipleType(.body, weight: .semibold)
                    .foregroundStyle(DipleColor.textOnAccent)
                    .frame(maxWidth: .infinity)
                    .diplePadding(.button)
                    .background(DipleColor.accent, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.readerControl)
            .accessibilityIdentifier("feed.follow")
        }
        .padding(DipleSpace.l)
        .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.l)
    }
}

/// A source the reader follows, in the list of them: its name, where it lives or why it did not
/// answer, and a menu with the rest.
private struct FollowedSourceRow: View {
    let source: FeedSource
    let onEditFields: () -> Void

    @ObservedObject private var store = FeedStore.shared
    @Environment(\.openURL) private var openURL
    @State private var isConfirmingUnfollow = false
    @ScaledMetric(relativeTo: .body) private var sealSize: CGFloat = 28

    private var detail: String {
        if let failure = source.failure { return failure }
        return source.host ?? ""
    }

    var body: some View {
        HStack(spacing: DipleSpace.m) {
            FeedSeal(source: source, size: sealSize)

            VStack(alignment: .leading, spacing: DipleSpace.hair) {
                Text(source.title)
                    .dipleType(.body, weight: .medium)
                    .foregroundStyle(DipleColor.textPrimary)
                    .lineLimit(2)
                Text(detail)
                    .dipleType(.caption)
                    .foregroundStyle(source.failure == nil ? DipleColor.textTertiary : DipleColor.destructive)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                if source.isArxiv {
                    Button("Fields…", systemImage: "square.grid.2x2", action: onEditFields)
                }
                if let site = source.siteURL {
                    Button("Open the site", systemImage: "safari") { openURL(site) }
                }
                Button("Copy feed address", systemImage: "link") {
                    UIPasteboard.general.url = source.feedURL
                }
                Divider()
                Button("Unfollow", systemImage: "minus.circle", role: .destructive) {
                    HapticManager.shared.impact(.medium)
                    store.unfollow(source.id)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .dipleIcon(14, weight: .semibold)
                    .foregroundStyle(DipleColor.textTertiary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More for \(source.title)")
        }
        .padding(.vertical, DipleSpace.s)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DipleColor.hairline).frame(height: DipleStroke.hairline)
        }
        .transition(.opacity)
    }
}

/// Changing which fields of arXiv a source follows.
private struct ArxivFieldsSheet: View {
    let source: FeedSource

    @ObservedObject private var store = FeedStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var fields: Set<String>

    init(source: FeedSource) {
        self.source = source
        _fields = State(initialValue: Set(source.arxivFields ?? ArxivField.suggested))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DipleSpace.l) {
                Text("The newest papers in any of these fields arrive in the feed, three at a time.")
                    .dipleType(.callout)
                    .foregroundStyle(DipleColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                ArxivFieldPicker(selection: $fields)
                Spacer()
            }
            .padding(DipleSpace.xl)
            .background(DipleColor.canvas.ignoresSafeArea())
            .navigationTitle("arXiv fields")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let chosen = ArxivField.offered.map(\.code).filter(fields.contains)
                        let changed = Set(chosen) != Set(source.arxivFields ?? [])
                        dismiss()
                        guard changed else { return }
                        Task { await store.setArxivFields(chosen, for: source.id) }
                    }
                    .disabled(fields.isEmpty)
                    .dipleType(.body, weight: .semibold)
                    .foregroundStyle(DipleColor.accentInk)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
