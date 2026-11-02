# HDMI2 — EG4S20 HDMI 1.4b 四区图片播放器

基于安路 EG4S20BG256 的 HDMI 1.4b 图片/音频播放工程。  
当前版本为阶段最终版：四区图片、目录缩略图、切图幕帘、主菜单/设置、单 WAV 循环播放。

## 功能

- HDMI 1.4b 输出，640×480p60；
- TF 卡 FAT32，根目录图片按文件名分区：
  - `A01.BMP` … `A10.BMP`
  - `B01.BMP` … `B10.BMP`
  - `C01.BMP` … `C10.BMP`
  - `D01.BMP` … `D10.BMP`
- 每区最多 10 张，区内首尾循环；
- 主菜单「目录 / 设置 / 待定」；
- 目录页四行固定 `ZONE A-D`，左上缩略图；
- 图片界面左下 `n/10`，右下 `ZONE A-D`；
- 图片切换右侧幕帘，只作用图片层；
- 单 WAV 背景音乐循环：
  - 根目录只放一个 `MAIN.WAV`；
  - 按文件大小计算循环点；
- 音频开关、音量 25/50/100%、波形、时间、自动轮播；
- 设置面板叠加在主菜单上，不跳图片。

## 定版 bitstream

| 项 | 值 |
|---|---|
| 文件 | `bitstream/HDMI2_HDMI14_Player_final.bit` |
| MD5 | `FF519E68118C05DC0D3535128B9D2E38` |
| SHA-256 | `CB72774A2E85FEDF136E8AC371537A78DB97EBA2064FBE6D4696119AE21940B2` |
| 器件 | EG4S20BG256 |
| 工具 | Anlogic TD 6.2.168116 |
| 资源 | 4179 mslices / 55 BRAM / 21 DSP |
| 时序 | Setup +1073 ps，Hold +7 ps，0 FEPS |

## 仓库结构

```
rtl/                可综合 RTL、IP、字库
constraints/       时序与引脚约束
bitstream/         定版 bit 与 manifest
project/           TD 工程文件参考
tools/             测试图片/字库/FAT 辅助脚本
docs/              交接、使用、代码说明、修改记录
```

## 构建

1. 安装 Anlogic TD 6.2.168116；
2. 新建/打开 `HDMI1.4b_Transmitter_v1.0` 工程，器件选 `EG4S20BG256`；
3. 添加 `rtl/` 下的 HDL 与 IP，顶层 `top_tf_hdmi_audio`；
4. 使用 `constraints/` 下的时序/引脚约束；
5. 综合 → 布局布线 → 生成 bit；
6. 布局 seed 建议 5（本版使用 seed 5）。

> `project/` 内是原工程文件参考，路径按本仓库结构可能需要重新指认。

## 上板

- TF 卡：FAT32，根目录放 `A01..D10` 共 40 张 BMP；
- 音频：根目录只放 `MAIN.WAV`（16-bit PCM，44.1/48 kHz）；
- 烧录 `bitstream/HDMI2_HDMI14_Player_final.bit`；
- HDMI 接显示器，上电。

## 按键

- 主菜单：W/S 选择，Enter 进入；
- 目录：W/S 切区，Enter 进图，Q 返回；
- 图片：A 上一张 / D 下一张；Q 回目录/主菜单；
- 设置：W/S 选行，A/D 调值，Enter 确认/进入编辑，Q 关闭。

## 已知限制

- 根目录 WAV 只识别第一个文件，因此只放 `MAIN.WAV`；
- WAV 循环点按文件大小估算，文件头/碎片会带来轻微误差；
- 图片只扫描根目录第一簇目录项；
- 缩略图为固定 60×45 缓存放大，块状明显；
- 波形保持原参数（128 高 / DECIMATE 24）。

## 文档

- [交接说明](docs/交接说明_HANDOFF.md)
- [使用说明](docs/使用说明_USAGE.md)
- [代码说明](docs/代码说明.md)
- [修改记录](docs/修改记录.txt)
- [设计参考](docs/设计参考例程文档.md)
