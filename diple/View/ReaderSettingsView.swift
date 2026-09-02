import SwiftUI

/// The reader's own controls: how the page is coloured, set and paced.
///
/// Laid out as a column of named rows — label on the left, control on the right — rather than
/// as a stack of small-caps sections with a control under each. The sections were a Settings
/// idiom applied to a reading control panel: five grey capitals down one screen, each of them
/// a heading for a single row, so the headings took as much vertical space as the things they
/// headed. A name beside its control says the same thing in one line.
///
/// Two blocks keep the older shape, because their control genuinely is the full width: the
/// theme swatches and the typeface specimens are choices you read across, not values you nudge.
///
/// **No numeric read-outs.** Size, leading and measure used to print a percentage, and a
/// percentage of a typographic quantity answers a question nobody has — nobody wants 110%
/// leading, they want it looser. The glyph on each button shows what pressing it does, and the
/// button greys out at the end of its ladder, which is the whole of what the number was for.
public struct ReaderSettingsView: View {
    @Binding public var settings: ReaderSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(settings: Binding<ReaderSettings>) {
        self._settings = settings
    }

    public var body: some View {
        ScrollView {
            settingsContent
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(DipleColor.canvas.opacity(0.6).ignoresSafeArea())
        .presentationBackground(.regularMaterial)
        // A fixed height clips the controls as soon as the text size grows, so let the
        // sheet size itself instead.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Two equal columns, one at accessibility sizes — the same trade the library grid and the
    /// notes board already make. Two columns of "Hyperlegible" at those sizes is two truncated
    /// labels, and the label *is* the specimen: a font option whose name cannot be read has
    /// nothing left to offer.
    private var pickerColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: DipleSpace.xxl) {
            header

            picker(title: "Theme") {
                LazyVGrid(columns: pickerColumns, spacing: DipleSpace.m) {
                    ForEach(ReaderPageTheme.allCases) { pageTheme in
                        themeButton(pageTheme)
                    }
                }
            }

            picker(title: "Typeface") {
                LazyVGrid(columns: pickerColumns, spacing: DipleSpace.m) {
                    ForEach(ReaderFont.allCases) { readerFont in
                        fontFamilyButton(fontOption: readerFont)
                    }
                }
            }

            VStack(spacing: DipleSpace.l) {
                stepperRow(
                    title: "Size",
                    decrease: .init(glyph: .letter(13), isEnabled: settings.canDecreaseFontSize) {
                        settings.fontSizeStep -= 1
                    },
                    increase: .init(glyph: .letter(21), isEnabled: settings.canIncreaseFontSize) {
                        settings.fontSizeStep += 1
                    }
                )

                stepperRow(
                    title: "Spacing",
                    decrease: .init(glyph: .rules(gap: 3, width: 20), isEnabled: settings.canTightenLineHeight) {
                        settings.lineHeightStep -= 1
                    },
                    increase: .init(glyph: .rules(gap: 7, width: 20), isEnabled: settings.canLoosenLineHeight) {
                        settings.lineHeightStep += 1
                    }
                )

                stepperRow(
                    title: "Width",
                    decrease: .init(glyph: .rules(gap: 5, width: 12), isEnabled: settings.canNarrow) {
                        settings.widthStep -= 1
                    },
                    increase: .init(glyph: .rules(gap: 5, width: 24), isEnabled: settings.canWiden) {
                        settings.widthStep += 1
                    }
                )
            }

            picker(title: "Reading") {
                HStack(spacing: DipleSpace.m) {
                    ForEach(ReadingMode.allCases) { mode in
                        readingModeButton(mode)
                    }
                }
            }

            Spacer(minLength: DipleSpace.xxl)
        }
        .padding(.horizontal, DipleSpace.xxl)
        .animation(DipleMotion.standard, value: settings)
    }

    private var header: some View {
        HStack {
            Text("Reader")
                .dipleType(.title)
                .foregroundStyle(DipleColor.textPrimary)
            Spacer()
            Button("Done") {
                HapticManager.shared.selection()
                dismiss()
            }
            .dipleType(.body, weight: .medium)
            .foregroundStyle(DipleColor.textPrimary)
        }
        .padding(.top, DipleSpace.l)
    }

    /// A block whose control is the full width: the name sits above it rather than beside it,
    /// because four swatches next to a label would leave the label a column of its own and the
    /// swatches too little room to read.
    private func picker<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            Text(title)
                .dipleType(.body, weight: .medium)
                .foregroundStyle(DipleColor.textSecondary)
            content()
        }
    }

    // MARK: - Steppers

    /// One end of a stepper: what it looks like, whether it can still move, and what it does.
    private struct StepperEnd {
        let glyph: StepperGlyph
        let isEnabled: Bool
        let action: () -> Void
    }

    /// The glyph *is* the label. A pair of buttons marked − and + says a value is changing and
    /// nothing about which one; a small A beside a large A, or three tight rules beside three
    /// loose ones, says what the page will do.
    private enum StepperGlyph {
        case letter(CGFloat)
        case rules(gap: CGFloat, width: CGFloat)
    }

    /// Label left, the pair of buttons right — until the text is large enough that the two
    /// cannot share a line, at which point the label takes its own. `ViewThatFits` decides that
    /// by measurement rather than by a size threshold, so it holds for any combination of
    /// language and Dynamic Type rather than the ones that were tried.
    private func stepperRow(title: String, decrease: StepperEnd, increase: StepperEnd) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DipleSpace.m) {
                stepperLabel(title)
                Spacer(minLength: DipleSpace.m)
                stepperButtons(decrease: decrease, increase: increase)
            }

            VStack(alignment: .leading, spacing: DipleSpace.s) {
                stepperLabel(title)
                stepperButtons(decrease: decrease, increase: increase)
            }
        }
    }

    private func stepperLabel(_ title: String) -> some View {
        Text(title)
            .dipleType(.body, weight: .medium)
            .foregroundStyle(DipleColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func stepperButtons(decrease: StepperEnd, increase: StepperEnd) -> some View {
        HStack(spacing: DipleSpace.s) {
            stepperButton(decrease, label: "\(currentStepperLabel) smaller")
            stepperButton(increase, label: "\(currentStepperLabel) larger")
        }
    }

    /// VoiceOver reads the row's own label through the accessibility element, so the buttons
    /// only have to say which way they go.
    private var currentStepperLabel: String { "Step" }

    private func stepperButton(_ end: StepperEnd, label: String) -> some View {
        Button {
            guard end.isEnabled else { return }
            HapticManager.shared.impact(.light)
            end.action()
        } label: {
            stepperGlyph(end.glyph)
                .foregroundStyle(end.isEnabled ? DipleColor.textPrimary : DipleColor.textQuaternary)
                .frame(width: 68, height: 44)
                .background(DipleColor.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: DipleRadius.s, style: .continuous))
        }
        .buttonStyle(.readerControl)
        .disabled(!end.isEnabled)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func stepperGlyph(_ glyph: StepperGlyph) -> some View {
        switch glyph {
        case let .letter(size):
            Text("A").dipleIcon(size, weight: size > 16 ? .bold : .medium)
        case let .rules(gap, width):
            // Drawn rather than borrowed from SF Symbols: no symbol varies its line gap, and
            // the gap is exactly what the Spacing control changes. Width does the same trick
            // sideways, so one glyph serves both rows and the pair reads as one family.
            VStack(spacing: gap) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    Capsule().frame(width: width, height: 2)
                }
            }
        }
    }

    // MARK: - Pickers

    /// The one control that rings itself by hand instead of calling `dipleSelected`.
    ///
    /// That modifier tints a chosen option with `accentSoft`, which is right everywhere the
    /// fill underneath is chrome — and wrong here, where the fill *is* the answer: laying a
    /// wash of accent over the Paper swatch would show the reader a paper they are not about
    /// to get. So the swatch keeps its page colour under every state and takes the ring alone,
    /// at the same `DipleStroke.selection` weight as everything else.
    private func themeButton(_ pageTheme: ReaderPageTheme) -> some View {
        let isSelected = settings.theme == pageTheme
        return Button {
            HapticManager.shared.selection()
            settings.theme = pageTheme
        } label: {
            HStack(spacing: DipleSpace.s) {
                Circle()
                    .fill(pageTheme.swatchInk)
                    .frame(width: 10, height: 10)
                Text(pageTheme.title)
                    .dipleType(.callout, weight: .medium)
                    .foregroundColor(pageTheme.swatchInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DipleSpace.m)
            .background(pageTheme.swatchBackground)
            .clipShape(RoundedRectangle(cornerRadius: DipleRadius.m, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DipleRadius.m, style: .continuous)
                    .stroke(isSelected ? DipleColor.accent : Color.clear, lineWidth: DipleStroke.selection)
            }
        }
        .buttonStyle(.readerControl)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// A specimen of the family it selects. New York and San Francisco are system faces with no
    /// app-side family name to pass to `Font.custom` — `registeredFamilyName` is `nil` for both —
    /// so they are named by design instead, which resolves to the same two faces the page gets
    /// through `ui-serif` and `-apple-system`. The shipped ones are named through `UIAppFonts`,
    /// which is a separate registration from the one Readium performs for the page itself.
    private func fontOptionLabel(_ fontOption: ReaderFont) -> Text {
        guard let family = fontOption.registeredFamilyName else {
            return Text(fontOption.title)
                .font(.system(
                    .subheadline,
                    design: fontOption == .serif ? .serif : .default,
                    weight: .medium
                ))
        }
        return Text(fontOption.title).font(.custom(family, size: 15, relativeTo: .subheadline))
    }

    /// A specimen, on the paper it will be printed on.
    ///
    /// The theme swatches above are the best control on this sheet because each is drawn in its
    /// own page colour: the choice is legible before it is made. The typeface buttons sat on
    /// interface chrome instead and so showed the face on a ground it will never appear on —
    /// and the selected one, when selection was still a fill, overprinted the specimen with
    /// accent and stopped being a specimen at all.
    ///
    /// Both grids now say the same thing the same way: the reader's current page colour and
    /// ink, the ring for the one that is chosen.
    private func fontFamilyButton(fontOption: ReaderFont) -> some View {
        let isSelected = settings.font == fontOption
        return Button {
            HapticManager.shared.selection()
            settings.font = fontOption
        } label: {
            // The only place in the app that leaves San Francisco, and it has to: this
            // label is a swatch for the family the page itself will be set in. Taking the
            // size from a `TextStyle` rather than a point size keeps it on Dynamic Type —
            // including for the shipped faces, where `Font.custom(_:relativeTo:)` is the
            // scaling form and the bare `Font.custom(_:size:)` is not.
            fontOptionLabel(fontOption)
                .foregroundStyle(settings.theme.swatchInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, DipleSpace.s)
                .padding(.vertical, DipleSpace.m)
                .background(settings.theme.swatchBackground)
                .clipShape(RoundedRectangle(cornerRadius: DipleRadius.m, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DipleRadius.m, style: .continuous)
                        .stroke(
                            isSelected ? DipleColor.accent : Color.clear,
                            lineWidth: DipleStroke.selection
                        )
                }
        }
        .buttonStyle(.readerControl)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func readingModeButton(_ mode: ReadingMode) -> some View {
        let isSelected = settings.readingMode == mode
        return Button {
            HapticManager.shared.selection()
            settings.readingMode = mode
        } label: {
            Text(mode.rawValue)
                .dipleType(.callout, weight: .medium)
                .foregroundStyle(isSelected ? DipleColor.accentInk : DipleColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DipleSpace.m)
                .dipleSelected(
                    isSelected,
                    in: RoundedRectangle(cornerRadius: DipleRadius.m, style: .continuous),
                    resting: DipleColor.surfaceRaised
                )
        }
        .buttonStyle(.readerControl)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The swatch colours for the theme picker. Kept here rather than on `ReaderPageTheme` itself
/// (`Model/ReaderSettings.swift`, which has no SwiftUI import): each theme is painted in its
/// own colour rather than inferred from the accent, which is what makes the choice legible
/// before it is made, and that is a View-layer concern, not a Readium-preferences one.
private extension ReaderPageTheme {
    var swatchBackground: Color {
        switch self {
        case .paper: return DipleColor.Page.paperBackground
        case .sepia: return DipleColor.Page.sepiaBackground
        case .carbon: return DipleColor.Page.carbonBackground
        case .ink: return DipleColor.Page.inkBackground
        }
    }

    var swatchInk: Color {
        switch self {
        case .paper: return DipleColor.Page.paperText
        case .sepia: return DipleColor.Page.sepiaText
        case .carbon: return DipleColor.Page.carbonText
        case .ink: return DipleColor.Page.inkText
        }
    }
}
