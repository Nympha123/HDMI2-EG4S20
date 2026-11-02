#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_scale_test_bmps.py  -  生成"任意分辨率"缩放的测试用 BMP

产物（24 bit、无压缩、行 4 字节对齐的标准 BMP，和工程里其它素材同格式）：
    A07 1280x720    -> N=2 -> 640x360   （下方补 120 行黑）
    A08 1920x1080   -> N=3 -> 640x360   （下方补 120 行黑）
    A09 1024x768    -> N=2 -> 512x384   （右补 128 px、下补 96 行）
    A10  800x600    -> N=2 -> 400x300   （右补 240 px、下补 180 行）
    B05 1600x1200   -> N=3 -> 534x400   （右补 106 px、下补 80 行）
    B06 2560x1440   -> N=4 -> 640x360   （下方补 120 行黑）

每张图上都画了：外框（看裁切）、四角色块（看有没有丢角）、64 px 网格（看抽取错位）、
中间大字"源分辨率 → 目标分辨率"、底部 "TEST <名字>"。
"""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "SD卡上内容")
FONT_CN = r"C:\Windows\Fonts\msyh.ttc"
FONT_NUM = r"C:\Windows\Fonts\consola.ttf"

CASES = [
    ("A07", 1280, 720),
    ("A08", 1920, 1080),
    ("A09", 1024, 768),
    ("A10", 800, 600),
    ("B05", 1600, 1200),
    ("B06", 2560, 1440),
]


def n_of(w, h):
    nx = 1 if w <= 640 else (2 if w <= 1280 else (3 if w <= 1920 else 4))
    ny = 1 if h <= 480 else (2 if h <= 960 else (3 if h <= 1440 else 4))
    return max(nx, ny)


def make(name, w, h):
    im = Image.new("RGB", (w, h), (0xEE, 0xF5, 0xFC))
    d = ImageDraw.Draw(im)

    # 64 px 网格（浅灰），方便看抽取有没有错行
    for x in range(0, w, 64):
        d.line([(x, 0), (x, h)], fill=(0xD8, 0xE2, 0xEC), width=max(1, w // 640))
    for y in range(0, h, 64):
        d.line([(0, y), (w, y)], fill=(0xD8, 0xE2, 0xEC), width=max(1, w // 640))

    # 外框（深蓝）+ 四角色块（红/绿/蓝/黄），任何一个角不见了就说明被裁了
    m = max(2, w // 160)
    d.rectangle([m, m, w - 1 - m, h - 1 - m], outline=(0x2C, 0x3E, 0x7A), width=m * 2)
    s = max(16, w // 12)
    d.rectangle([0, 0, s, s], fill=(0xE0, 0x30, 0x30))
    d.rectangle([w - 1 - s, 0, w - 1, s], fill=(0x20, 0xA0, 0x40))
    d.rectangle([0, h - 1 - s, s, h - 1], fill=(0x20, 0x50, 0xD0))
    d.rectangle([w - 1 - s, h - 1 - s, w - 1, h - 1], fill=(0xE0, 0xC0, 0x20))

    n = n_of(w, h)
    tw, th = (w + n - 1) // n, (h + n - 1) // n

    # 中间大字
    f1 = ImageFont.truetype(FONT_NUM, max(20, h // 6))
    f2 = ImageFont.truetype(FONT_CN, max(14, h // 14))
    f3 = ImageFont.truetype(FONT_NUM, max(12, h // 22))
    t1 = "%d x %d" % (w, h)
    t2 = "N=%d  ->  %d x %d" % (n, tw, th)
    t3 = "TEST %s" % name
    y0 = h // 2 - h // 8
    d.text((w // 2, y0), t1, font=f1, fill=(0x20, 0x2A, 0x40), anchor="mm")
    d.text((w // 2, y0 + h // 7), t2, font=f2, fill=(0x1E, 0x64, 0x9A), anchor="mm")
    d.text((w // 2, h - h // 10), t3, font=f3, fill=(0x40, 0x48, 0x58), anchor="mm")
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, w, h in CASES:
        im = make(name, w, h)
        p = os.path.join(OUT, name + ".BMP")
        im.save(p, "BMP")
        print("%-4s %5dx%-5d -> %4dx%-4d  N=%d  %8d 字节" %
              (name, w, h, (w + n_of(w, h) - 1) // n_of(w, h),
               (h + n_of(w, h) - 1) // n_of(w, h), n_of(w, h), os.path.getsize(p)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
