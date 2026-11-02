# 使用说明与版本状态（USAGE.md）

本仓库 = **HDMI 1.4b 发射器**工程（安路 **EG4S20BG256 / HX4S20** 板，**TD 6.2**）在官方例程基础上
合并"讲次系列"功能后的成果，并加入音频、内部双时钟校正、紧凑目录等增强。

---

## 1. 当前版本状态

* **读图链**：**4-bank**（loader `BANK0..BANK3`、reader/player 4 bank）；官方例程本身是双缓冲，不是 1-bank。
* **页面视图**：已从当前显示链移除（2026-10-20）；1:1 裁切方案归档在 [`doc/页面视图方案归档_20261020.md`](doc/页面视图方案归档_20261020.md)，`page_view.v` 源文件保留但不再例化。
* **时间**：内部 `time_clock` + `info_bands` 双时钟校正，**不接外部 RTC**；`rtc_sda/rtc_scl` 端口和引脚约束已删除。
* **音频**：WAV/BGM 2 音调 + 音量 25/50/100% + Enter 音频开关；WAV/波形/轮播互相独立。
* **轮播**：5/10/15 秒三档 + 独立开关；2 秒档已移除。
* **亮度/对比度**：已回退到削减前（编码器 0..16，共 17 档；面板名义 0..31、实际有效 0..16；0 允许；进度条仍是旧的半幅映射）。
* **切图**：KEY1 下一张 / KEY2 短按上一张；图片界面 **A 上一张 / D 下一张**（菜单/设置/目录打开时 A/D 仍只调值）。
* **分区表**：scanner 内部 512×64 BRAM 表，匹配 `A01..A10` 等；当前只读表的前 4 项，`zone_sel` 固定 A 区；目录选栏 / 5～10 张预取尚未接入。
* **已知且保留**：手动切图时短暂“沙沙声”来自图像装载与音频共享 SD/SDRAM/FIFO 的短暂抢占，不是故障；用户确认保留。
* **当前 bit**：`phy_1/HDMI1.4b_Transmitter_v1.0.bit`，MD5 **`7EBF8AE467A46A6C461A7D7386D64472`**；9045 LUT / 7161 reg / 4727 mslices / 99 pads / 49 BRAM，Setup `+119 ps`、Hold `+26 ps`。
* **板测**：双时钟版 `6E8D814A…` 已确认面板/图片界面同步；RTC 清理只删除未使用端口/引脚，需做一次快速复测。

---

## 2. 仓库组成

| 路径 | 内容 |
|---|---|
| `src/user_source/hdl_source/` | 全部 Verilog（顶层 `top_tf_hdmi_audio.v`、`page_view.v`、`subtitle_overlay.v`、`main_menu.v`、`rotary_brightness.v`、`font_rom.v` 等） |
| `src/user_source/hdl_source/SD/` | TF 卡读图链（`sd_card_bmp.v`、`fat32_*`、`frame_fifo_*`、`sd_card_*`、`seg_decoder.v`、`seg_scan.v` 等） |
| `src/user_source/hdl_source/{IP,include,hdmi1.4b_transmitter_core}/` | 官方 IP 与 HDMI 核，**加密文件请勿修改** |
| `src/user_source/constraints_source/` | **`timing.sdc`（时序）** 与 **`pin.adc`（引脚）** |
| `src/td_project/HDMI1.4b_Transmitter_v1.0.al` | **TD 工程文件（从这里打开）** |
| `src/td_project/..._Runs/{syn_1,phy_1}/` | 综合 / 布局布线运行目录，`phy_1/` 内含可直接下载的 **`.bit`** |
| `src/td_project/al_ip/` | IP 与 `FONT_ROM.mif`（**本工程字库已改为纯 RTL，不再使用 TD 的 FONT_ROM IP**） |
| `docs/`、`tools/` | 过程文档与辅助脚本（字库生成 `make_font_rom.py`、回收站删除 `recycle.ps1`） |
| `README_CURRENT.md` | 开发日志：每次改动 + 板测结论 + 已知问题过程 |

---

## 3. 下载后如何构建

1. 用 **TD 6.2** 打开 `src/td_project/HDMI1.4b_Transmitter_v1.0.al`；
2. 确认 `al_ip/` 下的 IP 齐全（`PLL.v`、`PLL_HDMI_AUDIO.v`、`AUDIO_SAMPLE_ROM.v` 等）；
   若缺失，按 `al_ip/*.ipc` 在 TD 中重新生成（参见官方例程里的 `_IP核需在TD中生成.txt`）；
3. 依次运行两个流程：
   ```bat
   cd src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\syn_1
   D:\App\TD\bin\td_commands_prompt.exe HDMI1.4b_Transmitter_v1.0.tcl     :: 综合
   cd ..\phy_1
   D:\App\TD\bin\td_commands_prompt.exe HDMI1.4b_Transmitter_v1.0.tcl     :: 布局布线
   ```
   产物：`phy_1/HDMI1.4b_Transmitter_v1.0.bit`（仓库内已附一份）。
4. **注意**：综合需要读到 `font_rom.hex`；若相对路径不同，请把
   `src/user_source/hdl_source/font_rom.hex` **复制到** `syn_1/` 与 `phy_1/`。

**参考数据（用于确认构建的是同一版本）**

| 项 | 数值 |
|---|---|
| 综合 | **7042 registers / 8419 LUT** |
| 时序 | **Setup +207 ps**、Hold +25 ps、TNS 0、失败端点 0 |
| 资源 | 32 BRAMs |

---

## 4. 下载与验证

1. 下载 `phy_1/HDMI1.4b_Transmitter_v1.0.bit`（JTAG 到 SRAM **断电即丢**；长期使用请写 Flash）；
2. 数码管：加载成功那位显示 **`F`**（`0` = 失败）；⚠️ 数码管与双色 LED **IO 复用** ⇒ **SW6 拨到数码管档位**；
3. TF 卡按原例程放置图片（`PIC1.BMP`..）与音频（`WAV`），命名/格式与官方例程一致。

---

## 5. 已验证 bit 归档（`src/td_project/..._Runs/` 之外的 `_bits_good/`，共 20 个）

| 名称 | 说明 |
|---|---|
| `G_17730B9F_L14_word.bit` | **最稳**：第十四讲完整版（菜单、旋钮亮度、对比度、底栏指示、三句字幕） |
| `G_88712E97_L13_pageview_crop.bit` | 页面视图裁切版（320×240），用户确认正常 |
| `P_DCCA3BC8_*` / `6F07FDC1` | 页面视图 480×360（当前行为基线） |
| 其余 | 各讲次里程碑（菜单、字幕、旋钮、对比度第二维、底栏指示…） |

**回退**：把任一 bit 复制为 `phy_1/HDMI1.4b_Transmitter_v1.0.bit` 重新下载即可。

---

## 6. 已知问题：后台图像 bank 的噪点（未解决）

* **现象**：多图常驻时，**未显示的那些图**随时间缓慢出现噪点；当前显示的图**始终干净**；**重读卡可清除**。
* **已确认**：首次出现于 **4-bank 结构移植**时；只有闲置图退化 ⇒ 与"SDRAM 行是否被反复激活"强相关；
  自动刷新看起来**未覆盖**闲置行。
* **已尝试无效**：只改 `preload_sel`（未真正改变加载路径）；整体回退 `SD/` 到早期提交
  （门禁结果与上一版**逐位相同** ⇒ 该回退未改变被综合的设计）。
* **建议**：当前源码和本 bit 是 **4-bank**（`BANK0..BANK3`、player 4 bank）；官方例程是 **双缓冲**，不是 1-bank。以后重做读图时保留 4-bank 或按官方双缓冲验证，不要再按“单缓冲”描述。

---

## 7. 时间：内部双时钟校正（不接外部 RTC）

- 时间源是 [`time_clock.v`](src/user_source/hdl_source/time_clock.v)：25 MHz 计数、BCD 输出，设置面板可装载校正；
- 图片界面 [`info_bands`](src/user_source/hdl_source/subtitle_overlay.v:264) 在 `tc_load` 时装入同一组 BCD，并清零自己的 1 秒分频；两屏从同一时刻重新计数；
- 面板和图片界面的时间都由内部计数器产生，**不再预留/使用 PCF8563、I2C 引脚**；
- `rtc_sda/rtc_scl` 已从顶层端口和 [`pin.adc`](src/user_source/constraints_source/pin.adc) 删除；
- `i2c_master.v` 只留在 `_incoming/_work/rtc/` 归档，**不在工程内**，不参与综合/布线；
- 当前上板片：`phy_1` MD5 **`7EBF8AE467A46A6C461A7D7386D64472`**（展区表 + 前 4 项读表预装，4727 mslices / 99 pads / 49 BRAM，Setup `+119 ps`、Hold `+26 ps`）。

---

## 8. 提交与标签

* 分支 **`merge-yang-ui`**（远程 `main` 不变，可开 PR 合并）
* 标签：`snapshot-2026-10-15`、`pre-baseline-read`、`pre-1bankA`、`pre-1bank-rework`、`page-view-crop-ok`
  （`rtc-baseline` 是历史标签，已不使用）
* 历史：46 次提交；根提交 = 远程 `main` 尖端（**直系历史，无需 force push**）

---

## 9. 注意事项

1. **勿改** `hdmi_1_4b_transmitter_core_wrapper.enc.v`、`sdr_*.enc.v` 等**加密 IP**；
2. 引脚约束**统一写在** `constraints_source/pin.adc`（**不要**写进 Verilog）；
3. **勿动** `SD/sd_card_bmp.v` 里的 **SD 分频常量 `CLK_FREQ_HZ`（100 MHz）** 与数码管扫描链；
4. 删除文件走回收站（`tools/recycle.ps1`）；
5. **一步一提交**，并在 `README_CURRENT.md` 记录板测结论。

## 轮播周期档位（2026-10-20 定案）

- 板上设置面板的「轮播」只有 **三档：5 秒 / 10 秒 / 15 秒**，另有「关」；**2 秒档已移除**。
- 实际周期仍约为标称值的 2 倍（5/10/15 → 约 10/20/30 秒）：`sd_card_clk` 是 50 MHz，而常量按 100 MHz 写；这是用户已接受的行为，暂不改。
- 相关代码：`panel_values.v`（`autoper` 0..2）、`top_tf_hdmi_audio.v`（`auto_period` 500M/1G/1.5G）、`settings_panel.v`（显示 `关 / 5秒 / 10秒 / 15秒`）。

## 两屏时钟同步（已完成，2026-10-20）

- 面板 `time_clock` 与图片界面 `info_bands` 共用同一组 BCD：Enter 退出「时间」编辑时产生 `tc_load`，两边同时装载并清零各自的 1 秒分频；
- `info_bands` 的 `time_str` 仍由本地计数器生成，只增加了 `load_d` 使能，**没有在像素路径上引入 64 位外部 mux**；
- 同时修好了原来永远不成立的 `tc_load` 写回条件，并让 Q 关闭面板时取消编辑；
- 板测：面板校时后图片界面同步跳变，随后两边同步走时；
- 最终 bit：`7EBF8AE4…`（9045 LUT / 7161 reg / **4727 mslices** / 99 pads / 49 BRAM，Setup `+119 ps`、Hold `+26 ps`）；展区表 + 前 4 项读表预装已包含，亮度/对比度保持削减前行为。

## 待办：目录页（受器件资源限制，必须复用现有逻辑）

**已验证的事实**（2026-10-19）：
- 板载 EG4S20 的 **mslice 上限 4900**；当前设计约 **9064 LUT**，实测**只剩 +0…+30 LUT** 的余量。
- 独立模块 `directory_screen.v`（已写好、保留在工程但不例化）会让 mslice 升到 **4994** ⇒ `PHY-9009` 溢出，**两次实测都失败**（除法器版 4984、比较链版 4994）。
- 已顺手省下的：`main_menu` 的 `hint_char` 恒为空格（−89 LUT，提交 `8540a96`）；`page_view.v`（旧缩略图页）已从显示链移除。

**可行路线**：**扩展 `main_menu.v`**，加 `dir_mode` 输入，为 1 时把绘制换成目录页版式
（左外框 + 上图片框 + 下文字框 / 右列表 8 行，每行 1 px 描边 + 行首圆点 / 滚动条），
**复用同一个 ROM 取模与合成管线**，预计只增 +40…60 LUT。

**版式数据**（`index.html`）：
- 背景 `#EEF5FC`；面板底 `#FFFFFF`；描边 `#BFE0F5`；图片框 `#EAF4FD`；选中行底 `#BCDEFB`（描边用该条目强调色，2 px）
- 左外框 `x 4..290, y 4..454`；上图片框 `x 14..280, y 14..192`；下文字框 `x 10..280, y 202..444`
- 右列表面板 `x 294..636, y 4..454`；行 `x 300..622`，`y0 = 10 + 54*r`，`y1 = y0 + 49`，共 8 行
- 行首圆点 `x = 316`，半径 5，用该行自己的强调色；滚动条 `x 626..630`
- 每行文字：`nameX = 332`，16 px 字模；行高 54 正好放一个 16 px 字模

**层级返回**：主界面 →(Enter 目录)→ 目录页 →(Enter)→ 图像界面 →(Q)→ 目录页 →(Q)→ 主界面；主界面按 Q 无动作。
用 `dir_active` / `dir_entered` 两个状态位实现（键盘域），并同步到视频域绘制。

**当前可用片**：`P_25CEA2D9_L17_tlock.bit`
