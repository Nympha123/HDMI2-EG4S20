#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""preview_transition.py -- 按 RTL 的淡入淡出公式做切图过渡预览

RTL（top_tf_hdmi_audio.v 的 vout_fade）：
    out = C + ((pix - C) * a) >> 5        C = #EEF5FC（页面底色）
    a: 31 -> 0（淡出，约 11 帧）-> 换 buffer -> 0 -> 31（淡入，约 10 帧）
只作用于图片层；顶部/底部 OSD 不参与，所以示意图里只画图片层。

输出：tools/_preview/transition_strip.png（11 帧连拍）
"""
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "SD卡图片")
OUT = os.path.join(HERE, "_preview")
C = (0xEE, 0xF5, 0xFC)                 # 与 RTL 的 C_FADE 一致
FADE_OUT = [31, 28, 25, 22, 19, 16, 13, 10, 7, 4, 1, 0]
FADE_IN = [0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 31]
THUMB = (240, 180)


def blend(im, a):
    """out = C + ((pix - C) * a) >> 5"""
    if a >= 31:
        return im
    out = Image.new("RGB", im.size)
    px, o = im.load(), out.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            o[x, y] = tuple(max(0, min(255, c + (((v - c) * a) >> 5)))
                            for v, c in zip(px[x, y], C))
    return out


def main():
    old = Image.open(os.path.join(SRC, "IMAGE00.BMP")).convert("RGB")
    new = Image.open(os.path.join(SRC, "IMAGE04.BMP")).convert("RGB")
    frames = [blend(old, a) for a in FADE_OUT] + [blend(new, a) for a in FADE_IN]

    # 每 2 帧取一帧，避免太长
    show = frames[::2]
    sheet = Image.new("RGB", (THUMB[0] * len(show) + 8 * (len(show) + 1), THUMB[1] + 16),
                      (30, 34, 42))
    for i, f in enumerate(show):
        sheet.paste(f.resize(THUMB, Image.LANCZOS), (8 + i * (THUMB[0] + 8), 8))
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "transition_strip.png")
    sheet.save(path)
    print("saved", path)


if __name__ == "__main__":
    raise SystemExit(main())
