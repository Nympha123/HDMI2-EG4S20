`timescale 1ns/1ps

// ===========================================================================
// 第九讲：底部滚动字幕叠加（本工程版 · 方案 R：纯 RTL 字库 ROM）
//
// 与上一版的唯一区别 = 字形来源：
//   上一版：模块内硬编码 5x7 ASCII 表 + 11 个 16x16 汉字 localparam
//   本  版：读 font_rom（纯 RTL ROM，数据由 al_ip\FONT_ROM.mif 转换来的
//           font_rom.hex，176 槽 x 16 行，16x16 点阵）
// 其余一律不动：端口、滚动、字符格几何、底带、配色。
//
// 槽位语义（与其 FONT_ROM.mif 一致）：
//   0x00 = 空槽（强制不画）        0x20 = 空格（强制不画）
//   0x01..0x0F = 菜单新增 15 汉字   0x20..0x7E = ASCII（槽号 = ASCII 码本身）
//   0x80..0xAF = 48 个汉字
// 取字地址： addr = 槽号 * 16 + (15 - 显示行)
//
// 读延迟：本模块的 ROM 只有 **1 级输出寄存**（见 font_rom.v），所以像素侧
//   判定信号只需延迟 **1 拍** 即可与字形数据对齐（上一版用 TD IP 时是 2 拍）。
// ===========================================================================
module subtitle_overlay #(
    parameter integer H_ACTIVE = 640,
    parameter integer SUB_Y    = 430,
    parameter integer CELL_W   = 8,      // 兼容参数（未使用）
    parameter integer SCROLL_STEP = 2
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_start,
    input  wire        de,
    input  wire [23:0] rgb_in,
    input  wire [11:0] pixel_x,
    input  wire [11:0] pixel_y,
    input  wire [191:0] text,
    input  wire [5:0]  length,
    input  wire        enable,
    output wire [23:0] rgb_out,
    output wire        overlay_active
);
    localparam integer SCROLL_CYCLE = H_ACTIVE + 128;
    localparam integer CELL_W_S = 16;
    localparam integer CELL_H_S = 18;

    // -------- 滚动位置：每帧左移 SCROLL_STEP 像素 --------
    reg [10:0] scroll_pos;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            scroll_pos <= 11'd0;
        else if (frame_start) begin
            if (scroll_pos + SCROLL_STEP >= SCROLL_CYCLE)
                scroll_pos <= 11'd0;
            else
                scroll_pos <= scroll_pos + SCROLL_STEP[10:0];
        end
    end

    wire [11:0] stream_x_full = pixel_x + {1'b0, scroll_pos};
    wire [11:0] stream_x = (stream_x_full >= SCROLL_CYCLE[11:0])
                           ? (stream_x_full - SCROLL_CYCLE[11:0]) : stream_x_full;

    // -------- 字符数与文本宽度（帧边界锁存） --------
    wire [4:0]  nchars_c = (length > 6'd24) ? 5'd24 : {1'b0, length[4:0]};
    wire [11:0] text_w_c = {6'd0, nchars_c} << 4;
    reg  [4:0]  nchars_q;
    reg  [11:0] text_w_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nchars_q <= 5'd0;
            text_w_q <= 12'd0;
        end else if (frame_start) begin
            nchars_q <= nchars_c;
            text_w_q <= text_w_c;
        end
    end
    wire [4:0]  nchars = nchars_q;
    wire [11:0] text_w = text_w_q;

    wire in_band_y = (pixel_y >= SUB_Y[11:0]) && (pixel_y < (SUB_Y[11:0] + CELL_H_S[11:0]));

    wire [4:0]  cidx = stream_x[8:4];       // 第几个字符
    wire [3:0]  col  = stream_x[3:0];       // 字内列号 0..15
    wire [11:0] dy   = pixel_y - SUB_Y[11:0];
    wire [7:0]  ch   = text[{cidx, 3'b000} +: 8];   // 槽号

    // -------- 字库 ROM：addr = 槽号*16 + (15 - 行) --------
    wire [3:0]  rom_row  = dy[3:0];
    wire [11:0] rom_addr = ({4'b0, ch} << 4) + {8'b0, (4'd15 - rom_row)};
    wire [15:0] rom_row_bits;
    font_rom u_font_rom (
        .clk  (clk),
        .addr (rom_addr),
        .dout (rom_row_bits)
    );

    // -------- 1 拍流水：像素侧判定与 ROM 数据对齐 --------
    wire qual_c = enable && de && in_band_y && (dy < 12'd16) &&
                  (stream_x < text_w) && (cidx < nchars) &&
                  (ch != 8'h00) && (ch != 8'h20);
    reg qual_d;
    reg [3:0] col_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            qual_d <= 1'b0;
            col_d  <= 4'd0;
        end else begin
            qual_d <= qual_c;
            col_d  <= col;
        end
    end

    wire hit = qual_d && rom_row_bits[4'd15 - col_d];

    // -------- 底带与配色 --------
    wire band = enable && de && in_band_y &&
                (pixel_x >= 12'd8) && (pixel_x < (H_ACTIVE[11:0] - 12'd8));

    assign rgb_out        = hit ? 24'h000000 : (band ? 24'hE8EEF2 : rgb_in);
    assign overlay_active = hit || band;

endmodule
