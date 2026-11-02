`timescale 1ns/1ps

// R3'-A: stream real audio content from the TF card and feed it into the
// existing HDMI audio chain (docs/29 rev: "what actually wins"). This module
// sits between the SD sector-read infrastructure and the PCM sample
// interface, using a dual-port BRAM circular buffer to absorb the ~12.5x
// rate mismatch between TF reads (~1.2 MB/s burst) and audio consumption
// (96 KB/s at 48 kHz 16-bit mono).
//
// Architecture:
//   TF sector bytes (mem_clk domain, byte-serial)
//     -> pair into 16-bit samples -> write into BRAM circular buffer
//   Audio sample ticks (pixel_clk domain, ~48 kHz)
//     -> read from BRAM -> output on valid/ready PCM interface
//
// The write side uses a sector-level state machine: issue one sector read,
// fill 256 samples (512 bytes), then issue the next. The read side consumes
// at the audio sample rate. Pointer crossing uses gray-coded 2FF sync (the
// established idiom). Buffer underflow outputs silence (zeros) with
// sample_valid still asserted, so the downstream HDMI chain never stalls.
//
// Data format: raw 16-bit signed little-endian PCM, 48 kHz mono. The PC
// tool (tools/make_audio_corpus.py) converts any WAV to this format before
// writing to the TF card. Endianness: TF bytes arrive LSB first.
module wav_stream_player #(
    // v79d：回退到 v60 的音频缓冲深度（1024 x 16 = 2 KB = 4 个扇区 ≈ 21.3 ms @48 kHz）。
    //   v79 为了省 LUT 把它减半到 512，读侧"有数就放"的策略在 512 深度下水位只有
    //   ~250 个样本（5 ms），抗抖动余量变小，听感上"滋滋"更明显；这里按用户要求
    //   整体回到 v60 的音频实现（深度 1024 + 满一个扇区才起播）。
    parameter integer ADDR_WIDTH = 10,         // 1024 x 16-bit = 2 KB = 4 sectors (~21.3 ms @48 kHz)
    parameter integer SAMPLES_PER_SECTOR = 256 // 512 bytes / 2
) (
    // write side: mem_clk domain (SD SPI engine clock)
    input  wire        wr_clk,
    input  wire        wr_rst_n,
    input  wire        play_enable,        // level: stream active
    input  wire        restart,            // one wr_clk pulse: restart from start_lba
    input  wire [31:0] start_lba,          // first data sector (after WAV header)
    input  wire [31:0] total_sectors,      // audio data extent in sectors
    output wire        sd_req,             // request a sector read
    output wire [31:0] sd_lba,
    input  wire        sd_busy,
    input  wire        sd_valid,           // one byte per valid pulse
    input  wire [7:0]  sd_byte,
    input  wire [8:0]  sd_byte_index,      // 0..511 within sector
    input  wire        sd_done,
    input  wire [7:0]  sd_error,

    // read side: pixel_clk domain (audio chain clock)
    input  wire        rd_clk,
    input  wire        rd_rst_n,
    input  wire        sample_tick,        // ~48 kHz pulse: consume one sample
    output reg  signed [15:0] sample_out,
    output reg         sample_valid,
    input  wire        sample_ready,       // from downstream (always 1 in our chain)

    // status (read side)
    output reg  [31:0] sample_counter,     // samples consumed (for OSD)
    output wire        stream_active,      // play_enable && not ended
    output wire        stream_end,         // all data consumed
    output wire        buffer_low,         // < 25% remaining (for OSD/status)
    // 写侧已经完全空闲（没有挂着的扇区事务）。顶层换曲时先拉低 play_enable、
    //   等这个信号为 1 再去跑 fat32_find_file —— 换曲期间“查文件名”和“取音频扇区”
    //   同时抢同一条 sd_valid/sd_done 总线会互相吞 done，板测表现就是音乐永久静音。
    output wire        player_idle
);
    // ---------------- circular buffer ----------------
    // v79d：把缓冲拆成"标准双端口 RAM"写法，让 TD 尽量推成 block RAM：
    //   写口：独立 always、单一时钟、单一写使能；
    //   读口：独立 always、地址 rd_ptr、输出寄存 buf_q。
    //   原来读/写都放在带大量无关逻辑的大 always 里，TD 推不出 BRAM，只能铺成
    //   LUTRAM（1024x16 要吃掉近 1000 个 LUT）。拆开后若仍是 LUTRAM，功能不变。
    reg [15:0] buffer [0:(1<<ADDR_WIDTH)-1];
    reg [ADDR_WIDTH-1:0] wr_ptr;    // write pointer (wr_clk domain)
    reg [ADDR_WIDTH-1:0] rd_ptr;    // read pointer (rd_clk domain)

    reg        buf_we;
    reg [15:0] buf_din;
    reg [ADDR_WIDTH-1:0] buf_waddr;
    always @(posedge wr_clk)
        if (buf_we)
            buffer[buf_waddr] <= buf_din;

    reg [15:0] buf_q;
    always @(posedge rd_clk)
        buf_q <= buffer[rd_ptr];

    // write state sync to read domain (quasi-static, 2FF is safe)
    reg [2:0] wstate_sync1, wstate_sync2;

    // gray-coded sync: wr_ptr -> rd_clk domain
    reg [ADDR_WIDTH-1:0] wr_gray;
    reg [ADDR_WIDTH-1:0] wr_gray_sync1, wr_gray_sync2;
    // gray-coded sync: rd_ptr -> wr_clk domain
    reg [ADDR_WIDTH-1:0] rd_gray;
    reg [ADDR_WIDTH-1:0] rd_gray_sync1, rd_gray_sync2;

    function [ADDR_WIDTH-1:0] to_gray;
        input [ADDR_WIDTH-1:0] b;
        begin
            to_gray = b ^ (b >> 1);
        end
    endfunction

    function [ADDR_WIDTH-1:0] from_gray;
        input [ADDR_WIDTH-1:0] g;
        reg [ADDR_WIDTH-1:0] b;
        integer i;
        begin
            b[ADDR_WIDTH-1] = g[ADDR_WIDTH-1];
            for (i = ADDR_WIDTH-2; i >= 0; i = i - 1)
                b[i] = b[i+1] ^ g[i];
            from_gray = b;
        end
    endfunction

    // synchronized pointers (each in the other domain)
    wire [ADDR_WIDTH-1:0] wr_ptr_in_rd = from_gray(wr_gray_sync2);
    wire [ADDR_WIDTH-1:0] rd_ptr_in_wr = from_gray(rd_gray_sync2);
    // ---- D1 (timing-only deviation from the reference) ----
    reg  [ADDR_WIDTH-1:0] wr_ptr_in_rd_q;
    reg  [ADDR_WIDTH-1:0] rd_ptr_in_wr_q;
    reg  [ADDR_WIDTH:0]   level_wr;
    reg  [ADDR_WIDTH:0]   level_rd;
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) wr_ptr_in_rd_q <= {ADDR_WIDTH{1'b0}};
        else           wr_ptr_in_rd_q <= wr_ptr_in_rd;
    end
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) rd_ptr_in_wr_q <= {ADDR_WIDTH{1'b0}};
        else           rd_ptr_in_wr_q <= rd_ptr_in_wr;
    end

    // fill level in write domain (for flow control)
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) level_wr <= {(ADDR_WIDTH+1){1'b0}};
        else           level_wr <= {1'b0, wr_ptr} - {1'b0, rd_ptr_in_wr_q};
    end
    // fill level in read domain (for buffer_low status)
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) level_rd <= {(ADDR_WIDTH+1){1'b0}};
        else           level_rd <= {1'b0, wr_ptr_in_rd_q} - {1'b0, rd_ptr};
    end

    // ---------------- write side state machine ----------------
    localparam [2:0] WS_IDLE  = 3'd0;
    localparam [2:0] WS_REQ   = 3'd1;
    localparam [2:0] WS_FILL  = 3'd2;
    localparam [2:0] WS_DONE  = 3'd3;
    localparam [2:0] WS_END   = 3'd4;
    localparam [2:0] WS_WAIT  = 3'd5;

    // Leave room for one whole sector plus a little for the 2FF pointer delay.
    localparam [ADDR_WIDTH:0] HIGH_WATER =
        (1 << ADDR_WIDTH) - SAMPLES_PER_SECTOR - 8;

    reg [2:0]  wstate;
    wire wstate_ended = (wstate == WS_END);
    reg [31:0] cur_lba;
    reg [31:0] sectors_read;
    reg [7:0]  lo_byte;             // little-endian pair assembly
    reg        lo_pending;
    // v79锛氭墖鍖轰簨鍔＄湅闂ㄧ嫍銆傛甯镐竴涓墖鍖?鈮?250 us锛?12 B @25 MHz SPI + 鍛戒护寮€閿€锛夛紝
    //   杩欓噷缁?84 ms锛岀瓑涓嶅埌 sd_done 灏变涪鎺夎繖绗斾簨鍔￠噸鏂版潵銆傛病鏈夊畠锛屽彧瑕佹湁涓€涓?done
    //   琚悶锛堜徊瑁佸垏鎹€丼D 鍗″伓鍙戜笉搴旂瓟锛夛紝鍐欎晶灏辨案涔呭仠鍦?WS_FILL锛岄煶涔愬啀涔熶笉浼氬搷銆?
    reg [21:0] stall_cnt;
    wire       stall_ev = (stall_cnt == 22'h3F_FFFF);
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n)
            stall_cnt <= 22'd0;
        else if ((wstate != WS_REQ) && (wstate != WS_FILL))
            stall_cnt <= 22'd0;
        else if (!stall_ev)
            stall_cnt <= stall_cnt + 22'd1;
    end

    // stream_end must mean "the reader has actually consumed all samples",
    // not "the last sector has been read".  ended is set only after WS_END
    // and a drained buffer; the top-level loop restart uses this signal.
    reg        ended;
    reg [2:0]  drain_cnt;

    assign sd_req = (wstate == WS_REQ);
    assign sd_lba = cur_lba;
    assign stream_active = play_enable && !ended;
    assign stream_end = ended;
    assign buffer_low = (level_rd < (1 << (ADDR_WIDTH-2))); // < 25%
    assign player_idle = (wstate == WS_IDLE);

    // -----------------------------------------------------------------------
    // v79锛歳estart 璺ㄦ椂閽熷煙鎷変几
    //   restart 鏉ヨ嚜 50 MHz 鍩熺殑 1 鎷嶈剦鍐诧紙20 ns锛夛紝video_clk 25 MHz锛?0 ns锛夌洿鎺ラ噰鏍?
    //   浼?鐪嬪緱鍒?0/1/2 娆?锛岃鎸囬拡鏈夊彲鑳戒笉璺熺潃娓呴浂 鈥斺€?鍐欐寚閽堝凡缁忓洖 0銆佽鎸囬拡杩樺仠鍦?
    //   鑰佷綅缃紝涓よ竟瀵规寚閽堢殑鍒ゆ柇浼氱煭鏆傞敊浣嶏紙鍚埌涓€灏忔鏃ф暟鎹?鏉傞煶锛夈€?
    //   杩欓噷鎶?restart 鎷夊鍒?16 鎷?sd_clk锛?20 ns锛夛紝鍐嶅幓鍚屾鍒拌鏃堕挓鍩熴€?
    // -----------------------------------------------------------------------
    reg [3:0] restart_hold;
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n)              restart_hold <= 4'd0;
        else if (restart)           restart_hold <= 4'hF;
        else if (restart_hold != 4'd0) restart_hold <= restart_hold - 4'd1;
    end
    wire restart_win = restart | (restart_hold != 4'd0);

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wstate         <= WS_IDLE;
            cur_lba        <= 32'd0;
            sectors_read   <= 32'd0;
            wr_ptr         <= {ADDR_WIDTH{1'b0}};
            lo_pending     <= 1'b0;
            lo_byte        <= 8'd0;
            ended          <= 1'b0;
        drain_cnt      <= 3'd0;
        buf_we         <= 1'b0;
        buf_din        <= 16'd0;
        buf_waddr      <= {ADDR_WIDTH{1'b0}};
        rd_gray_sync1  <= {ADDR_WIDTH{1'b0}};
            rd_gray_sync2  <= {ADDR_WIDTH{1'b0}};
            rd_gray        <= {ADDR_WIDTH{1'b0}};
        end else if (restart_win) begin
            wstate         <= WS_IDLE;
            cur_lba        <= 32'd0;
            sectors_read   <= 32'd0;
            wr_ptr         <= {ADDR_WIDTH{1'b0}};
            lo_pending     <= 1'b0;
            lo_byte        <= 8'd0;
            ended          <= 1'b0;
            drain_cnt      <= 3'd0;
        end else begin
            buf_we <= 1'b0;
            // gray-code sync of rd_ptr into wr domain
            rd_gray      <= to_gray(rd_ptr);
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;

            case (wstate)
            WS_IDLE: begin
                if (play_enable && start_lba != 32'd0 && total_sectors != 32'd0) begin
                    cur_lba      <= start_lba;
                    sectors_read <= 32'd0;
                    wr_ptr       <= {ADDR_WIDTH{1'b0}};
                    lo_pending   <= 1'b0;
                    wstate       <= WS_REQ;
                end
            end
            WS_REQ: begin
                if (stall_ev) begin
                    wstate <= WS_IDLE;          // 鐪嬮棬鐙楋細鎬荤嚎涓€鐩翠笉绌洪棽锛屼粠澶村啀鏉?
                end else if (!play_enable) begin
                    wstate <= WS_IDLE;
                end else if (!sd_busy) begin
                    wstate  <= WS_FILL;
                end
            end
            WS_FILL: begin
                if (stall_ev) begin
                    // 看门狗：等不到自己的 sd_done（被别的请求吞了/卡一直不应答）
                    wstate     <= WS_IDLE;
                    lo_pending <= 1'b0;
                end else begin
                if (sd_valid) begin
                    if (!lo_pending) begin
                        lo_byte    <= sd_byte;
                        lo_pending <= 1'b1;
                    end else begin
                        buf_we         <= 1'b1;
                        buf_din        <= {sd_byte, lo_byte};
                        buf_waddr      <= wr_ptr;
                        wr_ptr         <= wr_ptr + 1'b1;
                        lo_pending     <= 1'b0;
                    end
                end
                if (sd_done) begin
                    if (sd_error != 8'd0) begin
                        wstate <= WS_END;  // sector error: stop streaming
                    end else begin
                        sectors_read <= sectors_read + 1'b1;
                        cur_lba      <= cur_lba + 1'b1;
                        if (!play_enable) begin
                            wstate <= WS_IDLE;
                        end else if (sectors_read + 1'b1 >= total_sectors) begin
                            wstate <= WS_END;
                        end else if (level_wr < HIGH_WATER) begin
                            wstate <= WS_REQ;
                        end else begin
                            wstate <= WS_WAIT;   // buffer nearly full: wait
                        end
                    end
                end
                end
            end
            WS_DONE: wstate <= WS_REQ;  // unused, reserved
            WS_WAIT: begin
                if (!play_enable)
                    wstate <= WS_IDLE;
                else if (level_wr < HIGH_WATER)
                    wstate <= WS_REQ;
            end
            WS_END: begin
                // stay ended until play_enable drops
                if (!play_enable)
                    wstate <= WS_IDLE;
            end
            default: wstate <= WS_IDLE;
            endcase

            // Drained end: WS_END only means the last sector was read.
            // Wait for the read pointer to catch the write pointer
            // (level_wr == 0) plus a few cycles for the read-side pipeline,
            // so the top-level loop restart cannot discard residual samples.
            if (!play_enable) begin
                ended     <= 1'b0;
                drain_cnt <= 3'd0;
            end else if (wstate == WS_END) begin
                if (level_wr == 0) begin
                    if (drain_cnt == 3'd7)
                        ended <= 1'b1;
                    else
                        drain_cnt <= drain_cnt + 3'd1;
                end else begin
                    drain_cnt <= 3'd0;
                    ended     <= 1'b0;
                end
            end else begin
                ended     <= 1'b0;
                drain_cnt <= 3'd0;
            end
        end
    end

    // ---------------- read side ----------------
    // v79锛歳estart_win 鍦?sd_clk 鍩熷凡鏈?16 鎷嶅搴︼紝杩欓噷鍐嶆墦涓ゆ媿鍚屾鍒?video_clk 鍩燂紝
    //   璇绘寚閽堜笌鍐欐寚閽堟墠鑳戒繚璇?鍚屼竴娆?restart 鍙屾柟閮界湅鍒?銆?
    reg rst_rd1, rst_rd2;
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rst_rd1 <= 1'b0;
            rst_rd2 <= 1'b0;
        end else begin
            rst_rd1 <= restart_win;
            rst_rd2 <= rst_rd1;
        end
    end
    wire restart_rd = rst_rd2;

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr         <= {ADDR_WIDTH{1'b0}};
            sample_out     <= 16'sd0;
            sample_valid   <= 1'b0;
            sample_counter <= 32'd0;
            wr_gray_sync1  <= {ADDR_WIDTH{1'b0}};
            wr_gray_sync2  <= {ADDR_WIDTH{1'b0}};
            wr_gray        <= {ADDR_WIDTH{1'b0}};
            wstate_sync1   <= 3'd0;
            wstate_sync2   <= 3'd0;
        end else if (restart_rd) begin
            rd_ptr         <= {ADDR_WIDTH{1'b0}};
            sample_out     <= 16'sd0;
            sample_valid   <= 1'b0;
            sample_counter <= 32'd0;
        end else begin
            // gray-code sync of wr_ptr into rd domain
            wr_gray      <= to_gray(wr_ptr);
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
            wstate_sync1 <= wstate;
            wstate_sync2 <= wstate_sync1;

            sample_valid <= 1'b0;

            // v60 的读侧策略：缓冲里够一个扇区（256 样本）才开始放，避免“刚起播/刚换曲
            //   时缓冲只有几个样本”造成的欠载截断（听感上就是连续的“滋啦/咔哒”）。
            //   写侧进入 WS_END / WS_WAIT（收尾、缓冲将满）时只要还有数据就继续放，
            //   保证最后一段不丢。
            if (sample_tick && sample_ready) begin
                if ((level_rd >= SAMPLES_PER_SECTOR) ||
                    (((wstate_sync2 == WS_END) || (wstate_sync2 == WS_WAIT)) && (level_rd != 0))) begin
                    sample_out   <= buf_q;
                    rd_ptr       <= rd_ptr + 1'b1;
                    sample_valid <= 1'b1;
                    sample_counter <= sample_counter + 1'b1;
                end else begin
                    // 缓冲不足：补静音（sample_valid 仍然给，下游不会停）
                    sample_out   <= 16'sd0;
                    sample_valid <= 1'b1;
                end
            end
            if (!play_enable) begin
                rd_ptr         <= {ADDR_WIDTH{1'b0}};
                sample_counter <= 32'd0;
            end
        end
    end
endmodule
