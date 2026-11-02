
module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [2:0]   SCAN_TARGET_COUNT = 3'd4,
    parameter integer LONG_PRESS_MS     = 1000
)(
    input                       clk,
    input                       rst,
    input                       key_next,
    input                       key_auto,
    input                       auto_toggle,     // one sd-clock pulse from settings row 4
    input  [1:0]                auto_step,       // 0=5s,1=10s,2=15s
    input                       main_next_toggle,
    input                       main_prev_toggle,
    output [3:0]                state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg                  display_valid,
    output wire [1:0]           img_index_out,
    output wire [2:0]           img_count_out,
    output wire                 auto_play_out,

    // WAV sector reader (higher priority than BMP image reads)
    input                       wav_sector_req,
    input  [31:0]               wav_sector_lba,
    output wire                 wav_sector_busy,
    output wire                 wav_sector_valid,
    output wire [7:0]           wav_sector_byte,
    output wire [8:0]           wav_sector_byte_index,
    output wire                 wav_sector_done,
    output wire [7:0]           wav_sector_error,
    output wire                 img_sd_busy,
    // 2026-10-25: bmp_read 忙（开机扫描或装图）= 1。给顶层用来"图片装载期间
    // 把 WAV 的 SD 请求全部让开"——两者同时在总线上会互相吞 done，实测能把
    // 一次装载卡死 8 s 以上（数码管状态码 5）。
    output wire                 img_load_active,
    // 2026-10-25 v23：SD 初始化完成 + 分区/扫描元数据就绪（几十毫秒级）。
    // 上一级用它当"可以开始找 WAV 了"的门槛，替代原来的 display_valid（要等首图 ~1~2 s）。
    output wire                 boot_ok,
    output wire [4:0]           zone0_count,
    output wire [4:0]           zone1_count,
    output wire [4:0]           zone2_count,
    output wire [4:0]           zone3_count,
    input                       zone_apply,
    input                       zone_preview,
    input  [1:0]                zone_sel,
    output wire                 zone_mode_out,
    output wire [3:0]           zone_idx_out,
    output wire [4:0]           zone_count_out,
    // v31：当前**显示中**那张图的抽取比（1/2/3）。顶层用它把底栏 "n / m"
    // 换成 "1 / N"（源图是显示尺寸的 N 倍），屏幕上就能直接看到缩放比。
    output wire [1:0]           disp_scale,
    // 2026-10-25: 板上诊断码（顶层的数码管静态显示），用来在没有逻辑分析仪的情况下
    // 判断"进分区不换图"到底卡在哪一步：
    //   0 = 分区已装载完成（健康）          1 = 正在装载（<8s）
    //   2 = 分区请求挂着但没开始装载        3 = 还没收到过分区请求
    //   4 = 该分区图片表为空（FAT/分区解析失败） 5 = 装载超过 8s 仍没完成（卡死）
    //   6 = 收到过请求但既没进分区模式也没装载  8 = SD 还没初始化完成
    output wire [3:0]           dbg_state,

    input                       write_finish_toggle,
    output reg [1:0]            write_buf_idx,
    output reg [1:0]            disp_buf_idx,

    output                      write_req,
    input                       write_req_ack,
    output                      write_en,
    output [31:0]               write_data,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO
);

wire key_next_press;
wire key_auto_press;
wire key_auto_stable;
reg  [2:0] main_next_sync;
reg  [2:0] main_prev_sync;
wire main_next_pulse = main_next_sync[2] ^ main_next_sync[1];
wire main_prev_pulse = main_prev_sync[2] ^ main_prev_sync[1];
always @(posedge clk or posedge rst) begin
    if (rst) begin
        main_next_sync <= 3'd0;
        main_prev_sync <= 3'd0;
    end else begin
        main_next_sync <= {main_next_sync[1:0], main_next_toggle};
        main_prev_sync <= {main_prev_sync[1:0], main_prev_toggle};
    end
end

wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_data_valid;
wire             sd_sec_read_end;
wire             sd_sec_read_error;     // v79: SD 核报上来的坏扇区
wire             bmp_data_wr_en;
wire [23:0]      bmp_data;
wire             sd_init_done;
wire             bmp_ready;
wire             scan_done;
wire             scan_found_valid;
wire [31:0]      scan_found_sector;
wire [2:0]       scan_found_total;

reg              scan_start_pulse;
reg              load_start_pulse;
reg [31:0]       load_sector;
reg              scan_kicked;

reg              first_image_committed;
reg              auto_play_en;
reg [31:0]       auto_cnt;
reg [2:0]        img_found_count;
reg [1:0]        img_idx;              // 当前真正显示中的图片编号
reg [1:0]        load_idx;             // 当前正在写入的图片编号
reg [1:0]        pending_buf_idx;      // 当前正在写入的目标缓冲区
reg [31:0]       img_sector0;
reg [31:0]       img_sector1;
reg [31:0]       img_sector2;
reg [31:0]       img_sector3;
reg              next_req_pending;
reg              prev_req_pending;
reg              key_auto_stable_d;
reg [31:0]       long_press_cnt;
reg              long_press_marked;
reg              load_busy;

// 2026-10-25: 分区装载诊断（声明放前面，避免"use before declaration"变成隐式 1bit 网）
reg              zone_req_seen;
reg              empty_zone_seen;
reg              stuck_seen;
reg [1:0]        disp_scale_r;
wire [1:0]       bmp_src_scale;
reg [28:0]       load_wdt;
wire             load_wdt_expired = (load_wdt == 29'd399_999_999);   // 8 s @ 50 MHz
// 一笔装载 8 s 还没提交 -> 判定卡死，打断 bmp_read 并清 load_busy，
// 让后面的换区/翻页还能重新开始（否则整屏永久卡死，只能断电）。
// v79：SD 核报坏扇区（等不到数据令牌等）也立刻收笔，不让半截数据继续拼图。
//   只在"图片正在装"的时候采信（load_busy=1），开机扫描阶段不能被打断 ——
//   扫描被打断会让 scan_done 永远不置 1，之后既没有首图也没有换区。
wire             load_abort = load_wdt_expired | (sd_sec_read_error & load_busy);
// 2026-10-25 v23：开机首扫的起点/范围（等分区扫描器把 A01 的扇区算出来）
// v26 修正：计时从 **sd_init_done** 开始，而不是从复位开始。
//   以前从复位开始数 84 ms，而 SD 初始化本身要 100~500 ms，等 do_init 完成时
//   计时早就溢出 → 首扫经常抢在分区扫描前面启动 → 退回"从扇区 0 走 FAT"的慢扫，
//   于是每次上电时间差别很大（几秒到十几秒）。现在从 SD 就绪后数 168 ms，
//   分区扫描只要几毫秒，几乎必定先完成，上电时间就稳定了。
reg  [23:0]      boot_wait;
wire             zone_table_ok;
wire             boot_scan_go;
wire [31:0]      boot_scan_lba;
wire [31:0]      boot_scan_max;
always @(posedge clk or posedge rst) begin
    if (rst)                  boot_wait <= 24'd0;
    else if (scan_kicked)     boot_wait <= 24'd0;
    else if (!sd_init_done)   boot_wait <= 24'd0;              // 从 SD 就绪才开始计时
    else if (!boot_wait[23])  boot_wait <= boot_wait + 24'd1;   // 2^23 / 50MHz ≈ 168 ms
end
assign boot_scan_go = zscan_done || boot_wait[23];             // 分区扫描完成或超时兜底
always @(posedge clk or posedge rst) begin
    if (rst)
        load_wdt <= 29'd0;
    else if (!load_busy || sd_sec_read_end)
        load_wdt <= 29'd0;   // v34: 每收到一个镜像扇区就清零 => 8 秒无进展才放弃               // 只有在"装载挂着"的时候才计时
    else if (!load_wdt_expired)
        load_wdt <= load_wdt + 29'd1;
end

// bmp_ready 先表示“源文件读取/送 FIFO 完成”；真正切显示要等 write_finish_toggle 同步后
reg              source_done_seen;

// 同步 mem_clk 域的 write_finish_toggle
reg [2:0]        wrfin_tgl_sync;
wire             write_finish_pulse;

wire auto_tick;
wire [1:0] next_from_current;
wire [1:0] prev_from_current;

assign write_en   = bmp_data_wr_en;
assign write_data = {bmp_data[23:16], bmp_data[15:8], bmp_data[7:0], 8'b0};
wire [31:0] auto_period = (auto_step == 2'd0) ? (32'd5 * CLK_FREQ_HZ) :
                          (auto_step == 2'd1) ? (32'd10 * CLK_FREQ_HZ) :
                                                (32'd15 * CLK_FREQ_HZ);
assign auto_tick  = (auto_cnt >= (auto_period - 32'd1));
assign next_from_current = next_index_limited(img_idx, img_found_count);
assign prev_from_current = prev_index_limited(img_idx, img_found_count);
assign img_index_out = img_idx;
assign img_count_out = img_found_count;
assign auto_play_out = auto_play_en;
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_next (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_next),
    .press_pulse(key_next_press)
);

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_auto (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_auto),
    .press_pulse(key_auto_press),
    .button_stable_out(key_auto_stable)
);

function [1:0] next_index_limited;
    input [1:0] cur;
    input [2:0] count;
    begin
        case (count)
            3'd0: next_index_limited = 2'd0;
            3'd1: next_index_limited = 2'd0;
            3'd2: next_index_limited = (cur == 2'd1) ? 2'd0 : (cur + 2'd1);
            3'd3: next_index_limited = (cur == 2'd2) ? 2'd0 : (cur + 2'd1);
            default: next_index_limited = (cur == 2'd3) ? 2'd0 : (cur + 2'd1);
        endcase
    end
endfunction

function [1:0] prev_index_limited;
    input [1:0] cur;
    input [2:0] count;
    begin
        case (count)
            3'd0: prev_index_limited = 2'd0;
            3'd1: prev_index_limited = 2'd0;
            3'd2: prev_index_limited = (cur == 2'd0) ? 2'd1 : (cur - 2'd1);
            3'd3: prev_index_limited = (cur == 2'd0) ? 2'd2 : (cur - 2'd1);
            default: prev_index_limited = (cur == 2'd0) ? 2'd3 : (cur - 2'd1);
        endcase
    end
endfunction

function [31:0] sector_lut;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: sector_lut = img_sector0;
            2'd1: sector_lut = img_sector1;
            2'd2: sector_lut = img_sector2;
            2'd3: sector_lut = img_sector3;
            default: sector_lut = img_sector0;
        endcase
    end
endfunction

function [1:0] next_buf_lut;
    input [1:0] cur_disp_buf;
    input       valid_now;
    begin
        if (!valid_now)
            next_buf_lut = 2'd0;                 // 首图固定写 buffer0
        else if (cur_disp_buf == 2'd0)
            next_buf_lut = 2'd1;
        else
            next_buf_lut = 2'd0;
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        wrfin_tgl_sync        <= 3'b000;
        scan_start_pulse      <= 1'b0;
        load_start_pulse      <= 1'b0;
        load_sector           <= 32'd0;
        scan_kicked           <= 1'b0;
        first_image_committed <= 1'b0;
        auto_play_en          <= 1'b0;
        auto_cnt              <= 32'd0;
        img_found_count       <= 3'd0;
        img_idx               <= 2'd0;
        load_idx              <= 2'd0;
        pending_buf_idx       <= 2'd0;
        write_buf_idx         <= 2'd0;
        disp_buf_idx          <= 2'd0;
        img_sector0           <= 32'd0;
        img_sector1           <= 32'd0;
        img_sector2           <= 32'd0;
        img_sector3           <= 32'd0;
        zone_mode             <= 1'b0;
        zone_cur              <= 2'd0;
        zone_idx              <= 4'd0;
        zone_pending          <= 1'b0;
        zone_pending_sel      <= 2'd0;
        zone_req_seen         <= 1'b0;
        empty_zone_seen       <= 1'b0;
        stuck_seen            <= 1'b0;
        disp_scale_r          <= 2'd1;
        next_req_pending      <= 1'b0;
        prev_req_pending      <= 1'b0;
        key_auto_stable_d     <= 1'b1;
        long_press_cnt        <= 32'd0;
        long_press_marked     <= 1'b0;
        load_busy             <= 1'b0;
        source_done_seen      <= 1'b0;
        display_valid         <= 1'b0;
    end else begin
        wrfin_tgl_sync   <= {wrfin_tgl_sync[1:0], write_finish_toggle};
        scan_start_pulse <= 1'b0;
        load_start_pulse <= 1'b0;

        if (!sd_init_done) begin
            scan_kicked           <= 1'b0;
            first_image_committed <= 1'b0;
            auto_play_en          <= 1'b0;
            auto_cnt              <= 32'd0;
            img_found_count       <= 3'd0;
            img_idx               <= 2'd0;
            load_idx              <= 2'd0;
            pending_buf_idx       <= 2'd0;
            write_buf_idx         <= 2'd0;
            disp_buf_idx          <= 2'd0;
            img_sector0           <= 32'd0;
            img_sector1           <= 32'd0;
            img_sector2           <= 32'd0;
            img_sector3           <= 32'd0;
            next_req_pending      <= 1'b0;
        prev_req_pending      <= 1'b0;
        key_auto_stable_d     <= 1'b1;
        long_press_cnt        <= 32'd0;
        long_press_marked     <= 1'b0;
            load_busy             <= 1'b0;
            source_done_seen      <= 1'b0;
            display_valid         <= 1'b0;
        end else begin
            // 扫描阶段缓存前 4 张图的起始 sector
            if (scan_found_valid) begin
                case (img_found_count)
                    3'd0: img_sector0 <= scan_found_sector;
                    3'd1: img_sector1 <= scan_found_sector;
                    3'd2: img_sector2 <= scan_found_sector;
                    3'd3: img_sector3 <= scan_found_sector;
                    default: ;
                endcase

                if (img_found_count < 3'd4)
                    img_found_count <= img_found_count + 3'd1;
            end

            // 记住 bmp_read 已经把源图送完 FIFO，但还不能切显示，得等整帧写完
            if (load_busy && bmp_ready)
                source_done_seen <= 1'b1;

            // 注：曾经加过 2.7 s 装载看门狗，但 SD 侧一次整帧装载（921 KB）可能远慢于此
            //     （开机第一次装载尤其慢），看门狗会把正常装载掐断 -> display_valid 永远不置 1
            //     -> 整屏全黑。已删除，回到"写完即提交"的原始行为。
            // 只有真正收到 write_finish_toggle 脉冲，才提交新图并切换显示缓冲区
            // 注：曾经在这里做过"开机第一张写两遍"，但第二遍的 load_start_pulse
            //     没等 bmp_ready，脉冲丢在 bmp_read 忙的时候 -> load_busy 永远为 1，
            //     之后既不显示也不装载（整屏全黑）。已整体撤销，保持原来的单次提交。
            if (load_busy && source_done_seen && write_finish_pulse) begin
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
                disp_buf_idx          <= pending_buf_idx;
                img_idx               <= load_idx;
                disp_scale_r          <= bmp_src_scale;     // v31：跟图像一起提交
                display_valid         <= 1'b1;
                first_image_committed <= 1'b1;
            end else if (load_abort) begin
                // 8 s 看门狗：放弃这一笔装载，放开 load_busy，让换区/翻页能重来
                load_busy        <= 1'b0;
                source_done_seen <= 1'b0;
                stuck_seen       <= 1'b1;
            end

            // 上电后自动发起一次"扫描前 4 张 BMP"
            // 2026-10-25 v23：**从分区表拿到的 A01 扇区开始扫**，不再从扇区 0 一路扫过去。
            // 大卡上 FAT 区可能有几 MB~几十 MB（两张 FAT），老的 raw 扫描要一个扇区一个
            // 扇区走过整个 FAT 区才能碰到第一张 BMP —— 这就是"上电要等十几秒"的根源。
            // 现在分区扫描器（fat32_zone_scan，最高优先级、开机几毫秒就跑完）已经知道
            // A01 的确切扇区，直接从这里开扫：4 张图各读 1 个扇区就够，几毫秒完成。
            // 分区表为空（不是 A01..D10 命名）时才退回原来的"从 sector 0 扫"。
            if (!scan_kicked && bmp_ready && boot_scan_go) begin
                scan_start_pulse      <= 1'b1;
                scan_kicked           <= 1'b1;
                first_image_committed <= 1'b0;
                auto_play_en          <= 1'b0;
                auto_cnt              <= 32'd0;
                img_found_count       <= 3'd0;
                img_idx               <= 2'd0;
                load_idx              <= 2'd0;
                pending_buf_idx       <= 2'd0;
                write_buf_idx         <= 2'd0;
                disp_buf_idx          <= 2'd0;
                next_req_pending      <= 1'b0;
        prev_req_pending      <= 1'b0;
        key_auto_stable_d     <= 1'b1;
        long_press_cnt        <= 32'd0;
        long_press_marked     <= 1'b0;
                display_valid         <= 1'b0;
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
            end else begin
                // 忙的时候也只记 1 次“下一张”请求，不会累积成连跳两张
                if (key_next_press && scan_done && (img_found_count > 3'd0))
                    next_req_pending <= 1'b1;

                // 矩阵键盘 A/D：主界面手动上一张/下一张
                if (main_next_pulse && scan_done && (img_found_count > 3'd0))
                    next_req_pending <= 1'b1;
                if (main_prev_pulse && scan_done && (img_found_count > 3'd0))
                    prev_req_pending <= 1'b1;

                // KEY2: 短按切换自动轮播；长按 1 s 触发上一张。
                key_auto_stable_d <= key_auto_stable;
                if (!key_auto_stable) begin
                    if (!long_press_marked) begin
                        if (long_press_cnt >= ((CLK_FREQ_HZ / 1000) * LONG_PRESS_MS - 1)) begin
                            if (scan_done && (img_found_count > 3'd0)) begin
                                prev_req_pending <= 1'b1;
                                long_press_marked <= 1'b1;
                            end
                        end else begin
                            long_press_cnt <= long_press_cnt + 32'd1;
                        end
                    end
                end else begin
                    long_press_cnt <= 32'd0;
                    if (!key_auto_stable_d && !long_press_marked &&
                        scan_done && (img_found_count > 3'd1)) begin
                        auto_play_en <= ~auto_play_en;
                        auto_cnt     <= 32'd0;
                    end
                    long_press_marked <= 1'b0;
                end

                // 设置页第 4 行 Enter 也可以切换轮播
                if (auto_toggle && scan_done && (img_found_count > 3'd1)) begin
                    auto_play_en <= ~auto_play_en;
                    auto_cnt     <= 32'd0;
                end

                // 自动播放 1s 计数：只有当前没有写图任务时才计时
                if (scan_done && auto_play_en && display_valid && !load_busy && first_image_committed && (img_found_count > 3'd1)) begin
                    if (auto_tick)
                        auto_cnt <= 32'd0;
                    else
                        auto_cnt <= auto_cnt + 32'd1;
                end else begin
                    auto_cnt <= 32'd0;
                end

                // 目录确认：先挂起，等图片加载器空闲再装载所选分区第一张
                // 注意：zone_preview（目录里上下移动时的"预览装载"）不再触发装载。
                // 否则目录里每按一次 W/S 就在后台装一张，目录一关就会看到
                // "预览那次装载"和"Enter 那次装载"两遍切图动画。
                if (zone_apply) begin
                    zone_pending     <= 1'b1;
                    zone_pending_sel <= zone_sel;
                    zone_req_seen    <= 1'b1;
                end
                else if (zone_pending && scan_done && bmp_ready && !load_busy) begin
                    // 2026-10-25: 该分区一张图都没扫到时，绝不能拿 sec_mem 的复位值 0
                    // 去当扇区地址 —— bmp_read 读到扇区 0 头部不匹配会"静默失败"
                    // （不报错、不换图、也不占 load_busy），屏上看着就是"卡住不动"。
                    // 这里直接忽略这次切换，保持当前画面并让 A/D 翻页继续可用。
                    if (zone_cur_count == 5'd0) begin
                        zone_pending     <= 1'b0;
                        empty_zone_seen  <= 1'b1;
                    end else begin
                    zone_mode        <= 1'b1;
                    zone_cur         <= zone_pending_sel;
                    zone_idx         <= 4'd0;
                    zone_pending     <= 1'b0;
                    load_idx         <= 2'd0;
                    load_sector      <= zone_rd_sector;
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    next_req_pending <= 1'b0;
                    prev_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0;
                    end
                end
                // 首图自动加载到 buffer0
                else if (scan_done && !first_image_committed && bmp_ready && !load_busy && (img_found_count != 3'd0)) begin
                    load_idx         <= 2'd0;
                    load_sector      <= img_sector0;
                    pending_buf_idx  <= 2'd0;
                    write_buf_idx    <= 2'd0;
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    next_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // 手动下一张优先：写到“非当前显示”的另一块 buffer
                // 分区模式：上一张/下一张只在本区表内移动
                else if (zone_mode && bmp_ready && !load_busy && (next_req_pending || prev_req_pending)) begin
                    if (next_req_pending && (zone_cur_count != 5'd0)) begin
                        zone_idx         <= zone_next_idx;
                        load_sector      <= zone_rd2_sector;
                        pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                        write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                        load_start_pulse <= 1'b1;
                        load_busy        <= 1'b1;
                        source_done_seen <= 1'b0;
                    end else if (prev_req_pending && (zone_cur_count != 5'd0)) begin
                        zone_idx         <= zone_prev_idx;
                        load_sector      <= zone_rd2_sector;
                        pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                        write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                        load_start_pulse <= 1'b1;
                        load_busy        <= 1'b1;
                        source_done_seen <= 1'b0;
                    end
                    next_req_pending <= 1'b0;
                    prev_req_pending <= 1'b0;
                end
                else if (scan_done && bmp_ready && display_valid && !load_busy && next_req_pending && (img_found_count != 3'd0)) begin
                    load_idx         <= next_from_current;
                    load_sector      <= sector_lut(next_from_current);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    next_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // 上一张：同样重新读卡，写非显示 buffer；下一张优先。
                else if (scan_done && bmp_ready && display_valid && !load_busy &&
                         prev_req_pending && (img_found_count != 3'd0)) begin
                    load_idx         <= prev_from_current;
                    load_sector      <= sector_lut(prev_from_current);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    prev_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // 自动播放下一张：同样写到“非当前显示”的另一块 buffer
                // 分区模式自动轮播：按当前区张数循环
                else if (zone_mode && bmp_ready && display_valid && !load_busy &&
                         auto_play_en && auto_tick && (zone_cur_count > 5'd1)) begin
                    zone_idx         <= zone_next_idx;
                    load_sector      <= zone_rd2_sector;
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                else if (scan_done && bmp_ready && display_valid && !load_busy && auto_play_en && auto_tick && (img_found_count > 3'd1)) begin
                    load_idx         <= next_from_current;
                    load_sector      <= sector_lut(next_from_current);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
            end
        end
    end
end

// 4-bank 同款结构：图片请求和 WAV 请求先仲裁，再统一经过 sd_sector_adapter。
// adapter 在事务开始时锁存 LBA，事务中间不会因仲裁切换地址。
wire        img_sd_sec_read;
wire [31:0] img_sd_sec_addr;
wire [7:0]  arb_data;
wire        arb_valid;
wire [8:0]  arb_byte_index;
wire        arb_done;
wire [7:0]  arb_error;
wire        arb_busy;

// 分区扫描器：最高优先级，上电后先扫 A-D 文件名，再让图片扫描继续。
wire        zscan_req;
wire [31:0] zscan_lba;
wire        zscan_busy;
wire        zscan_done;
wire [7:0]  zscan_error;
reg         zscan_started;
wire        zscan_start = sd_init_done && !zscan_started;
always @(posedge clk or posedge rst) begin
    if (rst)
        zscan_started <= 1'b0;
    else if (zscan_start)
        zscan_started <= 1'b1;
end
wire zscan_active = zscan_req || zscan_busy;

reg        zone_mode;
reg [1:0]  zone_cur;
reg [3:0]  zone_idx;
reg        zone_pending;
reg [1:0]  zone_pending_sel;
wire [1:0] zone_rd_zone = zone_apply ? zone_sel :
                          (zone_pending ? zone_pending_sel : zone_cur);
wire [3:0] zone_rd_idx  = (zone_apply || zone_pending) ? 4'd0 : zone_idx;
wire [31:0] zone_rd_sector;
wire        zone_rd_valid;
wire [31:0] zone_rd2_sector;
wire [4:0]  zone_cur_count = (zone_rd_zone == 2'd0) ? zone0_count :
                             (zone_rd_zone == 2'd1) ? zone1_count :
                             (zone_rd_zone == 2'd2) ? zone2_count : zone3_count;
assign zone_mode_out  = zone_mode;
assign zone_idx_out   = zone_idx;
assign zone_count_out = zone_cur_count;
assign disp_scale     = disp_scale_r;
// 状态码（顶层数码管静态显示），含义见端口注释
assign dbg_state = !sd_init_done    ? 4'h8 :
                   stuck_seen       ? 4'h5 :
                   load_busy        ? 4'h1 :
                   empty_zone_seen  ? 4'h4 :
                   zone_mode        ? 4'h0 :
                   zone_pending     ? 4'h2 :
                   zone_req_seen    ? 4'h6 : 4'h3;
wire [3:0]  zone_next_idx = (({1'b0, zone_idx} + 5'd1) < zone_cur_count) ?
                            (zone_idx + 4'd1) : 4'd0;
wire [3:0]  zone_prev_idx = (zone_idx != 4'd0) ? (zone_idx - 4'd1) :
                            (zone_cur_count == 5'd0 ? 4'd0 : (zone_cur_count[3:0] - 4'd1));
wire [3:0]  zone_look_idx = next_req_pending ? zone_next_idx :
                            (prev_req_pending ? zone_prev_idx :
                             ((auto_play_en && auto_tick) ? zone_next_idx : zone_idx));

fat32_zone_scan u_zone_scan (
    .clk           (clk),
    .rst_n         (~rst),
    .start         (zscan_start),
    .busy          (zscan_busy),
    .done          (zscan_done),
    .fs_error      (zscan_error),
    .rd_zone       (zone_rd_zone),
    .rd_idx        (zone_rd_idx),
    .rd_sector     (zone_rd_sector),
    .rd_valid      (zone_rd_valid),
    .rd2_zone      (zone_cur),
    .rd2_idx       (zone_look_idx),
    .rd2_sector    (zone_rd2_sector),
    .zone0_count   (zone0_count),
    .zone1_count   (zone1_count),
    .zone2_count   (zone2_count),
    .zone3_count   (zone3_count),
    .sd_req        (zscan_req),
    .sd_lba        (zscan_lba),
    .sd_busy       (arb_busy),
    .sd_valid      (arb_valid & ~owner_wav),
    .sd_byte       (arb_data),
    .sd_byte_index (arb_byte_index),
    .sd_done       (arb_done & ~owner_wav),
    .sd_error      (arb_error)
);

// 2026-10-25 v23：开机首扫直接从分区表里的 A01 开始（见上方扫描触发处的注释）
assign zone_table_ok = zscan_done &&
                       ((zone0_count | zone1_count | zone2_count | zone3_count) != 5'd0);
assign boot_scan_lba = zone_table_ok ? zone_rd_sector : SCAN_START_SECTOR;
assign boot_scan_max = zone_table_ok ? (zone_rd_sector + 32'd65535) : SCAN_MAX_SECTOR;
// SD 就绪 + 分区表（或兜底的 raw 扫描）就绪 = 音频可以开始找 WAV
assign boot_ok = sd_init_done && (zscan_done || scan_done);

// ---------------------------------------------------------------------------
// 2026-10-25 v22：分时仲裁（图片优先 + 事务归属）
//
//   v21 为了不卡死，做法是"图片装载期间把 WAV 完全挡在总线外"，代价是换区/翻页时
//   音乐静音 1~2 s。v22 改成"图片优先 + 事务归属"，两件事同时成立：
//
//   1) **图片优先**：图片只要在请求就给它，WAV 只在"两个图片扇区之间那 1 拍空档"
//      里进来。所以一次装载最多被 WAV 拖慢约 10%，但绝不可能被饿死；
//   2) **事务归属**：每一笔 SD 事务在开始的这一拍锁存 owner（是 WAV 还是图片），
//      valid/done 只发给归属方。v20 卡死的真正原因是"WAV 把图片那一笔的 done
//      当成自己的，同时图片的 done 又被 wav_x_active 遮掉"——有了 owner 之后
//      这种双吞在结构上就不可能再发生。
//
//   另外把播放器看到的 sd_busy 改成"总线当前不归我"就为 1：否则它会在图片赢得
//   授权的那一拍误以为拿到总线（那一拍 arb_busy 还是 0），溜进 WS_FILL 之后
//   永远等不到自己的 done。
// ---------------------------------------------------------------------------
wire        img_req = img_sd_sec_read;
wire        wav_req = wav_sector_req;
wire        wav_grant = !zscan_active && wav_req;     // 这一拍仲裁指向 WAV

wire        arb_req = zscan_active ? 1'b1 :
                          (wav_req ? 1'b1 : img_req);
wire [31:0] arb_lba = zscan_active ? zscan_lba :
                          (wav_req ? wav_sector_lba : img_sd_sec_addr);

reg         owner_wav;
always @(posedge clk or posedge rst) begin
    if (rst)
        owner_wav <= 1'b0;
    else if (arb_req && !arb_busy)
        owner_wav <= wav_grant;      // 事务开始这一拍锁存归属
    else if (arb_done)
        owner_wav <= 1'b0;
end

assign img_sd_busy     = img_sd_sec_read || zscan_active;
assign img_load_active = ~bmp_ready;

sd_sector_adapter u_adapter (
    .clk                    (clk),
    .rst_n                  (~rst),
    .sector_req             (arb_req),
    .sector_lba             (arb_lba),
    .sector_busy            (arb_busy),
    .sector_valid           (arb_valid),
    .sector_byte            (arb_data),
    .sector_byte_index      (arb_byte_index),
    .sector_done            (arb_done),
    .sector_error           (arb_error),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_read_error      (sd_sec_read_error)
);

// WAV 看到的 busy = "总线不归我"：仲裁这一拍指向 WAV 且总线空闲时才允许它进 FILL
assign wav_sector_busy       = arb_busy | zscan_active;   // v34: 镜像装载期间 WAV 可插队
assign wav_sector_valid      = owner_wav ? arb_valid : 1'b0;
assign wav_sector_byte       = owner_wav ? arb_data  : 8'd0;
assign wav_sector_byte_index = owner_wav ? arb_byte_index : 9'd0;
assign wav_sector_done       = owner_wav ? arb_done  : 1'b0;
assign wav_sector_error      = owner_wav ? arb_error : 8'd0;

bmp_read bmp_read_m0(
    .clk                    (clk),
    .rst                    (rst),
    .ready                  (bmp_ready),

    .scan_start             (scan_start_pulse),
    .scan_start_sector      (boot_scan_lba),
    .scan_max_sector        (boot_scan_max),
    .scan_target_count      (SCAN_TARGET_COUNT),
    .scan_done              (scan_done),
    .scan_found_valid       (scan_found_valid),
    .scan_found_sector      (scan_found_sector),
    .scan_found_total       (scan_found_total),

    .load_start             (load_start_pulse),
    .load_sector            (load_sector),
    .abort                  (load_abort),

    .sd_init_done           (sd_init_done),
    .state_code             (state_code),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .src_scale              (bmp_src_scale),
    .write_req              (write_req),
    .write_req_ack          (write_req_ack),
    .sd_sec_read            (img_sd_sec_read),
    .sd_sec_read_addr       (img_sd_sec_addr),
    .sd_sec_read_data       ((owner_wav || zscan_active) ? 8'd0 : arb_data),
    .sd_sec_read_data_valid ((owner_wav || zscan_active) ? 1'b0 : arb_valid),
    .sd_sec_read_end        ((owner_wav || zscan_active) ? 1'b0 : arb_done),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data)
);

sd_card_top sd_card_top_m0(
    .clk                    (clk),
    .rst                    (rst),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_read_error      (sd_sec_read_error),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);

endmodule

module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按下=0
    output reg  press_pulse,
    output wire button_stable_out
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [31:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        cnt           <= 32'd0;
        press_pulse   <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable <= button_sync1;
                cnt           <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

assign button_stable_out = button_stable;

endmodule
