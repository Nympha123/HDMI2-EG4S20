#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""preview_bottom_bars.py - v45 底部 64 px（32 字幕 + 32 底栏）版面预览"""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RTL = os.path.join(ROOT, "rtl")

main = [int(l.strip(), 16) for l in open(os.path.join(RTL, "font_rom.hex")) if l.strip()]
ext = [int(l.strip(), 16) for l in open(os.path.join(RTL, "font_rom_ext.hex")) if l.strip()]

W, H = 640, 64
img = Image.new("RGB", (W, H), (0xDC, 0xEB, 0xF7))
px = img.load()
for y in range(32):
    for x in range(W):
        px[x, y] = (0xCF, 0xE3, 0xF4)
for x in range(W):
    px[x, 0] = (0x3F, 0x9E, 0xD8)     # SUB_Y 强调线
    px[x, 31] = (0x9C, 0xCB, 0xE8)    # BOT_Y-1 分隔线


def glyph(code9, x, y, color=(0x25, 0x44, 0x5C)):
    if code9 >= 0x100:
        rows = ext
        slot = code9 - 0x100
    else:
        rows = main
        slot = code9
    for row in range(16):
        bits = rows[slot * 16 + (15 - row)]
        for col in range(16):
            if bits & (1 << (15 - col)):
                xx, yy = x + col, y + row
                if 0 <= xx < W and 0 <= yy < H:
                    px[xx, yy] = color


def draw(codes, x, y, color=(0x25, 0x44, 0x5C)):
    for i, c in enumerate(codes):
        glyph(c, x + i * 16, y, color)


# 字幕：欢迎参观 · 曾侯乙编钟（y=424 -> 本图 y=8）
sub = [0xB0, 0xB1, 0xB2, 0xB3, 0x20, 0x100, 0x20, 0x101, 0x102, 0x103, 0x104, 0x105]
draw(sub, 10, 8)

# 底栏：1 / 6（y=456 -> 本图 y=40）
draw([0x31, 0x20, 0x2F, 0x20, 0x36], 8, 40)

# 底栏右侧：曾侯乙编钟展区（右对齐到 x=632）
zone = [0x101, 0x102, 0x103, 0x104, 0x105, 0x112, 0x13E]
draw(zone, 632 - len(zone) * 16, 40)

img.resize((W * 2, H * 2), Image.NEAREST).save(
    os.path.join(HERE, "_preview", "bottom_bars_v45.png"))
print("done")
