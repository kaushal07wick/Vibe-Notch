#!/usr/bin/env python3
"""Render the app icon — concept C: the watching eye inside the notch pill,
green approval check beneath, on warm paper. All artwork original.
Builds Resources/AppIcon.icns via iconutil."""
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent

INK = (13, 13, 15, 255)
PAPER_TOP = (247, 241, 227, 255)
PAPER_BOTTOM = (232, 224, 205, 255)
GREEN = (111, 185, 130, 255)
BLUE = (79, 125, 240, 255)
WHITE = (244, 246, 238, 255)
GREY = (60, 64, 70, 255)

EYE = [
    "..oooo..",
    ".oooooo.",
    "ooWWkkoo",
    "ooWWkkoo",
    ".oooooo.",
    "..oooo..",
]
CHECK = [
    "......o",
    ".....oo",
    "o...oo.",
    "oo.oo..",
    ".ooo...",
    "..o....",
]


def _grid(d, size, rows, scale, cy_frac, colors):
    cols = len(rows[0])
    n = len(rows)
    cell = (size * scale) / cols
    x0 = (size - cell * cols) / 2
    y0 = size * cy_frac - (cell * n) / 2
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            c = colors.get(ch)
            if c:
                d.rectangle((x0 + x * cell, y0 + y * cell,
                             x0 + (x + 1) * cell, y0 + (y + 1) * cell), fill=c)


def render(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    m = size * 0.09
    r = size * 0.185

    # warm paper squircle with a soft vertical gradient
    grad = Image.new("L", (1, 256))
    for y in range(256):
        grad.putpixel((0, y), 255 - y)
    grad = grad.resize((size, size))
    paper = Image.composite(
        Image.new("RGBA", (size, size), PAPER_TOP),
        Image.new("RGBA", (size, size), PAPER_BOTTOM), grad)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((m, m, size - m, size - m), radius=r, fill=255)
    img.paste(paper, (0, 0), mask)
    d = ImageDraw.Draw(img)

    # the notch pill, floating near the top, soft shadow
    pw, ph = size * 0.62, size * 0.30
    px0, py0 = (size - pw) / 2, size * 0.14
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (px0, py0 + size * 0.015, px0 + pw, py0 + ph + size * 0.015),
        radius=ph * 0.35, fill=(20, 15, 8, 80))
    shadow = shadow.filter(ImageFilter.GaussianBlur(size * 0.015))
    img.alpha_composite(shadow)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((px0, py0, px0 + pw, py0 + ph), radius=ph * 0.35, fill=INK)

    # the watching eye inside the pill
    _grid(d, size, EYE, 0.30, py0 / size + (ph / size) / 2,
          {"o": GREY, "W": WHITE, "k": BLUE})

    # green approval check on the paper below
    _grid(d, size, CHECK, 0.34, 0.68, {"o": GREEN})
    return img


def main() -> None:
    out = ROOT / "Resources" / "AppIcon.icns"
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for pts in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                px = pts * scale
                name = f"icon_{pts}x{pts}" + ("@2x" if scale == 2 else "") + ".png"
                render(px).save(iconset / name)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(out)], check=True)
    print(f"wrote {out}")


if __name__ == "__main__":
    sys.exit(main())
