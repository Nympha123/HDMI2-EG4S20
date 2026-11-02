#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""preview_topbar.py -- 用真实字库位图渲染"图片页顶栏"和"主菜单标题"，核对位置

字库 rtl/font_rom.hex：1024 槽 x 16 行，行倒序（addr = code*16 + (15-row)），
每行 4 位 hex（bit15 = 最左像素）。
输出 tools/_preview/topbar_new.png / menu_title_new.png
"""
import io
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(HERE, "_preview")

ROWS = [l.strip() for l in io.open(os.path.join(ROOT, "rtl", "font_rom.hex"), encoding="ascii") if l.strip()]


def glyph(code):
    """返回 16x16 的 0/1 位图（行 0 = 顶部）"""
    g = []
    for row in range(16):
        addr = code * 16 + (15 - row)
        v = int(ROWS[addr], 16)
        g.append([(v >> (15 - c)) & 1 for c in range(16)])
    return g


def draw_text(dst, x, y, codes, color=(0x25, 0x44, 0x5C)):
    for i, c in enumerate(codes):
        g = glyph(c)
        for r in range(16):
            for col in range(16):
                if g[r][col]:
                    dst.putpixel((x + i * 16 + col, y + r), color)


def bar_preview():
    W, H = 640, 32
    im = Image.new("RGB", (W, H), (0xEE, 0xF5, 0xFC))
    d = ImageDraw.Draw(im)
    # 「手动」= 0x8A 手? 用 info_bands 的 stat_off_str = 16'h8B8A（首字低字节）
    draw_text(im, 40 - 2 * 8, 8, [0x8A, 0x8B])
    title = [0x8D, 0x8E, 0x8F, 0xF8, 0xF9, 0xE0, 0xED, 0xFA, 0xEB, 0x90, 0x91]
    draw_text(im, 232, 8, title)
    tstr = [0x31, 0x32, 0x3A, 0x35, 0x32, 0x3A, 0x33, 0x30]      # 12:52:30
    draw_text(im, 632 - 8 * 16, 8, tstr)
    d.rectangle([0, 0, W - 1, H - 1], outline=(0x9C, 0xCB, 0xE8))
    im.resize((W * 2, H * 2), Image.NEAREST).save(os.path.join(OUT, "topbar_new.png"))

    # 主菜单标题（2 倍放大，x=144, y=40）
    m = Image.new("RGB", (640, 140), (0xF6, 0xF6, 0xF8))
    big = Image.new("RGB", (640, 80), (0xF6, 0xF6, 0xF8))
    draw_text(big, 144, 24, title, (0x5B, 0x4B, 0xC4))
    m.paste(big.resize((640, 80), Image.NEAREST), (0, 0))
    ImageDraw.Draw(m).rectangle([144 * 2 // 2, 40, 144 * 2 // 2 + 352 - 1, 40 + 31],
                                outline=(0xC0, 0xC0, 0xD0))
    m.save(os.path.join(OUT, "menu_title_new.png"))
    print("ok")


if __name__ == "__main__":
    bar_preview()
