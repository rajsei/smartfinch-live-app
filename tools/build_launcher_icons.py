"""Builds the launcher-icon inputs from the two brand marks.

The app has two names — Schlaumeise in German, Smartfinch everywhere else —
and each has its own round badge. A launcher icon cannot follow the device
language the way the in-app logo does, so this produces a full set for *both*
and `pubspec.yaml` points at one of them. Switching brands is a one-line change
there, not a redraw here.

Run it when a brand mark changes:

    python tools/build_launcher_icons.py
    dart run flutter_launcher_icons

What it makes, per brand, under `assets/images/launcher/`:

  <brand>-icon.png             1024², opaque. iOS and the legacy Android icon
                               both refuse transparency, so the mark is
                               composited onto its own outer-rim colour rather
                               than onto whatever the toolchain would pick.

  <brand>-icon-foreground.png  1024², transparent. Android's adaptive icon
                               masks this to a circle, a squircle or a rounded
                               square depending on the launcher, and crops
                               about a quarter of it in the process — so the
                               mark is scaled to the safe zone and centred,
                               and the background colour beneath it is the
                               mark's own rim, which is what makes the crop
                               invisible whatever shape it takes.

The rim colour is sampled rather than hard-coded: it is the mark's outermost
ring, and reading it from the file is what keeps this honest when the artwork
is redrawn.
"""

from __future__ import annotations

import math
import os
from collections import Counter

from PIL import Image

CANVAS = 1024

#: How much of the canvas the mark may fill on the adaptive foreground.
#: Android guarantees only the inner 66/108 of the layer survives every mask.
SAFE_ZONE = 0.66

#: The opaque icon has no mask to survive, so the mark can be nearly flush.
FULL_BLEED = 0.94

BRANDS = {
    "smartfinch": "assets/images/smartfinch_logo.png",
    "schlaumeise": "assets/images/schlaumeise_logo.png",
}

OUT_DIR = "assets/images/launcher"


def rim_colour(image: Image.Image) -> tuple[int, int, int]:
    """The mark's outermost ring colour.

    Sampled around the disc just inside its edge. That is the colour the badge
    ends in, so it is the one an icon should sit on: a mask that crops into the
    artwork then crops into more of the same colour.
    """
    box = image.getbbox()
    cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
    radius = (box[2] - box[0]) / 2

    counts: Counter[tuple[int, int, int]] = Counter()
    for step in range(720):
        angle = step * math.pi / 360
        for fraction in (0.975, 0.99):
            x = int(cx + math.cos(angle) * radius * fraction)
            y = int(cy + math.sin(angle) * radius * fraction)
            pixel = image.getpixel((x, y))
            if pixel[3] > 250:
                counts[pixel[:3]] += 1
    return counts.most_common(1)[0][0]


def centred(mark: Image.Image, fill: float, background) -> Image.Image:
    """The mark scaled to [fill] of the canvas, centred on [background]."""
    size = int(CANVAS * fill)
    scaled = mark.resize((size, size), Image.LANCZOS)

    canvas = Image.new("RGBA", (CANVAS, CANVAS), background)
    offset = (CANVAS - size) // 2
    canvas.alpha_composite(scaled, (offset, offset))
    return canvas


def build(brand: str, source: str) -> None:
    image = Image.open(source).convert("RGBA")
    # Cropped to its own content first, so the padding below is this script's
    # decision rather than whatever margin the export happened to leave.
    mark = image.crop(image.getbbox())
    rim = rim_colour(image)

    os.makedirs(OUT_DIR, exist_ok=True)

    opaque = centred(mark, FULL_BLEED, rim + (255,))
    opaque.convert("RGB").save(f"{OUT_DIR}/{brand}-icon.png")

    foreground = centred(mark, SAFE_ZONE, (0, 0, 0, 0))
    foreground.save(f"{OUT_DIR}/{brand}-icon-foreground.png")

    print(
        f"{brand}: rim #{rim[0]:02X}{rim[1]:02X}{rim[2]:02X} — "
        f"put that in pubspec's adaptive_icon_background"
    )


if __name__ == "__main__":
    for brand, source in BRANDS.items():
        build(brand, source)
