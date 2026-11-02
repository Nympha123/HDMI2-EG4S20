#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
add_intro_title_glyphs.py - v69 主菜单/系统页标题「系统简介」缺的两个字

font_rom.hex 里 0x1D..0x1F 是空槽（docs/HDMI2_EG4S20_调试与问题解决参考文档
§6.3 已注明），这里把 简(0x1D) / 介(0x1E) 写进去。
渲染参数与 v67 小字库一致：微软雅黑 16 px、阈值 128、汉字按包围盒居中。
主字库仍是 4096 深，TD 仍推断 8 块 BRAM，不增加资源。
"""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FONT_HEX = os.path.join(ROOT, "rtl", "font_rom.hex")
FONT = r"C:\Windows\Fonts\msyh.ttc"

GLYPHS = [(0x1D, "简"), (0x1E, "介")]


def render16(ch):
    f = ImageFont.truetype(FONT, 16)
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
        print("slot 0x%02X <- %s (old nonzero rows %d)" % (slot, ch, old))
    with open(FONT_HEX, "w", encoding="ascii", newline="\r\n") as fh:
        for w in words:
            fh.write("%04X\n" % w)
    print("updated", FONT_HEX)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
