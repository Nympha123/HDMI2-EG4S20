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
    input  wire        blank,      // 1 = 不画菜单（设置面板打开时用，背景露出图片页）
    input  wire [2:0]  sel,        // 主菜单选项 0..2；目录页行 0..7
    input  wire        dir_mode,   // 1 = draw the directory page (reuses this module's ROM pipeline)
    input  wire [15:0] fnt_dout,   // 与设置面板共用的 font_rom 输出
    output wire [13:0] fnt_addr,   // 本模块的取字地址
    output wire [23:0] rgb_out
);

    // ------------------------------------------------------------------
    // 版式常量（像素坐标，屏幕 640x480）
    // ------------------------------------------------------------------
    localparam [11:0] TITLE_X  = 12'd144;   // 标题左上角（11 字 x 32 = 352 宽，水平居中：(640-352)/2）
    localparam [11:0] TITLE_Y  = 12'd40;
    localparam [11:0] TITLE_W  = 12'd352;   // 11 字 x 32（2 倍放大）- 博物馆智能展品讲解系统
    localparam [11:0] TITLE_H  = 12'd32;

    // 右侧 4 个展品图标（编钟 / 青铜鼎 / 唐三彩马 / 剑）：44x44 1bpp 精灵，
    // 显示时放大 1.5 倍（66x66），行距 96，垂直范围 56..410
    localparam [11:0] ICON_X0  = 12'd470;
    localparam [11:0] ICON_Y0  = 12'd56;

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
            // 12 边形近似圆：45° 切线 + 30°/60° 两条切线，端头看起来是半圆而不是八角
            //   7*ox+4*oy <= 8*rc  (≈30°)  和  4*ox+7*oy <= 8*rc  (≈60°)
            pill_hit = (x >= x0) && (x < x1) && (y >= y0) && (y < y1) &&
                       (om <= rc) && (os <= (rc + rc[11:1])) &&
                       (({ox, 2'b0} + {ox, 1'b0} + ox + {oy, 2'b0}) <= {rc, 3'b0}) &&
                       (({oy, 2'b0} + {oy, 1'b0} + oy + {ox, 2'b0}) <= {rc, 3'b0});
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
    //        0x8D 博 0x8E 物 0x8F 馆 0x90 系 0x91 统（2026-10-24 新增，占用原「花瓷瓶明永」5 个空闲槽）
    function [7:0] ttl_char;
        input [3:0] i;
        begin
            case (i)
                4'd0:    ttl_char = 8'h8D;   // 博
                4'd1:    ttl_char = 8'h8E;   // 物
                4'd2:    ttl_char = 8'h8F;   // 馆
                4'd3:    ttl_char = 8'hF8;   // 智
                4'd4:    ttl_char = 8'hF9;   // 能
                4'd5:    ttl_char = 8'hE0;   // 展
                4'd6:    ttl_char = 8'hED;   // 品
                4'd7:    ttl_char = 8'hFA;   // 讲
                4'd8:    ttl_char = 8'hEB;   // 解
                4'd9:    ttl_char = 8'h90;   // 系
                default: ttl_char = 8'h91;   // 统
            endcase
        end
    endfunction

    function [7:0] lbl_char;
        input [1:0] item;
        input [2:0] i;
        begin
            if (item == 2'd0) begin
                lbl_char = (i == 3'd0) ? 8'hD1 : 8'hD2;   // 目录 (web main interface)                  // 开始
            end else if (item == 2'd1) begin
                case (i)                                                  // 设置 (web main interface)
                    3'd0:    lbl_char = 8'h20;   // space (centres 设置)
                    3'd1:    lbl_char = 8'hCF;   // 设
                    3'd2:    lbl_char = 8'hD0;   // 置
                    default: lbl_char = 8'h20;   // space
                endcase
            end else begin
                // v69：第三项改成「系统简介」（4 字正好占满 4 个字格）。
                //   系=0x90 统=0x91（原有），简=0x1D 介=0x1E（
                //   tools/add_intro_title_glyphs.py 写进主字库的空槽）。
                case (i)
                    3'd0:    lbl_char = 8'h90;   // 系
                    3'd1:    lbl_char = 8'h91;   // 统
                    3'd2:    lbl_char = 8'h1D;   // 简
                    default: lbl_char = 8'h1E;   // 介
                endcase
            end
        end
    endfunction

    function [7:0] hint_char;                  // hint bar removed: always a blank cell
        input        right;
        input [2:0]  i;
        begin
            hint_char = 8'h20;
        end
    endfunction

    function [7:0] dir_char;
        input [2:0] item;
        begin
            dir_char = 8'h31 + {5'b0, item};
        end
    endfunction

    // Reuse the three existing menu rows as a compact, paged catalogue.
    // W/S still traverses all eight entries; the visible group is 0..2, 3..5,
    // or 6..7. This preserves the existing renderer and stays within LUT budget.
    wire [2:0] dir_base = (sel < 3'd3) ? 3'd0 : ((sel < 3'd6) ? 3'd3 : 3'd6);
    wire [2:0] dir_item0 = dir_base;
    wire [2:0] dir_item1 = dir_base + 3'd1;
    wire [2:0] dir_item2 = dir_base + 3'd2;

    // ------------------------------------------------------------------
    // 取字模：本拍算出地址 -> 2 拍后数据可用
    // ------------------------------------------------------------------
    wire [11:0] tcx = pixel_x - TITLE_X;                 // 0..95
    wire [11:0] tcy = pixel_y - TITLE_Y;                 // 0..31
    wire        in_title = (pixel_x >= TITLE_X) && (pixel_x < (TITLE_X + TITLE_W)) &&
                           (pixel_y >= TITLE_Y) && (pixel_y < (TITLE_Y + TITLE_H));

    wire [11:0] lbx_0 = LBL_CX - 12'd16;                 // 2 字 → 32 宽
    wire [11:0] lbx_1 = LBL_CX - 12'd32;                 // 4 字 → 64 宽
    // Directory page: all three visible rows must start their digit in the
    // same 16 px cell. The normal main menu keeps the 2-char origin of row 0,
    // but in dir_mode row 0 uses the 4-char origin (same as rows 1/2), or its
    // number sits 16 px to the right of the numbers below.
    localparam [11:0] DIR_LX = LBL_CX - 12'd32;
    wire [11:0] lbx_0_eff = dir_mode ? DIR_LX : lbx_0;
    wire [11:0] lby_0 = BTN_Y0 + LBL_DY;
    wire [11:0] lby_1 = BTN_Y0 + BTN_DY + LBL_DY;
    wire [11:0] lby_2 = BTN_Y0 + BTN_DY + BTN_DY + LBL_DY;

    wire [11:0] l0x = pixel_x - lbx_0_eff;
    wire [11:0] l1x = pixel_x - lbx_1;
    wire [11:0] l2x = pixel_x - lbx_1;
    wire [11:0] l0y = pixel_y - lby_0;
    wire [11:0] l1y = pixel_y - lby_1;
    wire [11:0] l2y = pixel_y - lby_2;

    wire in_lbl0 = (pixel_x >= lbx_0_eff) && (pixel_x < (lbx_0_eff + 12'd32)) &&
                   (pixel_y >= lby_0) && (pixel_y < (lby_0 + 12'd16));
    wire in_lbl1 = (pixel_x >= lbx_1) && (pixel_x < (lbx_1 + 12'd64)) &&
                   (pixel_y >= lby_1) && (pixel_y < (lby_1 + 12'd16));
    wire in_lbl2 = (pixel_x >= lbx_1) && (pixel_x < (lbx_1 + 12'd64)) &&
                   (pixel_y >= lby_2) && (pixel_y < (lby_2 + 12'd16));

    wire [11:0] hlx = pixel_x - HINT_LX;
    wire [11:0] hrx = pixel_x - HINT_RX;
    wire [11:0] hty = pixel_y - HINT_TY;
    wire in_hintl = 1'b0;
    wire in_hintr = 1'b0;

    reg  [9:0] rom_code;
    reg  [3:0] rom_row;
    reg  [3:0] rom_col;
    reg        rom_use;

    always @* begin
        rom_code = 8'h00;
        rom_row  = 4'h0;
        rom_col  = 4'h0;
        rom_use  = 1'b0;
        if (in_title) begin
            if (dir_mode) begin
                rom_code = (tcx[8:5] == 4'd0) ? 8'hD1 :
                           (tcx[8:5] == 4'd1) ? 8'hD2 : 8'h00; // 目录
                rom_use  = (tcx[8:5] < 4'd2);
            end else begin
                rom_code = ttl_char(tcx[8:5]);                // 11 字
                rom_use  = 1'b1;
            end
            rom_row  = tcy[4:1];                          // 2 倍放大
            rom_col  = tcx[4:1];
        end else if (in_lbl0) begin
            rom_code = dir_mode ? ((l0x[6:4] == 3'd0) ? dir_char(dir_item0) : 8'h00) : lbl_char(2'd0, l0x[6:4]);
            rom_row  = l0y[3:0];
            rom_col  = l0x[3:0];
            rom_use  = 1'b1;
        end else if (in_lbl1) begin
            rom_code = dir_mode ? ((l1x[6:4] == 3'd0) ? dir_char(dir_item1) : 8'h00) : lbl_char(2'd1, l1x[6:4]);
            rom_row  = l1y[3:0];
            rom_col  = l1x[3:0];
            rom_use  = 1'b1;
        end else if (in_lbl2) begin
            rom_code = dir_mode ? ((l2x[6:4] == 3'd0 && dir_base != 3'd6) ? dir_char(dir_item2) : 8'h00) : lbl_char(2'd2, l2x[6:4]);
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
    wire [13:0] rom_addr = rom_use ? ({4'b0, rom_code} * 16 + {10'b0, (4'd15 - rom_row)})
                                   : 13'd0;

    wire [15:0] rom_row_bits;
    // RTL font ROM (ours, 1-cycle) + one address register => 2 cycles, as this pipeline expects
    reg [13:0] rom_addr_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rom_addr_q <= 12'd0;
        else        rom_addr_q <= rom_addr;
    end
    // 字库合并：ROM 提到 top 里，与设置面板共用一份（两者页面互斥/设置叠层遮罩）
    assign rom_row_bits = fnt_dout;
    assign fnt_addr     = rom_addr_q;

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
    wire [4:0] gstep   = {1'b0, dy_d[8:5]};      // web: g = 246 - round(14*y/H)

    wire [7:0] bg_r = 8'd246 - {3'b000, gstep};   // web base grey 246 -> 232
    wire [7:0] bg_g = 8'd246 - {3'b000, gstep};
    wire [7:0] bg_b = 8'd248 - {3'b000, gstep};   // web: b = g + 2
    wire [23:0] bg  = {bg_r, bg_g, bg_b};

    // ---- shift-based colour mixer with saturation (no 8-bit wrap) ----
    function [7:0] mix8;
        input [7:0] a;          // from
        input [7:0] b;          // to
        input [3:0] sh;         // 0..10, larger = smaller step
        reg signed [10:0] d, r;
        begin
            d = $signed({3'b000, b}) - $signed({3'b000, a});
            r = $signed({3'b000, a}) + (d >>> sh);
            if (r < 0)             mix8 = 8'd0;
            else if (r > 11'sd255) mix8 = 8'hFF;
            else                   mix8 = r[7:0];
        end
    endfunction


    // ------------------------------------------------------------------
    // 168 ms tint cross-fade (was 420 ms — felt laggy on the board)
    //   The wash is mixed toward the selected button colour in 8 shift steps,
    //   timed from a counter (not per-frame), so a dropped frame cannot stall it.
    //   FADE_CYC = 8 * 2^19 -> fade_cnt[22:19] gives exactly 0..7, so the 8 steps
    //   still span the whole counter instead of stalling at step 3.
    // ------------------------------------------------------------------
    localparam integer FADE_CYC = 24'd4_194_304;       // 168 ms at 25 MHz
    wire [1:0] tint_sel = dir_mode ? 2'd0 : sel[1:0];
    reg [1:0]  sel_q;
    reg [23:0] fade_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sel_q    <= 2'd0;
            fade_cnt <= FADE_CYC;
        end else begin
            sel_q <= tint_sel;
            if (tint_sel != sel_q) fade_cnt <= 24'd0;
            else if (fade_cnt < FADE_CYC) fade_cnt <= fade_cnt + 24'd1;
        end
    end
    // 0..7 shift amount: 8 steps over 168 ms
    wire [3:0]  fstep   = fade_cnt[22:19];                // 0..7, monotonic
    wire [2:0]  fade_st = (fstep > 4'd7) ? 3'd7 : fstep[2:0];   // saturate at 7 (no wrap)
    wire [23:0] tint_new = (tint_sel == 2'd0) ? C_BTN0 : ((tint_sel == 2'd1) ? C_BTN1 : C_BTN2);
    // cross-fade the TINT from the previous colour to the new one (web mixHex(from,to,k))
    reg  [23:0] tint_prev, tint_cur;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tint_prev <= C_BTN0;
            tint_cur  <= C_BTN0;
        end else if (sel != sel_q) begin
            tint_prev <= tint_cur;
            tint_cur  <= tint_new;
        end
    end
    wire [3:0] tsh = 4'd7 - {1'b0, fade_st};               // 7..0 -> small..full step
    wire [23:0] tint = { mix8(tint_prev[23:16], tint_cur[23:16], tsh),
                         mix8(tint_prev[15:8],  tint_cur[15:8],  tsh),
                         mix8(tint_prev[7:0],   tint_cur[7:0],   tsh) };
    // constant wash strength: 1/2 then another 1/4 -> about 3/4 of the tint
    wire [3:0] msh = 4'd1;      // web DECOR_TINT = 128 -> 50% on ring/disc/dots
    wire [7:0] bg_t_r = mix8(bg_r, tint[23:16], 4'd2);
    wire [7:0] bg_t_g = mix8(bg_g, tint[15:8],  4'd2);
    wire [7:0] bg_t_b = mix8(bg_b, tint[7:0],   4'd2);
    wire [23:0] bg_t   = {bg_t_r, bg_t_g, bg_t_b};
    wire [23:0] ring_t = { mix8(C_RING[23:16], tint[23:16], msh), mix8(C_RING[15:8], tint[15:8], msh), mix8(C_RING[7:0], tint[7:0], msh) };
    wire [23:0] disc_t = { mix8(C_DISC[23:16], tint[23:16], msh), mix8(C_DISC[15:8], tint[15:8], msh), mix8(C_DISC[7:0], tint[7:0], msh) };
    wire [23:0] dot_t  = { mix8(C_DOT[23:16],  tint[23:16], msh), mix8(C_DOT[15:8],  tint[15:8],  msh), mix8(C_DOT[7:0],  tint[7:0], msh) };

    // ------------------------------------------------------------------
    // 右侧 4 个展品图标（编钟 / 青铜鼎 / 唐三彩马 / 剑）
    //   1bpp 精灵，44x44，显示时 1.5 倍放大 -> 66x66，行距 96（比原来的 64 更分散）
    //   ROM 地址：addr = idx*1936 + sy*44 + sx （1936 = 44*44）
    //   整表 4*1936 = 7744 bit，仍是一块 9K BRAM（8192x1），放大不占内存
    // 颜色跟着菜单 tint 走：底色 C_ICON 与当前选中色 50% 混合，和环/盘使用同一渐变
    // ------------------------------------------------------------------
    localparam [23:0] C_ICON = 24'h8A8FA8;      // 图标底色（浅灰蓝），与 tint 各半混合后偏亮
    wire [23:0] icon_t = { mix8(C_ICON[23:16], tint[23:16], 4'd1),
                           mix8(C_ICON[15:8],  tint[15:8],  4'd1),
                           mix8(C_ICON[7:0],   tint[7:0],   4'd1) };

    localparam [11:0] ICON_PITCH = 12'd96;      // 行距
    localparam [11:0] ICON_SIZE  = 12'd66;      // 44 * 1.5

    wire [11:0] icy    = pixel_y - ICON_Y0;
    wire        ic_yin = (pixel_y >= ICON_Y0) && (pixel_y < (ICON_Y0 + 12'd384));
    // 行号：3 个比较器（行距 96 不是 2 的幂，不能像原来那样取位）
    wire [1:0]  ic_idx = (icy >= 12'd288) ? 2'd3 :
                         (icy >= 12'd192) ? 2'd2 :
                         (icy >= 12'd96)  ? 2'd1 : 2'd0;
    // 行内偏移 = icy - idx*96（96 = 64 + 32，纯移位）
    wire [11:0] ic_yoff = icy - {4'b0, ic_idx, 6'b0} - {5'b0, ic_idx, 5'b0};
    // 四个图标左右错位：第 2、4 个右移 12 px，视觉上更活泼
    wire [11:0] ic_x0  = ICON_X0 + (ic_idx[0] ? 12'd12 : 12'd0);
    wire [11:0] icx    = pixel_x - ic_x0;
    wire        ic_xin = (pixel_x >= ic_x0) && (pixel_x < (ic_x0 + ICON_SIZE));
    wire        ic_hit = ic_xin && ic_yin && (ic_yoff < ICON_SIZE) && !dir_mode;

    // 1.5 倍采样：src = dst * 2 / 3 ≈ (dst * 342) >> 9
    //   ⚠️ 乘法必须先把操作数扩到 18 bit：Verilog 里 `icx * 9'd342` 的积只有
    //   max(12,9)=12 bit，会回绕（65*342=22230 截成 1742），取到的是图标左上角
    //   8x8 的空白区 —— 板测现象就是"四个图标全没了"。
    wire [17:0] ic_sx_m = {6'b0, icx}     * 18'd342;
    wire [17:0] ic_sy_m = {6'b0, ic_yoff} * 18'd342;
    wire [8:0]  ic_sx_r = ic_sx_m[17:9];        // 0..43
    wire [8:0]  ic_sy_r = ic_sy_m[17:9];
    wire [5:0]  ic_sx   = (ic_sx_r > 9'd43) ? 6'd43 : ic_sx_r[5:0];
    wire [5:0]  ic_sy   = (ic_sy_r > 9'd43) ? 6'd43 : ic_sy_r[5:0];

    // sy*44 = sy*32 + sy*8 + sy*4（显式扩到 13 bit，避免表达式位宽溢出）
    wire [12:0] ic_row = {2'b0, ic_sy, 5'b0} + {4'b0, ic_sy, 3'b0} + {5'b0, ic_sy, 2'b0};
    wire [12:0] ic_base = (ic_idx == 2'd0) ? 13'd0    :
                          (ic_idx == 2'd1) ? 13'd1936 :
                          (ic_idx == 2'd2) ? 13'd3872 : 13'd5808;
    wire [12:0] ic_addr = ic_hit ? (ic_base + ic_row + {7'b0, ic_sx}) : 13'd0;

    reg  [12:0] ic_addr_q;
    reg         ic_d1, ic_d2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ic_addr_q <= 13'd0;
            ic_d1     <= 1'b0;
            ic_d2     <= 1'b0;
        end else begin
            ic_addr_q <= ic_addr;
            ic_d1     <= ic_hit;
            ic_d2     <= ic_d1;      // 与 use_d / dx_d 同为 2 拍
        end
    end

    wire ic_bit;
    menu_icon_rom u_menu_icon_rom (
        .clk  (clk),
        .addr (ic_addr_q),
        .dout (ic_bit)
    );
    wire icon_pix = ic_d2 && ic_bit;


    wire ring_o = oct_hit(dx_d, dy_d, 12'd462, 12'd238, 12'd176);
    wire ring_i = oct_hit(dx_d, dy_d, 12'd462, 12'd238, 12'd144);

    // 三个装饰圆点
    wire dot1 = oct_hit(dx_d, dy_d, 12'd250, 12'd66,  12'd26);
    wire dot2 = oct_hit(dx_d, dy_d, 12'd604, 12'd100, 12'd30);
    wire dot3 = oct_hit(dx_d, dy_d, 12'd596, 12'd372, 12'd22);

    wire [23:0] bg_dec =
        dot1 ? dot_t :
        dot2 ? dot_t :
        dot3 ? dot_t :
        ((ring_o && !ring_i) ? ring_t : (ring_i ? disc_t : bg_t));

    // ------------------------------------------------------------------
    // 三枚按钮
    // ------------------------------------------------------------------
    wire s0 = dir_mode ? (sel == dir_item0) : (sel == 3'd0);
    wire s1 = dir_mode ? (sel == dir_item1) : (sel == 3'd1);
    wire s2 = dir_mode ? ((dir_base != 3'd6) && (sel == dir_item2)) : (sel == 3'd2);

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
    wire btn2 = (!dir_mode || (dir_base != 3'd6)) && pill_hit(dx_d, dy_d, b2x0, b2y0, b2x1, b2y1, rc_2);
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
    wire in_hint   = 1'b0;                          // web has no bottom hint strip on the main menu
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
        end else if (blank) begin
            // 设置面板打开：菜单整层让开，面板背景就能露出下面的图片页
            // （共用字库时菜单的字模会被面板地址带歪，所以整层不画最干净）
            menu_rgb = rgb_d;
        end else if (sel_glow) begin
            menu_rgb = C_GLOW;
        end else if (on_sel) begin
            menu_rgb = (ink_d | icon) ? C_TXT_SEL : col_sel;
        end else if (on_off) begin
            menu_rgb = (ink_d | icon) ? C_TXT_OFF : col_off;
        end else if (in_hint) begin
            menu_rgb = ink_d ? C_HINT_TX : (hint_line ? C_HINT_LN : C_HINT_BG);
        end else if (icon_pix) begin
            menu_rgb = icon_t;
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
    input  wire       nav_up,       // keypad W      : selection up
    input  wire       nav_ok,       // keypad Enter  : confirm (short press)
    input  wire       nav_back,     // keypad Q      : leave the menu
    input  wire       nav_down,     // keypad S      : selection down
    output reg        menu_active,  // 1 = 主菜单或目录页；0 = 图片界面
    output reg        dir_mode,     // 1 = 目录页；从图片返回时保留
    output reg  [2:0] sel           // 主菜单选项 0..2；目录页行 0..7
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

    // keypad pulses are ~40 ms wide, so they are edge-detected here
    reg nu_d, no_d, nb_d, nd_d;
    wire nav_up_ev   = nav_up   & ~nu_d;
    wire nav_ok_ev   = nav_ok   & ~no_d;
    wire nav_back_ev = nav_back & ~nb_d;
    wire nav_down_ev = nav_down & ~nd_d;
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
            nu_d        <= 1'b0;
            no_d        <= 1'b0;
            nb_d        <= 1'b0;
            nd_d        <= 1'b0;
            menu_active <= 1'b1;      // 上电先进主菜单
            dir_mode    <= 1'b0;
            sel         <= 3'd0;
        end else begin
            lp_done_d <= lp_done;
            nu_d      <= nav_up;
            no_d      <= nav_ok;
            nb_d      <= nav_back;
            nd_d      <= nav_down;
            if (menu_active) begin
                if (dir_mode) begin
                    if (nav_back_ev) begin
                        dir_mode <= 1'b0;             // 目录页 Q -> 主菜单
                        sel      <= 3'd0;
                    end else if (nav_ok_ev || k3_confirm) begin
                        menu_active <= 1'b0;          // 目录页 Enter -> 图片
                    end else if (nav_up_ev) begin
                        sel <= (sel == 3'd0) ? 3'd7 : (sel - 3'd1);
                    end else if (nav_down_ev) begin
                        sel <= (sel == 3'd7) ? 3'd0 : (sel + 3'd1);
                    end
                end else begin
                    if (nav_ok_ev || k3_confirm) begin
                        if (sel == 3'd0) begin
                            dir_mode <= 1'b1;         // 主菜单「目录」-> 目录页
                            sel      <= 3'd0;
                        end
                    end else if (nav_up_ev) begin
                        sel <= (sel == 3'd0) ? 3'd2 : (sel - 3'd1);   // W: up
                    end else if (nav_down_ev) begin
                        sel <= (sel == 3'd2) ? 3'd0 : (sel + 3'd1);   // S: down
                    end
                end
            end else begin
                if (k3_press || nav_back_ev)
                    menu_active <= 1'b1;          // image screen: Q returns to the page that opened it
            end
        end
    end

endmodule
