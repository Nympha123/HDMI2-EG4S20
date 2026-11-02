#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""preview_directory_v79.py - 离线预览目录页左下角新增的「展区简介」三行

把 directory_ui.v 里的 y 坐标 / 文案 / 字模按同一规则重放，输出 PNG，
用来在没有板子的情况下检查：文字有没有压到边框、行距是否均匀、是否超宽。
"""
import os
import re
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RTL = os.path.join(ROOT, "rtl")
VDIR = os.path.join(HERE, "directory_params.vh")
EXT_HEX = os.path.join(RTL, "font_rom_ext.hex")

C_BG = (0xEE, 0xF5, 0xFC)
C_PANEL = (0xFF, 0xFF, 0xFF)
C_TEXT = (0x25, 0x44, 0x5C)

# 与 directory_ui.v 一致
X0 = 24
LEFT_BOX = (10, 202, 284, 448)
BORDER = (60, 158, 216)      # z_half_c (青)
ROWS = [
    # (name, ystart, t_row offset)
    ("DIR_N0", 218, 10),
    ("DIR_D0", 262, 6),
    ("DIR_Z0L0", 290, 2),
    ("DIR_Z0L1", 322, 2),
    ("DIR_Z0L2", 354, 2),
    ("DIR_HINT", 406, 6),
]


def load_params():
    txt = open(VDIR, encoding="utf-8").read()
    vals = {}
    for m in re.finditer(r"localparam \[(\d+):0\] (\w+) = \d+'h([0-9A-Fa-f]+);", txt):
        vals[m.group(2)] = int(m.group(3), 16)
    for m in re.finditer(r"localparam \[4:0\] (\w+_L) = 5'd(\d+);", txt):
        vals[m.group(1)] = int(m.group(2))
    return vals


def load_font():
    words = [int(l.strip(), 16) for l in open(EXT_HEX) if l.strip()]
    assert len(words) == 2048, len(words)
    return words


def glyph_rows(font, code):
    idx = code - 0x100
    return font[idx * 16:(idx + 1) * 16]


def draw_line(img, px, font, vec, n, y, dy, color=C_TEXT):
    for i in range(n):
        code = (vec >> (i * 9)) & 0x1FF
        if code in (0x00, 0x20):
            continue
        rows = glyph_rows(font, code)
        x = X0 + i * 16
        for r in range(16):
            w = rows[15 - r]
            for c in range(16):
                if (w >> (15 - c)) & 1:
                    img.putpixel((x + c, y + r), color)


def main():
    p = load_params()
    font = load_font()
    zone = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    img = Image.new("RGB", (640, 480), C_BG)
    d = ImageDraw.Draw(img)
    d.rectangle(LEFT_BOX, fill=C_PANEL, outline=BORDER, width=2)
    # 徽标占位
    d.rectangle((14, 14, 280, 188), fill=(247, 250, 253), outline=BORDER, width=2)
    d.rectangle((39, 20, 255, 182), fill=(150, 200, 230), outline=BORDER, width=1)
    d.text((60, 90), "ZONE BADGE", fill=C_TEXT)
    # 标题下分隔线
    d.line((24, 244, 260, 245), fill=BORDER)

    for base, y, dy in ROWS:
        name = base.replace("0", str(zone)) if base.startswith("DIR_N0") or base.startswith("DIR_D0") else base
        nm = base
        if nm == "DIR_N0":
            nm = "DIR_N%d" % zone
        elif nm == "DIR_D0":
            nm = "DIR_D%d" % zone
        elif nm.startswith("DIR_Z0"):
            nm = nm.replace("DIR_Z0", "DIR_Z%d" % zone)
        vec, n = p[nm], p[nm + "_L"]
        draw_line(img, None, font, vec, n, y, dy)
        # 行基线参考
        d.line((24, y + 15, 279, y + 15), fill=(230, 236, 242))

    img.resize((img.width * 2, img.height * 2), Image.NEAREST).save(
        os.path.join(HERE, "_dir_preview_z%d.png" % zone))
    print("ok zone", zone)


if __name__ == "__main__":
    main()
