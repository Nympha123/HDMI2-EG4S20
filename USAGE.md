# 使用说明与版本状态（USAGE.md）

本仓库 = **HDMI 1.4b 发射器**工程（安路 **EG4S20BG256 / HX4S20** 板，**TD 6.2**）在官方例程基础上
合并"讲次系列"功能后的成果，并额外加入**页面视图（Page View）**。

---

## 1. 当前版本状态

* **读图链**：官方单缓冲风格（顶层 + reader 已恢复到 4-bank 移植之前的状态）。
* **页面视图（本版新增）**：左侧 **480×360** 显示当前图像**原始像素裁切**（源图列 0–479 / 行 60–419，
  **无缩放、无缓存**）；右侧深色文字区 + 固定标题「**图片信息**」；页面视图内**隐藏信息带/滚动字幕**。
* **入口**：**长按 EC11 按钮 ≥0.8 s** 进/出（计数器必须先看到按键松开才计数 ⇒ **不会开机误触发**）。
* **切图**：KEY1 下一张 / KEY2 短按上一张（沿用原例程方式）。
* **其它保持不变**：主菜单、旋钮亮度/对比度、信息带与三句滚动字幕、音频波形、I2S 声音、数码管诊断。
* **板测结论**：切图、页面视图、其它功能**完全正常**；**已知问题**见第 6 节。

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
* **建议**：以官方单缓冲例程为起点重做读图（其 `SD/sd_card_bmp.v` 仅 14.6 KB），
  而不是从"第十四讲完整版"提交出发（后者**已包含多 bank 加载器**）。

---

## 7. 下一步：PCF8563 RTC（真实时间）

**目标**：把界面上的"假时间"（内部计数器）换成 PCF8563 真实时间，格式 `YYYY-MM-DD HH:MM`。

**接线**（成品模块，板载 32.768 kHz 晶振与 4.7 kΩ 上拉）：

| PCF8563 | 接 HX4S20 J2 40 芯 | 备注 |
|---|---|---|
| VDD | J2-29（**3.3 V**） | **严禁 5 V**（上拉会把 5 V 灌进 FPGA 引脚） |
| VSS | J2-12（GND） | 必须共地 |
| SDA | J2-1 → FPGA **P4** | `set_pin_assignment {I2C_SDA} { LOCATION = P4; IOSTANDARD = LVCMOS33; }` |
| SCL | J2-2 → FPGA **N4** | `set_pin_assignment {I2C_SCL} { LOCATION = N4; IOSTANDARD = LVCMOS33; }` |
| INT / CLKOUT | 悬空 | 一期不用 |

**一期只读**：FPGA 只读不写；时间由单片机/PC 配置。
时序：`START → 0xA2 → 0x02 → Repeated-START → 0xA3 → 连读 02H..08H（7 字节）→ NACK → STOP`；
数据为 **BCD**（星期寄存器**不是** BCD）；`02H.bit7 = VL`（1 = 掉电、时间无效）；单次通信 < 1 s。

**已完成**：`i2c_master.v`（位级 I2C 主机、开漏双向、已过门禁语法检查）——
当前**不在工程内**，存于 `_incoming/_work/rtc/`；接入时放回 `hdl_source/` 并加入 `.prj`。
**待做**：`pcf8563_rtc.v`（每秒读 + BCD→二进制 + VL 处理）、`subtitle_overlay.v` 时间源替换
（`vl=1` 显示"时间无效"并回退原计数器）、顶层 `inout I2C_SDA`/`output I2C_SCL` 与 `pin.adc`。

---

## 8. 提交与标签

* 分支 **`merge-yang-ui`**（远程 `main` 不变，可开 PR 合并）
* 标签：`rtc-baseline`（**本说明对应版本**）、`snapshot-2026-10-15`、`pre-baseline-read`、
  `pre-1bankA`、`pre-1bank-rework`、`page-view-crop-ok`
* 历史：46 次提交；根提交 = 远程 `main` 尖端（**直系历史，无需 force push**）

---

## 9. 注意事项

1. **勿改** `hdmi_1_4b_transmitter_core_wrapper.enc.v`、`sdr_*.enc.v` 等**加密 IP**；
2. 引脚约束**统一写在** `constraints_source/pin.adc`（**不要**写进 Verilog）；
3. **勿动** `SD/sd_card_bmp.v` 里的 **SD 分频常量 `CLK_FREQ_HZ`（100 MHz）** 与数码管扫描链；
4. 删除文件走回收站（`tools/recycle.ps1`）；
5. **一步一提交**，并在 `README_CURRENT.md` 记录板测结论。
