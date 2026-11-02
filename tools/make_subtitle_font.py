#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_subtitle_font.py - 字幕 + 目录页共用的 ext 字库（1024 x 16，2 块 BRAM）

内容：
  * 滚动字幕 3 句（第 1 句随展区）+ 4 个展区欢迎语
  * 目录页：4 个展区名 + 4 行时代/类别说明

输出：
  rtl/font_rom_ext.hex            1024 行（<=64 个字 x 16 行）
  tools/subtitle_params.vh        贴进 subtitle_overlay.v 的 localparam
  tools/directory_params.vh       贴进 directory_ui.v 的 localparam
  tools/subtitle_glyph_map.txt    字 -> 编码
  tools/_subtitle_preview.png     预览（环境变量 SUBTITLE_PREVIEW 可改路径）
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RTL = os.path.join(ROOT, "rtl")
MAIN_HEX = os.path.join(RTL, "font_rom.hex")
EXT_HEX = os.path.join(RTL, "font_rom_ext.hex")
VSUB = os.path.join(HERE, "subtitle_params.vh")
VDIR = os.path.join(HERE, "directory_params.vh")
MAP = os.path.join(HERE, "subtitle_glyph_map.txt")

FONT = r"C:\Windows\Fonts\msyh.ttc"
# v79：目录页左下角新增"展区简介"三行，字模从 64 槽扩到 128 槽（2048 x 16 = 4 块 BRAM）。
#   目录页与字幕互斥，两处共用同一片 ROM（在顶层实例化），所以 BRAM 总数不增。
EXT_DEPTH = 2048
EXT_CODE0 = 0x100
# 目录页只读 ext ROM，所以 ·（中点）必须进 ext，不能复用主字库的 0xB4
FORCE_NEW = {"·", "请", "展", "区"}
CODE_BITS = 9

SENTENCES = [
    ("SUB_A",  "欢迎参观 · 曾侯乙编钟", 12),
    ("SUB_B",  "欢迎参观 · 青铜礼器", 11),
    ("SUB_C",  "欢迎参观 · 唐三彩", 10),
    ("SUB_D",  "欢迎参观 · 越王勾践剑", 12),
    ("SUB_N1", "展厅内请保持安静，请勿触摸展品，拍照请关闭闪光灯", 24),
    ("SUB_N2", "开放时间 9:00—17:00，讲解服务请至前台预约", 26),
]

# 目录页：4 个展区名 + 4 行说明（左下图注 + 右侧列表共用）
DIR_NAMES = [
    ("DIR_N0", "曾侯乙编钟", 5),
    ("DIR_N1", "青铜礼器", 4),
    ("DIR_N2", "唐三彩", 3),
    ("DIR_N3", "越王勾践剑", 5),
]
DIR_DESCS = [
    ("DIR_D0", "战国 · 青铜编钟", 9),
    ("DIR_D1", "商周 · 青铜礼器", 9),
    ("DIR_D2", "唐代 · 陶俑", 7),
    ("DIR_D3", "春秋 · 青铜兵器", 9),
]
DIR_HINT = ("DIR_HINT", "请勿触摸展品", 6)
# v79：目录页左下角"展区简介"——每区 3 行，≤16 字/行（144 bit/行）
DIR_ZONE = [
    ("DIR_Z0L0", "战国曾侯乙墓出土", 8),
    ("DIR_Z0L1", "六十五件青铜编钟", 8),
    ("DIR_Z0L2", "音域跨五个八度", 7),
    ("DIR_Z1L0", "商周祭祀宴飨重器", 8),
    ("DIR_Z1L1", "鼎簋尊彝，礼制象征", 9),
    ("DIR_Z1L2", "多铸铭文传世", 6),
    ("DIR_Z2L0", "唐代低温铅釉陶器", 8),
    ("DIR_Z2L1", "黄绿褐三彩交融", 7),
    ("DIR_Z2L2", "多为随葬明器", 6),
    ("DIR_Z3L0", "春秋晚期越国剑", 7),
    ("DIR_Z3L1", "出土时寒光如新", 7),
    ("DIR_Z3L2", "刃薄而锋利", 5),
]
DIR_CHARS_PER_LINE = 16


def render(ch):
    for px in (16, 15, 14, 13, 12, 18, 20):
        f = ImageFont.truetype(FONT, px)
        im = Image.new("L", (32, 32), 0)
        d = ImageDraw.Draw(im)
        d.text((16, 16), ch, font=f, fill=255, anchor="mm")
        bb = im.getbbox()
        if bb is None:
            continue
        w, h = bb[2] - bb[0], bb[3] - bb[1]
        if w <= 16 and h <= 16:
            im = im.crop(bb)
            cell = Image.new("L", (16, 16), 0)
            cell.paste(im, ((16 - im.width) // 2, (16 - im.height) // 2))
            pix = cell.load()
            rows = []
            for row in range(16):
                v = 0
                for x in range(16):
                    if pix[x, row] > 100:
                        v |= (1 << (15 - x))
                rows.append(v)
            return rows
    raise SystemExit("cannot fit glyph: %r" % ch)


def main():
    main_words = [int(l.strip(), 16) for l in open(MAIN_HEX) if l.strip()]
    assert len(main_words) == 16384

    old_index = {}
    for slot in range(256):
        rows = main_words[slot * 16:(slot + 1) * 16]
        if any(rows):
            old_index.setdefault(tuple(rows[15 - r] for r in range(16)), slot)

    chars = []
    for _, text, _ in SENTENCES + DIR_NAMES + DIR_DESCS + [DIR_HINT] + DIR_ZONE + [("ZONE_PRE", "展区", 2)]:
        for ch in text:
            if ord(ch) >= 0x80 and ch not in chars:
                chars.append(ch)
    reuse, new = {}, []
    for ch in chars:
        slot = None if ch in FORCE_NEW else old_index.get(tuple(render(ch)))
        if slot is not None:
            reuse[ch] = slot
        else:
            new.append(ch)
    print("unique: %d | reuse: %d | new: %d" % (len(chars), len(reuse), len(new)))
    if len(new) > 128:
        raise SystemExit("new glyphs %d > 128" % len(new))

    ext = [0] * EXT_DEPTH
    code_of = {}
    for i, ch in enumerate(new):
        rows = render(ch)
        for row in range(16):
            ext[i * 16 + (15 - row)] = rows[row]
        code_of[ch] = EXT_CODE0 + i
    code_of.update(reuse)

    with open(EXT_HEX, "w", encoding="ascii", newline="\r\n") as fh:
        for w in ext:
            fh.write("%04X\n" % w)
    print("wrote", EXT_HEX)

    with open(MAP, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("char\tcode\twhere\n")
        for ch in chars:
            fh.write("%s\t9'h%03X\t%s\n" % (ch, code_of[ch],
                                            "old font_rom" if ch in reuse else "font_rom_ext"))
    print("wrote", MAP)

    # v79c：subtitle_overlay.v 里的 zone_str9（底栏「XX展区」）是**硬编码 9bit 码**，
    #   它依赖这里的分槽顺序。字形码是按 chars 出现顺序分配的，ZONE_PRE("展区") 排在
    #   最后，所以「区」永远落在最后一个新字上 —— 只要新字数量变化，它的码就会变。
    #   （v79b 加了三行展区简介，"区" 从 0x13E 变成 0x174，底栏就显示成了"展墓"。）
    #   这里显式校验，改了文案就会打印出来提醒同步修改 zone_str9。
    for ch, want in (("\u5c55", 0x112), ("\u533a", 0x174)):
        if code_of.get(ch) != want:
            print("WARN: '%s' -> 0x%03X (expected 0x%03X) -- update zone_str9 in subtitle_overlay.v"
                  % (ch, code_of.get(ch, -1), want))

    # ---- 字幕常量 ----
    out = ["    // ==== 字幕文案（博物馆版｜由 tools/make_subtitle_font.py 生成，勿手改）====",
           "    //   3 句循环：第 1 句随展区 A/B/C/D 切换，其余 2 句通用提示。",
           "    //   9 bit/字，首字在最低 9 位；0x00..0xFF 走主字库，0x100+ 走 font_rom_ext。",
           "    localparam integer SUB_CHARS = 32;"]
    for name, text, ln in SENTENCES:
        assert len(text) == ln, (text, len(text), ln)
        vec = 0
        for i, ch in enumerate(text):
            vec |= (ord(ch) if ord(ch) < 0x80 else code_of[ch]) << (i * CODE_BITS)
        out.append("    localparam [287:0] %s = 288'h%072X;  // %s" % (name, vec, text))
    open(VSUB, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
    print("wrote", VSUB)

    # ---- 目录页常量（16 字/行 = 144 bit）----
    out = ["    // ==== 目录页文案（由 tools/make_subtitle_font.py 生成，勿手改）====",
           "    //   9 bit/字，首字在最低 9 位；最多 16 字"]
    for name, text, ln in DIR_NAMES + DIR_DESCS + [DIR_HINT] + DIR_ZONE:
        assert len(text) == ln, (text, len(text), ln)
        vec = 0
        for i, ch in enumerate(text):
            vec |= (ord(ch) if ord(ch) < 0x80 else code_of[ch]) << (i * CODE_BITS)
        out.append("    localparam [%d:0] %s = %d'h%0*X;  // %s"
                   % (DIR_CHARS_PER_LINE * CODE_BITS - 1, name,
                      DIR_CHARS_PER_LINE * CODE_BITS,
                      (DIR_CHARS_PER_LINE * CODE_BITS) // 4, vec, text))
        out.append("    localparam [4:0] %s_L = 5'd%d;" % (name, ln))
    open(VDIR, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
    print("wrote", VDIR)

    # ---- 预览 ----
    rows_of = {}
    for ch in chars:
        c = code_of[ch]
        rows_of[ch] = main_words[c * 16:(c + 1) * 16] if ch in reuse else ext[(c - EXT_CODE0) * 16:(c - EXT_CODE0 + 1) * 16]

    def str_rows(text):
        if ord(text[0]) < 0x80:
            return main_words[ord(text[0]) * 16:(ord(text[0]) + 1) * 16]
        return rows_of[text[0]]

    all_lines = [t for _, t, _ in DIR_NAMES] + [t for _, t, _ in DIR_DESCS] + \
                [t for _, t, _ in DIR_ZONE] + [t for _, t, _ in SENTENCES]
    img = Image.new("RGB", (520, 18 * len(all_lines) + 8), (255, 255, 255))
    d = ImageDraw.Draw(img)
    for i, s in enumerate(all_lines):
        x = 4
        for ch in s:
            if ord(ch) < 0x80:
                rows = main_words[ord(ch) * 16:(ord(ch) + 1) * 16]
            else:
                rows = rows_of[ch]
            for r in range(16):
                w = rows[15 - r]
                for c in range(16):
                    if (w >> (15 - c)) & 1:
                        img.putpixel((x + c, 4 + i * 18 + r), (40, 60, 80))
            x += 16
    pv = os.environ.get("SUBTITLE_PREVIEW", os.path.join(HERE, "_subtitle_preview.png"))
    img.resize((img.width * 2, img.height * 2), Image.NEAREST).save(pv)
    print("preview:", pv)
    return 0


if __name__ == "__main__":
    sys.exit(main())
