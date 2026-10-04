#!/usr/bin/env python3
"""Test patterns for measuring how the frame's panel really looks (README.md).

  python3 tools/calibration/make_patterns.py        writes tools/calibration/patterns/

"Shown as is" patterns use only the panel's six inks (the deviceColor values in
shared/presets.json) and go straight to the screen with `console.py show`: they measure
the inks and how dots of two inks mix. The others are ordinary pictures with known
colours, added in the app like a photo, to compare what Automatic sends with its preview.
Needs Pillow and numpy.
"""
import json
import pathlib

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = pathlib.Path(__file__).resolve().parent / "patterns"
W, H = 800, 480

presets = json.loads((ROOT / "shared/presets.json").read_text())
INK = {
    c["name"]: tuple(int(c["deviceColor"][i : i + 2], 16) for i in (1, 3, 5))
    for c in next(p for p in presets["palettes"] if p["id"] == "spectra6")["colors"]
}
K, WH = INK["black"], INK["white"]

FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"
try:
    small = ImageFont.truetype(FONT, 13)
    title = ImageFont.truetype(FONT, 18)
except OSError:
    small = title = ImageFont.load_default()

# 4×4 Bayer thresholds: a coverage of n/16 of ink A over B, as evenly spread as possible.
BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]])


def canvas(text):
    img = Image.new("RGB", (W, H), WH)
    d = ImageDraw.Draw(img)
    d.fontmode = "1"  # no anti-aliasing: only the inks' own colours
    d.rectangle([0, 0, W - 1, H - 1], outline=K, width=4)  # the picture's edges, for measuring
    d.text((16, 10), text, font=title, fill=K)
    return img, d


def label(d, x, y, w, text):
    tw = d.textlength(text, font=small)
    d.text((x + (w - tw) / 2, y), text, font=small, fill=K)


def mix(img, x, y, w, h, a, b, coverage, stripes=False):
    """Ink a over ink b at `coverage` (0–1), dot by dot."""
    px = np.array(img)
    yy, xx = np.mgrid[0:h, 0:w]
    on = (xx % 2 == 0) if stripes else (BAYER4[yy % 4, xx % 4] < round(coverage * 16))
    px[y : y + h, x : x + w] = np.where(on[..., None], a, b)
    img.paste(Image.fromarray(px.astype(np.uint8)))


def inks():
    img, d = canvas("1  Inks, shown as is")
    names = ["white", "black", "red", "yellow", "green", "blue"]
    pw, ph, gap = 220, 165, 35
    for i, n in enumerate(names):
        x, y = gap + (i % 3) * (pw + gap), 52 + (i // 3) * (ph + 50)
        d.rectangle([x, y, x + pw - 1, y + ph - 1], fill=INK[n], outline=K if n == "white" else INK[n], width=2)
        label(d, x, y + ph + 8, pw, n)
    return img


def mixes():
    img, d = canvas("2  Two inks mixed dot by dot, shown as is")
    R, Y, G, B = INK["red"], INK["yellow"], INK["green"], INK["blue"]
    rows = [
        [(K, WH, 1 / 8, "black 1/8"), (K, WH, 1 / 4, "black 1/4"), (K, WH, 1 / 2, "black 1/2"),
         (K, WH, 3 / 4, "black 3/4"), (K, WH, 7 / 8, "black 7/8"), (K, WH, 1 / 2, "black 1/2 lines")],
        [(R, WH, 1 / 2, "red+white"), (Y, WH, 1 / 2, "yellow+white"), (G, WH, 1 / 2, "green+white"),
         (B, WH, 1 / 2, "blue+white"), (R, WH, 1 / 4, "red 1/4+white"), (B, WH, 1 / 4, "blue 1/4+white")],
        [(R, K, 1 / 2, "red+black"), (Y, K, 1 / 2, "yellow+black"), (G, K, 1 / 2, "green+black"),
         (B, K, 1 / 2, "blue+black"), (R, K, 1 / 4, "red 1/4+black"), (Y, K, 1 / 4, "yellow 1/4+black")],
        [(R, Y, 1 / 2, "red+yellow"), (R, B, 1 / 2, "red+blue"), (B, Y, 1 / 2, "blue+yellow"),
         (G, R, 1 / 2, "green+red"), (B, G, 1 / 2, "blue+green"), (G, Y, 1 / 2, "green+yellow")],
    ]
    pw, ph, gx = 110, 86, 20
    for r, row in enumerate(rows):
        for c, (a, b, cov, text) in enumerate(row):
            x, y = gx + c * (pw + gx), 40 + r * 109
            mix(img, x, y, pw, ph, a, b, cov, stripes=text.endswith("lines"))
            label(d, x, y + ph + 3, pw, text)
    return img


def chart(name, patches, cols, bg):
    """Flat patches on a background, no text (the app dithers these like a photo)."""
    img = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(img)
    rows = (len(patches) + cols - 1) // cols
    gap = 14
    pw, ph = (W - (cols + 1) * gap) // cols, (H - (rows + 1) * gap) // rows
    for i, c in enumerate(patches):
        x, y = gap + (i % cols) * (pw + gap), gap + (i // cols) * (ph + gap)
        d.rectangle([x, y, x + pw - 1, y + ph - 1], fill=c)
    return img


# X-Rite ColorChecker Classic, sRGB (D65), row by row.
COLORCHECKER = [
    (115, 82, 68), (194, 150, 130), (98, 122, 157), (87, 108, 67), (133, 128, 177), (103, 189, 170),
    (214, 126, 44), (80, 91, 166), (193, 90, 99), (94, 60, 108), (157, 188, 64), (224, 163, 46),
    (56, 61, 150), (70, 148, 73), (175, 54, 60), (231, 199, 31), (187, 86, 149), (8, 133, 161),
    (243, 243, 242), (200, 200, 200), (160, 160, 160), (122, 122, 121), (85, 85, 85), (52, 52, 52),
]

# Colours people judge by memory: skin (light to dark), sky, foliage, pastels, earth.
MEMORY = [
    (255, 219, 172), (241, 194, 125), (224, 172, 105), (198, 134, 66), (141, 85, 36), (92, 51, 23),
    (135, 206, 235), (100, 149, 237), (70, 130, 180), (34, 139, 34), (107, 142, 35), (85, 107, 47),
    (255, 209, 220), (204, 229, 255), (255, 250, 205), (160, 82, 45), (210, 180, 140), (128, 128, 0),
]


def ramps():
    """A smooth grey ramp, an 11-step grey wedge, white → pure colour ramps, and a hue sweep."""
    px = np.full((H, W, 3), 255, np.float64)
    x = np.linspace(0, 1, W)
    px[0:60] = (x * 255)[None, :, None]
    for i in range(11):
        x0, x1 = round(i * W / 11), round((i + 1) * W / 11)
        px[64:124, x0:x1] = round(i * 25.5)
    hues = [(255, 0, 0), (255, 255, 0), (0, 255, 0), (0, 255, 255), (0, 0, 255), (255, 0, 255)]
    y = 130
    for hue in hues:
        px[y : y + 44] = (255 + (np.array(hue, float)[None, :] - 255) * x[:, None])[None]
        y += 48
    hsv = np.stack([x, np.ones(W), np.ones(W)], -1)
    px[y : y + 44] = (np.array(Image.fromarray((hsv * 255).astype(np.uint8)[None], "HSV").convert("RGB"))[0])[None]
    return Image.fromarray(px.round().astype(np.uint8))


def main():
    OUT.mkdir(exist_ok=True)
    out = {
        "1-inks.png": inks(),
        "2-mixes.png": mixes(),
        "photo-colorchecker.png": chart("colorchecker", COLORCHECKER, 6, (0, 0, 0)),
        "photo-ramps.png": ramps(),
        "photo-memory-colours.png": chart("memory", MEMORY, 6, (128, 128, 128)),
    }
    for name, img in out.items():
        if not name.startswith("photo-"):
            used = {tuple(c) for c in np.array(img).reshape(-1, 3)}
            assert used <= set(INK.values()), f"{name}: colours outside the inks: {used - set(INK.values())}"
        if not name.startswith("photo-"):
            # Indexed, like the app's PNGs (only the inks in the palette).
            pal = Image.new("P", (1, 1))
            pal.putpalette([v for c in INK.values() for v in c])
            img = img.quantize(palette=pal, dither=Image.Dither.NONE)
        img.save(OUT / name, optimize=True)
        print(OUT / name)


if __name__ == "__main__":
    main()
