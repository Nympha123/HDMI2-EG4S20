# -*- coding: utf-8 -*-
"""A 区 6 页统一：第 n 页 / 共 6 页 + 6 段进度条；A05/A06 额外标注源分辨率。
BMP 是 BGR 存储，读写都做通道转换，避免照片被红蓝对调。"""
import os, struct
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SDF  = os.path.join(ROOT, "SD卡上内容")
PH   = r"E:\AnLU_QianSai\嵌赛\应用场景\博物馆照片-实拍\曾侯乙编钟"
PREV = os.path.join(ROOT, "tools", "_preview")
F_TXT  = r"C:\Windows\Fonts\msyh.ttc"
F_BOLD = r"C:\Windows\Fonts\msyhbd.ttc"

PHOTO = (35, 67, 270, 349)
PILL  = (46, 74, 111, 96)
LINE_Y, LINE_X = 63, 331
ANN_X = 452
BARS_X0, BARS_Y0, BARS_Y1, NBARS = 318, 133, 140, 6

def load_bmp(p):
    d = open(p, "rb").read()
    off = struct.unpack_from("<I", d, 10)[0]
    w = struct.unpack_from("<i", d, 18)[0]
    h = struct.unpack_from("<i", d, 22)[0]
    px = np.frombuffer(d[off:off+w*abs(h)*3], dtype=np.uint8).reshape(abs(h), w, 3)
    if h > 0: px = px[::-1]                    # 正高度 = 底行在前
    px = px[:, :, ::-1]                        # BGR -> RGB
    return Image.fromarray(np.ascontiguousarray(px), "RGB")

def save_bmp(p, img):
    a = np.array(img.convert("RGB"))[:, :, ::-1]   # RGB -> BGR
    h, w, _ = a.shape
    hdr = bytearray(54); hdr[0:2] = b"BM"
    struct.pack_into("<I", hdr, 2, 54+w*h*3); struct.pack_into("<I", hdr, 10, 54)
    struct.pack_into("<I", hdr, 14, 40); struct.pack_into("<i", hdr, 18, w)
    struct.pack_into("<i", hdr, 22, h); struct.pack_into("<H", hdr, 26, 1)
    struct.pack_into("<H", hdr, 28, 24); struct.pack_into("<I", hdr, 34, w*h*3)
    struct.pack_into("<i", hdr, 38, 2835); struct.pack_into("<i", hdr, 42, 2835)
    open(p, "wb").write(bytes(hdr) + a[::-1].tobytes())

def erase(a, x0, x1, y0, y1):
    for y in range(y0, y1):
        l = a[y, x0-2].astype(float); r = a[y, x1+2].astype(float)
        n = x1-x0; t = (np.arange(n)[:, None])/max(n-1, 1)
        a[y, x0:x1] = np.round(l[None, :]*(1-t)+r[None, :]*t).astype(np.uint8)

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
    d = ImageDraw.Draw(img); on = (229,192,60); off = (214,222,237)
    span = 131*S; gap = 6*S; w = (span-gap*(NBARS-1))//NBARS; x = BARS_X0*S
    for i in range(NBARS):
        d.rounded_rectangle([x, BARS_Y0*S, x+w-1, BARS_Y1*S-1], radius=3*S,
                            fill=(on if i == active else off))
        x += w + gap

def rebuild_1x(path, page_no):
    a = np.array(load_bmp(path))
    erase(a, 329, 432, 54, 72)
    erase(a, 314, 452, 130, 143)
    im = Image.fromarray(a)
    stamp(im, mask640(f"第 {page_no} 页 / 共 6 页", (LINE_X, LINE_Y), 11), 1, (118,132,154))
    bars(im, page_no-1)
    save_bmp(path, im)
    im.save(os.path.join(PREV, f"A0{page_no}_dec.png"))
    print("1x", path, im.size)

def rebuild_scaled(photo, S, badge, res, page_no, fit="cover"):
    tpl = np.array(load_bmp(os.path.join(SDF, "A01.BMP")))
    erase(tpl, 329, 560, 54, 72)
    erase(tpl, 314, 452, 130, 143)
    tpl[PILL[1]+2:PILL[3]-2, PILL[0]+3:PILL[2]-3] = (252, 253, 255)
    big = Image.fromarray(tpl).resize((640*S, 480*S), Image.NEAREST)
    ph = Image.open(photo).convert("RGB")
    tw, th = (PHOTO[2]-PHOTO[0])*S, (PHOTO[3]-PHOTO[1])*S
    if fit == "cover":
        sc = max(tw/ph.width, th/ph.height)
        r2 = ph.resize((max(1,int(ph.width*sc)), max(1,int(ph.height*sc))), Image.LANCZOS)
        l = (r2.width-tw)//2; t = (r2.height-th)//2
        big.paste(r2.crop((l, t, l+tw, t+th)), (PHOTO[0]*S, PHOTO[1]*S))
    else:
        sc = min(tw/ph.width, th/ph.height)
        r2 = ph.resize((max(1,int(ph.width*sc)), max(1,int(ph.height*sc))), Image.LANCZOS)
        big.paste((255,255,255), (PHOTO[0]*S, PHOTO[1]*S, PHOTO[0]*S+tw, PHOTO[1]*S+th))
        big.paste(r2, (PHOTO[0]*S+(tw-r2.width)//2, PHOTO[1]*S+(th-r2.height)//2))
    stamp(big, mask640(badge, ((PILL[0]+PILL[2])//2, (PILL[1]+PILL[3])//2+1), 11, bold=True), S, (30,78,170))
    stamp(big, mask640(f"第 {page_no} 页 / 共 6 页", (LINE_X, LINE_Y), 11), S, (118,132,154))
    stamp(big, mask640(res, (ANN_X, LINE_Y), 12), S, (70,146,164))
    bars(big, page_no-1, S)
    out = os.path.join(SDF, f"A0{page_no}.BMP")
    save_bmp(out, big)
    dec = np.array(big)[::S, ::S]
    Image.fromarray(dec).save(os.path.join(PREV, f"A0{page_no}_dec.png"))
    print("Nx", out, big.size)

if __name__ == "__main__":
    os.makedirs(PREV, exist_ok=True)
    for i in range(1, 5):
        rebuild_1x(os.path.join(SDF, f"A0{i}.BMP"), i)
    rebuild_scaled(os.path.join(PH, "OIP-C (3).webp"), 2, "钟厅陈列", "源图 1280×960", 5, "cover")
    rebuild_scaled(os.path.join(PH, "R-C.jpg"),        3, "钟架尺寸", "源图 1920×1440", 6, "contain")
