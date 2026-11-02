# -*- coding: utf-8 -*-
"""A05/A06：换成自己的正文（钟厅陈列 / 钟架尺寸），其它版式与 A01 一致。"""
import os, struct
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SDF  = os.path.join(ROOT, "SD卡上内容")
PH   = r"E:\AnLU_QianSai\嵌赛\应用场景\博物馆照片-实拍\曾侯乙编钟"
PREV = os.path.join(ROOT, "tools", "_preview")
F_TXT, F_BOLD = r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\msyhbd.ttc"

PHOTO=(35,67,270,349); PILL=(46,74,111,96)
LINE_Y,LINE_X,ANN_X = 63,331,452
BARS_X0,BARS_Y0,BARS_Y1,NBARS = 318,133,140,6
BODY_X, BODY_R, BODY_TOP, BODY_LH, BODY_INDENT = 318, 601, 160, 30.5, 36
BODY_FONT = 18
BODY_COLOR = (61,75,99)

TXT5 = ("钟厅按墓室原状陈列，三层曲尺形钟架依原大复原。六十五件青铜钟分列悬挂，"
        "钟体错金铭文与红色地毯相映，重现战国诸侯礼乐场景。")
TXT6 = ("钟架通长七百四十八厘米，高二百七十三厘米，曲尺转角处长三百三十五厘米。"
        "三层横梁承六十五件钟，可拆装搬运，是先秦大型乐器的制造典范。")

def load_bmp(p):
    d=open(p,"rb").read(); off=struct.unpack_from("<I",d,10)[0]
    w=struct.unpack_from("<i",d,18)[0]; h=struct.unpack_from("<i",d,22)[0]
    px=np.frombuffer(d[off:off+w*abs(h)*3],dtype=np.uint8).reshape(abs(h),w,3)
    if h>0: px=px[::-1]
    return Image.fromarray(np.ascontiguousarray(px[:,:,::-1]),"RGB")

def save_bmp(p,img):
    a=np.array(img.convert("RGB"))[:,:,::-1]; h,w,_=a.shape; hdr=bytearray(54); hdr[0:2]=b"BM"
    struct.pack_into("<I",hdr,2,54+w*h*3); struct.pack_into("<I",hdr,10,54); struct.pack_into("<I",hdr,14,40)
    struct.pack_into("<i",hdr,18,w); struct.pack_into("<i",hdr,22,h)
    struct.pack_into("<H",hdr,26,1); struct.pack_into("<H",hdr,28,24); struct.pack_into("<I",hdr,34,w*h*3)
    struct.pack_into("<i",hdr,38,2835); struct.pack_into("<i",hdr,42,2835)
    open(p,"wb").write(bytes(hdr)+a[::-1].tobytes())

def erase_text(a, x0, x1, y0, y1, rad=9, thr=12):
    """把"比局部亮背景更暗"的笔画像素替换成背景估计（横窗最大值），保留渐变/装饰"""
    reg = a[y0:y1, x0:x1].astype(np.int16)
    h, w, _ = reg.shape
    pad = np.pad(reg, ((0,0),(rad,rad),(0,0)), mode="edge")
    bg = np.maximum.reduce([pad[:, k:k+w, :] for k in range(2*rad+1)])
    m = (bg - reg).sum(axis=2) > thr*3
    reg[m] = bg[m]
    a[y0:y1, x0:x1] = reg.astype(np.uint8)
    return int(m.sum())

def erase_text_rowmean(a, x0, x1, y0, y1, thr=14):
    """把"明显比本行背景暗"的笔画像素，替换成本行背景均值（保住竖向渐变，不留亮斑）"""
    reg = a[y0:y1, x0:x1].astype(np.int16)
    lum = reg.sum(axis=2)
    ref = np.median(lum, axis=1, keepdims=True)
    mask = lum < (ref - thr*3)
    for y in range(reg.shape[0]):
        m = mask[y]
        if not m.any(): continue
        keep = reg[y][~m]
        if keep.size == 0: continue
        reg[y][m] = np.round(keep.mean(axis=0)).astype(np.int16)
    a[y0:y1, x0:x1] = reg.astype(np.uint8)
    return int(mask.sum())
def erase_text_v(a, x0, x1, y0, y1, rad=4, thr=8):
    """第二遍：竖直方向最大值滤波，抹掉只剩 AA 边缘的"残留行" """
    reg = a[y0:y1, x0:x1].astype(np.int16)
    h, w, _ = reg.shape
    pad = np.pad(reg, ((rad,rad),(0,0),(0,0)), mode="edge")
    bg = np.maximum.reduce([pad[k:k+h, :, :] for k in range(2*rad+1)])
    m = (bg - reg).sum(axis=2) > thr*3
    reg[m] = bg[m]
    a[y0:y1, x0:x1] = reg.astype(np.uint8)
    return int(m.sum())
def erase_band(a, x0, x1, y0, y1):
    for y in range(y0,y1):
        l=a[y,x0-2].astype(float); r=a[y,x1+2].astype(float)
        n=x1-x0; t=(np.arange(n)[:,None])/max(n-1,1)
        a[y,x0:x1]=np.round(l[None,:]*(1-t)+r[None,:]*t).astype(np.uint8)

def body_mask(text):
    m=Image.new("L",(640,480),0); d=ImageDraw.Draw(m)
    f=ImageFont.truetype(F_TXT,BODY_FONT)
    lines=[]; i=0
    while i < len(text):
        avail = (BODY_R-BODY_X-BODY_INDENT) if not lines else (BODY_R-BODY_X)
        cur=""
        while i < len(text) and f.getlength(cur+text[i]) <= avail:
            cur += text[i]; i += 1
        lines.append(cur)
    for li,ln in enumerate(lines):
        if not ln: continue
        slack=(BODY_R-BODY_X)-f.getlength(ln)
        per=slack/max(len(ln)-1,1) if li < len(lines)-1 else 0.0
        x=float(BODY_X + (BODY_INDENT if li==0 else 0))
        base=float(BODY_TOP+15+li*BODY_LH)
        for ch in ln:
            d.text((x,base), ch, font=f, fill=255, anchor="ls")
            x += f.getlength(ch) + per
    return m

def mask640(text,xy,size,anchor="lm",bold=False):
    SS=4; f=ImageFont.truetype(F_BOLD if bold else F_TXT,size*SS)
    t=Image.new("L",(640*SS,480*SS),0)
    ImageDraw.Draw(t).text((xy[0]*SS,xy[1]*SS),text,font=f,fill=255,anchor=anchor)
    return t.resize((640,480),Image.LANCZOS).point(lambda v:255 if v>=150 else 0)

def stamp(img,m,S,color):
    mm=m if S==1 else m.resize((640*S,480*S),Image.NEAREST)
    img.paste(Image.new("RGB",img.size,color),(0,0),mm)

def bars(img,active,S=1):
    d=ImageDraw.Draw(img); on=(229,192,60); off=(214,222,237)
    span=131*S; gap=6*S; w=(span-gap*(NBARS-1))//NBARS; x=BARS_X0*S
    for i in range(NBARS):
        d.rounded_rectangle([x,BARS_Y0*S,x+w-1,BARS_Y1*S-1],radius=3*S,fill=(on if i==active else off))
        x+=w+gap

def build(photo,S,badge,res,page_no,text,fit):
    a=np.array(load_bmp(os.path.join(SDF,"A01.BMP"))).astype(np.uint8)
    n=erase_text_rowmean(a, 306, 616, 144, 320, thr=5)
    erase_band(a,329,560,54,72)
    erase_band(a,314,452,130,143)
    a[PILL[1]+2:PILL[3]-2, PILL[0]+3:PILL[2]-3]=(252,253,255)
    big=Image.fromarray(a).resize((640*S,480*S),Image.NEAREST)
    ph=Image.open(photo).convert("RGB")
    tw,th=(PHOTO[2]-PHOTO[0])*S,(PHOTO[3]-PHOTO[1])*S
    if fit=="cover":
        sc=max(tw/ph.width,th/ph.height); r2=ph.resize((max(1,int(ph.width*sc)),max(1,int(ph.height*sc))),Image.LANCZOS)
        l=(r2.width-tw)//2; t=(r2.height-th)//2
        big.paste(r2.crop((l,t,l+tw,t+th)),(PHOTO[0]*S,PHOTO[1]*S))
    else:
        sc=min(tw/ph.width,th/ph.height); r2=ph.resize((max(1,int(ph.width*sc)),max(1,int(ph.height*sc))),Image.LANCZOS)
        big.paste((255,255,255),(PHOTO[0]*S,PHOTO[1]*S,PHOTO[0]*S+tw,PHOTO[1]*S+th))
        big.paste(r2,(PHOTO[0]*S+(tw-r2.width)//2,PHOTO[1]*S+(th-r2.height)//2))
    stamp(big,body_mask(text),S,BODY_COLOR)
    stamp(big,mask640(badge,((PILL[0]+PILL[2])//2,(PILL[1]+PILL[3])//2+1),11,bold=True),S,(30,78,170))
    stamp(big,mask640("第 %d 页 / 共 6 页"%page_no,(LINE_X,LINE_Y),11),S,(118,132,154))
    stamp(big,mask640(res,(ANN_X,LINE_Y),12),S,(70,146,164))
    bars(big,page_no-1,S)
    out=os.path.join(SDF,"A0%d.BMP"%page_no); save_bmp(out,big)
    Image.fromarray(np.array(big)[::S,::S]).save(os.path.join(PREV,"A0%d_dec.png"%page_no))
    print("built",out,big.size,"erased px",n)

if __name__=="__main__":
    build(os.path.join(PH,"OIP-C (3).webp"),2,"钟厅陈列","源图 1280×960",5,TXT5,"cover")
    build(os.path.join(PH,"R-C.jpg"),3,"钟架尺寸","源图 1920×1440",6,TXT6,"contain")
