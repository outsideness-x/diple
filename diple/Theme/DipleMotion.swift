import SwiftUI

/// Motion, as physics rather than timing curves.
///
/// A duration-and-curve animation always takes the same time regardless of how far it has to
/// travel, which is why `easeInOut` feels administrative: nothing in the world moves that way.
/// A spring carries the distance in its own maths, so a small change settles quickly and a
/// large one takes the time it needs, and an interrupted one continues from where it actually
/// is rather than snapping to where it was headed.
///
/// Three springs, chosen by what is moving — not by how long the author wanted it to take.
/// A screen with five different response values reads as five different pieces of software.
public enum DipleMotion {
    /// A finger is already on the glass: press states, scrub handles, anything reacting to
    /// contact. Fast and tight, because the reader is watching their own touch.
    public static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.8)

    /// The default. A state the reader asked for changing on screen: a toggle, a value, a
    /// selection, a bar redrawing.
    public static let standard = Animation.spring(response: 0.35, dampingFraction: 0.78)

    /// Something entering, leaving, or crossing the screen. Slower and softer, with just
    /// enough damping to stop short of a visible bounce.
    public static let gentle = Animation.spring(response: 0.5, dampingFraction: 0.85)
}
