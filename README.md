# HDMI-7 工程备份 —— 结构说明（README）

本目录是 **当前实际版本** 的独立工程备份：第十讲基线 + 第十一讲（WAV 播放）+ 第十二讲（音频波形可视化）。
**只含与当前版本有关的文件** ✓；中间实验版比特流、历史文档、参考讲义素材、测试音频均未纳入（它们在原工程里完好保留）。

- **打开**：`src\td_project\HDMI1.4b_Transmitter_v1.0.al` → 见 [`打开说明.md`](打开说明.md)
- **当前比特流**：`bitstream\HDMI1.4b_Transmitter_v1.0_L12_x7_695861ED.bit`
  MD5 = `695861ED1B171ACD6EF0A748E3954FCC`
- **清单**（逐文件字节数 + MD5 前 8 位）：[`FILELIST.txt`](FILELIST.txt)
- **规模**：110 个文件 / 1.80 MB；`.prj` 引用校验 **136/136 齐备** ✓

---

## 一、顶层目录

```
HDMI-7\
├── 打开说明.md          如何用 TD 打开、本工程踩坑清单（必读）
├── README.md            本文件：工程结构说明
├── FILELIST.txt         文件清单（含 MD5）
├── bitstream\           当前版本的比特流（唯一一份）
├── docs\                第十二讲交付说明 / 第十一讲交付说明 / 第十一讲进展记录
└── src\                 ★ 工程本体（层级不可改动）
    ├── td_project\      TD 工程：.al + al_ip + Runs\syn_1 + Runs\phy_1
    └── user_source\     全部 RTL 源码与约束
```

---

## 二、TD 工程结构（`src\td_project\`）

| 路径 | 作用 |
|---|---|
| `HDMI1.4b_Transmitter_v1.0.al` | **TD 工程文件**（打开它 ✓，24.6 KB） |
| `al_ip\` | 工程级 IP 配置：`PLL.ipc` / `PLL_HDMI_AUDIO.ipc` / `AUDIO_SAMPLE_ROM.ipc` |
| `HDMI1.4b_Transmitter_v1.0_Runs\syn_1\` | **综合**流程：`settings.cfg` + `.tcl` + `.prj`（源文件清单） |
| `HDMI1.4b_Transmitter_v1.0_Runs\phy_1\` | **布局布线 + 生成比特流**流程：同上三件；其 `settings.cfg` 里 `set parent ../syn_1`、`start_step opt_place` → `end_step bitgen` |

**流程** ✓：先在 `syn_1` 跑综合 ✓，再在 `phy_1` 跑 P&R/bitgen ✓（`.prj` 中源文件路径为 `../../../user_source/...` ✓，从 `...Runs\syn_1\` 上三级正好是 `src\` ✓，故**目录层级不能改** ✓）。

**源文件组织** ✓：芯片顶层在 `syn_1` 侧为 `top`（见下），IP 由 `.ipc`/`.tcl` 描述 ✓（PLL、FIFO、SDRAM ✓）。

---

## 三、RTL 结构（`src\user_source\`）

```
src\user_source\
├── constraints_source\     pin.adc（引脚约束）, timing.sdc（时钟/时序约束）, edid_debug.cwc, *.ipc/*.v
├── ip_source\              pll.ipc / pll.v / pll.vhd（PLL 源码型 IP）
└── hdl_source\
    ├── top_tf_hdmi_audio.v ★ 顶层模块 top（46.8 KB，39 处例化）
    ├── SD\                  SD 卡控制器族 + FAT32 + SDRAM 相关（20 个 .v）
    ├── IP\                  afifo_16_256 / afifo_16_32_256 / afifo_32_16_256 / sdram / sys_pll / video_pll（.v + .ipc + .tcl）
    ├── include\             global_def.v 与 SDRAM 控制器加密源码 sdr_*.enc.v
    ├── rom\                 音频/图片相关 ROM（初始化数据）
    ├── hdmi1.4b_transmitter_core\  HDMI 1.4b 核封装（.enc.v，加密）
    └── test\                测试激励
```

### 顶层 `top` 的功能块与例化位置（`top_tf_hdmi_audio.v`）

| 功能块 | 主要模块（顶层行号 ✓） |
|---|---|
| **时钟/复位/同步** | `PLL_HDMI_AUDIO u_audio_pll`（345）、`reset_sync`（264/270/276/282）、`sync_2ff`（231/238/245/288/297/304/312/319/935） |
| **SD 卡与文件系统** | `sd_card_bmp #(...)`（552，含 `sd_card_top`/`sd_card_cmd`/`sd_card_sec_read_write` 与 **3 个扇区主**：图片扫描 `fat32_volume_scanner`、流式 `fat32_file_streamer`、WAV ✓）、`fat32_find_file #(...)`（387，按名定位 `*.WAV` ✓）、`wav_stream_player`（452，16 位样本 + 循环缓冲 ✓） |
| **媒体存储通路** | `media_player_control`（740）→ `media_frame_loader`（767）→ `media_sdram_write_cdc`（799）→ **SDRAM** → `media_frame_reader`（868）→ `rgb_video_adapter`（904） |
| **显示链** | `video_timing_ctrl`（686）→ `video_fade_transition`（957，转场淡入淡出 ✓）→ `osd_overlay_24`（986，状态 OSD ✓）→ `subtitle_frame_commit`（1032）+ `subtitle_overlay`（1049，底部滚动字幕 ✓）→ **`promax_audio_waveform`（1071，第十二讲音频波形 ✓）** → `video_rgb_to_axis_640x480`（1148） |
| **音频链** | `hdmi_audio_tone_i2s_64fs`（1114，提示音）+ `I2S_receiver`（1125）→ `audio_arc_calculate`（1136，ACR N/CTS ✓）；**WAV 路径**：`wav_stream_player` 的 `sample_valid/sample_out` 与提示音经 2:1 选择后送 HDMI 核 ✓；`sync_fade_gain`（511）做**音画同步**增益 ✓ |
| **HDMI 输出** | `hdmi_1_4b_transmitter_core_wrapper`（1170，含 `.AUDIO_SAMPLE_RATE("48K")` ✓）→ `hdmi_phy_wrapper`（1217）+ `lane_lvds_10_1` |
| **按键/显示器件** | `fast_boot_gate`（923）、`key_remove_shakes`、`ax_debounce`、`seg_scan` + `seg_decoder`（6 位数码管）、`startup_pulse`（1161） |

### 数码管含义（调试时最有用 ✓）

| 位 | 显示内容（源码 `seg_scan` 例化处 ✓） |
|---|---|
| `seg_data_0` | reader 错误码 |
| `seg_data_1` | loader 解码错误码 |
| `seg_data_2` | CDC 状态 |
| `seg_data_3` | 按键事件计数 |
| **`seg_data_4`** | **已加载 bank 数（`loader_image_complete`）——正常为 `F`；若为 `0` 即"启动装载失败"，此时必然黑屏** ✓ |
| `seg_data_5` | WAV 速率表高位（本工程诊断用） |

---

## 四、时钟与时序

| 项 | 位置 / 说明 |
|---|---|
| 输入时钟 | `timing.sdc`：`create_clock clk 20ns`（50 MHz）✓，并 `derive_clocks`、对 PLL 输出 `rename_clock`（`clkc[0]`→`sd_card_clk` 等 ✓） |
| PLL | 工程级 `al_ip\PLL*.ipc` + `hdl_source\IP\sys_pll.*`、`video_pll.*`；当前输出包括 **sd_card_clk ≈50 MHz**（SD 侧 ✓）、**video_clk 25 MHz**（像素域 ✓）、**ext_mem_clk / hdmi_5x_clk 125 MHz**、**audio_mclk 12.288 MHz** ✓（确切参数以 `.ipc` 为准 ✓） |
| 引脚 | `constraints_source\pin.adc` ✓ |
| EDID | `edid_debug.cwc`（另有 `.bak`） |

---

## 五、关键文件速查（要改什么就找哪里）

| 想改的内容 | 文件 |
|---|---|
| 第十二讲波形外观（颜色/框/加权/条） | `hdl_source\promax_audio_waveform.v` ✓（参数 `WAVE_X/Y/WIDTH/HEIGHT`、`GRAY`、`BAR_GAP`、`DECIMATE` ✓；窗型加权在**采集侧** ✓） |
| 波形在链路上的位置与使能 | `hdl_source\top_tf_hdmi_audio.v` 第 1071 行附近（`enable = wav_active` ✓） |
| WAV 播放（循环、扇区请求、缓冲） | `hdl_source\wav_stream_player.v` ✓、`hdl_source\SD\sd_card_bmp.v`（WAV 扇区主端口与仲裁 ✓） |
| 按文件名找 `*.WAV` | `hdl_source\fat32_find_file.v` ✓（`MATCH_MODE`：0=任意 `*.WAV`，1=精确 8.3 名 ✓） |
| 音画同步增益 | `hdl_source\sync_fade_gain.v` ✓ |
| 转场淡入淡出 | `hdl_source\video_fade_transition.v` ✓ |
| 字幕 / 状态 OSD | `hdl_source\subtitle_overlay.v` ✓、`subtitle_frame_commit.v` ✓、`osd_overlay_24.v` ✓、`status_osd_overlay.v` ✓ |
| 按键行为（KEY1/KEY2） | `hdl_source\key_remove_shakes.v` ✓ + `SD\sd_card_bmp.v` 内长按/短按/自动轮播逻辑 ✓ |
| 数码管译码 | `SD\seg_scan.v` ✓、`SD\seg_decoder.v` ✓ |
| SDRAM 读通道 | `hdl_source\media_frame_reader.v` ✓、`media_sdram_write_cdc.v` ✓ |
| HDMI 核/PHY | `hdl_source\hdmi1.4b_transmitter_core\*.enc.v` ✓、`hdmi_phy_warpper.v` ✓、`lane_lvds_10_1.v` ✓ |
| 音频提示音 | `hdl_source\hdmi_audio_tone_i2s_64fs.v` ✓、`I2S_receiver.v` ✓、`audio_arc_calculate.v` ✓ |

---

## 六、修改代码时的注意事项

见 [`打开说明.md`](打开说明.md) 第三节（五条坑）✓，要点：
1. 改完**必须过综合门禁**（建议全新目录跑 `.tcl`）✓，并**比对寄存器数变化方向** ✓；
2. **比特流时间戳必须变新** ✓；
3. **不要改 `top_tf_hdmi_audio.v` 里 `sd_card_bmp` 的 `CLK_FREQ_HZ (100_000_000)`** ✓（会改变 SD 卡时钟分频，改小反而翻倍 → 黑屏 ✗）；
4. **黑屏先看数码管第 5 位（`seg_data_4`）**：`F` 正常 / `0` 装载失败 ✓；
5. **一次只改一个变量** ✓。

---

## 七、上传到 GitHub

本目录已初始化为 git 仓库（首次提交已完成 ✓）。上传步骤：

```bash
cd <本目录>
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git branch -M main
git push -u origin main
```

或在 GitHub 网页端直接**拖拽本目录**（"Add file → Upload files"）上传 ✓。

### 上传前请注意两点

1. **`.al` 里写有绝对路径** ✗ —— `src\td_project\HDMI1.4b_Transmitter_v1.0.al` 第 2 行为
   `Path="C:/Users/30685/Desktop/HDMI2/src/td_project"` ✓。
   别人克隆后若目录位置不同，TD 打开时可能需要**重新指定工程路径/重新添加源文件** ✓（`.prj` 里的源文件是相对路径 ✓，只要保持 `src\` 内部层级即可 ✓）。若希望彻底可移植，可把该行改成克隆后的实际路径 ✓。
2. **不要上传参考讲义素材** ✓（`参考文件\`：厂商课件与示例 ✗）与**测试音频大文件** ✗；本备份已**不含**这些 ✓✓。
3. 厂商加密 IP（`*.enc.v`，如 HDMI 核与 SDRAM 控制器 ✗）是否允许公开，请按你手上的授权自行判断 ✓。

`.gitignore` 已包含 TD 生成物（`*.db` / `*.fs` / `*.qor` / `*.rpt` / `*.log` / `log\` / `*.dmp` 等 ✓），因此**在仓库里直接跑 TD 也不会把中间产物提交进去** ✓。

