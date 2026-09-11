#!/usr/bin/env python3
"""Draws the app icon: the app's wordmark, in the app's own hand.

**What the icon says.** A diple is the wedge Alexandrian scholars set in the margin against a
line worth noticing — the ancestor of the quotation mark, and literally the app's name and its
function. The icon is that wedge with the app's initial and its full stop after it: `>d.`

**Why the letter is not optional.** The first icon of the app was the wedge alone, and it failed
for a reason worth keeping written down: on its own in an empty square it is not a diple, it is
the system chevron for "forward", and at 60 pt nobody reads it as anything else. The icon after
it answered that by drawing the line the wedge stands against — a whole page of it, three bars
and a margin. That worked and it was a picture: at Home Screen size it read as a menu glyph with
a chevron beside it, and it said nothing about which app it was. `>d.` answers the same
objection with three characters instead of a scene. The `d` is what stops the wedge being a
chevron, the full stop is the one the wordmark has carried since the redesign (`diple.` in the
masthead), and together they are a name rather than an illustration.

**The mark is written, not drawn.** It is set in Caveat, the same notebook hand as the Settings
colophon and the Living Margins note — the app's one handwriting face, and the only place its
own voice is not a publisher's. The previous icon simulated a broad-edged pen with swept
parallelograms to get a written mark out of two straight strokes; a face that was actually
written needs none of that. Weight 400: the floor of Caveat's `wght` axis, the family has
nothing lighter, and it is exactly the weight the colophon is set in.

**Colour carries the roles the app already assigns.** The mark is the accent, because in diple
the accent is always the reader's own act — the highlight, the progress ribbon, `accentInk`.
That is also what makes the accent alternates worth having: the thing that changes colour is the
thing the reader chose. The plate is the app's canvas, not its paper: the wordmark in the
masthead is light-on-dark, and an icon that inverted it would be a different mark.

**The set names carry the artwork, not just the colour** — the primary set included. iOS never
re-reads an icon whose name is already the one in force, so redrawing one under its old name
leaves every reader who had it selected looking at the previous artwork forever. `SUFFIX` is
what records the current design; the next redesign changes it here, in
`DipleAccent.alternateIconName`, and in `ASSETCATALOG_COMPILER_APPICON_NAME` /
`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`, and the four must not disagree.

Run from the repository root:

    python3 Scripts/generate_icons.py
    python3 Scripts/generate_mac_icon.py   # the Mac ladder is derived from what this writes
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ASSETS = Path("diple/Assets.xcassets")
FONT = Path("diple/Resources/Fonts/Caveat-Variable.ttf")

# Must stay in sync with `DipleAccent.alternateIconName` in diple/Theme/DipleAccent.swift and
# with the two asset-catalog build settings. Ink is the primary set, so it has no alternate.
SUFFIX = "Hand"
PRIMARY = "#86A8FF"
ACCENTS = {
    "Lilac": "#DF9BE1",
    "Mint": "#6FD6B4",
    "Clay": "#D97757",
    "Brass": "#C8A45C",
}

WORDMARK = (">", "d.")
# The floor of Caveat's axis. The family has no lighter cut, and this is what the colophon uses.
WEIGHT = 400

# How much ink is taken off each side of every stroke, in pixels of the finished 1024 artwork.
#
# **Thinner than the face goes.** At 400, the lightest weight Caveat has, the mark still came
# out too heavy for an icon: a stem around 45 px on a 1024 square, a felt-tip on the Home Screen
# rather than a pen. There is no lighter cut to reach for, so the weight is taken off the ink
# instead — the glyphs are rendered at the supersampled size and eroded evenly, which keeps
# every letterform and every wobble of the hand exactly where Caveat put them and removes only
# stroke. Six pixels a side is the value chosen from a side-by-side at 240, 120 and 60 px: at
# eight the full stop and the thin end of the wedge begin to break up at Spotlight size.
THINNING = 6

# Taken out of the gap between the wedge and the letter, as a fraction of the em.
#
# Caveat spaces `>` as the maths glyph it is in running text, where it stands between two
# operands with air on both sides. Here it is the first character of a word, and at the face's
# own fit the two halves read as a chevron *and* a letter rather than as one mark. Measured on
# the artwork at 1024: past about -0.08 the wedge starts to touch the bowl of the `d`.
KERN = -0.05

# The dark plate is a couple of units deeper so the icon does not glow against a dark wallpaper.
PLATE = (11, 11, 15)
PLATE_DARK = (7, 7, 10)

CANVAS = 1024
# Drawn at this multiple and downsampled. FreeType antialiases the glyph edges already; what
# this buys is the *placement* — the ink box is measured in supersampled pixels, so centring is
# accurate to a quarter of a final pixel rather than to a whole one.
SUPERSAMPLE = 4

# How much of the square the ink spans, along whichever axis binds first.
#
# A little over half. An icon is masked into a superellipse and then shown at 60 pt beside
# other icons; a wordmark run towards the edges loses its corners to the mask and its air to
# the neighbours. Two thirds was the first draft and read as shouting on the Home Screen — the
# mark is handwriting, and handwriting is smaller than the page it is written on.
INK_SPAN = 0.56

# How far the placement is pulled from the ink box towards the ink's centre of mass.
#
# **Neither one alone centres this mark.** By its box, the wedge — three thin strokes and a lot
# of enclosed emptiness — claims as much of the width as the `d`, and the word sits visibly
# right of centre. By its mass, the tall ascender and the full stop drag it the other way and
# the box hangs off the left. A fraction of the way from one to the other is what the eye reads
# as centred, and a third of the way is the value that looked right at 1024, at 180 and at 60.
#
# This replaces the pair of hand-picked nudges an earlier draft used. Two numbers tuned by eye
# are two numbers to re-tune the moment the wordmark or the face changes; this is a rule.
MASS_PULL = 0.33


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def fitted_font(size: int) -> ImageFont.FreeTypeFont:
    font = ImageFont.truetype(str(FONT), size)
    font.set_variation_by_axes([WEIGHT])
    return font


def drawn_wordmark(size: int) -> Image.Image:
    """The two halves on one baseline, kerned, cropped to the ink and nothing else.

    **Measured, not calculated.** `textbbox` answers with the face's metrics, and Caveat is a
    hand: its glyphs overshoot their own advances by design — the `d`'s ascender leans out past
    the letter it belongs to, the wedge sits inside a wide maths sidebearing. Placing by those
    numbers put the finished mark 55 px right of centre on a 1024 square. Rendering it and
    reading the alpha channel is the only measurement that is about the ink.

    The two pieces are drawn from one pen position on one baseline, so every vertical relation
    in the mark is the face's own; only the gap between them is ours.
    """
    font = fitted_font(size)
    # Room for the overshoot in every direction, then thrown away by the crop.
    sheet = Image.new("RGBA", (size * 5, size * 4), (0, 0, 0, 0))
    art = ImageDraw.Draw(sheet)

    pen = size
    for index, piece in enumerate(WORDMARK):
        art.text((pen, size), piece, font=font, fill=(255, 255, 255, 255))
        pen += art.textlength(piece, font=font) + KERN * size

    return sheet.crop(sheet.getbbox())


def wordmark_layer(colour: tuple[int, int, int]) -> Image.Image:
    """The mark, sized to `INK_SPAN`, thinned by `THINNING` and stood in the middle."""
    ink = drawn_wordmark(CANVAS * SUPERSAMPLE // 3).getchannel("A")

    # Sized at the supersampled scale first, so the erosion works on four pixels for every one
    # it will end up as, and the thinned edge is resampled smooth rather than stepped.
    scale = CANVAS * SUPERSAMPLE * INK_SPAN / max(ink.size)
    alpha = ink.resize((max(1, round(ink.width * scale)), max(1, round(ink.height * scale))), Image.LANCZOS)
    if THINNING:
        alpha = alpha.filter(ImageFilter.MinFilter(2 * round(THINNING * SUPERSAMPLE) + 1))
    alpha = alpha.resize(
        (max(1, round(alpha.width / SUPERSAMPLE)), max(1, round(alpha.height / SUPERSAMPLE))),
        Image.LANCZOS,
    )

    origin = optical_origin(alpha)

    layer = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    tinted = Image.new("RGBA", alpha.size, colour + (0,))
    tinted.putalpha(alpha)
    layer.paste(tinted, origin, tinted)
    return layer


def optical_origin(alpha: Image.Image) -> tuple[int, int]:
    """Where to put the ink so that it *looks* centred. See `MASS_PULL`."""
    weights = alpha.load()
    total = 0.0
    sum_x = 0.0
    sum_y = 0.0
    for y in range(alpha.height):
        for x in range(alpha.width):
            value = weights[x, y]
            if value:
                total += value
                sum_x += x * value
                sum_y += y * value

    box_centre = (alpha.width / 2, alpha.height / 2)
    mass_centre = (sum_x / total, sum_y / total) if total else box_centre

    anchor = tuple(
        box + (mass - box) * MASS_PULL
        for box, mass in zip(box_centre, mass_centre)
    )
    return (round(CANVAS / 2 - anchor[0]), round(CANVAS / 2 - anchor[1]))


def artwork(plate, colour) -> Image.Image:
    canvas = Image.new("RGB", (CANVAS, CANVAS), plate)
    layer = wordmark_layer(colour)
    canvas.paste(layer, (0, 0), layer)
    return canvas


def contents() -> dict:
    """One artwork per iOS 18 appearance."""
    return {
        "images": [
            {
                "filename": "icon.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            },
            {
                "appearances": [{"appearance": "luminosity", "value": "dark"}],
                "filename": "icon-dark.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            },
            {
                "appearances": [{"appearance": "luminosity", "value": "tinted"}],
                "filename": "icon-tinted.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            },
        ],
        "info": {"author": "xcode", "version": 1},
    }


def write(name: str, accent: str) -> None:
    icon_set = ASSETS / f"AppIcon{name}.appiconset"
    icon_set.mkdir(parents=True, exist_ok=True)
    colour = hex_to_rgb(accent)

    artwork(PLATE, colour).save(icon_set / "icon.png")
    artwork(PLATE_DARK, colour).save(icon_set / "icon-dark.png")
    # **Tinted has to be greyscale**: the system colours it by luminance from the reader's own
    # tint, and an accent mark under somebody else's hue reads as a mistake rather than a choice.
    # Near-white rather than the mid grey the old artwork used — that one had a cream page to
    # carry the brightness and the mark could sit under it, and this has only the mark.
    artwork((0, 0, 0), (235, 235, 235)).save(icon_set / "icon-tinted.png")

    (icon_set / "Contents.json").write_text(json.dumps(contents(), indent=2) + "\n", encoding="utf-8")
    print(f"wrote {icon_set}")


def main() -> None:
    write(SUFFIX, PRIMARY)
    for name, accent in ACCENTS.items():
        write(f"{name}{SUFFIX}", accent)


if __name__ == "__main__":
    main()
