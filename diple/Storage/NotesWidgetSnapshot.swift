import Foundation
import WidgetKit

/// Writes what the notes widget shows and asks WidgetKit to redraw it.
///
/// Written on activation, when the app leaves the screen — which is when a session's writing is
/// over — and after anything arrives from outside it (Add to Today, the share sheet, iCloud). A
/// widget one change behind is a widget; blocking the app to keep it level is the worse trade, so
/// the write happens off the main actor and failures are silent.
enum NotesWidgetSnapshot {
    static let widgetKind = "diple.Notes"

    /// How much of today's page the widget is given: enough for the medium family's lines, few
    /// enough bytes that the snapshot stays a snapshot.
    private static let previewCharacters = 220

    static func refresh(now: Date = Date()) {
        Task.detached(priority: .utility) {
            write(now: now)
        }
    }

    nonisolated static func write(now: Date) {
        guard AppDatabase.startupFailure == nil,
              let store = try? NotesSnapshotStore.shared(),
              let notes = try? AppDatabase.shared.fetchAllNotes(),
              let spaces = try? AppDatabase.shared.fetchSpaces()
        else { return }

        let items = notes.map { NoteItem(note: $0, tags: [], book: nil) }
        try? store.write(make(items: items, spaces: spaces, now: now))
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    /// Pure, so the widget's numbers and the Desk's are held equal by a test rather than by hope.
    nonisolated static func make(
        items: [NoteItem],
        spaces: [NoteSpace],
        now: Date,
        calendar: Calendar = .current
    ) -> NotesSnapshot {
        let key = Note.dailyKey(for: now, calendar: calendar)
        let today = NotesDesk.dailyPage(for: key, in: items).map { page in
            NotesSnapshot.Today(
                day: DailyQuoteDay.key(for: now, timeZone: calendar.timeZone),
                title: page.note.title ?? Note.dailyTitle(forKey: key, calendar: calendar),
                preview: preview(of: page.note.body)
            )
        }
        return NotesSnapshot(
            generatedAt: now,
            inboxCount: NotesDesk.inbox(items, spaces: spaces).count,
            openTaskCount: NotesDesk.openTaskCount(items),
            today: today
        )
    }

    /// The page's prose, line by line, without Markdown's punctuation — a widget shows words.
    nonisolated static func preview(of body: String) -> String {
        let lines = body
            .split(whereSeparator: \.isNewline)
            .map { NoteMarkdown.plainText(String($0)).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var preview = ""
        for line in lines {
            let candidate = preview.isEmpty ? line : preview + "\n" + line
            guard candidate.count <= previewCharacters else {
                if preview.isEmpty { preview = String(line.prefix(previewCharacters - 1)) + "…" }
                break
            }
            preview = candidate
        }
        return preview
    }
}
