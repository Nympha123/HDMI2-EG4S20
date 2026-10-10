`timescale 1ns/1ps

// ===========================================================================
// 第九讲：状态 OSD 核心（12 位）
//
// 参考实现：参考文件\第九讲：OSD字幕叠加\第9课_OSD字幕叠加\status_osd_overlay.v
// 本工程改写点：
//   1. pixel_x / pixel_y 直接来自 video_timing_ctrl 的 x / y 输出（该模块
//      已保证 de=1 时为有效像素坐标），因此不再需要行计数器重建；
//   2. 位置默认左上角 OSD_X=8 / OSD_Y=8（可用参数覆盖）；
//   3. 显示内容依次为 4 个字符：
//        字符0 = 当前显示 PIC 序号（bank 号 + 1）
//        字符1 = auto 使能显示 'a'，否则显示 'e'
//        字符2 = 错误码高 4 位（十六进制）
//        字符3 = 错误码低 4 位（十六进制）
//   4. 配色沿用参考语义：无错误 = 黄 (12'hFF0)，有错误 = 红 (12'hF44)。
//   5. 状态量在 frame_start（vsync 下降沿）锁存，避免帧内撕裂。
//
// 纯组合 + 寄存器，不依赖任何外部 IP。
// ===========================================================================
module status_osd_overlay #(
    parameter integer OSD_X = 8,
    parameter integer OSD_Y = 8
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_start,      // vsync 下降沿（帧边界）
    input  wire [1:0]  active_index,     // 当前显示 bank（reader_index）
    input  wire        auto_enabled,     // 自动轮播使能
    input  wire [7:0]  error_code,       // 错误码（本项目接 {4'b0, state_code}）
    input  wire        in_de,
    input  wire [11:0] in_rgb,
    input  wire [11:0] pixel_x,
    input  wire [11:0] pixel_y,
    output reg  [11:0] out_rgb,
    output reg         out_de,
    output wire        osd_pixel
);

    reg [1:0] index_q;
    reg       auto_q;
    reg [7:0] error_q;

    reg       osd_hit;
    reg [3:0] char_value;
    reg [2:0] char_row;
    reg [4:0] glyph_row;

    // 帧边界锁存状态，避免 OSD 在帧内变化造成撕裂
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            index_q <= 2'd0;
            auto_q  <= 1'b0;
            error_q <= 8'd0;
        end else if (frame_start) begin
            index_q <= active_index;
            auto_q  <= auto_enabled;
            error_q <= error_code;
        end
    end

    // 5x7 点阵字库（每行 5 位，共 7 行；row=6 为最后一行）
    function [4:0] font_row;
        input [3:0] value;
        input [2:0] row;
        begin
            case (value)
                4'h0: case (row) 0:font_row=5'b11111; 1:font_row=5'b10001; 2:font_row=5'b10001; 3:font_row=5'b10001; 4:font_row=5'b10001; 5:font_row=5'b10001; default:font_row=5'b11111; endcase
                4'h1: case (row) 0:font_row=5'b00100; 1:font_row=5'b01100; 2:font_row=5'b00100; 3:font_row=5'b00100; 4:font_row=5'b00100; 5:font_row=5'b00100; default:font_row=5'b11111; endcase
                4'h2: case (row) 0:font_row=5'b11111; 1:font_row=5'b00001; 2:font_row=5'b00001; 3:font_row=5'b11111; 4:font_row=5'b10000; 5:font_row=5'b10000; default:font_row=5'b11111; endcase
                4'h3: case (row) 0:font_row=5'b11111; 1:font_row=5'b00001; 2:font_row=5'b00001; 3:font_row=5'b11111; 4:font_row=5'b00001; 5:font_row=5'b00001; default:font_row=5'b11111; endcase
                4'h4: case (row) 0:font_row=5'b10001; 1:font_row=5'b10001; 2:font_row=5'b10001; 3:font_row=5'b11111; 4:font_row=5'b00001; 5:font_row=5'b00001; default:font_row=5'b00001; endcase
                4'h5: case (row) 0:font_row=5'b11111; 1:font_row=5'b10000; 2:font_row=5'b10000; 3:font_row=5'b11111; 4:font_row=5'b00001; 5:font_row=5'b00001; default:font_row=5'b11111; endcase
                4'h6: case (row) 0:font_row=5'b11111; 1:font_row=5'b10000; 2:font_row=5'b10000; 3:font_row=5'b11111; 4:font_row=5'b10001; 5:font_row=5'b10001; default:font_row=5'b11111; endcase
                4'h7: case (row) 0:font_row=5'b11111; 1:font_row=5'b00001; 2:font_row=5'b00010; 3:font_row=5'b00100; 4:font_row=5'b01000; 5:font_row=5'b01000; default:font_row=5'b01000; endcase
                4'h8: case (row) 0:font_row=5'b11111; 1:font_row=5'b10001; 2:font_row=5'b10001; 3:font_row=5'b11111; 4:font_row=5'b10001; 5:font_row=5'b10001; default:font_row=5'b11111; endcase
                4'h9: case (row) 0:font_row=5'b11111; 1:font_row=5'b10001; 2:font_row=5'b10001; 3:font_row=5'b11111; 4:font_row=5'b00001; 5:font_row=5'b00001; default:font_row=5'b11111; endcase
                // 'A'：对应自动轮播开（复用 a 字形）
                4'ha: case (row) 0:font_row=5'b01110; 1:font_row=5'b10001; 2:font_row=5'b10001; 3:font_row=5'b11111; 4:font_row=5'b10001; 5:font_row=5'b10001; default:font_row=5'b10001; endcase
                // 'E'：自动轮播关
                4'he: case (row) 0:font_row=5'b11111; 1:font_row=5'b10000; 2:font_row=5'b10000; 3:font_row=5'b11110; 4:font_row=5'b10000; 5:font_row=5'b10000; default:font_row=5'b11111; endcase
                // 'F'：错误提示位（备用）
                4'hf: case (row) 0:font_row=5'b11111; 1:font_row=5'b10000; 2:font_row=5'b10000; 3:font_row=5'b11110; 4:font_row=5'b10000; 5:font_row=5'b10000; default:font_row=5'b10000; endcase
                default: font_row = 5'b00000;
            endcase
        end
    endfunction

    always @* begin
        osd_hit    = 1'b0;
        char_value = 4'h0;
        char_row   = pixel_y[2:0] - OSD_Y[2:0];
        glyph_row  = 5'b00000;

        if (pixel_x >= OSD_X && pixel_x < (OSD_X + 32) &&
            pixel_y >= OSD_Y && pixel_y < (OSD_Y + 8)) begin
            // 每 8 像素一个字符，共 4 个字符
            case ((pixel_x - OSD_X) / 8)
                0: char_value = {2'b00, index_q} + 1'b1;      // PIC 序号（1~4）
                1: char_value = auto_q ? 4'ha : 4'he;         // A = 自动开 / E = 自动关
                2: char_value = error_q[7:4];                 // 错误码高 4 位
                3: char_value = error_q[3:0];                 // 错误码低 4 位
                default: char_value = 4'h0;
            endcase
            glyph_row = font_row(char_value, char_row);
            // 字形宽 5 像素、高 7 行；行内按 (x-OSD_X)%8 选位
            if (((pixel_x - OSD_X) % 8) < 5 && char_row < 7)
                osd_hit = glyph_row[4 - ((pixel_x - OSD_X) % 8)];
        end

        out_de  = in_de;
        out_rgb = in_rgb;
        if (in_de && osd_hit)
            out_rgb = (error_q == 8'd0) ? 12'hff0 : 12'hf44;   // 黄=正常，红=有错误
    end

    assign osd_pixel = osd_hit && in_de;

endmodule
