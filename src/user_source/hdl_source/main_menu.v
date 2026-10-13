`timescale 1ns/1ps
// ===========================================================================
//  main_menu.v  --  主菜单画面 + 菜单状态机
//
//  画面（640x480@60Hz，video_clk 域）：
//    * 淡紫竖向渐变背景 + 右侧装饰圆环 / 几个浅紫圆点（仿参考图风格）
//    * 左上角标题「主菜单」（16x16 字模 2 倍放大）
//    * 左侧三枚大圆角胶囊按钮，自上而下：开始 / 二号待定 / 三号待定
//        选中项：满色 + 白色光晕描边 + 左侧白色三角标 + 白色文字
//        未选中：同色淡化 50% + 深灰紫文字
//    * 底部深紫提示条：「短按切换   长按确定」
//
//  字模：复用 al_ip/FONT_ROM（新增汉字占槽位 0x01..0x0F，见 FONT_ROM.mif）。
//        该 ROM 是「SP + REGMODE_A = OUTREG」，读延迟 **2 拍**；
//        本模块与 subtitle_overlay.v 的 FIX 14 完全一致：地址当拍送 ROM，
//        像素侧信号统一延迟 2 拍，保证「字形数据」与「字内列号」是同一个像素。
//        —— 千万不要把它当 1 拍，否则汉字旁边会多出小点（历史踩坑）。
//
//  分区：本模块只负责画。当前是「主菜单」还是「图片界面」、选中第几项，
//        由下面的 main_menu_ctrl 给出，经顶层同步进 video_clk。
// ===========================================================================
module main_menu (
    input  wire        clk,        // video_clk (25MHz)
    input  wire        rst_n,      // video_rst_n
    input  wire        de,
    input  wire [11:0] pixel_x,
    input  wire [11:0] pixel_y,
    input  wire [23:0] rgb_in,
    input  wire        active,     // 1 = 显示主菜单
    input  wire [1:0]  sel,        // 当前选中项 0..2
    output wire [23:0] rgb_out
);

    // ------------------------------------------------------------------
    // 版式常量（像素坐标，屏幕 640x480）
    // ------------------------------------------------------------------
    localparam [11:0] TITLE_X  = 12'd56;    // 标题左上角
    localparam [11:0] TITLE_Y  = 12'd40;
    localparam [11:0] TITLE_W  = 12'd96;    // 3 字 x 32（2 倍放大）
    localparam [11:0] TITLE_H  = 12'd32;

    localparam [11:0] BTN_X0   = 12'd56;    // 按钮基准矩形
    localparam [11:0] BTN_X1   = 12'd400;
    localparam [11:0] BTN_Y0   = 12'd130;
    localparam [11:0] BTN_DY   = 12'd98;    // 行距：130 / 228 / 326
    localparam [11:0] BTN_H    = 12'd76;
    localparam [11:0] SPX      = 12'd8;     // 选中时左右外扩
    localparam [11:0] SPY      = 12'd5;     // 选中时上下外扩
    localparam [11:0] RC_N     = 12'd38;    // 普通圆角半径 = 半高 -> 胶囊（半圆端）
    localparam [11:0] RC_S     = 12'd43;    // 选中圆角半径 = 半高
    localparam [11:0] LBL_DY   = 12'd30;    // 文字相对按钮顶部的偏移
    localparam [11:0] LBL_CX   = 12'd250;   // 文字组中心（按钮内文字区）

    localparam [11:0] HINT_Y0  = 12'd428;   // 底部提示条
    localparam [11:0] HINT_TY  = 12'd446;   // 提示文字行
    localparam [11:0] HINT_LX  = 12'd200;   // 左组「短按切换」
    localparam [11:0] HINT_RX  = 12'd376;   // 右组「长按确定」

    // ------------------------------------------------------------------
    // 配色
    // ------------------------------------------------------------------
    localparam [23:0] C_TITLE   = 24'h5B4BC4;
    localparam [23:0] C_BTN0    = 24'h45CEE4;   // 开始   青
    localparam [23:0] C_BTN1    = 24'hF0C64B;   // 二号   黄
    localparam [23:0] C_BTN2    = 24'h8A79E6;   // 三号   紫
    // 未选中 = 基色向白淡化： 每通道 (c>>1)+0x60（比 +0x80 略深，浅底上更清楚）
    localparam [23:0] C_BTN0_P  = 24'h82C7D2;
    localparam [23:0] C_BTN1_P  = 24'hD8C385;
    localparam [23:0] C_BTN2_P  = 24'hA59CD3;
    localparam [23:0] C_TXT_SEL = 24'hFFFFFF;
    localparam [23:0] C_TXT_OFF = 24'h4A4463;
    localparam [23:0] C_GLOW    = 24'hFFFFFF;
    localparam [23:0] C_HINT_BG = 24'h3A3163;
    localparam [23:0] C_HINT_LN = 24'h6E5FD8;
    localparam [23:0] C_HINT_TX = 24'hF0ECFB;
    localparam [23:0] C_RING    = 24'hD6CCF1;
    localparam [23:0] C_DISC    = 24'hEDE7FA;
    localparam [23:0] C_DOT     = 24'hE1D9F6;

    // ------------------------------------------------------------------
    // 几何小工具（全部纯组合，成本低）
    // ------------------------------------------------------------------

    // 八边形近似圆：max(|dx|,|dy|) <= r 且 |dx|+|dy| <= 1.5r
    function oct_hit;
        input [11:0] x;
        input [11:0] y;
        input [11:0] cx;
        input [11:0] cy;
        input [11:0] r;
        reg   [12:0] dx;
        reg   [12:0] dy;
        reg   [12:0] ds;
        reg   [12:0] dm;
        begin
            dx = (x >= cx) ? (x - cx) : (cx - x);
            dy = (y >= cy) ? (y - cy) : (cy - y);
            ds = dx + dy;
            dm = (dx > dy) ? dx : dy;
            oct_hit = (dm <= {1'b0, r}) && (ds <= ({1'b0, r} + {1'b0, r[11:1]}));
        end
    endfunction

    // 圆角胶囊：矩形 + 四角按半径 rc 做八边形圆角
    //   ox/oy = 到最近一个"角圆心"的水平/垂直偏移（中间区域为 0），
    //   再做一次八边形半径判定 max(ox,oy)<=rc && ox+oy<=1.5rc。
    //   rc = 半高时两端就是半圆（胶囊）。
    function pill_hit;
        input [11:0] x;
        input [11:0] y;
        input [11:0] x0;
        input [11:0] y0;
        input [11:0] x1;
        input [11:0] y1;
        input [11:0] rc;
        reg   [11:0] xcl;
        reg   [11:0] xcr;
        reg   [11:0] ycu;
        reg   [11:0] ycd;
        reg   [11:0] ox;
        reg   [11:0] oy;
        reg   [11:0] om;
        reg   [11:0] os;
        begin
            xcl = x0 + rc;
            xcr = x1 - 12'd1 - rc;
            ycu = y0 + rc;
            ycd = y1 - 12'd1 - rc;
            ox  = (x < xcl) ? (xcl - x) : ((x > xcr) ? (x - xcr) : 12'd0);
            oy  = (y < ycu) ? (ycu - y) : ((y > ycd) ? (y - ycd) : 12'd0);
            om  = (ox > oy) ? ox : oy;
            os  = ox + oy;
            pill_hit = (x >= x0) && (x < x1) && (y >= y0) && (y < y1) &&
                       (om <= rc) && (os <= (rc + rc[11:1]));
        end
    endfunction

    // 右向三角标（图标）：顶点在右端 (ax, ay)
    function tri_hit;
        input [11:0] x;
        input [11:0] y;
        input [11:0] ax;
        input [11:0] ay;
        reg   [12:0] dx;
        reg   [12:0] dy;
        begin
            dx = ax - x;
            dy = (y >= ay) ? (y - ay) : (ay - y);
            tri_hit = (x <= ax) && (dx <= 13'd22) && (dy <= (dx - (dx >> 3)));
        end
    endfunction

    // ------------------------------------------------------------------
    // 文本表：码 == FONT_ROM 槽位号（0x01..0x0F 是本次为菜单新增的汉字）
    // ------------------------------------------------------------------
    //  槽位：0x01 开 0x02 始 0x03 二 0x04 号 0x05 待 0x06 定 0x07 三
    //        0x08 菜 0x09 单 0x0A 切 0x0B 换 0x0C 确 0x0D 长 0x0E 按 0x0F 短
    //        0x82 主（原有槽位，"主"字本来就在字库里）
    function [7:0] ttl_char;
        input [7:0] i;
        begin
            case (i)
                8'd0:    ttl_char = 8'h82;   // 主
                8'd1:    ttl_char = 8'h08;   // 菜
                default: ttl_char = 8'h09;   // 单
            endcase
        end
    endfunction

    function [7:0] lbl_char;
        input [1:0] item;
        input [2:0] i;
        begin
            if (item == 2'd0) begin
                lbl_char = (i == 3'd0) ? 8'h01 : 8'h02;                  // 开始
            end else if (item == 2'd1) begin
                case (i)                                                  // 二号待定
                    3'd0:    lbl_char = 8'h03;
                    3'd1:    lbl_char = 8'h04;
                    3'd2:    lbl_char = 8'h05;
                    default: lbl_char = 8'h06;
                endcase
            end else begin
                case (i)                                                  // 三号待定
                    3'd0:    lbl_char = 8'h07;
                    3'd1:    lbl_char = 8'h04;
                    3'd2:    lbl_char = 8'h05;
                    default: lbl_char = 8'h06;
                endcase
            end
        end
    endfunction

    function [7:0] hint_char;
        input        right;      // 0 = 左组「短按切换」, 1 = 右组「长按确定」
        input [2:0]  i;
        begin
            if (!right) begin
                case (i)
                    3'd0:    hint_char = 8'h0F;   // 短
                    3'd1:    hint_char = 8'h0E;   // 按
                    3'd2:    hint_char = 8'h0A;   // 切
                    default: hint_char = 8'h0B;   // 换
                endcase
            end else begin
                case (i)
                    3'd0:    hint_char = 8'h0D;   // 长
                    3'd1:    hint_char = 8'h0E;   // 按
                    3'd2:    hint_char = 8'h0C;   // 确
                    default: hint_char = 8'h06;   // 定
                endcase
            end
        end
    endfunction

    // ------------------------------------------------------------------
    // 取字模：本拍算出地址 -> 2 拍后数据可用
    // ------------------------------------------------------------------
    wire [11:0] tcx = pixel_x - TITLE_X;                 // 0..95
    wire [11:0] tcy = pixel_y - TITLE_Y;                 // 0..31
    wire        in_title = (pixel_x >= TITLE_X) && (pixel_x < (TITLE_X + TITLE_W)) &&
                           (pixel_y >= TITLE_Y) && (pixel_y < (TITLE_Y + TITLE_H));

    wire [11:0] lbx_0 = LBL_CX - 12'd16;                 // 2 字 → 32 宽
    wire [11:0] lbx_1 = LBL_CX - 12'd32;                 // 4 字 → 64 宽
    wire [11:0] lby_0 = BTN_Y0 + LBL_DY;
    wire [11:0] lby_1 = BTN_Y0 + BTN_DY + LBL_DY;
    wire [11:0] lby_2 = BTN_Y0 + BTN_DY + BTN_DY + LBL_DY;

    wire [11:0] l0x = pixel_x - lbx_0;
    wire [11:0] l1x = pixel_x - lbx_1;
    wire [11:0] l2x = pixel_x - lbx_1;
    wire [11:0] l0y = pixel_y - lby_0;
    wire [11:0] l1y = pixel_y - lby_1;
    wire [11:0] l2y = pixel_y - lby_2;

    wire in_lbl0 = (pixel_x >= lbx_0) && (pixel_x < (lbx_0 + 12'd32)) &&
                   (pixel_y >= lby_0) && (pixel_y < (lby_0 + 12'd16));
    wire in_lbl1 = (pixel_x >= lbx_1) && (pixel_x < (lbx_1 + 12'd64)) &&
                   (pixel_y >= lby_1) && (pixel_y < (lby_1 + 12'd16));
    wire in_lbl2 = (pixel_x >= lbx_1) && (pixel_x < (lbx_1 + 12'd64)) &&
                   (pixel_y >= lby_2) && (pixel_y < (lby_2 + 12'd16));

    wire [11:0] hlx = pixel_x - HINT_LX;
    wire [11:0] hrx = pixel_x - HINT_RX;
    wire [11:0] hty = pixel_y - HINT_TY;
    wire in_hintl = (pixel_x >= HINT_LX) && (pixel_x < (HINT_LX + 12'd64)) &&
                    (pixel_y >= HINT_TY) && (pixel_y < (HINT_TY + 12'd16));
    wire in_hintr = (pixel_x >= HINT_RX) && (pixel_x < (HINT_RX + 12'd64)) &&
                    (pixel_y >= HINT_TY) && (pixel_y < (HINT_TY + 12'd16));

    reg  [7:0] rom_code;
    reg  [3:0] rom_row;
    reg  [3:0] rom_col;
    reg        rom_use;

    always @* begin
        rom_code = 8'h00;
        rom_row  = 4'h0;
        rom_col  = 4'h0;
        rom_use  = 1'b0;
        if (in_title) begin
            rom_code = ttl_char({6'b0, tcx[6:5]});        // 3 字
            rom_row  = tcy[4:1];                          // 2 倍放大
            rom_col  = tcx[4:1];
            rom_use  = 1'b1;
        end else if (in_lbl0) begin
            rom_code = lbl_char(2'd0, l0x[6:4]);
            rom_row  = l0y[3:0];
            rom_col  = l0x[3:0];
            rom_use  = 1'b1;
        end else if (in_lbl1) begin
            rom_code = lbl_char(2'd1, l1x[6:4]);
            rom_row  = l1y[3:0];
            rom_col  = l1x[3:0];
            rom_use  = 1'b1;
        end else if (in_lbl2) begin
            rom_code = lbl_char(2'd2, l2x[6:4]);
            rom_row  = l2y[3:0];
            rom_col  = l2x[3:0];
            rom_use  = 1'b1;
        end else if (in_hintl) begin
            rom_code = hint_char(1'b0, hlx[6:4]);
            rom_row  = hty[3:0];
            rom_col  = hlx[3:0];
            rom_use  = 1'b1;
        end else if (in_hintr) begin
            rom_code = hint_char(1'b1, hrx[6:4]);
            rom_row  = hty[3:0];
            rom_col  = hrx[3:0];
            rom_use  = 1'b1;
        end
    end

    // addr = code*16 + (15 - row)
    wire [11:0] rom_addr = rom_use ? ({4'b0, rom_code} * 16 + {8'b0, (4'd15 - rom_row)})
                                   : 12'd0;

    wire [15:0] rom_row_bits;
    FONT_ROM u_menu_font_rom (
        .doa   (rom_row_bits),
        .addra (rom_addr),
        .ocea  (1'b1),
        .rsta  (1'b0),
        .clka  (clk)
    );

    // ------------------------------------------------------------------
    // 2 拍流水：像素侧信号与 ROM 数据对齐
    // ------------------------------------------------------------------
    reg        de_s1,   de_d;
    reg        act_s1,  act_d;
    reg        use_s1,  use_d;
    reg        blank_s1, blank_d;
    reg [3:0]  col_s1,  col_d;
    reg [11:0] dx_s1,   dx_d;
    reg [11:0] dy_s1,   dy_d;
    reg [23:0] rgb_s1,  rgb_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            de_s1    <= 1'b0;  de_d    <= 1'b0;
            act_s1   <= 1'b0;  act_d   <= 1'b0;
            use_s1   <= 1'b0;  use_d   <= 1'b0;
            blank_s1 <= 1'b1;  blank_d <= 1'b1;
            col_s1   <= 4'd0;  col_d   <= 4'd0;
            dx_s1    <= 12'd0; dx_d    <= 12'd0;
            dy_s1    <= 12'd0; dy_d    <= 12'd0;
            rgb_s1   <= 24'd0; rgb_d   <= 24'd0;
        end else begin
            de_s1    <= de;      de_d    <= de_s1;
            act_s1   <= active;  act_d   <= act_s1;
            use_s1   <= rom_use; use_d   <= use_s1;
            blank_s1 <= (rom_code == 8'h00);
            blank_d  <= blank_s1;
            col_s1   <= rom_col; col_d   <= col_s1;
            dx_s1    <= pixel_x; dx_d    <= dx_s1;
            dy_s1    <= pixel_y; dy_d    <= dy_s1;
            rgb_s1   <= rgb_in;  rgb_d   <= rgb_s1;
        end
    end

    wire ink_d = use_d && !blank_d && rom_row_bits[4'd15 - col_d];

    // ------------------------------------------------------------------
    // 背景：竖向渐变（每 16 像素一档，共约 30 档；用减法而不是查表，省 LUT）
    // ------------------------------------------------------------------
    wire [4:0] gstep   = dy_d[8:4];              // y/16 -> 0..29
    wire [4:0] gstep_b = gstep[4:1];             // 蓝色只降一半，底部带点紫
    wire [7:0] bg_r = 8'hF7 - {3'b000, gstep};
    wire [7:0] bg_g = 8'hF3 - {3'b000, gstep};
    wire [7:0] bg_b = 8'hFD - {3'b000, gstep_b};
    wire [23:0] bg  = {bg_r, bg_g, bg_b};

    wire ring_o = oct_hit(dx_d, dy_d, 12'd462, 12'd238, 12'd176);
    wire ring_i = oct_hit(dx_d, dy_d, 12'd462, 12'd238, 12'd144);

    // 三个装饰圆点
    wire dot1 = oct_hit(dx_d, dy_d, 12'd250, 12'd66,  12'd26);
    wire dot2 = oct_hit(dx_d, dy_d, 12'd604, 12'd100, 12'd30);
    wire dot3 = oct_hit(dx_d, dy_d, 12'd596, 12'd372, 12'd22);

    wire [23:0] bg_dec =
        dot1 ? C_DOT :
        dot2 ? C_DOT :
        dot3 ? C_DOT :
        ((ring_o && !ring_i) ? C_RING : (ring_i ? C_DISC : bg));

    // ------------------------------------------------------------------
    // 三枚按钮
    // ------------------------------------------------------------------
    wire s0 = (sel == 2'd0);
    wire s1 = (sel == 2'd1);
    wire s2 = (sel == 2'd2);

    wire [11:0] by0_0 = BTN_Y0;
    wire [11:0] by0_1 = BTN_Y0 + BTN_DY;
    wire [11:0] by0_2 = BTN_Y0 + BTN_DY + BTN_DY;
    wire [11:0] by1_0 = BTN_Y0 + BTN_H;
    wire [11:0] by1_1 = BTN_Y0 + BTN_DY + BTN_H;
    wire [11:0] by1_2 = BTN_Y0 + BTN_DY + BTN_DY + BTN_H;

    wire [11:0] b0x0 = s0 ? (BTN_X0 - SPX) : BTN_X0;
    wire [11:0] b0x1 = s0 ? (BTN_X1 + SPX) : BTN_X1;
    wire [11:0] b0y0 = s0 ? (by0_0 - SPY)  : by0_0;
    wire [11:0] b0y1 = s0 ? (by1_0 + SPY)  : by1_0;
    wire [11:0] b1x0 = s1 ? (BTN_X0 - SPX) : BTN_X0;
    wire [11:0] b1x1 = s1 ? (BTN_X1 + SPX) : BTN_X1;
    wire [11:0] b1y0 = s1 ? (by0_1 - SPY)  : by0_1;
    wire [11:0] b1y1 = s1 ? (by1_1 + SPY)  : by1_1;
    wire [11:0] b2x0 = s2 ? (BTN_X0 - SPX) : BTN_X0;
    wire [11:0] b2x1 = s2 ? (BTN_X1 + SPX) : BTN_X1;
    wire [11:0] b2y0 = s2 ? (by0_2 - SPY)  : by0_2;
    wire [11:0] b2y1 = s2 ? (by1_2 + SPY)  : by1_2;

    wire [11:0] rc_0 = s0 ? RC_S : RC_N;
    wire [11:0] rc_1 = s1 ? RC_S : RC_N;
    wire [11:0] rc_2 = s2 ? RC_S : RC_N;

    wire btn0 = pill_hit(dx_d, dy_d, b0x0, b0y0, b0x1, b0y1, rc_0);
    wire btn1 = pill_hit(dx_d, dy_d, b1x0, b1y0, b1x1, b1y1, rc_1);
    wire btn2 = pill_hit(dx_d, dy_d, b2x0, b2y0, b2x1, b2y1, rc_2);
    wire in_btn  = btn0 | btn1 | btn2;
    wire on_sel  = (btn0 & s0) | (btn1 & s1) | (btn2 & s2);
    wire on_off  = in_btn & ~on_sel;

    // 选中项光晕：比按钮再外扩 6px 的白圈
    wire [11:0] sbx0 = s0 ? b0x0 : (s1 ? b1x0 : b2x0);
    wire [11:0] sbx1 = s0 ? b0x1 : (s1 ? b1x1 : b2x1);
    wire [11:0] sby0 = s0 ? b0y0 : (s1 ? b1y0 : b2y0);
    wire [11:0] sby1 = s0 ? b0y1 : (s1 ? b1y1 : b2y1);
    wire [11:0] src  = s0 ? rc_0 : (s1 ? rc_1 : rc_2);
    wire sel_pill   = pill_hit(dx_d, dy_d, sbx0, sby0, sbx1, sby1, src);
    wire sel_glow_o = pill_hit(dx_d, dy_d, sbx0 - 12'd6, sby0 - 12'd6,
                                           sbx1 + 12'd6, sby1 + 12'd6, src + 12'd6);
    wire sel_glow   = sel_glow_o && !sel_pill;

    // 左侧三角图标（三枚按钮各一个，垂直中心不随选中变化）
    wire [11:0] iy_0 = by0_0 + 12'd38;
    wire [11:0] iy_1 = by0_1 + 12'd38;
    wire [11:0] iy_2 = by0_2 + 12'd38;
    wire icon0 = btn0 && tri_hit(dx_d, dy_d, BTN_X0 + 12'd78, iy_0);
    wire icon1 = btn1 && tri_hit(dx_d, dy_d, BTN_X0 + 12'd78, iy_1);
    wire icon2 = btn2 && tri_hit(dx_d, dy_d, BTN_X0 + 12'd78, iy_2);
    wire icon  = icon0 | icon1 | icon2;

    wire [23:0] col_sel = (btn0 & s0) ? C_BTN0 : ((btn1 & s1) ? C_BTN1 : C_BTN2);
    wire [23:0] col_off = btn0 ? C_BTN0_P : (btn1 ? C_BTN1_P : C_BTN2_P);

    // ------------------------------------------------------------------
    // 底部提示条
    // ------------------------------------------------------------------
    wire in_hint   = (dy_d >= HINT_Y0);
    wire hint_line = (dy_d == HINT_Y0) || (dy_d == (HINT_Y0 + 12'd1));

    // ------------------------------------------------------------------
    // 合成
    // ------------------------------------------------------------------
    reg [23:0] menu_rgb;
    always @* begin
        if (!de_d) begin
            menu_rgb = rgb_d;
        end else if (!act_d) begin
            menu_rgb = rgb_d;
        end else if (sel_glow) begin
            menu_rgb = C_GLOW;
        end else if (on_sel) begin
            menu_rgb = (ink_d | icon) ? C_TXT_SEL : col_sel;
        end else if (on_off) begin
            menu_rgb = (ink_d | icon) ? C_TXT_OFF : col_off;
        end else if (in_hint) begin
            menu_rgb = ink_d ? C_HINT_TX : (hint_line ? C_HINT_LN : C_HINT_BG);
        end else begin
            menu_rgb = ink_d ? C_TITLE : bg_dec;
        end
    end

    assign rgb_out = menu_rgb;

endmodule


// ===========================================================================
//  main_menu_ctrl  --  主菜单 / 图片界面的切换与选中项
//
//  行为（sd_card_clk 域；按键低有效，消抖 20ms）：
//    * 上电复位后停在「主菜单」，默认选中第 1 项（开始）
//    * 主菜单里：
//        - KEY2 短按            -> 选中项下移（到最低端后回到顶端）
//        - KEY3 短按（松开时）  -> 选中项下移（同上）
//        - KEY3 长按 0.8s 以上  -> 「确定」；选中"开始"则进入图片界面，
//                                  其余两项暂无功能（保持不动）
//    * 图片界面里：
//        - KEY3 短按            -> 返回主菜单
//
//  时钟：sd_card_clk = 50MHz（见 timing.sdc 的 rename_clock），
//        所以 CLK_FREQ_HZ 必须写 50_000_000；
//        注意不要照抄 sd_card_bmp 里的 100_000_000 —— 那是给 SD 卡分频用的，
//        和真实时钟频率不是一回事（README 里专门警告过）。
// ===========================================================================
module main_menu_ctrl #(
    parameter integer CLK_FREQ_HZ   = 50_000_000,
    parameter integer DEBOUNCE_MS   = 20,
    parameter integer LONG_PRESS_MS = 800
)(
    input  wire       clk,          // sd_card_clk
    input  wire       rst,          // 高有效复位
    input  wire       key2,         // KEY2：短按下移
    input  wire       key3,         // KEY3：短按下移 / 长按确定
    output reg        menu_active,  // 1 = 主菜单
    output reg  [1:0] sel           // 0..2
);

    localparam integer DB_CYC = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
    localparam integer LP_CYC = (CLK_FREQ_HZ / 1000) * LONG_PRESS_MS;

    // ---------------- KEY2：消抖 + 按下脉冲 ----------------
    reg        k2_s0, k2_s1, k2_stable;
    reg [31:0] k2_cnt;
    reg        k2_press;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            k2_s0     <= 1'b1;
            k2_s1     <= 1'b1;
            k2_stable <= 1'b1;
            k2_cnt    <= 32'd0;
            k2_press  <= 1'b0;
        end else begin
            k2_s0    <= key2;
            k2_s1    <= k2_s0;
            k2_press <= 1'b0;
            if (k2_s1 == k2_stable) begin
                k2_cnt <= 32'd0;
            end else if (k2_cnt >= (DB_CYC - 1)) begin
                if (k2_stable && !k2_s1)
                    k2_press <= 1'b1;
                k2_stable <= k2_s1;
                k2_cnt    <= 32'd0;
            end else begin
                k2_cnt <= k2_cnt + 32'd1;
            end
        end
    end

    // ---------------- KEY3：消抖 + 短按 / 长按 ----------------
    reg        k3_s0, k3_s1, k3_stable;
    reg [31:0] k3_cnt;
    reg        k3_press;
    reg        k3_release;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            k3_s0      <= 1'b1;
            k3_s1      <= 1'b1;
            k3_stable  <= 1'b1;
            k3_cnt     <= 32'd0;
            k3_press   <= 1'b0;
            k3_release <= 1'b0;
        end else begin
            k3_s0      <= key3;
            k3_s1      <= k3_s0;
            k3_press   <= 1'b0;
            k3_release <= 1'b0;
            if (k3_s1 == k3_stable) begin
                k3_cnt <= 32'd0;
            end else if (k3_cnt >= (DB_CYC - 1)) begin
                if (k3_stable && !k3_s1) k3_press   <= 1'b1;
                if (!k3_stable && k3_s1) k3_release <= 1'b1;
                k3_stable <= k3_s1;
                k3_cnt    <= 32'd0;
            end else begin
                k3_cnt <= k3_cnt + 32'd1;
            end
        end
    end

    // 长按计时：按下期间累加，到点后置 lp_done 并保持到松开
    reg [31:0] lp_cnt;
    reg        lp_done;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lp_cnt  <= 32'd0;
            lp_done <= 1'b0;
        end else if (k3_press) begin
            lp_cnt  <= 32'd0;
            lp_done <= 1'b0;
        end else if (!k3_stable) begin
            if (lp_cnt >= (LP_CYC - 1)) begin
                lp_cnt  <= LP_CYC - 1;
                lp_done <= 1'b1;
            end else begin
                lp_cnt <= lp_cnt + 32'd1;
            end
        end else begin
            lp_cnt  <= 32'd0;
            lp_done <= 1'b0;
        end
    end

    reg  lp_done_d;
    wire k3_long_evt = lp_done & ~lp_done_d;       // 按住到点的那一拍
    wire k3_short_evt = k3_release & ~lp_done;     // 松开且没到长按

    // lp_armed：本次按压还允许触发「长按确定」。
    //   在图片界面里 KEY3 短按是"返回主菜单"，那一次按压要作废掉长按，
    //   否则按住不放会先返回菜单、再被判成长按直接又进了图片界面。
    reg lp_armed;
    always @(posedge clk or posedge rst) begin
        if (rst)
            lp_armed <= 1'b1;
        else if (k3_release)
            lp_armed <= 1'b1;
        else if (!menu_active && k3_press)
            lp_armed <= 1'b0;
    end

    wire k3_confirm = k3_long_evt & lp_armed;
    wire step_down  = k2_press | k3_short_evt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lp_done_d   <= 1'b0;
            menu_active <= 1'b1;      // 上电先进主菜单
            sel         <= 2'd0;
        end else begin
            lp_done_d <= lp_done;
            if (menu_active) begin
                if (k3_confirm) begin
                    if (sel == 2'd0)
                        menu_active <= 1'b0;      // 「开始」-> 进入图片界面
                    // 其余两项暂无功能：保持主菜单不动
                end else if (step_down) begin
                    sel <= (sel == 2'd2) ? 2'd0 : (sel + 2'd1);
                end
            end else begin
                if (k3_press)
                    menu_active <= 1'b1;          // 图片界面 KEY3 短按 -> 回主菜单
            end
        end
    end

endmodule
