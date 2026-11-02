#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_menu_assets.py - 主菜单改版所需素材

1) 标题新增 5 个汉字（博物馆系统）写入主字库 font_rom.hex 的空闲槽位 0x8D..0x91
   （这 5 个槽位在原字库里是「花 瓷 瓶 明 永」，全工程无任何文本引用，见 tools/font_slot_audit）
2) 生成右侧 4 个展品图标的 1bpp 精灵表 menu_icon.hex（8192 行，1 bit/行）
   布局：icon_idx*1936 + ly*44 + lx   (1936 = 44*44)

用法： python tools/make_menu_assets.py
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RTL = os.path.join(ROOT, "rtl")
FONT_HEX = os.path.join(RTL, "font_rom.hex")
ICON_HEX = os.path.join(RTL, "menu_icon.hex")
ICON_SRC = os.path.join(HERE, "menu_icons.py")

FONT = r"C:\Windows\Fonts\msyh.ttc"

TITLE_SLOTS = [0x8D, 0x8E, 0x8F, 0x90, 0x91]
TITLE_CHARS = "博物馆系统"

ICON_SIZE = 44
ICON_CELL = ICON_SIZE * ICON_SIZE      # 1936
ICON_DEPTH = 8192


def render16(ch):
    """标题字模：宋体 16px 直接渲染（不缩放），阈值 128，按包围盒居中。
    实测笔画平均长度 2.14px、墨量 92，与字库原有的「智能展品讲解」（2.26 / 77）最接近；
    之前用 15x15 缩放版只有 1.84px，2 倍放大后显得又细又糊。"""
    f = ImageFont.truetype(r"C:\Windows\Fonts\simsun.ttc", 16)
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
    # ---------- 1) 标题字模 ----------
    words = [int(l.strip(), 16) for l in open(FONT_HEX) if l.strip()]
    assert len(words) == 16384
    for slot, ch in zip(TITLE_SLOTS, TITLE_CHARS):
        rows = render16(ch)
        for row in range(16):
            words[slot * 16 + (15 - row)] = rows[row]
        print("  slot 0x%02X <- %s" % (slot, ch))
    with open(FONT_HEX, "w", encoding="ascii", newline="\r\n") as fh:
        for w in words:
            fh.write("%04X\n" % w)
    print("updated", FONT_HEX)

    # ---------- 2) 图标精灵 ----------
    sys.path.insert(0, HERE)
    import draw_icons as D

    icons = [D.icon_bells(), D.icon_ding(), D.icon_horse(), D.icon_sword()]

    bits = [0] * ICON_DEPTH
    for idx, im in enumerate(icons):
        px = im.load()
        assert im.size == (ICON_SIZE, ICON_SIZE), im.size
        base = idx * ICON_CELL
        for ly in range(ICON_SIZE):
            for lx in range(ICON_SIZE):
                if px[lx, ly] > 127:
                    bits[base + ly * ICON_SIZE + lx] = 1
    with open(ICON_HEX, "w", encoding="ascii", newline="\r\n") as fh:
        for b in bits:
            fh.write("%X\n" % b)
    print("wrote", ICON_HEX, "set bits:", sum(bits))
    return 0


if __name__ == "__main__":
    sys.exit(main())
