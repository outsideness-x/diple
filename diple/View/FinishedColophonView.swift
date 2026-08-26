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
                // Not "Notes and index follow": the boundary is just as often a bibliography,
                // a publisher's colophon or — in every book from Project Gutenberg, which is
                // most free EPUBs — a licence. The reader is owed the one fact that holds in
                // all of them, which is that the story is over.
                Text("The rest is back matter.")
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

    /// One line each, shrinking a little before they wrap.
    ///
    /// The three share the row equally, and at `buttonLarge` padding "Second Read" and
    /// "Keep reading" each lost their last word to a second line — which stood three pills at
    /// two different heights on the one page in the app whose whole job is to be well set.
    @ViewBuilder
    private var actionButtons: some View {
        if colophon.quoteCount > 0 {
            Button("Second Read", action: onOpenSecondRead)
                .dipleType(.footnote, weight: .semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(DipleColor.textOnAccent)
                .frame(maxWidth: .infinity)
                .diplePadding(.buttonLarge)
                .background(DipleColor.accent, in: Capsule())
                .buttonStyle(.plain)
        }

        Button("Close", action: onFinish)
            .dipleType(.footnote, weight: .semibold)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
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
            .lineLimit(1)
            .minimumScaleFactor(0.8)
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

#if DEBUG
/// The colophon over a page that counts the taps it receives.
///
/// The property worth guarding is that the final page *holds* the one beneath it: opaque,
/// taking every tap, nothing turning underneath. A real book cannot demonstrate that
/// repeatably — reaching its last page needs a seeded library, and how far one tap carries
/// depends on the device, the type size and how busy the machine is, which is what made the
/// test that tried it both slow and flaky. Here the page under the colophon is a counter, and
/// any tap that gets through moves it.
struct FinishedColophonUITestFixture: View {
    @State private var pageTaps = 0
    @State private var isPresented = true

    private let chrome = ReaderChrome.forTheme(.carbon)

    var body: some View {
        ZStack {
            chrome.page.ignoresSafeArea()

            Text("Taps reaching the page: \(pageTaps)")
                .dipleType(.body)
                .foregroundStyle(chrome.control)
                .accessibilityIdentifier("colophon.fixture.pageTaps")
                .allowsHitTesting(false)

            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { pageTaps += 1 }
                .accessibilityHidden(true)

            if isPresented {
                FinishedColophonView(
                    colophon: FinishedColophon(
                        title: "The Picture of Dorian Gray",
                        author: "Oscar Wilde",
                        date: Date(),
                        quoteCount: 2,
                        readingEnd: ReadingEnd(progression: 0.96, source: .contents)
                    ),
                    chrome: chrome,
                    onFinish: { isPresented = false },
                    onOpenSecondRead: { isPresented = false },
                    onKeepReading: { isPresented = false }
                )
            }
        }
    }
}
#endif
