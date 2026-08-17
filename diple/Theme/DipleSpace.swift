import SwiftUI

/// The 4-point grid.
///
/// Every padding, gap and inset in the app comes from this scale. The value of a grid is
/// entirely in it having no exceptions — a single `padding(14)` between two `padding(12)`
/// cards is not visible on its own but breaks the optical rhythm of the column, which is
/// the thing that reads as "considered" rather than "assembled".
///
/// Deliberately not Dynamic Type-scaled: text grows, the frame around it does not. Scaling
/// both at once inflates a layout far past what the screen can hold.
public enum DipleSpace {
    /// 2 — the only sub-grid value, for optical nudges inside a control (never between them).
    public static let hair: CGFloat = 2
    /// 4 — label to its value, icon to its text.
    public static let xs: CGFloat = 4
    /// 8 — inside a card, between stacked lines of text.
    public static let s: CGFloat = 8
    /// 12 — card padding, gap between chips.
    public static let m: CGFloat = 12
    /// 16 — gap between cards, screen gutter on compact widths.
    public static let l: CGFloat = 16
    /// 20 — screen gutter.
    public static let xl: CGFloat = 20
    /// 24 — between groups inside a screen.
    public static let xxl: CGFloat = 24
    /// 32 — between sections.
    public static let xxxl: CGFloat = 32
    /// 40 — bottom inset of a scroll view, so the last row clears the tab bar.
    public static let scrollBottom: CGFloat = 40
}

/// Corner radii.
///
/// Radius tracks the size of the thing it rounds: a 6pt radius on a full-width sheet looks
/// sharp, a 24pt radius on a chip looks inflated. Picking by role keeps that proportional.
public enum DipleRadius {
    /// 4 — progress tracks, tiny indicators.
    public static let xs: CGFloat = 4
    /// 8 — book covers, thumbnails, inline controls.
    public static let s: CGFloat = 8
    /// 12 — cards and rows.
    public static let m: CGFloat = 12
    /// 16 — sheets and large panels.
    public static let l: CGFloat = 16
    /// 24 — full-screen containers.
    public static let xl: CGFloat = 24
}

/// Border widths. Depth is built from edges, not from drop shadows, so these are the
/// hairlines that do the work — sub-point on Retina, which is why 0.5 is the default.
public enum DipleStroke {
    /// 0.5 — the standard separating edge.
    public static let hairline: CGFloat = 0.5
    /// 1 — an edge that must survive over an unpredictable background (a book page).
    public static let regular: CGFloat = 1
    /// 2 — the spine mark at the leading edge of a catalogue row. Enough width to carry a hue
    /// at a glance, narrow enough to stay a mark rather than become a border.
    public static let spine: CGFloat = 2
    /// 2 — the reader's resting progress line. Thicker than a separator on purpose: it is not
    /// an edge between two surfaces but a mark that has to be legible at a glance, over paper,
    /// sepia or night, without becoming a bar.
    public static let progressLine: CGFloat = 2
}

/// Padding for interactive elements.
///
/// Horizontal always exceeds vertical. A control padded evenly looks squat and unbalanced;
/// the extra side room is what makes a button read as resting on the line of text rather
/// than sitting on top of it.
public enum DipleControlPadding {
    case chip
    case field
    case button
    case buttonLarge

    public var horizontal: CGFloat {
        switch self {
        case .chip: return 8
        case .field: return 12
        case .button: return 16
        case .buttonLarge: return 24
        }
    }

    public var vertical: CGFloat {
        switch self {
        case .chip: return 4
        case .field: return 8
        case .button: return 8
        case .buttonLarge: return 12
        }
    }
}

public extension View {
    /// Applies the asymmetric padding for a control role.
    func diplePadding(_ role: DipleControlPadding) -> some View {
        padding(.horizontal, role.horizontal)
            .padding(.vertical, role.vertical)
    }
}

private struct DipleSpaceSpecimen: View {
    private let steps: [(String, CGFloat)] = [
        ("hair", DipleSpace.hair), ("xs", DipleSpace.xs), ("s", DipleSpace.s),
        ("m", DipleSpace.m), ("l", DipleSpace.l), ("xl", DipleSpace.xl),
        ("xxl", DipleSpace.xxl), ("xxxl", DipleSpace.xxxl)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            ForEach(steps, id: \.0) { step in
                HStack(spacing: DipleSpace.m) {
                    Text(step.0)
                        .dipleType(.micro)
                        .foregroundStyle(DipleColor.textTertiary)
                        .frame(width: 44, alignment: .leading)

                    Rectangle()
                        .fill(DipleColor.accent)
                        .frame(width: step.1, height: 12)

                    Text("\(Int(step.1))")
                        .dipleType(.micro)
                        .foregroundStyle(DipleColor.textQuaternary)
                        .monospacedDigit()
                }
            }
        }
        .padding(DipleSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DipleColor.canvas)
    }
}

#Preview("Spacing scale") {
    DipleSpaceSpecimen()
        .preferredColorScheme(.dark)
}
