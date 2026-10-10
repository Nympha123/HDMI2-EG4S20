`timescale 1ns/1ps

module media_frame_loader #(
    parameter integer ADDR_WIDTH = 21,
    parameter integer IMAGE_WORDS = 307200,
    parameter integer FIFO_DEPTH = 512,
    parameter integer BURST_SIZE = 128,
    parameter integer STALL_TIMEOUT = 65535
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  load_start,
    input  wire [1:0]            image_index,
    input  wire                  pixel_valid,
    input  wire [23:0]           pixel_rgb,
    input  wire                  frame_commit,
    input  wire [7:0]            decode_error,
    output wire                  load_busy,
    output reg                   load_done,
    output reg  [3:0]            image_complete,
    output reg  [7:0]            memory_error,
    input  wire                  controller_init_done,
    input  wire                  controller_busy,
    input  wire                  refresh_active,
    // 第八讲：读侧是否正在突发。写侧只在读侧空闲时"开始"一个新突发，
    // 对应官方 frame_fifo_write 的 `~App_rd_busy` 条件（避免读写同时打 SDRAM 控制器）。
    input  wire                  reader_active,
    output reg                   app_wr_en,
    // 第八讲：本模块是否正在写突发（= 官方 O_wr_busy 语义），供读侧做互斥
    output wire                  wr_burst_active,
    output reg  [ADDR_WIDTH-1:0] app_wr_addr,
    output reg  [3:0]            app_wr_mask,
    output reg  [31:0]           app_wr_data
);
    localparam ERR_NONE          = 8'h00;
    localparam ERR_NOT_ACTIVE    = 8'h41;
    localparam ERR_FIFO_OVERFLOW = 8'h42;
    localparam ERR_PIXEL_COUNT   = 8'h43;
    localparam ERR_DECODE        = 8'h44;
    localparam ERR_SHORT_FRAME   = 8'h45;
    localparam ERR_WRITE_STALL   = 8'h46;

    localparam integer PTR_WIDTH = (FIFO_DEPTH <= 2) ? 1 : $clog2(FIFO_DEPTH);
    localparam [PTR_WIDTH:0] EFFECTIVE_BURST =
        (BURST_SIZE < FIFO_DEPTH) ? BURST_SIZE : FIFO_DEPTH;
    localparam [ADDR_WIDTH-1:0] BANK0_BASE = 0;
    localparam [ADDR_WIDTH-1:0] BANK1_BASE = IMAGE_WORDS;
    localparam [ADDR_WIDTH-1:0] BANK2_BASE = IMAGE_WORDS * 2;
    localparam [ADDR_WIDTH-1:0] BANK3_BASE = IMAGE_WORDS * 3;

    // ===== 第八讲：垂直翻转（等效官方 frame_fifo_write 的 WRITE_V_FLIP=1）=====
    // BMP 的行是自下而上存储，显示自下而上扫描，故写入时按"行倒序、行内升序"落盘：
    //   起始地址 = 最后一行的行首；行内 +1 递增；行末跳回上一行（-LINE_JUMP）。
    // 常量与官方完全一致：FIRST_ADDR_OFFSET=(H-1)*W, LINE_JUMP=W*2-1。
    // 关键：突发内部地址始终递增（曾用"整帧倒序"实现，实测导致全黑，见 修改记录.txt 第十节）。
    localparam integer FRAME_WIDTH = 640;
    localparam [ADDR_WIDTH-1:0] VFLIP_FIRST_ADDR_OFFSET = IMAGE_WORDS - FRAME_WIDTH;
    localparam [ADDR_WIDTH-1:0] VFLIP_LINE_JUMP         = (FRAME_WIDTH * 2) - 1;
    localparam [9:0]            VFLIP_ROW_LAST_X        = FRAME_WIDTH - 1;
    reg [ADDR_WIDTH-1:0] wr_addr_r;
    reg [9:0]            vflip_x;

    reg active;
    reg [1:0] active_image;
    reg commit_seen;
    reg [31:0] pixels_received;
    reg [31:0] pixels_written;
    reg [31:0] stall_count;
    reg [31:0] fifo_mem [0:FIFO_DEPTH-1];
    reg [PTR_WIDTH-1:0] wr_ptr;
    reg [PTR_WIDTH-1:0] rd_ptr;
    reg [PTR_WIDTH:0] fifo_count;
    reg burst_active;
    reg [PTR_WIDTH:0] burst_remaining;
    wire pop_allowed;
    wire push_allowed;
    wire start_burst;
    wire [PTR_WIDTH:0] next_burst_words;

    assign load_busy = active;

    // ===== Lesson-8 C6: periodic re-preload used as a data refresh =====
    // This board's SDRAM gets no effective auto-refresh (2-3 min retention observed,
    // and Sdr_init_ref_ba is reported undriven inside the encrypted controller).
    // Writes recharge the accessed rows, so every 60 s clear all four completion
    // flags: sd_card_bmp then re-loads the four banks through the proven preload
    // path. Cost: ~1 s of frozen display per minute.
    localparam [32:0] REFRESH_PERIOD = 33'd2_000_000_000;   // 60 s @ 100 MHz
    reg [32:0] refresh_cnt;
    reg        refresh_request;
    reg  [1:0] refresh_idx;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            refresh_idx <= 2'd0;
        else if (refresh_request)
            refresh_idx <= refresh_idx + 1'b1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            refresh_cnt     <= 33'd0;
            refresh_request <= 1'b0;
        end else begin
            refresh_request <= 1'b0;
            if (!active) begin
                if (refresh_cnt >= REFRESH_PERIOD - 1'b1) begin
                    refresh_cnt     <= 33'd0;
                    refresh_request <= 1'b1;
                end else begin
                    refresh_cnt <= refresh_cnt + 1'b1;
                end
            end
        end
    end
    // 突发级忙标志（与 reader 侧的 rd_burst_active 配对使用）
    assign wr_burst_active = burst_active;
    // The inherited controller consumes a continuous App_wr_en burst and
    // handles busy/refresh internally. Those status outputs are not per-word
    // ready signals and must not split an active write burst.
    assign start_burst = active && controller_init_done && !burst_active &&
                         !reader_active &&
                         fifo_count != 0 &&
                         (fifo_count >= EFFECTIVE_BURST || commit_seen);
    assign next_burst_words = (fifo_count >= EFFECTIVE_BURST) ?
                              EFFECTIVE_BURST : fifo_count;
    assign pop_allowed = active && controller_init_done && burst_active &&
                         fifo_count != 0;
    assign push_allowed = active && pixel_valid &&
                          (fifo_count < FIFO_DEPTH || pop_allowed);

    function [ADDR_WIDTH-1:0] bank_base;
        input [1:0] index;
        begin
            case (index)
                2'd0: bank_base = BANK0_BASE;
                2'd1: bank_base = BANK1_BASE;
                2'd2: bank_base = BANK2_BASE;
                default: bank_base = BANK3_BASE;
            endcase
        end
    endfunction

    task fail_load;
        input [7:0] code;
        begin
            memory_error <= code;
            active <= 1'b0;
            burst_active <= 1'b0;
            burst_remaining <= 0;
            load_done <= 1'b1;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active <= 1'b0;
            active_image <= 2'd0;
            commit_seen <= 1'b0;
            pixels_received <= 32'd0;
            pixels_written <= 32'd0;
            stall_count <= 32'd0;
            wr_ptr <= {PTR_WIDTH{1'b0}};
            rd_ptr <= {PTR_WIDTH{1'b0}};
            fifo_count <= {(PTR_WIDTH+1){1'b0}};
            burst_active <= 1'b0;
            burst_remaining <= 0;
            load_done <= 1'b0;
            image_complete <= 4'd0;
            memory_error <= ERR_NONE;
            app_wr_en <= 1'b0;
            app_wr_addr <= {ADDR_WIDTH{1'b0}};
            wr_addr_r <= {ADDR_WIDTH{1'b0}};
            vflip_x <= 10'd0;
            app_wr_mask <= 4'b0000;
            app_wr_data <= 32'd0;
        end else begin
            load_done <= 1'b0;
            app_wr_en <= 1'b0;

            if (load_start && !active) begin
                active <= 1'b1;
                active_image <= image_index;
                // 第八讲：从"最后一行行首"开始写（垂直翻转的起点）
                wr_addr_r <= bank_base(image_index) + VFLIP_FIRST_ADDR_OFFSET;
                vflip_x   <= 10'd0;
                commit_seen <= 1'b0;
                pixels_received <= 32'd0;
                pixels_written <= 32'd0;
                stall_count <= 32'd0;
                wr_ptr <= {PTR_WIDTH{1'b0}};
                rd_ptr <= {PTR_WIDTH{1'b0}};
                fifo_count <= {(PTR_WIDTH+1){1'b0}};
                burst_active <= 1'b0;
                burst_remaining <= 0;
                memory_error <= ERR_NONE;
                case (image_index)
                    2'd0: image_complete[0] <= 1'b0;
                    2'd1: image_complete[1] <= 1'b0;
                    2'd2: image_complete[2] <= 1'b0;
                    default: image_complete[3] <= 1'b0;
                endcase
            end

            // C6: ?????????? ? ?? sd_card_bmp ???????=???
            if (1'b0 && refresh_request)   // C6 disabled: background sweep now provides the refresh
                image_complete[refresh_idx] <= 1'b0;

            if (active) begin
                if (decode_error != 0) begin
                    fail_load(ERR_DECODE);
                end else if (pixel_valid && pixels_received >= IMAGE_WORDS) begin
                    fail_load(ERR_PIXEL_COUNT);
                end else if (pixel_valid && !push_allowed) begin
                    fail_load(ERR_FIFO_OVERFLOW);
                end else begin
                    if (start_burst) begin
                        burst_active <= 1'b1;
                        burst_remaining <= next_burst_words;
                    end

                    if (push_allowed) begin
                        // 计数用完整条件（含 FIFO 未满判定），保证像素数与 FIFO 记账一致
                        pixels_received <= pixels_received + 1'b1;
                    end

                    // 第八讲时序优化：RAM 写使能只依赖 active/pixel_valid 两个寄存器，
                    // 不再经过 fifo_count 的比较/或逻辑——综合与布线后该路径
                    // （fifo_count_reg -> 推断 RAM 的 e）长期是 sd_card_clk 域最差路径。
                    // 溢出保护仍由上面的 push_allowed 计数侧承担；FIFO 真满时本已属
                    // ERR_FIFO_OVERFLOW 失败路径，多写一个陈旧项不影响结果。
                    if (active && pixel_valid) begin
                        fifo_mem[wr_ptr] <= {8'h00, pixel_rgb};
                        wr_ptr <= wr_ptr + 1'b1;
                    end

                    if (pop_allowed) begin
                        app_wr_en <= 1'b1;
                        // 第八讲：垂直翻转（行倒序、行内升序），地址寄存器由下方规则递增
                        app_wr_addr <= wr_addr_r;
                        app_wr_data <= fifo_mem[rd_ptr];
                        app_wr_mask <= 4'b0000;
                        rd_ptr <= rd_ptr + 1'b1;
                        pixels_written <= pixels_written + 1'b1;
                        stall_count <= 32'd0;
                        if (vflip_x == VFLIP_ROW_LAST_X) begin
                            vflip_x   <= 10'd0;
                            wr_addr_r <= wr_addr_r - VFLIP_LINE_JUMP;   // 行末：跳回上一行行末
                        end else begin
                            vflip_x   <= vflip_x + 10'd1;
                            wr_addr_r <= wr_addr_r + 1'b1;              // 行内：递增
                        end
                        if (burst_remaining == 1) begin
                            burst_active <= 1'b0;
                            burst_remaining <= 0;
                        end else begin
                            burst_remaining <= burst_remaining - 1'b1;
                        end
                    end else if (fifo_count != 0 &&
                                 (commit_seen || fifo_count >= EFFECTIVE_BURST)) begin
                        if (stall_count == STALL_TIMEOUT)
                            fail_load(ERR_WRITE_STALL);
                        else
                            stall_count <= stall_count + 1'b1;
                    end else begin
                        stall_count <= 32'd0;
                    end

                    case ({push_allowed, pop_allowed})
                        2'b10: fifo_count <= fifo_count + 1'b1;
                        2'b01: fifo_count <= fifo_count - 1'b1;
                        default: fifo_count <= fifo_count;
                    endcase

                    if (frame_commit)
                        commit_seen <= 1'b1;

                    if (commit_seen && fifo_count == 0 && !pop_allowed &&
                        !burst_active) begin
                        if (pixels_received != IMAGE_WORDS || pixels_written != IMAGE_WORDS) begin
                            fail_load(ERR_SHORT_FRAME);
                        end else begin
                            case (active_image)
                                2'd0: image_complete[0] <= 1'b1;
                                2'd1: image_complete[1] <= 1'b1;
                                2'd2: image_complete[2] <= 1'b1;
                                default: image_complete[3] <= 1'b1;
                            endcase
                            active <= 1'b0;
                            load_done <= 1'b1;
                        end
                    end
                end
            end else if (pixel_valid) begin
                memory_error <= ERR_NOT_ACTIVE;
            end
        end
    end
endmodule
