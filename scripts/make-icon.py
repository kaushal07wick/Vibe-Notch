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


GHOST = [
    "...oooooo...",
    "..oblbbbbbo.",
    ".oblbbbbbbbo",
    ".obbbbbbbbbo",
    ".obbWWbbWWbo",
    ".obbkWbbkWbo",
    ".obpbbbbbpbo",
    ".obbbbbbbbdo",
    ".obbbbbbbddo",
    ".obbbbbbbddo",
    ".obbobbobbo.",
    "..oo.oo.oo..",
]
GHOST_COLORS = {"o": (42, 63, 122, 255), "b": (122, 167, 255, 255), "l": (185, 210, 255, 255),
                "d": (79, 120, 216, 255), "p": (255, 159, 192, 255),
                "W": (255, 255, 255, 255), "k": (16, 24, 48, 255)}


def render(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    m = size * 0.09
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((m, m, size - m, size - m), radius=size * 0.185, fill=255)
    grad = Image.new("L", (1, 256))
    for y in range(256):
        grad.putpixel((0, y), 255 - y)
    bg = Image.composite(Image.new("RGBA", (size, size), (24, 28, 44, 255)),
                         Image.new("RGBA", (size, size), (9, 10, 14, 255)), grad.resize((size, size)))
    img.paste(bg, (0, 0), mask)
    _grid(ImageDraw.Draw(img), size, GHOST, 0.56, 0.5, GHOST_COLORS)
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
