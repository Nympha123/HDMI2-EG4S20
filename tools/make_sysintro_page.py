#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_sysintro_page.py  -  v69「系统简介」四页说明页的字库 / 文本 ROM / 预览

产物（RTL 直接读）：
  rtl/font_rom_sys.hex    128 槽 x 16 行 = 2048 字，16x16 1bpp，4 块 BRAM9K
  rtl/sysintro_text.hex   1024 x 9 bit，1 块 BRAM9K
      地址 = {page[1:0], line[1:0], slot[5:0]}
        line 0      = 2 倍大页标题（每字占 8 个 slot，只用 slot 0..4）
        line 1..3   = 正文
        slot        = 8 px 一格
      码值
        0x000..0x07F = ASCII（查主字库 font_rom，只取 8 px 宽）
        0x080..0x0FF = 汉字左半（0x080|槽号）
        0x100..0x17F = 汉字右半（0x100|槽号，同一槽号）

  tools/_preview/sysintro_p1..4.png  640x480 预览（几何与 RTL 完全一致）

版面常量必须和 rtl/sysinfo_panel.v 的 localparam 一一对应。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RTL = os.path.join(ROOT, "rtl")
FONT_MAIN = os.path.join(RTL, "font_rom.hex")
FONT_SYS = os.path.join(RTL, "font_rom_sys.hex")
TEXT_HEX = os.path.join(RTL, "sysintro_text.hex")
PREVIEW = os.path.join(HERE, "_preview")

FONT = r"C:\Windows\Fonts\msyh.ttc"      # 与 v67 一致：微软雅黑 16px
THR = 128

# ---------------------------------------------------------------------------
# 版面（与 sysinfo_panel.v 一致）
# ---------------------------------------------------------------------------
X0, X1, Y0, Y1 = 80, 560, 78, 412           # 卡片边框
TTL_X, TTL_Y = 288, 92                       # 标题「系统简介」16 px 网格
SEP_Y, SEP_X0, SEP_X1 = 120, 96, 544         # 标题下分隔线
HG_X, HG_Y = 96, 168                         # 页标题 2 倍（32 px 网格）
BD_X, BD_Y = 96, 224                         # 正文起点（8 px 一格）
BD_PITCH, BD_LINES, BD_SLOTS = 40, 3, 56     # 行距 / 行数 / 每行 8 px 格数
FT_X, FT_Y = 96, 372                         # 按键提示
PG_X, PG_Y = 520, 372                        # 页码 "n/4"

TITLE = "系统简介"
FOOT_HINT = "A/D:SWITCH  BACK:EXIT"

# 每页 = (2 倍大标题, [正文行...])；行内手动断句，脚本会校验每行 <= BD_SLOTS 格
PAGES = [
    ("四个展区", [
        "曾侯乙编钟（6页）、青铜礼器（4页）、唐三彩（4页）、",
        "越王勾践剑（4页），共18页图文，全部由TF卡BMP装载、",
        "SDRAM双缓存切换；",
    ]),
    ("分区配乐", [
        "主界面MENU.WAV开场，A、B、C、D四区各一首专属",
        "48kHz讲解音频，换区自动换曲，装载新图时音乐不断",
        "（WAV优先仲裁）；",
    ]),
    ("自适应缩放", [
        "源图分辨率不限，最大2560×1920，装载期按N行/N列",
        "抽取（N=ceil(W/640)，1~4），写进SDRAM的仍是标准",
        " ",
    ]),
    ("参数口径", [
        "640×480P60、RGB888、HDMI 1.4b、48kHz 16bit单声道、",
        "LUT约17K、BRAM 59。",
    ]),
]

NO_LINE_HEAD = "、，。；：）】》”’,.;:)]}"


def is_ascii(ch):
    return 0x20 <= ord(ch) <= 0x7E


def slots_of(line):
    return sum(1 if is_ascii(ch) else 2 for ch in line)


def render_glyph(ch):
    """16x16 1bpp，字面位置固定（不做包围盒居中），保证标点/基线一致。"""
    from PIL import Image, ImageDraw, ImageFont

    f = ImageFont.truetype(FONT, 16)
    canvas = Image.new("L", (48, 48), 0)
    ImageDraw.Draw(canvas).text((24, 24), ch, font=f, fill=255, anchor="mm")
    if canvas.getbbox() is None:
        return [0] * 16
    cell = canvas.crop((16, 17, 32, 33))
    px = cell.point(lambda v: 255 if v > THR else 0).load()
    rows = []
    for y in range(16):
        v = 0
        for x in range(16):
            if px[x, y]:
                v |= 1 << (15 - x)
        rows.append(v)
    return rows


def build():
    slots, order = {}, []
    for head, lines in PAGES:
        for ch in head + "".join(lines):
            if not is_ascii(ch) and ch not in slots:
                slots[ch] = len(order)
                order.append(ch)
    for ch in TITLE:
        if ch not in slots:
            slots[ch] = len(order)
            order.append(ch)
    if len(order) > 128:
        raise SystemExit("too many glyphs: %d > 128" % len(order))

    layout = []
    for head, lines in PAGES:
        if len(lines) > BD_LINES:
            raise SystemExit("page %r has %d lines > %d" % (head, len(lines), BD_LINES))
        for ln in lines:
            if slots_of(ln) > BD_SLOTS:
                raise SystemExit("page %r line too wide: %d > %d: %r"
                                 % (head, slots_of(ln), BD_SLOTS, ln))
        layout.append((head, lines))

    rom = [0x020] * 1024
    for p, (head, lines) in enumerate(layout):
        base = p << 8
        for c, ch in enumerate(head):
            rom[base + c] = 0x080 | slots[ch]          # line 0, slot 0..4
        for c, ch in enumerate(TITLE):
            rom[base + 8 + c] = 0x080 | slots[ch]      # line 0, slot 8..11
        for li, line in enumerate(lines):
            s = 0
            for ch in line:
                if is_ascii(ch):
                    rom[base | ((li + 1) << 6) | s] = ord(ch) & 0x7F
                    s += 1
                else:
                    idx = slots[ch]
                    rom[base | ((li + 1) << 6) | s] = 0x080 | idx
                    rom[base | ((li + 1) << 6) | s + 1] = 0x180 | idx
                    s += 2
    with open(TEXT_HEX, "w", encoding="ascii", newline="\n") as fh:
        for v in rom:
            fh.write("%03X\n" % v)

    words = [0] * 2048
    for ch, slot in slots.items():
        rows = render_glyph(ch)
        for r in range(16):
            words[slot * 16 + (15 - r)] = rows[r]
    with open(FONT_SYS, "w", encoding="ascii", newline="\n") as fh:
        for v in words:
            fh.write("%04X\n" % v)

    print("glyphs : %d (0x00..0x%02X)" % (len(order), len(order) - 1))
    for p, (head, lines) in enumerate(layout):
        print("  P%d %s" % (p + 1, head))
        for ln in lines:
            print("     [%2d slots] %s" % (slots_of(ln), ln))
    print("text   :", TEXT_HEX)
    print("font   :", FONT_SYS)
    return layout, slots


# ---------------------------------------------------------------------------
# 预览（几何与 RTL 完全一致）
# ---------------------------------------------------------------------------
def load_hex(path, depth):
    words = []
    with open(path) as fh:
        for i, line in enumerate(fh):
            if i >= depth:
                break
            s = line.strip()
            if s:
                words.append(int(s, 16))
    return words


def blit_cell(px, rows, x0, y0, scale, color):
    """整 16 px 格（汉字 / 2 倍标题）。"""
    for r in range(16):
        bits = rows[15 - r]
        for c in range(16):
            if bits & (1 << (15 - c)):
                for dy in range(scale):
                    for dx in range(scale):
                        xx, yy = x0 + c * scale + dx, y0 + r * scale + dy
                        if 0 <= xx < 640 and 0 <= yy < 480:
                            px[xx, yy] = color


def blit_narrow(px, rows, x0, y0, color):
    """8 px 宽 ASCII（取 bit11..bit4，与 RTL 的 fnt_dout[11-xoff] 一致）。"""
    for r in range(16):
        bits = (rows[15 - r] >> 4) & 0xFF          # bit11..bit4 -> b7..b0
        for c in range(8):
            if bits & (1 << (7 - c)):
                if 0 <= x0 + c < 640 and 0 <= y0 + r < 480:
                    px[x0 + c, y0 + r] = color


def preview(layout, slots):
    from PIL import Image

    main = load_hex(FONT_MAIN, 16384)
    sysf = load_hex(FONT_SYS, 2048)

    def main_rows(ch):
        s = ord(ch)
        return main[s * 16:s * 16 + 16]

    for p, (head, lines) in enumerate(layout):
        im = Image.new("RGB", (640, 480), (116, 122, 125))   # 压暗 50% 的浅色界面
        px = im.load()
        for y in range(Y0, Y1):
            for x in range(X0, X1):
                edge = (x in (X0, X1 - 1)) or (y in (Y0, Y1 - 1))
                px[x, y] = (0x6E, 0x5F, 0xD8) if edge else (0x17, 0x1B, 0x22)
        for x in range(SEP_X0, SEP_X1):
            px[x, SEP_Y] = (0x3A, 0x42, 0x4E)
        # 标题 16 px
        for i, ch in enumerate(TITLE):
            s = slots[ch]
            blit_cell(px, sysf[s * 16:s * 16 + 16], TTL_X + i * 16, TTL_Y, 1, (0xF0, 0xCB, 0x4D))
        # 页标题 2 倍
        for i, ch in enumerate(head):
            s = slots[ch]
            blit_cell(px, sysf[s * 16:s * 16 + 16], HG_X + i * 32, HG_Y, 2, (0xF0, 0xCB, 0x4D))
        # 页码 8 px
        for i, ch in enumerate("%d/4" % (p + 1)):
            blit_narrow(px, main_rows(ch), PG_X + i * 8, PG_Y, (0x8A, 0x93, 0xA6))
        # 正文 8 px 网格
        for li, line in enumerate(lines):
            s = 0
            for ch in line:
                if is_ascii(ch):
                    blit_narrow(px, main_rows(ch), BD_X + s * 8,
                                BD_Y + li * BD_PITCH, (0xCF, 0xE8, 0xF2))
                    s += 1
                else:
                    sl = slots[ch]
                    blit_cell(px, sysf[sl * 16:sl * 16 + 16], BD_X + s * 8,
                              BD_Y + li * BD_PITCH, 1, (0xCF, 0xE8, 0xF2))
                    s += 2
        # 底栏
        for i, ch in enumerate(FOOT_HINT):
            blit_narrow(px, main_rows(ch), FT_X + i * 8, FT_Y, (0x8A, 0x93, 0xA6))

        os.makedirs(PREVIEW, exist_ok=True)
        out = os.path.join(PREVIEW, "sysintro_p%d.png" % (p + 1))
        im.save(out)
        im.resize((1280, 960), Image.NEAREST).save(
            os.path.join(PREVIEW, "sysintro_p%d_2x.png" % (p + 1)))
    sheet = Image.new("RGB", (1280, 960), (0, 0, 0))
    for p in range(4):
        sheet.paste(Image.open(os.path.join(PREVIEW, "sysintro_p%d.png" % (p + 1))),
                    ((p % 2) * 640, (p // 2) * 480))
    sheet.save(os.path.join(PREVIEW, "sysintro_sheet.png"))
    print("preview:", PREVIEW)
    return 0


def main():
    layout, slots = build()
    preview(layout, slots)
    return 0


if __name__ == "__main__":
    sys.exit(main())
