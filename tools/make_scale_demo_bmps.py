# -*- coding: utf-8 -*-
import os, struct, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont

SD  = r"E:\AnLU_QianSai\HDMI2-EG4S20_New\HDMI2-EG4S20\SD卡上内容"
PH  = r"E:\AnLU_QianSai\嵌赛\应用场景\博物馆照片-实拍\曾侯乙编钟"
OUT = r"E:\deepseek_Project"
F_BADGE = r"C:\Windows\Fonts\msyhbd.ttc"
F_TXT   = r"C:\Windows\Fonts\msyh.ttc"

# 版面几何（640x480 基准，实测自 A01.BMP）
PHOTO = (35, 67, 270, 349)      # left, top, right(exclusive), bottom(exclusive)
PILL  = (46, 74, 111, 96)       # 白药丸
ANN_Y = 63                      # 分辨率标注的基线中线
ANN_X = 331
IND_X0, IND_X1 = 329, 436       # 旧的“第 n 页 / 共 4 页”要擦掉的横向范围
IND_Y0, IND_Y1 = 54, 72

def load_bmp(path):
    d = open(path, "rb").read()
    off = struct.unpack_from("<I", d, 10)[0]
    w   = struct.unpack_from("<i", d, 18)[0]
    h   = struct.unpack_from("<i", d, 22)[0]
    px  = np.frombuffer(d[off:off+w*abs(h)*3], dtype=np.uint8).reshape(abs(h), w, 3)
    img = Image.fromarray(px[::-1] if h > 0 else px, "RGB")   # -> top-down
    return img

def save_bmp(path, img):
    a = np.array(img.convert("RGB"))
    h, w, _ = a.shape
    rows = a[::-1]                      # bottom-up
    hdr = bytearray(54)
    hdr[0:2] = b"BM"
    struct.pack_into("<I", hdr, 2, 54 + w*h*3)
    struct.pack_into("<I", hdr, 10, 54)
    struct.pack_into("<I", hdr, 14, 40)
    struct.pack_into("<i", hdr, 18, w)
    struct.pack_into("<i", hdr, 22, h)
    struct.pack_into("<H", hdr, 26, 1)
    struct.pack_into("<H", hdr, 28, 24)
    struct.pack_into("<I", hdr, 34, w*h*3)
    struct.pack_into("<i", hdr, 38, 2835)   # 72 dpi
    struct.pack_into("<i", hdr, 42, 2835)
    with open(path, "wb") as f:
        f.write(bytes(hdr)); f.write(rows.tobytes())

def build(tpl_path, photo_path, S, badge, res_txt, out_path, fit="cover"):
    tpl = load_bmp(tpl_path)
    a = np.array(tpl).astype(np.int16)
    # 1) 擦掉旧的页码行：逐行在 x 两侧取样做线性插值（保住水平渐变）
    for y in range(IND_Y0, IND_Y1):
        l = a[y, IND_X0-3]
        r = a[y, IND_X1+3]
        n = IND_X1 - IND_X0
        t = (np.arange(n)[:, None]) / max(n-1, 1)
        a[y, IND_X0:IND_X1] = np.round(l[None, :]*(1-t) + r[None, :]*t).astype(np.int16)
    # 2) 擦白药丸内部（保留 1px 边框）
    a[PILL[1]+2:PILL[3]-2, PILL[0]+3:PILL[2]-3] = (252, 253, 255)
    base = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB")
    # 3) 放大到目标分辨率（最近邻：文字像素与 1x 完全一致，板上抽取后逐像素还原）
    big = base.resize((640*S, 480*S), Image.NEAREST)
    # 4) 贴照片
    ph = Image.open(photo_path).convert("RGB")
    tw, th = (PHOTO[2]-PHOTO[0])*S, (PHOTO[3]-PHOTO[1])*S
    if fit == "cover":
        sc = max(tw/ph.width, th/ph.height)
        r2 = ph.resize((max(1,int(math.ceil(ph.width*sc))), max(1,int(math.ceil(ph.height*sc)))), Image.LANCZOS)
        left = (r2.width - tw)//2; top = (r2.height - th)//2
        r2 = r2.crop((left, top, left+tw, top+th))
        big.paste(r2, (PHOTO[0]*S, PHOTO[1]*S))
    else:   # contain -> 白底居中（线稿类）
        sc = min(tw/ph.width, th/ph.height)
        r2 = ph.resize((max(1,int(ph.width*sc)), max(1,int(ph.height*sc))), Image.LANCZOS)
        big.paste((255,255,255), (PHOTO[0]*S, PHOTO[1]*S, PHOTO[0]*S+tw, PHOTO[1]*S+th))
        big.paste(r2, (PHOTO[0]*S + (tw-r2.width)//2, PHOTO[1]*S + (th-r2.height)//2))
    # 5) 药丸文字
    d = ImageDraw.Draw(big)
    fb = ImageFont.truetype(F_BADGE, 11*S)
    cx = (PILL[0]+PILL[2])//2*S; cy = (PILL[1]+PILL[3])//2*S
    d.text((cx, cy+1*S), badge, font=fb, fill=(30, 78, 170), anchor="mm")
    # 6) 分辨率标注（替代原来的“第 n 页 / 共 4 页”）
    ft = ImageFont.truetype(F_TXT, 12*S)
    d.text((ANN_X*S, ANN_Y*S), res_txt, font=ft, fill=(78, 150, 168), anchor="lm")
    save_bmp(out_path, big)
    # 预览：按板上抽取（每 S 个取 1）后应该就是 640x480 的正常页面
    dec = np.array(big)[::S, ::S]
    Image.fromarray(dec).save(out_path.replace(".BMP", "_dec.png"))
    print(out_path, big.size, os.path.getsize(out_path))

build(os.path.join(SD,"A01.BMP"), os.path.join(PH,"OIP-C (3).webp"), 2,
      "钟厅陈列", "源图 1280 × 960", os.path.join(SD,"A05.BMP"), "cover")
build(os.path.join(SD,"A01.BMP"), os.path.join(PH,"R-C.jpg"), 3,
      "钟架尺寸", "源图 1920 × 1440", os.path.join(SD,"A06.BMP"), "contain")
