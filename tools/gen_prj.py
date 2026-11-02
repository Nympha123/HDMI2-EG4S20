#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_prj.py - 为命令行流程重建 Runs/{syn_1,phy_1}/HDMI1.4b_Transmitter_v1.0.prj

TD 的 GUI 每次运行会用 .al 重新生成 .prj；纯命令行流程不会。
新增/删除源文件后（例如加了 rtl/menu_icon_rom.v），必须先刷新 .prj，
否则综合会报 HDL-8007 "xxx is a black box"。

用法： python tools/gen_prj.py
"""
import os
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
PROJ = os.path.join(ROOT, "project")
RTL = os.path.join(ROOT, "rtl")
RUNS = os.path.join(PROJ, "HDMI1.4b_Transmitter_v1.0_Runs")

EXCLUDE = {"afifo_16_256_sim.v"}


def rel(p, base):
    return os.path.relpath(p, base).replace("\\", "/")


def build(files):
    P = []
    P.append('<?xml version="1.0" encoding="UTF-8"?>')
    P.append('<Project Version="3" Minor="2">')
    P.append('    <Project_Created_Time></Project_Created_Time>')
    P.append('    <TD_Version>6.2.168116</TD_Version>')
    P.append('    <Name>HDMI1.4b_Transmitter_v1.0</Name>')
    P.append('    <HardWare>')
    P.append('        <Family>EG4</Family>')
    P.append('        <Device>EG4S20BG256</Device>')
    P.append('        <Speed></Speed>')
    P.append('    </HardWare>')
    P.append('    <Source_Files>')
    P.append('        <Verilog>')
    for i, p in enumerate(files, 1):
        P.append('            <File Path="../../../rtl/%s">' % rel(p, RTL))
        P.append('                <FileInfo>')
        P.append('                    <Attr Name="UsedInSyn" Val="true"/>')
        P.append('                    <Attr Name="UsedInP&R" Val="true"/>')
        P.append('                    <Attr Name="BelongTo" Val="design_1"/>')
        P.append('                    <Attr Name="CompileOrder" Val="%d"/>' % i)
        P.append('                </FileInfo>')
        P.append('            </File>')
    P.append('        </Verilog>')
    P.append('        <IP_FILE>')
    P.append('        </IP_FILE>')
    P.append('    </Source_Files>')
    P.append('    <FileSets>')
    P.append('        <FileSet Name="design_1" Type="DesignFiles">')
    P.append('        </FileSet>')
    P.append('        <FileSet Name="constraint_1" Type="ConstrainFiles">')
    P.append('        </FileSet>')
    P.append('    </FileSets>')
    P.append('    <TOP_MODULE>')
    P.append('        <LABEL>top</LABEL>')
    P.append('        <MODULE>top</MODULE>')
    P.append('        <CREATEINDEX>user</CREATEINDEX>')
    P.append('    </TOP_MODULE>')
    P.append('    <Property>')
    P.append('    </Property>')
    P.append('    <Device_Settings>')
    P.append('    </Device_Settings>')
    P.append('    <Configurations>')
    P.append('    </Configurations>')
    P.append('</Project>')
    return "\n".join(P) + "\n"


def main():
    files = []
    for dp, dn, fn in os.walk(RTL):
        for f in fn:
            if f.lower().endswith(".v") and f not in EXCLUDE:
                files.append(os.path.join(dp, f))
    files.sort()
    txt = build(files)
    for run in ("syn_1", "phy_1"):
        d = os.path.join(RUNS, run)
        if not os.path.isdir(d):
            continue
        with open(os.path.join(d, "HDMI1.4b_Transmitter_v1.0.prj"), "wb") as fh:
            fh.write(txt.encode("utf-8"))
        print("updated", os.path.join(d, "HDMI1.4b_Transmitter_v1.0.prj"))
    print("files:", len(files))
    return 0


if __name__ == "__main__":
    sys.exit(main())
