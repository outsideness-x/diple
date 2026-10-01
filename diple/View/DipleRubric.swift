import SwiftUI

/// The places inside a room, set as a rubric rather than as a control.
///
/// It was a system `Picker(.segmented)` on the shelf — the only piece of stock UIKit on the
/// screen, and it read as one: a settings widget where the page wanted a section head. A
/// section is announced in type. The current place is set at full strength with a rule under
/// it, the ones you might go to are dimmed, and nothing is boxed.
///
/// Two rooms use it: the library's queue (Inbox, Later, Archive) and Highlights (Passages,
/// Notes). One component, so the two cannot drift into two ways of saying "you are here".
///
/// The count rides as a superior figure rather than in the label, because "Inbox 2" reads as a
/// name containing a number and `Inbox²` reads as a name with a count attached. A place with
/// nothing in it prints no figure: the name already says it is empty once it is opened.
///
/// A third user since 2026-10-01: the reader's contents sheet (Contents, Highlights, Notes,
/// Bookmarks), which was the last system segmented control in the app. Four places do not fit a
/// phone at the size a room's two or three do, so a sheet sets them a size down
/// (`Size.sheet`); and when even that does not fit — the largest Dynamic Type sizes, a narrow
/// window — the row scrolls sideways rather than wrapping or truncating a place's name.
struct DipleRubric<Option: Hashable>: View {
    /// How large the places are set: a room's own, or a size down for a sheet holding four.
    enum Size {
        case room
        case sheet
    }

    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    let count: (Option) -> Int
    /// The accessibility identifier of one place, for the UI tests.
    let identifier: (Option) -> String
    var size: Size = .room

    var body: some View {
        ViewThatFits(in: .horizontal) {
            places
            ScrollView(.horizontal) { places }
                .scrollIndicators(.hidden)
        }
    }

    private var places: some View {
        HStack(alignment: .bottom, spacing: size == .room ? DipleSpace.xl : DipleSpace.l) {
            ForEach(options, id: \.self) { option in
                segment(option)
            }
            Spacer(minLength: 0)
        }
    }

    private func segment(_ option: Option) -> some View {
        let isSelected = selection == option
        let name = title(option)
        let figure = count(option)
        return Button {
            guard !isSelected else { return }
            HapticManager.shared.selection()
            withAnimation(DipleMotion.standard) { selection = option }
        } label: {
            HStack(alignment: .top, spacing: DipleSpace.hair) {
                Text(name)
                    .dipleType(size == .room ? .headline : .callout, weight: isSelected ? .semibold : .regular)
                    .lineLimit(1)

                if figure > 0 {
                    Text("\(figure)")
                        .dipleType(.tag)
                        .monospacedDigit()
                        .baselineOffset(size == .room ? 7 : 5)
                }
            }
            .foregroundStyle(isSelected ? DipleColor.textPrimary : DipleColor.textQuaternary)
            .padding(.bottom, DipleSpace.s)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isSelected ? DipleColor.accentInk : Color.clear)
                    .frame(height: DipleStroke.selection)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.readerControl)
        .accessibilityLabel(figure > 0 ? "\(name), \(figure)" : name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(identifier(option))
    }
}

public extension View {
    /// A section's heading on a page of content — "Recently opened", "Highlights", a month.
    ///
    /// Sentence case at 14 semibold, not tracked capitals at 11 (2026-09-30). Spaced-out caps
    /// down a page of books read as the labels of a form; a reading app's pages are not forms.
    /// Capitals stay where the page *is* a form — Settings, the editors' field labels, review
    /// sheets — and a heading here is a phrase, so it is set as one.
    ///
    /// Callers pass the words in sentence case; nothing here changes the case of what it is
    /// given, so a title with a proper noun in it keeps its capital.
    func dipleSectionHeading() -> some View {
        dipleType(.callout, weight: .semibold)
            .foregroundStyle(DipleColor.textTertiary)
    }
}
