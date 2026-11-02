#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""preview_sysinfo.py - 用 font_rom.hex 复刻 v44「系统信息」页的版面预览"""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FONT_HEX = os.path.join(ROOT, "rtl", "font_rom.hex")

W, H = 640, 480
words = [int(l.strip(), 16) for l in open(FONT_HEX) if l.strip()]


def glyph(ch_code, x, y, scale=1, color=(30, 30, 30)):
    """在 (x,y) 画 16x16 字模，scale 倍最近邻放大。"""
    for row in range(16):
        bits = words[ch_code * 16 + (15 - row)]
        for col in range(16):
            if bits & (1 << (15 - col)):
                for dy in range(scale):
                    for dx in range(scale):
                        xx, yy = x + col * scale + dx, y + row * scale + dy
                        if 0 <= xx < W and 0 <= yy < H:
                            pix[xx, yy] = color


def text(codes, x, y, scale=1, color=(30, 30, 30)):
    for i, c in enumerate(codes):
        glyph(ord(c) if isinstance(c, str) else c, x + i * 16 * scale, y, scale, color)


img = Image.new("RGB", (W, H), (246, 246, 248))
pix = img.load()
# 主菜单竖向渐变
for y in range(H):
    g = 246 - int(round(14 * y / H))
    for x in range(W):
        pix[x, y] = (g, g, min(255, g + 2))

# 主菜单标题（2 倍）
title_codes = [0x8D, 0x8E, 0x8F, 0xF8, 0xF9, 0xE0, 0xED, 0xFA, 0xEB, 0x90, 0x91]
for i, c in enumerate(title_codes):
    glyph(c, 144 + i * 32, 40, 2, (0x5B, 0x4B, 0xC4))

# 三个按钮（近似）
btn_col = [(0x45, 0xCE, 0xE4), (0xF0, 0xC6, 0x4B), (0x8A, 0x79, 0xE6)]
for i, by in enumerate((130, 228, 326)):
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((56, by, 399, by + 75), radius=38, fill=btn_col[i])
text((0xD1, 0xD2), 218, 160, 1, (0xFF, 0xFF, 0xFF))
text((0xCF, 0xD0), 218, 258, 1, (0xFF, 0xFF, 0xFF))
text((0x90, 0x91), 218, 356, 1, (0xFF, 0xFF, 0xFF))

# 主菜单在位时，sysinfo_panel 把外面压暗 50%
for y in range(H):
    for x in range(W):
        r, g, b = pix[x, y]
        pix[x, y] = (r >> 1, g >> 1, b >> 1)

# ---------------- 面板 ----------------
X0, X1, Y0, Y1 = 80, 560, 78, 412
TITLE_X, TITLE_Y = 288, 92
ROW_Y0 = 128
LAB_X, VAL_X = 122, 260
FLD_X0, FLD_X1 = 252, 524
C_EDGE = (0x6E, 0x5F, 0xD8)
C_PANEL = (0x17, 0x1B, 0x22)
C_FIELD = (0x10, 0x14, 0x1A)
C_FLDLN = (0x3A, 0x42, 0x4E)
C_LINE = (0x23, 0x2A, 0x36)
C_TITLE = (0xF0, 0xCB, 0x4D)
C_LAB = (0xE8, 0xEE, 0xF2)
C_VAL = (0x9F, 0xD8, 0xE8)

d = ImageDraw.Draw(img)
d.rectangle((X0, Y0, X1 - 1, Y1 - 1), fill=C_PANEL, outline=C_EDGE)
for r in range(6):
    ry = ROW_Y0 + r * 40
    d.rectangle((FLD_X0, ry - 4, FLD_X1 - 1, ry + 16), fill=C_FIELD, outline=C_FLDLN)
    d.line((106, ry + 24, 533, ry + 24), fill=C_LINE)

# 标题
for i, c in enumerate((0x90, 0x91, 0x1B, 0x1C)):
    glyph(c, TITLE_X + i * 16, TITLE_Y, 1, C_TITLE)

labels = [(0x10, 0x11), (0x12, 0x13), (0xF0, 0x1A),
          (0x14, 0x15), (0x16, 0x17), (0x18, 0x19)]
values = ["EG4S20BG256", "640X480P60", "48KHZ WAV",
          "TF CARD OK", "LUT17K BRAM54", "V44 20261026"]
for r in range(6):
    ry = ROW_Y0 + r * 40
    for i, c in enumerate(labels[r]):
        glyph(c, LAB_X + i * 16, ry, 1, C_LAB)
    text(values[r], VAL_X, ry, 1, C_VAL)

img.save(os.path.join(HERE, "_preview", "sysinfo_panel.png"))
img.resize((W * 2, H * 2), Image.NEAREST).save(
    os.path.join(HERE, "_preview", "sysinfo_panel_2x.png"))
print("done")
