#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""preview_menu_icons.py -- 用真实精灵表按 RTL 的 1.5 倍采样画主菜单右侧图标，核对大小/间距

RTL（main_menu.v）：
    ICON_X0=470, ICON_Y0=56, 行距 96, 显示 66x66
    src = (dst * 342) >> 9        （= dst * 2 / 3，1.5 倍最近邻）
    奇数行右移 12 px
输出 tools/_preview/menu_icons_new.png
"""
import io
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(HERE, "_preview")

BITS = [int(l.strip()) for l in io.open(os.path.join(ROOT, "rtl", "menu_icon.hex"), encoding="ascii") if l.strip()]
FONT = [l.strip() for l in io.open(os.path.join(ROOT, "rtl", "font_rom.hex"), encoding="ascii") if l.strip()]

ICON_X0, ICON_Y0, PITCH, SIZE = 470, 56, 96, 66
TITLE = [0x8D, 0x8E, 0x8F, 0xF8, 0xF9, 0xE0, 0xED, 0xFA, 0xEB, 0x90, 0x91]


def icon_bit(idx, sy, sx):
    return BITS[idx * 1936 + sy * 44 + sx]


def glyph(code):
    rows = []
    for r in range(16):
        v = int(FONT[code * 16 + (15 - r)], 16)
        rows.append([(v >> (15 - c)) & 1 for c in range(16)])
    return rows


def main():
    W, H = 640, 480
    im = Image.new("RGB", (W, H), (0xF2, 0xF2, 0xF7))
    d = ImageDraw.Draw(im)
    # 背景竖向渐变
    for y in range(H):
        c = 246 - y * 14 // H
        d.line([(0, y), (W, y)], fill=(c, c, c + 2))
    # 右侧装饰环（八边形近似，和 oct_hit 一致：max<=r 且 |dx|+|dy|<=1.5r）
    def oct_hit(x, y, cx, cy, r):
        dx, dy = abs(x - cx), abs(y - cy)
        return max(dx, dy) <= r and dx + dy <= r * 3 // 2
    for y in range(H):
        for x in range(300, W):
            if oct_hit(x, y, 462, 238, 176) and not oct_hit(x, y, 462, 238, 144):
                im.putpixel((x, y), (0xD9, 0xD4, 0xF2))
            elif oct_hit(x, y, 462, 238, 144):
                im.putpixel((x, y), (0xE6, 0xE2, 0xF8))
    # 三枚胶囊按钮
    for i, col in enumerate([(0x45, 0xCE, 0xE4), (0xF0, 0xC6, 0x4B), (0x8A, 0x79, 0xE6)]):
        y0 = 130 + i * 98
        d.rounded_rectangle([56, y0, 400, y0 + 76], radius=38, fill=col)
    # 标题（2 倍）
    for i, code in enumerate(TITLE):
        g = glyph(code)
        for r in range(16):
            for c in range(16):
                if g[r][c]:
                    d.rectangle([144 + i * 32 + c * 2, 40 + r * 2,
                                 144 + i * 32 + c * 2 + 1, 40 + r * 2 + 1],
                                fill=(0x5B, 0x4B, 0xC4))
    # 图标（1.5 倍，与 RTL 同一采样）
    for idx in range(4):
        x0 = ICON_X0 + (12 if idx % 2 else 0)
        y0 = ICON_Y0 + idx * PITCH
        for dy in range(SIZE):
            sy = min(43, (dy * 342) >> 9)
            for dx in range(SIZE):
                sx = min(43, (dx * 342) >> 9)
                if icon_bit(idx, sy, sx):
                    im.putpixel((x0 + dx, y0 + dy), (0x8A, 0x8F, 0xA8))
    im.save(os.path.join(OUT, "menu_icons_new.png"))
    print("saved", os.path.join(OUT, "menu_icons_new.png"))


if __name__ == "__main__":
    raise SystemExit(main())
