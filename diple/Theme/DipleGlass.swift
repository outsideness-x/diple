import SwiftUI

/// The glass the app's floating chrome is made of.
///
/// Since iOS 26 the system draws its own: Liquid Glass, which bends what is behind it, catches
/// light along its rim and answers a touch. diple already showed it in every sheet's Done button
/// and every context menu, while its own floating chrome — the tab bar, the reader's bars, the
/// highlight bar, the toasts — was the *shape* of that glass assembled from the frosted materials
/// iOS has had since 15: a blur, a tint, a hairline and a drop shadow. Beside the real thing the
/// copy read as a copy, which is the one impression a publisher's app cannot afford.
///
/// So on 26 those surfaces are the system's glass and carry **no shadow of their own** — the
/// glass has its depth built in, and a blur under it would be a second, older answer to the same
/// question. The frosted recipe stays exactly as it was for iOS 18–25 (the deployment target is
/// 18.0): every call site keeps its own fallback rather than sharing one, so nothing an older
/// system draws changes by a pixel.
public enum DipleGlass {
    /// A surface controls stand on: the reader's bars, a toast, the highlight bar.
    case regular
    /// A surface that is itself what the finger presses — the tab bar, a single glass button.
    /// It swells and lights under the touch the way the system's own controls do.
    case interactive

    @available(iOS 26.0, *)
    var system: Glass {
        switch self {
        case .regular: return .regular
        case .interactive: return .regular.interactive()
        }
    }
}

public extension View {
    /// Sets this view on system glass in `shape` where the system has glass, and applies
    /// `fallback` — the recipe the call site drew before — where it does not.
    @ViewBuilder
    func dipleGlass<S: Shape, Fallback: ViewModifier>(
        _ glass: DipleGlass = .regular,
        in shape: S,
        fallback: Fallback
    ) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(glass.system, in: shape)
        } else {
            modifier(fallback)
        }
    }

    /// Renders several glass surfaces as one group: they sample what is behind them together
    /// and can morph into one another as the layout changes, which separate surfaces cannot.
    ///
    /// `spacing` is the distance at which two surfaces start to melt together. Every group in
    /// the app passes less than the gap its surfaces actually stand apart by, so at rest they
    /// stay separate objects and only ever flow into each other mid-animation.
    @ViewBuilder
    func dipleGlassGroup(spacing: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    /// A bar of actions along the bottom of a screen — the selection bars of the shelf and the
    /// board, the filing pass.
    ///
    /// On 26 it floats: a glass capsule inset from the edges, like the system's own bottom
    /// toolbars, rather than a plate fastened across the screen. Before 26 it is the full-width
    /// material band it always was.
    func dipleBottomBar() -> some View {
        modifier(DipleBottomBarSurface())
    }
}

private struct DipleBottomBarSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .padding(.horizontal, DipleSpace.l)
                .padding(.vertical, DipleSpace.s)
                .glassEffect(.regular, in: Capsule(style: .continuous))
                .padding(.horizontal, DipleSpace.l)
                .padding(.bottom, DipleSpace.s)
        } else {
            content
                .padding(.horizontal, DipleSpace.xl)
                .padding(.vertical, DipleSpace.m)
                .background(.ultraThinMaterial)
        }
    }
}
