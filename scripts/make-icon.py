#!/usr/bin/env python3
"""Render the app icon (pixel invader in a dark notch pill on a light squircle)
and build Resources/AppIcon.icns via iconutil."""
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
INVADER = [
    "..X.....X..",
    "...X...X...",
    "..XXXXXXX..",
    ".XX.XXX.XX.",
    "XXXXXXXXXXX",
    "X.XXXXXXX.X",
    "X.X.....X.X",
    "...XX.XX...",
]
CLAY = (217, 119, 66, 255)          # claude clay
INK = (13, 13, 15, 255)             # panel ink
SQUIRCLE = (241, 234, 217, 255)     # paper


def rounded(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def render(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    m = size * 0.09                       # squircle margin (icon grid-ish)
    rounded(d, (m, m, size - m, size - m), radius=size * 0.20, fill=SQUIRCLE)
    # notch pill hanging from the squircle top
    pw, ph = size * 0.52, size * 0.30
    px0, py0 = (size - pw) / 2, m
    rounded(d, (px0, py0 - size * 0.05, px0 + pw, py0 + ph), radius=size * 0.10, fill=INK)
    # pixel invader centered in the pill
    cell = pw / 16
    ix0 = px0 + (pw - cell * len(INVADER[0])) / 2
    iy0 = py0 + (ph - cell * len(INVADER)) / 2 - size * 0.01
    for y, row in enumerate(INVADER):
        for x, ch in enumerate(row):
            if ch == "X":
                d.rectangle((ix0 + x * cell, iy0 + y * cell,
                             ix0 + (x + 1) * cell, iy0 + (y + 1) * cell), fill=CLAY)
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
