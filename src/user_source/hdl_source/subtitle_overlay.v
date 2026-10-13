`timescale 1ns/1ps

// ===========================================================================
// 第九讲：底部滚动字幕叠加（本工程版）
//
// 结构（与参考 promax_text_overlay 同思路，仅做本工程适配）：
//   stream_x = (pixel_x + scroll_pos) mod (H_ACTIVE+128)   —— 每帧左移 SCROLL_STEP 像素
//   每个字符占 16x16 一格（CELL_W_S x CELL_H_S = 16 x 18，下方留 2 行）
//   文本 text[191:0] = 最多 24 个 8 位字符；length = 实际字符数（>24 截到 24）
//   颜色：文字 24'h000000（黑），底带 24'hE8EEF2（浅灰），底带左右各留 8px
//
// ---------------------------------------------------------------------------
// 本次改动（③-b'，移植自杨竹平版字幕模块的"字库 ROM"做法，端口保持不变）：
//   1) 字形不再用硬编码表（原 CN_GLYPH_* + 5x7 ASCII case），改为读
//      al_ip\FONT_ROM（TD ROM IP，由 FONT_ROM.ipc + FONT_ROM.mif 生成）：
//          addr = code * 16 + (15 - row)     code = 8 位字符槽位号
//      槽位语义（按其 FONT_ROM.mif 逐槽核对）：
//          0x20..0x7E = ASCII（槽位号就是 ASCII 码本身；数字 d -> 0x30+d，'/' -> 0x2F）
//          0x80..0xAF = 48 个汉字（0x80 + i）
//          ★ 不要再写成 "0x20 + d" —— 那是乱码的根因之一。
//   2) ★ FONT_ROM 的读延迟是 **2 拍**（SP 寄存地址 1 拍 + REGMODE_A=OUTREG 输出寄存 1 拍），
//      不是 1 拍。因此：地址**当拍直接送 ROM**（不要再额外寄存，否则变 3 拍），
//      像素侧与"是否是字符像素"的判定信号统一延迟 2 拍 —— 这样 rom_row_bits 与
//      列号 col_d2 属于**同一个像素**。若不延迟，字形会比列号慢 1 像素，把左邻
//      汉字第 0 列的笔画画到本字格第一列 —— 板上表现就是"每个汉字旁边多一个小点"。
//   3) 0x00（空槽）与 0x20（空格）强制不画，防止字库里这两槽万一有内容时字间冒点。
// ===========================================================================
module subtitle_overlay #(
    parameter integer H_ACTIVE = 640,   // 水平有效像素
    parameter integer SUB_Y    = 430,   // 字幕带顶部 Y
    parameter integer CELL_W   = 8,     // 兼容参数（当前未使用）
    parameter integer SCROLL_STEP = 2   // 每帧左移像素数
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_start,     // 一帧开始（用 reader_frame_start）
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

    // ---------------- 滚动位置（每帧推进，到周期末回绕） ----------------
    localparam integer SCROLL_CYCLE = H_ACTIVE + 128;
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

    // ---------------- 字符格几何 ----------------
    localparam integer CELL_W_S = 16;      // 字符格宽
    localparam integer CELL_H_S = 18;      // 字符格高（16 行字形 + 2 行留白）

    // 字符数与文本宽度在帧边界锁存（避免帧内变化造成抖动）
    wire [4:0]  nchars_c = (length > 6'd24) ? 5'd24 : {1'b0, length[4:0]};
    wire [11:0] text_w_c = {6'd0, nchars_c} << 4;   // nchars * 16
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

    wire [4:0]  cidx = stream_x[8:4];       // 第几个字符（16 像素一格）
    wire [3:0]  col  = stream_x[3:0];       // 字内列号 0..15
    wire [11:0] dy   = pixel_y - SUB_Y[11:0];

    // ---------------- 取字符槽位号 ----------------
    wire [7:0]  ch = text[{cidx, 3'b000} +: 8];

    // ---------------- 字库 ROM：addr = code*16 + (15 - row) ----------------
    wire [3:0]  rom_row  = dy[3:0];                                   // 0..15
    wire [11:0] rom_addr = ({4'b0, ch} << 4) + {8'b0, (4'd15 - rom_row)};
    wire [15:0] rom_row_bits;
    FONT_ROM u_font_rom (
        .doa   (rom_row_bits),
        .addra (rom_addr),
        .ocea  (1'b1),
        .rsta  (1'b0),
        .clka  (clk)
    );

    // ---------------- 2 拍流水线：把"像素侧判定"与 ROM 数据对齐（FIX 14） ----------------
    wire qual_c = enable && de && in_band_y && (dy < 12'd16) &&
                  (stream_x < text_w) && (cidx < nchars) &&
                  (ch != 8'h00) && (ch != 8'h20);
    reg qual_d1, qual_d2;
    reg [3:0] col_d1, col_d2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            qual_d1 <= 1'b0; qual_d2 <= 1'b0;
            col_d1  <= 4'd0; col_d2  <= 4'd0;
        end else begin
            qual_d1 <= qual_c;   qual_d2 <= qual_d1;
            col_d1  <= col;      col_d2  <= col_d1;
        end
    end

    // 字形像素：bit15 对应最左列
    wire hit = qual_d2 && rom_row_bits[4'd15 - col_d2];

    // ---------------- 底带与配色 ----------------
    wire band = enable && de && in_band_y &&
                (pixel_x >= 12'd8) && (pixel_x < (H_ACTIVE[11:0] - 12'd8));

    assign rgb_out        = hit ? 24'h000000 : (band ? 24'hE8EEF2 : rgb_in);
    assign overlay_active = hit || band;

endmodule
