import SwiftUI
import WidgetKit

/// The notes workshop on the Home Screen and the Lock Screen: today's page, the Inbox, and a new
/// note one tap away.
///
/// Like the passage widget it only reads — `NotesSnapshot`, written by the app — and every tap
/// is a `diple://` address the app already routes, the same ways in the Home Screen quick actions
/// and Control Center use. Monochrome, as the Desk is: the widget sits among other apps' colours,
/// and a notes page that shouted would be the wrong kind of loud.
struct NotesWidget: Widget {
    static let kind = "diple.Notes"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NotesProvider()) { entry in
            NotesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Notes")
        .description("Today’s page, the Inbox, and a new note a tap away.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

enum NotesAddress {
    static let newNote = address("new-note")
    static let today = address("today")
    static let inbox = address("inbox")

    private static func address(_ host: String) -> URL? {
        var components = URLComponents()
        components.scheme = "diple"
        components.host = host
        return components.url
    }
}

struct NotesEntry: TimelineEntry {
    let date: Date
    let snapshot: NotesSnapshot?

    /// Today's page only while it is still today: a snapshot written last night does not describe
    /// this morning, and at midnight the widget turns to an empty page by itself.
    var today: NotesSnapshot.Today? { snapshot?.today(on: date) }
}

struct NotesProvider: TimelineProvider {
    func placeholder(in context: Context) -> NotesEntry {
        NotesEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (NotesEntry) -> Void) {
        completion(NotesEntry(date: Date(), snapshot: context.isPreview ? .placeholder : load()))
    }

    /// Now, and the midnight after it — the one change the widget can make without the app.
    func getTimeline(in context: Context, completion: @escaping (Timeline<NotesEntry>) -> Void) {
        let snapshot = load()
        let now = Date()
        let midnight = DailyQuoteDay.startOfNextDay(after: now)
        completion(Timeline(
            entries: [NotesEntry(date: now, snapshot: snapshot), NotesEntry(date: midnight, snapshot: snapshot)],
            policy: .after(midnight)
        ))
    }

    private func load() -> NotesSnapshot? {
        (try? NotesSnapshotStore.shared())?.read()
    }
}

// MARK: - Views

struct NotesWidgetView: View {
    let entry: NotesEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 20, weight: .medium))
            }
            .widgetURL(NotesAddress.newNote)
            .accessibilityLabel("New note")

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Today")
                    .font(.system(size: 13, weight: .semibold))
                Text(entry.today?.preview ?? "Nothing written yet")
                    .font(.system(size: 12))
                    .foregroundStyle(entry.today == nil ? .secondary : .primary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(NotesAddress.today)

        case .systemMedium:
            MediumNotes(entry: entry)

        default:
            SmallNotes(entry: entry)
                .widgetURL(NotesAddress.today)
        }
    }
}

/// The day's first lines under the day's name. A small widget has one place to tap, and it is
/// today's page; the Inbox count rides along at the foot because it is the other thing the Desk
/// would tell someone glancing at it.
private struct SmallNotes: View {
    let entry: NotesEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DayLabel(date: entry.date)
            TodayLines(today: entry.today, lineLimit: 4)
            Spacer(minLength: 0)
            if let inbox = entry.snapshot?.inboxCount, inbox > 0 {
                Text(inbox == 1 ? "1 in Inbox" : "\(inbox) in Inbox")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Today's page on the left; the Inbox, the open tasks and a new note on the right — three taps
/// that each go where they say.
private struct MediumNotes: View {
    let entry: NotesEntry

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AddressLink(NotesAddress.today) {
                VStack(alignment: .leading, spacing: 6) {
                    DayLabel(date: entry.date)
                    TodayLines(today: entry.today, lineLimit: 5)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            Rectangle()
                .fill(.quaternary)
                .frame(width: 0.5)

            VStack(alignment: .leading, spacing: 10) {
                AddressLink(NotesAddress.inbox) {
                    Count(label: "Inbox", value: entry.snapshot?.inboxCount ?? 0)
                }
                Count(label: "Tasks", value: entry.snapshot?.openTaskCount ?? 0)
                Spacer(minLength: 0)
                AddressLink(NotesAddress.newNote) {
                    Label("New note", systemImage: "square.and.pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.fill.secondary, in: Capsule())
                }
            }
            .frame(width: 104, alignment: .leading)
        }
    }
}

/// A `Link` when there is an address, and the content alone when there is not. The addresses are
/// built from constant parts and are never absent; this is what lets them stay optional without a
/// force unwrap, and without a stand-in address that would open something else.
private struct AddressLink<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: () -> Content

    init(_ url: URL?, @ViewBuilder content: @escaping () -> Content) {
        self.url = url
        self.content = content
    }

    var body: some View {
        if let url {
            Link(destination: url, label: content)
        } else {
            content()
        }
    }
}

private struct DayLabel: View {
    let date: Date

    var body: some View {
        Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.4)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

private struct TodayLines: View {
    let today: NotesSnapshot.Today?
    let lineLimit: Int

    var body: some View {
        if let today, !today.preview.isEmpty {
            Text(today.preview)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineSpacing(1)
                .lineLimit(lineLimit)
        } else {
            Text("Nothing written today.")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct Count: View {
    let label: String
    let value: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value, format: .number)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(value == 0 ? .tertiary : .primary)
        }
    }
}

private extension NotesSnapshot {
    /// What the widget gallery shows before the app has written anything.
    static var placeholder: Self {
        Self(
            generatedAt: Date(),
            inboxCount: 3,
            openTaskCount: 2,
            today: Today(
                day: DailyQuoteDay.key(for: Date()),
                title: "Today",
                preview: "Read two chapters before the train.\nA margin is a conversation the book cannot hear."
            )
        )
    }
}
