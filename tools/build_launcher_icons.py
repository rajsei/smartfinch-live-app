"""Builds the launcher icons and start screens of both brands.

The app has two names — Schlaumeise in German, Smartfinch everywhere else —
and each has its own round badge. Android picks resources by the phone's
language, so there the launcher icon and the start screen follow it the way
the in-app logo does. An iPhone has exactly one icon; `pubspec.yaml` names it.

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

flutter_launcher_icons turns those into the default Android icon (the brand
`image_path_android` names) and the iOS icon (`image_path_ios`). The rest goes
straight into `android/app/src/main/res/`, because flutter_launcher_icons
knows nothing of languages:

  drawable-<density>/ic_splash.png
                               The Android 12+ start screen, default brand.
                               The system draws this icon on a 288 dp canvas
                               and masks it to the inner 192 dp circle. Its
                               background is `@color/ic_launcher_background`,
                               so it always sits on the launcher icon's colour.

  …-<locale>-…                 For each language in LOCALE_BRANDS, the whole
                               set again in its brand: legacy icon, adaptive
                               foreground, adaptive icon XML, background
                               colour and start screen.

The rim colour is sampled rather than hard-coded: it is the mark's outermost
ring, and reading it from the file is what keeps this honest when the artwork
is redrawn.
"""

from __future__ import annotations

import math
import os
import re
import shutil
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

#: Languages whose Android icon and start screen are not the default brand's.
#: Must agree with `AppLogo.assetFor` and the `values-<locale>` app names.
LOCALE_BRANDS = {"de": "schlaumeise"}

ANDROID_RES = "android/app/src/main/res"

DENSITIES = {
    "mdpi": 1.0,
    "hdpi": 1.5,
    "xhdpi": 2.0,
    "xxhdpi": 3.0,
    "xxxhdpi": 4.0,
}

#: Sizes in dp at mdpi, the same flutter_launcher_icons writes for the default.
LEGACY_ICON_DP = 48
ADAPTIVE_LAYER_DP = 108

#: The Android 12+ splash icon: a 288 dp canvas whose inner 192 dp circle is
#: all that shows. The round mark fills that circle, just inside its edge.
SPLASH_DP = 288
SPLASH_FILL = 0.66


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


def load_mark(source: str) -> Image.Image:
    """The brand mark, cropped to its own content.

    Cropped first so the padding is this script's decision rather than
    whatever margin the export happened to leave.
    """
    image = Image.open(source).convert("RGBA")
    return image.crop(image.getbbox())


def centred(mark: Image.Image, canvas: int, fill: float, background) -> Image.Image:
    """The mark scaled to [fill] of a [canvas]² square, centred on [background]."""
    size = int(canvas * fill)
    scaled = mark.resize((size, size), Image.LANCZOS)

    out = Image.new("RGBA", (canvas, canvas), background)
    offset = (canvas - size) // 2
    out.alpha_composite(scaled, (offset, offset))
    return out


def default_android_brand() -> str:
    """The brand `pubspec.yaml` builds the default Android icon from."""
    with open("pubspec.yaml", encoding="utf-8") as pubspec:
        match = re.search(
            r'^  image_path_android: "assets/images/launcher/([a-z]+)-icon\.png"',
            pubspec.read(),
            re.MULTILINE,
        )
    if match is None or match.group(1) not in BRANDS:
        raise SystemExit("pubspec.yaml: no image_path_android for a known brand")
    return match.group(1)


def res_dir(kind: str, *qualifiers: str) -> str:
    """`res/<kind>-<qualifiers…>`, created if missing."""
    path = os.path.join(ANDROID_RES, "-".join((kind,) + qualifiers))
    os.makedirs(path, exist_ok=True)
    return path


def build_inputs(brand: str) -> None:
    """The two 1024² inputs flutter_launcher_icons reads for [brand]."""
    image = Image.open(BRANDS[brand]).convert("RGBA")
    mark = load_mark(BRANDS[brand])
    rim = rim_colour(image)

    os.makedirs(OUT_DIR, exist_ok=True)

    opaque = centred(mark, CANVAS, FULL_BLEED, rim + (255,))
    opaque.convert("RGB").save(f"{OUT_DIR}/{brand}-icon.png")

    foreground = centred(mark, CANVAS, SAFE_ZONE, (0, 0, 0, 0))
    foreground.save(f"{OUT_DIR}/{brand}-icon-foreground.png")

    print(f"{brand}: rim #{rim[0]:02X}{rim[1]:02X}{rim[2]:02X}")


def build_splash(brand: str, *qualifiers: str) -> None:
    """The Android 12+ splash icon for [brand] at every density.

    Transparent around the mark: the background is the window's splash colour,
    which is the launcher icon's, so the start screen and the icon match.
    """
    mark = load_mark(BRANDS[brand])
    for density, scale in DENSITIES.items():
        splash = centred(mark, int(SPLASH_DP * scale), SPLASH_FILL, (0, 0, 0, 0))
        splash.save(os.path.join(res_dir("drawable", *qualifiers, density), "ic_splash.png"))


def build_locale(locale: str, brand: str) -> None:
    """Every launcher resource for [locale], in [brand].

    The adaptive icon XML is copied too, not just its layers: Android ranks the
    language above the API level, so a `-de` PNG with no `-de-anydpi-v26` beside
    it would beat the adaptive icon and German phones would get the flat one.
    """
    icon = Image.open(f"{OUT_DIR}/{brand}-icon.png").convert("RGB")
    foreground = Image.open(f"{OUT_DIR}/{brand}-icon-foreground.png").convert("RGBA")
    for density, scale in DENSITIES.items():
        legacy = int(LEGACY_ICON_DP * scale)
        icon.resize((legacy, legacy), Image.LANCZOS).save(
            os.path.join(res_dir("mipmap", locale, density), "ic_launcher.png")
        )
        layer = int(ADAPTIVE_LAYER_DP * scale)
        foreground.resize((layer, layer), Image.LANCZOS).save(
            os.path.join(res_dir("drawable", locale, density), "ic_launcher_foreground.png")
        )

    shutil.copyfile(
        os.path.join(ANDROID_RES, "mipmap-anydpi-v26", "ic_launcher.xml"),
        os.path.join(res_dir("mipmap", locale, "anydpi", "v26"), "ic_launcher.xml"),
    )

    rim = rim_colour(Image.open(BRANDS[brand]).convert("RGBA"))
    with open(os.path.join(res_dir("values", locale), "colors.xml"), "w", encoding="utf-8", newline="\n") as colors:
        colors.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<!-- Generated by tools/build_launcher_icons.py: the launcher icon's\n"
            f"     background in this language's brand ({brand}). -->\n"
            "<resources>\n"
            f'    <color name="ic_launcher_background">#{rim[0]:02X}{rim[1]:02X}{rim[2]:02X}</color>\n'
            "</resources>\n"
        )

    build_splash(brand, locale)
    print(f"android {locale}: {brand}")


if __name__ == "__main__":
    for brand in BRANDS:
        build_inputs(brand)

    default = default_android_brand()
    build_splash(default)
    print(f"android default: {default}")

    for locale, brand in LOCALE_BRANDS.items():
        build_locale(locale, brand)
