# HDMI2 — EG4S20 HDMI 1.4b 博物馆导览播放器

基于安路 **EG4S20BG256**（HX4S20 板）的 HDMI 1.4b 图片/音频播放工程，当前是"博物馆智能展品讲解系统"演示版：
四展区图片 + 目录页（中文展区名 + 展区徽标）+ 主菜单/设置/系统信息 + 滚动讲解字幕 + 分区 WAV 循环。

> 本 README 汇总了 2026-10-24 这一轮（17 次迭代）的全部改动、当前资源占用、构建/烧录流程与踩过的坑，
> 后续维护照着这份文档就能接着做。

---

## 1. 当前状态一览

| 项 | 值 |
|---|---|
| 器件 / 工具 | EG4S20BG256 / Anlogic TD 6.2.168116 |
| 输出 | HDMI 1.4b，640×480p60 |
| **mslices** | **4634 / 4900（94.6%）** |
| **BRAM9K** | **59 / 64（92.2%）** |
| LUT / 寄存器 | 17 150 / 6 320（P&R 口径；综合 17 149 / 6 324） |
| DSP | 20 / 29（69.0%） |
| 时序 | Setup **+572 ps**，Hold **+36 ps**，0 FEPS |
| 当前 bit | `bitstream/HDMI2_HDMI14_Player_v71.bit`（675,020 B） |
| MD5 | **F0EF11FAE171E341ADEBD9473B36EB01** |

> 2026-10-27 v71（当前定版，已回写 FLASH）：**任意分辨率缩放** —— `bmp_read` 不再只认 640/1280/1920 三档，
> 改成 N = max(ceil(W/640), ceil(H/480))（1..4），按 N 整数抽取后右/下补黑凑满 640x480，
> 支持 W≤2560、H≤1920 的任意 24 bit BMP（**0 BRAM**）。黑边位置也修正过：BMP 是自底向上存的，
> 所以"画面下方黑边"必须在读像素**之前**补（新增 `ST_PADTOP`，用减法循环算 out_h=ceil(H/N)）。
> **v75 曾在 ST_PADTOP 里漏了计数器条件（每拍清零）→ 补行永不结束、点图卡死**，v76 已修（一行）。
> **最左白边：回填方案全部撤销**（主界面也撤了，用户实测没用），要根治只能改 de/OSD 时序。
> 资源 4635 mslices（94.6%）、Setup +655 ps / Hold +21 ps。
> 测试图 A07~A10/B05/B06 见 `SD卡上内容/缩放测试说明.txt`。
>
> 2026-10-27 v71：**切图只改"淡出与装载并行"一项**——装载一开始就变暗、
> 图到了再亮回来（淡变时长保持原来的 0.37 s，0.13 s 太快看不出动画）；
> v70 的"最左白边回填"已撤销（目录页出色块、图片页有错位，各页面流水深度不同，
> 固定回填必然多补/少补），正解是把 OSD 计数按页面提前 D 拍启动，待单独验证。
> 资源 4634 mslices / 59 BRAM，Setup +572 ps / Hold +36 ps，place seed 6。
>
> 2026-10-27 v70：**切图提速 + 最左白边修复**（白边方案已撤销，见 v71）。淡变 0.37 s→0.13 s（A_STEP 3→8），
> 并且改成"装载一开始就先暗下去、图到了再亮回来"（淡出与装载并行）；
> 每行最左 6 个像素用本行 x=16 的真实像素补（不改 de、不整帧移位），
> 解决主菜单/图片页最左那条白竖线（v48~v55 八次修补都没治根）。
> 资源 4553 mslices / 59 BRAM / LUT 17 269，Setup +667 ps / Hold +25 ps。
>
> 2026-10-27 v69：**主菜单第三项「系统」改成「系统简介」，系统页重做成四页图文**
> （四个展区 / 分区配乐 / 自适应缩放 / 参数口径），**A/D 左右键翻页**、Back 退出；
> 正文用 8 px 一格 + 汉字 16 px 两种字宽混排，数字/英文不再占满 16 px 格。
> 字库改成「文本 ROM（1024×9，1 块 BRAM）+ 小字库（128 槽×16，4 块）」，RTL 里
> 不再硬编码字槽。资源反而下降：mslices 4620 → **4538**、LUT 17 427 → **17 113**，
> BRAM 56 → **59**；Setup +737 ps / Hold +25 ps，0 FEPS（place seed **2**：seed 3 会 -105 ps / 1 FEPS）。
>
> v54 保留 SPI 25 MHz 和 `video_delay` 消隐保持修复；主菜单最左仍有 1 px 级
> 浅白线，用户确认保留。v46 的 CMD18 方案未通过板测，已回退；v45 仍保留为
> 12.5 MHz 回退：`bitstream/HDMI2_HDMI14_Player_v45.bit` +
> `project/dsh_flash_v45_rollback.tcl`。

⚠️ **Hold 只有 ~23 ps**：布线必须开 route 阶段的 `fix_hold`（`project/.../phy_1/settings.cfg` 里
`arr_filter on` + `arr_rwns -100000` + `drHoldFix on`）。关掉它实测 Hold 为负 / 有违例端点。

---

## 2. 这一轮做了什么（按功能）

### 2.1 滚动字幕（`rtl/subtitle_overlay.v`，模块 `info_bands`）
- 3 句循环，约 50 s 一轮：
  1. 随展区变：`欢迎参观 · 曾侯乙编钟 / 青铜礼器 / 唐三彩 / 越王勾践剑`
  2. `展厅内请保持安静，请勿触摸展品，拍照请关闭闪光灯`
  3. `开放时间 9:00—17:00，讲解服务请至前台预约`
- 进区自动回到第 1 句；9 bit 字符码，`0x00..0xFF` 走主字库，`0x100+` 走 `font_rom_ext`（1024×16，2 块 BRAM）。
- 文案由 `tools/make_subtitle_font.py` 生成（见 §5 字库流程）。

### 2.2 主菜单（`rtl/main_menu.v`）
- 标题「博物馆智能展品讲解系统」11 字，2 倍放大，`TITLE_W=352`；
- 标题字模（槽位 `0x8D..0x91`）用 **宋体 16 px 直接渲染 + 阈值 128**（`tools/make_menu_assets.py`），
  笔画平均 2.14 px，与原厂「智能展品讲解」的 2.26 px 对齐；早期用微软雅黑渲染只有 1.84 px，2 倍放大后发糊。
- 右侧 4 个展品图标（编钟/鼎/三彩马/剑）：44×44 1bpp 精灵，`rtl/menu_icon_rom.v` + `menu_icon.hex`，1 块 BRAM；
  颜色 `C_ICON = 0x8A8FA8`，与选中色 `mix8(C_ICON, tint, 1)` 各半混合（早期 `0x3A3555` 太深）。
- 选中色渐变：**168 ms**（`FADE_CYC = 24'd4_194_304`，`fstep = fade_cnt[22:19]`）。
  ⚠️ 改 `FADE_CYC` 必须同步改切片位，否则 8 级走不满、颜色变不到位（420 ms 版本曾踩过）。

### 2.3 目录页（`rtl/directory_ui.v`）
- 左侧：**展区徽标**（上，216×162，见 §2.5）+ 三行文字（下）
  - 展区名：`曾侯乙编钟 / 青铜礼器 / 唐三彩 / 越王勾践剑`
  - 时代说明：`战国 · 青铜编钟 / 商周 · 青铜礼器 / 唐代 · 陶俑 / 春秋 · 青铜兵器`
  - 固定提示：`请勿触摸展品`
- 右侧 4 行列表：展区中文名 + 圆点 + 选中高亮，**没有** `ZONE A-D` 字样了；
- 文字走 `font_rom_ext`（目录页自己一份，2 块 BRAM），9 bit 码，**2 拍流水**与像素对齐；
  行文字索引是 6 bit（`ridx5`），左侧标题用 `lidx`（`x-24`）——两者不能混用，混用会出现"取到隔壁字"的乱码。

### 2.4 图片页（`rtl/subtitle_overlay.v` + 图片素材）
- **切图过渡**：不再黑幕硬扫，改成「暗到页面底色 `#EEF5FC` → 换 buffer → 亮出新图」，
  11+11 帧 ≈ **0.37 s**（alpha 5 bit、每帧 3 级，`top_tf_hdmi_audio.v` 的 `vout_fade`）；
  显示索引 `disp_show_idx` 比 `disp_buf_idx` 慢半个过渡，靠"读地址每帧起点才锁存"保证不撕裂；
  混合公式 `out = C + ((pix - C) * a) >> 5`，全亮时旁路（不加延迟）。预览见 `tools/_preview/transition_strip.png`；
- ⚠️ **进区不再放两遍过渡**：目录里 W/S 的 `zone_preview` 不再触发后台装载，
  `zone_apply` 改成 toggle 跨域（`zone_apply_sd`）成单拍脉冲，过渡触发要求索引稳定 15 拍；
- 底栏右侧：**`曾侯乙编钟展区` / `青铜礼器展区` / `唐三彩展区` / `越王勾践剑展区`**
  （8 格 ×16 px = 128 px，右对齐到 x=632，前面补空格；全部走 ext 字库）；
- 底栏左侧 `n / 4`，顶栏左「手动/轮播中」、中间标题、右时间；
- **分区 BGM**：根目录 `MENU.WAV / A.WAV / B.WAV / C.WAV / D.WAV`（裸 16 bit 小端 PCM、48 kHz 单声道），
  主菜单与目录放 MENU，A~D 各放各的；播完用播放器自己的 `stream_end` 自动重来（循环）；
  换区时按 8.3 名重查一次并给播放器 `restart`（查找器只有一份，不占 BRAM）。详见 §2.8。

### 2.5 目录页展区徽标（方案 D，`rtl/directory_ui.v` + `rtl/zone_badge.hex`）

> 原来这里是「SDRAM 截图缩略图」（96×72 RGB444，`thumb_mem` 8192×12 = 11 块 BRAM
> + 顶层 5×5 抽样/三点平均/3 个 18×18 乘法器）。截图缩到 96×72 再放大 2.25 倍，
> 屏上就是一团糊（96×72 里连展区名都糊成 5 px），评审第一眼就是「没做好」。
> 2026-10-24 按「方案 D：不用缩略图，改展区徽标 + 文字」整体替换。

| 项 | 现状 |
|---|---|
| 画面 | 左侧预览框 216×162 @ (39,20)，**4 个展区各一张徽标**（编钟/青铜鼎/唐三彩马/勾践剑） |
| 素材 | 108×81 图源，**2 倍最近邻放大**（像素风印刷徽章）；`rtl/zone_badge.hex` |
| 编码 | 每像素 **2 bit 材质码**：0 paper / 1 tint / 2 accent / 3 ink |
| 存储 | 4 区 × 8748 × 2 bit = 69,984 bit → 1 片 34992×2 ROM（模块 `zone_badge_rom`，**8 块 BRAM9K**，综合实测 13 块） |
| 显示色 | 每区主色 `z_acc`（青/铜绿/琥珀/朱）+ `tint = (A>>1)+128`（50% 主色）+ 固定 paper/ink；**无乘法器** |
| 整列配色 | 切展区时**左右两列一起换色**：两列面板边框 = 50% 主色、选中行底 = 25% 主色、行边框/圆点 = 25%/主色、滚动条当前段 = 主色 |
| 滚动条 | 轨道 12..444（= 4×108，正好 4 行高），y=120/228/336 各开 2 px 缝 → **4 等分**；末段到底（旧版 12..446 轨道配 100 高块，第 4 行差 10 px） |
| 地址 | `addr = sel*8748 + by*108 + bx`；`by*108 = by*128 − by*16 − by*4`，全移位加减 |
| 流水 | 地址寄存器 1 拍 + ROM 1 拍 = **2 拍**，与字模 ROM 同相；展区色同样延 2 拍；徽标不进 `base_col`，在输出级按 `b_hit_d2` 覆盖 |
| 生成器 | `tools/make_zone_badges.py`（PIL 超采样 8× → 面积投票降采样 → 自动钩 1 px 外轮廓） |
| 自检 | `tools/check_zone_badge_render.py`：用 Python 复刻 RTL 的地址/调色板，逐像素比对素材原图（当前 4 区均为 0 差异） |

设计要点（改图时别丢）：
1. **图标只画色块，描边由脚本统一钩一圈**（`outline_layer`）。手画描边在形体交叠处会互相穿插，
   低分辨率下就变成一团乱线（老版本踩过：编钟一画就成"柜子"）。
2. **1 px 细线必须落在整数像素上**；降采样用「面积投票 + 平手偏向更深的材质」，
   用 `>` 会让 1 px 墨线全丢（描边消失）。
3. **边框至少 2 px 图源（= 4 px 显示）**：1 px 的彩色线在 640×480 上经显示器缩放/相机采样会糊成
   "深灰红"，看起来就不像展区色（板测反馈过）。圆环同理，现为 2 px。
4. 徽标**不要塞进 `thumb_*` 那套抽样逻辑**：ROM 按屏幕坐标直接寻址，与 SDRAM 读通路完全无关。
5. 2 bit/px 是资源与观感的平衡点：降到 1 bit 可再省 6 块 BRAM，但只剩两色，不再有描边和套色。
6. 预览产物在 `tools/_preview/`：`zone_badges.png`（4 张 2 倍图）、`zone_detail_N.png`（4 倍看细节）、
   `zone_page_N.png`（640×480 整页效果，配色与 RTL 一致）。
7. 目录页底部原有一条深紫「页脚条」（y 458..480，`C_FOOT/C_FOOTLN`）已删除——4 行列表用不到它，
   屏上只剩两道看不懂的横线。

### 2.6 字库合并（省 8 块 BRAM）
- `main_menu` 与 `settings_panel` **共用一份 `font_rom`**（`top` 里的 `u_shared_font`），地址由 `settings_active` 二选一；
- 前提条件：**设置面板打开时必须不透明**（面板外画 `C_OUT_BG` 压暗），否则菜单字模会露出来。
  `rtl/settings_panel.v` 里 `pix = C_OUT_BG;` 这一行**不要改回** `rgb_in`，除非同时把字库拆回去（+8 BRAM）。
- 现在 `font_rom` 实例：`u_font_rom`（info_bands）+ `u_shared_font`（menu/settings）= 2 份 × 8 = 16 块。

### 2.7 图片素材（16 张 640×480 24-bit BMP）
- 布局给 OSD 让位：内容压在 **y 32..410**，避开顶栏 0..31、字幕带 416..455、底栏 456..479；
- 左侧实景照片卡缩到 **240×290**（原 282×390），位置 (30,60)，内容更居中；
- 生成/重排脚本：`tools/relayout_card.py`（整页压进安全区）、`tools/shrink_card_photo.py`（照片缩小）；
- 产物：`SD卡图片/IMAGE00..15.BMP`；烧卡时改名 `A01..A04 / B01..B04 / C01..C04 / D01..D04`（同格式、同大小 921,654 B）。

### 2.8 音频只认 WAV：上电不再有"老音乐"（v19，2026-10-25）

**症状**：TF 卡根目录里没有 `MAIN.WAV`，可上电第一段响的就是"那首老曲子"，之后才切 `MENU.WAV`。

**原因**：不是读错文件、也不是 FLASH 里有音频残留。v14 的音频源是三选一：

```verilog
assign audio_left_src = wav_active_vid ? 采样 : (wav_found_any ? 24'sd0 : audio_left_data);
```

上电到"找到第一个 WAV"之间 `wav_found_any=0`，于是回落到内部测试音
`hdmi_audio_tone_i2s_64fs`（C4-D4-E4-G4-A4-C5-A4-G4，每音 0.5 s 循环）。它每次都一模一样、
又总在上电第一段，所以一直被当成"固化进 FLASH 的 MAIN.WAV"（`docs/修改记录.txt` 第 25 条
其实已经查过一次，v16 回退时把这条又带回来了）。

**现在的做法**（`rtl/top_tf_hdmi_audio.v`）
- 删掉 `hdmi_audio_tone_i2s_64fs` 与 `I2S_receiver` 两个实例（不是靠综合裁掉）；
- `audio_left/right_src` 只有两态：正在播 WAV → 采样，其它 → 0；
- `audio_valid_src = wav_sample_valid`，**必须保持 48 kHz 逐样本节拍，不能恒 1**——
  `audio_arc_calculate` 用它数样本算 ACR 的 CTS（48 样本 @25 MHz = 25000），恒 1 会算成 48；
- 音频 PLL / `audio_mclk` **保留**：`rst_all = ~rst_n | ~audio_pll_lock` 依赖它的 lock。

**连带约束**：`audio_mclk` 时钟已无负载，TD 会裁掉该时钟网；`timing.sdc` 里引用它的
4 条命令必须同步删掉 `audio_mclk`，否则 `set_clock_uncertainty -hold 0.050` 整条失败
（Hold 会虚高 50 ps）。实测改正后 Hold +26 ps。

**代价**：卡里一张 WAV 都没有时是全程静音（以前至少还有测试音）。两者不可兼得。

### 2.9 「系统」信息页（v44，主菜单第三项）

**行为**：主菜单 W/S 选到「系统」，Enter 打开只读信息层；主菜单不离开，
背景压暗 50% 仍可见。系统页打开时 W/S 被 `sys_on` 冻结，Enter / Q 关闭；
目录/图片/设置页不能打开它。设置页第 5 行「轮播」Enter 仍照旧切自动轮播。

**版面**：与 `settings_panel` 同一套深色卡片（`#171B22` + `#6E5FD8` 描边 +
金色标题），6 行「2 字标签 + 值」：

| 行 | 标签 | 值 |
|---|---|---|
| 0 | 器件 | `EG4S20BG256` |
| 1 | 输出 | `640X480P60` |
| 2 | 音频 | `48KHZ WAV` |
| 3 | 存储 | `TF CARD OK/ERR`（由 `boot_ok` 实时给出） |
| 4 | 资源 | `LUT17K BRAM54` |
| 5 | 版本 | `V44 20261026` |

**省资源做法**：
- `sysinfo_panel` 与 `settings_panel` **共用** `u_set_font`（两者永不同屏）⇒ 0 BRAM；
- 新增 13 个汉字写进主字库 `0x10..0x1C`（其中 `0x1A..0x1C` 原为空槽），
  字库仍 ≤ 4096 行 ⇒ TD 仍是 8 块 BRAM，**不增加 BRAM**；
- 文字查表用一条 7 bit 扁平 `case`；版面只画矩形/直线，无乘法器/行缓存。

**改动文件**：`rtl/menu_ctrl.v`（第三项 → `open_sysinfo`，保持 `menu_active`）、
`rtl/top_tf_hdmi_audio.v`（`sys_active` 开关与端口）、`rtl/sysinfo_panel.v`（重写）、
`rtl/font_rom.hex`、`tools/add_sysinfo_glyphs.py`、`tools/preview_sysinfo.py`。
详见 [`docs/v44_系统信息页.md`](docs/v44_系统信息页.md)。

### 2.10 底部两条带等高 + 删进度条（v45）

板测反馈：字幕带（原 416..455，40 px）比底栏（456..479，24 px）高，
而且底栏左侧有一根旧进度条，现场看就是"左下角一条奇怪的横线"。

v45 改成：

| 区域 | 范围 | 高度 |
|---|---|---|
| 顶栏 | 0..31 | 32 px |
| 图片区 | 32..415 | 384 px |
| 字幕带 | 416..447 | **32 px** |
| 底栏 | 448..479 | **32 px** |

- 底部总高仍是 64 px（40+24 = 32+32），图片区/顶栏完全不动；
- 字幕文字仍在 424..439，底栏文字 456..471，各自在 32 px 内居中；
- 删除 `BAR_X0/X1/Y0/Y1`、`C_TRACK`、`bar_fill`、`bar_end`、`on_bar`，
  底栏只留 `n / m`（左）和展区名（右）；
- `info_bands` 从 698 LUT + 174 ripple 降到 **658 LUT + 133 ripple**，
  整版 LUT −85、mslices 4574。

### 2.11 A05/A06 加载速度（v47 已提速）

A05（1280×960，2×）和 A06（1920×1440，3×）慢的根因是 SD 读的
**SPI 时钟只有 12.5 MHz**（50 MHz / 4），再加上每 512 B 一个 CMD17：

| 图 | 源尺寸 | 抽取 | 读取扇区 | v45 实测约 |
|---|---|---|---:|---:|
| A05 | 1280×960 | 2× | 480×8 = 3840 | 3.9 s |
| A06 | 1920×1440 | 3× | 480×12 = 5760 | 5.8 s |

v47 把高速段 SPI 提到 **25 MHz**：

- `spi_master` 增加 `S_FAST` 状态：`clk_div==0` 时 DCLK 每拍翻转一次，
  16 拍发完一个字节；初始化仍用 `SPI_LOW_SPEED_DIV=248` 的低速；
- 不改 SD 命令/读状态机，不改 CMD17 流程，所以读图链和 v45 完全一致；
- 所有图的数据传输时间减半，A05/A06 也会跟着变快；实际秒数以板测为准；
- 资源基本不变：LUT 17 288、BRAM 54、mslices 4582。

**v46 的 CMD18 + 8 扇区缓存方案已判定失败**：板测图片/音乐全无，
源码已回退到 v45 的 SD 读链路；v46 只保留为失败记录
（`docs/v46_CMD18缓存.md`），不要再用那版 bit。

**回退**：v45 bit 仍在 `bitstream/HDMI2_HDMI14_Player_v45.bit`，
运行 `project/dsh_flash_v45_rollback.tcl` 可一键写回。

### 2.12 左边缘黑/白竖线（v54）

现象：图片页和目录页最左侧有一道黑线，主菜单没有；后来修成白线，
且会遮住字幕左端。

根因：`rtl/SD/video_delay.v` 在行消隐时把 `vout_data_r` 清零：

```verilog
else
    vout_data_r <= {DATA_WIDTH{1'b0}};
```

而 `de_r` 比数据晚一拍，所以每行第一个有效像素拿到的是这个 0（图片页黑线）。
主菜单/目录的 2 拍流水又把这个 0/白值继续带到左边，形成不同颜色的线。

v54 改成**消隐期间保持上一拍有效像素**（不清零），从源头去掉 0：

```verilog
else if (de_d[19])
    vout_data_r <= read_data;
// 不再 else 清零
```

结果：图片页/目录页黑线消失；主菜单最左仍可能有 1 px 级极细浅白线，
用户确认保留这一版（见 `docs/v54_左边缘修复.md`）。

资源：LUT 17 219、REG 6 368、BRAM 54、mslices 4 569，Setup +328 / Hold +33 ps。

### 2.13 「系统简介」四页说明页（v69，主菜单第三项）

主菜单第三项由「系统」改成「系统简介」，选中 Enter 打开只读说明页，
**A/D（左右键）翻页 0..3，Back 退出**；打开期间 W/S/Enter 被冻结，背景仍是主菜单。

| 页 | 标题（2 倍） | 正文 |
|---|---|---|
| 1 | 四个展区 | 曾侯乙编钟（6页）、青铜礼器（4页）、唐三彩（4页）、越王勾践剑（4页），共18页图文，全部由TF卡BMP装载、SDRAM双缓存切换； |
| 2 | 分区配乐 | 主界面MENU.WAV开场，A、B、C、D四区各一首专属48kHz讲解音频，换区自动换曲，装载新图时音乐不断（WAV优先仲裁）； |
| 3 | 自适应缩放 | 源图允许640×480、1280×960、1920×1440三种，装载期按N行/N列抽取，写进SDRAM的仍是标准640×480帧——0块BRAM的代价完成扩展要求3； |
| 4 | 参数口径 | 640×480P60、RGB888、HDMI 1.4b、48kHz 16bit单声道、LUT约17K、BRAM 59。 |

**版面**：卡片 80..560 × 78..412（与设置面板同色系），标题「系统简介」16 px 居中，
分隔线 y=120，页标题 2 倍 32 px（金色），正文 8 px 一格 × 56 格/行 × 3 行（青色），
底栏 `A/D:SWITCH  BACK:EXIT`，右上角页码 `n/4`。

**字宽混排（省 LUT 的关键）**：正文按 8 px 一格排，汉字占 2 格（16 px），
数字/英文占 1 格（取主字库 8 px 宽的字心，bit11..bit4）——
以前 ASCII 也占 16 px 格，一行只能放 28 个字符且数字之间全是空隙。

**字库**（两块 ROM，RTL 里没有硬编码字槽，全部由脚本生成）：

| ROM | 规模 | BRAM | 内容 |
|---|---|---|---|
| `rtl/sysintro_text.hex` | 1024 × 9 bit | 1 | `addr={page[1:0],line[1:0],slot[5:0]}`；line0 = 页标题(slot0..4)+标题字(slot8..11)，line1..3 = 正文；码值 `0x000..0x07F`=ASCII、`0x080\|n`=汉字左半、`0x180\|n`=汉字右半 |
| `rtl/font_rom_sys.hex` | 128 槽 × 16 行 | 4 | 114 个 16×16 汉字/标点（微软雅黑 16 px、字面位置固定不居中，标点才不会飘） |

- 主字库 `font_rom` 只补了两个字：`0x1D 简` / `0x1E 介`（`tools/add_intro_title_glyphs.py`），
  4096 深不变，仍是 8 块 BRAM；主菜单第三项的 4 个字格 = 系 0x90 / 统 0x91 / 简 0x1D / 介 0x1E。
- 生成器 `tools/make_sysintro_page.py`：改文案只需要改 `PAGES`，跑一次就重排
  `sysintro_text.hex` + `font_rom_sys.hex` + 4 张 640×480 预览
  （`tools/_preview/sysintro_p1..4.png` / `_2x` / `_sheet`）。
- 自检 `tools/check_sysintro_render.py`：用 Python 复刻 RTL 的取址规则逐像素比对
  生成器的理想版面，**当前 4 页均 0 差异**；改版面/换字库后先跑它再综合。

**流水**：地址（组合）→ 文本 ROM 输出 + 坐标寄存 → 字模 ROM 输出 = **2 拍**，
和设置面板一致，叠层不会错位；底栏/页码是纯 ASCII，用 `!ft_s1` 挡掉汉字分支
（它们那一列的文本 ROM 地址会落到正文行上，不挡就会画出正文的汉字）。

**资源**：mslices 4620→4538、LUT 17 427→17 113、BRAM 56→59、Setup +499→+737 ps（seed 2）。

### 2.14 v67 的 9 行中文滚动页（历史版本，已被 v69 取代）

`rtl/sysinfo_panel.v` 改成 **9 行中文说明页**，一次显示 7 行，只保留
亮点/加分点和三条关键参数：

| 行 | 内容 |
|---|---|
| 0 | `博物馆智能展讲` |
| 1 | `亮点/加分点` |
| 2 | `4 个展区 A/B/C/D` |
| 3 | `主菜单+各展区不同音乐` |
| 4 | `曾侯乙 图5/6 缩放适配` |
| 5 | `音频波形可视化` |
| 6 | `640X480P60 RGB` |
| 7 | `48KHZ 16BIT WAV` |
| 8 | `LUT17K BRAM54` |

- **Up/Down 移动选中行**，窗口自动滚动；选中行紫色背景 + 左侧金色竖条，
  文字变白；底部 `UP/DOWN:SCROLL  BACK:EXIT`；Back 退出。
- 标题「系统信息」和 ASCII 仍走主字库 `font_rom`；正文 35 个中文
  （博物馆智能展讲、亮点加分点、个展区、主菜单、各不同音乐、曾侯乙、
  图、缩放适配、音频波形可视化）放进一块 **576x16 小字库**
  `rtl/font_rom_sys.hex`（2 块 BRAM），不改 `font_rom_ext` 的 64 个槽，
  不影响字幕/目录。
- 资源：LUT 17 427 / REG 6 363 / BRAM 56 / DSP 20 / **mslices 4 620（94.3%）**，
  Setup +499 ps / Hold +25 ps，0 FEPS（**seed 4**）；seed 3 会 -416 ps，
  必须用 seed 4。
- 原 v65 两页、v66 英文 14 行方案均已被 v67 取代；见
  `docs/v67_系统信息中文滚动页.md`。

---

## 3. 仓库结构

```
rtl/                可综合 RTL、IP、字库（font_rom.hex / font_rom_ext.hex / font_rom_sys.hex /
                    sysintro_text.hex / menu_icon.hex / zone_badge.hex 必须与 .v 同目录）
constraints/        时序与引脚约束（pin.adc / timing.sdc）
bitstream/          当前 bit、历史 bit、MANIFEST
project/            TD 工程（.al）+ Runs/syn_1、Runs/phy_1（含 settings.cfg / dsh_run.tcl）
SD卡图片/           16 张成品 BMP（IMAGE00..15）
tools/              字库/图片/工程文件生成脚本
docs/               交接、使用、代码说明
```

### 3.1 修改前 / 修改后 两份快照

| 用途 | 路径 | 说明 |
|---|---|---|
| **修改后（本仓库，当前工作副本）** | `E:\AnLU_QianSai\HDMI2-EG4S20_New\HDMI2-EG4S20` | 含全部改动、SD 卡图片、构建产物 |
| **修改前（只读参照）** | `E:\AnLU_QianSai\HDMI2-EG4S20` | 由 git `HEAD ac38798` 导出的原始工程：127 个文件、2.1 MB，只有源码 + 原始 bit，**没有** `SD卡图片/`、`user_source/`、构建产物 |
| 原版 README 留档 | 本仓库 `docs/README_修改前.md` | 修改前那版 69 行说明 |

> 两份互不共享 `.git`；修改前那份只作对照，不要在里面改代码。
> 构建产物（`project/**/*.db` 等，约 43 MB）可随时删掉重生成，不影响源码。

---

## 4. 构建与烧录

### 4.1 命令行（推荐）
```powershell
# 综合：read_design -> opt_gate
cd E:\AnLU_QianSai\HDMI2-EG4S20_New\HDMI2-EG4S20\project\HDMI1.4b_Transmitter_v1.0_Runs\syn_1
E:\AnLu_Install\bin\td_commands_prompt.exe dsh_run.tcl

# 布局布线 + 生成 bit：opt_place -> opt_route -> bitgen
cd ..\phy_1
E:\AnLu_Install\bin\td_commands_prompt.exe dsh_run.tcl
```
- 综合后看 `syn_1\flow.status`（Setup/Hold）与 `HDMI1.4b_Transmitter_v1.0_gate.area`（资源）；
- 布线后看 `phy_1\route_flow.status` 与 `td_*.log` 里的 `RUN-1001 : N mslices, ...`；
- 重跑前把 `*.db / *.area / *.log / *.logw / flow.status / route_flow.status` 删掉，避免用旧结果。

### 4.2 GUI
打开 `project/HDMI1.4b_Transmitter_v1.0.al` → Read Design / Optimize RTL / Gate / Placement / Routing / Bitstream，
布局 seed 用 **2**（v69 实测：seed 2 → +737 ps、3 → -105 ps / 1 FEPS、4 → +125、5 → +266、7 → +305）。

> 命令行流程里的 seed 写在 `phy_1\HDMI1.4b_Transmitter_v1.0.tcl` 的 `opt_place` 可编辑区
> `set_param place seed 2`。GUI 重新生成这个 tcl 会把该行丢掉，记得补回来。

### 4.3 烧录（BitWriter）

当前定版用 `project/dsh_flash.tcl` 直接写配置 FLASH（`program_spi`，约 64 s + verify）：

```tcl
catch {list_cable} e0
catch {download -bit E:/AnLU_QianSai/HDMI2-EG4S20_New/HDMI2-EG4S20/bitstream/HDMI2_HDMI14_Player_v69.bit \
       -mode program_spi -v -spd 8 -sec 64 -cable 0 -flashsize 128} e1
puts "FLASH_RC=$e1"
exit 0
```
```powershell
E:\AnLu_Install\bin\bw_commands_prompt.exe E:/AnLU_QianSai/HDMI2-EG4S20_New/HDMI2-EG4S20/project/dsh_flash.tcl
# 成功标志：PRG-2014 : Chip validation success: EG4S20BG256
#           program_spi ... 64.8 s，随后 verify_spi / program 无报错
```
只写 SRAM 做临时验证时去掉 `-mode program_spi`（断电即丢）。

---

## 5. 字库 / 文案修改流程（重要，顺序不能错）

```powershell
# 1) 改文案：tools/make_subtitle_font.py 里的 SENTENCES / DIR_NAMES / DIR_DESCS / DIR_HINT
#    （主菜单标题字模改 tools/make_menu_assets.py）

# 2) 跑生成器：必须让它跑完！不要接 | Select-Object -First N
#    ——管道被提前关闭会 BrokenPipe 杀掉进程，hex/map 写了、*_params.vh 没写，
#      结果是"字库是新的、RTL 里还是旧编码"，屏上全是串位乱码（第 11 轮踩过）
python tools/make_subtitle_font.py

# 3) 把生成好的常量贴回 RTL（subtitle_overlay.v + directory_ui.v）
python tools/patch_text_params.py

# 4) 校验：RTL 里的段码必须和字库表一致
python tools/check_codes.py        # 或 tools/verify_codes.py，输出应全部 MATCH
```

- `font_rom_ext` 现在 **63/64 槽**，只剩 1 个空位；再加新中文要么扩到 2048 深（+2 块 BRAM），要么删文案。
- 目录页/GUI 用到的字必须在 **ext 字库**里（目录页不实例化主字库）：
  生成器里 `FORCE_NEW = {"·", "请", "展", "区"}` 就是为了把只出现在目录/底栏的字强制放进 ext。

---

## 6. 踩过的坑 / 不要动的地方

| # | 坑 | 说明 |
|---|---|---|
| 1 | **ROM 深度被裁** | `info_bands` 的主字库若不出现高地址访问，TD 会推断成 2048 深（4 块），`0x80` 以上字模全部别址（顶栏/字幕变花且不报错）。`subtitle_overlay.v` 里 `pixel_x >= 640` 时取 `0xFF` 槽的**护栏代码不要删**，删了综合器就会裁。 |
| 2 | **字库共用前提** | `settings_panel` 必须不透明（`pix = C_OUT_BG`），否则菜单字模外泄。 |
| 3 | **`$readmemh` 路径** | 按**源文件目录**解析，`font_rom.hex` / `font_rom_ext.hex` / `menu_icon.hex` / `zone_badge.hex` 必须留在 `rtl/`。 |
| 4 | **`.al` 文件** | 必须是 **CRLF**、文件名必须等于工程名（否则 PRJ-8640 / PRJ-8643）；被 TD 改坏后用 `python tools/gen_al.py` 重生成。 |
| 5 | **新增/删除源文件** | 先跑 `python tools/gen_al.py` + `python tools/gen_prj.py`，否则 `HDL-8007 black box` / `GUI-8004 Source file is missing`。 |
| 6 | **global_def.v shim** | `user_source/hdl_source/include/global_def.v` 是按工程目录解析的旧 include，`rtl/SD/sdram.v` 依赖它，**不要删**。 |
| 7 | **预载方案已回滚** | 曾做过"4 槽位 SDRAM 预载 + 后台填充"，会导致**自动跳页 / 上下键方向错乱**，已整套撤销（`sd_card_bmp.v` 里无 `slot_valid/fill_active/load_is_fill` 残留）。切图仍是"读完再显示 + 0.33 s 幕帘"，稳定。 |
| 8 | **Hold 余量小** | 25 ps。再往 `sd_card_bmp` 的优先级链或 OSD 组合逻辑上加逻辑前，先看 `route_flow.status`。 |
| 9 | **BMP 格式** | 640×480、24 bit、无压缩、921,654 B；改名成 `A01..D04`，固件按 8.3 短名扫根目录。 |
| 10 | **徽标 1 px 线会丢** | `tools/make_zone_badges.py` 的面积投票降采样若把平手判给浅色，1 px 描边会整条消失（徽标变成一坨色块）。必须 `>=`（平手偏向更深材质），且细线落在整数像素上。 |
| 11 | **`thumb_mem.v` 已弃用** | 还在 `.prj` 里但不再例化（0 BRAM），留着只为免动工程清单；确认没人用后可删并重跑 `tools/gen_al.py` + `tools/gen_prj.py`。 |
| 12 | **删时钟要同步改 SDC** | 删掉 `audio_mclk` 后 `timing.sdc` 里 4 条引用它的命令会报 `USR-8130/8159`，其中 `set_clock_uncertainty -hold 0.050` 一旦失败，Hold 会虚高 50 ps（实测 421→471）。删任何时钟前先 grep 约束文件。 |
| 13 | **Setup 掉下来先换 seed** | 临界路径是 `sd_card_bmp` 的 zone_scan→load_sector 组合链，与音频这类改动无关。实测 seed 5 → +124 ps、seed 1 → +296 ps、**seed 3 → +861 ps**。别先怀疑自己的逻辑。 |

---

## 7. 按键

| 页面 | 操作 |
|---|---|
| 主菜单 | W/S 选择，Enter 进入，Q 退出菜单；第三项是「系统简介」 |
| 系统简介（主菜单第三项） | Enter 打开只读四页说明；**A 上一页 / D 下一页**（到头夹住不循环）；Back 关闭；打开时 W/S/Enter 冻结，不会带动背景菜单 |
| 目录 | W/S 切区，Enter 进图，Q 回主菜单 |
| 图片 | A 上一张 / D 下一张；Q 回目录/主菜单 |
| 设置 | W/S 选行，A/D 调值，Enter 确认/进入时间编辑，Q 关闭 |
| 编码器 | 旋转调亮度/对比度；长按 0.8 s 开关设置面板（菜单/目录打开时无效） |

---

## 8. 版本记录（2026-10-24 这一轮）

| 阶段 | bit / MD5 | 资源 | 内容 |
|---|---|---|---|
| 原始定版 | `HDMI2_HDMI14_Player_final.bit` / `FF519E68…` | 4179 ms / 55 BRAM | 四区播放、字幕、菜单雏形 |
| 博物馆字幕 | `…_subtitle_museum.bit` / `1D81C065…` | 4209 ms / 57 BRAM | 字幕换博物馆文案 |
| 新标题+图标 | `…_museum_menu.bit` / `BEF6CA67…` | 4226 ms / 58 BRAM | 标题 11 字、右侧 4 图标 |
| 目录页改版 | 同上文件 / `E4C3500A…` | 4191 ms / 57 BRAM | 中文展区名、左下说明、72×54 缩略图 |
| 目录修正 | 同上文件 / `43142450…` | 4259 ms / 57 BRAM | 修行索引回绕、左标题取码、加提示行 |
| 提示改词 | 同上文件 / `BDAAFC64…` | 4255 ms / 57 BRAM | 「请勿触摸展品」、缩略图列索引修正 |
| 展区名+图片 | 同上文件 / `9424F2DD…` | 4187 ms / 57 BRAM | 底栏「…展区」、图片重排（照片缩小） |
| 过渡加速 | 同上文件 / `D5181629…` | 4203 ms / 57 BRAM / 21 DSP | 幕帘 20 帧、渐变 168 ms |
| SDRAM 预载 | 同上文件 / `0BA501FC…` | 4240 ms / 57 BRAM | **已回滚**（自动跳页） |
| 缩略图 96×72 | 同上文件 / `D1F9CE36…` | 4246 ms / 60 BRAM | RGB565→RGB444、5×5 抽取 |
| 字库合并 | 同上文件 / `5333CA93…` | 4212 ms / 52 BRAM | 菜单/设置共用 font_rom（−8 BRAM） |
| 缩略图 216×162 | 同上文件 / `525D5DB3…` | 4242 ms / 52 BRAM / 24 DSP | 缩略图等比显示（上一版） |
| **当前：v69** | **`HDMI2_HDMI14_Player_v69.bit` / `42076F1B…`** | **4559 ms / 59 BRAM / 20 DSP** | **主菜单第三项改「系统简介」；系统页重做成四页图文（四个展区 / 分区配乐 / 自适应缩放 / 参数口径），A/D 左右翻页、Back 退出；正文 8 px 一格 + 汉字 16 px 混排（ASCII 取主字库 8 px 字心）；文本 ROM 1024×9（1 BRAM）+ 小字库 128 槽×16（4 BRAM），RTL 不硬编码字槽；`make_sysintro_page.py` 生成、`check_sysintro_render.py` 逐像素自检 0 差异；LUT 17 220 / REG 6 327；Setup +737 ps / Hold +23 ps，0 FEPS，place seed 2** |
| v67（已被 v69 取代） | `HDMI2_HDMI14_Player_v67.bit` / `34C1F8BD…` | 4620 ms / 56 BRAM / 20 DSP | 系统页 9 行中文 Up/Down 滚动；正文 35 个中文进 576x16 小字库（2 BRAM）；LUT 17 427 / REG 6 363；Setup +499 ps / Hold +25 ps，seed 4 |
| v66 | `HDMI2_HDMI14_Player_v66.bit` / `2096F542…` | 4661 ms / 54 BRAM / 20 DSP | v65 基础上把系统信息页改成 14 行英文 Up/Down 滚动说明页；7 行窗口、选中高亮 + 竖条、Back 退出；LUT 17 628 / REG 6 362；Setup +952 ps / Hold +33 ps，0 FEPS，seed 3（已被 v67 取代） |
| v54 | `HDMI2_HDMI14_Player_v54.bit` / `B6D54613…` | 4569 ms / 54 BRAM / 20 DSP | 保留 v47 的 SPI 25 MHz；`video_delay` 消隐期间保持上一拍，去掉每行第一个像素的 0；图片/目录黑线消失，主菜单残留 1 px 级浅白线（用户确认保留）；LUT 17 219 / REG 6 368；Setup +328 ps / Hold +33 ps，0 FEPS，seed 3 |
| v47 | `HDMI2_HDMI14_Player_v47.bit` / `7330B46F…` | 4582 ms / 54 BRAM / 20 DSP | SPI 高速段 12.5→25 MHz（`spi_master` S_FAST，初始化仍低速）；读图链与 v45 相同；LUT 17 288 / REG 6 375；Setup +1079 ps / Hold +25 ps，0 FEPS，seed 3 |
| v46（失败，已回退） | `HDMI2_HDMI14_Player_v46.bit` / `83D6F0CF…` | 4665 ms / 58 BRAM / 20 DSP | CMD18 + 8 扇区缓存实验；板测图片/音乐全无，源码已回退到 v45 读链路；**不要使用** |
| v45 | `HDMI2_HDMI14_Player_v45.bit` / `A4270695…` | 4574 ms / 54 BRAM / 20 DSP | 字幕带/底栏 32 px + 32 px 等高（总高 64 不变），删底栏左侧旧进度条；`info_bands` 698→658 LUT；整版 LUT 17 264 / REG 6 337；Setup +521 ps / Hold +25 ps，0 FEPS，seed 3 |
| v44 | `HDMI2_HDMI14_Player_v44.bit` / `97949274…` | 4614 ms / 54 BRAM / 20 DSP | 主菜单第三项「系统」= 只读配置信息页（背景仍主菜单，只能从主界面打开）；修正 v43 点系统进轮播/设置的问题；LUT 17 371 / REG 6 377；Setup +1204 ps / Hold +21 ps，0 FEPS，place seed 3 |
| v19 | `HDMI2_HDMI14_Player_menu_wav_first.bit` / `1D0CE03B…` | 4293 ms / 54 BRAM / 20 DSP | 音频只认 WAV（删内部测试音 + I2S_receiver）：上电第一段声音就是 MENU.WAV；−88 mslices / −163 LUT / −378 REG / −3 DSP，Setup +861 ps / Hold +26 ps，place seed 3 |
| 上一版：v18 = v14 | `HDMI2_HDMI14_Player_zone_badge.bit` / `595D4526…` | 4381 ms / 54 BRAM / 23 DSP | 按需求回退到 v14（分区 BGM 可用版）；v15~v17 的黑屏修复/重扫/SD 看门狗全部撤掉；**上电会先响内部测试音** |

`…_museum_menu_prev.bit` 是"含预载 bug"的备份，**不要用**；需要回退用上表任一 MD5 重建。

---

## 9. 已知限制 / 可继续做的事

- **目录页左侧预览**已经是徽标（不是实时截图），所以「预览」与真实图片不再一致——这是方案 D
  的取舍：清晰、有个性，但不再"所见即所得"。如果想两者兼得，只有走方案 E（1:1 显示画面的一块，
  要从 SDRAM 再读一路 + 行缓存，约 +1 块 BRAM + 200 LUT + 仲裁逻辑，工作量最大）。
- **BRAM 已到 59/64（92%）**：徽标 ROM 占 13 块（2 bit/px × 4 区 × 108×81），
  系统简介的文本 ROM 1 块 + 小字库 4 块。再要省只能降到
  1 bit/px（−6 块，但只剩两色）；再要加字库/图标就得先从这里腾。
- 根目录 WAV 只认第一个文件；WAV 循环点按文件大小估算。
- 图片只扫描根目录第一簇目录项。
- 波形参数沿用原工程（128 高 / DECIMATE 24）。
- 系统简介正文写死在 `tools/make_sysintro_page.py` 的 `PAGES` 里（编译期进 ROM），
  改文案要重跑生成器 + 重新综合；不支持运行时读 TF 卡文本。

---

## 10. 文档

- [交接说明](docs/交接说明_HANDOFF.md)
- [使用说明](docs/使用说明_USAGE.md)
- [代码说明](docs/代码说明.md)
- [字幕与字库说明](docs/字幕与字库说明.md)
- [系统简介四页（v69）](docs/v69_系统简介四页.md)
- [v69~v78 改版与问题排查总结（Word）](docs/HDMI2_EG4S20_v69-v78_改版与问题排查总结_20261027.docx)
- [修改记录](docs/修改记录.txt)
