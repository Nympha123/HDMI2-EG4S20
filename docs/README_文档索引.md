# docs 文档索引（2026-10-27 整理）

> 目录里文件较多，先看这一页。**两份 docx 是历史调试记录，请勿删除。**

## 1 先看这几份

| 文档 | 内容 |
|---|---|
| `v79_本轮改造总览_20261027.md` | **本轮（v79→v79d）全部改动的汇总**：问题根因、资源演进、经验教训、构建/固化/回退 |
| `交接说明_HANDOFF.md` | 上一轮交接（工程环境、铁律、历史状态），部分内容已被 v79 取代 |
| `使用说明_USAGE.md` | 按键/界面/设置项的操作说明 |
| `代码说明.md` | 工程结构与模块职责 |
| `修改记录.txt` | 从 v1 到 v78 的逐版本详细记录（19 万字节，最全的历史） |

## 2 重要历史记录（docx，勿删）

| 文档 | 内容 |
|---|---|
| `HDMI2_EG4S20_调试与问题解决参考文档_20261027.docx` | **v67 定版调试全记录**：白边/左边缘竖线的 8 轮尝试、音频“滋滋”的 v57–v64 专项实验、CMD18 失败复盘、资源与 seed 经验 |
| `HDMI2_EG4S20_v69-v78_改版与问题排查总结_20261027.docx` | **v69–v78 改版总结**：系统简介四页、重影根因、切图延迟、任意分辨率四次翻车、音频“滋滋”证据链、12 条踩坑清单 |

这两份 docx 里的结论（尤其是“滋滋”已排除 SD/WAV 数据链、白边只能靠改 DE/OSD 时序根治）
是本轮判断的基础，**不要删**。

## 3 本轮（v79 – v79d）逐版记录

| 文档 | 版本 | 关键内容 |
|---|---|---|
| `v79_稳定性修复与资源分析.md` | v79 | 三个现场问题（返回键 / 回主界面音乐卡死 / 换区停在老图）的根因与修复；SD 读令牌超时、坏扇区上报、SD 子系统自恢复；资源分析 |
| `v79b_界面微调_白边对称与展区简介.md` | v79b | 左右对称白色装饰线、目录页三行展区简介、ext 字库 64→128 槽并与字幕共用 |
| `v79c_白线加粗_展区错字_图像错位.md` | v79c | 白线 2→4 px、`zone_str9` 字形码错位（“展墓”）、读 FIFO 异步清零过窄导致的整帧错位 |
| `v79d_音频回退v60_缓冲搬BRAM.md` | v79d | 音频回退 v60（1024 缓冲 + 满扇区起播）、音频缓冲改标准双端口 RAM 后被推断成 BRAM（省 546 LUT）、`ST_PADTOP` 死代码裁剪 |
| `清理记录_20261027.md` | — | 本次目录整理删了什么、为什么删、保留了什么 |

## 4 更早的逐版本专题

| 文档 | 内容 |
|---|---|
| `v44_系统信息页.md` / `v45_字幕底栏修正.md` / `v46_CMD18缓存.md` / `v47_25MHz_SPI.md` | 系统页入口、字幕与底栏等高、CMD18 失败复盘、SPI 提速 |
| `v54_左边缘修复.md` | 左边缘黑/白线的根因（`video_delay` 消隐清零）与 v54 修法 |
| `v65_系统信息两页.md` / `v66_系统信息滚动页.md` / `v67_系统信息中文滚动页.md` / `v69_系统简介四页.md` | 系统信息页的四次改版 |
| `字幕与字库说明.md` | 字库槽位、9 bit 码、行倒序存储、渲染器约定 |
| `系统简介.txt` | 系统简介四页的文案原文 |
| `设计参考例程文档.md` | 安路官方 APUG092 例程的结构说明 |
| `compare-current-vs-reference.md` | 当前工程与参考例程的差异对照 |
| `README_修改前.md` | 本轮开始前的 README 快照 |

## 5 备份与素材

| 路径 | 内容 |
|---|---|
| `_backup/baseline_v14/`、`_backup/final_wav_first_20261025/` | 历史构建的 area/qor/flow.status（资源与时序对比用） |
| `_backup/v44_*`、`v45_*`、`v46_*`、`v47_*`、`v48_*`、`v69_*` | 各次改动前的 RTL 快照 |
| `_backup/v79_before_20261027/`、`_backup/v79_after_20261027/` | 本轮改动的 RTL 前后快照（10 个文件） |
| `_backup/top_tf_hdmi_audio.v.before_wav_only_20261025` | 音频只保留 WAV 之前的顶层快照 |
| `../bitstream/MANIFEST.txt` | 每个交付 bit 的 MD5 / 资源 / 时序 / 说明 |
| `../SD卡上用于测试的内容/` | TF 卡素材（A/B/C/D 展区图、5 首 WAV、缩放测试图） |

## 6 工具脚本（`tools/`，本轮新增的用 ★ 标）

| 脚本 | 作用 |
|---|---|
| ★ `make_subtitle_font.py` | 生成 ext 字库 hex + 字幕/目录参数表 + 字表 + 预览；含“展/区”码值校验 |
| ★ `preview_directory_v79.py` | 把目录页左下角的坐标/文案/字模重放成 PNG，离线检查版式 |
| ★ `check_zone_str.py` | 解码 `subtitle_overlay.v` 里的 `zone_str9`，核对字形码 |
| `make_font_rom.py` / `add_sysinfo_glyphs.py` / `add_intro_title_glyphs.py` | 主字库/系统页字库生成与加字 |
| `make_sysintro_page.py` / `check_sysintro_render.py` | 系统简介版面生成与逐像素自检 |
| `make_zone_badges.py` / `check_zone_badge_render.py` | 展区徽标 ROM 生成与自检 |
| `make_a_zone_pages.py` / `make_page5_6.py` / `make_scale_test_bmps.py` / `make_zone_test_bmps.py` | 各类测试页面图生成 |
| `preview_*.py` | 菜单/底栏/系统信息/转场的离线预览 |
| `read_fat32_root.py` / `read_volume.py` | 直接读 TF 卡根目录/卷信息，排查装载问题 |
| `gen_al.py` / `gen_prj.py` / `update_manifest.py` | 工程清单与 MANIFEST 生成 |

## 7 构建与固化（命令速查）

```bat
cd project\HDMI1.4b_Transmitter_v1.0_Runs\syn_1
E:\AnLu_Install\bin\td_commands_prompt.exe dsh_run.tcl
cd ..\phy_1
E:\AnLu_Install\bin\td_commands_prompt.exe dsh_run.tcl
cd ..\..
E:\AnLu_Install\bin\bw_commands_prompt.exe "project/dsh_flash.tcl"
```

- 布局种子：`phy_1/HDMI1.4b_Transmitter_v1.0.tcl` 里 `set_param place seed 5`
  （seed 3 也可用；**seed 4 会出负 slack**，见 v79 文档）；
- 固化：`project/dsh_flash.tcl` 当前指向 `bitstream/HDMI2_HDMI14_Player_v79d.bit`；
- 回退：把 `dsh_flash.tcl` 里的文件名换成 `v79c` / `v79b` / `v79` / `v71` 再执行。
