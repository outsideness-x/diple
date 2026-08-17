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
