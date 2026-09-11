import SwiftUI

/// Every word the notes are filed under, A–Z, with how many notes carry it.
///
/// An index, not a place of its own: tapping a word opens the All notes board with that one chip
/// pressed, which is everything a page for a single tag would have been — the doctrine recorded
/// when the board was unified. Renaming stays where it already lives, in the chip's menu.
struct NotesTagsView: View {
    @ObservedObject var model: NotesWorkshopModel
    let open: (NotesPlace) -> Void

    private var tags: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in model.items {
            for tag in item.tags { counts[tag, default: 0] += 1 }
        }
        return counts
            .map { (tag: $0.key, count: $0.value) }
            .sorted { $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
    }

    var body: some View {
        let tags = self.tags
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                DipleMasthead(
                    title: "Tags",
                    strapline: tags.isEmpty ? nil : (tags.count == 1 ? "1 tag" : "\(tags.count) tags")
                ) {
                    EmptyView()
                }
                .padding(.bottom, DipleSpace.l)

                if tags.isEmpty {
                    Text("A note's tags are set under its title. Every word used on a note is listed here.")
                        .dipleType(.callout)
                        .foregroundStyle(DipleColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(tags, id: \.tag) { entry in
                    Button {
                        HapticManager.shared.selection()
                        open(.tag(entry.tag))
                    } label: {
                        HStack(spacing: DipleSpace.m) {
                            Text("#\(entry.tag)")
                                .dipleType(.body)
                                .foregroundStyle(DipleColor.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: DipleSpace.s)
                            Text("\(entry.count)")
                                .dipleType(.footnote, weight: .regular)
                                .monospacedDigit()
                                .foregroundStyle(DipleColor.textTertiary)
                        }
                        .frame(minHeight: 44)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(DipleColor.hairline)
                                .frame(height: DipleStroke.hairline)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.bookCard)
                }
            }
            .padding(.horizontal, DipleSpace.xl)
            .padding(.bottom, DipleSpace.scrollBottom)
        }
        .background(DipleColor.canvas.ignoresSafeArea())
        .tracksTabBarCollapse()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DipleColor.canvas, for: .navigationBar)
    }
}
