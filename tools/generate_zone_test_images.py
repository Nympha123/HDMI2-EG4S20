#!/usr/bin/env python3
"""Generate 640x480 24-bit BMP zone test images A01..D04.

Pure background colour + large label. Intended to be copied to the SD-card
root as A01.BMP ... D04.BMP (current firmware reads up to 4 images per zone).
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent / "test_images_zones"
OUT.mkdir(exist_ok=True)

FONT_BOLD = r"C:\Windows\Fonts\arialbd.ttf"
FONT_REG = r"C:\Windows\Fonts\arial.ttf"

ZONES = {
    "A": (178, 34, 34),     # firebrick
    "B": (30, 58, 138),     # deep blue
    "C": (22, 101, 52),     # dark green
    "D": (107, 33, 168),    # purple
}

W, H = 640, 480
LABEL_SIZE = 220
SMALL_SIZE = 48


def fit_font(path: str, text: str, max_width: int, start: int) -> ImageFont.FreeTypeFont:
    size = start
    while size > 40:
        f = ImageFont.truetype(path, size)
        b = f.getbbox(text)
        if (b[2] - b[0]) <= max_width:
            return f
        size -= 8
    return ImageFont.truetype(path, 40)


def main() -> None:
    small = ImageFont.truetype(FONT_REG, SMALL_SIZE)
    for zone, bg in ZONES.items():
        for n in range(1, 5):
            label = f"{zone}{n:02d}"
            img = Image.new("RGB", (W, H), bg)
            d = ImageDraw.Draw(img)
            # top-left zone label
            d.text((40, 28), f"ZONE {zone}", font=small, fill=(255, 255, 255))
            # large centred index
            f = fit_font(FONT_BOLD, label, 560, LABEL_SIZE)
            d.text((W // 2, H // 2 + 10), label, font=f, fill=(255, 255, 255),
                   anchor="mm")
            # bottom-right resolution hint (kept small)
            d.text((W - 40, H - 30), "640x480 TEST", font=small,
                   fill=(235, 235, 235), anchor="rs")
            path = OUT / f"{label}.BMP"
            img.save(path, "BMP")
            print(path)

    # 4x4 contact sheet for quick inspection
    tw, th = 320, 240
    sheet = Image.new("RGB", (tw * 4, th * 4), (24, 24, 24))
    for zi, zone in enumerate(ZONES):
        for n in range(1, 5):
            label = f"{zone}{n:02d}"
            im = Image.open(OUT / f"{label}.BMP").convert("RGB").resize((tw, th))
            sheet.paste(im, ((n - 1) * tw, zi * th))
    sheet.save(OUT / "contact_sheet.png")
    print(OUT / "contact_sheet.png")


if __name__ == "__main__":
    main()
