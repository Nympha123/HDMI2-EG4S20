#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""make_zone_badges.py -- 目录页「展区徽标」素材生成（方案 D）

取代原来的 SDRAM 截图缩略图：左侧预览框改成 4 个展区的专属徽标
（编钟 / 青铜鼎 / 唐三彩马 / 越王勾践剑），2 倍像素放大，套色印刷风。

做法：图标只画"色块"，描边由程序统一钩一次外轮廓（sticker 风），
细线（纹样/鬃毛/缠缑）才手工画 ink —— 这样叠在一起的形体不会出现
互相穿插的描边，低分辨率下更清楚。

板端资源：
  * 1 个展区 = 108x81 像素 x 2 平面（accent 面 / ink 面）= 2 x 8748 bit
  * 4 个展区 = 2 片 ROM，每片 34992 x 1 bit -> 各 4 块 BRAM9K，共 8 块
    （原来是 96x72 RGB444 缩略图缓存 8192x12 = 11 块 BRAM，净省 3 块）
  * 显示区 216x162 @ (39,20)，最近邻 2 倍放大：0 BRAM、0 乘法器

输出：
  rtl/zone_badge_acc.hex           accent 平面（34992 行，每行 1 bit）
  rtl/zone_badge_ink.hex           ink 平面（34992 行，每行 1 bit）
  tools/_preview/zone_badges.png   4 个徽标 2 倍放大拼图
  tools/_preview/zone_detail_N.png 单区 4 倍放大（看细节）
  tools/_preview/zone_page_N.png   目录页 640x480 效果模拟

地址：addr = zone*8748 + y*108 + x       (8748 = 108*81)
"""
import math
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RTL = os.path.join(ROOT, "rtl")
OUT = os.path.join(HERE, "_preview")

W, H = 108, 81           # 图源尺寸（显示 2 倍 -> 216x162）
ZONES = 4
ZSTRIDE = W * H          # 8748 = 108*81
SS = 8                   # 超采样倍数

# 材质编号：0 paper / 1 tint / 2 accent / 3 ink
PAPER, TINT, ACC, INK = 0, 1, 2, 3

# 每展区主色（显示侧；RTL 里有同名常量表，改色两边一起改）
ACCENTS = [
    0x3F9ED8,   # A 曾侯乙编钟  青（沿用页面强调色）
    0x3F9C86,   # B 青铜礼器    铜绿
    0xD9902E,   # C 唐三彩      琥珀
    0xC2563A,   # D 越王勾践剑  朱
]
PAPER_RGB = (0xF7, 0xFA, 0xFD)
INK_RGB = (0x25, 0x44, 0x5C)

CCX, CCY = 54.0, 40.0    # 徽标圆心


def rgb24(v):
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255)


def tint_of(v):
    """tint = 50% accent + 50% white（与 RTL 的 (A>>1)+0x80 一致）"""
    return tuple(min(255, (c >> 1) + 0x80) for c in rgb24(v))


# --------------------------------------------------------------------------
# 画布：材质索引图（超采样）。Xf 提供围绕圆心的缩放/平移，方便调比例。
# --------------------------------------------------------------------------
class Plate:
    def __init__(self):
        self.im = Image.new("L", (W * SS, H * SS), PAPER)
        self.d = ImageDraw.Draw(self.im)

    @staticmethod
    def _s(v):
        return int(round(v * SS))

    def xf(self, s=1.0, dx=0.0, dy=0.0):
        return Xf(self, s, dx, dy)

    def rect(self, x0, y0, x1, y1, m):
        self.d.rectangle([self._s(x0), self._s(y0), self._s(x1), self._s(y1)], fill=m)

    def ring_rect(self, x0, y0, x1, y1, w, m):
        s, ww = self._s, max(1, self._s(w))
        x0, y0, x1, y1 = s(x0), s(y0), s(x1), s(y1)
        self.d.rectangle([x0, y0, x1, y0 + ww], fill=m)
        self.d.rectangle([x0, y1 - ww, x1, y1], fill=m)
        self.d.rectangle([x0, y0, x0 + ww, y1], fill=m)
        self.d.rectangle([x1 - ww, y0, x1, y1], fill=m)

    def poly(self, pts, m):
        self.d.polygon([(self._s(x), self._s(y)) for x, y in pts], fill=m)

    def line(self, pts, w, m):
        self.d.line([(self._s(x), self._s(y)) for x, y in pts],
                    fill=m, width=max(1, self._s(w)), joint="curve")

    def ellipse(self, cx, cy, rx, ry, m):
        self.d.ellipse([self._s(cx - rx), self._s(cy - ry),
                        self._s(cx + rx), self._s(cy + ry)], fill=m)

    def ring(self, cx, cy, r, w, m):
        self.d.ellipse([self._s(cx - r), self._s(cy - r),
                        self._s(cx + r), self._s(cy + r)],
                       outline=m, width=max(1, self._s(w)))


class Xf:
    """围绕 (CCX,CCY) 的等比缩放 + 平移代理"""

    def __init__(self, p, s, dx, dy):
        self.p, self.s, self.dx, self.dy = p, s, dx, dy

    def xf(self, s=1.0, dx=0.0, dy=0.0):
        return Xf(self.p, self.s * s, self.dx + dx * self.s, self.dy + dy * self.s)

    def _x(self, x):
        return CCX + (x - CCX) * self.s + self.dx

    def _y(self, y):
        return CCY + (y - CCY) * self.s + self.dy

    def _pts(self, pts):
        return [(self._x(x), self._y(y)) for x, y in pts]

    def rect(self, x0, y0, x1, y1, m):
        self.p.rect(self._x(x0), self._y(y0), self._x(x1), self._y(y1), m)

    def ring_rect(self, x0, y0, x1, y1, w, m):
        self.p.ring_rect(self._x(x0), self._y(y0), self._x(x1), self._y(y1), w * self.s, m)

    def poly(self, pts, m):
        self.p.poly(self._pts(pts), m)

    def line(self, pts, w, m):
        self.p.line(self._pts(pts), w * self.s, m)

    def ellipse(self, cx, cy, rx, ry, m):
        self.p.ellipse(self._x(cx), self._y(cy), rx * self.s, ry * self.s, m)

    def ring(self, cx, cy, r, w, m):
        self.p.ring(self._x(cx), self._y(cy), r * self.s, w * self.s, m)


# --------------------------------------------------------------------------
# 图标（局部坐标以 (54,40) 为中心）：只画色块 + 内部细线，外轮廓自动生成
# --------------------------------------------------------------------------
def icon_bells(p):
    """曾侯乙编钟：横梁 + 两枚甬钟（宽口、平底，钟形最好认）"""
    p.rect(32.0, 22.6, 76.0, 27.4, ACC)                              # 横梁
    p.ellipse(32.0, 25.0, 2.7, 2.7, ACC)                             # 梁端圆头
    p.ellipse(76.0, 25.0, 2.7, 2.7, ACC)

    for cx, hw, bot in ((45.0, 7.4, 55.0), (63.0, 7.4, 55.0)):
        top = 28.2
        p.rect(cx - 1.1, 26.6, cx + 1.1, top + 1.0, ACC)             # 挂钮
        p.poly([(cx - hw * 0.60, top + 1.4), (cx - hw * 0.54, top),
                (cx + hw * 0.54, top), (cx + hw * 0.60, top + 1.4),
                (cx + hw * 0.74, top + 7.0), (cx + hw, bot - 1.2),
                (cx + hw * 0.96, bot), (cx - hw * 0.96, bot),
                (cx - hw, bot - 1.2), (cx - hw * 0.74, top + 7.0)], ACC)
        p.line([(cx - hw * 0.80, bot - 4.6), (cx + hw * 0.80, bot - 4.6)], 0.9, INK)
        p.line([(cx - hw * 0.64, top + 6.0), (cx + hw * 0.64, top + 6.0)], 0.8, INK)


def icon_ding(p):
    """青铜礼器：立耳三足鼎"""
    for x0 in (37.8, 63.4):                                          # 双耳（带孔）
        p.rect(x0, 19.4, x0 + 6.4, 29, ACC)
        p.rect(x0 + 2.2, 22.2, x0 + 4.2, 28, PAPER)
    p.rect(33.4, 27.2, 74.6, 32, ACC)                                # 口沿
    p.poly([(34.4, 32), (73.6, 32), (70.2, 43.5), (64.8, 50.5),
            (43.2, 50.5), (37.8, 43.5)], ACC)                        # 腹
    p.line([(36.6, 35.6), (71.4, 35.6)], 0.9, INK)                   # 纹带
    for i in range(5):
        x = 39.8 + i * 5.7
        p.rect(x, 37.9, x + 2.5, 40.2, INK)
    for x0 in (43.4, 52.4, 61.4):                                    # 三足
        p.rect(x0, 50, x0 + 4.0, 60, ACC)
    p.line([(39.6, 43.2), (68.4, 43.2)], 0.8, INK)                   # 腹部下沿


def icon_horse(p0):
    """唐三彩：鞍马（整体色块 + 鬃毛/鞍/眼细线）"""
    p = p0.xf(1.0, -1.5, 1.5)
    for x0, x1 in ((36.5, 40.5), (42.5, 46.5), (56.0, 60.0), (62.0, 66.0)):
        p.rect(x0, 43.5, x1, 58.5, ACC)                              # 四腿
    p.poly([(35.0, 33.0), (37.5, 31.0), (46.0, 30.0), (58.0, 30.5),
            (63.0, 32.5), (65.5, 36.0), (65.0, 41.0), (62.0, 45.5),
            (46.0, 46.0), (37.0, 43.5), (35.0, 38.0)], ACC)          # 身体
    p.poly([(60.0, 38.0), (63.0, 24.0), (69.8, 24.6), (66.2, 40.0)], ACC)   # 颈
    p.poly([(62.6, 24.6), (66.0, 19.2), (73.6, 19.6), (76.0, 23.2),
            (75.0, 27.2), (66.6, 27.0)], ACC)                        # 头
    p.poly([(66.4, 19.6), (67.4, 15.0), (69.4, 19.8)], ACC)          # 双耳
    p.poly([(70.4, 19.4), (72.0, 15.2), (73.2, 19.8)], ACC)
    p.poly([(34.8, 33.4), (29.6, 39.6), (30.8, 46.6), (33.0, 45.2),
            (32.2, 40.0)], ACC)                                      # 尾
    # 内部细线
    for i in range(4):                                               # 鬃毛
        p.rect(64.4 + i * 0.5, 25.4 + i * 3.6, 66.0 + i * 0.5, 27.8 + i * 3.6, INK)
    p.line([(45.0, 30.4), (56.8, 31.0), (58.4, 37.6), (46.2, 37.0),
            (45.0, 30.4)], 0.9, INK)                                 # 鞍
    p.rect(49.4, 32.0, 53.2, 35.6, INK)
    p.rect(71.6, 21.6, 73.4, 23.2, INK)                              # 眼
    p.line([(46.2, 37.0), (45.4, 42.6)], 0.8, INK)                   # 鞦带


def icon_sword(p):
    """越王勾践剑：菱形暗花纹 + 剑首圆盘"""
    p.ellipse(54, 59.2, 4.4, 4.4, ACC)                               # 剑首
    p.rect(50.6, 45.0, 57.4, 56.0, ACC)                              # 剑柄
    p.rect(43.8, 40.8, 64.2, 45.4, ACC)                              # 护手
    p.poly([(54, 15.0), (58.4, 22.6), (58.4, 41.0),
            (49.6, 41.0), (49.6, 22.6)], ACC)                        # 剑身
    # 内部细线
    for y in (24.6, 29.8, 35.0):                                     # 菱形暗纹
        p.line([(54, y), (57.6, y + 3.6)], 0.9, INK)
        p.line([(54, y), (50.4, y + 3.6)], 0.9, INK)
    p.line([(54, 17.2), (54, 21.2)], 0.9, INK)                       # 中脊
    p.rect(50.8, 41.0, 57.2, 45.2, INK)                              # 格心
    for i in range(3):                                               # 缠缑
        y = 47.2 + i * 3.1
        p.line([(50.8, y), (57.2, y + 2.0)], 0.9, INK)
    p.ellipse(54, 59.2, 1.5, 1.5, INK)                               # 剑首中心


ICONS = [icon_bells, icon_ding, icon_horse, icon_sword]


# --------------------------------------------------------------------------
# 降采样 / 自动描边
# --------------------------------------------------------------------------
def downsample(im):
    """超采样材质图 -> 108x81 材质图（取覆盖率最大的材质，平手偏向更深的材质）"""
    px = im.load()
    out = Image.new("L", (W, H), PAPER)
    o = out.load()
    for y in range(H):
        for x in range(W):
            cnt = [0, 0, 0, 0]
            for sy in range(SS):
                for sx in range(SS):
                    cnt[px[x * SS + sx, y * SS + sy]] += 1
            best, bestc = PAPER, cnt[PAPER]
            for m in (TINT, ACC, INK):
                if cnt[m] >= bestc:
                    best, bestc = m, cnt[m]
            o[x, y] = best
    return out


def outline_layer(mat_img):
    """给图层统一钩 1px 外轮廓；返回 (图层材质图, 覆盖掩码)"""
    px = mat_img.load()
    solid = [[px[x, y] != PAPER for y in range(H)] for x in range(W)]

    def inside(x, y):
        return 0 <= x < W and 0 <= y < H and solid[x][y]

    out = Image.new("L", (W, H), PAPER)
    o = out.load()
    for y in range(H):
        for x in range(W):
            if not solid[x][y]:
                continue
            edge = not (inside(x - 1, y) and inside(x + 1, y) and
                        inside(x, y - 1) and inside(x, y + 1))
            o[x, y] = INK if edge else px[x, y]
    return out


# --------------------------------------------------------------------------
# 版式：斜纹底 + 粗色边框 + 四角标 + 白盘 + 刻度 + 展区指示点 + 图标
#   2026-10-24 v3：边框从 1px 加粗到 2px（显示 4px）—— 1px 线在 640x480 上
#   再经过显示器缩放/相机采样会糊成"深红灰"，换区时看不出是展区色。
# --------------------------------------------------------------------------
def compose(zone):
    p = Plate()
    # 斜纹底（tint = 50% 主色，浅但看得出冷暖）
    p.rect(0, 0, W - 1, H - 1, TINT)
    for k in range(-H, W + H, 7):
        p.line([(k, 0), (k + H, H)], 1.1, PAPER)
    # 粗外框：2 px
    p.ring_rect(0, 0, W - 1, H - 1, 2.0, ACC)
    # 四角直角标（1.5 px）
    for cx, cy, sx, sy in ((7, 7, 1, 1), (W - 8, 7, -1, 1),
                           (7, H - 8, 1, -1), (W - 8, H - 8, -1, -1)):
        p.line([(cx, cy + sy * 6), (cx, cy), (cx + sx * 6, cy)], 1.5, ACC)

    # 中央白盘 + 粗圆环（2 px）+ 细外环
    p.ellipse(CCX, CCY, 27.0, 27.0, PAPER)
    p.ring(CCX, CCY, 27.0, 2.0, ACC)
    p.ring(CCX, CCY, 30.2, 1.0, ACC)
    # 刻度（24 格，四正位加长）
    for k in range(24):
        a = k * math.pi / 12
        r0, r1 = (33.0, 35.8) if k % 6 == 0 else (33.8, 35.2)
        p.line([(CCX + r0 * math.cos(a), CCY + r0 * math.sin(a)),
                (CCX + r1 * math.cos(a), CCY + r1 * math.sin(a))], 1.0, ACC)

    # 图标图层（自动描边）贴上来
    ip = Plate()
    ICONS[zone](ip.xf(1.0))
    icon = outline_layer(downsample(ip.im))
    up = icon.resize((W * SS, H * SS), Image.NEAREST)
    mask = Image.eval(icon, lambda v: 255 if v != PAPER else 0)\
                .resize((W * SS, H * SS), Image.NEAREST)
    p.im.paste(up, (0, 0), mask)

    # 底部展区指示点（4 格，当前展区实心）
    x0 = CCX - 9
    for k in range(4):
        x = x0 + k * 6
        if k == zone:
            p.rect(x, 72.8, x + 3.4, 76.0, ACC)
        else:
            p.ring_rect(x, 72.8, x + 3.4, 76.0, 0.8, INK)
    return p


# --------------------------------------------------------------------------
# 输出
# --------------------------------------------------------------------------
def write_code(path, mats):
    """写 2bit 材质码（每行 1 个 hex 位）：addr = zone*8748 + y*108 + x"""
    with open(path, "w", encoding="ascii") as f:
        for z in range(ZONES):
            px = mats[z].load()
            for y in range(H):
                for x in range(W):
                    f.write("%x\n" % px[x, y])


def write_plane(path, mats, bit):
    """写 1 bit/行 hex（材质码的第 bit 位）：addr = zone*8748 + y*108 + x 顺序展开"""
    with open(path, "w", encoding="ascii") as f:
        for z in range(ZONES):
            px = mats[z].load()
            for y in range(H):
                for x in range(W):
                    f.write("1\n" if (px[x, y] >> bit) & 1 else "0\n")


def recolor(mat_img, zone, scale=2):
    """材质图 -> RGB（最近邻放大）"""
    a = ACCENTS[zone]
    pal = {PAPER: PAPER_RGB, TINT: tint_of(a), ACC: rgb24(a), INK: INK_RGB}
    px = mat_img.load()
    out = Image.new("RGB", (W, H))
    o = out.load()
    for y in range(H):
        for x in range(W):
            o[x, y] = pal[px[x, y]]
    return out.resize((W * scale, H * scale), Image.NEAREST)


NAMES = ["曾侯乙编钟", "青铜礼器", "唐三彩", "越王勾践剑"]
DESCS = ["战国 · 青铜编钟", "商周 · 青铜礼器", "唐代 · 陶俑", "春秋 · 青铜兵器"]


def render_page(mats, sel):
    """按 directory_ui.v 现在的配色复刻整页（左侧整列 + 选中行跟着展区色）"""
    acc = rgb24(ACCENTS[sel])
    half = tuple(min(255, (c >> 1) + 128) for c in acc)     # 50% 主色
    quart = tuple(min(255, (c >> 2) + 192) for c in acc)    # 25% 主色
    page = Image.new("RGB", (640, 480), (0xEE, 0xF5, 0xFC))
    d = ImageDraw.Draw(page)
    # 左侧两框：边框 = 50% 展区色
    d.rectangle([14, 14, 279, 187], fill=(255, 255, 255), outline=half, width=4)
    d.rectangle([10, 202, 283, 447], fill=(255, 255, 255), outline=half, width=4)
    # 右列：页面蓝 -> 50% 展区色
    d.rectangle([294, 4, 635, 453], fill=(255, 255, 255), outline=half, width=4)
    page.paste(recolor(mats[sel], sel), (39, 20))
    try:
        f16 = ImageFont.truetype("C:/Windows/Fonts/simsun.ttc", 16)
    except Exception:
        f16 = ImageFont.load_default()
    d.text((24, 216), NAMES[sel], font=f16, fill=(0x25, 0x44, 0x5C))
    d.line([(24, 244), (260, 244)], fill=half, width=2)
    d.text((24, 260), DESCS[sel], font=f16, fill=(0x25, 0x44, 0x5C))
    d.text((24, 304), "请勿触摸展品", font=f16, fill=(0x25, 0x44, 0x5C))
    for i, n in enumerate(NAMES):
        y0 = 10 + i * 108
        hit = (i == sel)
        d.rectangle([300, y0, 621, y0 + 99],
                    fill=quart if hit else (255, 255, 255),
                    outline=acc if hit else quart, width=2)
        d.rectangle([312, y0 + 34, 321, y0 + 43], fill=acc)
        d.text((330, y0 + 42), n, font=f16, fill=(0x25, 0x44, 0x5C))
    # 右侧滚动条：整条 12..444，3 道缝 4 等分，当前段实心
    d.rectangle([626, 12, 630, 443], fill=quart)
    d.rectangle([626, 12 + sel * 108, 630, 12 + sel * 108 + 107], fill=acc)
    for y in (120, 228, 336):
        d.rectangle([626, y, 630, y + 1], fill=(255, 255, 255))
    return page


def main():
    mats = [downsample(compose(z).im) for z in range(ZONES)]

    os.makedirs(RTL, exist_ok=True)
    write_code(os.path.join(RTL, "zone_badge.hex"), mats)

    for z in range(ZONES):
        pa = sum(1 for v in mats[z].getdata() if v == ACC)
        pk = sum(1 for v in mats[z].getdata() if v == INK)
        print(f"zone {z}: accent {pa:5d} px  ink {pk:5d} px  "
              f"({(pa + pk) / (W * H):.1%} covered)")

    os.makedirs(OUT, exist_ok=True)
    sheet = Image.new("RGB", (ZONES * (W * 2 + 12) + 12, H * 2 + 24), (238, 245, 252))
    for z in range(ZONES):
        sheet.paste(recolor(mats[z], z), (12 + z * (W * 2 + 12), 12))
    sheet.save(os.path.join(OUT, "zone_badges.png"))
    for z in range(ZONES):
        recolor(mats[z], z, 4).save(os.path.join(OUT, f"zone_detail_{z}.png"))
    for z in range(ZONES):
        render_page(mats, z).save(os.path.join(OUT, f"zone_page_{z}.png"))
    print("preview:", OUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
