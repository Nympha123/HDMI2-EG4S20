#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""draw_icons.py - 生成主菜单右侧 4 个博物馆图标（44x44 1bpp）"""
import os
from PIL import Image, ImageDraw

OUT = os.environ.get("ICON_PREVIEW_DIR", os.path.join(os.path.dirname(os.path.abspath(__file__)), "_preview"))
S = 44
SS = 8


def canvas():
    return Image.new("L", (S * SS, S * SS), 0)


def finish(im):
    im = im.resize((S, S), Image.LANCZOS)
    px = im.load()
    out = Image.new("L", (S, S), 0)
    o = out.load()
    for y in range(S):
        for x in range(S):
            o[x, y] = 255 if px[x, y] > 80 else 0
    return out


def sc(v):
    return int(round(v * SS))


def bar(d, x0, y0, x1, y1):
    """实心条（坐标为目标像素，含端点）"""
    d.rectangle([sc(x0), sc(y0), sc(x1), sc(y1)], fill=255)


def stroke(d, pts, w=1.6):
    d.line([(sc(x), sc(y)) for x, y in pts], fill=255, width=sc(w), joint="curve")


def ring(d, cx, cy, r, w=1.6):
    d.ellipse([sc(cx - r), sc(cy - r), sc(cx + r), sc(cy + r)], outline=255, width=sc(w))


# ---------------------------------------------------------------- 编钟
def icon_bells():
    im = canvas(); d = ImageDraw.Draw(im)
    bar(d, 5, 7, 39, 9)            # 横梁
    bar(d, 6, 9, 8, 37)            # 左柱
    bar(d, 36, 9, 38, 37)          # 右柱
    bar(d, 3, 36, 41, 38)          # 底座
    for cx in (14, 22, 30):
        bar(d, cx - 1, 10, cx + 1, 13)        # 挂钮
        d.polygon([(sc(cx - 4), sc(14)), (sc(cx + 4), sc(14)),
                   (sc(cx + 3), sc(27)), (sc(cx), sc(30)), (sc(cx - 3), sc(27))],
                  outline=255, width=sc(1.4))
    return finish(im)


# ---------------------------------------------------------------- 鼎
def icon_ding():
    im = canvas(); d = ImageDraw.Draw(im)
    bar(d, 7, 14, 37, 17)                       # 口沿
    stroke(d, [(10, 17), (34, 17), (29, 31), (15, 31), (10, 17)], 1.6)   # 腹
    stroke(d, [(11, 8), (11, 15)], 1.6)         # 左耳
    stroke(d, [(15, 8), (15, 15)], 1.6)
    stroke(d, [(33, 8), (33, 15)], 1.6)
    stroke(d, [(29, 8), (29, 15)], 1.6)
    bar(d, 11, 8, 15, 9)
    bar(d, 29, 8, 33, 9)
    stroke(d, [(17, 31), (16, 39)], 1.6)        # 三足
    stroke(d, [(22, 31), (22, 39)], 1.6)
    stroke(d, [(27, 31), (28, 39)], 1.6)
    bar(d, 20, 22, 23, 25)                      # 圆点
    return finish(im)


# ---------------------------------------------------------------- 马
def icon_horse():
    im = canvas(); d = ImageDraw.Draw(im)
    stroke(d, [(12, 24), (30, 24), (31, 30), (12, 30), (12, 24)], 1.6)   # 身
    stroke(d, [(29, 24), (33, 14)], 1.6)                                 # 颈
    stroke(d, [(33, 14), (38, 12), (38, 17), (33, 17)], 1.4)             # 头
    for lx in (15, 20, 26, 30):                                          # 四腿
        stroke(d, [(lx, 30), (lx, 38)], 1.5)
    stroke(d, [(12, 25), (7, 29)], 1.5)                                  # 尾
    bar(d, 19, 25, 22, 28)                                               # 圆点
    return finish(im)


# ---------------------------------------------------------------- 剑
def icon_sword():
    im = canvas(); d = ImageDraw.Draw(im)
    stroke(d, [(22, 4), (27, 29)], 1.5)          # 剑身左
    stroke(d, [(22, 4), (17, 29)], 1.5)          # 剑身右
    stroke(d, [(17, 29), (27, 29)], 1.5)
    bar(d, 11, 29, 33, 32)                       # 护手
    bar(d, 20, 32, 24, 38)                       # 柄
    ring(d, 22, 40, 2.6, 1.5)                    # 剑首
    return finish(im)


def main():
    os.makedirs(OUT, exist_ok=True)
    icons = [("bells", icon_bells()), ("ding", icon_ding()),
             ("horse", icon_horse()), ("sword", icon_sword())]
    sheet = Image.new("RGB", (4 * (S * 6) + 40, S * 6 + 40), (246, 246, 250))
    for i, (n, im) in enumerate(icons):
        big = im.resize((S * 6, S * 6), Image.NEAREST).convert("RGB")
        sheet.paste(big, (10 + i * (S * 6 + 10), 10))
    sheet.save(os.path.join(OUT, "icons_preview.png"))
    print("icons preview:", os.path.join(OUT, "icons_preview.png"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
