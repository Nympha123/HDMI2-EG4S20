#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
check_sysintro_render.py  -  按 rtl/sysinfo_panel.v 的取址规则逐像素复算，
和 tools/make_sysintro_page.py 的“理想排版”结果逐像素比对。

为什么要有这一步：
  系统页的字有两条 ROM（文本 ROM 出码值 / 小字库出点阵），码值里还编码了
  “汉字左半 / 右半 / ASCII”，只要槽号、行号、半字选择或 bit 抽取有一处写错，
  屏上就是整行串位或半个字 —— 而综合/布线不会报任何错。这个脚本把 RTL 的
  算法在 Python 里重放一遍，和生成器的版面对像素，能提前抓出这类错误。

用法：python tools/check_sysintro_render.py
输出：tools/_preview/sysintro_rtl_p1..4.png，逐页打印差异像素数。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RTL = os.path.join(ROOT, "rtl")
PREVIEW = os.path.join(HERE, "_preview")

# 与 sysinfo_panel.v 一致的版面常量
X0, X1, Y0, Y1 = 80, 560, 78, 412
TTL_X, TTL_Y = 288, 92
SEP_Y, SEP_X0, SEP_X1 = 120, 96, 544
HG_X, HG_Y = 96, 168
BD_X, BD_Y = 96, 224
BD_END = 120
FT_X, FT_Y = 96, 372
PG_X = 520

C_TITLE = (0xF0, 0xCB, 0x4D)
C_VAL = (0xCF, 0xE8, 0xF2)
C_FOOT = (0x8A, 0x93, 0xA6)
C_EDGE = (0x6E, 0x5F, 0xD8)
C_PANEL = (0x17, 0x1B, 0x22)
C_LINE = (0x3A, 0x42, 0x4E)

FOOT = "A/D:SWITCH  BACK:EXIT"


def load_hex(path, depth):
    w = []
    with open(path) as fh:
        for i, line in enumerate(fh):
            if i >= depth:
                break
            s = line.strip()
            if s:
                w.append(int(s, 16))
    return w


def lint_widths():
    """扫 sysinfo_panel.v 里"一条声明写多个名字 + 只有第一个带位宽"的写法。

    `wire [1:0] tcol = tx[5:4], tgx3 = tx[3:0];` 会把 tgx3 也声明成 2 bit，
    屏上就是标题/页标题"重影"（同一个字被画成 4 份 / 2 份叠在一起）。
    综合、布线、下面的像素比对都不会报这个错 —— 只能靠这条静态检查。
    """
    import re
    path = os.path.join(RTL, "sysinfo_panel.v")
    pat = re.compile(r"^\s*(?:wire|reg)\s*\[[^\]]+\]\s*\w+\s*=\s*[^;]*,\s*\w+\s*=")
    bad = []
    for i, line in enumerate(open(path, encoding="utf-8"), 1):
        if pat.match(line):
            bad.append("  sysinfo_panel.v:%d  %s" % (i, line.strip()))
    if bad:
        print("LINT FAIL: 一条声明里写了多个名字（只有第一个带位宽）")
        print("\n".join(bad))
        return 1
    print("lint  : 位宽声明 OK")
    return 0


def main():
    from PIL import Image

    if lint_widths():
        return 1

    main_font = load_hex(os.path.join(RTL, "font_rom.hex"), 16384)
    sys_font = load_hex(os.path.join(RTL, "font_rom_sys.hex"), 2048)
    text = load_hex(os.path.join(RTL, "sysintro_text.hex"), 1024)
    if len(sys_font) < 2048 or len(text) < 1024:
        raise SystemExit("hex 文件行数不足: font=%d text=%d" % (len(sys_font), len(text)))

    rc = 0
    for page in range(4):
        im = Image.new("RGB", (640, 480), (116, 122, 125))
        px = im.load()
        for y in range(480):
            for x in range(640):
                in_card = (X0 <= x < X1) and (Y0 <= y < Y1)
                in_ttl = (TTL_X <= x < TTL_X + 64) and (TTL_Y <= y < TTL_Y + 16)
                in_head = (HG_X <= x < HG_X + 160) and (HG_Y <= y < HG_Y + 32)
                dby = y - BD_Y
                bd_v = (dby >= 0) and (dby < BD_END)
                bline = 0 if dby < 40 else (1 if dby < 80 else 2)
                boff = dby if dby < 40 else (dby - 40 if dby < 80 else dby - 80)
                in_bd = bd_v and (boff < 16) and (BD_X <= x < BD_X + 448)
                in_ft = (FT_X <= x < FT_X + 176) and (FT_Y <= y < FT_Y + 16)
                in_pg = (PG_X <= x < PG_X + 24) and (FT_Y <= y < FT_Y + 16)
                sep = (y == SEP_Y) and (SEP_X0 <= x < SEP_X1)

                # ---- 文本 ROM 地址 ----
                if in_ttl:
                    slot = 8 + ((x - TTL_X) >> 4)
                    line = 0
                elif in_head:
                    slot = (x - HG_X) >> 5
                    line = 0
                else:
                    slot = (x - BD_X) >> 3 if x >= BD_X else 0
                    line = 1 + bline
                code = text[(page << 8) | (line << 6) | (slot & 63)]

                # ---- 逐区域取字模 ----
                if in_ttl:
                    gx, row = (x - TTL_X) & 15, (y - TTL_Y) & 15
                elif in_head:
                    gx, row = ((x - HG_X) & 31) >> 1, ((y - HG_Y) & 31) >> 1
                elif in_bd:
                    gx = (8 if (code & 0x100) else 0) + ((x - BD_X) & 7)
                    row = boff & 15
                else:
                    gx, row = 0, (y - FT_Y) & 15

                # 码值 bit7 = 汉字（0x080|槽 / 0x100|槽 都是汉字），否则是 ASCII
                cjk = bool(code & 0x80) and (in_ttl or in_head or in_bd)
                if cjk:
                    bits = sys_font[(code & 0x7F) * 16 + (15 - row)]
                    pix_on = (bits >> (15 - gx)) & 1
                else:
                    if in_ttl or in_head or in_bd:
                        acs = code & 0x7F
                    elif in_pg:
                        ci = (x - PG_X) >> 3
                        acs = (0x31 + page) if ci == 0 else (0x2F if ci == 1 else 0x34)
                    elif in_ft:
                        ci = (x - FT_X) >> 3
                        acs = ord(FOOT[ci]) if ci < len(FOOT) else 0x20
                    else:
                        acs = 0x20
                    xoff = (x - (PG_X if in_pg else FT_X)) & 7
                    bits = main_font[acs * 16 + (15 - row)]
                    pix_on = (bits >> (11 - xoff)) & 1

                txt = in_ttl or in_head or in_bd or in_ft or in_pg
                gold = in_ttl or in_head
                foot = in_ft or in_pg
                edge = in_card and (x in (X0, X1 - 1) or y in (Y0, Y1 - 1))

                if txt and pix_on:
                    col = C_TITLE if gold else (C_FOOT if foot else C_VAL)
                elif sep:
                    col = C_LINE
                elif edge:
                    col = C_EDGE
                elif in_card:
                    col = C_PANEL
                else:
                    col = (116, 122, 125)
                px[x, y] = col

        # 与生成器的理想排版比对
        ref = Image.open(os.path.join(PREVIEW, "sysintro_p%d.png" % (page + 1)))
        diff = 0
        rp, ip = ref.load(), im.load()
        for y in range(480):
            for x in range(640):
                if rp[x, y] != ip[x, y]:
                    diff += 1
        out = os.path.join(PREVIEW, "sysintro_rtl_p%d.png" % (page + 1))
        im.save(out)
        tag = "OK  " if diff == 0 else "DIFF"
        print("%s page %d: %d diff pixels -> %s" % (tag, page + 1, diff, out))
        if diff:
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
