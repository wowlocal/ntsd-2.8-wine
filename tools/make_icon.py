#!/usr/bin/env python3
"""Build AppIcon.icns from the in-game logo (assets/logo_source.png).

The logo sits on a dark menu background with a bright white glow around it,
so we cut it out by flood-filling the dark background from the image border,
then place it on a macOS-style squircle with a "dawn" gradient.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "logo_source.png"
OUT_PNG = ROOT / "assets" / "AppIcon-1024.png"
OUT_ICNS = ROOT / "assets" / "AppIcon.icns"

CANVAS = 1024
BODY = 824            # Apple icon grid: 824px squircle on a 1024 canvas
SS = 4                # supersampling for smooth edges
LUM_THRESHOLD = 200   # the logo's white glow is brighter than this, the menu background is darker
CLOSE_R = 14          # radius used to seal gaps in the glow ring


def cut_out_logo(img: Image.Image) -> Image.Image:
    rgb = np.asarray(img.convert("RGB")).astype(np.float32)
    lum = rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    # Silhouette = the white glow ring, closed and hole-filled; drop small
    # bright specks (city lights) by keeping only sizeable components.
    yy, xx = np.mgrid[-CLOSE_R:CLOSE_R + 1, -CLOSE_R:CLOSE_R + 1]
    disk = xx ** 2 + yy ** 2 <= CLOSE_R ** 2
    bright = lum > LUM_THRESHOLD
    closed = ndimage.binary_closing(np.pad(bright, CLOSE_R), structure=disk)[CLOSE_R:-CLOSE_R, CLOSE_R:-CLOSE_R]
    filled = ndimage.binary_fill_holes(closed)
    labels, n = ndimage.label(filled)
    sizes = ndimage.sum(filled, labels, range(1, n + 1))
    keep = [i + 1 for i, s in enumerate(sizes) if s > filled.size * 0.004]
    fg = np.isin(labels, keep)
    mask = Image.fromarray((fg * 255).astype(np.uint8))
    # Close small holes, then soften the edge a little.
    mask = mask.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
    mask = mask.filter(ImageFilter.GaussianBlur(1.2))
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out.crop(mask.getbbox())


def squircle_mask(size: int, body: int) -> Image.Image:
    big = size * SS
    r = body * SS / 2
    c = big / 2
    n = 5.0
    t = np.linspace(0, 2 * np.pi, 2000)
    ct, st = np.cos(t), np.sin(t)
    xs = c + r * np.sign(ct) * np.abs(ct) ** (2 / n)
    ys = c + r * np.sign(st) * np.abs(st) ** (2 / n)
    m = Image.new("L", (big, big), 0)
    ImageDraw.Draw(m).polygon(list(zip(xs, ys)), fill=255)
    return m.resize((size, size), Image.LANCZOS)


def dawn_background(size: int) -> Image.Image:
    y = np.linspace(0, 1, size)[:, None]
    x = np.linspace(0, 1, size)[None, :]
    top = np.array([16, 18, 44], dtype=np.float32)       # night indigo
    mid = np.array([70, 30, 92], dtype=np.float32)       # violet
    low = np.array([236, 104, 52], dtype=np.float32)     # dawn orange
    t = np.clip(y, 0, 1)[..., None]
    col = np.where(t < 0.62,
                   top + (mid - top) * (t / 0.62),
                   mid + (low - mid) * ((t - 0.62) / 0.38))
    # Warm glow rising from the bottom centre.
    d = np.sqrt((x - 0.5) ** 2 + (y - 1.05) ** 2)[..., None]
    glow = np.clip(1 - d / 0.75, 0, 1) ** 2
    col = col + glow * np.array([255, 150, 70], dtype=np.float32) * 0.35
    col = np.broadcast_to(col, (size, size, 3))
    return Image.fromarray(np.clip(col, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def main() -> None:
    logo = cut_out_logo(Image.open(SRC))
    bg = dawn_background(CANVAS)

    target_w = int(BODY * 0.92)
    scale = target_w / logo.width
    logo = logo.resize((target_w, int(logo.height * scale)), Image.LANCZOS)
    lx = (CANVAS - logo.width) // 2
    ly = (CANVAS - logo.height) // 2 - 10

    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    sh = Image.new("RGBA", logo.size, (0, 0, 0, 170))
    sh.putalpha(logo.getchannel("A").point(lambda a: a * 170 // 255))
    shadow.alpha_composite(sh, (lx, ly + 14))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))

    art = bg.copy()
    art.alpha_composite(shadow)
    art.alpha_composite(logo, (lx, ly))

    # Subtle top highlight for depth.
    hl = Image.new("L", (CANVAS, CANVAS), 0)
    ImageDraw.Draw(hl).ellipse((-200, -760, CANVAS + 200, 420), fill=40)
    hl = hl.filter(ImageFilter.GaussianBlur(60))
    white = Image.new("RGBA", (CANVAS, CANVAS), (255, 255, 255, 0))
    white.putalpha(hl)
    art.alpha_composite(white)

    icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    icon.paste(art, (0, 0), squircle_mask(CANVAS, BODY))

    # Soft drop shadow under the squircle, like system icons.
    base = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    sq = squircle_mask(CANVAS, BODY).point(lambda a: a * 90 // 255)
    s2 = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 255))
    s2.putalpha(sq)
    base.alpha_composite(s2, (0, 12))
    base = base.filter(ImageFilter.GaussianBlur(14))
    base.alpha_composite(icon)
    base.save(OUT_PNG)

    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for pt in (16, 32, 128, 256, 512):
            for mul in (1, 2):
                px = pt * mul
                name = f"icon_{pt}x{pt}{'@2x' if mul == 2 else ''}.png"
                base.resize((px, px), Image.LANCZOS).save(iconset / name)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(OUT_ICNS)], check=True)
    print(f"wrote {OUT_ICNS}")


if __name__ == "__main__":
    sys.exit(main())
