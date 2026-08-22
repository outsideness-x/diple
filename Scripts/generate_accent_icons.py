#!/usr/bin/env python3
"""Regenerates the alternate app icons, one per accent colour.

The icon is a colophon: a New York "d" in cream on near-black with a rule beneath it in the
accent. The accent is therefore the *only* thing that differs between the five sets, and the
brass `AppIcon` is the source every alternate is derived from — never the other way round.

Recolouring is exact rather than approximate. The rule is a solid bar over the plate, so each
of its pixels is a blend of exactly two colours; the blend factor is recovered by projecting the
pixel onto the plate→rule line and the new accent is laid back down with the same factor, which
leaves the anti-aliased ends of the rule intact. A hue rotation or a masked fill would damage
both. The "d" is left alone because it is cream in every accent, and it is safe to say so with a
band: the glyph ends at y=704 and the rule starts at y=835.

The tinted variant is copied byte for byte. It has to be greyscale — the system colours it by
luminance from the reader's own tint, and an accent rule under somebody else's hue reads as a
mistake rather than a choice — so there is nothing in it to recolour.

**The set names carry the artwork, not just the colour.** iOS never re-reads an alternate icon
whose name is already the one in force, so redrawing one under its old name leaves every reader
who had it selected looking at the previous artwork forever. `SUFFIX` is what records the
current design; the next redesign changes it here and in `DipleAccent.alternateIconName`, and
the two must not disagree.

Run from the repository root:

    python3 Scripts/generate_accent_icons.py
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

from PIL import Image

ASSETS = Path("diple/Assets.xcassets")
SOURCE = ASSETS / "AppIcon.appiconset"

# Must stay in sync with `DipleAccent` in diple/Theme/DipleAccent.swift: `alternateIconName` is
# the name of the .appiconset generated here, and brass is `nil` there because brass *is* the
# primary `AppIcon` and so has no alternate to generate.
SUFFIX = "Colophon"
ACCENTS = {
    "Lilac": "#DF9BE1",
    "Mint": "#6FD6B4",
    "Clay": "#D97757",
    "Periwinkle": "#8FA4F2",
}

# The brass of the source artwork. The plate under it differs between the standard and dark
# variants (dark is a couple of units deeper so the icon does not glow against a dark wallpaper),
# so the plate is read from the image rather than written down twice.
SOURCE_RULE = (200, 164, 92)
# Everything below this row is rule; the "d" ends well above it. See the module docstring.
RULE_TOP = 760

VARIANTS = ("icon.png", "icon-dark.png")
COPIED = ("icon-tinted.png",)


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def recolour_rule(source: Image.Image, target: tuple[int, int, int]) -> Image.Image:
    out = source.copy()
    pixels = out.load()
    # The plate colour, taken from a corner: the standard and dark artworks differ here.
    plate = pixels[0, 0][:3]

    axis = [SOURCE_RULE[i] - plate[i] for i in range(3)]
    axis_length_squared = sum(component * component for component in axis)
    delta = [target[i] - plate[i] for i in range(3)]

    for y in range(RULE_TOP, source.size[1]):
        for x in range(source.size[0]):
            r, g, b, a = pixels[x, y]
            projection = sum(
                (channel - plate[i]) * axis[i]
                for i, channel in enumerate((r, g, b))
            )
            t = min(max(projection / axis_length_squared, 0.0), 1.0)
            pixels[x, y] = (
                round(plate[0] + delta[0] * t),
                round(plate[1] + delta[1] * t),
                round(plate[2] + delta[2] * t),
                a,
            )
    return out


def contents() -> dict:
    """Mirrors the brass icon: one artwork per iOS 18 appearance."""
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


def main() -> None:
    for name, hex_value in ACCENTS.items():
        icon_set = ASSETS / f"AppIcon{name}{SUFFIX}.appiconset"
        icon_set.mkdir(parents=True, exist_ok=True)

        target = hex_to_rgb(hex_value)
        for variant in VARIANTS:
            artwork = Image.open(SOURCE / variant).convert("RGBA")
            recolour_rule(artwork, target).save(icon_set / variant)
        for variant in COPIED:
            shutil.copyfile(SOURCE / variant, icon_set / variant)

        (icon_set / "Contents.json").write_text(
            json.dumps(contents(), indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"wrote {icon_set}")


if __name__ == "__main__":
    main()
