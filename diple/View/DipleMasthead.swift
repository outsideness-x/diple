import SwiftUI

/// The head of a place. One component for Home, the library and the board.
///
/// The three roots used to open three different ways: Home drew its own masthead with the bar
/// hidden, the library put the **wordmark** in a system navigation bar, and the board put its
/// name there with a floating accent label underneath. Moving between them read as moving
/// between applications, and the library's arrangement was the exact fault the comment on
/// Home's masthead complains about — a wordmark shrunk to the size of a back button. It also
/// said nothing: the reader knows they are in diple, what they do not know is which room.
///
/// So the wordmark is printed once, on the front page, the way a publication prints its name on
/// page one and not in the running head of every screen. The other two print their own name.
///
/// The system bar stays *hidden* rather than styled. `navigationTitle` is still set by each
/// screen, because that is what labels the back button of anything pushed from it — the same
/// arrangement Home has used since its masthead was built.
public struct DipleMasthead<Trailing: View>: View {
    /// What this place is called.
    let title: String
    /// The line under the name: the date on Home, a count elsewhere. `nil` prints nothing and
    /// reserves no height — an empty `Text` is not nothing, it is a blank line.
    let strapline: String?
    /// Whether this is the wordmark. Only Home passes `true`, and it is what selects the
    /// editorial face; every other place is a label, not a masthead.
    let isWordmark: Bool
    @ViewBuilder let trailing: () -> Trailing

    public init(
        title: String,
        strapline: String? = nil,
        isWordmark: Bool = false,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.strapline = strapline
        self.isWordmark = isWordmark
        self.trailing = trailing
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                Text(title)
                    .dipleType(isWordmark ? .wordmark : .hero)
                    .foregroundStyle(DipleColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let strapline {
                    Text(strapline)
                        .dipleType(.footnote, weight: .regular)
                        .foregroundStyle(DipleColor.textTertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DipleSpace.m)

            HStack(spacing: DipleSpace.s) {
                trailing()
            }
        }
        // Vertical only. The head sits at whatever gutter its container already establishes —
        // on Home that is the padded column the lead and the rows share, and a second inset
        // here would step the left edge of the page in and back out again for no reason the
        // reader can see. Callers that place it outside such a column add the gutter.
        .padding(.top, DipleSpace.l)
        .accessibilityElement(children: .contain)
    }
}

/// A control in a masthead: a glyph in a 44 pt target, in the quiet ink the rest of the head
/// uses. The accent is not spent here — a masthead action is a way in, not the screen's action.
public struct MastheadButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    public init(systemImage: String, label: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button {
            HapticManager.shared.selection()
            action()
        } label: {
            Image(systemName: systemImage)
                .dipleIcon(16)
                .foregroundStyle(DipleColor.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.readerControl)
        .accessibilityLabel(label)
    }
}

/// The same glyph and target as `MastheadButton`, for the cases where the control opens a menu
/// or pushes rather than running a closure. A `Menu` cannot be built from a `Button`, and a
/// `NavigationLink` is not one either, so the *look* is what is shared.
public struct MastheadGlyph: View {
    let systemImage: String

    public init(systemImage: String) {
        self.systemImage = systemImage
    }

    public var body: some View {
        Image(systemName: systemImage)
            .dipleIcon(16)
            .foregroundStyle(DipleColor.textSecondary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

#Preview("Mastheads") {
    VStack(alignment: .leading, spacing: DipleSpace.xxxl) {
        DipleMasthead(
            title: "diple.",
            strapline: "Wednesday, 2 September",
            isWordmark: true
        ) {
            MastheadGlyph(systemImage: "plus")
            MastheadGlyph(systemImage: "gearshape")
        }

        DipleMasthead(title: "Library", strapline: "12 sources · 3 unread") {
            MastheadGlyph(systemImage: "plus")
            MastheadGlyph(systemImage: "gearshape")
        }

        DipleMasthead(title: "Notes", strapline: "48 notes") {
            MastheadGlyph(systemImage: "arrow.up.arrow.down")
            MastheadGlyph(systemImage: "plus")
        }

        Spacer()
    }
    .padding(.horizontal, DipleSpace.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(DipleColor.canvas)
}
