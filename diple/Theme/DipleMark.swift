import SwiftUI

/// Diple's small visual signature: two pages held around one shared spine.
/// It is drawn in SwiftUI so it stays crisp from a compact cover placeholder to an empty state.
public struct DipleMark: View {
    public var size: CGFloat

    public init(size: CGFloat = 44) {
        self.size = size
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let width = canvasSize.width
            let height = canvasSize.height
            let spineTop = CGPoint(x: width * 0.5, y: height * 0.2)
            let spineBottom = CGPoint(x: width * 0.5, y: height * 0.88)

            var leftPage = Path()
            leftPage.move(to: spineTop)
            leftPage.addCurve(
                to: CGPoint(x: width * 0.12, y: height * 0.12),
                control1: CGPoint(x: width * 0.40, y: height * 0.08),
                control2: CGPoint(x: width * 0.22, y: height * 0.08)
            )
            leftPage.addLine(to: CGPoint(x: width * 0.12, y: height * 0.72))
            leftPage.addCurve(
                to: spineBottom,
                control1: CGPoint(x: width * 0.28, y: height * 0.66),
                control2: CGPoint(x: width * 0.42, y: height * 0.74)
            )

            var rightPage = Path()
            rightPage.move(to: spineTop)
            rightPage.addCurve(
                to: CGPoint(x: width * 0.88, y: height * 0.12),
                control1: CGPoint(x: width * 0.60, y: height * 0.08),
                control2: CGPoint(x: width * 0.78, y: height * 0.08)
            )
            rightPage.addLine(to: CGPoint(x: width * 0.88, y: height * 0.72))
            rightPage.addCurve(
                to: spineBottom,
                control1: CGPoint(x: width * 0.72, y: height * 0.66),
                control2: CGPoint(x: width * 0.58, y: height * 0.74)
            )

            let lineWidth = max(1, size * 0.045)
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [DipleColor.textSecondary, DipleColor.accent]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: width, y: height)
            )
            context.stroke(leftPage, with: shading, lineWidth: lineWidth)
            context.stroke(rightPage, with: shading, lineWidth: lineWidth)

            let nodeDiameter = max(2, size * 0.09)
            for point in [
                CGPoint(x: width * 0.12, y: height * 0.12),
                CGPoint(x: width * 0.88, y: height * 0.12)
            ] {
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - nodeDiameter / 2,
                        y: point.y - nodeDiameter / 2,
                        width: nodeDiameter,
                        height: nodeDiameter
                    )),
                    with: .color(DipleColor.accent)
                )
            }
        }
        .frame(width: size, height: size * 0.82)
        .accessibilityHidden(true)
    }
}

#Preview("Diple Mark") {
    VStack(spacing: DipleSpace.xxl) {
        DipleMark(size: 72)
        DipleMark(size: 32)
        DipleMark(size: 18)
    }
    .padding(DipleSpace.xxxl)
    .background(DipleColor.canvas)
    .preferredColorScheme(.dark)
}
