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
struct DipleRubric<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    let count: (Option) -> Int
    /// The accessibility identifier of one place, for the UI tests.
    let identifier: (Option) -> String

    var body: some View {
        HStack(alignment: .bottom, spacing: DipleSpace.xl) {
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
                    .dipleType(.headline, weight: isSelected ? .semibold : .regular)

                if figure > 0 {
                    Text("\(figure)")
                        .dipleType(.tag)
                        .monospacedDigit()
                        .baselineOffset(7)
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
