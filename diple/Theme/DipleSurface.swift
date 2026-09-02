import SwiftUI

/// Depth without drop shadows.
///
/// A card is separated from the canvas by an edge, not by a blur beneath it. The edge is a
/// single hairline that is brighter along the top and fades towards the bottom — the light a
/// bevel would catch if the card were a physical thing. One gradient stroke does the work of
/// the border-plus-inner-highlight pair, and does it without a second layer to keep in sync.
public struct CraftSurface: ViewModifier {
    let fill: Color
    let radius: CGFloat

    public func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [DipleColor.insetHighlight, DipleColor.hairline],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: DipleStroke.hairline
                    )
            )
    }
}

public extension View {
    /// A card: surface, carved edge, nothing beneath it.
    func craftSurface(_ fill: Color = DipleColor.surface, radius: CGFloat = DipleRadius.m) -> some View {
        modifier(CraftSurface(fill: fill, radius: radius))
    }

    /// Marks an option as the chosen one. The only way the app says "this one".
    ///
    /// A ring, never a flood of accent. Every chosen state used to be a saturated fill, and on
    /// a screen with more than one such control the result was several equally loud objects and
    /// no main one: Settings showed a filled appearance segment, a ringed accent swatch, a
    /// filled haptic segment and two accent switches at once, none of which is that screen's
    /// action. The accent is the loudest thing the app owns, so it is spent on the *action* —
    /// one per screen — and a chosen filter, typeface or segment is a state, not an action.
    ///
    /// The ring also survives what a fill cannot. A filled swatch has to overprint its own
    /// label, which is why the reader's typeface buttons stopped being specimens of the face
    /// they select the moment one was picked; an outline leaves whatever is inside it alone.
    ///
    /// `resting` is the fill when nothing is chosen — usually `surfaceOverlay`, but a control
    /// already sitting on a raised surface passes its own.
    func dipleSelected<S: InsettableShape>(
        _ isSelected: Bool,
        in shape: S,
        resting: Color = DipleColor.surfaceOverlay
    ) -> some View {
        background(isSelected ? DipleColor.accentSoft : resting, in: shape)
            .overlay {
                shape.strokeBorder(
                    isSelected ? DipleColor.accent : Color.clear,
                    lineWidth: DipleStroke.selection
                )
            }
    }
}

#Preview("Surfaces") {
    VStack(spacing: DipleSpace.xl) {
        Text("Card on canvas")
            .dipleType(.body)
            .foregroundStyle(DipleColor.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DipleSpace.m)
            .craftSurface()

        Text("Raised")
            .dipleType(.body)
            .foregroundStyle(DipleColor.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DipleSpace.m)
            .craftSurface(DipleColor.surfaceRaised)
    }
    .padding(DipleSpace.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DipleColor.canvas)
    .preferredColorScheme(.dark)
}
