#!/usr/bin/env python3
"""Build the Google Play feature graphic (1024x500) for Bondbell.

Run from anywhere:  /opt/homebrew/bin/python3 store_assets/feature_graphic/build_feature_graphic.py

Background: OpenArt gpt-image-2 output (openart/f3.png, 1792x1344), centre-cropped
to 1024:500 and scaled. All text is rendered here in Inter (OFL, store_assets/fonts/);
the model never draws text. Output: feature_graphic_1024x500.png (RGB, no alpha).
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
BG = HERE / "openart" / "f3.png"
FONT = HERE.parent / "fonts" / "Inter.ttf"
OUT = HERE / "feature_graphic_1024x500.png"

W, H = 1024, 500
SCALE = 4  # draw text at 4x, then downsample for clean edges
PAPER = (0xFA, 0xF7, 0xF0)
BRASS_LIGHT = (0xE2, 0xB8, 0x5C)

TITLE = "Bondbell"
TAGLINE = ["Check your bond numbers", "on your phone. No login."]


def inter(size: int, weight: int) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(FONT), size)
    f.set_variation_by_axes([min(32, max(14, size // SCALE)), weight])
    return f


def main() -> None:
    src = Image.open(BG).convert("RGB")
    sw, sh = src.size
    ch = round(sw * H / W)
    top = (sh - ch) // 2
    bg = src.crop((0, top, sw, top + ch)).resize((W * SCALE, H * SCALE), Image.LANCZOS)

    d = ImageDraw.Draw(bg)
    x = 72 * SCALE
    title_font = inter(92 * SCALE, 700)
    tag_font = inter(34 * SCALE, 500)

    # Vertically centre the text block on the canvas.
    t_box = d.textbbox((0, 0), TITLE, font=title_font)
    t_h = t_box[3] - t_box[1]
    line_h = round(34 * SCALE * 1.3)
    gap = 26 * SCALE
    block = t_h + gap + line_h * len(TAGLINE)
    y = (H * SCALE - block) // 2
    d.text((x, y - t_box[1]), TITLE, font=title_font, fill=PAPER)
    y += t_h + gap
    for line in TAGLINE:
        d.text((x, y), line, font=tag_font, fill=BRASS_LIGHT)
        y += line_h

    bg.resize((W, H), Image.LANCZOS).save(OUT)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
