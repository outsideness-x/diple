import SwiftUI

/// The publication's own final page: a quiet question, not a completion ceremony.
public struct FinishedColophonView: View {
    public let colophon: FinishedColophon
    public let chrome: ReaderChrome
    public let onFinish: () -> Void
    public let onOpenSecondRead: () -> Void
    public let onKeepReading: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var appeared = false

    public init(
        colophon: FinishedColophon,
        chrome: ReaderChrome,
        onFinish: @escaping () -> Void,
        onOpenSecondRead: @escaping () -> Void,
        onKeepReading: @escaping () -> Void
    ) {
        self.colophon = colophon
        self.chrome = chrome
        self.onFinish = onFinish
        self.onOpenSecondRead = onOpenSecondRead
        self.onKeepReading = onKeepReading
    }

    public var body: some View {
        ZStack {
            chrome.page
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DipleSpace.xxl) {
                    identity

                    Rectangle()
                        .fill(chrome.separator)
                        .frame(height: DipleStroke.hairline)
                        .accessibilityHidden(true)

                    facts
                    actions
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DipleSpace.xl)
                .padding(.vertical, DipleSpace.xxxl)
            }
            .scrollIndicators(.hidden)
            .opacity(appeared ? 1 : 0)
            .offset(y: reduceMotion || appeared ? 0 : DipleSpace.m)
        }
        .contentShape(Rectangle())
        .environment(\.colorScheme, chrome.colorScheme)
        .onAppear {
            HapticManager.shared.notification(.success)
            withAnimation(DipleMotion.gentle) {
                appeared = true
            }
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: DipleSpace.s) {
            Text(colophon.title)
                .dipleType(.display)
                .foregroundStyle(chrome.control)
                .fixedSize(horizontal: false, vertical: true)

            Text(colophon.author)
                .dipleType(.callout)
                .foregroundStyle(chrome.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            Text(dateLine)
                .dipleType(.micro)
                .foregroundStyle(chrome.secondary)
                .monospacedDigit()

            if colophon.quoteCount > 0 {
                Text(passageLine)
                    .dipleType(.footnote)
                    .foregroundStyle(chrome.control)
                    .monospacedDigit()
            }

            if colophon.readingEnd.hasBackMatter {
                Text("Notes and index follow.")
                    .dipleType(.callout)
                    .foregroundStyle(chrome.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: DipleSpace.m) {
                actionButtons
            }
        } else {
            HStack(spacing: DipleSpace.m) {
                actionButtons
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if colophon.quoteCount > 0 {
            Button("Second Read", action: onOpenSecondRead)
                .dipleType(.footnote, weight: .semibold)
                .foregroundStyle(DipleColor.textOnAccent)
                .frame(maxWidth: .infinity)
                .diplePadding(.buttonLarge)
                .background(DipleColor.accent, in: Capsule())
                .buttonStyle(.plain)
        }

        Button("Close", action: onFinish)
            .dipleType(.footnote, weight: .semibold)
            .foregroundStyle(chrome.control)
            .frame(maxWidth: .infinity)
            .diplePadding(.buttonLarge)
            .overlay {
                Capsule()
                    .stroke(chrome.separator, lineWidth: DipleStroke.hairline)
            }
            .buttonStyle(.plain)

        Button("Keep reading", action: onKeepReading)
            .dipleType(.footnote, weight: .semibold)
            .foregroundStyle(chrome.secondary)
            .frame(maxWidth: .infinity)
            .diplePadding(.buttonLarge)
            .buttonStyle(.plain)
    }

    private var passageLine: String {
        colophon.quoteCount == 1
            ? "1 passage saved"
            : "\(colophon.quoteCount) passages saved"
    }

    private var dateLine: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .current
        let components = calendar.dateComponents([.day, .month, .year], from: colophon.date)
        let months = calendar.monthSymbols
        guard let day = components.day,
              let month = components.month,
              let year = components.year,
              months.indices.contains(month - 1)
        else { return "FINISHED" }

        return "FINISHED · \(day) \(months[month - 1].uppercased()) \(year)"
    }
}
