import SwiftUI

/// What was read, and when — every sitting, a day to a line.
///
/// **A ledger, not a scoreboard.** There is no streak, no goal, no badge and no comparison with
/// last week, and their absence is the design rather than a stage it has not reached yet: this
/// app already removed a memory-scoring layer once (migration v13) because rating a reader is
/// not what a reading app is for. What is left is the thing a diary is for — being able to look
/// back and see that you read in the evenings, and that you spent October inside one book.
///
/// Since 2026-11-09 this is the **Journal**, one page in from `ReadingStatisticsView`: the year
/// at a glance moved there, together with the hours-of-the-day strip and the summary that used
/// to head this page, and what stays here is the ledger they are drawn from.
///
/// Every figure is measured rather than clocked. `ReadingSession` records the reason.
struct ReadingLogView: View {
    @State private var log = ReadingLog.make(from: [], titles: [:])
    @State private var hasLoaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DipleSpace.xxxl) {
                if log.isEmpty {
                    empty
                } else {
                    ledger
                }
            }
            .padding(.horizontal, DipleSpace.xl)
            .padding(.top, DipleSpace.l)
            .padding(.bottom, DipleSpace.scrollBottom)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DipleColor.canvas.ignoresSafeArea())
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DipleColor.canvas, for: .navigationBar)
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            load()
        }
    }

    /// One read of the table and one of the shelf, grouped in memory. A year of sittings is a
    /// few hundred rows of six columns; the alternative is a query per month and another per
    /// day, run while the screen is being laid out.
    private func load() {
        let sessions = (try? AppDatabase.shared.fetchReadingSessions()) ?? []
        let books = (try? AppDatabase.shared.fetchAllBooks()) ?? []
        // A deleted source is printed under the title the log kept for it; a book on the shelf
        // under its own, which may have been edited since.
        let remembered = (try? AppDatabase.shared.fetchReadingLogSources()) ?? []
        var titles = Dictionary(remembered.map { ($0.bookId, $0.title) }, uniquingKeysWith: { first, _ in first })
        for book in books { titles[book.id] = book.title }
        log = ReadingLog.make(from: sessions, titles: titles)
    }

    // MARK: - The ledger

    private var ledger: some View {
        VStack(alignment: .leading, spacing: DipleSpace.xxl) {
            ForEach(log.months) { month in
                VStack(alignment: .leading, spacing: DipleSpace.m) {
                    sectionHeading(monthTitle(month.date))

                    Text(monthLine(month))
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
                        .monospacedDigit()

                    ForEach(month.days) { day in
                        dayRow(day)
                    }
                }
            }
        }
    }

    private func dayRow(_ day: ReadingLog.Day) -> some View {
        VStack(alignment: .leading, spacing: DipleSpace.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayTitle(day.date))
                    .dipleType(.body, weight: .medium)
                    .foregroundStyle(DipleColor.textPrimary)

                Spacer(minLength: DipleSpace.m)

                Text(ReadingEstimate.format(minutes: day.minutes))
                    .dipleType(.footnote, weight: .regular)
                    .foregroundStyle(DipleColor.textSecondary)
                    .monospacedDigit()
            }

            ForEach(day.entries) { entry in
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.title)
                        .dipleType(.editorialItem)
                        .foregroundStyle(DipleColor.textSecondary)
                        .lineLimit(2)

                    if let trailing = entryTrailing(entry, in: day) {
                        Spacer(minLength: DipleSpace.m)

                        Text(trailing)
                            .dipleType(.caption)
                            .foregroundStyle(DipleColor.textQuaternary)
                            .monospacedDigit()
                            .layoutPriority(1)
                    }
                }
            }
        }
        .padding(.vertical, DipleSpace.m)
        // A rule closes the entry, as it does everywhere else in this app.
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DipleColor.separator)
                .frame(height: DipleStroke.hairline)
        }
    }

    /// What is printed after a title, which is only ever what the line above has not said.
    ///
    /// A day with one book already carries that book's minutes on the day line, and printing
    /// them again under it is the same tautology the shelf removed when it stopped setting a
    /// percentage beside a bar already filled to it. The number of times a book was picked up
    /// is new either way.
    private func entryTrailing(_ entry: ReadingLog.Entry, in day: ReadingLog.Day) -> String? {
        let repeats = entry.sittings > 1 ? "\(entry.sittings)×" : nil

        guard day.entries.count > 1 else { return repeats }

        let duration = ReadingEstimate.format(minutes: entry.minutes)
        guard let repeats else { return duration }
        return "\(duration) · \(repeats)"
    }

    private func monthTitle(_ date: Date) -> String {
        let isThisYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        return date.formatted(isThisYear ? .dateTime.month(.wide) : .dateTime.month(.wide).year())
    }

    private func monthLine(_ month: ReadingLog.Month) -> String {
        let sittings = month.sittingCount == 1 ? "1 sitting" : "\(month.sittingCount) sittings"
        let books = month.bookCount == 1 ? "1 source" : "\(month.bookCount) sources"
        return "\(ReadingEstimate.format(minutes: month.minutes)) · \(sittings) · \(books)"
    }

    private func dayTitle(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .dipleSectionHeading()
    }

    /// The log begins the day it begins: nothing before it was recorded, and inventing a
    /// history from reading positions would be a chart of guesses.
    private var empty: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            Text("Nothing written down yet")
                .dipleType(.editorialTitle)
                .foregroundStyle(DipleColor.textPrimary)

            Text("Sittings are recorded as you read. A page or two is enough for one to count; a book left open on the table is not reading and is not written down.")
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, DipleSpace.xxxl)
    }
}
