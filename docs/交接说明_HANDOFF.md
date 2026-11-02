# HDMI2 / EG4S20 项目交接说明（2026-10-19）

> 给接手的新会话：**先读这一页**，再动手。源码和 TD 工具结果按对应 run 记录；板上行为只在明确标注板测的条目中视为已验证。最新目录页候选已生成 bitstream，尚未上板。

## 1. 项目与环境

| 项 | 值 |
|---|---|
| 工程根 | `C:\Users\30685\Desktop\HDMI2` |
| 工程文件 | `src\td_project\HDMI1.4b_Transmitter_v1.0.al` |
| 综合/布线目录 | `src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\{syn_1,phy_1}` |
| TD 命令行 | `D:\App\TD\bin\td_commands_prompt.exe`（在 run 目录里执行 `HDMI1.4b_Transmitter_v1.0.tcl`） |
| Git 仓库 | `C:\Users\30685\Desktop\HDMI-7`（远程 `git@github.com:Nympha123/HDMI2-EG4S20.git`；不在 HDMI2 子目录内） |
| 器件 | Anlogic EG4S20BG256（HX4S20 板） |
| 参考网页 | `D:\Project\Deepseek\web_test\handover\`（`index.html` 是唯一权威，`README.md` 有设计说明） |

## 2. 铁律（违反过，都出过事故）

1. **每次改动都要过门禁**：新建 `_verify_syn` 目录，拷入 `settings.cfg` / `.tcl` / `.prj` / `font_rom.hex`，跑综合，
   过滤 `HDL-8007|PRJ-8|black box|ERROR:`（排除 `fs_error`）。门禁数字与上一版对比，**变化必须能解释**。
2. **必须完整跑 syn + phy**。删中间文件后只跑 P&R 会得到 `PHY-8023` / `RUN-8102`。
3. **时序必须为正**才能交付：`Setup WNS ≥ 0` 且 `Hold WNS ≥ 0`、`NUM_FEPS = 0`。
4. **资源必须检查**：`PHY-9009 ERROR: Design's mslice number = N, exceeds the limit 4900` 是**器件装不下**；
   最新分页目录候选综合为 **9119 LUT / 7321 reg**，P&R 为 **4780 mslices / 4900**，余 120 mslices。
5. 每步一个变量、一次提交；出问题一律 `git checkout` 回退，不要在坏树上继续叠改动。
6. `pin.adc` **不能有 `//` 注释、不能有 BOM**；Verilog 里不写引脚约束。
7. 不改 `参考文件\` 与用户文件；不动 `sd_card_bmp.v` 的 `CLK_FREQ_HZ`。
8. PowerShell 命令里**不要出现中文**（编码会坏），中文只通过写文件工具写。

## 3. 当前状态（源码已改、综合与 P&R 验证通过；当前改动未生成 bitstream）

| 项 | 值 |
|---|---|
| 已有 bit 文件 | 最新候选 `_bits_pending\HDMI2_directory_lba_pipeline_20261019.bit`（MD5 `D22935F455848B2964E6275F6F3A7935`，SHA-256 `7A4BFED1294C61CF9AEF3E5838FE9FE656242EB31AF227D15EAD226BEF04030D`），由下方通过时序门禁的独立 P&R 数据库生成；尚未上板。旧文件 `_bits_pending\P_25CEA2D9_L17_tlock.bit` 仍未证明对应当前源码 |
| HDMI2 工作区源码综合结果 | 最新候选 **7321 reg / 9119 LUT**；`gate.qor` Setup `+507 ps`、Hold `+421 ps`，`flow.status` Setup `+520 ps`、Hold `+421 ps`，均为 0 个违规端点；综合阶段报告口径有差异，最终以 P&R 为准 |
| HDMI2 工作区源码 P&R 结果 | 最新候选 **4780 mslices**（上限 4900，余 120）；Setup WNS `+390 ps`、Hold WNS `+25 ps`、TNS `0`、`NUM_FEPS=0`。原先 Setup `+800 ps` 裕量目标未达到 |
| 最新代码改动 | 保留轮播 15 秒第 4 档和网页设置面板档位；目录页已接回主菜单，采用复用 ROM 的三行分页列表；WAV 起始 LBA 转换增加一级寄存器以切断失败路径。已完成独立综合、完整 P&R 和 BitGen；bitstream 尚未上板 |
| Git 状态 | HDMI2 工作区不是 Git 仓库；源码仓库为 `C:\Users\30685\Desktop\HDMI-7`。本次目录页与 LBA 时序修改及验证留在 HDMI2 工作区，未提交、未同步到 HDMI-7；3 份未跟踪课程文档不触碰 |

### 2026-10-19 GUI 生成 bitstream 时的 black-box 错误

- 用户截图对应 GUI 的 `syn_1` 在 `2026-10-19 17:47:34` 失败。日志 `src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\syn_1\run.logw` 报 17 个 `HDL-8007` black-box 错误和相应 `HDL-7144` unknown-module 警告，包括 `fat32_find_file`、`settings_panel`、`time_clock`、`page_view`、`main_menu` 等；这是综合未加载 RTL 源文件，不是 BitWriter、板卡或时序错误。
- 根因已定位：GUI 项目 `HDMI1.4b_Transmitter_v1.0.al` 的 Verilog 清单只有 47 项；通过面板版综合/P&R 的 `_verify_syn_webpanel` 清单有 75 项，缺少 28 个源文件。用户源码都存在，旧 `.al` / `syn_1` 项目清单没有登记它们。
- 已在 HDMI2 的 `.al` 中补入这 28 项，路径和 CompileOrder（56..83）与已通过验证的 75 项清单逐项一致；旧文件备份在 `src\td_project\_incoming_backup\HDMI1.4b_Transmitter_v1.0.al.before_source_manifest_fix_20261019`。已确认 75 项都指向存在的 RTL 文件。
- 这份 `.al` 修复尚需 GUI 重新载入才能更新内存中的工程和 `syn_1` 生成清单。重新打开 `HDMI1.4b_Transmitter_v1.0.al` 后再运行综合、P&R 和 BitWriter；以新 `syn_1` 日志中没有 `HDL-8007` / `HDL-7144` 为准。此前 `_verify_syn_webpanel` / `_verify_phy_webpanel` 已用同一份 75 项源清单通过；本轮未生成 bitstream，也未上板。

### 历史阶段记录：独立 time_clock 计数器候选（不是当前源码）

以下数据对应较早的 `time_clock` 独立候选快照，仅用于追溯，不代表本交接顶部列出的当前面板源码；当前版本以紧随其后的“设置面板与网页档位对齐验证记录”为准。

- 最新独立综合目录：`src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\_verify_syn_timeclock`。
- 最新独立 P&R 目录：`src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\_verify_phy_timeclock`；从该综合数据库完整执行 placement、route 和 route-stage `fix_hold`，`end_step=opt_route`，没有生成 bitstream。
- 综合门禁过滤 `HDL-8007|PRJ-8|black box|ERROR:` 未命中。相比原 `_verify_syn` 基线（7265 reg / 9064 LUT、Setup `+907 ps`、Hold `+421 ps`），新结果增加 1 reg、11 LUT，综合 Setup 少 403 ps。
- 综合工具的报告口径有阶段差异：同一 `_verify_syn_timeclock` 中，`flow.status` / `*_gate.timing` 给出 Setup `+504 ps`，而 `gate.qor` 的 QoR 汇总行是 `+94 ps`；基线对应为 `+907 ps` 与 `+43 ps`。两者均为综合阶段报告，最终交付判断以对应 P&R 的 `route_flow.status` / `route.qor` 为准。
- 对应当前源码 P&R 最终报告为 Setup `+608 ps`、Hold `+23 ps`、`NUM_FEPS=0`，mslice 4782；原当前源码基线 `_verify_phy` 为 Setup `+2 ps`、Hold `+34 ps`、mslice 4783。此处记录的是两次实际 flow 的结果，不把布局布线差异单独归因于计数器逻辑；当前结果通过交付门槛，但 Hold 裕量仍薄，Setup 也未达到原先 `+800 ps` 目标。
- 较早的 FIFO 单项候选记录：删除 `media_frame_reader.v` 正常写分支的外层 `!fifo_full` 后，旧版 `_verify_phy_fifo` 为 Setup `+488 ps`、Hold `+25 ps`、mslice 4792。当时因与该旧快照基线比较而回滚到 `b3374fb`；这项旧对比不能替代当前集成面板源码的完整重验结论。
- `_verify_syn` 与 `_verify_phy` 是改动前当前源基线；旧 `syn_1` / `phy_1` 含有 `u_directory_screen`，与当前顶层源不一致，不可拿来归因。
- 当前可用 bit 的 MD5 仍是交接前记录值；它没有被证明对应本次 `time_clock` 源码。新源码尚无 bitstream，也没有本轮上板验证。

### 2026-10-19 设置面板与网页档位对齐验证记录

- 权威网页 `D:\Project\Deepseek\web_test\handover\index.html` 定义波形默认开启 25%，Enter 独立切换波形开关，A/D 在开启时调整 25/50/100%；自动轮播默认关闭，Enter 切换开关，A/D 在开启时调整 2/5/10/15 秒。15 秒第 4 档按用户决定保留。
- `promax_audio_waveform.v` 的 25% 分支为 `(0xD8 + 3*C) >> 2`，50% 为 `(0xD8 + C) >> 1`，100% 为 `0xD8`；与网页混色公式逐项一致。修复了 100% 分支原先透传背景色的问题。
- 独立综合目录：`src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\_verify_syn_webpanel`；综合 7281 reg / 9014 LUT，`flow.status` Setup `+786 ps`、Hold `+421 ps`、TNS `0`、`NUM_FEPS=0`。同一阶段 `gate.qor` 报 Setup `+234 ps`，保留该工具的阶段报告差异记录。
- 独立 P&R 目录：`src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\_verify_phy_webpanel`；从上述综合数据库完整执行 placement、route 和 route-stage `fix_hold`，`end_step=opt_route`。最终 Setup `+567 ps`、Hold `+25 ps`、TNS `0`、`NUM_FEPS=0`；最终资源 4739 mslices / 4718 lslices。Setup 未达到 `+800 ps` 目标，但时序无正负 slack 违规；资源低于 4900 mslices 上限。
- `HDL-8007|PRJ-8|black box|ERROR:` 门禁过滤无命中（排除 `fs_error`）。仍有 timing.sdc 中 4 个旧信号名无法匹配的告警，以及工具提示 1 个 clock net 使用 local routing；本轮未修改约束或时钟结构。
- 本轮没有生成 bitstream，也没有上板；旧 bitstream 不得视为对应本轮源码。
- 本轮按用户决定先完成源码与工具验证，面板上板操作留待后续。

#### FIFO 写使能选择的版本说明

- 本轮最终 `media_frame_reader.v` 的正常 FIFO 写使能不再在模块外重复判断 `!fifo_full`；`afifo_32_16_256.v` 内部仍以 `wr_en_s = !full_flag & we` 拒绝 FIFO 满时写入，满保护没有删除。
- 这项选择依据是**当前整合面板源码**的完整构建：无外层判断版本综合为 7281 reg / 9014 LUT，并完成 P&R（Setup `+567 ps`、Hold `+25 ps`、0 违例、4739 mslices）。
- 集成期间另测过保留外层 `!fifo_full` 的版本：综合为 7281 reg / 9023 LUT；默认布局下 hold 修复在 HDMI 加密核局部网线上报 `PHY-8023`，随后 `RUN-8102`，没有生成 `route_flow.status`；seed 1 布局的 Setup 为 `−586 ps`。因此当前源码选用无外层重复判断、保留 FIFO 内部满保护的组合。早期独立 `_verify_phy_fifo` 结果属于不同源码快照，不应与本轮最终结果混为一谈。

### 2026-10-19 A1 底栏亮度数值条验证记录

- 工作区和仓库镜像均已从 `subtitle_overlay.v` 删除亮度/对比度文字生成、`LUM_*` 位置参数和底栏对应 ROM 选字分支；底部进度条、n/N 数字组、展区名和两拍 ROM 对齐管线保留。
- 修改前备份：`_incoming\_work\subtitle_overlay_a1_before.v`；修改前 SHA-256 `7D1F81C2DB8D7B10E1C50F6F8459726D9B3EDBF3ABB65D3AF1B169D5481B1777`；修改后 SHA-256 `9FD099EE6DCFE5E05EA3DC8971B88B3A60F2EE23BDED8AF61682EDEAE64564E3`。
- 独立综合目录：`src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\_verify_syn_a1`；7266 reg / 9075 LUT，Setup `+504 ps`、Hold `+421 ps`、TNS `0`、`NUM_FEPS=0`；`HDL-8007|PRJ-8|black box|ERROR:` 过滤无命中（排除 `fs_error`）。
- 独立 P&R 目录：`src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\_verify_phy_a1`；完整 placement、route 和 route-stage `fix_hold` 已完成，最终 Setup `+357 ps`、Hold `+20 ps`、TNS `0`、`NUM_FEPS=0`，资源日志最终为 4788 mslices；未生成 bitstream。
- A1 没有带来可测 LUT 下降：综合仍为 9075 LUT。该结果只说明资源节省预估未被本轮工具实测，不影响网页要求对应的功能删除。

### 已确认可用的既有功能（历史版本曾上板验证）

> 以下是旧板测版本的记录；本轮新档位已通过综合和 P&R，尚未上板验证。

- **键盘**：4×4 矩阵键盘，行 `kp_row[0..3]`=D14/G12/H13/J14，列 `kp_col[0..3]`=G11/F13/H14/J13；
  按键实测编号 W=0 A=1 D=2 S=3 Enter=4 Q=8；脉冲展宽 **80 ms**（必过 20 ms 消抖）、边沿触发；板载按键已全部断开
- **主界面**：三项「目录/设置/三号待定」、8 字标题「智能展品讲解单元」、网页灰渐变 `246→232` + 环/圆盘/三点、
  **420 ms tint 交叉渐变**（旧色→新色，不回灰；底色 TINT_ALPHA≈1/4、装饰 DECOR_TINT=1/2）、**无底栏**、**Q 无动作**
- **设置面板**：网页几何（面板 80..560/78..412、行 128..328@40、标签 x=122、条 260..520 h20、开关 14×14、白色选中框 x106..536 y−12..+32 2px）；
  面板**在亮度模块之前**（所以面板自身随亮度变）；面板背景 = 打开时的界面；选中框随 W/S；Q 松开边沿关闭；Enter 从「设置」进入
- **面板参数**：亮度/对比度已回退到削减前（编码器 0..16，共 17 档；面板名义 0..31、有效 0..16；0 允许）；音量 **25/50/100% 三档 + Enter 音频开关**；轮播 **5/10/15 秒三档 + 开关**（2 秒档已移除）；
  **时间校时**（`time_clock.v` 软件时钟 1 Hz；Enter 进/出、A/D 选字段、W/S 改 BCD；字段金黄 + 2 px 小框；校时中大选中框锁定不动）
- **图片界面**：网页浅色主题（栏底 `#DCEBF7`、字幕带 `#CFE3F4`、强调 `#3F9ED8`、文字 `#25445C`、槽 `#B2D3EA`）+ 栏分隔线 `#9CCBE8`
- **字库**：1024 槽（14 位地址 / 10 位槽号 / 16384 字）；渲染器与作者工具逐字节一致（simsun，行倒序存储）

## 4. 已知未完成 / 有坑

| 项 | 状态 |
|---|---|
| **两屏时钟同步** | **已完成（2026-10-20）**：`time_clock` + `info_bands` 由同一 `tc_load` 装载 BCD，并同时清零 1 秒分频；板测通过。当前可用片 `7EBF8AE4…`：**4727 mslices / 99 pads / 49 BRAM**，Setup `+119 ps`、Hold `+26 ps`。 |
| **目录页** | 独立模块 `directory_screen.v` 已写好（比较链版），但例化后 **mslice 4994 > 4900** 溢出，**不可行**。必须**扩展 `main_menu`** 复用其 ROM 管线。 |
| **底栏数值条** | A1 已完成：`subtitle_overlay.v` 已删除「亮度 nn/16」及其对应 ROM 选字逻辑；综合与 P&R 门禁通过，未生成 bitstream。 |
| **滚动字幕底栏 / 信息栏收起** | 未做。 |
| **气泡** | 未做（网页默认是漂移气泡，板子目前是静态环/盘/点）。 |
| **RTC** | **不接外部 RTC**：时间只用内部 `time_clock` + `info_bands` 双时钟校正；`rtc_sda/scl` 顶层端口和 `pin.adc` 约束已删除；`i2c_master.v` 仅归档在 `_incoming/_work/rtc/`，不在工程内。 |
| **自动轮播** | 5/10/15 秒三档 + 独立开关；2 秒档已移除；完整综合/P&R 通过，板测通过。 |

## 5. 下一步建议顺序

1. 当前双时钟版 Setup `+727 ps`、Hold `+29 ps`，无时序违规；下一步如果继续加目录/预取逻辑，先从小改动开始并逐次核对 Setup。
2. **目录页**：扩展 `main_menu`，加 `dir_mode` 分支画版式（数据见下），**每步核对 LUT 增量 ≤ +30**。
3. 滚动字幕 → 信息栏收起 → 气泡；每项仍需独立综合和完整 P&R。

## 6. 目录页版式数据（`index.html`，权威）

- 背景 `#EEF5FC`；面板底 `#FFFFFF`；描边 `#BFE0F5`；图片框底 `#EAF4FD`；选中行底 `#BCDEFB`（描边=该条目强调色，2 px）
- 左外框 `x 4..290, y 4..454`；上图片框 `x 14..280, y 14..192`；下文字框 `x 10..280, y 202..444`
- 右列表面板 `x 294..636, y 4..454`；行 `x 300..622`，`y0 = 10 + 54*r`，`y1 = y0 + 49`，共 **8 行**
- 行首圆点 `x = 316`、半径 5、用该行自己的强调色；滚动条 `x 626..630`
- 行文字 `nameX = 332`（16 px 字模）；底栏 `y = 458`
- 层级：主界面 →(Enter 目录)→ 目录页 →(Enter)→ 图像 →(Q)→ 目录页 →(Q)→ 主界面；主界面 Q 无动作

## 7. 其他关键经验

- **像素取模必须 2 拍**：`font_rom` 1 拍 + 地址寄存 1 拍；几何信号要与之对齐 2 拍（`main_menu` 是范本）。
- **非 16 对齐的 x 起点会让字形左右两半互换**（`520`、`296` 都踩过）⇒ 用 `pa - x0` 而不是 `px[3:0]`。
- **不要用除法**（`/ 54` 直接综合出巨型除法器，时序崩到 −1888 ps）。
- 面板/亮度链路：`vout_data` →（面板叠加）→ `brightness_contrast_adjust` → `vout_data_br` → 最终 `I_rgb`。
- 8 位加法混合会**溢出回绕**（黑/绿/黄/红色带）⇒ 用 11 位有符号 + 饱和钳位。

## 8. 参考文件位置（网页端权威来源）

| 路径 | 作用 |
|---|---|
| `D:\Project\Deepseek\web_test\handover\index.html` | **唯一权威**：所有版式、颜色、坐标、按键语义都从这里读（约 130 KB 单文件） |
| `D:\Project\Deepseek\web_test\handover\README.md` | 设计说明（信息带配色表、目录页说明、气泡代价分析、标题等，约 55 KB） |
| `D:\Project\Deepseek\web_test\handover\FPGA-PORTING-TODO.md` | 作者写的**移植清单**（§2.x 分条：信息栏收起、设置面板、配色、目录页…） |
| `...\handover\build\font.json` | 字模槽位表（`addedGlyphs` = 字 → 槽号；`slothex` = 全部槽的十六进制） |
| `...\handover\build\font_rom.256.hex` | 512 槽字库（8192 字） |
| `...\handover\build\font_rom.expanded.hex` | 512 槽扩展版（8192 行） |
| `...\handover\build\*.png` | 网页截图（`menu-0-catalog.png`、`settings-panel.png`、`dir-themes.png`、`img-themes.png`、`bars-autohide.png`、`group-steps.png`） |
| `...\handover\tools\add-glyphs.py` | 作者的加字工具（**simsun.ttc** + 多档字号 + `anchor="mm"` + 包围盒居中；本工程的 `_incoming` 版渲染器就是照它复刻并验证过逐字节一致的） |
| `...\handover\tools\emit-font-hex.mjs` | 从 `font.json` 生成 hex |
| `...\handover\tools\check-all.ps1` | 网页自检（14 项） |
| `...\handover\tools\render-*.mjs` | 生成上面那些截图 |
| `C:\Users\30685\Desktop\HDMI2\参考文件\` | 官方例程（如 `第二讲…\第1课_官方例程`），**只读**，不要改 |

**注意**：`D:\Project\Deepseek\web_test\handover\` 在沙箱里**只读**——脚本默认往 `handover\build\` 写会报 `EPERM`，
需要把工具逻辑**复刻到工程内**（`_incoming\_work\render_glyph.py` 就是这么来的，已验证与作者工具逐字节一致）。

**工程内已有的等价物**：
- `src\user_source\hdl_source\font_rom.hex`（1024 槽、16384 字、**行倒序**存储）
- `src\user_source\hdl_source\font_rom.v`（14 位地址、1 拍延迟）
- 渲染器复刻：`_incoming\_work\render_glyph.py`（若已清理，可从 git 历史 `626937f` 找回）

## 2026-10-19 HDMI2 bitstream black-box recurrence and manifest recovery

- The new screenshot title points to the intended project directory, C:\Users\30685\Desktop\HDMI2\src\td_project. The directory is correct, but the active syn_1 run was using a stale 47-file source manifest.
- At 18:30:54, TD regenerated syn_1\HDMI1.4b_Transmitter_v1.0.prj with 47 Verilog entries. Its log repeated the 17 HDL-8007 black-box errors and corresponding HDL-7144 unknown-module warnings. The GUI also rewrote the root .al to 47 entries (SHA-256 0BF7102D746F51CE011353F42FCFA79753F2DDD3A06403F8625D1859811018C2).
- Restored the HDMI2 root .al from the matching 75-entry project copy at C:\Users\30685\Desktop\HDMI-7\src\td_project\HDMI1.4b_Transmitter_v1.0.al; its project Path still points to HDMI2. Before restoration, saved the 47-entry file as src\td_project\_incoming_backup\HDMI1.4b_Transmitter_v1.0.al.before_gui_manifest_restore_20261019.
- Restored .al SHA-256 is 426CF59E0E65B1073470E51B0A625CA55C510D23CA2EFAF169EC43FB1E6FF2AA. It contains 75 Verilog entries, every path exists, and its resolved source list matches _verify_syn_webpanel\HDMI1.4b_Transmitter_v1.0.prj exactly. That verified synthesis reported Setup +786 ps, Hold +421 ps, zero timing endpoints in violation, and no HDL-8007/HDL-7144; the matching P&R verification reported Setup +567 ps, Hold +25 ps, zero violations.
- At 18:48:55, reran the current syn_1 from the restored 75-entry manifest after renaming the stale error log/marker. Its generated .prj has 75 Verilog entries and all 75 source paths resolve.
- This fresh run completed Read Design, Optimize RTL, and Optimize Gate (process exit 0). Its log has no HDL-8007 black-box errors, HDL-7144 unknown-module warnings, or read_design error marker. Gate report: 9014 LUTs, 7298 registers, Setup +786 ps, Hold +421 ps, TNS 0, NUM_FEPS 0. The logw still contains other warnings, including duplicate implicit declarations and invalid false-path constraints; they are separate from the black-box failure.
- This fresh syn_1 run stops after synthesis; it did not run placement/route or BitWriter and did not produce a new bitstream. The separately verified _verify_phy_webpanel result remains Setup +567 ps, Hold +25 ps, zero timing violations.
- If TD still shows the old 17 black-box errors, close the stale GUI project without saving its in-memory state, then use File > Open Project on `src\td_project\HDMI1.4b_Transmitter_v1.0.al` (do not open a `.prj` under Runs\syn_1). Confirm Compile Order contains 75 Verilog files and run Read Design again before proceeding to BitWriter. The screenshot path is the correct HDMI2 project; the remaining likely cause is the GUI's cached 47-entry project state.
- A standalone CLI experiment opened the root .al and analyzed 82 total source items, but the default flow wrapper then failed to find top top (HIER-1013 / HDL-8001). This experiment is not a successful fresh build and is unrelated to the successful syn_1 rerun above.
- On reopening the root .al, TD showed Flow Step Recovery. Accepted recovery; the dialog closed, the project still points to HDMI2, the hierarchy contains top, and the current log tree shows Critical (7) / Warning (55) with no Error or black-box entries.
- The GUI `phy_1` snapshot remains stale (47 Verilog entries, last written at 18:30:54); the GUI `syn_1` source manifest has 75 entries but its database predates the directory/LBA edits. Do not use either old database for this candidate. The independent verify runs below rebuilt the current source and completed BitGen.

## 2026-10-19 Directory page reconnection and WAV LBA timing closure

- `main_menu.v` now uses `dir_mode` to reuse its existing three-row visual/ROM pipeline for a compact, paged list of all eight directory entries. Enter from the main menu opens the directory; W/S cycles through the eight entries; Enter opens an image; Q returns from image to directory and from directory to main menu. This is the resource-limited three-row page, not the web reference's full eight-row layout.
- `top_tf_hdmi_audio.v` synchronizes the directory mode and 3-bit selection into the video domain and blocks the settings-panel shortcut while the directory is open. It also captures `wav_start_lba` once after `wav_find_found` and gates playback with the registered-valid flag, adding one startup cycle while preserving loop restarts.
- The prior P&R failure was the combinational `first_cluster - 2`, multiply by sectors-per-cluster, and add `data_start_lba` path into `wav_stream_player`; it had Setup `-110 ps` and one failing endpoint. With the LBA register, that path is no longer critical.
- Latest independent synthesis run: `src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\_verify_syn_directory_lba_pipeline_20261019`. It used the verified 75-Verilog source manifest; `HDL-8007|HDL-7144|PRJ-8|black box|ERROR:` filtering had no matches. `gate.qor`: 7321 registers, 9119 LUTs, Setup `+507 ps`, Hold `+421 ps`, zero timing violations. `flow.status` reports Setup `+520 ps` with the same Hold and violation counts.
- Preferred complete P&R run: `src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\_verify_phy_directory_lba_pipeline_20261019`, using route-stage `fix_hold`. Final `route_flow.status` / `route.qor`: 4780 mslices, Setup `+390 ps`, Hold `+25 ps`, TNS `0`, `NUM_FEPS=0`. This passes the nonnegative timing and 4900-mslice gates with 120 mslices spare. Setup margin is below the earlier `+800 ps` goal. The remaining worst setup path is `u_media_frame_reader/issued_count_mem_reg[6]` to `burst_issued_mem_reg[5]` on `ext_mem_clk`, with `+390 ps` slack.
- A separate seed-1 P&R run, `_verify_phy_directory_lba_pipeline_s1_20261019`, ended at Setup `+289 ps`, Hold `+20 ps`, and zero FEPS. The default-seed run remains the better measured result; keep it as the preferred candidate.
- BitGen run: `src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\_verify_bitgen_directory_lba_pipeline_20261019`; it imported the passing default-seed `*_pr.db`, exited successfully, and logged `Generate bitstream completely`. The delivered test copy is `_bits_pending\HDMI2_directory_lba_pipeline_20261019.bit` (658724 bytes; MD5 `D22935F455848B2964E6275F6F3A7935`, SHA-256 `7A4BFED1294C61CF9AEF3E5838FE9FE656242EB31AF227D15EAD226BEF04030D`). No board test has been performed. Keep the old `_bits_pending\P_25CEA2D9_L17_tlock.bit` unassociated with this candidate. Source backup before the LBA change: `_incoming\_work\top_tf_hdmi_audio_before_lba_pipeline_20261019.v`.
- 用户确认：本次实际烧录的是 `phy` 目录里的 bitstream。板上观察到：点击“目录”后直接进入图片显示，没有出现目录选择页。此现象已由用户板测确认，归属该 `phy` 目录 bitstream。
- 当前对话没有核实这份 bitstream 的完整路径、文件名和哈希。后续分析前应先对该文件计算 MD5/SHA-256，并与下方分页目录候选核对；不要仅凭它位于 `phy` 目录就认定它由当前分页目录 RTL 构建。
- 交接记录此前注明，GUI 工程的 `phy_1` 可能是旧快照。若用户测试的正是 `src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\phy_1` 中的文件，需先确认其哈希和构建日志，再判断是旧构建还是当前目录页候选。
- 当前分页目录 RTL 位于 `src\user_source\hdl_source\main_menu.v` 和 `top_tf_hdmi_audio.v`：`main_menu` 通过 `dir_mode` 复用字体 ROM/像素流水，8 个条目分三行分页；W/S 切换，Enter 进入所选图片，图片页 Q 返回目录，目录页 Q 返回主菜单。
- 独立分页目录候选已完成综合、完整 placement/route/route-stage `fix_hold` 和 BitGen。综合为 9119 LUT / 7321 reg；P&R 为 4780/4900 mslices，Setup WNS +390 ps、Hold WNS +25 ps、TNS 0、`NUM_FEPS=0`。运行目录：
  - `src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\_verify_syn_directory_lba_pipeline_20261019`
  - `src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\_verify_phy_directory_lba_pipeline_20261019`
- 对应 BitGen 候选副本为 `_bits_pending\HDMI2_directory_lba_pipeline_20261019.bit`，MD5 `D22935F455848B2964E6275F6F3A7935`，SHA-256 `7A4BFED1294C61CF9AEF3E5838FE9FE656242EB31AF227D15EAD226BEF04030D`。在确认哈希前，不要把本次板测结果归到这份候选。
- 新对话优先事项：核对用户烧录文件与上述候选的哈希；若匹配，沿目录入口状态机和顶层选择逻辑排查为何跳过目录页；若不匹配，从当前 HDMI2 RTL 和完整 source manifest 重新生成 BitGen，并用新的文件名、哈希交付板测。
- 原始完整页面 `directory_screen.v` 曾单独接入评估为约 4994 mslices，超过 4900 上限。先确认分页目录候选确实在板上工作，再继续完整页面接入和资源删减分析。
- 本轮未修改 RTL，也未更新工程 source manifest；交接记录此前尚未落盘更新。