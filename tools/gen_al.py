#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_al.py - 刷新 TD 工程文件里的 Verilog 源码清单

背景：TD 打开 .al 时按相对路径找源码，路径对不上会报
      "GUI-8004 ERROR: Source file is missing!"，并且**把 Source_Files 清空**。
      本脚本以现有 .al 为模板，把 <Verilog>...</Verilog> 段重写成
      rtl/ 下全部可综合 .v（排除仿真模型），其余段（约束、Runs、TOP_MODULE）原样保留。

两个必须遵守的格式细节（都踩过）：
  1) .al 必须是 **CRLF** 换行、UTF-8 无 BOM；
  2) <Project Name> 必须与文件名一致（HDMI1.4b_Transmitter_v1.0），
     否则 TD 报 PRJ-8643 "file name does not match the project name"。

用法：
    python tools/gen_al.py

如果 .al 已经被 TD 清空/写坏，先从 git 恢复模板再跑：
    git checkout -- project/HDMI1.4b_Transmitter_v1.0.al
"""
import os
import re
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
PROJ = os.path.join(ROOT, "project")
RTL = os.path.join(ROOT, "rtl")
AL = os.path.join(PROJ, "HDMI1.4b_Transmitter_v1.0.al")

EXCLUDE = {"afifo_16_256_sim.v"}


def rel(p, base):
    return os.path.relpath(p, base).replace("\\", "/")


def main():
    if not os.path.exists(AL):
        raise SystemExit("missing %s (restore it from git first)" % AL)

    raw = open(AL, "rb").read().decode("utf-8")
    if not re.search(r"<Name>HDMI1\.4b_Transmitter_v1\.0</Name>", raw):
        raise SystemExit("unexpected project name in .al")

    files = []
    for dp, dn, fn in os.walk(RTL):
        for f in fn:
            if f.lower().endswith(".v") and f not in EXCLUDE:
                files.append(os.path.join(dp, f))
    files.sort()

    entries = []
    for i, p in enumerate(files, 1):
        entries.append('            <File Path="%s">\r\n' % rel(p, PROJ))
        entries.append('                <FileInfo>\r\n')
        entries.append('                    <Attr Name="UsedInSyn" Val="true"/>\r\n')
        entries.append('                    <Attr Name="UsedInP&R" Val="true"/>\r\n')
        entries.append('                    <Attr Name="BelongTo" Val="design_1"/>\r\n')
        entries.append('                    <Attr Name="CompileOrder" Val="%d"/>\r\n' % i)
        entries.append('                </FileInfo>\r\n')
        entries.append('            </File>\r\n')
    block = "".join(entries)

    start = raw.index("<Verilog>") + len("<Verilog>")
    body_start = raw.index("\r\n", start) + 2
    end = raw.index("</Verilog>")
    raw = raw[:body_start] + block + raw[end:]

    # 工程目录（Path 属性）
    raw = re.sub(r'Path="[^"]*"', 'Path="%s"' % PROJ.replace("\\", "/"), raw, count=1)

    open(AL, "wb").write(raw.encode("utf-8"))
    print("updated", AL, "->", len(files), "verilog files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
