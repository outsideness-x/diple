#!/usr/bin/env python3
"""Draws the app icon: the diple in the margin of a page.

**What the icon says.** A diple is the wedge Alexandrian scholars set in the margin against a
line worth noticing — the ancestor of the quotation mark, and literally the app's name and its
function. The first icon of the app was that wedge alone, and it failed for a reason worth
keeping written down: on its own in an empty square it is not a diple, it is the system chevron
for "forward", and at 60 pt nobody reads it as anything else. **The sign only means what it
means in relation to a line**, which is exactly why the reader's own margin marker works. So the
icon carries the line too: the wedge stands in the margin, the page runs off the right edge, and
the mark is a mark rather than a button.

**The mark is written, not drawn.** The stroke is the region a broad-edged pen covers as it is
dragged along a path — at every step the nib is a short segment held at a fixed angle, and the
stroke is the union of the parallelograms it sweeps. The heavy arm and the hairline arm, the
terminals cut flat at the pen's own angle, and a corner that joins the way ink joins all fall
out of that model rather than being drawn in by hand.

**Colour carries the roles the app already assigns.** The page is cream, because that is the
app's paper; the mark is the accent, because in diple the accent is always the reader's own act —
the highlight, the progress ribbon, `accentInk`. That is also what makes the accent alternates
worth having: the thing that changes colour is the thing the reader chose.

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
import math
from pathlib import Path

from PIL import Image, ImageDraw

ASSETS = Path("diple/Assets.xcassets")

# Must stay in sync with `DipleAccent.alternateIconName` in diple/Theme/DipleAccent.swift and
# with the two asset-catalog build settings. Brass is the primary set, so it has no alternate.
SUFFIX = "Diple"
PRIMARY = "#C8A45C"
ACCENTS = {
    "Lilac": "#DF9BE1",
    "Mint": "#6FD6B4",
    "Clay": "#D97757",
    "Periwinkle": "#8FA4F2",
}

CREAM = (233, 226, 212)
# The dark plate is a couple of units deeper so the icon does not glow against a dark wallpaper.
PLATE = (11, 11, 15)
PLATE_DARK = (7, 7, 10)

CANVAS = 1024
# Drawn at this multiple and downsampled: `ImageDraw` has no anti-aliasing of its own, and the
# hairline arm of the mark is exactly where that shows.
SUPERSAMPLE = 4

# The composition, in 1024 space.
#
# **Everything sits on one margin grid.** The content is inset by `MARGIN` on all four sides and
# nothing crosses it: the mark starts at the left margin, the full lines stop at the right one,
# and the group is centred in what is left. An earlier draft ran the lines off the right edge to
# say "the page continues"; at Home Screen size that does not read as a page continuing, it
# reads as artwork that does not fit its own square.
MARGIN = 150.0
GUTTER = 64.0            # between the mark in the margin and the text it stands against

LINE_PITCH = 112.0
LINE_THICKNESS = 44.0
# The last line is short, the way the last line of a paragraph is. It is the one detail that
# stops three equal bars from reading as a hamburger menu.
LINE_SHORT = 0.66        # of the measure

MARK_HEIGHT = 165.0
# The mark reaches this much of its own height to the right of where it starts.
MARK_REACH = 0.92

# The nib: its width as a fraction of the mark's height, and the angle it is held at before and
# after the apex.
#
# **The pen twists at the corner, and it has to.** Held at one angle for the whole sign, the
# return stroke runs nearly along the nib's own edge and comes out as a needle that tapers to
# nothing — true to the physics of a fixed nib and useless as a mark, which is exactly why a
# scribe rolls the pen through the corner instead. Turning it to `NIB_ANGLE[1]` on the way out
# gives the light arm real weight and a flat terminal, and keeps the contrast that tells the two
# strokes apart.
NIB_WIDTH = 0.42
NIB_ANGLE = (-22.0, -64.0)
# Where along the path the twist happens. It starts **before** the apex on purpose: a pen that
# only begins to turn at the corner runs its first centimetre of the return stroke along its own
# edge, and that shows as a hairline that steps into full weight partway down the arm.
NIB_TWIST = (0.30, 0.62)
BOW = (-4.0, 3.0)


def layout() -> dict:
    """Where everything sits, derived from the margin rather than written down twice.

    The group is centred vertically as a whole — the mark hangs above the first line, so
    centring the block of lines alone would leave the artwork sitting low in the square.
    """
    text_left = MARGIN + MARK_HEIGHT * MARK_REACH + GUTTER
    text_right = 1024 - MARGIN
    return {
        "text_left": text_left,
        "text_right": text_right,
        "first_line": 512 - (2 * LINE_PITCH + LINE_THICKNESS / 2 - MARK_HEIGHT / 2) / 2,
    }


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def quad(p0, p1, p2, n):
    out = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        out.append((
            u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
            u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1],
        ))
    return out


def bowed(start, end, bow, samples=120):
    """A path from start to end, bent perpendicular to itself — a hand rather than a ruler."""
    dx, dy = end[0] - start[0], end[1] - start[1]
    length = math.hypot(dx, dy) or 1
    nx, ny = -dy / length, dx / length
    mid = ((start[0] + end[0]) / 2 + nx * bow, (start[1] + end[1]) / 2 + ny * bow)
    return quad(start, mid, end, samples)


def nib_sweep(path, width, angle_start, angle_end):
    """The parallelograms a nib of `width` sweeps along `path`, twisting after the apex.

    The angle holds at `angle_start` until `NIB_TWIST[0]` of the way along and reaches
    `angle_end` by `NIB_TWIST[1]`. Rotating it evenly over the whole path instead puts the change
    where the stroke is heaviest, which shows as a step in the thick arm rather than as weight in
    the thin one.
    """
    faces = []
    for i in range(len(path) - 1):
        corners = []
        for j, point in enumerate((path[i], path[i + 1])):
            t = (i + j) / (len(path) - 1)
            turn = min(1.0, max(0.0, (t - NIB_TWIST[0]) / (NIB_TWIST[1] - NIB_TWIST[0])))
            theta = math.radians(angle_start + (angle_end - angle_start) * turn)
            dx, dy = math.cos(theta) * width / 2, math.sin(theta) * width / 2
            corners.append(((point[0] - dx, point[1] - dy), (point[0] + dx, point[1] + dy)))
        faces.append([corners[0][0], corners[0][1], corners[1][1], corners[1][0]])
    return faces


def mark() -> list[list[tuple[float, float]]]:
    """The diple: one movement of the pen, down into the apex and back out of it.

    One continuous path rather than two strokes, because that is how the sign is made and
    because it is what lets the apex join itself instead of being mitred together.
    """
    height = MARK_HEIGHT
    y = layout()["first_line"]
    tip = (MARGIN + height * MARK_REACH, y)
    top = (MARGIN, y - height / 2)
    bottom = (MARGIN + 12, y + height / 2)
    path = bowed(top, tip, BOW[0]) + bowed(tip, bottom, BOW[1])[1:]
    return nib_sweep(path, height * NIB_WIDTH, *NIB_ANGLE)


def page() -> list[list[tuple[float, float]]]:
    """The lines the mark stands against."""
    box = layout()
    left, right = box["text_left"], box["text_right"]
    ends = (right, right, left + (right - left) * LINE_SHORT)
    lines = []
    for index, end in enumerate(ends):
        y = box["first_line"] + LINE_PITCH * index
        lines.append([
            (left, y - LINE_THICKNESS / 2),
            (end, y - LINE_THICKNESS / 2),
            (end, y + LINE_THICKNESS / 2),
            (left, y + LINE_THICKNESS / 2),
        ])
    return lines


def artwork(plate, mark_colour, page_colour) -> Image.Image:
    canvas = Image.new("RGB", (CANVAS * SUPERSAMPLE, CANVAS * SUPERSAMPLE), plate)
    art = ImageDraw.Draw(canvas)
    for polygons, fill in ((page(), page_colour), (mark(), mark_colour)):
        for polygon in polygons:
            art.polygon([(x * SUPERSAMPLE, y * SUPERSAMPLE) for x, y in polygon], fill=fill)
    return canvas.resize((CANVAS, CANVAS), Image.LANCZOS)


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

    artwork(PLATE, colour, CREAM).save(icon_set / "icon.png")
    artwork(PLATE_DARK, colour, CREAM).save(icon_set / "icon-dark.png")
    # **Tinted has to be greyscale**: the system colours it by luminance from the reader's own
    # tint, and an accent mark under somebody else's hue reads as a mistake rather than a choice.
    # The page keeps the brighter value, so the hierarchy of the artwork survives the tinting.
    artwork((0, 0, 0), (150, 150, 150), (255, 255, 255)).save(icon_set / "icon-tinted.png")

    (icon_set / "Contents.json").write_text(json.dumps(contents(), indent=2) + "\n", encoding="utf-8")
    print(f"wrote {icon_set}")


def main() -> None:
    write(SUFFIX, PRIMARY)
    for name, accent in ACCENTS.items():
        write(f"{name}{SUFFIX}", accent)


if __name__ == "__main__":
    main()
