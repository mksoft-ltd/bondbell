#!/usr/bin/env python3
"""Frame Bondbell's raw store captures per store_assets/SCREENSHOTS.md.

    python3 tools/publish/frame_screenshots.py <raw-root>

<raw-root> holds iphone/, ipad/ and android/ folders of raw captures named as
integration_test/screenshots_test.dart names them (01_result.png, ...).
Writes:
    ios/fastlane/screenshots/en-GB/<n>_iphone69.png   1320 x 2868
    ios/fastlane/screenshots/en-GB/<n>_ipad13.png     2064 x 2752
    android/fastlane/metadata/android/en-GB/images/phoneScreenshots/<n>.png  1080 x 1920

Plate, type, sizes and placement are the spec's "Framing" section; nothing
here is generated art. iOS sets come only from iOS captures and the Play set
only from Android captures.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parents[2]
FONT = REPO / "store_assets/fonts/Inter.ttf"
GREEN = (0x1F, 0x5C, 0x45)
PAPER = (0xFA, 0xF7, 0xF0)
BRASS = (0xE2, 0xB8, 0x5C)

# n -> (raw capture name, headline, iPad headline override, subheadline)
SHOTS = [
    (1, "01_result", "Your bond prizes, checked for you", None, "Saved once. Checked on your device."),
    (2, "02_onboarding_privacy", "No login. Your numbers stay on your phone.",
     "No login. Your numbers stay on your iPad.", "No account, no tracking."),
    (3, "03_home", "Know when new results are due", None, "One reminder a month. Nothing else."),
    (4, "04_holder", "Old paper certificates? Add them too", None, "Ranges or single numbers."),
    (5, "05_unclaimed", "Look for prizes never claimed", None, "Back to 1957."),
    (6, "06_history", "Every draw you've checked, together", None, "Part of Bondbell Pro."),
]

DEVICES = {
    # canvas, headline px, sub px, gap, top margin, scale of width, gap below sub
    "iphone": dict(size=(1320, 2868), head=96, sub=48, gap=24, top=150, scale=0.84, below=64,
                   out=lambda n: REPO / f"ios/fastlane/screenshots/en-GB/{n}_iphone69.png"),
    "ipad": dict(size=(2064, 2752), head=112, sub=56, gap=28, top=140, scale=0.80, below=72,
                 out=lambda n: REPO / f"ios/fastlane/screenshots/en-GB/{n}_ipad13.png"),
    "android": dict(size=(1080, 1920), head=68, sub=34, gap=18, top=96, scale=0.84, below=44,
                    out=lambda n: REPO / f"android/fastlane/metadata/android/en-GB/images/phoneScreenshots/{n}.png"),
}


def font(px: int, weight: int) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(FONT), px)
    f.set_variation_by_axes([32, weight])  # optical size (display), weight
    return f


def wrap(draw, text, f, max_w):
    """One line if it fits; otherwise the balanced two-line split (no orphans)."""
    words = text.split()
    if draw.textlength(text, font=f) <= max_w:
        return [text]
    splits = [(" ".join(words[:i]), " ".join(words[i:])) for i in range(1, len(words))]
    fits = [s for s in splits if max(draw.textlength(x, font=f) for x in s) <= max_w]
    if fits:
        return list(min(fits, key=lambda s: max(draw.textlength(x, font=f) for x in s)))
    lines, cur = [], ""
    for w in words:
        trial = f"{cur} {w}".strip()
        if draw.textlength(trial, font=f) <= max_w or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    lines.append(cur)
    if len(lines) > 2:
        raise SystemExit(f"headline needs {len(lines)} lines (max 2): {text!r}")
    return lines


def frame(raw: Path, device: str, headline: str, sub: str) -> Image.Image:
    d = DEVICES[device]
    W, H = d["size"]
    canvas = Image.new("RGB", (W, H), GREEN)
    draw = ImageDraw.Draw(canvas)
    hf, sf = font(d["head"], 700), font(d["sub"], 500)

    max_w = int(W * 0.88)
    y = d["top"]
    line_h = round(d["head"] * 1.15)
    for line in wrap(draw, headline, hf, max_w):
        draw.text((W / 2, y), line, font=hf, fill=PAPER, anchor="ma")
        y += line_h
    y += d["gap"] - (line_h - d["head"])
    if draw.textlength(sub, font=sf) > max_w:
        raise SystemExit(f"subheadline does not fit one line: {sub!r}")
    draw.text((W / 2, y), sub, font=sf, fill=BRASS, anchor="ma")
    y += d["sub"] + d["below"]

    shot = Image.open(raw).convert("RGB")
    if device == "ipad" and shot.size == (2064, 2752):
        # iPadOS 26 draws its window-resize corner glyph at the bottom right of
        # every simulator capture (system chrome, not app UI). Paint it out with
        # the page colour sampled just left of it.
        # Only the glyph's own (darker) pixels are replaced, each with the
        # pixel left of the box on the same row, so any FAB shadow survives.
        px = shot.load()
        for yy in range(2690, 2750):
            ref = px[2000, yy]
            for xx in range(2002, 2062):
                if sum(px[xx, yy]) < sum(ref) - 24:
                    px[xx, yy] = ref
    sw = round(W * d["scale"])
    sh = round(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    radius = round(sw * 0.06)
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), radius=radius, fill=255)
    x = (W - sw) // 2
    canvas.paste(shot, (x, y), mask)

    # 2 px paper outline at 25% opacity
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(overlay).rounded_rectangle((x, y, x + sw - 1, y + sh - 1), radius=radius,
                                              outline=PAPER + (64,), width=2)
    canvas = Image.alpha_composite(canvas.convert("RGBA"), overlay).convert("RGB")
    assert canvas.size == (W, H)
    return canvas


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO / "build/screenshots/publish"
    for device in DEVICES:
        for n, name, head, ipad_head, sub in SHOTS:
            raw = root / device / f"{name}.png"
            if not raw.exists():
                raise SystemExit(f"missing raw capture {raw}")
            text = ipad_head if (device == "ipad" and ipad_head) else head
            out = DEVICES[device]["out"](n)
            out.parent.mkdir(parents=True, exist_ok=True)
            frame(raw, device, text, sub).save(out, "PNG", optimize=True)
            print(f"{out.relative_to(REPO)}  <- {raw.name}")


if __name__ == "__main__":
    main()
