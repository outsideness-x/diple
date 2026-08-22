import SwiftUI

private enum FirstLaunchStorage {
    static let completionKey = "diple_has_completed_first_launch"
}

/// The one-time opening title for a new installation.
///
/// This is intentionally a short piece of identity rather than onboarding: there are no
/// permissions to ask for and no controls to teach before someone has a book. The animation
/// turns the app icon's two ingredients — its serif `d` and reading line — into pages, marks
/// and connected thoughts, then gets out of the way. A tap always skips it.
public struct FirstLaunchGate<Content: View>: View {
    @AppStorage(FirstLaunchStorage.completionKey) private var hasCompletedFirstLaunch = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLeaving = false
    @State private var hasCompletedForcedRun = false

    private let content: Content
    /// UI tests need to reproduce an installation without deleting the simulator's real
    /// library. Unlike overriding the UserDefaults key through the argument domain, this flag
    /// does not keep forcing the persisted value back to `false` after the intro finishes.
    private let isForcedForTesting = ProcessInfo.processInfo.arguments.contains("-diple-test-first-launch")

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ZStack {
            content
                .opacity(!isPresenting || isLeaving ? 1 : 0)
                .scaleEffect(!isPresenting || isLeaving || reduceMotion ? 1 : 0.985)
                .allowsHitTesting(!isPresenting)
                .accessibilityHidden(isPresenting)

            if isPresenting {
                FirstLaunchView(onFinish: finish)
                    .opacity(isLeaving ? 0 : 1)
                    .scaleEffect(isLeaving && !reduceMotion ? 1.035 : 1)
                    .allowsHitTesting(!isLeaving)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .background(DipleColor.canvas.ignoresSafeArea())
        .statusBarHidden(isPresenting)
    }

    private var isPresenting: Bool {
        !hasCompletedForcedRun && (!hasCompletedFirstLaunch || isForcedForTesting)
    }

    private func finish() {
        guard !isLeaving else { return }

        if reduceMotion {
            hasCompletedFirstLaunch = true
            hasCompletedForcedRun = true
            return
        }

        withAnimation(DipleMotion.gentle) {
            isLeaving = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(520))
            hasCompletedFirstLaunch = true
            hasCompletedForcedRun = true
        }
    }
}

private struct FirstLaunchView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var didScheduleStory = false

    var body: some View {
        GeometryReader { proxy in
            let shortestSide = min(proxy.size.width, proxy.size.height)
            let artworkWidth = min(max(shortestSide * 0.56, 208), 312)

            ZStack {
                DipleColor.canvas

                LaunchThoughtPaths(progress: progress)
                    .padding(max(DipleSpace.xl, shortestSide * 0.07))

                VStack(spacing: 0) {
                    Spacer(minLength: DipleSpace.xxxl)

                    LaunchColophon(progress: progress, width: artworkWidth)

                    VStack(spacing: DipleSpace.s) {
                        LaunchSequenceLabel(progress: progress)

                        Text("A place for what stays with you.")
                            .dipleType(.callout)
                            .foregroundStyle(DipleColor.textTertiary)
                            .multilineTextAlignment(.center)
                            .opacity(Self.segment(progress, from: 0.76, to: 0.91))
                            .offset(y: (1 - Self.segment(progress, from: 0.76, to: 0.91)) * 8)
                    }
                    .padding(.top, DipleSpace.xxxl)

                    Spacer(minLength: DipleSpace.xxxl)

                    HStack(spacing: DipleSpace.s) {
                        Capsule()
                            .fill(DipleColor.accent)
                            .frame(width: 20, height: 2)

                        Text("TAP TO BEGIN")
                            .dipleType(.nano)
                            .foregroundStyle(DipleColor.textQuaternary)
                    }
                    .opacity(Self.segment(progress, from: 0.88, to: 0.98))
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom, DipleSpace.xxl))
                }
                .padding(.horizontal, DipleSpace.xl)
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: onFinish)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Welcome to diple. A place for what stays with you.")
            .accessibilityHint("Double tap to begin")
            .accessibilityAddTraits(.isButton)
        }
        .onAppear(perform: playStory)
    }

    private func playStory() {
        guard !didScheduleStory else { return }
        didScheduleStory = true

        if reduceMotion {
            progress = 1
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.6))
                onFinish()
            }
            return
        }

        withAnimation(.linear(duration: 4.1)) {
            progress = 1
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4.65))
            onFinish()
        }
    }

    fileprivate static func segment(_ value: CGFloat, from: CGFloat, to: CGFloat) -> CGFloat {
        guard to > from else { return value >= to ? 1 : 0 }
        let normalized = min(max((value - from) / (to - from), 0), 1)
        // A cubic smoothstep gives every beat a clean arrival without stacking several
        // independent animations that can drift apart after an interruption.
        return normalized * normalized * (3 - 2 * normalized)
    }
}

private struct LaunchColophon: View {
    let progress: CGFloat
    let width: CGFloat

    private var pageProgress: CGFloat {
        FirstLaunchView.segment(progress, from: 0.02, to: 0.32)
    }

    private var pageDeparture: CGFloat {
        FirstLaunchView.segment(progress, from: 0.58, to: 0.82)
    }

    private var glyphProgress: CGFloat {
        FirstLaunchView.segment(progress, from: 0.22, to: 0.58)
    }

    private var lineProgress: CGFloat {
        FirstLaunchView.segment(progress, from: 0.42, to: 0.70)
    }

    var body: some View {
        let height = width * 0.86

        ZStack {
            LaunchPagePair(progress: pageProgress)
                .frame(width: width * 0.78, height: height * 0.78)
                .opacity(1 - pageDeparture)
                .scaleEffect(1 + pageDeparture * 0.09)
                .blur(radius: pageDeparture * 5)

            Text("d")
                .font(.system(size: width * 0.57, weight: .regular, design: .serif))
                .foregroundStyle(DipleColor.textPrimary)
                .tracking(-width * 0.025)
                .offset(y: -height * 0.045 + (1 - glyphProgress) * 14)
                .mask(alignment: .bottom) {
                    Rectangle()
                        .scaleEffect(y: glyphProgress, anchor: .bottom)
                }
                .opacity(glyphProgress)

            VStack {
                Spacer()

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DipleColor.hairline)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [DipleColor.accent.opacity(0.62), DipleColor.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .scaleEffect(x: lineProgress, anchor: .leading)

                    Circle()
                        .fill(DipleColor.accent)
                        .frame(width: 6, height: 6)
                        .offset(x: max(0, width * 0.54 * lineProgress - 6))
                        .opacity(lineProgress < 0.04 || lineProgress > 0.98 ? 0 : 1)
                }
                .frame(width: width * 0.54, height: 4)
            }
        }
        .frame(width: width, height: height)
    }
}

/// Two quiet card-surfaces turn toward the reader like a book opening. Perspective is kept
/// deliberately shallow: these are the same carved, shadowless surfaces used everywhere else
/// in the app, just briefly given a third dimension.
private struct LaunchPagePair: View {
    let progress: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let gap = DipleSpace.xs * progress
            let pageWidth = max(0, (proxy.size.width - gap) / 2)
            let openingAngle = 74 * (1 - progress)

            HStack(spacing: gap) {
                page
                    .frame(width: pageWidth)
                    .rotation3DEffect(
                        .degrees(openingAngle),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: .trailing,
                        perspective: 0.72
                    )

                page
                    .frame(width: pageWidth)
                    .rotation3DEffect(
                        .degrees(-openingAngle),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: .leading,
                        perspective: 0.72
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var page: some View {
        RoundedRectangle(cornerRadius: DipleRadius.m, style: .continuous)
            .fill(DipleColor.surface)
            .overlay {
                RoundedRectangle(cornerRadius: DipleRadius.m, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [DipleColor.insetHighlight, DipleColor.hairline],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: DipleStroke.hairline
                    )
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: DipleSpace.s) {
                    ForEach([0.72, 0.90, 0.54, 0.82, 0.64], id: \.self) { fraction in
                        Capsule()
                            .fill(DipleColor.textQuaternary.opacity(0.25))
                            .frame(maxWidth: .infinity)
                            .frame(height: 2)
                            .scaleEffect(x: fraction, anchor: .leading)
                    }
                }
                .padding(DipleSpace.l)
                .opacity(progress)
            }
    }
}

private struct LaunchSequenceLabel: View {
    let progress: CGFloat

    var body: some View {
        HStack(spacing: DipleSpace.m) {
            word("READ", from: 0.61, to: 0.73)
            dot(from: 0.67, to: 0.77)
            word("KEEP", from: 0.70, to: 0.82)
            dot(from: 0.76, to: 0.86)
            word("RETURN", from: 0.79, to: 0.91)
        }
    }

    private func word(_ value: String, from: CGFloat, to: CGFloat) -> some View {
        let reveal = FirstLaunchView.segment(progress, from: from, to: to)
        return Text(value)
            .dipleType(.micro, weight: .semibold)
            .foregroundStyle(DipleColor.textSecondary)
            .opacity(reveal)
            .offset(y: (1 - reveal) * 7)
    }

    private func dot(from: CGFloat, to: CGFloat) -> some View {
        Circle()
            .fill(DipleColor.accent)
            .frame(width: 4, height: 4)
            .scaleEffect(FirstLaunchView.segment(progress, from: from, to: to))
    }
}

/// Highlights become notes and return later: a few hand-drawn paths carry that loop behind the
/// mark. Drawing them in a Canvas keeps the field scale-independent on iPhone, iPad and Mac.
private struct LaunchThoughtPaths: View, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let paths = thoughtPaths(in: size, center: center)

            for (index, path) in paths.enumerated() {
                let start = 0.42 + CGFloat(index) * 0.055
                let reveal = FirstLaunchView.segment(progress, from: start, to: start + 0.28)
                let fade = FirstLaunchView.segment(progress, from: 0.82, to: 1)
                let opacity = reveal * (1 - fade * 0.62)
                guard opacity > 0 else { continue }

                context.stroke(
                    path.trimmedPath(from: 0, to: reveal),
                    with: .color(DipleColor.accent.opacity(0.20 * opacity)),
                    style: StrokeStyle(lineWidth: 0.75, lineCap: .round)
                )

                if reveal > 0.92 {
                    let node = paths[index].currentPoint ?? center
                    let diameter: CGFloat = index.isMultiple(of: 2) ? 5 : 3
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: node.x - diameter / 2,
                            y: node.y - diameter / 2,
                            width: diameter,
                            height: diameter
                        )),
                        with: .color(DipleColor.accent.opacity(0.58 * opacity))
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func thoughtPaths(in size: CGSize, center: CGPoint) -> [Path] {
        let destinations: [(CGPoint, CGPoint, CGPoint)] = [
            (
                CGPoint(x: size.width * 0.13, y: size.height * 0.30),
                CGPoint(x: size.width * 0.33, y: size.height * 0.49),
                CGPoint(x: size.width * 0.18, y: size.height * 0.40)
            ),
            (
                CGPoint(x: size.width * 0.86, y: size.height * 0.25),
                CGPoint(x: size.width * 0.67, y: size.height * 0.48),
                CGPoint(x: size.width * 0.82, y: size.height * 0.37)
            ),
            (
                CGPoint(x: size.width * 0.91, y: size.height * 0.69),
                CGPoint(x: size.width * 0.70, y: size.height * 0.52),
                CGPoint(x: size.width * 0.82, y: size.height * 0.61)
            ),
            (
                CGPoint(x: size.width * 0.08, y: size.height * 0.72),
                CGPoint(x: size.width * 0.31, y: size.height * 0.53),
                CGPoint(x: size.width * 0.18, y: size.height * 0.63)
            )
        ]

        return destinations.map { destination, control1, control2 in
            var path = Path()
            path.move(to: center)
            path.addCurve(to: destination, control1: control1, control2: control2)
            return path
        }
    }
}

#Preview("First launch — final") {
    FirstLaunchView(onFinish: {})
        .preferredColorScheme(.dark)
}
