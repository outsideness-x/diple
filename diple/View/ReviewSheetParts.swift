import SwiftUI

/// The pieces a review sheet is built from.
///
/// diple has two screens that stand between choosing a file and changing the library — restoring
/// a backup and importing somebody else's highlights — and they must look like one another,
/// because they are the same promise made twice: *here is exactly what will happen, nothing is
/// deleted, you can still walk away.* Copies of a hero and a counted row drift apart in a single
/// afternoon of tuning one of them, so the shape lives here and only the words differ.
///
/// The emblem, not an icon on a plain canvas: a framed panel is what tells the reader this is a
/// threshold rather than one more settings row.
public struct ReviewHero: View {
    public let systemImage: String
    public let isComplete: Bool
    public let title: String
    public let detail: String

    public init(systemImage: String, isComplete: Bool, title: String, detail: String) {
        self.systemImage = systemImage
        self.isComplete = isComplete
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DipleSpace.l) {
            ZStack {
                RoundedRectangle(cornerRadius: DipleRadius.l, style: .continuous)
                    .fill(DipleColor.surfaceRaised)
                    .overlay {
                        RoundedRectangle(cornerRadius: DipleRadius.l, style: .continuous)
                            .stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline)
                    }

                VStack(spacing: DipleSpace.s) {
                    Image(systemName: isComplete ? "checkmark" : systemImage)
                        .dipleIcon(24, weight: .medium)
                        .foregroundStyle(isComplete ? DipleColor.textOnAccent : DipleColor.textPrimary)
                        .frame(width: 52, height: 52)
                        .background(isComplete ? DipleColor.accent : DipleColor.surfaceOverlay, in: Circle())

                    Capsule()
                        .fill(DipleColor.accent)
                        .frame(width: 28, height: 2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 154)

            VStack(alignment: .leading, spacing: DipleSpace.s) {
                Text(title)
                    .dipleType(.display)
                    .foregroundStyle(DipleColor.textPrimary)

                Text(detail)
                    .dipleType(.callout)
                    .foregroundStyle(DipleColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One line of "this many, of this kind". The number is set in the display face and greys out at
/// zero rather than disappearing: a row that vanishes when it has nothing to report makes the
/// list a different length each time, and the reader has to re-read it to see what is missing.
public struct ReviewCountRow: View {
    public let icon: String
    public let title: String
    public let detail: String
    public let value: Int

    public init(icon: String, title: String, detail: String, value: Int) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.value = value
    }

    public var body: some View {
        HStack(spacing: DipleSpace.m) {
            Image(systemName: icon)
                .dipleIcon(15, weight: .medium)
                .foregroundStyle(DipleColor.accentInk)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .dipleType(.body, weight: .medium)
                    .foregroundStyle(DipleColor.textPrimary)
                Text(detail)
                    .dipleType(.caption)
                    .foregroundStyle(DipleColor.textTertiary)
            }

            Spacer()

            Text("\(value)")
                .dipleType(.title)
                .foregroundStyle(value > 0 ? DipleColor.textPrimary : DipleColor.textQuaternary)
                .monospacedDigit()
        }
        .padding(.horizontal, DipleSpace.l)
        .padding(.vertical, DipleSpace.m)
        .background(DipleColor.surfaceRaised)
    }
}

/// A quiet aside: what the operation will not do, what the file does not contain, or why it
/// stopped. Destructive colouring is the caller's choice, not a separate view.
public struct ReviewNote: View {
    public let icon: String
    public let title: String
    public let detail: String
    public var colour: Color = DipleColor.accent

    public init(icon: String, title: String, detail: String, colour: Color = DipleColor.accent) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.colour = colour
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DipleSpace.m) {
            Image(systemName: icon)
                .dipleIcon(16, weight: .medium)
                .foregroundStyle(colour)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                Text(title)
                    .dipleType(.body, weight: .medium)
                    .foregroundStyle(DipleColor.textPrimary)
                Text(detail)
                    .dipleType(.caption)
                    .foregroundStyle(DipleColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DipleSpace.l)
        .craftSurface(DipleColor.surface, radius: DipleRadius.m)
    }
}

/// The one big number a finished operation leaves behind.
public struct ReviewOutcome: View {
    public let label: String
    public let value: Int
    public let detail: String

    public init(label: String, value: Int, detail: String) {
        self.label = label
        self.value = value
        self.detail = detail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            Text(label)
                .dipleType(.micro, weight: .semibold)
                .foregroundStyle(DipleColor.textTertiary)
            Text("\(value)")
                .dipleType(.hero)
                .foregroundStyle(DipleColor.textPrimary)
                .monospacedDigit()
            Text(detail)
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DipleSpace.l)
        .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.m)
    }
}

public extension View {
    func reviewPrimaryButton() -> some View {
        self
            .dipleType(.body, weight: .semibold)
            .foregroundStyle(DipleColor.textOnAccent)
            .frame(maxWidth: .infinity)
            .diplePadding(.buttonLarge)
            .background(DipleColor.accent, in: Capsule())
            .buttonStyle(.readerControl)
    }

}

/// The working state of a review sheet's primary control: the same capsule, with the verb in
/// the present tense beside a spinner. Not a `Button` — there is nothing to tap while it runs.
public struct ReviewProgressCapsule: View {
    public let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        HStack(spacing: DipleSpace.m) {
            ProgressView().tint(DipleColor.textOnAccent)
            Text(title)
                .dipleType(.body, weight: .semibold)
        }
        .foregroundStyle(DipleColor.textOnAccent)
        .frame(maxWidth: .infinity)
        .diplePadding(.buttonLarge)
        .background(DipleColor.accent, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
