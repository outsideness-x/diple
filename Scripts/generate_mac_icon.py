#!/usr/bin/env python3
"""Derives the macOS app icon from the iOS one.

Two things make a Mac icon different from the phone's, and both of them are why this script
exists rather than the asset catalog simply reusing `icon.png`:

**Shape.** Every icon in the Dock is a rounded square floating inside a transparent canvas with
air around it. An iOS icon is drawn edge to edge because the system masks it; on macOS nothing
masks anything, so the same file lands in the Dock as a hard-cornered rectangle noticeably
larger than its neighbours. Apple's grid puts the body at 824 pt inside a 1024 pt canvas, and
the corner radius of the Big Sur shape is a shade under 22.4% of the body.

**Sizes.** A single 1024 image is enough for iOS, which is why the set carries one. macOS wants
the whole ladder from 16 pt to 512 pt at both scales, and — this is the part that fails at
submission rather than at build time — **the 512 pt @2x rung is mandatory**. Without it the
`.icns` Xcode derives tops out at 512 px and App Store Connect rejects the upload for a missing
icon. Nothing in a local build says so.

Only the primary set is given a macOS ladder. The four accent alternates exist for the Home
Screen icon picker, and Mac Catalyst has no equivalent: `AppIconManager` is compiled out there
(see `#if !targetEnvironment(macCatalyst)`), so a Mac ladder under those names would be four
sets of artwork nothing can ever select.

Run from the repository root:

    python3 Scripts/generate_mac_icon.py
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw

SET = Path("diple/Assets.xcassets/AppIconColophon.appiconset")
SOURCE = SET / "icon.png"

CANVAS = 1024
# Apple's macOS icon grid: the body of a "large" square icon is 824 pt of a 1024 pt canvas.
BODY = 824
# The Big Sur superellipse, close enough at this radius that the difference is sub-pixel at
# every rung below 512.
CORNER_RATIO = 0.2237
# Drawn at this multiple and downsampled, so the corners are anti-aliased by resampling rather
# than by `ImageDraw`, which has none.
SUPERSAMPLE = 4

# (point size, scale). The 512 @2x rung is the one submission depends on.
RUNGS = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size * SUPERSAMPLE, size * SUPERSAMPLE), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size * SUPERSAMPLE - 1, size * SUPERSAMPLE - 1),
        radius=radius * SUPERSAMPLE,
        fill=255,
    )
    return mask.resize((size, size), Image.LANCZOS)


def build_master() -> Image.Image:
    source = Image.open(SOURCE).convert("RGB")
    body = source.resize((BODY, BODY), Image.LANCZOS)
    body.putalpha(rounded_mask(BODY, round(BODY * CORNER_RATIO)))

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    inset = (CANVAS - BODY) // 2
    canvas.paste(body, (inset, inset), body)
    return canvas


def filename(point: int, scale: int) -> str:
    return f"mac-{point}.png" if scale == 1 else f"mac-{point}@2x.png"


def main() -> None:
    master = build_master()

    for point, scale in RUNGS:
        pixels = point * scale
        master.resize((pixels, pixels), Image.LANCZOS).save(SET / filename(point, scale))

    contents = json.loads((SET / "Contents.json").read_text())
    # Whatever is already there for iOS stays; the macOS rungs are added beside it, and a rerun
    # replaces only its own.
    images = [image for image in contents["images"] if image.get("idiom") != "mac"]
    images += [
        {
            "filename": filename(point, scale),
            "idiom": "mac",
            "scale": f"{scale}x",
            "size": f"{point}x{point}",
        }
        for point, scale in RUNGS
    ]
    contents["images"] = images
    (SET / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")

    print(f"wrote {len(RUNGS)} macOS rungs into {SET}")


if __name__ == "__main__":
    main()
