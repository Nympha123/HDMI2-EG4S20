
# ============================================================
# merged_top_tf_hdmi_audio.sdc
# 用于：TF 图片轮播 + HDMI(视频+音频) 整合工程
#
# 合并原则：
# 1) 保留 top.sdc 里的系统主时钟与 derive_clocks
# 2) 把 timing(2).sdc 里的 pixel/serial 时钟改成整合工程实际名字
# 3) 增加 hdmi_5x_clk / audio_mclk 的命名
# 4) 不再对内部 net 直接 create_clock，避免和 derive_clocks 重复
# ============================================================

# ------------------------------------------------------------
# 1. 板级输入主时钟
#    你的原 top.sdc 里 clk=50MHz，所以这里仍然用 20ns
# ------------------------------------------------------------
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]

# ------------------------------------------------------------
# 2. 自动推导 PLL 输出时钟
# ------------------------------------------------------------
derive_clocks

# ------------------------------------------------------------
# 3. 给关键 PLL 输出命名
#    下面这些路径是按你当前工程实例名写的：
#      sys_pll      -> sys_pll_m0
#      video_pll    -> video_pll_m0
#      音频 PLL     -> u_audio_pll
#
#    如果综合后实例路径略有不同，就按 Timing Analyzer 里的实际 pin 路径改。
# ------------------------------------------------------------
rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {video_clk}   -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {audio_mclk}  -source [get_ports {clk}] -master_clock {clk} [get_pins {u_audio_pll/pll_inst.clkc[2]}]
# 第六讲 2.6.5 第5条：SDRAM 移位时钟（ext_mem_clk 相移 180°，即 clkc[2]）也要命名，
# 否则第5条的 false_path 引用不到该时钟而静默失效。
rename_clock -name {ext_mem_clk_sft} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[2]}]

# ------------------------------------------------------------
# 4. 从原 timing(2).sdc 迁移过来的 HDMI 像素/串行时钟约束
#
#    原文件是：
#      create_clock -name pixel_clk  ... [get_nets {S_pixel_clk}]
#      create_clock -name serial_clk ... [get_nets {S_serial_clk}]
#      set_clock_groups -exclusive ...
#
#    在整合工程里，这两个时钟已经由 video_pll 产生，并通过 derive_clocks 建出来了，
#    所以这里只保留“组关系”，不再重复 create_clock。
#
#    这里沿用原作者的写法，把 video_clk 和 hdmi_5x_clk 设成 exclusive。
#    如果后面 Timing Analyzer 明确显示两者之间需要做同步时序分析，再把这一条去掉。
# ------------------------------------------------------------
set_clock_groups -exclusive \
    -group [get_clocks {video_clk}] \
    -group [get_clocks {hdmi_5x_clk}]

# ------------------------------------------------------------
# 5. 音频 I2S 发生器/接收器跨域
#
#    audio_mclk 域里生成 I2S，video_clk 域里做三拍同步采样。
#    这类路径不是普通同步时序路径，直接切掉更合理。
# ------------------------------------------------------------
set_clock_groups -asynchronous \
    -group [get_clocks {audio_mclk}] \
    -group [get_clocks {video_clk} hdmi_5x_clk sd_card_clk ext_mem_clk]

# ------------------------------------------------------------
# 6. sd_card_clk / ext_mem_clk / video_clk / hdmi_5x_clk 互异步
#
#    启用依据（2026-10-07 逐条核对源码后打开，原文是作者预留的注释）：
#      - frame_read_write/frame_fifo_read.v：read_req 经 read_req_d0/d1/d2 三级
#        同步进 mem_clk，read_len/read_addr_index 各两级；源码注释即写明
#        "synchronize to 'mem_clk' clock domain"。
#      - frame_read_write/frame_fifo_write.v：write_req 同样三级同步。
#      - 像素数据通路走真双时钟异步 FIFO，其时序约束由 IpSDCList 传入的
#        afifo_16_32_256.tcl / afifo_32_16_256.tcl 提供。
#      - 跨域显示控制 disp_buf_idx 在 frame_read_write 内部经 read_addr_index_d0/d1
#        同步；display_valid 由本工程在顶层用 sync_2ff 同步进 video_clk。
#    不打开时，video_clk -> ext_mem_clk 这类 0ns 预算的握手路径会被当成同步路径
#    分析，产生 -1.5ns 量级的"伪 hold 违例"，并导致 TD 的 Hold Fix 阶段直接放弃
#    （日志：Too much hold violation, please check the src code）。
# ------------------------------------------------------------
set_clock_groups -asynchronous \
    -group [get_clocks {sd_card_clk}] \
    -group [get_clocks {ext_mem_clk}] \
    -group [get_clocks {video_clk}] \
    -group [get_clocks {hdmi_5x_clk}]

# ------------------------------------------------------------
# 7. 其余 Input/Output delay 先保持空白
#    你当前两个原始 sdc 也都没有写这部分。
# ------------------------------------------------------------

# ------------------------------------------------------------
# Lesson 6 reliability constraints
# ------------------------------------------------------------
# External reset is asynchronous by design; reset_sync handles release.
set_false_path -from [get_ports {rst_n}]

# Do not time the first stage of the reset synchronizers.
set_false_path -to [get_regs -hier {*/s1}]

# Bound the HDMI output datapath to the serial clock period.
set_max_delay -from [get_clocks {hdmi_5x_clk}] \
    -to [get_ports {HDMI_CLK_P HDMI_D0_P HDMI_D1_P HDMI_D2_P}] \
    8.000 -datapath_only

# Keep a small, explicit hold uncertainty for the named user clocks.
set_clock_uncertainty -hold 0.050 \
    [get_clocks {clk sd_card_clk ext_mem_clk video_clk hdmi_5x_clk audio_mclk}]

# 第六讲 2.6.5 第5条：SDRAM 移位时钟路径设为 false_path（硬 IP 的 I/O 窗口，
# ext_mem_clk 与它的 180° 相移时钟之间不做普通时序分析）。
set_false_path -from [get_clocks {ext_mem_clk}] -to [get_clocks {ext_mem_clk_sft}]
set_false_path -from [get_clocks {ext_mem_clk_sft}] -to [get_clocks {ext_mem_clk}]

# 第六讲 A2（三路 PLL 锁定参与复位）：ext_rst_n 现在由 rst_n 与三路 PLL 锁定
# 经 pll_ready 锁存产生，是整个芯片的异步复位网络。它到各域 reset_sync 的路径
# 不应做恢复/移除时序分析（与上面 rst_n 的处理同类）。
set_false_path -from [get_regs -hier {pll_ready}]

# ===== Lesson-8: 7-seg diagnostics =====
# Display-only status sampling across clock domains; no functional timing requirement.
set_false_path -to [get_pins {ctrl_active_index_seg_reg*/D}]
set_false_path -to [get_pins {reader_index_seg_reg*/D}]
set_false_path -to [get_pins {reader_error_seg_reg*/D}]
set_false_path -to [get_pins {loader_image_complete_seg_reg*/D}]
