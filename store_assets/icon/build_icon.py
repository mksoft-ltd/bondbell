#!/usr/bin/env python3
"""Finish Bondbell's OpenArt bell mark into every icon asset, in code.

Run from the repo root:  /opt/homebrew/bin/python3 store_assets/icon/build_icon.py
Then:                    dart run flutter_launcher_icons

Input : store_assets/icon/openart/<CHOSEN>.png (raw OpenArt output, 1024 square,
        mark on a near-flat bottle-green field).
Output: store_assets/icon/
          app_icon_1024.png          iOS / flutter_launcher_icons master, RGB, no alpha
          adaptive_foreground.png    Android adaptive foreground, mark on transparency
          adaptive_monochrome.png    Android 13 themed-icon layer (white silhouette)
          play_icon_512.png          Google Play hi-res icon
          mark.png                   the keyed mark at native size (for the feature graphic)
          proofs/                    180 / 120 / 48 px and round-launcher-mask proofs

The model's green is a few RGB units off brand and slightly noisy, so the mark is
keyed off it and re-laid on the exact brand hex. Nothing here draws text.
"""
from __future__ import annotations

import os
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent
CHOSEN = ROOT / "openart" / "v1.png"
GREEN = (0x1F, 0x5C, 0x45)  # bottle green, BRAND.md
PAPER = (0xFA, 0xF7, 0xF0)

# Fraction of the iOS master the mark's height occupies.
MASTER_MARK_HEIGHT = 0.60
# flutter_launcher_icons insets the adaptive foreground by 16% per side, so the
# source canvas spans 68% of the 108 dp layer. The mask-safe circle is 66 dp
# (radius 0.3056 of the layer) -> radius 0.449 of the source canvas. Keep the
# farthest drawn pixel inside 0.37 for a visible margin.
ADAPTIVE_MAX_RADIUS = 0.37
ADAPTIVE_SIZE = 1024


def key_mark(src: Image.Image) -> Image.Image:
    """Return the mark as RGBA on transparency, with green fringes removed."""
    rgb = src.convert("RGB")
    w, h = rgb.size
    border = [rgb.getpixel((x, y)) for x in range(0, w, 8) for y in (2, h - 3)]
    border += [rgb.getpixel((x, y)) for y in range(0, h, 8) for x in (2, w - 3)]
    bg = tuple(sorted(c[i] for c in border)[len(border) // 2] for i in range(3))

    px = rgb.load()
    alpha = Image.new("L", (w, h), 0)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ap, op = alpha.load(), out.load()
    lo, hi = 22.0, 70.0  # RGB distance: noise floor -> fully mark
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            d = ((r - bg[0]) ** 2 + (g - bg[1]) ** 2 + (b - bg[2]) ** 2) ** 0.5
            a = 0.0 if d <= lo else 1.0 if d >= hi else (d - lo) / (hi - lo)
            if a <= 0:
                continue
            # Un-mix the background from edge pixels so no green halo remains.
            c = tuple(
                max(0, min(255, round((v - (1 - a) * bv) / a)))
                for v, bv in zip((r, g, b), bg)
            )
            ap[x, y] = round(a * 255)
            op[x, y] = (*c, round(a * 255))
    # Drop isolated specks: anything not near the solid body.
    solid = alpha.point(lambda v: 255 if v > 200 else 0).filter(ImageFilter.MaxFilter(9))
    out.putalpha(ImageChops.multiply(out.getchannel("A"), solid))
    return out.crop(out.getchannel("A").getbbox())


def max_radius(mark: Image.Image) -> float:
    """Distance from the mark's bbox centre to its farthest drawn pixel."""
    a = mark.getchannel("A").load()
    w, h = mark.size
    cx, cy = w / 2, h / 2
    r = 0.0
    for y in range(h):
        for x in range(w):
            if a[x, y] > 16:
                r = max(r, ((x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2) ** 0.5)
    return r


def place(mark: Image.Image, size: int, scale: float, bg) -> Image.Image:
    m = mark.resize((round(mark.width * scale), round(mark.height * scale)), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), bg)
    canvas.alpha_composite(m, ((size - m.width) // 2, (size - m.height) // 2))
    return canvas


def main() -> None:
    os.chdir(ROOT)
    proofs = ROOT / "proofs"
    proofs.mkdir(exist_ok=True)

    mark = key_mark(Image.open(CHOSEN))
    mark.save("mark.png")

    # iOS / store master: exact brand green, no alpha.
    master = place(mark, 1024, MASTER_MARK_HEIGHT * 1024 / mark.height, (*GREEN, 255))
    master = master.convert("RGB")
    master.save("app_icon_1024.png")

    # Play hi-res icon (Play asks for a 32-bit PNG; fully opaque).
    master.resize((512, 512), Image.LANCZOS).convert("RGBA").save("play_icon_512.png")

    # Android adaptive foreground + monochrome, scaled by computed clearance.
    r = max_radius(mark)
    fg_scale = ADAPTIVE_MAX_RADIUS * ADAPTIVE_SIZE / r
    fg = place(mark, ADAPTIVE_SIZE, fg_scale, (0, 0, 0, 0))
    fg.save("adaptive_foreground.png")
    mono = Image.new("RGBA", fg.size, (255, 255, 255, 0))
    mono.putalpha(fg.getchannel("A"))
    mono.save("adaptive_monochrome.png")
    print(f"mark {mark.size}, max radius {r:.0f}px, adaptive scale {fg_scale:.3f}")

    # Proofs: plain downscales of the master.
    for s in (180, 120, 48):
        master.resize((s, s), Image.LANCZOS).save(proofs / f"icon_{s}.png")

    # Round launcher mask: foreground at 68% of a 432 px layer (the package's
    # 16% inset), layer on brand green, masked to the 288 px visible circle,
    # with the 264 px safe circle drawn in paper for review.
    layer = Image.new("RGBA", (432, 432), (*GREEN, 255))
    inner = fg.resize((round(432 * 0.68),) * 2, Image.LANCZOS)
    off = (432 - inner.width) // 2
    layer.alpha_composite(inner, (off, off))
    circle = Image.new("L", (432 * 4, 432 * 4), 0)
    ImageDraw.Draw(circle).ellipse((72 * 4, 72 * 4, 360 * 4, 360 * 4), fill=255)
    circle = circle.resize((432, 432), Image.LANCZOS)
    round_proof = Image.new("RGBA", (432, 432), (255, 255, 255, 255))
    round_proof.paste(layer, (0, 0), circle)
    guide = round_proof.copy()
    ImageDraw.Draw(guide).ellipse((84, 84, 348, 348), outline=(*PAPER, 255), width=2)
    round_proof.crop((72, 72, 360, 360)).save(proofs / "round_mask_288.png")
    guide.crop((72, 72, 360, 360)).save(proofs / "round_mask_safe_guide.png")
    round_proof.crop((72, 72, 360, 360)).resize((48, 48), Image.LANCZOS).save(
        proofs / "round_mask_48.png"
    )
    # Monochrome proof: white silhouette on a dark themed-icon plate.
    mono_plate = Image.new("RGBA", (432, 432), (40, 44, 42, 255))
    mono_inner = mono.resize(inner.size, Image.LANCZOS)
    mono_plate.alpha_composite(mono_inner, (off, off))
    themed = Image.new("RGBA", (432, 432), (255, 255, 255, 255))
    themed.paste(mono_plate, (0, 0), circle)
    themed.crop((72, 72, 360, 360)).save(proofs / "monochrome_288.png")


if __name__ == "__main__":
    main()
