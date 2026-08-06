#!/usr/bin/env python3
"""Regenerates the alternate app icons, one per accent colour.

The mark on the icon is a solid shape over a near-black plate, so every pixel is a blend
between exactly two colours. Recolouring is therefore exact rather than approximate: the
blend factor of a pixel is recovered by projecting it onto the background→foreground line,
and the new colour is laid back down with the same factor. Anti-aliased edges survive
untouched, which a hue rotation or a masked fill would both damage.

Run from the repository root after changing `ACCENTS`:

    python3 Scripts/generate_accent_icons.py

The pink `AppIcon` is the source of truth and is never rewritten.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

ASSETS = Path("diple/Assets.xcassets")
SOURCE_ICON = ASSETS / "AppIcon.appiconset" / "diple-icon.png"

# Must stay in sync with `DipleAccent` in diple/Theme/DipleAccent.swift: the enum's
# `alternateIconName` is the name of the .appiconset generated here.
ACCENTS = {
    "Mint": "#6FD6B4",
    "Clay": "#D97757",
    "Periwinkle": "#8FA4F2",
}

BACKGROUND = (9, 9, 9)
FOREGROUND = (223, 155, 225)


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def recolour(source: Image.Image, target: tuple[int, int, int]) -> Image.Image:
    pixels = source.load()
    out = Image.new("RGBA", source.size)
    out_pixels = out.load()

    axis = [FOREGROUND[i] - BACKGROUND[i] for i in range(3)]
    axis_length_squared = sum(component * component for component in axis)
    delta = [target[i] - BACKGROUND[i] for i in range(3)]

    for y in range(source.size[1]):
        for x in range(source.size[0]):
            r, g, b, a = pixels[x, y]
            projection = sum(
                (channel - BACKGROUND[i]) * axis[i]
                for i, channel in enumerate((r, g, b))
            )
            t = min(max(projection / axis_length_squared, 0.0), 1.0)
            out_pixels[x, y] = (
                round(BACKGROUND[0] + delta[0] * t),
                round(BACKGROUND[1] + delta[1] * t),
                round(BACKGROUND[2] + delta[2] * t),
                a,
            )
    return out


def contents(slug: str) -> dict:
    """Mirrors the pink icon: one artwork used for all three iOS 18 appearances."""
    return {
        "images": [
            {
                "filename": f"diple-icon-{slug}.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            },
            {
                "appearances": [{"appearance": "luminosity", "value": "dark"}],
                "filename": f"diple-icon-{slug}-dark.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            },
            {
                "appearances": [{"appearance": "luminosity", "value": "tinted"}],
                "filename": f"diple-icon-{slug}-tinted.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            },
        ],
        "info": {"author": "xcode", "version": 1},
    }


def main() -> None:
    source = Image.open(SOURCE_ICON).convert("RGBA")

    for name, hex_value in ACCENTS.items():
        slug = name.lower()
        icon_set = ASSETS / f"AppIcon{name}.appiconset"
        icon_set.mkdir(parents=True, exist_ok=True)

        artwork = recolour(source, hex_to_rgb(hex_value))
        for suffix in ("", "-dark", "-tinted"):
            artwork.save(icon_set / f"diple-icon-{slug}{suffix}.png")

        (icon_set / "Contents.json").write_text(
            json.dumps(contents(slug), indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"wrote {icon_set}")


if __name__ == "__main__":
    main()
