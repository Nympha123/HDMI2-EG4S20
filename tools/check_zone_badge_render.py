#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_zone_badge_render.py -- 用 Python 复刻 RTL 的徽标像素通路，核对地址/调色板

复刻对象（rtl/directory_ui.v）：
  BDG_X0=39, BDG_Y0=20, 显示 216x162, 图源 108x81, 2 倍放大
  bdx = x-39, bdy = y-20
  bmx = bdx>>1, bmy = bdy>>1
  row = bmy*108            （RTL 用 bmy*128 - bmy*16 - bmy*4）
  base = sel*8748          （0 / 8748 / 17496 / 26244）
  addr = base + row + bmx
  code = zone_badge.hex[addr]       0 paper / 1 tint / 2 accent / 3 ink
  color: paper #F7FAFD, tint (A>>2)+192, accent A, ink #25445C
输出 tools/_preview/zone_rtl_check_N.png（应和 make_zone_badges.py 的
zone_page_N.png 里的徽标完全一致）。
"""
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
HEX = os.path.join(ROOT, "rtl", "zone_badge.hex")
OUT = os.path.join(HERE, "_preview")

ACC = [0x3F9ED8, 0x3F9C86, 0xD9902E, 0xC2563A]
PAPER = (0xF7, 0xFA, 0xFD)
INK = (0x25, 0x44, 0x5C)
BASE = [0, 8748, 17496, 26244]
BDG_X0, BDG_Y0 = 39, 20
DW, DH = 216, 162


def accent_rgb(sel):
    v = ACC[sel]
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255)


def tint_rgb(sel):
    return tuple(min(255, (c >> 1) + 128) for c in accent_rgb(sel))


def main():
    with open(HEX, "r", encoding="ascii") as f:
        data = [int(t, 16) for t in f.read().split()]

    expect = 4 * 8748
    assert len(data) == expect, f"hex 行数 {len(data)} != {expect}"

    for sel in range(4):
        img = Image.new("RGB", (DW, DH))
        px = img.load()
        a = accent_rgb(sel)
        t = tint_rgb(sel)
        pal = [PAPER, t, a, INK]
        for y in range(DH):
            for x in range(DW):
                bmx = x >> 1
                bmy = y >> 1
                row = bmy * 128 - bmy * 16 - bmy * 4      # RTL 写法
                assert row == bmy * 108
                addr = BASE[sel] + row + bmx
                px[x, y] = pal[data[addr]]
        img.save(os.path.join(OUT, f"zone_rtl_check_{sel}.png"))

    # 与生成脚本的直接渲染对比（同样 2 倍、同色）
    import make_zone_badges as mz
    for sel in range(4):
        ref = mz.recolor(mz.downsample(mz.compose(sel).im), sel, 2)
        got = Image.open(os.path.join(OUT, f"zone_rtl_check_{sel}.png")).convert("RGB")
        diff = sum(1 for p, q in zip(ref.getdata(), got.getdata()) if p != q)
        print(f"zone {sel}: 与素材原图不一致像素 {diff} / {DW * DH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
