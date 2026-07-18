#!/usr/bin/env python3
"""Render the app icon — the Claude mascot under a menu-bar notch, on a warm
paper squircle — and build Resources/AppIcon.icns via iconutil."""
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent

# the real mascot proportions (body / eyes / hands / legs)
MASCOT = [
    ".oooooooo.",
    ".okooooko.",
    "oooooooooo",
    "oooooooooo",
    ".oooooooo.",
    ".oooooooo.",
    ".o.o..o.o.",
    ".o.o..o.o.",
]
CLAY = (221, 119, 91, 255)          # mascot clip orange #DD775B
INK = (13, 13, 15, 255)             # notch ink
PAPER_TOP = (247, 241, 227, 255)
PAPER_BOTTOM = (232, 224, 205, 255)
SPIN = (111, 185, 130, 255)         # activity green


def render(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    m = size * 0.09                        # Apple-ish icon grid margin
    r = size * 0.185                       # squircle radius

    # paper squircle with a soft vertical gradient
    grad = Image.new("L", (1, 256))
    for y in range(256):
        grad.putpixel((0, y), 255 - int(y * 0.10))
    grad = grad.resize((size, size))
    paper = Image.composite(
        Image.new("RGBA", (size, size), PAPER_TOP),
        Image.new("RGBA", (size, size), PAPER_BOTTOM), grad)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((m, m, size - m, size - m), radius=r, fill=255)
    img.paste(paper, (0, 0), mask)
    d = ImageDraw.Draw(img)

    # menu-bar band across the top, hugging the squircle corners
    band_h = size * 0.16
    band = Image.new("L", (size, size), 0)
    bd = ImageDraw.Draw(band)
    bd.rounded_rectangle((m, m, size - m, size - m), radius=r, fill=255)
    bd.rectangle((0, m + band_h, size, size), fill=0)
    img.paste(Image.new("RGBA", (size, size), INK), (0, 0), band)
    d = ImageDraw.Draw(img)

    # the notch pill bulging below the band
    pw, ph = size * 0.34, size * 0.075
    px0 = (size - pw) / 2
    d.rounded_rectangle((px0, m + band_h - ph, px0 + pw, m + band_h + ph),
                        radius=ph, fill=INK)

    # mascot — big, centered in the paper area, soft drop shadow
    cols, rows = len(MASCOT[0]), len(MASCOT)
    cell = (size * 0.52) / cols
    ix0 = (size - cell * cols) / 2
    iy0 = m + band_h + (size - m - band_h - m - cell * rows) / 2 + size * 0.02

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((ix0 + cell, iy0 + cell * (rows - 0.6),
                          ix0 + cell * (cols - 1), iy0 + cell * (rows + 0.6)),
                         radius=cell, fill=(20, 15, 8, 70))
    shadow = shadow.filter(ImageFilter.GaussianBlur(size * 0.015))
    img.alpha_composite(shadow)
    d = ImageDraw.Draw(img)

    for y, row in enumerate(MASCOT):
        for x, ch in enumerate(row):
            if ch == "o":
                d.rectangle((ix0 + x * cell, iy0 + y * cell,
                             ix0 + (x + 1) * cell, iy0 + (y + 1) * cell), fill=CLAY)
            elif ch == "k":
                d.rectangle((ix0 + x * cell, iy0 + y * cell,
                             ix0 + (x + 1) * cell, iy0 + (y + 1) * cell), fill=INK)

    # activity bars — the compact spinner, bottom right of the mascot
    bx = ix0 + cell * cols + cell * 0.5
    for i, h in enumerate((2.0, 3.2, 2.6)):
        d.rectangle((bx + i * cell * 0.55, iy0 + cell * (rows - h),
                     bx + i * cell * 0.55 + cell * 0.32, iy0 + cell * rows),
                    fill=SPIN)
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
