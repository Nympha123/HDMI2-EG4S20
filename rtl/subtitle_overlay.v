`timescale 1ns/1ps

// ===========================================================================
// ?????????????????????????????????????????????ASCII 5x7???
//
// ???????????????????????????\????????????OSD????????????\???9???_OSD????????????\promax_text_overlay.v
//           ????????????????????? 18x18 ?????????????????????????????????????????????????????????
//             ASCII 5x7 ??????????????????????????????????????????????????????/????????????????????????
//
// ???????????????dst_text[95:0] = 8 ??? 12 ????????????????????????????????????????????????????????? 7 ???
//           ??? ASCII???dst_length[5:0] ?????????????????????>8 ?????? 8 ????????????
// ????????????????????????????????? SUB_Y????????? 430?????????????????? 8px????????? 5px + ?????? 3px??????
// ??????????????????12'hFFF ????????? 24 ????????????????????????????????????????????????????????????
// ???????????????????????????????????????de ???????????????????????????
// ===========================================================================
module subtitle_overlay #(
    parameter integer H_ACTIVE = 640,   // ????????????
    parameter integer SUB_Y    = 430,   // ??????????????? Y
    parameter integer CELL_W   = 8,      // ?????????????????????
    parameter integer SCROLL_STEP = 2    // ??????????????????????????????
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_start,     // ????????????????????? reader_frame_start???
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

    // ------------------------------------------------------------------
    // ???????????????????????? promax_text_overlay ????????????????????????
    //   stream_x = pixel_x + scroll_pos????????? H_ACTIVE+128 ??????
    //   scroll_pos ???????????? SCROLL_STEP????????????????????????????????????
    // ------------------------------------------------------------------
    localparam integer SCROLL_CYCLE = H_ACTIVE + 128;
    reg [10:0] scroll_pos;                       // 0 .. SCROLL_CYCLE-1

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

    // ------------------------------------------------------------------
    // ?????????????????? promax_text_overlay ?????????????????????18px ??? ??? ???????????? 16px???
    //   ASCII ?????? 5x7 ?????? 2 ??? ??? ??? col 3..12??????????????? 3px ?????????
    //   ???????????? dy 2..15????????? 2 ????????????
    //   ????????????????????????????????????????????????????????????????????????
    //   ????????? 16 ?????? 18 ????????????16 ??? 2 ?????????cidx/col ????????????????????????
    //   ??????????????????????????????????????????????????????????????????????????? 18 ????????????
    //   Setup ????????? -630ps/48 ????????????
    // ------------------------------------------------------------------
    localparam integer CELL_W_S = 16;      // ???????????????2 ???????????????????????????
    localparam integer CELL_H_S = 18;      // ????????????

    // ???????????????????????? 8????????????????????????????????????????????????????????????????????????????????????
    // ???????????????????????????????????????
    wire [4:0]  nchars_c = (length > 6'd24) ? 5'd24 : {1'b0, length[4:0]};
    wire [11:0] text_w_c = {6'd0, nchars_c} << 4;   // *16???2 ?????? ??? ?????????
    reg  [4:0]  nchars_q;
    reg  [11:0] text_w_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nchars_q <= 4'd0;
            text_w_q <= 12'd0;
        end else if (frame_start) begin
            nchars_q <= nchars_c;
            text_w_q <= text_w_c;
        end
    end

    wire [4:0]  nchars = nchars_q;
    wire [11:0] text_w = text_w_q;

    // ????????????????????????????????????????????? subtitle_band_pixel ?????????
    wire in_band_y = (pixel_y >= SUB_Y[11:0]) && (pixel_y < (SUB_Y[11:0] + CELL_H_S[11:0]));

    // ????????????????????????????????? 16 ??? ????????????
    wire [4:0]  cidx = stream_x[8:4];           // ???????????? 0..7
    wire [3:0]  col  = stream_x[3:0];            // ????????? 0..15
    wire [4:0]  scol = {1'b0, col};              // ?????????????????????
    wire [11:0] dy   = pixel_y - SUB_Y[11:0];    // ????????????????????? 3 ?????????
    wire [3:0]  srow = dy[3:0];                  // ????????? 0..15

    // ?????? cidx ??? 12 ??????????????? 7 ??????ASCII???
    // ??? 8 ????? subtitle_char ? index*8 +: 8 ???
    // ??? 8 ??????? + ????????????? 24 ???
    wire [7:0] ch = text[{cidx, 3'b000} +: 8];

    // 5x7 ?????????????????? 35 ??? = 7 ??? x 5 ????????????????????? 0 ??????????????????
    localparam [255:0] CN_GLYPH_0 = 256'b0000000110000000000100011000110000011001100110000000110110010000000010011001000000000001100000000111111111111110000000111100000000000111111000000000010110110000000011011001100000111001100011100110000110000010000000011000000000000001100000000000000000000000;
    localparam [255:0] CN_GLYPH_1 = 256'b0000000000101000011111110010100000010100111111100001010000101000011111100010100001010110111111100101011000000000010101100000000001100110011111000100001001000100011111100111110001000010010001000100001001000100011111100111110001000010010000000000000000000000;
    localparam [255:0] CN_GLYPH_2 = 256'b0000000100000000000000010000000000000001000000000011111111111000001000010000100000100001000010000011111111111000001000010000100000100001000010000011111111111000001111111111100000100001000000000000000100000010000000011111111000000000000000000000000000000000;
    localparam [255:0] CN_GLYPH_3 = 256'b0000000000000000001111111111110000000000001110000000000001100000000000011000000000000001100000000111111111111110011111111111100000000001100000000000000110000000000000011000000000000001100000000000000110000000000001110000000000000000000000000000000000000000;
    localparam [255:0] CN_GLYPH_4 = 256'b0000000000000000001111111111110000000001100000000000000110000000000000011000000000000001100000000000000110000000000000011000000000000001100000000000000110000000000000011000000000000001100000000111111111111110000000000000000000000000000000000000000000000000;
    localparam [255:0] CN_GLYPH_5 = 256'b0000110011000000000010001000000000011001100000000001000111111110001100110100000000110110010000000101000001111100010100000100000000010000010000000001000001000000000100000111111000010000010000000001000001000000000100000100000000010000010000000000000000000000;
    localparam [255:0] CN_GLYPH_6 = 256'b0000000100000000000000011000000001111111111111000110000000000100011000000000010000011111111110000000011000110000000011000001100000011111111011000000000110000000000111111111100000000001100000000000000110000000011111111111111000000000000000000000000000000000;
    localparam [255:0] CN_GLYPH_7 = 256'b0001000001000000000100000100100000010000010011000001010001001000011101011111111001010010011100000101000001110000000100000111000000010000111100000001000010110000000100001011000000010001101100000001001100110010000101100001111000000000000000000000000000000000;
    localparam [255:0] CN_GLYPH_8 = 256'b0000110000000000000010000011111001111111101001000001100000100100000100000010010000111111001001000111000100101100010111110010010000010001001000100001000100100010000111110010001000010001001011100001000100100000000100110010000000000000001000000000000000000000;
    localparam [255:0] CN_GLYPH_9  = 256'b0000000001100000011100111000000001010000100000000101011111110000011100101010000001010010101000000101111111110000011100101010000001010010101000000101011111110000011100001000000001010011111000000000000000000000000000000000000000000000000000000000000000000000;
    localparam [255:0] CN_GLYPH_10 = 256'b0000100010000000011111111111000000001000100000000100000100000000001011111111000000000010100000000110011111100000001000001000000000101111111100000010000010000000001000001000000001011111111100000000000000000000000000000000000000000000000000000000000000000000;
    // ???????? chinese_glyph_row ?????? 16 ??? 11 ? 1?
    // ???? 256 ???????? -> ??????????Setup ?????
    reg [15:0] cn_row;
    always @* begin
        case (ch[3:0])
            4'd0: cn_row = CN_GLYPH_0[255 - {4'b0, cnrow_r, 4'b0000} -: 16];
             4'd1: cn_row = CN_GLYPH_1[255 - {4'b0, cnrow_r, 4'b0000} -: 16];
             4'd2: cn_row = CN_GLYPH_2[255 - {4'b0, cnrow_r, 4'b0000} -: 16];
             4'd3: cn_row = CN_GLYPH_3[255 - {4'b0, cnrow_r, 4'b0000} -: 16];
             4'd4: cn_row = CN_GLYPH_4[255 - {4'b0, cnrow_r, 4'b0000} -: 16];
             4'd5: cn_row = CN_GLYPH_5[255 - {4'b0, cnrow_r, 4'b0000} -: 16];
             4'd6: cn_row = CN_GLYPH_6[255 - {4'b0, cnrow_r, 4'b0000} -: 16];
             4'd7: cn_row = CN_GLYPH_7[255 - {4'b0, cnrow_r, 4'b0000} -: 16];
             4'd8: cn_row = CN_GLYPH_8[255 - {4'b0, cnrow_r, 4'b0000} -: 16];
             4'd9: cn_row = CN_GLYPH_9[255 - {4'b0, cnrow_r, 4'b0000} -: 16];
             4'd10: cn_row = CN_GLYPH_10[255 - {4'b0, cnrow_r, 4'b0000} -: 16];
            default: cn_row = 16'b0;
        endcase
    end

    reg [34:0] glyph;
    always @* begin
        case (ch)
            7'h20: glyph = 35'b00000_00000_00000_00000_00000_00000_00000; // ??????
            7'h2D: glyph = 35'b00000_00000_00000_11111_00000_00000_00000; // -
            7'h5F: glyph = 35'b00000_00000_00000_00000_00000_00000_11111; // _
            7'h61: glyph = 35'b00000_00000_01110_00001_01111_10001_01111; // a
            7'h68: glyph = 35'b10000_10000_11110_10001_10001_10001_10001; // h
            7'h6D: glyph = 35'b00000_00000_11010_10101_10101_10101_10101; // m
            7'h70: glyph = 35'b00000_00000_11110_10001_10001_11110_10000; // p
            7'h79: glyph = 35'b00000_00000_10001_10001_01111_00001_01110; // y
            7'h30: glyph = 35'b01110_10001_10011_10101_11001_10001_01110; // 0
            7'h31: glyph = 35'b00100_01100_00100_00100_00100_00100_01110; // 1
            7'h32: glyph = 35'b01110_10001_00001_00010_00100_01000_11111; // 2
            7'h33: glyph = 35'b11111_00010_00100_00010_00001_10001_01110; // 3
            7'h34: glyph = 35'b00010_00110_01010_10010_11111_00010_00010; // 4
            7'h35: glyph = 35'b11111_10000_11110_00001_00001_10001_01110; // 5
            7'h36: glyph = 35'b00110_01000_10000_11110_10001_10001_01110; // 6
            7'h37: glyph = 35'b11111_00001_00010_00100_01000_01000_01000; // 7
            7'h38: glyph = 35'b01110_10001_10001_01110_10001_10001_01110; // 8
            7'h39: glyph = 35'b01110_10001_10001_01111_00001_00010_01100; // 9
            7'h41: glyph = 35'b01110_10001_10001_11111_10001_10001_10001; // A
            7'h42: glyph = 35'b11110_10001_10001_11110_10001_10001_11110; // B
            7'h43: glyph = 35'b01110_10001_10000_10000_10000_10001_01110; // C
            7'h44: glyph = 35'b11110_10001_10001_10001_10001_10001_11110; // D
            7'h45: glyph = 35'b11111_10000_10000_11110_10000_10000_11111; // E
            7'h46: glyph = 35'b11111_10000_10000_11110_10000_10000_10000; // F
            7'h47: glyph = 35'b01110_10001_10000_10111_10001_10001_01111; // G
            7'h48: glyph = 35'b10001_10001_10001_11111_10001_10001_10001; // H
            7'h49: glyph = 35'b01110_00100_00100_00100_00100_00100_01110; // I
            7'h4A: glyph = 35'b00111_00010_00010_00010_00010_10010_01100; // J
            7'h4B: glyph = 35'b10001_10010_10100_11000_10100_10010_10001; // K
            7'h4C: glyph = 35'b10000_10000_10000_10000_10000_10000_11111; // L
            7'h4D: glyph = 35'b10001_11011_10101_10101_10001_10001_10001; // M
            7'h4E: glyph = 35'b10001_11001_10101_10011_10001_10001_10001; // N
            7'h4F: glyph = 35'b01110_10001_10001_10001_10001_10001_01110; // O
            7'h50: glyph = 35'b11110_10001_10001_11110_10000_10000_10000; // P
            7'h51: glyph = 35'b01110_10001_10001_10001_10101_10010_01101; // Q
            7'h52: glyph = 35'b11110_10001_10001_11110_10100_10010_10001; // R
            7'h53: glyph = 35'b01111_10000_10000_01110_00001_00001_11110; // S
            7'h54: glyph = 35'b11111_00100_00100_00100_00100_00100_00100; // T
            7'h55: glyph = 35'b10001_10001_10001_10001_10001_10001_01110; // U
            7'h56: glyph = 35'b10001_10001_10001_10001_10001_01010_00100; // V
            7'h57: glyph = 35'b10001_10001_10001_10101_10101_10101_01010; // W
            7'h58: glyph = 35'b10001_10001_01010_00100_01010_10001_10001; // X
            7'h59: glyph = 35'b10001_10001_01010_00100_00100_00100_00100; // Y
            7'h5A: glyph = 35'b11111_00001_00010_00100_01000_10000_11111; // Z
            default: glyph = 35'b00000_00000_00000_00000_00000_00000_00000;
        endcase
    end

    // ????????????ASCII 2 ????????? ??? ?????? = (srow-2)>>1???srow ??? [2,16) ??? ?????? 0..6???
    wire [3:0] grow = (srow - 4'd2) >> 1;
    wire [4:0] row_bits = glyph[34 - grow * 5 -: 5];

    // ????????????ASCII 2 ????????? + ?????? ??? ?????? = (scol-3)>>1???scol ??? [3,13) ??? ?????? 0..4???
    wire [4:0] gcol = (scol - 5'd3) >> 1;

    // ??????????????????????????????????????????????????????????????????????????? 2 ?????????????????????????????????
    // ?????? 16???????????? col 3..12???????????? 3px ??????????????????????????????????????????????????????
    // ????????? dy=2 ??????srow-2???? 15-col?
    // ??? dy<16 ???????"???????"???????? 18 ???? 16 ??
    wire [3:0]  cnrow_r = srow - 4'd2;

    wire        cn_pix  = cn_row[4'd15 - col] && (dy < 12'd16) && (srow >= 4'd2);
    wire        asc_pix = (scol >= 5'd3) && (scol < 5'd13) && row_bits[4 - gcol];
    wire hit = enable && in_band_y && (stream_x < text_w) &&
               (cidx < nchars) && (ch[7] ? cn_pix : asc_pix);

    // ??????????????? + ???????????????????????? promax_text_overlay ????????????????????????
    //   ??????????????????pixel_x ??? [8, H_ACTIVE-8) ??????????????? 24'hE8EEF2
    wire band = enable && in_band_y && (pixel_x >= 12'd8) && (pixel_x < (H_ACTIVE[11:0] - 12'd8));

    assign rgb_out        = hit ? 24'h000000 : (band ? 24'hE8EEF2 : rgb_in);
    assign overlay_active = hit || band;

endmodule
// ===========================================================================
// info_bands : 三条信息带 + 主图区   （《组内执行文档》2.1 版式 / 图 1）
//
//   顶部状态栏 (0,0)-(639,31)     640x32   编号+名称 / 状态 / 时间戳
//   主图区     (0,32)-(639,415)   640x384  图片层：本模块完全不碰，原样透传
//   字幕条     (0,416)-(639,455)  640x40   顶部 1px 金色强调分隔线 + 滚动讲解词
//   底部信息栏 (0,456)-(639,479)  640x24   进度条 + n/N / 亮度档位 / 展区名
//
// 与工程既有风格保持一致：
//   * 纯组合选点 + frame_start 锁存跨域状态 => 零流水延迟，不改 de 与既有对齐
//   * 全部字形 16x16，打包进 GLYPH_ROM，按 (code,row) 取 16 位一行
//   * 信息带为不透明覆盖：不读底图像素、不做 Alpha，省掉一条显存读取通路
//   * 进度条填充宽度查表，像素时钟路径上不出现除法
//   * 右上角时间由内部 1 s 计数器生成，设置面板可校时；不接外部 RTC
//
// 字符编码（本模块的核心约定，勿再引入偏移换算）：
//   * 每个字符占一个 8 位元素，元素 0 在最低位；文本向量宽度 = 字符数 x 8
//   * 字符码 == GLYPH_ROM 槽位号，直接索引：
//       槽位 0x20..0x7E = ASCII，槽位号就是 ASCII 码本身
//                            （数字 d -> 0x30+d，'/' -> 0x2F，0x20 为空格）
//       槽位 0x80..0xAF = 本项目用到的 48 个汉字，一字一槽
//     （上面的范围按 FONT_ROM.mif 逐一核对过；旧注释写的 0x00..0x5F /
//       0x60..0x8F 与实际字模不符，文字乱码的根因之一就是照旧注释写了
//       0x20+d 的取码偏移。）
//     与原工程 `case (ch[3:0]) CN_GLYPH_<n>` 思路一致：码即槽位。
// ===========================================================================
// info_bands : 三条信息带 + 主图区
//
//   顶部状态栏 (0,0)-(639,31)     编号+名称 / 状态 / 时间戳
//   主图区     (0,32)-(639,415)   图片层：完全透传
//   字幕条     (0,416)-(639,455)  顶部 1px 金色分隔线 + 滚动讲解词
//   底部信息栏 (0,456)-(639,479)  进度条 + n/N / 亮度档位 / 展区名
//
// 字模走 TD 的 ROM IP（FONT_ROM），与官方例程同一条路径：
//   官方 24_VGA_shiyan9_B：ROM b2v_inst2(.doa, .clka, .ocea(1'b1),
//                                    .rsta(1'b0), .addra);
//   本模块同样用法；ROM 由 al_ip\FONT_ROM.ipc + FONT_ROM.mif 生成。
//
// 地址与字模格式：
//   addr = code * 16 + (15 - 显示行)      code: ASCII 或 0x80|i(汉字)
//   每个 16 位字：bit15 = 该行最左像素
//   ——该格式取自原工程 CN_GLYPH_*（板上已验证可用），已逐位比对一致
//
// ⚠ ROM 读时序（FIX 14）：FONT_ROM 是 SP + REGMODE_A = OUTREG，
//   同步读要寄存地址（1 拍）+ 输出寄存器（1 拍）= **总延迟 2 拍**。
//   所以本模块把 pixel_x / pixel_y / de / rgb_in / 取字控制（含字内列号）
//   统一延迟 2 拍，做到"字形数据"和"字内列号"永远属于同一个像素；
//   地址则直接送给 FONT_ROM（不要再额外寄存，否则延迟会变成 3 拍）。
// ===========================================================================
module info_bands (
    input  wire        clk,             // video_clk (25MHz)
    input  wire        rst_n,
    input  wire        frame_start,     // vsync 下降沿
    input  wire        de,
    input  wire [11:0] pixel_x,
    input  wire [11:0] pixel_y,
    input  wire [23:0] rgb_in,
    input  wire [1:0]  cur_index,
    input  wire [3:0]  img_ready,
    input  wire        zone_mode,
    input  wire [3:0]  zone_idx,
    input  wire [4:0]  zone_count,
    input  wire [1:0]  zone_sel,
    input  wire [1:0]  disp_scale,     // v31：当前显示图的抽取比（1/2/3）
    input  wire        auto_enabled,
    // v37：共用主字库（与主菜单 二选一）
    output wire [13:0] fnt_addr_o,
    input  wire [15:0] fnt_dout_i,
    // v79：共用 ext 小字库（与目录页 二选一）。ROM 搬到顶层，两处共一片，
    //      深度扩到 2048（128 槽）后 BRAM 仍是 4 块，不额外占资源。
    output wire [10:0] fnt_addr_ext_o,
    input  wire [15:0] fnt_dout_ext_i,
    input  wire [4:0]  bright_level,   // 亮度档位 0..4（5 档）
    input  wire        param_is_contrast, // 1 = the knob is editing contrast (bottom bar word)
    // wall-clock correction from the settings panel's time_clock:
    // a one-cycle load installs the six BCD digits; the pixel-side time_str
    // is still generated from these local counters, so the pixel path does
    // not gain a 64-bit external mux.
    input  wire        load,
    input  wire [7:0]  hh_in,
    input  wire [7:0]  mm_in,
    input  wire [7:0]  ss_in,
    output wire [23:0] rgb_out
);

    // ---------------- 配色 ----------------
    localparam [23:0] C_BAR_BG     = 24'hDCEBF7;   // web light theme: bar fill
    localparam [23:0] C_SUB_BG     = 24'hCFE3F4;   // web: subtitle band fill
    localparam [23:0] C_ACCENT     = 24'h3F9ED8;   // web: saturated cyan-blue accent
    localparam [23:0] C_TEXT       = 24'h25445C;   // web: deep navy text
    localparam [23:0] C_STATUS_ON  = 24'h6AB17D;
    localparam [23:0] C_STATUS_OFF = 24'h949DAB;
    localparam [23:0] C_LINE       = 24'h9CCBE8;   // web: 1 px rule above the bottom bar

    // ---------------- 版式坐标 ----------------
    localparam integer SUB_Y      = 416;   // 字幕带 416..447（32 px）
    localparam integer BOT_Y      = 448;   // 底栏   448..479（32 px），与字幕带等高
    localparam integer TOP_TXT_Y  = 8;
    localparam integer TOP_NUM_X  = 16;
    localparam integer TOP_SLASH_X= 48;
    localparam integer TOP_NAME_X = 72;
    localparam integer TOP_STAT_CX= 40;
    localparam integer TOP_TIME_R = 620;   // v79b 624 -> v79c 620，给最右 4 px 白色装饰线让位
    // 顶栏居中标题「博物馆智能展品讲解系统」：11 字 x 16 = 176 px，水平居中
    localparam integer TITLE_X0   = 232;    // (640-176)/2
    localparam integer TITLE_N    = 11;
    // 字模槽位与 main_menu 的 ttl_char 一致（0x8D 博 0x8E 物 0x8F 馆 0xF8 智
    // 0xF9 能 0xE0 展 0xED 品 0xFA 讲 0xEB 解 0x90 系 0x91 统），首字在最低 8 位
    localparam [87:0] TITLE_STR8 = 88'h91_90_EB_FA_ED_E0_F9_F8_8F_8E_8D;
    localparam integer SUB_TXT_X  = 10;
    localparam integer SUB_ENTRY_X = 640;   // FIX 7: 字幕从右边界外进入（= H_ACTIVE）
    localparam integer SUB_TXT_Y  = 424;
    localparam integer BOT_TXT_Y  = 456;   // 32 px 底栏内居中：8 + 16 + 7
    localparam integer ZONE_R     = 620;   // v79b 624 -> v79c 620，同上
    localparam integer GLYPH      = 16;

    // ============ 跨域状态：帧边界锁存 ============
    reg [3:0] idx_q;
    reg [3:0] rdy_q;
    reg       auto_q;
    reg       zone_mode_q;
    reg [3:0] zone_idx_q;
    reg [4:0] zone_count_q;
    reg [1:0] zone_sel_q;
    reg [1:0] scale_q;      // v31：显示图的抽取比（1/2/3）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idx_q  <= 2'd0;
            rdy_q  <= 4'd0;
            auto_q <= 1'b0;
            zone_mode_q  <= 1'b0;
            zone_idx_q   <= 4'd0;
            zone_count_q <= 5'd0;
            zone_sel_q   <= 2'd0;
            scale_q      <= 2'd1;
        end else if (frame_start) begin
            idx_q  <= cur_index;
            rdy_q  <= img_ready;
            auto_q <= auto_enabled;
            zone_mode_q  <= zone_mode;
            zone_idx_q   <= zone_idx;
            zone_count_q <= zone_count;
            zone_sel_q   <= zone_sel;
            scale_q      <= disp_scale;
        end
    end

    // 分区模式用当前区内的序号/张数；普通模式用旧 4 张索引。
    // v32：底栏这一格**恢复成普通的 n / m 页码**（和各展区一致，例：B01 显示 1 / 4）。
    //   v31 曾把它在缩放显示时换成 "1 / N"，但页面上已经印了"源图 …"标注，
    //   底栏再换口径容易让人误读，所以撤掉。缩放比只由图片里的标注体现。
    wire [4:0] disp_num   = zone_mode_q ? ({1'b0, zone_idx_q} + 5'd1) :
                                          ({3'b0, idx_q[1:0]} + 5'd1);
    reg [3:0] rdy_seen;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rdy_seen <= 4'd0;
        else
            rdy_seen <= rdy_seen | rdy_q;
    end
    wire [2:0] img_total = {2'b00, rdy_seen[0]} + {2'b00, rdy_seen[1]} +
                           {2'b00, rdy_seen[2]} + {2'b00, rdy_seen[3]};
    wire [4:0] disp_total = zone_mode_q ? zone_count_q : {2'b0, img_total};

    reg [3:0] num_tens, num_ones, tot_tens, tot_ones;
    always @* begin
        case (disp_num)
            5'd1:    begin num_tens = 4'd0; num_ones = 4'd1; end
            5'd2:    begin num_tens = 4'd0; num_ones = 4'd2; end
            5'd3:    begin num_tens = 4'd0; num_ones = 4'd3; end
            5'd4:    begin num_tens = 4'd0; num_ones = 4'd4; end
            5'd5:    begin num_tens = 4'd0; num_ones = 4'd5; end
            5'd6:    begin num_tens = 4'd0; num_ones = 4'd6; end
            5'd7:    begin num_tens = 4'd0; num_ones = 4'd7; end
            5'd8:    begin num_tens = 4'd0; num_ones = 4'd8; end
            5'd9:    begin num_tens = 4'd0; num_ones = 4'd9; end
            5'd10:   begin num_tens = 4'd1; num_ones = 4'd0; end
            default: begin num_tens = 4'd0; num_ones = 4'd0; end
        endcase
        case (disp_total)
            5'd1:    begin tot_tens = 4'd0; tot_ones = 4'd1; end
            5'd2:    begin tot_tens = 4'd0; tot_ones = 4'd2; end
            5'd3:    begin tot_tens = 4'd0; tot_ones = 4'd3; end
            5'd4:    begin tot_tens = 4'd0; tot_ones = 4'd4; end
            5'd5:    begin tot_tens = 4'd0; tot_ones = 4'd5; end
            5'd6:    begin tot_tens = 4'd0; tot_ones = 4'd6; end
            5'd7:    begin tot_tens = 4'd0; tot_ones = 4'd7; end
            5'd8:    begin tot_tens = 4'd0; tot_ones = 4'd8; end
            5'd9:    begin tot_tens = 4'd0; tot_ones = 4'd9; end
            5'd10:   begin tot_tens = 4'd1; tot_ones = 4'd0; end
            default: begin tot_tens = 4'd0; tot_ones = 4'd0; end
        endcase
    end

    // FIX 2b: bottom-row "n / m" group.  Figure 1 shows "3 / 4", i.e.
    // without a leading zero, so a zero tens digit is skipped and the ones
    // digit moves into the tens cell.
    // FIX 12: 数字组改成"按实际字符数紧凑排布"（原来 '/' 固定在 48 号槽，
    //         单个数字时 "4" 与 "/" 之间空了一整格，看着很散）。
    //         现在：数字组左端固定在 8，字符一格接一格，'/' 紧跟数字。
    wire        num_two    = (num_tens != 4'd0);
    wire        tot_two    = (tot_tens != 4'd0);
    wire [11:0] num_ones_x = num_two ? 12'd24 : 12'd8;          // 个位槽（无前导 0 时左移到 8）
    wire [11:0] slash_x    = num_ones_x + 12'd16;               // '/' 紧跟数字组
    wire [11:0] tot_tens_x = slash_x + 12'd16;
    wire [11:0] tot_ones_x = tot_tens_x + (tot_two ? 12'd16 : 12'd0);

    // ============ 文本表（元素 0 在最低位）============
    localparam integer TIME_N = 8;

    // FIX 11: 右上角时间由 video_clk 分频出 1 秒节拍，从下面的 TIME_INIT_* 起算，
    //   按 HH:MM:SS 走 24 小时回绕。项目使用内部时钟，不接外部 RTC；
    //   设置面板校时时通过 load 把六个 BCD 位装入这里，两屏共用同一时间。
    localparam integer CLK_HZ     = 25000000;   // video_clk = 25.000 MHz（TD PLL 从 50MHz 分频）
    localparam [3:0]  TIME_INIT_H_T = 4'd1, TIME_INIT_H_O = 4'd2;   // 12
    localparam [3:0]  TIME_INIT_M_T = 4'd4, TIME_INIT_M_O = 4'd7;   // 47
    localparam [3:0]  TIME_INIT_S_T = 4'd3, TIME_INIT_S_O = 4'd6;   // 36

    reg [24:0] tick_cnt;
    reg [3:0]  h_tens, h_ones, m_tens, m_ones, s_tens, s_ones;
    wire tick_1s = (tick_cnt == CLK_HZ[24:0] - 25'd1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_cnt <= 25'd0;
            h_tens <= TIME_INIT_H_T; h_ones <= TIME_INIT_H_O;
            m_tens <= TIME_INIT_M_T; m_ones <= TIME_INIT_M_O;
            s_tens <= TIME_INIT_S_T; s_ones <= TIME_INIT_S_O;
        end else if (load) begin
            // panel correction: install the edited BCD time and restart the
            // 1 s divider so both screens count from the same instant
            tick_cnt <= 25'd0;
            h_tens <= hh_in[7:4]; h_ones <= hh_in[3:0];
            m_tens <= mm_in[7:4]; m_ones <= mm_in[3:0];
            s_tens <= ss_in[7:4]; s_ones <= ss_in[3:0];
        end else if (tick_1s) begin
            tick_cnt <= 25'd0;
            if (s_ones == 4'd9) begin
                s_ones <= 4'd0;
                if (s_tens == 4'd5) begin
                    s_tens <= 4'd0;
                    if (m_ones == 4'd9) begin
                        m_ones <= 4'd0;
                        if (m_tens == 4'd5) begin
                            m_tens <= 4'd0;
                            if ((h_tens == 4'd2) && (h_ones == 4'd3)) begin
                                h_tens <= 4'd0; h_ones <= 4'd0;      // 23:59:59 -> 00:00:00
                            end else if (h_ones == 4'd9) begin
                                h_ones <= 4'd0; h_tens <= h_tens + 4'd1;
                            end else begin
                                h_ones <= h_ones + 4'd1;
                            end
                        end else begin
                            m_tens <= m_tens + 4'd1;
                        end
                    end else begin
                        m_ones <= m_ones + 4'd1;
                    end
                end else begin
                    s_tens <= s_tens + 4'd1;
                end
            end else begin
                s_ones <= s_ones + 4'd1;
            end
        end else begin
            tick_cnt <= tick_cnt + 25'd1;
        end
    end

    // "HH:MM:SS" 字符向量：元素 0（最低字节）= 最左字符 = 时的十位
    // （用延迟一拍的 tick 装载，保证装载到的是"进位之后"的计数值）
    reg        tick_1s_d;
    reg        load_d;
    reg [63:0] time_str;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_1s_d <= 1'b0;
            load_d    <= 1'b0;
            time_str  <= 64'h36333A37343A3231;               // 上电先显示 12:47:36
        end else begin
            tick_1s_d <= tick_1s;
            load_d    <= load;
            if (tick_1s_d || load_d)
                time_str <= { 8'h30 + {4'b0, s_ones}, 8'h30 + {4'b0, s_tens}, 8'h3A,
                              8'h30 + {4'b0, m_ones}, 8'h30 + {4'b0, m_tens}, 8'h3A,
                              8'h30 + {4'b0, h_ones}, 8'h30 + {4'b0, h_tens} };
        end
    end

    localparam integer STAT_ON_N = 3;
    wire [23:0] stat_on_str = 24'h898887;
    localparam integer STAT_OFF_N = 2;
    wire [15:0] stat_off_str = 16'h8B8A;
    // 底栏右侧：中文「展区 <展品名>」，8 格 x 16 px = 128 px，右对齐到 ZONE_R。
    //   全部走 ext 字库（0x101+），不碰主字库的高地址段 —— 否则综合器会把
    //   info_bands 的主字库推断成 2048 深（4 块 BRAM），0x80 以上的字模全部别址。
    localparam integer ZONE_N = 8;
    reg [71:0] zone_str9;
    always @* begin
        case (zone_sel_q)
            2'd0:    zone_str9 = 72'hBA44A0B0481C0A0220; // 曾侯乙编钟展区
            2'd1:    zone_str9 = 72'hBA44A130883C184020; // 青铜礼器展区
            2'd2:    zone_str9 = 72'hBA44A190B850804020; // 唐三彩展区
            default: zone_str9 = 72'hBA44A231087C3A1A20; // 越王勾践剑展区
        endcase
    end
    localparam integer SUB_CHARS = 32;
    // ==== 滚动字幕文案（博物馆版｜由 tools/make_subtitle_font.py 生成，勿手改）====
    //   3 句循环：第 1 句随展区 A/B/C/D 切换，其余 2 句为通用提示（一轮约 50 s）。
    //   编码 9 bit/字，首字在最低 9 位；0x00..0xFF 走主字库 font_rom，
    //   0x100..0x17F 走共用小字库 font_rom_ext（rtl/font_rom_ext.v，2048 深 = 128 槽，4 块 BRAM）。
    localparam [287:0] SUB_A = 288'h00000000000000000000000000000000000000000000082C12070280882002059AC962B0;  // 欢迎参观 · 曾侯乙编钟
    localparam [287:0] SUB_B = 288'h00000000000000000000000000000000000000000000000426110783082002059AC962B0;  // 欢迎参观 · 青铜礼器
    localparam [287:0] SUB_C = 288'h00000000000000000000000000000000000000000000000002190B85082002059AC962B0;  // 欢迎参观 · 唐三彩
    localparam [287:0] SUB_D = 288'h00000000000000000000000000000000000000000000088C421F0E86882002059AC962B0;  // 欢迎参观 · 越王勾践剑
    localparam [287:0] SUB_N1 = 288'h00000000000000000092C92472290C56411F8D47A251D8E46E2B1A8CC622F168AC522712;  // 展厅内请保持安静，请勿触摸展品，拍照请关闭闪光灯
    localparam [287:0] SUB_N2 = 288'h00000000000002673298CC25F15974B6592B8D0C0603A1B8C65430180E8722094CA24F26;  // 开放时间 9:00—17:00，讲解服务请至前台预约
    reg  [1:0]   sub_idx;                   // 0=欢迎语(随区) 1/2=通用提示
    reg  [287:0] sub_str_r;
    reg  [5:0]   sub_len_r;
    always @* begin
        case (sub_idx)
            2'd0: case (zone_sel_q)
                      2'd0: begin sub_str_r = SUB_A;  sub_len_r = 6'd16; end
                      2'd1: begin sub_str_r = SUB_B;  sub_len_r = 6'd11; end
                      2'd2: begin sub_str_r = SUB_C;  sub_len_r = 6'd10; end
                      default: begin sub_str_r = SUB_D; sub_len_r = 6'd12; end
                  endcase
            2'd1: begin sub_str_r = SUB_N1; sub_len_r = 6'd24; end
            default: begin sub_str_r = SUB_N2; sub_len_r = 6'd26; end
        endcase
    end
    wire [287:0] sub_str = sub_str_r;
    wire [5:0]   sub_len = sub_len_r;
    localparam integer NAME_CAP = 8;
    reg [63:0] name_str;
    reg [4:0] name_len;
    always @* begin
        case (idx_q)
            2'd0: begin name_str = 64'h929190858F8E8D8C; name_len = 5'd8; end
            2'd1: begin name_str = 64'h96959493; name_len = 5'd4; end
            2'd2: begin name_str = 64'h989783; name_len = 5'd3; end
            2'd3: begin name_str = 64'h41869A99; name_len = 5'd4; end
            default: begin name_str = 64'h0; name_len = 5'd0; end
        endcase
    end

    // 滚动讲解词：每帧右移 SCROLL_STEP 像素
    // FIX 7: 字幕从"右边界之外"进入，再向左滑过整屏。
    //   原来字符串左端 = SUB_TXT_X(10) - scroll_pos，scroll_pos=0 时整句
    //   就已经出现在屏幕左半边（看着像"从屏幕中间冒出来"）。
    //   现在字符串左端 = SUB_ENTRY_X(640，即右边界) - scroll_pos：
    //   scroll_pos=0 时整句在右边界外，逐帧向左推进，滑出左边界后循环。
    // FIX 8: 滚动速度由 2 像素/帧 改为 1 像素/帧（≈60 像素/秒，原来 ≈120）。
    //   要再调：SCROLL_STEP = 1 慢、2 快（都是每帧一次 frame_start ≈ 59.5Hz）。
    localparam integer SCROLL_STEP  = 1;
    wire [11:0] SCROLL_CYCLE = 640 + GLYPH * sub_len;
    reg [11:0] scroll_pos;
    // 换展区（W/S 或 Enter 进区）时从"本区欢迎语"重新开始滚动，
    // 这样进任何一个区，观众第一眼看到的一定是该区的欢迎词。
    wire zone_chg = (zone_sel != zone_sel_q);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scroll_pos <= 12'd0;
            sub_idx    <= 2'd0;
        end else if (zone_chg) begin
            scroll_pos <= 12'd0;
            sub_idx    <= 2'd0;
        end else if (frame_start)
            if (scroll_pos + SCROLL_STEP >= SCROLL_CYCLE) begin
                scroll_pos <= 12'd0;
                sub_idx    <= (sub_idx == 2'd2) ? 2'd0 : (sub_idx + 2'd1);  // one full pass -> next sentence
            end else
                scroll_pos <= scroll_pos + SCROLL_STEP[11:0];
    end

    // name_str 的零扩展到 1024 位：单独声明一条 wire，避免在函数调用实参里
    // 写 {960{1'b0}, name_str} 这种「拼接里套复制」的写法（TD 解析会报错）
    // 避免「拼接里套复制」：先单独做一次 512 位复制，再与 name_str 拼接
    wire [511:0]  name_pad = {512{1'b0}};
    wire [1023:0] name_vec = {name_pad, name_pad, name_str};

    // ============ ROM 接口：地址 -> 1 拍后出数据 ============
    // 本拍算出地址（纯组合，用当前 pixel_x/y）
    wire [11:0] top_row   = pixel_y[3:0] - TOP_TXT_Y[3:0];
    wire [11:0] sub_row   = pixel_y[3:0] - SUB_TXT_Y[3:0];
    wire [11:0] bot_row   = pixel_y[3:0] - BOT_TXT_Y[3:0];
    // ---- FIX 1: one X origin for the scrolling subtitle ----
    // sci (which character) and sub_col (which column inside that glyph)
    // MUST come from the same origin.
    // FIX 7: 入口取右边界 SUB_ENTRY_X（不是原来的 10）——字幕从右边滑进来。
    wire [11:0] sub_x0  = pixel_x - SUB_ENTRY_X[11:0] + scroll_pos;
    wire [7:0]  sci     = sub_x0[11:4];
    wire [3:0]  sub_col = sub_x0[3:0];
    // 滚动词的字符序号：超出字符串长度必须钳位并关闭取字。
    // 否则 txt_char 会取到向量高位填充的 0x00，地址落回 0 号槽，
    // 屏上就会重复出现 0 号槽的字形（本次现象：滚过之后全是「亮」）。
    wire        sci_in  = (sci < sub_len);
    // 字幕每句 ≤ 32 字（SUB_CHARS），所以字符序号只用低 5 位，
    // 让 txt_char9 的 (ci*9) 不会超出 288 bit 的向量范围。
    wire [4:0]  sci_c   = sci_in ? sci[4:0] : 5'd0;

    // 选择本拍要取的字模：按区域优先级（同最终合成优先级）
    reg [8:0]  rom_code;
    reg [3:0]  rom_row;
    reg        rom_use;
    reg [11:0] t_dx, t_dy;
    always @* begin
        rom_code = 8'd0;
        rom_row  = 4'd0;
        rom_use  = 1'b0;
        t_dx     = 12'd0;
        t_dy     = 12'd0;
        // 综合器护栏：不可见区（x>=640）发一次 0xFF 槽的取字，
        // 让工具按 4096 深分配 info_bands 的主字库。否则它会把地址证明到
        // <0x800，把 ROM 裁成 2048 深，0x80 以上的字模全部别址
        // （顶栏「手动/轮播中」、字幕「欢迎参观」都会花掉）。
        if (pixel_x >= 12'd640) begin
            rom_code = 9'h0FF;
            rom_row  = 4'd0;
            rom_use  = 1'b1;
            t_dx     = 12'd0;
            t_dy     = 12'd0;
        end else if (pixel_y >= SUB_Y[11:0]) begin
            if (pixel_y < BOT_Y[11:0]) begin
                // 字幕条
                if ((pixel_y >= SUB_TXT_Y[11:0]) && (pixel_y < SUB_TXT_Y[11:0] + 12'd16)) begin
                    rom_code = txt_char9(sub_str, sci_c);
                    rom_row  = sub_row[3:0];
                    rom_use  = sci_in;              // 越界即不取字（原工程 cidx<nchars）
                    t_dx     = {8'b0, sub_col};
                    t_dy     = {8'b0, sub_row[3:0]};
                end
            end else begin
                // 底栏
                if ((pixel_y >= BOT_TXT_Y[11:0]) && (pixel_y < BOT_TXT_Y[11:0] + 12'd16)) begin
                    // FIX 2: ASCII digit d lives in ROM slot 0x30+d, not
                    // 0x20+d.  0x20+d is space/punctuation - that is why the
                    // bottom-left group showed '!' (1) and '$' (4) instead of
                    // digits.
                    // FIX 12: 数字组紧凑排布： 数字(8..) '/' 紧跟 总数(紧跟)，
                    //         槽位由 num_ones_x / slash_x / tot_tens_x / tot_ones_x 给出。
                    if      ((pixel_x >= 12'd8) && (pixel_x < num_ones_x))
                        begin rom_code = 8'h30 + {4'b0, num_tens}; t_dx = pixel_x - 12'd8;      rom_use = num_two; end
                    else if ((pixel_x >= num_ones_x) && (pixel_x < slash_x))
                        begin rom_code = 8'h30 + {4'b0, num_ones}; t_dx = pixel_x - num_ones_x; rom_use = 1'b1;    end
                    else if ((pixel_x >= slash_x) && (pixel_x < tot_tens_x))
                        begin rom_code = 8'h2F;                   t_dx = pixel_x - slash_x;    rom_use = 1'b1;    end
                    else if ((pixel_x >= tot_tens_x) && (pixel_x < tot_ones_x))
                        begin rom_code = 8'h30 + {4'b0, tot_tens}; t_dx = pixel_x - tot_tens_x; rom_use = tot_two; end
                    else if ((pixel_x >= tot_ones_x) && (pixel_x < (tot_ones_x + 12'd16)))
                        begin rom_code = 8'h30 + {4'b0, tot_ones}; t_dx = pixel_x - tot_ones_x; rom_use = 1'b1;    end
                    else if ((pixel_x >= (ZONE_R - ZONE_N * 16)) && (pixel_x < ZONE_R)) begin
                        rom_code = txt_char9(zone_str9, (pixel_x - (ZONE_R - ZONE_N * 16)) >> 4);
                        t_dx = pixel_x - (ZONE_R - ZONE_N * 16);
                        rom_use = 1'b1;
                    end
                    if (rom_use) begin
                        rom_row = bot_row[3:0];
                        t_dy    = {8'b0, bot_row[3:0]};
                    end
                end
            end
        end else if (pixel_y < 12'd32) begin
            // 顶栏
            if ((pixel_y >= TOP_TXT_Y[11:0]) && (pixel_y < TOP_TXT_Y[11:0] + 12'd16)) begin
                // 左上角图片序号/固定名称已移除
                if ((pixel_x >= (TOP_STAT_CX - STAT_ON_N * 8)) &&
                         (pixel_x <  (TOP_STAT_CX + STAT_ON_N * 8))) begin
                    rom_code = auto_q ? txt_char(stat_on_str,  (pixel_x - (TOP_STAT_CX - STAT_ON_N * 8)) >> 4)
                                      : txt_char(stat_off_str, (pixel_x - (TOP_STAT_CX - STAT_OFF_N * 8)) >> 4);
                    t_dx = auto_q ? (pixel_x - (TOP_STAT_CX - STAT_ON_N * 8))
                                  : (pixel_x - (TOP_STAT_CX - STAT_OFF_N * 8));
                    rom_use = 1'b1;
                end
                else if ((pixel_x >= (TOP_TIME_R - TIME_N * 16)) && (pixel_x < TOP_TIME_R)) begin
                    rom_code = txt_char(time_str, (pixel_x - (TOP_TIME_R - TIME_N * 16)) >> 4);
                    t_dx     = pixel_x - (TOP_TIME_R - TIME_N * 16);
                    rom_use  = 1'b1;
                end
                // 顶栏居中标题：博物馆智能展品讲解系统
                else if ((pixel_x >= TITLE_X0[11:0]) &&
                         (pixel_x <  (TITLE_X0[11:0] + TITLE_N * 16))) begin
                    rom_code = TITLE_STR8[((pixel_x - TITLE_X0[11:0]) >> 4) * 8 +: 8];
                    t_dx     = pixel_x - TITLE_X0[11:0];
                    rom_use  = 1'b1;
                end
                if (rom_use) begin
                    rom_row = top_row[3:0];
                    t_dy    = {8'b0, top_row[3:0]};
                end
            end
        end
    end

    // 地址：addr = code*16 + (15 - row)
    //   0x000..0x0FF -> 主字库 font_rom（4096 深，8 块 BRAM，字库内容原样不动）
    //   0x100..0x17F -> 共用 ext 小字库（2048 深 = 128 槽，4 块 BRAM，见 rtl/font_rom_ext.v）
    //   两片并行读、按 is_ext 选输出：主字库的地址只有 12 bit，不会被 9 bit 字符码
    //   撑成 8192 深（那样这一份字库就要从 8 块 BRAM 涨到 15 块）。
    wire        is_ext        = (rom_code >= 9'h100);
    wire [11:0] rom_addr_main = rom_use ? ({rom_code[7:0], 4'b0} + {8'b0, (4'd15 - rom_row)}) : 12'd0;
    wire [10:0] rom_addr_ext  = rom_use ? ({rom_code[6:0], (4'd15 - rom_row)}) : 11'd0;
    wire [15:0] rom_row_bits_main;
    wire [15:0] rom_row_bits_ext;
    // FIX 14: 字模读取的真实延迟是 **2 拍**，不是 1 拍。
    //   这块 ROM 是"SP + REGMODE_A = OUTREG"：SP 同步读本身要寄存地址（1 拍），
    //   OUTREG 再加一级输出寄存器（1 拍）——合起来 2 拍。
    //   （旧的注释写"读延迟 1 拍"是错的；板上看到的"每个汉字左边多一个小点"，
    //     正是"字形数据比列号慢 1 个像素"时，把**左邻汉字第 0 列**的笔画画到了
    //     本字格第一列上 —— 汉字第 0 列常有笔画，ASCII 数字第 0 列是空的，
    //     所以只有汉字旁边看得见。）
    //   因此这里地址**直接**送给 ROM（不再额外寄存），像素侧统一延迟 2 拍：
    //   第 t 拍给地址 -> 第 t+2 拍 rom_row_bits = 第 t 个像素的字模行，二者同像素。
    reg [11:0] rom_addr_q;
    reg [10:0] rom_addr_ext_q;
    reg        ext_s1, ext_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rom_addr_q     <= 12'd0;
            rom_addr_ext_q <= 11'd0;
            ext_s1         <= 1'b0;
            ext_d          <= 1'b0;
        end else begin
            rom_addr_q     <= rom_addr_main;
            rom_addr_ext_q <= rom_addr_ext;
            ext_s1         <= is_ext;
            ext_d          <= ext_s1;     // 与 use_d / col_d 同为 2 拍
        end
    end
    // v37：主字库与主菜单**共用**同一块 font_rom（两者永不同屏），地址送出、数据收回
    assign fnt_addr_o = {2'd0, rom_addr_q};
    assign rom_row_bits_main = fnt_dout_i;   // v38: 原来这里又声明了一次同名 wire，
    //       导致 734 行那个真正的网没驱动 => 主字库文字整层丢失（顶栏/字幕中文消失）
    // v79：ext 字库同样搬到顶层与目录页共用（目录页 / 字幕永不同屏）
    assign fnt_addr_ext_o = rom_addr_ext_q;
    assign rom_row_bits_ext = fnt_dout_ext_i;
    wire [15:0] rom_row_bits = ext_d ? rom_row_bits_ext : rom_row_bits_main;

    // ============ 2 拍流水线：像素侧信号与 ROM 数据对齐 ============
    // 另外：空槽（0x00 未用槽、0x20 空格）强制不画，
    //       防止字库里这两个槽位万一有内容时在字与字之间冒出小点。
    reg        de_s1,  de_d;
    reg        use_s1, use_d;
    reg        blank_s1, blank_d;
    reg [3:0]  col_s1, col_d;
    reg [11:0] dx_s1, dx_d, dy_s1, dy_d;
    reg [23:0] rgb_s1, rgb_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            de_s1 <= 1'b0;    de_d <= 1'b0;
            use_s1 <= 1'b0;   use_d <= 1'b0;
            blank_s1 <= 1'b1; blank_d <= 1'b1;
            col_s1 <= 4'd0;   col_d <= 4'd0;
            dx_s1 <= 12'd0;   dx_d <= 12'd0;
            dy_s1 <= 12'd0;   dy_d <= 12'd0;
            rgb_s1 <= 24'd0;  rgb_d <= 24'd0;
        end else begin
            de_s1  <= de;            de_d  <= de_s1;    // 第 1、2 级：de
            use_s1 <= rom_use;       use_d <= use_s1;   // 取字控制
            // 空槽标记（0x00 未用槽 / 0x20 空格）跟着一起延迟
            blank_s1 <= (rom_code == 8'h00) || (rom_code == 8'h20);
            blank_d  <= blank_s1;
            col_s1 <= t_dx[3:0];     col_d <= col_s1;   // 字内列号
            // FIX 5: 进度条/带判定要用"屏幕 X"（旧代码误接成 t_dx，导致进度条画不出来）
            dx_s1  <= pixel_x;       dx_d  <= dx_s1;
            dy_s1  <= pixel_y;       dy_d  <= dy_s1;
            rgb_s1 <= rgb_in;
            rgb_d  <= rgb_s1;
        end
    end

    // 字模像素：bit15 = 最左像素，故位序为 15 - col_d；
    // 这里用的 rom_row_bits 与 col_d/use_d 属于同一个像素（都是 2 拍前的地址/控制）。
    wire ink_d = use_d && !blank_d && rom_row_bits[4'd15 - col_d];

    // ============ 合成（用延迟后的信号）============
    wire in_top = (dy_d < 12'd32);
    wire in_sub = (dy_d >= SUB_Y[11:0]) && (dy_d < BOT_Y[11:0]);
    wire in_bot = (dy_d >= BOT_Y[11:0]);
    wire on_accent = (dy_d == SUB_Y[11:0]);
    // 顶部"轮播中 / 手动"现在和标题、时间用同一个正文色 C_TEXT（原来是绿色 C_STATUS_ON，
    // 在一片蓝白里显得突兀；板测要求统一）
    wire on_stat = (dx_d >= (TOP_STAT_CX - STAT_ON_N * 8)) &&
                   (dx_d <  (TOP_STAT_CX + STAT_ON_N * 8));
    wire [23:0] stat_rgb = C_TEXT;

    reg [23:0] band_rgb;
    always @* begin
        if (!de_d) begin
            band_rgb = rgb_d;
        end else if (in_sub) begin
            if (dy_d == (BOT_Y[11:0] - 12'd1))   band_rgb = C_LINE;
            else                             band_rgb = on_accent ? C_ACCENT : (ink_d ? C_TEXT : C_SUB_BG);
        end else if (in_bot) begin
            band_rgb = ink_d ? C_TEXT : C_BAR_BG;
        end else if (in_top) begin
            band_rgb = ink_d ? (on_stat ? stat_rgb : C_TEXT) : C_BAR_BG;
        end else begin
            band_rgb = rgb_d;
        end
    end

    assign rgb_out = band_rgb;

    // ============ 取字符码 ============
    // 8 bit/字：顶栏时间/状态、底栏 ZONE 等旧文案沿用（ASCII 与 0x80..0xFF 槽位）
    function [7:0] txt_char;
        input [1023:0] t;
        input [6:0]    ci;
        begin
            txt_char = t[(ci * 8) +: 8];
        end
    endfunction

    // 9 bit/字：滚动字幕专用（0x101+ 新字模 + ASCII），支持到 0x1FF 槽位
    function [8:0] txt_char9;
        input [1023:0] t;
        input [4:0]    ci;
        begin
            txt_char9 = t[(ci * 9) +: 9];
        end
    endfunction

endmodule
