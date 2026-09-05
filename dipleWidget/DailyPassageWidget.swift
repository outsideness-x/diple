import SwiftUI
import WidgetKit

/// One saved passage, on the Home Screen and the Lock Screen.
///
/// The widget reads and never writes. Everything it shows was decided by the app and left in
/// the App Group — see `DailyQuoteSnapshot` — so the passage here and the passage on Home are
/// the same passage, chosen by one rule in one place, rather than two implementations of
/// "today's quote" that agree until the day they do not.
struct DailyPassageWidget: Widget {
    static let kind = "diple.DailyPassage"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: DailyPassageProvider()) { entry in
            DailyPassageView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Passage")
        .description("A passage you saved, returned one day at a time.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct DailyPassageEntry: TimelineEntry {
    let date: Date
    let passage: DailyQuoteSnapshot.Entry?
    /// True when the library holds passages but this day has none resolved — the app has not
    /// run for longer than the snapshot reaches ahead. It is a different sentence from "you
    /// have not saved anything yet", and saying the wrong one is worse than saying nothing.
    let isBeyondSnapshot: Bool
}

struct DailyPassageProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyPassageEntry {
        DailyPassageEntry(date: Date(), passage: .placeholder, isBeyondSnapshot: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyPassageEntry) -> Void) {
        completion(entry(for: Date(), snapshot: loadSnapshot()))
    }

    /// One entry per day the snapshot reaches, each beginning at that day's midnight, and a
    /// reload asked for the morning after the last of them. The system may refresh sooner and
    /// is welcome to; what this guarantees is that a phone left alone still turns the page.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyPassageEntry>) -> Void) {
        let snapshot = loadSnapshot()
        let now = Date()
        var entries = [entry(for: now, snapshot: snapshot)]

        var day = DailyQuoteDay.startOfNextDay(after: now)
        for _ in 0..<DailyQuoteSnapshotStore.horizonInDays {
            guard snapshot?.entry(for: DailyQuoteDay.key(for: day)) != nil else { break }
            entries.append(entry(for: day, snapshot: snapshot))
            day = DailyQuoteDay.startOfNextDay(after: day)
        }

        completion(Timeline(entries: entries, policy: .after(day)))
    }

    private func loadSnapshot() -> DailyQuoteSnapshot? {
        (try? DailyQuoteSnapshotStore.shared())?.read()
    }

    private func entry(for date: Date, snapshot: DailyQuoteSnapshot?) -> DailyPassageEntry {
        let passage = snapshot?.entry(for: DailyQuoteDay.key(for: date))
        return DailyPassageEntry(
            date: date,
            passage: passage,
            isBeyondSnapshot: passage == nil && (snapshot?.totalQuoteCount ?? 0) > 0
        )
    }
}

// MARK: - Views

struct DailyPassageView: View {
    let entry: DailyPassageEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let passage = entry.passage {
                switch family {
                case .accessoryRectangular:
                    LockScreenPassage(passage: passage)
                default:
                    HomeScreenPassage(passage: passage, family: family)
                }
            } else {
                EmptyPassage(isBeyondSnapshot: entry.isBeyondSnapshot, family: family)
            }
        }
        // No custom URL when there is nothing to go to: a widget that opens the app on a
        // promise it cannot keep is worse than one that just opens the app.
        .widgetURL(entry.passage == nil ? nil : URL(string: "diple://daily"))
    }
}

/// The Home Screen card: the passage, and under it the book it came from.
///
/// The rule down the left is the same gesture `QuoteCardView` makes in the app — the colour the
/// reader marked the passage with, standing beside it rather than behind it. It is the only
/// colour on the card, which is what lets a yellow passage and a green one be told apart at a
/// glance without either of them shouting.
private struct HomeScreenPassage: View {
    let passage: DailyQuoteSnapshot.Entry
    let family: WidgetFamily

    private var quoteSize: CGFloat {
        switch family {
        case .systemSmall: return 13
        case .systemLarge: return 17
        default: return 15
        }
    }

    private var lineLimit: Int {
        switch family {
        case .systemSmall: return 6
        case .systemLarge: return 14
        default: return 5
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(Color(widgetHex: passage.colorHex))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 8) {
                Text(passage.text)
                    // The reading serif rather than the interface face: this is a published
                    // sentence, not a label. See "Вторая гарнитура" in CLAUDE.md for why a
                    // saved passage is one of the few places that changes voice.
                    .font(.system(size: quoteSize, design: .serif))
                    .foregroundStyle(.primary)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .lineLimit(lineLimit)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)

                if let byline {
                    Text(byline)
                        .font(.system(size: 10, weight: .medium))
                        .textCase(.uppercase)
                        .tracking(0.4)
                        .foregroundStyle(.tertiary)
                        .lineLimit(family == .systemSmall ? 1 : 2)
                }
            }
        }
    }

    /// Title first, byline after it, and only when there is room for both — a small widget that
    /// spends two of its six lines on attribution has stopped being a passage.
    private var byline: String? {
        guard let title = passage.bookTitle, !title.isEmpty else { return passage.bookAuthor }
        guard family != .systemSmall, let author = passage.bookAuthor, !author.isEmpty else { return title }
        return "\(title) · \(author)"
    }
}

/// The Lock Screen is monochrome and vibrant: colour is not available, the type is small, and
/// three lines is the honest budget. So the passage arrives without its mark and without its
/// byline — what fits is the sentence, and the sentence is the point.
private struct LockScreenPassage: View {
    let passage: DailyQuoteSnapshot.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(passage.text)
                .font(.system(size: 13, design: .serif))
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            if let title = passage.bookTitle, !title.isEmpty {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EmptyPassage: View {
    let isBeyondSnapshot: Bool
    let family: WidgetFamily

    private var line: String {
        isBeyondSnapshot ? "Open diple to turn the page." : "Passages you save will appear here."
    }

    var body: some View {
        if family == .accessoryRectangular {
            Text(line)
                .font(.system(size: 12))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 18, weight: .thin))
                    .foregroundStyle(.tertiary)
                Text(line)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Colour

private extension Color {
    /// Six bytes, read the same way the app reads them.
    ///
    /// Deliberately a second, tiny parser rather than a share of `Color+Theme`: that file is
    /// part of a theme layer that reaches into app settings and the reader's page themes, none
    /// of which an extension may pull in for one swatch. Nothing about `#RRGGBB` drifts.
    init(widgetHex hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = .secondary
            return
        }
        self = Color(
            .sRGB,
            red: Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8) / 255,
            blue: Double(value & 0x0000FF) / 255
        )
    }
}

private extension DailyQuoteSnapshot.Entry {
    /// What the gallery shows before a real snapshot is available.
    static var placeholder: Self {
        Self(
            day: DailyQuoteDay.key(for: Date()),
            quoteID: "placeholder",
            text: "You cannot buy the revolution. You cannot make the revolution. You can only be the revolution.",
            bookTitle: "The Dispossessed",
            bookAuthor: "Ursula K. Le Guin",
            colorHex: "#FFD60A"
        )
    }
}
