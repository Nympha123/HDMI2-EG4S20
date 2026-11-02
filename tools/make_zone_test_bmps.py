from PIL import Image, ImageDraw, ImageFont
import os, shutil

W, H = 640, 480
OUT = r"C:\Users\30685\Desktop\HDMI2\test_images_zones"
os.makedirs(OUT, exist_ok=True)

font_path = r"C:\Windows\Fonts\arialbd.ttf"
font_big = ImageFont.truetype(font_path, 150)
font_mid = ImageFont.truetype(font_path, 42)
font_small = ImageFont.truetype(font_path, 26)

# distinct background colours per zone
zone_bg = {
    'A': (200, 60, 60),
    'B': (40, 120, 200),
    'C': (40, 160, 90),
    'D': (150, 80, 190),
}

def make(name, zone, num):
    img = Image.new("RGB", (W, H), zone_bg[zone])
    d = ImageDraw.Draw(img)
    # checker/grid so scaling/tearing is obvious
    for y in range(0, H, 60):
        for x in range(0, W, 60):
            if ((x // 60) + (y // 60)) % 2 == 0:
                d.rectangle([x, y, x + 59, y + 59], fill=tuple(min(255, c + 22) for c in zone_bg[zone]))
    # border
    d.rectangle([4, 4, W - 5, H - 5], outline=(255, 255, 255), width=8)
    # corner markers
    for (cx, cy) in [(30, 30), (W - 30, 30), (30, H - 30), (W - 30, H - 30)]:
        d.ellipse([cx - 12, cy - 12, cx + 12, cy + 12], fill=(255, 255, 255))
    label = f"{zone}{num:02d}"
    bbox = d.textbbox((0, 0), label, font=font_big)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text(((W - tw) / 2 - bbox[0], 150 - bbox[1]), label, font=font_big, fill=(255, 255, 255))
    sub = f"ZONE {zone}  /  IMAGE {num:02d}"
    bbox = d.textbbox((0, 0), sub, font=font_mid)
    tw = bbox[2] - bbox[0]
    d.text(((W - tw) / 2 - bbox[0], 320), sub, font=font_mid, fill=(255, 255, 255))
    foot = "640x480 24-bit BMP  TEST PATTERN"
    bbox = d.textbbox((0, 0), foot, font=font_small)
    tw = bbox[2] - bbox[0]
    d.text(((W - tw) / 2 - bbox[0], 390), foot, font=font_small, fill=(255, 255, 255))
    path = os.path.join(OUT, f"{zone}{num:02d}.BMP")
    img.save(path, format="BMP")
    return path

files = []
for n in range(5, 11):
    files.append(make("A", "A", n))
for n in range(2, 11):
    files.append(make("B", "B", n))
for n in range(1, 11):
    files.append(make("C", "C", n))
for n in range(1, 11):
    files.append(make("D", "D", n))

for p in files:
    shutil.copy2(p, "E:\\" + os.path.basename(p))

for p in files:
    print(os.path.basename(p), os.path.getsize(p))
