#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
add_sysinfo_glyphs.py - v44 「系统信息」页所需的 13 个汉字

把下面这些字写进主字库 font_rom.hex 的 0x10..0x1C 槽（这些槽原来只被旧
sysinfo_panel 使用；v44 重写该页后统一复用）。渲染参数与 v39 / 主菜单标题
一致：宋体 16 px、阈值 128、按包围盒居中。

用法（用工程自带的 Python）：
    python tools/add_sysinfo_glyphs.py
"""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FONT_HEX = os.path.join(ROOT, "rtl", "font_rom.hex")
SIMSUN = r"C:\Windows\Fonts\simsun.ttc"

# 槽号 -> 汉字（顺序就是 sysinfo_panel.v 里的 lab_code / title_code）
GLYPHS = [
    (0x10, "器"), (0x11, "件"),
    (0x12, "输"), (0x13, "出"),
    (0x14, "存"), (0x15, "储"),
    (0x16, "资"), (0x17, "源"),
    (0x18, "版"), (0x19, "本"),
    (0x1A, "频"), (0x1B, "信"), (0x1C, "息"),
]


def render16(ch):
    f = ImageFont.truetype(SIMSUN, 16)
    im = Image.new("L", (48, 48), 0)
    d = ImageDraw.Draw(im)
    d.text((24, 24), ch, font=f, fill=255, anchor="mm")
    bb = im.getbbox()
    if bb is None:
        raise SystemExit("cannot render %r" % ch)
    im = im.crop(bb)
    cell = Image.new("L", (16, 16), 0)
    if im.width <= 16 and im.height <= 16:
        cell.paste(im, ((16 - im.width) // 2, (16 - im.height) // 2))
    else:
        cell.paste(im.resize((16, 16), Image.LANCZOS), (0, 0))
    pix = cell.point(lambda v: 255 if v > 128 else 0).load()
    rows = []
    for row in range(16):
        v = 0
        for x in range(16):
            if pix[x, row] > 127:
                v |= (1 << (15 - x))
        rows.append(v)
    return rows


def main():
    lines = [l.strip() for l in open(FONT_HEX) if l.strip()]
    assert len(lines) == 16384, len(lines)
    words = [int(l, 16) for l in lines]

    for slot, ch in GLYPHS:
        old = sum(1 for r in range(16) if words[slot * 16 + r])
        rows = render16(ch)
        for row in range(16):
            words[slot * 16 + (15 - row)] = rows[row]
        print("slot 0x%02X <- %s  (old nonzero rows %d)" % (slot, ch, old))

    with open(FONT_HEX, "w", encoding="ascii", newline="\r\n") as fh:
        for w in words:
            fh.write("%04X\n" % w)
    print("updated", FONT_HEX)

    # 预览：13 个字排成一行，放大 4 倍
    scale = 4
    W, H = 13 * 16 * scale, 16 * scale
    out = Image.new("RGB", (W, H), (23, 27, 34))
    px = out.load()
    for i, (slot, ch) in enumerate(GLYPHS):
        for row in range(16):
            bits = words[slot * 16 + (15 - row)]
            for x in range(16):
                if bits & (1 << (15 - x)):
                    for dy in range(scale):
                        for dx in range(scale):
                            px[i * 16 * scale + x * scale + dx, row * scale + dy] = (232, 238, 242)
    prev = os.path.join(HERE, "_preview", "sysinfo_glyphs.png")
    os.makedirs(os.path.dirname(prev), exist_ok=True)
    out.save(prev)
    print("preview", prev)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
