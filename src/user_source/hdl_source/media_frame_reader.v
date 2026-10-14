`timescale 1ns/1ps

module media_frame_reader #(
    parameter integer ADDR_WIDTH = 21,
    parameter integer IMAGE_WORDS = 307200,
    parameter integer FIFO_DEPTH = 512,
    parameter integer FIFO_MARGIN = 8,
    parameter integer BURST_SIZE = 128,
    parameter integer BURST_GAP_CYCLES = 12,
    parameter integer MAX_INFLIGHT_BURSTS = 2,
    parameter integer DIAG_RETURN_PATTERN = 0,
    parameter integer DIAG_SYNTH_STREAM = 0
) (
    input  wire                  mem_clk,
    input  wire                  mem_rst_n,
    input  wire                  controller_init_done,
    input  wire                  controller_busy,
    input  wire                  refresh_active,
    // 第八讲：写侧是否在突发。读侧只在写侧空闲时"开始"一个新突发，
    // 对应官方 frame_fifo_read 的 `~App_wr_busy` 条件（避免读写同时打 SDRAM 控制器）。
    input  wire                  writer_active,
    output wire [3:0]            sweep_dbg,
    output reg                   app_rd_en,
    output reg  [ADDR_WIDTH-1:0] app_rd_addr,
    input  wire                  sdram_rd_valid,
    input  wire [31:0]           sdram_rd_data,

    input  wire                  pix_clk,
    input  wire                  pix_rst_n,
    input  wire                  frame_start,
    input  wire [1:0]            active_index,
    input  wire                  thumb_mode,     // 1 = thumbnail point-read mode (addresses come from src_*)
    input  wire                  thumb_req,      // 1 = fetch one thumbnail source pixel now
    input  wire [1:0]            src_index,      // which bank to fetch from (thumbnail source)
    input  wire [9:0]            src_x,          // source column 0..639
    input  wire [9:0]            src_y,          // source row 0..479
    input  wire                  pixel_consume,
    output wire [23:0]           pixel_rgb,
    output wire                  pixel_valid,
    output reg                   underflow,

    output reg                   reader_busy,
    // 第八讲：本模块是否正在读突发（= 官方 O_rd_busy 语义），供写侧做互斥
    output wire                  rd_burst_active,
    output reg                   frame_read_done,
    output reg  [1:0]            reader_index,
    output reg  [7:0]            reader_error
);
    localparam [7:0] ERR_NONE          = 8'h00;
    localparam [7:0] ERR_FRAME_OVERRUN = 8'h61;
    localparam [7:0] ERR_FIFO_OVERFLOW = 8'h62;
    localparam [7:0] ERR_UNDERFLOW     = 8'h63;
    localparam [7:0] ERR_SHORT_FRAME   = 8'h64;
    localparam integer FIFO_COUNT_W = (FIFO_DEPTH <= 2) ? 1 : $clog2(FIFO_DEPTH);
    localparam integer BURST_COUNT_W =
        (BURST_SIZE < 2) ? 1 : $clog2(BURST_SIZE + 1);
    localparam integer INFLIGHT_COUNT_W =
        (MAX_INFLIGHT_BURSTS * BURST_SIZE < 2) ? 1 :
        $clog2(MAX_INFLIGHT_BURSTS * BURST_SIZE + 1);

    reg request_pending_pix;
    // ===== Lesson-8 C5: bank sweep state =====
    reg  [1:0]            sweep_bank;
    reg  [ADDR_WIDTH-1:0] sweep_off;
    reg  [3:0]            sweep_inflight;
    reg  [15:0]           sweep_hold;
reg  [7:0]            sweep_burst_rem;
    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n)
            sweep_hold <= 16'd0;
        else if (sweep_issue)
            sweep_hold <= 16'd1024;
        else if (sweep_hold != 16'd0)
            sweep_hold <= sweep_hold - 1'b1;
    end
    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n)
            sweep_burst_rem <= 8'd0;
        else if (sweep_armed)
            sweep_burst_rem <= 8'd128;
        else if ((sweep_burst_rem != 8'd0) && sweep_issue)
            sweep_burst_rem <= sweep_burst_rem - 1'b1;
    end
    // Sweep must be issued as its own BURST (same shape as the display burst):
    // single sweep words interleaved between display bursts made the controller
    // fetch one wrong word per interrupted burst -> fixed-position vertical stripes.
    // The sweep may only arm when the display FIFO is nearly FULL: at that moment the
    // display does not need the bus for a while, so the bounded sweep burst cannot
    // starve it. Arming merely on "no display read in flight" was wrong - that state
    // also occurs when the FIFO is running DRY, and blocking the rescue burst there
    // dropped pixels at a fixed stream position (fixed vertical stripes on screen).
    // The sweep must NEVER touch the bank that is currently being displayed:
    // the displayed bank is already refreshed by the display's own reads, and the
    // visible noise proved to follow the sweep's bank traversal. Only the other
    // three banks need background refreshing.
    // fifo_full turned out to gate the sweep off almost permanently (its polarity /
    // threshold does not mean "nearly full" here), which is why making the sweep
    // denser or sparser changed nothing. Display starvation is instead prevented
    // structurally: the sweep is a bounded 128-word burst with a >=1024 cycle
    // hold-off and it never touches the displayed bank.
    wire sweep_armed = (sweep_burst_rem == 8'd0) && (sweep_hold == 16'd0) &&

                       !DIAG_SYNTH_STREAM &&
                       !start_burst && !burst_active_mem && inflight_empty_mem &&
                       // Arm the sweep inside the display's inter-burst gap (gap counter
                       // non-zero). The previous "gap counter == 0" plus "no burst active"
                       // combination could NEVER be satisfied: the display bursts
                       // back-to-back, so at gap==0 the next burst already starts.
                       // The sweep is a bounded 128-word burst, so the display waits at
                       // most ~128 cycles, which its 512-word FIFO absorbs.
                       (burst_gap_count_mem != 0) &&
                       !reload_pending_mem && (fifo_reset_count_mem == 0) &&
                       !writer_active;
    wire sweep_issue = (sweep_burst_rem != 8'd0) || sweep_armed;

    reg request_toggle_pix;
    reg [1:0] request_index_pix;
    reg frame_armed_pix;
    reg [ADDR_WIDTH:0] consumed_count_pix;

    reg request_sync1_mem;
    reg request_sync2_mem;
    reg request_seen_mem;
    reg [1:0] index_sync1_mem;
    reg [1:0] index_sync2_mem;
    reg reload_pending_mem;
    reg [1:0] reload_index_mem;
    reg [2:0] fifo_reset_count_mem;
    reg [ADDR_WIDTH:0] issued_count_mem;
    reg [ADDR_WIDTH:0] returned_count_mem;
    reg [INFLIGHT_COUNT_W-1:0] inflight_count_mem;
    reg inflight_empty_mem /* fehdl keep="true" */;
    reg burst_active_mem;
    reg [BURST_COUNT_W-1:0] burst_issued_mem;
    reg [BURST_COUNT_W-1:0] burst_target_mem;
    reg [7:0] burst_gap_count_mem;
    reg [ADDR_WIDTH:0] diag_written_count_mem;
    reg [9:0] diag_column_mem;
    reg [23:0] diag_rgb_mem;
    reg [1:0] fifo_release_mem;
    reg [1:0] fifo_release_pix;

    wire fifo_reset_request = !mem_rst_n || !pix_rst_n ||
                              (fifo_reset_count_mem != 0);
    wire fifo_reset = fifo_reset_request ||
                      !fifo_release_mem[1] || !fifo_release_pix[1];
    wire fifo_full;
    wire fifo_empty;
    wire fifo_almost_full;
    wire [FIFO_COUNT_W-1:0] fifo_wrusedw;
    wire [31:0] fifo_raw_data;
    wire fifo_raw_valid;
    wire fifo_raw_read_en;
    wire prefetch_valid;
    wire [31:0] prefetch_data;
    wire pixel_pop = pixel_consume && prefetch_valid;
    wire [ADDR_WIDTH:0] inflight_words =
        {{(ADDR_WIDTH+1-INFLIGHT_COUNT_W){1'b0}}, inflight_count_mem};
    wire final_return = returned_count_mem == IMAGE_WORDS - 1;
    wire [ADDR_WIDTH+1:0] reserved_words =
        {{(ADDR_WIDTH+2-FIFO_COUNT_W){1'b0}}, fifo_wrusedw} +
        {{1{1'b0}}, inflight_words};
    localparam integer FULL_BURSTS_ONLY = (IMAGE_WORDS % BURST_SIZE) == 0;
    wire [ADDR_WIDTH:0] remaining_words = IMAGE_WORDS - issued_count_mem;
    wire [ADDR_WIDTH:0] next_burst_words =
        FULL_BURSTS_ONLY ? BURST_SIZE :
        ((remaining_words > BURST_SIZE) ? BURST_SIZE : remaining_words);
    wire [ADDR_WIDTH+2:0] reserved_after_burst =
        {{1{1'b0}}, reserved_words} + {{2{1'b0}}, next_burst_words};
    wire inflight_window_ok = (MAX_INFLIGHT_BURSTS == 1) ?
        inflight_empty_mem :
        ((inflight_words + next_burst_words) <=
         (MAX_INFLIGHT_BURSTS * BURST_SIZE));
    wire fifo_reservation_ok =
        reserved_after_burst <= (FIFO_DEPTH - FIFO_MARGIN);
    reg inflight_window_ok_q;
    reg fifo_reservation_ok_q;
    // Refresh window generator: DRAM reads refresh the accessed row, but rows that
    // are never accessed rely on the controller's auto-refresh. With a continuous
    // read stream the controller rarely gets an idle slot, so untouched banks fade
    // (observed: other images corrupted after >15 min idle while the displayed one
    // stayed clean). Force a short idle window periodically so refresh can run.
    reg [7:0] ref_gap_cnt;
    reg [7:0] ref_idle_cnt;
    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin
            ref_gap_cnt  <= 8'd0;
            ref_idle_cnt <= 8'd0;
        end else if (ref_idle_cnt != 8'd0) begin
            ref_idle_cnt <= ref_idle_cnt - 1'b1;
        end else if (app_rd_en) begin
            if (ref_gap_cnt == 8'd255) begin
                ref_gap_cnt  <= 8'd0;
                ref_idle_cnt <= 8'd63;
            end else begin
                ref_gap_cnt <= ref_gap_cnt + 1'b1;
            end
        end
    end

    wire start_burst = (sweep_burst_rem == 8'd0) && !DIAG_SYNTH_STREAM && reader_busy && controller_init_done &&
                       // 第八讲：读侧也要等写侧空闲。实测放开这条（只让写侧让行）会让
                       // 随机丢点密度明显上升——说明并发访问才是主要腐蚀源，互斥必须保留。
                       !writer_active &&
                       fifo_reset_count_mem == 0 && !burst_active_mem &&
                       burst_gap_count_mem == 0 &&
                       issued_count_mem != IMAGE_WORDS &&
                       inflight_window_ok_q && fifo_reservation_ok_q;
    // ?????????????????????????????
// ?? inflight_empty_mem ???? 1?? 282 ?? bank ???????
// ??????????? inflight_empty_mem ??? 1?reader_index ????? 0?
//   ???"??????? bank?ctrl_active_index ??????????"??
wire issue_allowed = !DIAG_SYNTH_STREAM && reader_busy && burst_active_mem &&
                     !reload_pending_mem;
    wire diag_stream_write = DIAG_SYNTH_STREAM && reader_busy &&
                             !fifo_reset && !fifo_full;
    wire fifo_write_enable = DIAG_SYNTH_STREAM ? diag_stream_write :
                             (sdram_rd_valid && !fifo_reset && !fifo_full && (issued_count_mem != returned_count_mem));
    wire [31:0] fifo_write_data = (DIAG_RETURN_PATTERN || DIAG_SYNTH_STREAM) ?
                                  {8'h00, diag_rgb_mem} : sdram_rd_data;

    always @* begin
        if (diag_column_mem < 10'd80)
            diag_rgb_mem = 24'hffffff;
        else if (diag_column_mem < 10'd160)
            diag_rgb_mem = 24'hffff00;
        else if (diag_column_mem < 10'd240)
            diag_rgb_mem = 24'h00ffff;
        else if (diag_column_mem < 10'd320)
            diag_rgb_mem = 24'h00ff00;
        else if (diag_column_mem < 10'd400)
            diag_rgb_mem = 24'hff00ff;
        else if (diag_column_mem < 10'd480)
            diag_rgb_mem = 24'hff0000;
        else if (diag_column_mem < 10'd560)
            diag_rgb_mem = 24'h0000ff;
        else
            diag_rgb_mem = 24'h000000;
    end

    function [ADDR_WIDTH-1:0] bank_base;
        input [1:0] index;
        begin
            case (index)
                2'd0: bank_base = {ADDR_WIDTH{1'b0}};
                2'd1: bank_base = IMAGE_WORDS;
                2'd2: bank_base = IMAGE_WORDS * 2;
                default: bank_base = IMAGE_WORDS * 3;
            endcase
        end
    endfunction

    // Delay the request by one pixel clock so media_player_control can commit
    // active_index on the frame_start edge before this module captures it.
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            request_pending_pix <= 1'b0;
            request_toggle_pix <= 1'b0;
            request_index_pix <= 2'd0;
            frame_armed_pix <= 1'b0;
            consumed_count_pix <= 0;
            underflow <= 1'b0;
            fifo_release_pix <= 2'b00;
        end else begin
            if (fifo_reset_request)
                fifo_release_pix <= 2'b00;
            else
                fifo_release_pix <= {fifo_release_pix[0], 1'b1};

            if (frame_start) begin
                if (frame_armed_pix && consumed_count_pix != IMAGE_WORDS) begin
                    underflow <= 1'b1;
                end
                consumed_count_pix <= 0;
                request_pending_pix <= 1'b1;
            end else if (request_pending_pix) begin
                request_index_pix <= active_index;
                request_toggle_pix <= ~request_toggle_pix;
                request_pending_pix <= 1'b0;
                frame_armed_pix <= 1'b1;
            end

            if (pixel_consume) begin
                if (prefetch_valid)
                    consumed_count_pix <= consumed_count_pix + 1'b1;
                else if (frame_armed_pix)
                    underflow <= 1'b1;
            end
        end
    end

    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin
            request_sync1_mem <= 1'b0;
            sweep_bank <= 2'd0;
            sweep_off  <= {ADDR_WIDTH{1'b0}};
            sweep_inflight <= 4'd0;
            request_sync2_mem <= 1'b0;
            request_seen_mem <= 1'b0;
            index_sync1_mem <= 2'd0;
            index_sync2_mem <= 2'd0;
            reload_pending_mem <= 1'b0;
            reload_index_mem <= 2'd0;
            fifo_reset_count_mem <= 3'd0;
            issued_count_mem <= 0;
            returned_count_mem <= 0;
            inflight_count_mem <= 0;
            inflight_empty_mem <= 1'b1;
            burst_active_mem <= 1'b0;
            burst_issued_mem <= 0;
            burst_target_mem <= 0;
            burst_gap_count_mem <= 0;
            diag_written_count_mem <= 0;
            diag_column_mem <= 0;
            fifo_release_mem <= 2'b00;
            inflight_window_ok_q <= 1'b1;
            fifo_reservation_ok_q <= 1'b1;
            app_rd_en <= 1'b0;
            app_rd_addr <= 0;
            reader_busy <= 1'b0;
            frame_read_done <= 1'b0;
            reader_index <= 2'd0;
            reader_error <= ERR_NONE;
        end else begin
            if (fifo_reset_request)
                fifo_release_mem <= 2'b00;
            else
                fifo_release_mem <= {fifo_release_mem[0], 1'b1};

            request_sync1_mem <= request_toggle_pix;
            request_sync2_mem <= request_sync1_mem;
            index_sync1_mem <= request_index_pix;
            index_sync2_mem <= index_sync1_mem;
            app_rd_en <= 1'b0;
            frame_read_done <= 1'b0;
            inflight_window_ok_q <= inflight_window_ok;
            fifo_reservation_ok_q <= fifo_reservation_ok;

            if (fifo_reset_count_mem != 0)
                fifo_reset_count_mem <= fifo_reset_count_mem - 1'b1;
            if (burst_gap_count_mem != 0)
                burst_gap_count_mem <= burst_gap_count_mem - 1'b1;

            // In-flight accounting must see ONLY the display traffic.
            // A raw sdram_rd_valid return also covers sweep (refresh) words, which
            // decremented the count without a matching increment and desynchronised
            // inflight_empty_mem -> display bursts stopped -> black screen.
            // A return is a display return iff the display is still expecting one.
            case ({issue_allowed, (sdram_rd_valid && (issued_count_mem != returned_count_mem))})
                2'b10: begin
                    inflight_count_mem <= inflight_count_mem + 1'b1;
                    inflight_empty_mem <= 1'b0;
                end
                2'b01: begin
                    if (!inflight_empty_mem) begin
                        inflight_count_mem <= inflight_count_mem - 1'b1;
                        if (inflight_count_mem == 1)
                            inflight_empty_mem <= 1'b1;
                    end
                end
                2'b11: begin
                    // Issue and return in the same cycle (the normal pipelined case).
                    // Count stays the same, but emptiness must still be evaluated,
                    // otherwise inflight_empty_mem reports "empty" while reads are
                    // actually outstanding (it also used to block the bank reload).
                    if (inflight_count_mem == 1)
                        inflight_empty_mem <= 1'b1;
                    else
                        inflight_empty_mem <= inflight_empty_mem;
                end
                default: begin
                    inflight_count_mem <= inflight_count_mem;
                    inflight_empty_mem <= inflight_empty_mem;
                end
            endcase

            if (request_sync2_mem != request_seen_mem) begin
                request_seen_mem <= request_sync2_mem;
                reload_pending_mem <= 1'b1;
                reload_index_mem <= index_sync2_mem;
                if (reader_busy || !inflight_empty_mem) begin
                    reader_busy <= 1'b0;
                    burst_active_mem <= 1'b0;
                    reader_error <= ERR_FRAME_OVERRUN;
                end
            end

            if (reload_pending_mem && inflight_empty_mem) begin
                reload_pending_mem <= 1'b0;
                reader_index <= reload_index_mem;
                issued_count_mem <= 0;
                returned_count_mem <= 0;
                inflight_count_mem <= 0;
                inflight_empty_mem <= 1'b1;
                burst_active_mem <= 1'b0;
                burst_issued_mem <= 0;
                burst_target_mem <= 0;
                burst_gap_count_mem <= 0;
                diag_written_count_mem <= 0;
                diag_column_mem <= 0;
                fifo_reset_count_mem <= 3'd4;
                reader_busy <= 1'b1;
                reader_error <= ERR_NONE;
            end

            if (start_burst) begin
                burst_active_mem <= 1'b1;
                burst_issued_mem <= 0;
                burst_target_mem <= next_burst_words[BURST_COUNT_W-1:0];
            end

            // ===== Lesson-8 C5: bank sweep for DRAM refresh =====
            // Reads also recharge the accessed row, so sweeping every bank keeps
            // all rows refreshed even if the controller's auto-refresh is starved.
            // Conservative: only issue when the display path is idle, and never
            // overlap the display's in-flight reads (returned words are indistinguishable).
            if (sweep_issue) begin
                if (sweep_off == IMAGE_WORDS[ADDR_WIDTH-1:0] - 1'b1) begin
                    sweep_off <= {ADDR_WIDTH{1'b0}};
                    // Rotate to the next bank, skipping the displayed one. (Blocking
                    // arming with "sweep_bank != reader_index" deadlocked at reset,
                    // where both are 0 -> the sweep never ran at all.)
                    if ((sweep_bank + 2'd1) == reader_index)
                        sweep_bank <= sweep_bank + 2'd2;
                    else
                        sweep_bank <= sweep_bank + 2'd1;
                end else begin
                    sweep_off <= sweep_off + 1'b1;
                end
            end

            // Issue paths are strictly separate:
            //  - display read drives app_rd_addr from the frame counter and is the
            //    ONLY thing that advances issued_count_mem / burst_issued_mem.
            //  - sweep read (DRAM refresh) emits its own address and must not touch
            //    any display accounting: doing so corrupted the frame completion
            //    logic and made "issued != returned" permanently true, which in turn
            //    let sweep words into the display FIFO (the F-state lock-up).
            if (issue_allowed) begin
                app_rd_en   <= 1'b1;
                app_rd_addr <= thumb_mode ? (bank_base(src_index) + (src_y * 10'd640) + src_x)
                                       : (bank_base(reader_index) + issued_count_mem[ADDR_WIDTH-1:0]);
                issued_count_mem <= issued_count_mem + 1'b1;
                burst_issued_mem <= burst_issued_mem + 1'b1;
                if (burst_issued_mem + 1'b1 == burst_target_mem) begin
                    burst_active_mem <= 1'b0;
                    burst_gap_count_mem <= BURST_GAP_CYCLES;
                end
            end else if (sweep_issue) begin
                app_rd_en   <= 1'b1;
                app_rd_addr <= bank_base(sweep_bank) + sweep_off;
            end

            if (sweep_issue)
                sweep_inflight <= sweep_inflight + 1'b1;
            else if ((sweep_inflight != 0) && sdram_rd_valid)
                sweep_inflight <= sweep_inflight - 1'b1;

            if (!DIAG_SYNTH_STREAM && sdram_rd_valid && (issued_count_mem != returned_count_mem)) begin
                returned_count_mem <= returned_count_mem + 1'b1;
                if (fifo_full) begin
                    reader_busy <= 1'b0;
                    burst_active_mem <= 1'b0;
                    reader_error <= ERR_FIFO_OVERFLOW;
                end else if (final_return) begin
                    reader_busy <= 1'b0;
                    burst_active_mem <= 1'b0;
                    frame_read_done <= 1'b1;
                end
            end

            if (DIAG_SYNTH_STREAM && diag_stream_write) begin
                diag_written_count_mem <= diag_written_count_mem + 1'b1;
                diag_column_mem <= (diag_column_mem == 10'd639) ?
                                   10'd0 : diag_column_mem + 1'b1;
                if (diag_written_count_mem == IMAGE_WORDS - 1) begin
                    reader_busy <= 1'b0;
                    frame_read_done <= 1'b1;
                end
            end else if (!DIAG_SYNTH_STREAM && DIAG_RETURN_PATTERN &&
                         sdram_rd_valid) begin
                diag_column_mem <= (diag_column_mem == 10'd639) ?
                                   10'd0 : diag_column_mem + 1'b1;
            end
        end
    end

    rfifo_32_32_512 #(
        .DATA_WIDTH_W(32), .DATA_WIDTH_R(32),
        .ADDR_WIDTH_W(FIFO_COUNT_W), .ADDR_WIDTH_R(FIFO_COUNT_W),
        .AL_FULL_NUM(FIFO_DEPTH-FIFO_MARGIN), .AL_EMPTY_NUM(2),
        .SHOW_AHEAD_EN(1'b0), .OUTREG_EN("NOREG")
    ) u_read_fifo (
        .rst(fifo_reset), .clkw(mem_clk), .clkr(pix_clk),
        .we(fifo_write_enable), .di(fifo_write_data),
        .re(fifo_raw_read_en), .dout(fifo_raw_data), .valid(fifo_raw_valid),
        .full_flag(fifo_full), .empty_flag(fifo_empty),
        .afull(fifo_almost_full), .aempty(),
        .wrusedw(fifo_wrusedw), .rdusedw()
    );

    fifo_prefetch_2 #(.DATA_WIDTH(32)) u_prefetch (
        .clk(pix_clk), .rst(fifo_reset), .raw_empty(fifo_empty),
        .raw_valid(fifo_raw_valid), .raw_data(fifo_raw_data),
        .raw_read_en(fifo_raw_read_en), .consume(pixel_pop),
        .out_valid(prefetch_valid), .out_empty(), .out_data(prefetch_data)
    );

    assign pixel_rgb = prefetch_data[23:0];
    assign pixel_valid = prefetch_valid;
    // 突发级忙标志（与 loader 侧的 wr_burst_active 配对使用）
    assign rd_burst_active = burst_active_mem;
    // Slow, human-readable sweep progress: increments once per COMPLETED 128-word
    // sweep burst. Shown on the 2nd digit from the left, so the value is stable
    // enough to read (the previous packed state changed every cycle and looked
    // static no matter what the sweep did).
    reg [3:0] sweep_done_cnt;
    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n)
            sweep_done_cnt <= 4'd0;
        else if (sweep_issue && (sweep_burst_rem == 8'd1))
            sweep_done_cnt <= sweep_done_cnt + 1'b1;
    end
    assign sweep_dbg = sweep_done_cnt;

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            // The memory-domain error remains authoritative for controller faults.
        end else if (underflow) begin
            // underflow is exported separately; the Top may merge it as 8'h63.
        end
    end

endmodule
