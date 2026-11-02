
module top(
    input                       clk,
    input                       rst_n,
    input                       key1,           // 手动下一张
    input                       key2,           // 自动播放 开/关
    input                       enc_s1,         // EC11 A
    input                       enc_s2,         // EC11 B
    input                       enc_key,        // EC11 按键，低有效
    output wire                 kp_row,         // 6键公共线, 恒定低电平(=公共地)
    input  wire [5:0]           kp_col,         // 6根感应线(内部上拉,按下为0)

    output [5:0]                seg_sel,
    output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 24'd307200;   // 640*480
parameter BUF0_ADDR     = 24'd0;
parameter BUF1_ADDR     = FRAME_PIXELS;
// 4 槽位：展区 4 张图常驻 SDRAM，切图直接换地址，不再读卡
parameter BUF2_ADDR     = FRAME_PIXELS * 2;
parameter BUF3_ADDR     = FRAME_PIXELS * 3;

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
wire        display_valid;
wire [1:0]  zone_apply_sel;      // 目录 Enter 时选中的展区（video_clk 域）
wire        zone_apply;          // 目录 Enter 的 1 拍脉冲（video_clk 域）
wire        zone_preview;        // 目录上下移动的预览脉冲（已不再用来装图）
wire        zone_apply_sd;       // 上面那个脉冲在 sd_card_clk 域的单拍版本
wire        auto_toggle_sd;
wire [1:0]  player_img_idx;
wire [2:0]  player_img_count;
wire        player_auto;


wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 音频发射相关
// 2026-10-25: 内部 I2S 测试音 / I2S 接收链路已删除（见下方"音频源只认 WAV"一节），
// audio_mclk 只剩"让音频 PLL 有输出、进而保证 audio_pll_lock 有效"的作用，
// 而 audio_pll_lock 参与 rst_all —— 所以 PLL 和这根线都要保留，不要当成没用删掉。
wire        audio_pll_lock;
wire        audio_mclk;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

// WAV file reader / streamer
wire        wav_find_req;
wire [31:0] wav_find_lba;
wire        wav_find_busy;
wire        wav_find_found;
wire [7:0]  wav_find_err;
wire [31:0] wav_first_cluster;
wire [31:0] wav_file_size;
wire [31:0] wav_data_start;
wire [7:0]  wav_spc;
wire        wav_play_req;
wire [31:0] wav_play_lba;
wire        wav_sector_busy;
wire        wav_sector_valid;
wire [7:0]  wav_sector_byte;
wire [8:0]  wav_sector_byte_index;
wire        wav_sector_done;
wire [7:0]  wav_sector_error;
wire        img_sd_busy;
wire        img_load_active;   // = ~bmp_ready：图片正在扫描/装载
wire        boot_ok;           // SD 就绪 + 分区/扫描元数据就绪（音频起播门槛）
wire        wav_sector_req;
wire [31:0] wav_sector_lba;
wire signed [15:0] wav_sample_out;
wire        wav_sample_valid;
wire        wav_stream_active;
wire        wav_stream_end;
wire        wav_buffer_low;
wire        wav_active_vid;
reg         wav_tick;
wire [23:0] audio_left_src;
wire [23:0] audio_right_src;
wire        audio_valid_src;
// 图像链路状态码（来自 sd_card_bmp，驱动数码管静态显示；见 DBG_SEG_ON）
wire [3:0]  dbg_state;
// v31：当前显示图的抽取比（1/2/3），给底栏把 "n / m" 显示成 "1 / N"
wire [1:0]  disp_scale;
// v44：主菜单第三项「系统简介」选中脉冲（打开只读信息层，不离开主菜单）
wire        menu_open_sysinfo;
reg         sys_active;              // 「系统简介」层打开（只在主菜单上有效）
reg  [1:0]  sys_page;                // v69：当前页 0..3（A/D 左右翻页）

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// 统一复位：TF 图像链路 + HDMI 音频链路
wire rst_all;
assign rst_all = ~rst_n | ~audio_pll_lock;
wire sdcard_rst_n = ~rst_all;   // 官方顶层原本没有这个网名；键盘扫描必须用有效复位

// ---------------------------------------------------------------------------
// v79：SD 子系统"卡死自恢复"
//
//   现场故障（音乐永久静音 + 进任何展区都停在上一张图、只有 UI 还在动）最可能的
//   物理原因是 SD 有一条事务没有收尾：sd_card_cmd 的 S_READ_WAIT 在等数据令牌
//   0xFE 时没有超时，卡一旦漏应答（排线/杜邦线接触不良、热插拔、上电不稳），
//   就永久卡在该状态，sd_sector_adapter 的 busy 一直是 1，于是图片装载和 WAV
//   播放都再也拿不到扇区 —— 看起来就是"回到主界面音乐卡死、进别的展区还是老图"。
//
//   这里在顶层做一个兜底：总线连续 336 ms 都没有收尾（正常一个扇区 ≤ 250 us），
//   就把整个 SD 子系统（SD 核 + 图片装载 + 分区表 + WAV 查找/播放）复位重来一遍，
//   等于自动"重新插一次卡"，不需要断电。复位由 sd_clk 同步产生、同步释放。
// ---------------------------------------------------------------------------
reg  [24:0] sd_stall_cnt;
reg  [3:0]  sd_rst_hold;
wire        sd_stall_ev = (sd_stall_cnt == 25'd16_777_215);   // 336 ms @ 50 MHz
always @(posedge sd_card_clk or negedge sdcard_rst_n) begin
    if (!sdcard_rst_n) begin
        sd_stall_cnt <= 25'd0;
        sd_rst_hold  <= 4'd0;
    end else begin
        if (sd_stall_ev)
            sd_rst_hold <= 4'hF;
        else if (sd_rst_hold != 4'd0)
            sd_rst_hold <= sd_rst_hold - 4'd1;

        if (sd_stall_ev || !wav_sector_busy)
            sd_stall_cnt <= 25'd0;
        else
            sd_stall_cnt <= sd_stall_cnt + 25'd1;
    end
end
wire sd_soft_rst = sd_stall_ev | (sd_rst_hold != 4'd0);
wire sd_rst_n    = sdcard_rst_n & ~sd_soft_rst;
wire sd_rst_all  = rst_all | sd_soft_rst;
wire wav_player_idle;

// ---------------------------------------------------------------------------
// 目录 Enter 请求跨时钟域：video_clk(25 MHz) 的 1 拍脉冲 -> toggle
//   -> sd_card_clk(50 MHz) 两拍同步后取异或成单拍脉冲。
// 直接把 25 MHz 的窄脉冲接到 sd 域会被采样 0/1/2 次，运气不好一次都收不到
// （板测表现：进任何展区都还停在开机那张图）。
// ---------------------------------------------------------------------------
reg apply_tgl;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all)
        apply_tgl <= 1'b0;
    else if (zone_apply)
        apply_tgl <= ~apply_tgl;
end
reg ap_s1, ap_s2, ap_s3;
always @(posedge sd_card_clk or negedge sdcard_rst_n) begin
    if (!sdcard_rst_n) begin
        ap_s1 <= 1'b0;
        ap_s2 <= 1'b0;
        ap_s3 <= 1'b0;
    end else begin
        ap_s1 <= apply_tgl;
        ap_s2 <= ap_s1;
        ap_s3 <= ap_s2;
    end
end
assign zone_apply_sd = ap_s2 ^ ap_s3;

// 保持你原来的 TF / SDRAM / video 时钟
sys_pll sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .reset      (1'b0)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .reset      (1'b0)
);

// 复用你 I2S->HDMI 工程里的 PLL，只取 12.288MHz 音频主时钟
PLL_HDMI_AUDIO u_audio_pll(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (audio_pll_lock),
    .clk0_out   (),
    .clk1_out   (),
    .clk2_out   (audio_mclk)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// ===================== TF 多图扫描与缓存（双缓冲） =====================
sd_card_bmp #(
    .CLK_FREQ_HZ       (50_000_000),
    .SCAN_START_SECTOR (32'd0),
    .SCAN_MAX_SECTOR   (32'd131071),
    .SCAN_TARGET_COUNT (3'd4)
) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (sd_rst_all),
    .key_next          (key1),
    .key_auto          (key2),
    .auto_toggle       (auto_toggle_sd),
    .auto_step         (auto_step),
    .main_next_toggle  (main_next_tgl),
    .main_prev_toggle  (main_prev_tgl),
    .state_code        (),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),
    .display_valid     (display_valid),
    .img_index_out     (player_img_idx),
    .img_count_out     (player_img_count),
    .auto_play_out     (player_auto),
    .wav_sector_req    (wav_sector_req),
    .wav_sector_lba    (wav_sector_lba),
    .wav_sector_busy   (wav_sector_busy),
    .wav_sector_valid  (wav_sector_valid),
    .wav_sector_byte   (wav_sector_byte),
    .wav_sector_byte_index (wav_sector_byte_index),
    .wav_sector_done   (wav_sector_done),
    .wav_sector_error  (wav_sector_error),
    .img_sd_busy       (img_sd_busy),
    .img_load_active   (img_load_active),
    .boot_ok           (boot_ok),
    .zone0_count       (),
    .zone1_count       (),
    .zone2_count       (),
    .zone3_count       (),
    .zone_apply        (zone_apply_sd),
    .zone_preview      (1'b0),
    .zone_sel          (zone_sel),
    .zone_mode_out     (zone_mode),
    .zone_idx_out      (zone_idx),
    .zone_count_out    (zone_count),
    .disp_scale        (disp_scale),
    .dbg_state         (dbg_state),

    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),

    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso)
);

// 数码管：静态显示一个十六进制"图像链路状态码"（六位同时显示同一个字符）。
// seg_sel 低有效，全 0 = 六位全亮；seg_data 低有效，MSB 是小数点。
// 这个码是 2026-10-25 加的现场诊断手段：板上没有逻辑分析仪，进分区不换图时
// 一眼就能分清是"分区表空"、"请求丢了"、"装载卡死"还是"已经装好了"。
// 0=分区装载完成(健康) 1=正在装载 2=请求挂着没开始 3=还没收到请求
// 4=该分区图片表为空 5=装载超过 8 s 没完成 6=收到请求但没进分区也没装载 8=SD 未初始化
localparam DBG_SEG_ON = 1'b0;   // v31：定版关掉数码管调试码（省 ~40 LUT，评委看不到调试字符）
reg [6:0] dbg_seg7;
always @(*) begin
    case (dbg_state)
        4'h0:    dbg_seg7 = 7'b100_0000;   // 0
        4'h1:    dbg_seg7 = 7'b111_1001;   // 1
        4'h2:    dbg_seg7 = 7'b010_0100;   // 2
        4'h3:    dbg_seg7 = 7'b011_0000;   // 3
        4'h4:    dbg_seg7 = 7'b001_1001;   // 4
        4'h5:    dbg_seg7 = 7'b001_0010;   // 5
        4'h6:    dbg_seg7 = 7'b000_0010;   // 6
        4'h8:    dbg_seg7 = 7'b000_0000;   // 8
        default: dbg_seg7 = 7'b111_1111;   // 全灭
    endcase
end
assign seg_sel  = 6'b000000;
assign seg_data = DBG_SEG_ON ? {1'b1, dbg_seg7} : 8'hFF;

// ===================== 原图像时序与帧缓存 =====================
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

// ===================== 设置面板 OSD（阶段 2 第一步） =====================
// 图片界面旋转编码器不再直调亮度/对比度；长按 0.8 s 呼出设置面板。
reg  [11:0] osd_x, osd_y;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        osd_x <= 12'd0;
        osd_y <= 12'd0;
    end else begin
        // hs/vs 在本工程中是低有效：同步期为低，有效视频为高。
        if (!vs)
            osd_y <= 12'd0;
        else if (de && (osd_x == 12'd639))
            osd_y <= osd_y + 12'd1;
        if (!hs)
            osd_x <= 12'd0;
        else if (de)
            osd_x <= osd_x + 12'd1;
    end
end

wire [4:0] enc_level;
wire       enc_key_pulse;
rotary_brightness #(
    .CLK_FREQ_HZ     (25_000_000),
    .SAMPLE_US       (250),
    .CONFIRM         (3),
    .KEY_DEBOUNCE_MS (20),
    .KEY_BLANK_MS    (60),
    .RESET_ON_KEY    (1'b0),
    .LEVEL_INIT      (5'd12),
    .LEVEL_MAX       (5'd16)
) u_enc (
    .clk       (video_clk),
    .rst_n     (~rst_all),
    .enc_a     (enc_s1),
    .enc_b     (enc_s2),
    .enc_key   (enc_key),
    .level     (enc_level),
    .key_pulse (enc_key_pulse)
);

// ===== 矩阵键盘：W/A/S/D/Q/Enter =====
// 实测索引：0=W 1=A 2=D 3=S 4=Enter 8=Q
wire [15:0] kp_state;
wire        kp_event, kp_ev_press;
wire [7:0]  kp_code;
matrix_keyboard_scan #(
    .CLK_HZ (50_000_000)
) u_matrix_keyboard (
    .clk         (sd_card_clk),
    .rst_n       (sdcard_rst_n),
    .key_row     (kp_row),
    .key_col     (kp_col),
    .key_event   (kp_event),
    .key_code    (kp_code),
    .key_pressed (kp_ev_press),
    .key_state   (kp_state)
);

reg [15:0] kp_state_d;
reg [21:0] kp_hold_cnt;
reg [2:0]  kp_hold_key;
reg        kp_hold_run;
always @(posedge sd_card_clk or negedge sdcard_rst_n) begin
    if (!sdcard_rst_n) begin
        kp_state_d  <= 16'd0;
        kp_hold_cnt <= 22'd0;
        kp_hold_key <= 3'd0;
        kp_hold_run <= 1'b0;
    end else begin
        kp_state_d <= kp_state;
        if      (kp_state[0] && !kp_state_d[0]) begin kp_hold_key <= 3'd1; kp_hold_run <= 1'b1; kp_hold_cnt <= 22'd4_000_000; end
        else if (kp_state[3] && !kp_state_d[3]) begin kp_hold_key <= 3'd2; kp_hold_run <= 1'b1; kp_hold_cnt <= 22'd4_000_000; end
        else if (kp_state[8] && !kp_state_d[8]) begin kp_hold_key <= 3'd3; kp_hold_run <= 1'b1; kp_hold_cnt <= 22'd4_000_000; end
        else if (kp_state[4] && !kp_state_d[4]) begin kp_hold_key <= 3'd4; kp_hold_run <= 1'b1; kp_hold_cnt <= 22'd4_000_000; end
        else if (kp_state[1] && !kp_state_d[1]) begin kp_hold_key <= 3'd5; kp_hold_run <= 1'b1; kp_hold_cnt <= 22'd4_000_000; end
        else if (kp_state[2] && !kp_state_d[2]) begin kp_hold_key <= 3'd6; kp_hold_run <= 1'b1; kp_hold_cnt <= 22'd4_000_000; end
        if (kp_hold_run) begin
            if (kp_hold_cnt == 22'd0) kp_hold_run <= 1'b0;
            else                      kp_hold_cnt <= kp_hold_cnt - 22'd1;
        end
    end
end
wire kp_up    = kp_hold_run && (kp_hold_key == 3'd1);
wire kp_down  = kp_hold_run && (kp_hold_key == 3'd2);
wire kp_back  = kp_hold_run && (kp_hold_key == 3'd3);
wire kp_enter = kp_hold_run && (kp_hold_key == 3'd4);
wire kp_dec   = kp_hold_run && (kp_hold_key == 3'd5);
wire kp_inc   = kp_hold_run && (kp_hold_key == 3'd6);

menu_ctrl u_menu_ctrl (
    .clk          (video_clk),
    .rst          (rst_all),
    .key_up       (kp_up),
    .key_down     (kp_down),
    .key_ok       (kp_enter),
    .key_back     (kp_back),
    .settings_on  (settings_active),
    .sys_on       (sys_active),
    .menu_active  (menu_active),
    .dir_active   (dir_active),
    .open_settings(menu_open_settings),
    .open_sysinfo (menu_open_sysinfo),
    .zone_apply   (zone_apply),
    .zone_preview (zone_preview),
    .zone_sel     (zone_sel),
    .sel          (menu_sel),
    .dir_sel      (dir_sel)
);

// 同步到 video_clk 并做上升沿检测
reg kup1,kup2,kdn1,kdn2,kbk1,kbk2,ken1,ken2,kdc1,kdc2,kic1,kic2;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        kup1<=0; kup2<=0; kdn1<=0; kdn2<=0; kbk1<=0; kbk2<=0;
        ken1<=0; ken2<=0; kdc1<=0; kdc2<=0; kic1<=0; kic2<=0;
    end else begin
        kup1<=kp_up; kup2<=kup1;
        kdn1<=kp_down; kdn2<=kdn1;
        kbk1<=kp_back; kbk2<=kbk1;
        ken1<=kp_enter; ken2<=ken1;
        kdc1<=kp_dec; kdc2<=kdc1;
        kic1<=kp_inc; kic2<=kic1;
    end
end
wire kp_up_ev    = kup1 & ~kup2;
wire kp_down_ev  = kdn1 & ~kdn2;
wire kp_back_ev  = kbk1 & ~kbk2;
wire kp_enter_ev = ken1 & ~ken2;
wire kp_dec_ev   = kdc1 & ~kdc2;
wire kp_inc_ev   = kic1 & ~kic2;

// 主界面 A/D：手动上一张 / 下一张（设置页内仍用于调参数）
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        main_next_tgl <= 1'b0;
        main_prev_tgl <= 1'b0;
    end else if (!settings_active && !time_edit && !menu_active && !dir_active) begin
        if (kp_inc_ev) main_next_tgl <= ~main_next_tgl;
        if (kp_dec_ev) main_prev_tgl <= ~main_prev_tgl;
    end
end

// 自动轮播切换请求同步到 sd_card_clk
reg auto_tog_tgl;
reg auto_tog_s1, auto_tog_s2;
always @(posedge sd_card_clk or negedge sdcard_rst_n) begin
    if (!sdcard_rst_n) begin
        auto_tog_s1 <= 1'b0;
        auto_tog_s2 <= 1'b0;
    end else begin
        auto_tog_s1 <= auto_tog_tgl;
        auto_tog_s2 <= auto_tog_s1;
    end
end
assign auto_toggle_sd = auto_tog_s2 ^ auto_tog_s1;

// v44：主菜单第三项「系统」只打开只读信息层，不再启动/切换轮播。
// 轮播只由设置页第 5 行的 Enter 控制（避免"点系统却开始放幻灯片"）。

reg        settings_active;
reg        main_next_tgl;
reg        main_prev_tgl;
wire       menu_active;
wire       dir_active;
wire [2:0] menu_sel;
wire [2:0] dir_sel;
wire       menu_open_settings;
wire [1:0] zone_sel;
wire       zone_mode;
wire [3:0] zone_idx;
wire [4:0] zone_count;

// （zone_apply / zone_preview / zone_apply_sd 的声明在文件顶部，跨域逻辑在 PLL 之后）
reg [2:0]  settings_row;
reg        time_edit;
reg [1:0]  time_field;
reg [7:0]  edit_hh, edit_mm, edit_ss;
reg        time_load;
reg        audio_on;
reg [1:0]  vol_step;
reg        wave_on;
reg [1:0]  wave_step;
reg [1:0]  auto_step;
reg [7:0]  set_bright;
reg [7:0]  set_contrast;
reg [4:0]  enc_level_d;
reg        enc_key_s1, enc_key_s2;
reg        enc_key_stable;
reg [19:0] enc_db_cnt;
reg [24:0] enc_lp_cnt;
reg        enc_lp_mark;

function [7:0] bcd_inc;
    input [7:0] v;
    input [7:0] vmax;
    begin
        if (v >= vmax)
            bcd_inc = 8'h00;
        else if (v[3:0] == 4'd9)
            bcd_inc = {v[7:4] + 4'd1, 4'd0};
        else
            bcd_inc = {v[7:4], v[3:0] + 4'd1};
    end
endfunction

function [7:0] bcd_dec;
    input [7:0] v;
    input [7:0] vmax;
    begin
        if (v == 8'h00)
            bcd_dec = vmax;
        else if (v[3:0] == 4'd0)
            bcd_dec = {v[7:4] - 4'd1, 4'd9};
        else
            bcd_dec = {v[7:4], v[3:0] - 4'd1};
    end
endfunction

always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        settings_active  <= 1'b0;
        settings_row    <= 3'd0;
        time_edit       <= 1'b0;
        time_field      <= 2'd0;
        edit_hh         <= 8'd0;
        edit_mm         <= 8'd0;
        edit_ss         <= 8'd0;
        time_load       <= 1'b0;
        audio_on        <= 1'b1;
        vol_step        <= 2'd3;
        wave_on         <= 1'b0;
        wave_step       <= 2'd2;
        auto_step       <= 2'd1;
        auto_tog_tgl    <= 1'b0;
        set_bright       <= 8'd255;
        set_contrast     <= 8'd128;
        enc_level_d      <= 5'd12;
        enc_key_s1       <= 1'b1;
        enc_key_s2       <= 1'b1;
        enc_key_stable   <= 1'b1;
        enc_db_cnt       <= 20'd0;
        enc_lp_cnt       <= 25'd0;
        enc_lp_mark      <= 1'b0;
    end else begin
        enc_key_s1 <= enc_key;
        enc_key_s2 <= enc_key_s1;
        enc_level_d <= enc_level;
        time_load <= 1'b0;

        // 20 ms 稳定滤波，避免长按期间按键抖动反复重置/重触发
        if (enc_key_s2 == enc_key_stable) begin
            enc_db_cnt <= 20'd0;
        end else if (enc_db_cnt >= 20'd499_999) begin
            enc_key_stable <= enc_key_s2;
            enc_db_cnt     <= 20'd0;
        end else begin
            enc_db_cnt <= enc_db_cnt + 20'd1;
        end

        // 长按 0.8 s：开关设置面板；短按：切亮度/对比度行
        if (!enc_key_stable) begin
            if (enc_lp_cnt < 25'd20_000_000)
                enc_lp_cnt <= enc_lp_cnt + 25'd1;
            else if (!enc_lp_mark) begin
                enc_lp_mark     <= 1'b1;
                if (!menu_active && !dir_active) begin
                    settings_active <= ~settings_active;
                    settings_row    <= 3'd0;
                    time_edit       <= 1'b0;
                end
            end
        end else begin
            enc_lp_cnt  <= 25'd0;
            enc_lp_mark <= 1'b0;
        end

        if (settings_active && !time_edit && enc_key_pulse && !enc_lp_mark)
            settings_row <= (settings_row == 3'd5) ? 3'd0 : (settings_row + 3'd1);

        // 矩阵键盘：W/S 选行，A/D 调值，Q 退出，Enter 打开/进入时间编辑
        if (menu_open_settings || (!settings_active && !menu_active && !dir_active && !zone_apply && kp_enter_ev)) begin
            settings_active <= 1'b1;
            settings_row    <= 3'd0;
            time_edit       <= 1'b0;
        end else if (settings_active && kp_back_ev) begin
            if (time_edit)
                time_edit <= 1'b0;
            else
                settings_active <= 1'b0;
        end else if (settings_active && !time_edit && kp_up_ev) begin
            settings_row <= (settings_row == 3'd0) ? 3'd5 : (settings_row - 3'd1);
        end else if (settings_active && !time_edit && kp_down_ev) begin
            settings_row <= (settings_row == 3'd5) ? 3'd0 : (settings_row + 3'd1);
        end

        // 行 4：Enter 切换自动轮播（跨到 sd_card_clk 后做单拍）
        // v43：只有设置面板第 5 行 Enter 才切轮播；三号「系 统」不再顺带开轮播
        if (settings_active && (settings_row == 3'd4) && !time_edit && kp_enter_ev)
            auto_tog_tgl <= ~auto_tog_tgl;

        // 行 2：Enter 开关音频；音量由 A/D 调整
        if (settings_active && (settings_row == 3'd2) && !time_edit && kp_enter_ev)
            audio_on <= ~audio_on;
        // 行 3：Enter 开关波形；A/D 调 25/50/100% 透明度
        if (settings_active && (settings_row == 3'd3) && !time_edit && kp_enter_ev)
            wave_on <= ~wave_on;

        // 行 5：Enter 进入时间编辑 / 最终确认；A/D 切时/分/秒，W/S 增减
        if (settings_active && (settings_row == 3'd5) && kp_enter_ev) begin
            if (!time_edit) begin
                time_edit  <= 1'b1;
                time_field <= 2'd0;
                edit_hh    <= tc_hh;
                edit_mm    <= tc_mm;
                edit_ss    <= tc_ss;
            end else begin
                time_load <= 1'b1;
                time_edit <= 1'b0;
            end
        end

        if (settings_active && time_edit) begin
            if (kp_dec_ev)
                time_field <= (time_field == 2'd0) ? 2'd2 : (time_field - 2'd1);
            else if (kp_inc_ev)
                time_field <= (time_field == 2'd2) ? 2'd0 : (time_field + 2'd1);

            if (kp_up_ev || (enc_level != enc_level_d && enc_level > enc_level_d)) begin
                if (time_field == 2'd0)
                    edit_hh <= bcd_inc(edit_hh, 8'h23);
                else if (time_field == 2'd1)
                    edit_mm <= bcd_inc(edit_mm, 8'h59);
                else
                    edit_ss <= bcd_inc(edit_ss, 8'h59);
            end else if (kp_down_ev || (enc_level != enc_level_d && enc_level < enc_level_d)) begin
                if (time_field == 2'd0)
                    edit_hh <= bcd_dec(edit_hh, 8'h23);
                else if (time_field == 2'd1)
                    edit_mm <= bcd_dec(edit_mm, 8'h59);
                else
                    edit_ss <= bcd_dec(edit_ss, 8'h59);
            end
        end else if (settings_active && kp_inc_ev) begin
            if (settings_row == 3'd0)
                set_bright <= (set_bright > 8'd239) ? 8'd255 : (set_bright + 8'd16);
            else if (settings_row == 3'd1)
                set_contrast <= (set_contrast > 8'd239) ? 8'd255 : (set_contrast + 8'd16);
            else if (settings_row == 3'd2)
                vol_step <= (vol_step == 2'd3) ? 2'd0 : (vol_step + 2'd1);
            else if (settings_row == 3'd3)
                wave_step <= (wave_step == 2'd2) ? 2'd0 : (wave_step + 2'd1);
            else if (settings_row == 3'd4)
                auto_step <= (auto_step == 2'd2) ? 2'd0 : (auto_step + 2'd1);
        end else if (settings_active && kp_dec_ev) begin
            if (settings_row == 3'd0)
                set_bright <= (set_bright < 8'd16) ? 8'd0 : (set_bright - 8'd16);
            else if (settings_row == 3'd1)
                set_contrast <= (set_contrast < 8'd16) ? 8'd0 : (set_contrast - 8'd16);
            else if (settings_row == 3'd2)
                vol_step <= (vol_step == 2'd0) ? 2'd3 : (vol_step - 2'd1);
            else if (settings_row == 3'd3)
                wave_step <= (wave_step == 2'd0) ? 2'd2 : (wave_step - 2'd1);
            else if (settings_row == 3'd4)
                auto_step <= (auto_step == 2'd0) ? 2'd2 : (auto_step - 2'd1);
        end

        // 只在设置面板打开时，旋转才调整亮度/对比度
        if (settings_active && !time_edit && (enc_level != enc_level_d)) begin
            if (settings_row == 3'd0) begin
                if (enc_level > enc_level_d)
                    set_bright <= (set_bright > 8'd239) ? 8'd255 : (set_bright + 8'd16);
                else
                    set_bright <= (set_bright < 8'd16) ? 8'd0 : (set_bright - 8'd16);
            end else if (settings_row == 3'd1) begin
                if (enc_level > enc_level_d)
                    set_contrast <= (set_contrast > 8'd239) ? 8'd255 : (set_contrast + 8'd16);
                else
                    set_contrast <= (set_contrast < 8'd16) ? 8'd0 : (set_contrast - 8'd16);
            end
        end
    end
end

wire [7:0] tc_hh, tc_mm, tc_ss;

wire [23:0] vout_data_adj;
brightness_contrast_adjust u_bc_adjust (
    .clk        (video_clk),
    .rst_n      (~rst_all),
    .in_de      (de),
    .rgb_in     (vout_data_raw),
    .brightness (set_bright),
    .contrast   (set_contrast),
    .out_de     (),
    .rgb_out    (vout_data_adj)
);

// 2026-10-25 v23：首图还没提交（display_valid=0）时，图片层垫**页面底色**而不是黑屏。
// 以前是整层输出 24'd0，于是"上电还没装完就点进展区"看到的是纯黑（像死机）。
// 现在装载过程中看到的是"淡蓝页面 + 顶栏时间 + 字幕带"，图一到就正常显示；
// 因为只在 display_valid=0 时替换，SDRAM 里正在写的那半帧不会被露出来（不会撕裂）。
// 定义放在 C_FADE 之后（localparam 必须先声明后使用）。

wire [23:0] vout_data_osd;
wire [23:0] vout_data_menu;
wire [23:0] vout_data_dir;
// 2026-10-25 v26：菜单和设置面板**各自一份** font_rom（+8 BRAM，54→62/64）。
// 以前共用一份、字模地址由 settings_active 二选一，所以设置面板一打开，
// `main_menu.blank` 就必须把菜单整层让开（否则两边抢字库地址，菜单字模会被
// 面板地址带歪）。菜单一让开，背景就透出下一层 —— 用户看到的就是
// "从主界面点设置，背景不是主界面"。
// 各自一份之后两者可以同时画：菜单照常铺在底下（外圈被面板压暗 50%），
// 设置面板叠在上面，和网页设计一致（"面板背景 = 打开时的界面"）。
// 代价：BRAM 54→62（上限 64），后面若还要加 BRAM 就得先从这里腾。
wire [13:0] fnt_addr_menu, fnt_addr_set;
wire [15:0] fnt_dout_menu, fnt_dout_set;
// v37：主菜单与 info_bands 共用一块主字库（菜单页 / 图片页互斥，永不同屏）=> 省 8 块 BRAM
wire        menu_font_sel;
wire [13:0] fnt_addr_info;
wire [15:0] fnt_dout_shared;
font_rom u_shared_font (
    .clk  (video_clk),
    .addr (menu_font_sel ? fnt_addr_menu : fnt_addr_info),
    .dout (fnt_dout_shared)
);
// v39：「系 统」信息页与设置面板共用这块字库（两者永不同屏）=> 0 BRAM
wire [13:0] fnt_addr_sys;
wire [15:0] fnt_dout_setf;
font_rom u_set_font (
    .clk  (video_clk),
    .addr (sys_active ? fnt_addr_sys : fnt_addr_set),
    .dout (fnt_dout_setf)
);
// v79：ext 小字库（字幕 + 目录页）也搬到这里共用一份，深度扩到 2048（128 槽）。
//   以前是两份 1024×16（2+2 块 BRAM），现在一份 2048×16（4 块）——总数不变，
//   但目录页左下角那三行"展区简介"需要的字位有了（64 槽 -> 128 槽）。
//   目录页和字幕永不同屏，所以地址二选一是安全的（与 u_shared_font 同一个套路）。
wire [10:0] fnt_addr_ext_dir;    // 目录页要的地址
wire [10:0] fnt_addr_ext_info;   // 字幕要的地址
wire [15:0] fnt_dout_ext;
font_rom_ext u_ext_font (
    .clk  (video_clk),
    .addr (dir_active ? fnt_addr_ext_dir : fnt_addr_ext_info),
    .dout (fnt_dout_ext)
);

settings_panel u_settings_panel (
    .clk        (video_clk),
    .fnt_dout   (fnt_dout_setf),
    .fnt_addr   (fnt_addr_set),
    .rst_n      (~rst_all),
    .de         (de),
    .px         (osd_x),
    .py         (osd_y),
    .rgb_in     (vout_data_dir),

    .active     (settings_active),
    .sel_row    (settings_row),
    .time_edit  (time_edit),
    .time_field (time_field),
    .bright     (set_bright),
    .contrast   (set_contrast),
    .wave_on    (wave_on),
    .wave_step  (wave_step),
    .vol_step   ({1'b0, vol_step}),
    .audio_on   (audio_on),
    .auto_on    (player_auto),
    .auto_step  (auto_step),
    .hh         (time_edit ? edit_hh : tc_hh),
    .mm         (time_edit ? edit_mm : tc_mm),
    .ss         (time_edit ? edit_ss : tc_ss),
    .rgb_out    (vout_data_osd)
);

// v44/v69：「系统简介」层开关（四页说明，A/D 左右翻页）
//   * 只由主菜单第三项（open_sysinfo 脉冲）打开，menu_active 保持 1；
//   * A/D（左右键）翻页 0..3，到头夹住不循环；Back 关闭；
//   * 离开主菜单也强制关闭（双保险）；
//   * 打开期间 menu_ctrl 收到 sys_on=1，冻结 W/S/Enter，背景菜单不会跟着动。
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        sys_active <= 1'b0;
        sys_page   <= 2'd0;
    end else if (menu_open_sysinfo && menu_active) begin
        sys_active <= 1'b1;
        sys_page   <= 2'd0;
    end else if (sys_active && (!menu_active || kp_back_ev)) begin
        sys_active <= 1'b0;
        sys_page   <= 2'd0;
    end else if (sys_active) begin
        if (kp_inc_ev && (sys_page != 2'd3))
            sys_page <= sys_page + 2'd1;        // D：下一页
        else if (kp_dec_ev && (sys_page != 2'd0))
            sys_page <= sys_page - 2'd1;        // A：上一页
    end
end

wire [23:0] vout_data_sys;
sysinfo_panel u_sysinfo (
    .clk      (video_clk),
    .rst_n    (~rst_all),
    .de       (de),
    .px       (osd_x),
    .py       (osd_y),
    .rgb_in   (vout_data_osd),
    .active   (sys_active),
    .page     (sys_page),
    .fnt_dout (fnt_dout_setf),
    .fnt_addr (fnt_addr_sys),
    .rgb_out  (vout_data_sys)
);

// ===================== 字幕/时钟 OSD（阶段 2 第二步） =====================
reg        info_vs_d;
wire       info_frame_start = info_vs_d ^ vs;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all)
        info_vs_d <= 1'b0;
    else
        info_vs_d <= vs;
end

// ===================== 切图过渡：淡到页面底色 -> 换 buffer -> 淡入 =====================
// 说明：显示侧读地址在 frame_fifo_read 里是"每帧起点（S_ACK）才锁存"的，
//       所以 buffer 换得早或晚都不会撕裂 —— 只有画面内容会跳。
//       旧做法是"黑幕从左边退开 0.33 s"，硬边 + 纯黑，观感很廉价；
//       现在改成"暗到页面底色再亮出来"的过渡（约 0.37 s，11+11 帧），
//       全程 0 BRAM，只多 3 个乘法器（alpha 混合）+ 一点状态机。
wire [23:0] vout_data_wave;

localparam [23:0] C_FADE = 24'hEEF5FC;      // 过渡底色 = 页面底色（目录页 C_BG）
// 没图时图片层垫页面底色（见上方 v23 注释）；有图时就是正常的图片层
// 没图时图片层垫页面底色（见上方 v23 注释）；有图时就是正常的图片层。
// 2026-10-25 v25：**主菜单在位时也垫页面底色**。原因是主界面点"设置"后
//   `main_menu` 会被 blank 掉（设置面板和菜单共用一份 font_rom，地址被设置面板
//   独占，菜单不能同时画），blank 之后透出来的就是这一层 —— 以前透出来的是
//   SDRAM 里的图片页（顶栏"第 n 页/共 n 页"、展品照片、底栏展区名），看起来
//   就像"点设置背景变成了图片"。主菜单本身就是不透明满页，屏蔽图片层对它
//   没有任何视觉影响；而从图片页长按编码器打开设置时（menu_active=0）仍然是
//   "当前图片压暗一半"，符合原来的设计。
wire [23:0] img_under = (display_valid && !menu_active) ? vout_data_adj : C_FADE;
localparam [4:0]  A_MAX  = 5'd31;           // alpha 5 bit，A_MAX = 全亮
// v70：每帧 3 级 -> 11+11 帧 ≈ 0.37 s（保持原来的观感；0.13 s 太快，动画看不出来）
localparam [4:0]  A_STEP = 5'd3;

reg  [1:0]  dib_s1, dib_s2;                 // disp_buf_idx 同步到 video_clk
reg  [1:0]  idx_seen;                       // 稳定的新索引
reg  [3:0]  idx_stable;                     // 连续不变计数（去抖，去掉多比特跨域的毛刺）
reg  [1:0]  disp_show_idx;                  // 真正送给读通路的索引
reg  [1:0]  tstate;
reg  [4:0]  fade_a;
reg  [9:0]  fade_wait;                      // T_OUT 里等新图的最长帧数（约 10 s）

// v70：装载开始（img_load_active 上升沿）就先把画面暗下去，图到了再亮回来。
//   以前是"装载完 -> 淡出 -> 换 buffer -> 淡入"，淡出那 0.13 s 白白串在后面。
//   img_load_active 来自 sd_card_bmp（50 MHz 域），这里 2FF 同步后取上升沿。
reg  il_a1, il_a2, il_a3;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        il_a1 <= 1'b0;
        il_a2 <= 1'b0;
        il_a3 <= 1'b0;
    end else begin
        il_a1 <= img_load_active;
        il_a2 <= il_a1;
        il_a3 <= il_a2;
    end
end
wire load_start_ev = il_a2 & ~il_a3;

localparam [1:0] T_IDLE = 2'd0, T_OUT = 2'd1, T_IN = 2'd2;

always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        dib_s1     <= 2'd0;
        dib_s2     <= 2'd0;
        idx_seen   <= 2'd0;
        idx_stable <= 4'd0;
    end else begin
        dib_s1 <= disp_buf_idx;
        dib_s2 <= dib_s1;
        if (dib_s2 != idx_seen) begin
            idx_seen   <= dib_s2;
            idx_stable <= 4'd0;
        end else if (idx_stable != 4'hF) begin
            idx_stable <= idx_stable + 4'd1;
        end
    end
end
wire idx_settled = (idx_stable == 4'hF);
// 每帧一个 tick（vs 上升沿）。之前这里直接按 video_clk 走，
// 整个过渡 22 拍 = 0.9 us，屏上完全看不到，看起来就是"直接换一张"。
wire fade_frame_tick = vs & ~info_vs_d;

always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        tstate        <= T_IDLE;
        fade_a        <= A_MAX;
        disp_show_idx <= 2'd0;
        fade_wait     <= 10'd0;
    end else begin
        case (tstate)
            T_IDLE: begin
                fade_a    <= A_MAX;
                fade_wait <= 10'd0;
                // v70：按键/分区切换一发起装载就先暗下去；自动轮播同样走这条
                if ((load_start_ev ||
                     (display_valid && idx_settled && (idx_seen != disp_show_idx))) &&
                    fade_frame_tick)
                    tstate <= T_OUT;
            end
            T_OUT: begin
                if (fade_frame_tick) begin
                    if (fade_a > A_STEP) begin
                        fade_a <= fade_a - A_STEP;
                    end else begin
                        fade_a <= 5'd0;                 // 全底色
                        // 新图到位才换 buffer；没到位就停在底色上等（顶栏/字幕还在动）
                        if (idx_settled && (idx_seen != disp_show_idx)) begin
                            disp_show_idx <= idx_seen;  // 这一刻换 buffer
                            fade_wait     <= 10'd0;
                            tstate        <= T_IN;
                        end else if (fade_wait == 10'd600) begin
                            fade_wait <= 10'd0;         // 装载失败/超时：把旧图亮回来
                            tstate    <= T_IN;
                        end else begin
                            fade_wait <= fade_wait + 10'd1;
                        end
                    end
                end
            end
            T_IN: begin
                if (fade_frame_tick) begin
                    if (fade_a >= (A_MAX - A_STEP)) begin
                        fade_a <= A_MAX;
                        tstate <= T_IDLE;
                    end else begin
                        fade_a <= fade_a + A_STEP;
                    end
                end
            end
            default: tstate <= T_IDLE;
        endcase
    end
end

// 单通道混合：out = C + ((pix - C) * a) >> 5，带饱和
function [7:0] fade_ch;
    input [7:0] p;
    input [7:0] c;
    input [4:0] a;
    reg signed [9:0]  d;
    reg signed [14:0] m;
    reg signed [10:0] r;
    begin
        d = $signed({2'b00, p}) - $signed({2'b00, c});
        m = d * $signed({1'b0, a});
        r = $signed({2'b00, c}) + (m >>> 5);
        if (r < 0)
            fade_ch = 8'd0;
        else if (r > 11'sd255)
            fade_ch = 8'hFF;
        else
            fade_ch = r[7:0];
    end
endfunction

wire [23:0] vout_fade = (fade_a == A_MAX) ? vout_data_wave :
                        { fade_ch(vout_data_wave[23:16], C_FADE[23:16], fade_a),
                          fade_ch(vout_data_wave[15:8],  C_FADE[15:8],  fade_a),
                          fade_ch(vout_data_wave[7:0],   C_FADE[7:0],   fade_a) };

time_clock #(
    .CLK_HZ (25_000_000)
) u_time_clock (
    .clk    (video_clk),
    .rst_n  (~rst_all),
    .load   (time_load),
    .hh_in  (edit_hh),
    .mm_in  (edit_mm),
    .ss_in  (edit_ss),
    .hh     (tc_hh),
    .mm     (tc_mm),
    .ss     (tc_ss)
);

// 提交时间时给顶部信息带一个装载脉冲，之后两边都从 25 MHz 同源计数。
reg       time_load_d;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all)
        time_load_d <= 1'b0;
    else
        time_load_d <= time_load;
end
wire info_time_load = time_load_d;

wire [23:0] vout_data_info;
// v37：菜单/目录页时共享字库给主菜单，其余时候给 info_bands
assign menu_font_sel = menu_active | dir_active;
info_bands u_info_bands (
    .fnt_addr_o      (fnt_addr_info),
    .fnt_dout_i      (fnt_dout_shared),
    .fnt_addr_ext_o  (fnt_addr_ext_info),
    .fnt_dout_ext_i  (fnt_dout_ext),
    .clk               (video_clk),
    .rst_n             (~rst_all),
    .frame_start       (info_frame_start),
    .de                (de),
    .pixel_x           (osd_x),
    .pixel_y           (osd_y),
    .rgb_in            (vout_fade),
    .cur_index         (player_img_idx),
    .img_ready         ({4{display_valid}}),
    .zone_mode         (zone_mode),
    .zone_idx          (zone_idx),
    .zone_count        (zone_count),
    .zone_sel          (zone_sel),
    .disp_scale        (disp_scale),
    .auto_enabled      (player_auto),
    .bright_level      (set_bright[7:4]),
    .param_is_contrast (1'b0),
    .load              (info_time_load),
    .hh_in             (tc_hh),
    .mm_in             (tc_mm),
    .ss_in             (tc_ss),
    .rgb_out           (vout_data_info)
);

// ===================== 音频波形 OSD（行 3） =====================
promax_audio_waveform #(
    .WAVE_X      (64),
    .WAVE_Y      (176),
    .WAVE_WIDTH  (512),
    .WAVE_HEIGHT (128),
    .DECIMATE    (24)
) u_promax_audio_waveform (
    .clk             (video_clk),
    .rst_n           (~rst_all),
    .vsync           (vs),
    .de              (de),
    .rgb_in          (img_under),
    .pixel_x         (osd_x[9:0]),
    .opacity         (wave_step),
    .enable          (wave_on && audio_on),
    .pcm_tap_valid   (audio_valid_src),
    .pcm_tap_left    ($signed(audio_left_src[23:8])),
    .rgb_out         (vout_data_wave),
    .waveform_active ()
);

// 主界面三按钮菜单（目录 / 设置 / 待定）
main_menu u_main_menu (
    .clk      (video_clk),
    .fnt_dout (fnt_dout_shared),
    .fnt_addr (fnt_addr_menu),
    .rst_n    (~rst_all),
    .de       (de),
    .pixel_x  (osd_x),
    .pixel_y  (osd_y),
    .rgb_in   (vout_data_info),
    .active   (menu_active),
    .blank    (1'b0),          // v26：菜单有自己的字库了，设置面板打开时不再让开
    .sel      (menu_sel),
    .dir_mode (1'b0),
    .rgb_out  (vout_data_menu)
);

// 目录页（参考 web_test 布局）
// 左侧预览框已改成「展区徽标」（方案 D）：素材是 4 区各一张 108x81 的
// 2bpp 材质码表，直接由 directory_ui 内部的 zone_badge_rom 读，
// 原来这里那套 5x5 抽样 + 三点平均 + 3 个 18x18 乘法器（thumb_mem 11 块 BRAM）
// 整段删除，省 11 块 BRAM / 3 个 DSP。
directory_ui u_directory_ui (
    .clk      (video_clk),
    .rst_n    (~rst_all),
    .de       (de),
    .pixel_x  (osd_x),
    .pixel_y  (osd_y),
    .rgb_in   (vout_data_menu),
    .active   (dir_active),
    .sel      (dir_sel),
    .fnt_addr (fnt_addr_ext_dir),
    .fnt_dout (fnt_dout_ext),
    .rgb_out  (vout_data_dir)
);

// 首图提交前不再整层关黑：图片层在 v23 里已经改成"没图垫页面底色"（img_under），
// 所以这里始终输出 OSD 链路 —— 上电/换区装载期间看到的是淡蓝页面而不是黑屏。
//
// ---------------- 最左白边：回填方案全部撤销（2026-10-27 第四轮上板） ----------------
// 主界面也撤了：用户实测"没用"。三轮回填（v70 统一 6 px / v73 按页面 2~4 px / v75 只补主界面）
// 都只能在"多补一个像素"和"补出来的列来自上一行"之间取舍，做不到既不留线又不串色。
// 结论：这条路彻底放弃。要根治只能改 de/OSD 时序（让 OSD 计数提前 D 拍启动），
// 必须单独出验证位，不动演示版。
//
// v79：既然消不掉，就把它做成"设计的一部分"——左右各 2 px 白色竖线，对称。
//   * 左边这道本来就是 OSD 比 de 晚 D 拍留下的残影（颜色≈上一行右端），
//     现在直接把 osd_x<=1 覆盖成纯白，线与线的颜色统一；
//   * 右边 x>=638 覆盖成纯白，下一行行首的残影又会把这道白线"印"回左边，
//     于是两边天然对称；
//   * 目录页不加（dir_active=1 时直通），保持原来的版式。
localparam [23:0] C_EDGE = 24'hFFFFFF;
wire edge_on = ~dir_active;
// v79c：2 px -> 4 px（左右各 4 列），两侧对称
wire edge_px = (osd_x <= 12'd3) || (osd_x >= 12'd636);
assign vout_data = (edge_on && edge_px) ? C_EDGE : vout_data_sys;   // 最上层是「系统」简介页（未打开时透传）

frame_read_write #(
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (BUF2_ADDR),
    .read_addr_3       (BUF3_ADDR),
    .read_addr_index   (disp_show_idx),
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (BUF2_ADDR),
    .write_addr_3      (BUF3_ADDR),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// ===================== 音频：只认 TF 卡里的 WAV =====================
// 2026-10-25: 删掉内部 I2S 测试音（hdmi_audio_tone_i2s_64fs）和 I2S_receiver。
// 以前没有 WAV 时音频源会回落到那个 8 音循环测试音（C4-D4-E4-G4-A4-C5-A4-G4，每音 0.5 s），
// 上电听感就像"又在放以前固化进去的那首老曲子"，板上一直被误认成 FLASH 里的 MAIN.WAV。
// 现在起，任何时刻只有"正在播 WAV"才有声音，其它时候一律静音；
// 于是上电后听到的第一段声音必然是 MENU.WAV（主菜单/目录页选中的就是它）。
// 顺带省下测试音 + 接收器的寄存器/DSP（v16 实测 REG −364、DSP −3）。
//
// v70t 诊断（音频"滋滋"定位用，已单独出 bit：bitstream/HDMI2_HDMI14_Player_v70t.bit）
//   把音频源临时换成内部 1 kHz 正弦（64 点 1/4 表 + 象限展开），采样节拍、24 bit
//   左对齐、音量、ACR、HDMI 通路全部不变，只是不经过 SD/WAV：
//     听感干净 -> 问题在 WAV/SD 数据链；还是滋滋 -> 问题在 HDMI 核/接口。
//   正式版这里没有测试音，音频源只有 WAV。
assign wav_active_vid   = wav_stream_active && wav_find_found;
assign audio_left_src  = wav_active_vid ? {wav_sample_out[15], wav_sample_out, 8'd0} : 24'sd0;
assign audio_right_src = audio_left_src;

// ⚠️ audio_valid 必须是"每样本一拍"的 48 kHz 节拍，不能恒为 1：
// audio_arc_calculate 用它数样本数来算 ACR 的 CTS（48 个样本 → 25 MHz 下应为 25000），
// 恒 1 会让 CTS 变成 48，HDMI 接收端会把音频采样率判错。
// wav_stream_player 的读侧无论有没有在播都按 wav_tick 给 valid（缓冲空时给 0 值），
// 正好是我们要的"静音但节拍不断"。
assign audio_valid_src = wav_sample_valid;

audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_audio_valid (audio_valid_src),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_vs          (vs),
    .I_de          (de),
    .I_rgb         (vout_data),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_all),
    .O_pulse (edid_trig)
);

// ===================== 分区 BGM（MENU / A / B / C / D） =====================
//   主菜单和目录页放 MENU.WAV，A~D 展区各放 A/B/C/D.WAV；
//   曲目按 8.3 文件名在根目录里查（运行期可换名重查），播完自动重来（循环）。
//   换区 = 重新查一次名字 + 把播放器的 start_lba/total_sectors 换掉再 restart。
//   资源：只多一个 FSM + 一份 88bit 名字表，不占 BRAM、不复制查找器。
localparam [87:0] NM_MENU = 88'h4D454E5520202020_574156;   // "MENU    WAV"
localparam [87:0] NM_A    = 88'h4120202020202020_574156;   // "A       WAV"
localparam [87:0] NM_B    = 88'h4220202020202020_574156;   // "B       WAV"
localparam [87:0] NM_C    = 88'h4320202020202020_574156;   // "C       WAV"
localparam [87:0] NM_D    = 88'h4420202020202020_574156;   // "D       WAV"

// 想要哪一段：0=MENU，1..4 = A..D
//   ⚠️ 用 zone_sel（目录里选中的展区，进区后保持不变），不是 zone_idx ——
//   后者是"本区第几张图"（顶栏 第 n 页），拿它当展区会变成按页换曲。
wire [2:0] aud_want_vid = (menu_active || dir_active) ? 3'd0
                                                    : ({1'b0, zone_sel} + 3'd1);
// 音频起播门槛：SD 初始化 + 元数据就绪（不再等首图，见 v23 注释）
wire       aud_boot_ok  = boot_ok;

// v79：目标曲目做"稳定滤波"。menu_active / dir_active / zone_sel 都是 video_clk
//   域的多 bit 信号，直接 2FF 进 sd 域时，1->0 这类变化中间可能扫出 2、3 这种
//   不存在的展区号，会让音频去查一个不存在的文件。这里要求目标值连续 65536 拍
//   （≈1.3 ms）不变才采信。
reg  [2:0]  aw_s1, aw_s2, aw_s3;
reg  [15:0] aw_settle;
always @(posedge sd_card_clk or negedge sd_rst_n) begin
    if (!sd_rst_n) begin
        aw_s1 <= 3'd0; aw_s2 <= 3'd0; aw_s3 <= 3'd7; aw_settle <= 16'd0;
    end else begin
        aw_s1 <= aud_want_vid;
        aw_s2 <= aw_s1;
        if (aw_s2 != aw_s3) begin
            if (aw_settle == 16'hFFFF) begin
                aw_s3     <= aw_s2;
                aw_settle <= 16'd0;
            end else begin
                aw_settle <= aw_settle + 16'd1;
            end
        end else begin
            aw_settle <= 16'd0;
        end
    end
end
wire [2:0] aud_want = aw_s3;

wire [87:0] aud_name = (aud_want == 3'd1) ? NM_A :
                       (aud_want == 3'd2) ? NM_B :
                       (aud_want == 3'd3) ? NM_C :
                       (aud_want == 3'd4) ? NM_D : NM_MENU;

// ---------------------------------------------------------------------------
// v79：换曲流程（板测"从展区回主界面音乐就永久静音"的根因修复）
//
//   v78 及以前：发现目标曲目变了就直接 start fat32_find_file，而此时 wav_stream_player
//   很可能正在等自己的扇区 sd_done。两条通路共享同一组 sd_valid / sd_byte / sd_done
//   （sd_card_bmp 里只区分"WAV 还是图片"，没区分"播放器还是查找器"）：
//     * 查找器会把播放器那一笔的 done 当成自己的，播放器又把查找器那一笔当成自己的；
//     * 播放器在 WS_REQ 看到总线空闲进了 WS_FILL，可它的 sd_req 已经被 mux 掉，
//       仲裁再也不会为它开事务 -> 永远等不到 done -> 音乐永久卡死。
//
//   现在改成串行：目标变化 -> 先拉低 play_enable（播放器自己会在一个扇区内退回 IDLE）
//   -> 等 player_idle -> 才 start 查找 -> 查到后再给 restart + 新 LBA + play_enable。
//   每一步都有超时兜底，任何一步出问题都回到 IDLE 重试，不会把状态机钉死。
// ---------------------------------------------------------------------------
localparam [2:0] A_IDLE  = 3'd0,   // 正常播放，盯目标
                 A_STOP  = 3'd1,   // 已停播，等播放器写侧空闲
                 A_GO    = 3'd2,   // 已发出查找请求，等 finder 起来
                 A_BUSY  = 3'd3;   // 查找进行中

localparam [21:0] AUD_TO_MAX = 22'h3F_FFFF;   // 84 ms @ 50 MHz
localparam [23:0] AUD_RETRY  = 24'h0F_FFFF;   // 失败后歇 ~0.33 s 再试

reg  [2:0]  aud_state;
reg  [2:0]  aud_sel_cur;      // 当前正在播的曲目，7 = 还没查过
reg  [2:0]  aud_target;
reg         aud_go, aud_restart_q, aud_play_en;
reg  [31:0] aud_lba_q, aud_secs_q;
reg  [23:0] aud_retry;
reg  [21:0] aud_to;

always @(posedge sd_card_clk or negedge sd_rst_n) begin
    if (!sd_rst_n) begin
        aud_state     <= A_IDLE;
        aud_sel_cur   <= 3'd7;      // 7 = 还没查过：开机第一轮一定会查一次 MENU
        aud_target    <= 3'd0;
        aud_go        <= 1'b0;
        aud_restart_q <= 1'b0;
        aud_play_en   <= 1'b0;
        aud_lba_q     <= 32'd0;
        aud_secs_q    <= 32'd0;
        aud_retry     <= 24'd0;
        aud_to        <= 22'd0;
    end else begin
        aud_go        <= 1'b0;
        aud_restart_q <= 1'b0;
        case (aud_state)
            A_IDLE: begin
                aud_to <= 22'd0;
                if (aud_retry != 24'd0) begin
                    aud_retry <= aud_retry - 24'd1;
                end else if (aud_boot_ok && (aud_want != aud_sel_cur)) begin
                    // 目标变了：先停播，等播放器退出（play_enable=0 后它最多再占一个扇区）
                    aud_target  <= aud_want;
                    aud_play_en <= 1'b0;
                    aud_state   <= A_STOP;
                end
            end
            A_STOP: begin
                if (wav_player_idle || (aud_to == AUD_TO_MAX)) begin
                    aud_to    <= 22'd0;
                    aud_go    <= 1'b1;
                    aud_state <= A_GO;
                end else begin
                    aud_to <= aud_to + 22'd1;
                end
            end
            A_GO: begin
                if (wav_find_busy) begin
                    aud_to    <= 22'd0;
                    aud_state <= A_BUSY;
                end else if (aud_to == AUD_TO_MAX) begin
                    aud_to    <= 22'd0;
                    aud_retry <= AUD_RETRY;
                    aud_state <= A_IDLE;
                end else begin
                    aud_to <= aud_to + 22'd1;
                end
            end
            A_BUSY: begin
                if (!wav_find_busy) begin
                    aud_to <= 22'd0;
                    if (wav_find_found) begin
                        aud_lba_q     <= wav_data_start +
                                         ((wav_first_cluster - 32'd2) * {24'd0, wav_spc});
                        aud_secs_q    <= (wav_file_size + 32'd511) >> 9;
                        aud_restart_q <= 1'b1;
                        aud_sel_cur   <= aud_target;
                        aud_retry     <= 24'd0;
                        aud_play_en   <= 1'b1;
                    end else begin
                        aud_retry <= AUD_RETRY;     // 没找到：别锁死，过一会再试
                    end
                    aud_state <= A_IDLE;
                end else if (aud_to == AUD_TO_MAX) begin
                    aud_to    <= 22'd0;              // finder 自己也有看门狗，这里只是兜底
                    aud_retry <= AUD_RETRY;
                    aud_state <= A_IDLE;
                end else begin
                    aud_to <= aud_to + 22'd1;
                end
            end
            default: aud_state <= A_IDLE;
        endcase

        // 流程中间目标又变了（用户继续按键）：放弃这次换曲，回 IDLE 重新来
        if (((aud_state == A_GO) || (aud_state == A_BUSY)) && (aud_want != aud_target))
            aud_state <= A_IDLE;
    end
end

fat32_find_file u_fat32_find_file (
    .clk                 (sd_card_clk),
    .rst_n               (sd_rst_n),
    .start               (aud_go),
    .target_name         (aud_name),
    .busy                (wav_find_busy),
    .found               (wav_find_found),
    .fs_error            (wav_find_err),
    .first_cluster       (wav_first_cluster),
    .file_size           (wav_file_size),
    .data_start_lba      (wav_data_start),
    .sectors_per_cluster (wav_spc),
    .sd_req              (wav_find_req),
    .sd_lba              (wav_find_lba),
    .sd_busy             (wav_sector_busy),
    .sd_valid            (wav_sector_valid),
    .sd_byte             (wav_sector_byte),
    .sd_byte_index       (wav_sector_byte_index),
    .sd_done             (wav_sector_done),
    .sd_error            (wav_sector_error)
);

// 48 kHz sample tick, video_clk = 25 MHz
reg [24:0] wav_acc;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        wav_acc <= 25'd0;
        wav_tick <= 1'b0;
    end else if (wav_acc + 25'd48000 >= 25'd25000000) begin
        wav_acc <= wav_acc + 25'd48000 - 25'd25000000;
        wav_tick <= 1'b1;
    end else begin
        wav_acc <= wav_acc + 25'd48000;
        wav_tick <= 1'b0;
    end
end

// 循环：播放器把整段读完并排空（stream_end）就重来一遍；换区也用同一个 restart 脉冲
wire wav_restart = wav_stream_end | aud_restart_q;
// 2026-10-25 v24：上电后先静音 2.5 s 再起播。
//   断电/固化重启时整条 HDMI 链路要重新建链，电视/显示器锁上信号并开始出声要 1~2 s；
//   早于这个时间播出去的声音接收端直接丢掉 —— 板测表现就是"从中间开始放"
//   （开场白只剩"…系统"）。只延迟**起播**，WAV 查找/装载照旧提前做，
//   所以不影响上电后图片的速度，换区/翻页也不受影响（那时链路早就稳了）。
//   换显示器若还缺开头，把 AUD_HOLD_CYC 加大到 4~5 s 即可（50 MHz 计数）。
//   ⚠️ 2026-10-25 v27 修正：v25 写成了 `27'd149_999_999` —— 27 bit 最大只有
//   134,217,727，这个常量被静默截断成 15,782,271（= 0.32 s），于是"3 s 静音"
//   实际只有 0.32 s，开场白又只剩"…系统"。计数器改成 28 bit。
localparam [27:0] AUD_HOLD_CYC = 28'd199_999_999;      // 4 s @ 50 MHz
reg  [27:0] aud_hold_cnt;
wire        aud_hold_done = (aud_hold_cnt == AUD_HOLD_CYC);
always @(posedge sd_card_clk or negedge sdcard_rst_n) begin
    if (!sdcard_rst_n)         aud_hold_cnt <= 28'd0;
    else if (!aud_hold_done)   aud_hold_cnt <= aud_hold_cnt + 28'd1;
end
// v79：换曲期间 aud_play_en=0，播放器停播，避免"查找器"和"播放器"抢同一组 sd_done
wire wav_play_enable = aud_play_en & (aud_lba_q != 32'd0) & aud_hold_done;

// v79：只有 A_IDLE（正常播放）时总线请求才归播放器；换曲流程里归查找器。
//   两条请求在结构上互斥，sd_valid/sd_done 不会再被两边同时消费。
assign wav_sector_req  = (aud_state == A_IDLE) ? wav_play_req : wav_find_req;
assign wav_sector_lba  = (aud_state == A_IDLE) ? wav_play_lba : wav_find_lba;

wav_stream_player u_wav_stream_player (
    .wr_clk        (sd_card_clk),
    .wr_rst_n      (sd_rst_n),
    .play_enable   (wav_play_enable),
    .restart       (wav_restart),
    .start_lba     (aud_lba_q),
    .total_sectors (aud_secs_q),
    .sd_req        (wav_play_req),
    .sd_lba        (wav_play_lba),
    .sd_busy       (wav_sector_busy),
    .sd_valid      (wav_sector_valid),
    .sd_byte       (wav_sector_byte),
    .sd_byte_index (wav_sector_byte_index),
    .sd_done       (wav_sector_done),
    .sd_error      (wav_sector_error),
    .rd_clk        (video_clk),
    .rd_rst_n      (~rst_all),
    .sample_tick   (wav_tick),
    .sample_out    (wav_sample_out),
    .sample_valid  (wav_sample_valid),
    .sample_ready  (1'b1),
    .sample_counter(),
    .stream_active (wav_stream_active),
    .stream_end    (wav_stream_end),
    .buffer_low    (wav_buffer_low),
    .player_idle   (wav_player_idle)
);
// 音频源选择（2026-10-25 "音频只认 WAV" 版）：
//   * 正在放 WAV                  -> WAV 采样
//   * 其它任何时刻（没卡/没文件/缓冲间隙） -> 静音
// 不再回落到内部 I2S 测试音；audio_left_src / audio_valid_src 的定义已上移到
// "音频：只认 TF 卡里的 WAV" 那一节（紧跟被删掉的测试音实例位置）。

// ===================== 带音频的 HDMI 1.4b 发射 =====================
// 2026-10-25 v30：整体降 6 dB 给后级留余量（26/64/128 → 13/32/64）。
// 板测事实：**关音频（输出精确 0）就完全安静；一放音乐就全程"滋滋"，且随音量成比例**。
// 说明噪声不是后级自噪声，而是"被我们的信号激出来的"；而我们的数字通路是可验证无损的
// （16 bit → 24 bit 左对齐、DC=0、无掉块/无块重复、静音样本精确为 0），
// 所以最可能是显示器/电视的小喇叭 + 功放在接近满幅时失真/互调（"滋滋"）。
// 先把数字电平压 6 dB（峰值从 -6 dBFS 降到 -12 dBFS），让后级有 6 dB 余量；
// 你把电视音量相应开大一点即可。若这一版"滋滋"明显变小 → 就是后级过载，
// 再决定是停在 -12 dBFS 还是继续 -18 dBFS。
wire [7:0] audio_gain = (vol_step == 2'd0) ? 8'd13 :
                        (vol_step == 2'd1) ? 8'd32 :
                        (vol_step == 2'd2) ? 8'd64 : 8'd128;
wire signed [31:0] audio_l_mul = $signed(audio_left_src)  * $signed({1'b0, audio_gain});
wire signed [31:0] audio_r_mul = $signed(audio_right_src) * $signed({1'b0, audio_gain});
wire [23:0] audio_left_vol  = audio_on ? audio_l_mul[31:8] : 24'sd0;
wire [23:0] audio_right_vol = audio_on ? audio_r_mul[31:8] : 24'sd0;

hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_all),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (audio_valid_src),
    .I_audio_left_data  (audio_left_vol),
    .I_audio_right_data (audio_right_vol),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_all),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
