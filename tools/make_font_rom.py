#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_font_rom.py  -  build a new font_rom.hex for the subtitle/glyph ROM

Why: the project's font ROM (font_rom.hex, 176 slots, from FONT_ROM.mif) only
contains 63 CJK glyphs. This script renders ANY characters you need as 16x16
1-bpp glyphs and appends them as NEW slots, leaving the original 0x00..0xAF
slots completely untouched (so ASCII 0x20..0x7E and the 48 existing CJK glyphs
keep working exactly as before).

Slot / bit conventions (must match the RTL and the original mif):
    addr = slot * 16 + (15 - row)      row 0 = top line
    in each 16-bit word, bit15 = leftmost pixel
    -> word index slot*16+15 is the TOP row of that glyph

Usage:
    python make_font_rom.py <chars.txt> [out.hex] [--slot0 0xB0] [--depth 4096]

<chars.txt> may contain anything; every non-space character in it (deduped, in
first-appearance order) gets its own slot. All characters share one font.
A map file "<out>.map.txt" is written next to the hex: char -> slot.
"""
import sys, os

BASE_HEX = r"C:\Users\30685\Desktop\HDMI2\src\user_source\hdl_source\font_rom.hex"
FONT_CANDIDATES = [
    r"C:\Windows\Fonts\msyh.ttc",    # Microsoft YaHei
    r"C:\Windows\Fonts\msyhbd.ttc",
    r"C:\Windows\Fonts\simhei.ttf",  # SimHei
    r"C:\Windows\Fonts\simsun.ttc",  # SimSun
    r"C:\Windows\Fonts\Deng.ttf",    # DengXian
]

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = dict()
    for a in sys.argv[1:]:
        if a.startswith("--"):
            k, _, v = a[2:].partition("=")
            opts[k] = v
    if not args:
        print(__doc__); return 2
    chars_file = args[0]
    out_hex = args[1] if len(args) > 1 else os.path.join(
        os.path.dirname(BASE_HEX), "font_rom.hex")
    slot0 = int(opts.get("slot0", "0xB0"), 0)
    depth = int(opts.get("depth", "4096"))

    from PIL import Image, ImageDraw, ImageFont
    font_path = next((f for f in FONT_CANDIDATES if os.path.exists(f)), None)
    if font_path is None:
        print("no font found in", FONT_CANDIDATES); return 3
    print("font  :", font_path)

    # ---- read the existing base data (keep 0x00..0xAF untouched) ----
    base = [0] * depth
    if os.path.exists(BASE_HEX):
        lines = [l.strip() for l in open(BASE_HEX) if l.strip()]
        for i, l in enumerate(lines[:depth]):
            base[i] = int(l, 16)
    print("base  :", BASE_HEX, "->", len(lines), "words")

    # ---- characters to add (dedup, keep order, drop whitespace) ----
    text = open(chars_file, encoding="utf-8").read()
    seen, chars = set(), []
    for c in text:
        if c.isspace():
            continue
        if c not in seen:
            seen.add(c); chars.append(c)
    print("chars :", len(chars), "unique -> slots 0x%02X.." % slot0)
    if slot0 + len(chars) > 256:
        print("ERROR: more than %d characters would not fit in 8-bit slots"
              % (256 - slot0)); return 4

    # ---- render each char into a 16x16 cell ----
    # try a few pixel sizes and pick the largest that still fits the cell
    img = Image.new("L", (16, 16), 0)
    for n, ch in enumerate(chars):
        slot = slot0 + n
        best = None
        for px in (16, 15, 14, 13, 12, 18, 20):
            f = ImageFont.truetype(font_path, px)
            im = Image.new("L", (32, 32), 0)
            d = ImageDraw.Draw(im)
            d.text((16, 16), ch, font=f, fill=255, anchor="mm")
            bb = im.getbbox()
            if bb is None:
                continue
            w, h = bb[2] - bb[0], bb[3] - bb[1]
            if w <= 16 and h <= 16:
                best = (im, bb); break
        if best is None:
            print("  !! cannot fit:", ch); continue
        im, bb = best
        im = im.crop(bb)
        cell = Image.new("L", (16, 16), 0)
        cell.paste(im, ((16 - im.width) // 2, (16 - im.height) // 2))
        px = cell.load()
        for row in range(16):                 # row 0 = top
            w = 0
            for x in range(16):               # x 0 = left
                if px[x, row] > 100:
                    w |= (1 << (15 - x))
            base[slot * 16 + (15 - row)] = w

    # ---- write hex + map ----
    with open(out_hex, "w", encoding="ascii", newline="\n") as fh:
        for i in range(depth):
            fh.write("%04X\n" % base[i])
    map_path = out_hex + ".map.txt"
    with open(map_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("char\tslot\tcode_for_text_vector\n")
        for n, ch in enumerate(chars):
            fh.write("%s\t0x%02X\t8'h%02X\n" % (ch, slot0 + n, slot0 + n))
    print("wrote :", out_hex, "(%d words)" % depth)
    print("map   :", map_path)
    return 0

if __name__ == "__main__":
    sys.exit(main())
