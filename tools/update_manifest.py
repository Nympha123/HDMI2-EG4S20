#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""update_manifest.py -- 在 bitstream/MANIFEST.txt 顶部追加一条新版本记录（UTF-8）

用法（在工具里跑一次即可，记录改完就不需要再跑）：
    python tools/update_manifest.py
"""
import io
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MAN = os.path.join(ROOT, "bitstream", "MANIFEST.txt")

NEW = """# 当前版本：2026-10-24 目录页「展区徽标」版（方案 D）

| 项 | 值 |
|---|---|
| 文件 | HDMI2_HDMI14_Player_zone_badge.bit |
| 大小 | 669,200 字节 |
| MD5 | 803DDEBA69F55A2CD3A5E35D8AC7A299 |
| SHA-256 | 65BABEE3C1DBD42ED58C1C852D743B3382D7E73BEC2933E8F47C21C984DD4789 |
| 资源 | 4229 mslices / 15575 LUT / 6420 REG / 54 BRAM / 19 DSP |
| 时序 | Setup +988 ps / Hold +25 ps / 0 FEPS |
| 说明 | 目录页缩略图换成 4 个展区徽标（编钟/鼎/三彩马/剑，108x81 2bpp 源码，2 倍放大）；删掉 5x5 抽样 + thumb_mem（-11 BRAM、-3 乘法器）；ROM 共用 +8 BRAM |

上一版：HDMI2_HDMI14_Player_museum_menu.bit（525D5DB3…，96x72 截图缩略图）。
历史版本与完整改动见 README.md 第 8 节。
---

"""


def main():
    with io.open(MAN, encoding="utf-8") as f:
        old = f.read()
    if "zone_badge" in old:
        print("manifest already updated")
        return 0
    with io.open(MAN, "w", encoding="utf-8", newline="\n") as f:
        f.write(NEW + old)
    print("manifest updated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
