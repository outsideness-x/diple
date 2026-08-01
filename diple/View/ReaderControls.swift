import SwiftUI

/// Draggable reading-progress bar.
///
/// The visible line stays thin while reading and thickens with a handle under the finger,
/// so the control reads as decoration until it is touched. Dragging previews the target
/// position locally and only jumps once the finger lifts, which keeps the navigator from
/// churning through intermediate locations.
public struct ReadingProgressSlider: View {
    public let progress: Double
    public let isEnabled: Bool
    public let onSeek: (Double) -> Void

    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0
    @State private var lastTickStep: Int = -1

    private static let trackHeight: CGFloat = 3
    private static let activeTrackHeight: CGFloat = 6
    private static let handleSize: CGFloat = 14

    public init(progress: Double, isEnabled: Bool, onSeek: @escaping (Double) -> Void) {
        self.progress = progress
        self.isEnabled = isEnabled
        self.onSeek = onSeek
    }

    private var displayedProgress: Double {
        min(max(isScrubbing ? scrubProgress : progress, 0), 1)
    }

    public var body: some View {
        GeometryReader { geo in
            let height = isScrubbing ? Self.activeTrackHeight : Self.trackHeight
            let filled = geo.size.width * displayedProgress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: height)

                Capsule()
                    .fill(Color.dipleAccent)
                    .frame(width: filled, height: height)

                Circle()
                    .fill(Color.dipleAccent)
                    .frame(width: Self.handleSize, height: Self.handleSize)
                    .shadow(color: Color.black.opacity(0.5), radius: 4, y: 1)
                    .offset(x: filled - Self.handleSize / 2)
                    .opacity(isScrubbing ? 1 : 0)
                    .scaleEffect(isScrubbing ? 1 : 0.4)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isScrubbing)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled, geo.size.width > 0 else { return }
                        if !isScrubbing {
                            isScrubbing = true
                            lastTickStep = -1
                            HapticManager.shared.impact(.light)
                        }
                        scrubProgress = min(max(value.location.x / geo.size.width, 0), 1)

                        // A tick every 2% turns the drag into something you can feel.
                        let step = Int(scrubProgress * 50)
                        if step != lastTickStep {
                            lastTickStep = step
                            HapticManager.shared.selection()
                        }
                    }
                    .onEnded { _ in
                        guard isEnabled, isScrubbing else { return }
                        isScrubbing = false
                        HapticManager.shared.impact(.medium)
                        onSeek(scrubProgress)
                    }
            )
        }
        .frame(height: 26)
        .opacity(isEnabled ? 1 : 0.6)
    }
}

/// Brief confirmation pill shown over the page after an action such as saving a bookmark.
public struct ReaderToastView: View {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Color(red: 0.95, green: 0.95, blue: 0.96))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.45), radius: 10, y: 4)
    }
}

/// Gives the reader's icon buttons a tactile press response — SwiftUI's plain buttons
/// have none, which makes the overlay feel dead on a dark background.
public struct ReaderControlButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == ReaderControlButtonStyle {
    static var readerControl: ReaderControlButtonStyle { ReaderControlButtonStyle() }
}

/// Press feedback for the library grid. `.plain` leaves the cards completely inert, which
/// makes a tap feel like it was lost until the reader finishes opening.
public struct BookCardButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == BookCardButtonStyle {
    static var bookCard: BookCardButtonStyle { BookCardButtonStyle() }
}
