# -*- coding: utf-8 -*-
"""A 区六页统一生成：
   A01~A04  原位改页码（第 n 页 / 共 6 页）+ 重画 6 段进度条
   A05/A06  用未使用的实景照片按 A01 版式重建，正文换成自己的内容，
            并在正文最后加“该图片从 W×H 缩放适配到 640×480”
用法： python make_a_zone_pages.py
"""
import os, struct
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SDF  = os.path.join(ROOT, "SD卡上内容")
PH   = r"E:\AnLU_QianSai\嵌赛\应用场景\博物馆照片-实拍\曾侯乙编钟"
PREV = os.path.join(ROOT, "tools", "_preview")
F_TXT, F_BOLD = r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\msyhbd.ttc"

PHOTO = (35, 67, 270, 349)
PILL  = (46, 74, 111, 96)
LINE_Y, LINE_X = 63, 331
# 进度条：6 段，和 B01 的四段同风格（圆角、等高），只是更窄以放得下 6 段
BARS_X0, BARS_Y0, BARS_Y1, NBARS = 318, 132, 141, 6
BAR_W, BAR_GAP = 15, 7
BAR_ON, BAR_OFF = (229, 192, 60), (198, 208, 226)
# 正文版式（实测自 A01）
BODY_X, BODY_R, BODY_TOP, BODY_LH, BODY_INDENT = 318, 601, 160, 30.5, 36
BODY_FONT, BODY_COLOR = 18, (61, 75, 99)

TXT = {
 5: ("钟厅依墓室原状陈列，三层钟架按原大复原，六十五件青铜钟分列悬挂，重现战国礼乐场景。",
     "该图片从1280×960缩放适配到640×480。"),
 6: ("钟架通长七百四十八厘米，高二百七十三厘米，曲尺转角处长三百三十五厘米，可拆装搬运。",
     "该图片从1920×1440缩放适配到640×480。"),
}
BADGE = {5: "钟厅陈列", 6: "钟架尺寸"}

def load_bmp(p):
    d = open(p, "rb").read()
    off = struct.unpack_from("<I", d, 10)[0]
    w = struct.unpack_from("<i", d, 18)[0]
    h = struct.unpack_from("<i", d, 22)[0]
    px = np.frombuffer(d[off:off+w*abs(h)*3], dtype=np.uint8).reshape(abs(h), w, 3)
    if h > 0: px = px[::-1]
    return Image.fromarray(np.ascontiguousarray(px[:, :, ::-1]), "RGB")

def save_bmp(p, img):
    a = np.array(img.convert("RGB"))[:, :, ::-1]
    h, w, _ = a.shape
    hdr = bytearray(54); hdr[0:2] = b"BM"
    struct.pack_into("<I", hdr, 2, 54+w*h*3); struct.pack_into("<I", hdr, 10, 54)
    struct.pack_into("<I", hdr, 14, 40); struct.pack_into("<i", hdr, 18, w)
    struct.pack_into("<i", hdr, 22, h); struct.pack_into("<H", hdr, 26, 1)
    struct.pack_into("<H", hdr, 28, 24); struct.pack_into("<I", hdr, 34, w*h*3)
    struct.pack_into("<i", hdr, 38, 2835); struct.pack_into("<i", hdr, 42, 2835)
    open(p, "wb").write(bytes(hdr) + a[::-1].tobytes())

def erase_band(a, x0, x1, y0, y1):
    for y in range(y0, y1):
        l = a[y, x0-2].astype(float); r = a[y, x1+2].astype(float)
        n = x1-x0; t = (np.arange(n)[:, None])/max(n-1, 1)
        a[y, x0:x1] = np.round(l[None, :]*(1-t)+r[None, :]*t).astype(np.uint8)

def erase_text_rowmean(a, x0, x1, y0, y1, thr=10):
    """按“文字行”整带抹除：先检出每一行文字的 y 范围，再用该带上下两行干净背景
    做竖直线性插值填满 —— 无残影、无亮斑，装饰边缘（近竖直）位置不变。"""
    reg = a[y0:y1, x0:x1].astype(np.int16)
    lum = reg.sum(axis=2)
    ref = np.percentile(lum, 90, axis=1, keepdims=True)
    mask = lum < (ref - thr*3)
    rows = np.where(mask.any(axis=1))[0]
    if rows.size == 0:
        return
    bands = []; start = rows[0]; prev = rows[0]
    for r in rows[1:]:
        if r - prev <= 3:
            prev = r
        else:
            bands.append((start, prev)); start = r; prev = r
    bands.append((start, prev))
    for (b0, b1) in bands:
        ay0 = max(b0-1, 0); ay1 = min(b1+2, reg.shape[0]-1)     # 整带（含 AA 边缘）
        top = reg[max(ay0-2, 0), :].astype(float)
        bot = reg[min(ay1+2, reg.shape[0]-1), :].astype(float)
        n = ay1 - ay0
        if n <= 0: continue
        t = (np.arange(n)+1)[:, None]/(n+1)
        reg[ay0:ay1, :] = np.round(top[None, :]*(1-t[:, :, None]) + bot[None, :]*t[:, :, None]).astype(np.int16)
    a[y0:y1, x0:x1] = reg.astype(np.uint8)
def mask640(text, xy, size, anchor="lm", bold=False):
    SS = 4
    f = ImageFont.truetype(F_BOLD if bold else F_TXT, size*SS)
    t = Image.new("L", (640*SS, 480*SS), 0)
    ImageDraw.Draw(t).text((xy[0]*SS, xy[1]*SS), text, font=f, fill=255, anchor=anchor)
    return t.resize((640, 480), Image.LANCZOS).point(lambda v: 255 if v >= 150 else 0)

def stamp(img, m, S, color):
    mm = m if S == 1 else m.resize((640*S, 480*S), Image.NEAREST)
    img.paste(Image.new("RGB", img.size, color), (0, 0), mm)

def bars(img, active, S=1):
    d = ImageDraw.Draw(img)
    x = BARS_X0*S
    for i in range(NBARS):
        d.rounded_rectangle([x, BARS_Y0*S, x+BAR_W*S-1, BARS_Y1*S-1],
                            radius=4*S, fill=(BAR_ON if i == active else BAR_OFF))
        x += (BAR_W + BAR_GAP)*S

def tokenize(text):
    """把数字/字母/× 连成的串当成不可拆的整体，避免 “640×4 / 80” 这种断行"""
    toks = []; buf = ""
    for ch in text:
        if ch.isascii() and (ch.isalnum() or ch in "×.%+-"):
            buf += ch
        else:
            if buf: toks.append(buf); buf = ""
            toks.append(ch)
    if buf: toks.append(buf)
    return toks

def body_mask(paras):
    """多段正文。每段首行缩进 BODY_INDENT（两格），段内除末行外两端对齐，右边界严格 = BODY_R"""
    m = Image.new("L", (640, 480), 0); d = ImageDraw.Draw(m)
    f = ImageFont.truetype(F_TXT, BODY_FONT)
    layout = []                                  # (文本, 缩进, 是否两端对齐)
    for para in paras:
        toks = tokenize(para); i = 0; first = True; block = []
        while i < len(toks):
            ind = BODY_INDENT if first else 0
            avail = BODY_R - (BODY_X + ind)
            cur = ""
            while i < len(toks) and f.getlength(cur + toks[i]) <= avail:
                cur += toks[i]; i += 1
            if cur == "" and i < len(toks):
                cur = toks[i]; i += 1
            block.append((cur, ind)); first = False
        for k, (cur, ind) in enumerate(block):
            layout.append((cur, ind, k < len(block)-1))
    for li, (cur, ind, justify) in enumerate(layout):
        if not cur: continue
        x0 = BODY_X + ind
        width = BODY_R - x0
        slack = width - f.getlength(cur)
        per = slack/max(len(cur)-1, 1) if justify else 0.0
        x = float(x0); base = float(BODY_TOP+15+li*BODY_LH)
        for ch in cur:
            d.text((x, base), ch, font=f, fill=255, anchor="ls")
            x += f.getlength(ch) + per
    return m, len(layout)
def retitle_1x(page_no):
    p = os.path.join(SDF, "A0%d.BMP" % page_no)
    a = np.array(load_bmp(p))
    erase_band(a, 329, 440, 54, 72)          # 旧页码行
    erase_band(a, 310, 460, 126, 146)        # 旧进度条（4 段/6 段都覆盖）
    im = Image.fromarray(a)
    stamp(im, mask640("第 %d 页 / 共 6 页" % page_no, (LINE_X, LINE_Y), 11), 1, (118, 132, 154))
    bars(im, page_no-1)
    save_bmp(p, im)
    print("retitle", p)

def rebuild(photo, S, page_no, fit):
    a = np.array(load_bmp(os.path.join(SDF, "A01.BMP"))).astype(np.uint8)
    erase_text_rowmean(a, 306, 616, 144, 320)          # 抹 A01 正文
    erase_band(a, 329, 440, 54, 72)
    erase_band(a, 310, 460, 126, 146)
    a[PILL[1]+2:PILL[3]-2, PILL[0]+3:PILL[2]-3] = (252, 253, 255)
    big = Image.fromarray(a).resize((640*S, 480*S), Image.NEAREST)
    ph = Image.open(photo).convert("RGB")
    tw, th = (PHOTO[2]-PHOTO[0])*S, (PHOTO[3]-PHOTO[1])*S
    if fit == "cover":
        sc = max(tw/ph.width, th/ph.height)
        r2 = ph.resize((max(1, int(ph.width*sc)), max(1, int(ph.height*sc))), Image.LANCZOS)
        l = (r2.width-tw)//2; t = (r2.height-th)//2
        big.paste(r2.crop((l, t, l+tw, t+th)), (PHOTO[0]*S, PHOTO[1]*S))
    else:
        sc = min(tw/ph.width, th/ph.height)
        r2 = ph.resize((max(1, int(ph.width*sc)), max(1, int(ph.height*sc))), Image.LANCZOS)
        big.paste((255, 255, 255), (PHOTO[0]*S, PHOTO[1]*S, PHOTO[0]*S+tw, PHOTO[1]*S+th))
        big.paste(r2, (PHOTO[0]*S+(tw-r2.width)//2, PHOTO[1]*S+(th-r2.height)//2))
    body, nl = body_mask([TXT[page_no][0], TXT[page_no][1]])
    stamp(big, body, S, BODY_COLOR)
    stamp(big, mask640(BADGE[page_no], ((PILL[0]+PILL[2])//2, (PILL[1]+PILL[3])//2+1), 11, bold=True),
          S, (30, 78, 170))
    stamp(big, mask640("第 %d 页 / 共 6 页" % page_no, (LINE_X, LINE_Y), 11), S, (118, 132, 154))
    bars(big, page_no-1, S)
    out = os.path.join(SDF, "A0%d.BMP" % page_no)
    save_bmp(out, big)
    print("rebuild", out, big.size, "body lines:", nl)

if __name__ == "__main__":
    os.makedirs(PREV, exist_ok=True)
    for i in range(1, 5):
        retitle_1x(i)
    rebuild(os.path.join(PH, "OIP-C (3).webp"), 2, 5, "cover")
    rebuild(os.path.join(PH, "R-C.jpg"),        3, 6, "contain")
