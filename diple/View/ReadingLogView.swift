import SwiftUI

/// What was read, and when.
///
/// **A ledger, not a scoreboard.** There is no streak, no goal, no badge and no comparison with
/// last week, and their absence is the design rather than a stage it has not reached yet: this
/// app already removed a memory-scoring layer once (migration v13) because rating a reader is
/// not what a reading app is for. What is left is the thing a diary is for — being able to look
/// back and see that you read in the evenings, and that you spent October inside one book.
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
                    summary
                    hours
                    ledger
                }
            }
            .padding(.horizontal, DipleSpace.xl)
            .padding(.top, DipleSpace.l)
            .padding(.bottom, DipleSpace.scrollBottom)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DipleColor.canvas)
        .navigationTitle("Reading log")
        .navigationBarTitleDisplayMode(.inline)
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
        let titles = Dictionary(books.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        log = ReadingLog.make(from: sessions, titles: titles)
    }

    // MARK: - The head of the page

    private var summary: some View {
        VStack(alignment: .leading, spacing: DipleSpace.xs) {
            Text(ReadingEstimate.format(minutes: log.totalMinutes))
                .dipleType(.hero)
                .foregroundStyle(DipleColor.textPrimary)
                .monospacedDigit()

            Text(summaryLine)
                .dipleType(.footnote, weight: .regular)
                .foregroundStyle(DipleColor.textTertiary)
                .monospacedDigit()
        }
    }

    private var summaryLine: String {
        let sittings = log.sittingCount == 1 ? "1 sitting" : "\(log.sittingCount) sittings"
        let books = log.bookCount == 1 ? "1 source" : "\(log.bookCount) sources"
        return "\(sittings) · \(books)"
    }

    /// When the reader sits down, drawn rather than written — the same choice the resting
    /// progress line makes. Twenty-four bars is a shape you read in one glance and a table you
    /// would never read at all.
    @ViewBuilder
    private var hours: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            sectionHeading("WHEN YOU READ")

            let peak = log.hoursOfDay.max() ?? 0
            if peak > 0 {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0 ..< 24, id: \.self) { hour in
                        let share = log.hoursOfDay[hour] / peak
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            // The accent, filling to a measured share — the one role the budget
                            // allows it here, the same one the progress line spends it on.
                            .fill(share > 0 ? DipleColor.accent : DipleColor.separator)
                            .frame(height: max(2, 44 * share))
                    }
                }
                .frame(height: 44, alignment: .bottom)
                .accessibilityElement()
                .accessibilityLabel(hoursAccessibilityLabel)

                HStack {
                    hourTick("00")
                    Spacer()
                    hourTick("06")
                    Spacer()
                    hourTick("12")
                    Spacer()
                    hourTick("18")
                    Spacer()
                    hourTick("24")
                }

                if let settled = log.settledHour {
                    Text("Most often around \(hourLabel(settled)).")
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
                        .padding(.top, DipleSpace.xs)
                }
            }
        }
    }

    private func hourTick(_ text: String) -> some View {
        Text(text)
            .dipleType(.nano)
            .foregroundStyle(DipleColor.textQuaternary)
            .monospacedDigit()
    }

    private func hourLabel(_ hour: Int) -> String {
        let components = DateComponents(hour: hour)
        guard let date = Calendar.current.date(from: components) else { return "\(hour)" }
        return date.formatted(.dateTime.hour())
    }

    private var hoursAccessibilityLabel: String {
        guard let settled = log.settledHour else { return "When you read" }
        return "When you read. Most often around \(hourLabel(settled))."
    }

    // MARK: - The ledger

    private var ledger: some View {
        VStack(alignment: .leading, spacing: DipleSpace.xxl) {
            ForEach(log.months) { month in
                VStack(alignment: .leading, spacing: DipleSpace.m) {
                    sectionHeading(monthTitle(month.date).uppercased())

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
                        .dipleType(.callout)
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
            .dipleType(.nano, weight: .semibold)
            .tracking(1.2)
            .foregroundStyle(DipleColor.textQuaternary)
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
