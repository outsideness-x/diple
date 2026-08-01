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

/// Light rather than paint.
///
/// A saturated fill shouts; a glow points. Used behind interactive elements and under the
/// accent so the eye is led to them instead of being flagged down.
public struct CraftGlow: ViewModifier {
    let color: Color
    let radius: CGFloat

    public func body(content: Content) -> some View {
        content
            .background(
                color
                    .blur(radius: radius)
                    .opacity(0.55)
                    .allowsHitTesting(false)
            )
    }
}

public extension View {
    /// A card: surface, carved edge, nothing beneath it.
    func craftSurface(_ fill: Color = DipleColor.surface, radius: CGFloat = DipleRadius.m) -> some View {
        modifier(CraftSurface(fill: fill, radius: radius))
    }

    /// A soft halo of the given colour, for elements that should draw the eye.
    func craftGlow(_ color: Color = DipleColor.accentGlow, radius: CGFloat = 12) -> some View {
        modifier(CraftGlow(color: color, radius: radius))
    }
}

/// The wash behind an empty state.
///
/// A flat disc of tinted accent reads as a placeholder shape. A radial falloff reads as light
/// coming from somewhere, which is what gives an otherwise bare screen a sense of depth.
public struct AccentWash: View {
    public var diameter: CGFloat = 220

    public init(diameter: CGFloat = 220) {
        self.diameter = diameter
    }

    public var body: some View {
        RadialGradient(
            colors: [DipleColor.accent.opacity(0.16), DipleColor.accent.opacity(0)],
            center: .center,
            startRadius: 0,
            endRadius: diameter / 2
        )
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
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

        Text("Glowing")
            .dipleType(.body, weight: .semibold)
            .foregroundStyle(DipleColor.textOnAccent)
            .diplePadding(.buttonLarge)
            .background(DipleColor.accent, in: Capsule())
            .craftGlow()
    }
    .padding(DipleSpace.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DipleColor.canvas)
    .preferredColorScheme(.dark)
}
