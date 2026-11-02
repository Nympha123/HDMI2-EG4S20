`timescale 1ns/1ps

// ===========================================================================
// directory_ui — 目录页（左侧展区徽标 + 展区说明，右侧 4 行展区列表）
//
//  2026-10-24 v2（方案 D）：
//    * 干掉 SDRAM 截图缩略图（96x72 RGB444 -> 8192x12 = 11 块 BRAM，
//      外加顶层的 5x5 抽样/三点平均/三个 18x18 乘法器）
//    * 左侧预览框换成「展区徽标」：216x162 @ (39,20)，图源 108x81，
//      2 倍最近邻放大，每像素 2 bit 材质码（paper/tint/accent/ink）
//      -> 4 区 x 8748 x 2bit = 69984 bit，1 片 34992x2 ROM，8 块 BRAM9K
//    * 材质码在显示侧用「每区主色 + 亮/暗派生色」还原，只有 1 个 24bit
//      4 选 1（主色）+ 1 个 4 选 1（合成）的加法器树，无乘法器
//    * 素材由 tools/make_zone_badges.py 生成（zone_badge_b0/b1.hex）
//  文本内容由 tools/make_subtitle_font.py 生成到 tools/directory_params.vh
// ===========================================================================
module directory_ui (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        de,
    input  wire [11:0] pixel_x,
    input  wire [11:0] pixel_y,
    input  wire [23:0] rgb_in,
    input  wire        active,
    input  wire [2:0]  sel,
    // v79：ext 小字库搬到顶层，与字幕共用（两者永不同屏），地址送出、数据收回
    output wire [10:0] fnt_addr,
    input  wire [15:0] fnt_dout,
    output wire [23:0] rgb_out
);
    localparam [23:0] C_BG     = 24'hEEF5FC;
    localparam [23:0] C_PANEL  = 24'hFFFFFF;
    localparam [23:0] C_TEXT   = 24'h25445C;
    // 注：原来的页面蓝 C_LINE/C_SEL/C_ACCENT 已不再使用——边框、选中行、
    //     圆点、滚动块全部改成由展区色 z_acc_c / z_half_c / z_quart_c 派生。

    // ==== 展区色（与 tools/make_zone_badges.py 的 ACCENTS 一致）====
    // 目录页的左侧整列（边框/选中行/圆点/滚动块）都跟着当前展区的颜色走，
    // 这样切到「唐三彩」时边框、徽标、列表高亮一起变琥珀色。
    wire [23:0] z_acc_c = (sel == 3'd0) ? 24'h3F9ED8 :     // 青（页面强调色）
                          (sel == 3'd1) ? 24'h3F9C86 :     // 铜绿
                          (sel == 3'd2) ? 24'hD9902E :     // 琥珀
                                         24'hC2563A;      // 朱
    // 50% 主色 + 50% 白（徽标底/面板边框），逐通道移位相加，无乘法
    wire [23:0] z_half_c = { ({2'b00, z_acc_c[23:18]} + 8'd128),
                             ({2'b00, z_acc_c[15:10]} + 8'd128),
                             ({2'b00, z_acc_c[7:2]}   + 8'd128) };
    // 25% 主色 + 75% 白（列表选中行底）
    wire [23:0] z_quart_c = { ({2'b00, z_acc_c[23:18]} + 8'd192),
                              ({2'b00, z_acc_c[15:10]} + 8'd192),
                              ({2'b00, z_acc_c[7:2]}   + 8'd192) };

    // ==== 目录页文案（由 tools/make_subtitle_font.py 生成，勿手改）====
    //   9 bit/字，首字在最低 9 位；最多 16 字
    localparam [143:0] DIR_N0 = 144'h0000000000000000000000001058240E0501;  // 曾侯乙编钟
    localparam [4:0] DIR_N0_L = 5'd5;
    localparam [143:0] DIR_N1 = 144'h00000000000000000000000000084C220F06;  // 青铜礼器
    localparam [4:0] DIR_N1_L = 5'd4;
    localparam [143:0] DIR_N2 = 144'h00000000000000000000000000000432170A;  // 唐三彩
    localparam [4:0] DIR_N2_L = 5'd3;
    localparam [143:0] DIR_N3 = 144'h0000000000000000000000001118843E1D0D;  // 越王勾践剑
    localparam [4:0] DIR_N3_L = 5'd5;
    localparam [143:0] DIR_D0 = 144'h0000000000000001058241E0C20800826B34;  // 战国 · 青铜编钟
    localparam [4:0] DIR_D0_L = 5'd9;
    localparam [143:0] DIR_D1 = 144'h0000000000000001098441E0C20800826F36;  // 商周 · 青铜礼器
    localparam [4:0] DIR_D1_L = 5'd9;
    localparam [143:0] DIR_D2 = 144'h000000000000000000004EA722080082710A;  // 唐代 · 陶俑
    localparam [4:0] DIR_D2_L = 5'd7;
    localparam [143:0] DIR_D3 = 144'h0000000000000001099EC1E0C2080082793B;  // 春秋 · 青铜兵器
    localparam [4:0] DIR_D3_L = 5'd9;
    localparam [143:0] DIR_HINT = 144'h000000000000000000000023D128EC723715;  // 请勿触摸展品
    localparam [4:0] DIR_HINT_L = 5'd6;
    localparam [143:0] DIR_Z0L0 = 144'h000000000000000000A04FE7D03814066B34;  // 战国曾侯乙墓出土
    localparam [4:0] DIR_Z0L0_L = 5'd8;
    localparam [143:0] DIR_Z0L1 = 144'h00000000000000000082C120F06A250E8541;  // 六十五件青铜编钟
    localparam [4:0] DIR_Z0L1_L = 5'd8;
    localparam [143:0] DIR_Z0L2 = 144'h0000000000000000000052A9348A1D1E8D45;  // 音域跨五个八度
    localparam [4:0] DIR_Z0L2_L = 5'd7;
    localparam [143:0] DIR_Z1L0 = 144'h00000000000000000084D3E9D4DA652E6F36;  // 商周祭祀宴飨重器
    localparam [4:0] DIR_Z1L0_L = 5'd8;
    localparam [143:0] DIR_Z1L1 = 144'h000000000000000156AAD52111AA9D4AA350;  // 鼎簋尊彝，礼制象征
    localparam [4:0] DIR_Z1L1_L = 5'd9;
    localparam [143:0] DIR_Z1L2 = 144'h00000000000000000000002B95BAD566B157;  // 多铸铭文传世
    localparam [4:0] DIR_Z1L2_L = 5'd6;
    localparam [143:0] DIR_Z2L0 = 144'h00000000000000000084CE6C15FAF576710A;  // 唐代低温铅釉陶器
    localparam [4:0] DIR_Z2L0_L = 5'd8;
    localparam [143:0] DIR_Z2L1 = 144'h00000000000000000000596C90C85D8EC561;  // 黄绿褐三彩交融
    localparam [4:0] DIR_Z2L1_L = 5'd7;
    localparam [143:0] DIR_Z2L2 = 144'h000000000000000000000021369B459ECD57;  // 多为随葬明器
    localparam [4:0] DIR_Z2L2_L = 5'd6;
    localparam [143:0] DIR_Z3L0 = 144'h000000000000000000004466B0DB5DAA793B;  // 春秋晚期越国剑
    localparam [4:0] DIR_Z3L0_L = 5'd7;
    localparam [143:0] DIR_Z3L1 = 144'h000000000000000000005BADB24B64A2813F;  // 出土时寒光如新
    localparam [4:0] DIR_Z3L1_L = 5'd7;
    localparam [143:0] DIR_Z3L2 = 144'h000000000000000000000000173B95C6E16F;  // 刃薄而锋利
    localparam [4:0] DIR_Z3L2_L = 5'd5;

    function [8:0] txt9;
        input [143:0] t;
        input [3:0]   ci;
        begin
            txt9 = t[(ci * 9) +: 9];
        end
    endfunction

    // ------------------------------------------------------------------
    // 区域判定
    // ------------------------------------------------------------------
    wire in_left   = (pixel_x >= 12'd4)   && (pixel_x < 12'd290) &&
                     (pixel_y >= 12'd4)   && (pixel_y < 12'd454);
    wire in_right  = (pixel_x >= 12'd294) && (pixel_x < 12'd636) &&
                     (pixel_y >= 12'd4)   && (pixel_y < 12'd454);
    wire in_upper  = (pixel_x >= 12'd14)  && (pixel_x < 12'd280) &&
                     (pixel_y >= 12'd14)  && (pixel_y < 12'd188);
    wire in_lower  = (pixel_x >= 12'd10)  && (pixel_x < 12'd284) &&
                     (pixel_y >= 12'd202) && (pixel_y < 12'd448);

    // ------------------------------------------------------------------
    // 展区徽标：216x162 @ (39,20) <- 108x81 图源，2 倍放大
    //   地址 addr = sel*8748 + by*108 + bx      (8748 = 108*81)
    //   每像素 2 bit 材质码：0 paper / 1 tint / 2 accent / 3 ink
    // ------------------------------------------------------------------
    localparam [11:0] BDG_X0  = 12'd39;
    localparam [11:0] BDG_Y0  = 12'd20;
    localparam [23:0] C_PAPER = 24'hF7FAFD;
    localparam [23:0] C_BINK  = 24'h25445C;      // 与页面正文同色

    wire [11:0] bdx = pixel_x - BDG_X0;
    wire [11:0] bdy = pixel_y - BDG_Y0;
    wire        bdg_hit = (pixel_x >= BDG_X0) && (pixel_x < (BDG_X0 + 12'd216)) &&
                          (pixel_y >= BDG_Y0) && (pixel_y < (BDG_Y0 + 12'd162));
    wire [6:0]  bmx = bdx[8:1];                  // 0..107
    wire [6:0]  bmy = bdy[8:1];                  // 0..80
    // 行基址 by*108 = by*128 - by*16 - by*4（移位加减，无乘法）
    wire [13:0] b_row = {bmy, 7'b0} - {3'b0, bmy, 4'b0} - {5'b0, bmy, 2'b0};

    reg [14:0] b_base;
    always @* begin
        case (sel[1:0])
            2'd0:    b_base = 15'd0;
            2'd1:    b_base = 15'd8748;
            2'd2:    b_base = 15'd17496;
            default: b_base = 15'd26244;
        endcase
    end
    wire [15:0] b_addr = bdg_hit ? ({1'b0, b_base} + {2'b0, b_row} + {9'b0, bmx})
                                 : 16'd0;

    // 地址 1 拍 + ROM 1 拍 = 2 拍；展区色也跟着延 2 拍，与 ROM 数据同相
    reg  [15:0] b_addr_q;
    reg         b_hit_d1, b_hit_d2;
    reg  [23:0] z_acc_d1, z_acc_d2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            b_addr_q <= 16'd0;
            b_hit_d1 <= 1'b0;  b_hit_d2 <= 1'b0;
            z_acc_d1 <= 24'h3F9ED8;  z_acc_d2 <= 24'h3F9ED8;
        end else begin
            b_addr_q <= b_addr;
            b_hit_d1 <= bdg_hit;   b_hit_d2 <= b_hit_d1;
            z_acc_d1 <= z_acc_c;   z_acc_d2 <= z_acc_d1;
        end
    end

    wire [1:0] b_pix;
    zone_badge_rom u_zone_badge_rom (
        .clk  (clk),
        .addr (b_addr_q),
        .dout (b_pix)
    );

    // 徽标：tint = (A>>1)+128（与生成脚本 tint_of 一致）
    wire [23:0] z_tint = { ({2'b00, z_acc_d2[23:18]} + 8'd128),
                           ({2'b00, z_acc_d2[15:10]} + 8'd128),
                           ({2'b00, z_acc_d2[7:2]}   + 8'd128) };
    wire [23:0] bdg_col = (b_pix == 2'd0) ? C_PAPER :
                          (b_pix == 2'd1) ? z_tint  :
                          (b_pix == 2'd2) ? z_acc_d2 : C_BINK;

    // ------------------------------------------------------------------
    // 文字取码（本拍算 code/row/col，2 拍后出字模）
    // ------------------------------------------------------------------
    wire [11:0] rix = pixel_x - 12'd330;      // 右侧列表文字
    wire [5:0]  ridx5 = rix[9:4];      // 0..18，5 bit 才够（4 bit 会在 x>570 回绕）
    wire [3:0]  rcol = rix[3:0];

    wire [11:0] lix = pixel_x - 12'd24;       // 左侧文字
    wire [3:0]  lidx = lix[7:4];
    wire [3:0]  lcol = lix[3:0];

    reg  [1:0]  sel_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sel_q <= 2'd0;
        else        sel_q <= sel[1:0];
    end

    wire [8:0] n0 = txt9(DIR_N0, ridx5[3:0]);
    wire [8:0] n1 = txt9(DIR_N1, ridx5[3:0]);
    wire [8:0] n2 = txt9(DIR_N2, ridx5[3:0]);
    wire [8:0] n3 = txt9(DIR_N3, ridx5[3:0]);
    wire [8:0] d0 = txt9(DIR_D0, lidx);
    wire [8:0] d1 = txt9(DIR_D1, lidx);
    wire [8:0] d2 = txt9(DIR_D2, lidx);
    wire [8:0] d3 = txt9(DIR_D3, lidx);

    // 左侧标题用的是 lidx（x-24），不能复用右侧行文字的 ridx（x-330 在左侧是负数回绕）
    wire [8:0] nl0 = txt9(DIR_N0, lidx);
    wire [8:0] nl1 = txt9(DIR_N1, lidx);
    wire [8:0] nl2 = txt9(DIR_N2, lidx);
    wire [8:0] nl3 = txt9(DIR_N3, lidx);
    wire [8:0] sel_name = (sel_q == 2'd0) ? nl0 : (sel_q == 2'd1) ? nl1 :
                          (sel_q == 2'd2) ? nl2 : nl3;
    wire [8:0] sel_desc = (sel_q == 2'd0) ? d0 : (sel_q == 2'd1) ? d1 :
                          (sel_q == 2'd2) ? d2 : d3;
    wire [4:0] sel_nlen = (sel_q == 2'd0) ? DIR_N0_L : (sel_q == 2'd1) ? DIR_N1_L :
                          (sel_q == 2'd2) ? DIR_N2_L : DIR_N3_L;
    wire [4:0] sel_dlen = (sel_q == 2'd0) ? DIR_D0_L : (sel_q == 2'd1) ? DIR_D1_L :
                          (sel_q == 2'd2) ? DIR_D2_L : DIR_D3_L;

    // v79：左下角「展区简介」三行（y = 290 / 322 / 354）。
    //   同时把「请勿触摸展品」从 y=306 挪到最下面 y=406，读起来是
    //   展区名 → 时代·类别 → 三行简介 → 底部提示。
    wire [8:0] zl0 = (sel_q == 2'd0) ? txt9(DIR_Z0L0, lidx) : (sel_q == 2'd1) ? txt9(DIR_Z1L0, lidx) :
                     (sel_q == 2'd2) ? txt9(DIR_Z2L0, lidx) : txt9(DIR_Z3L0, lidx);
    wire [8:0] zl1 = (sel_q == 2'd0) ? txt9(DIR_Z0L1, lidx) : (sel_q == 2'd1) ? txt9(DIR_Z1L1, lidx) :
                     (sel_q == 2'd2) ? txt9(DIR_Z2L1, lidx) : txt9(DIR_Z3L1, lidx);
    wire [8:0] zl2 = (sel_q == 2'd0) ? txt9(DIR_Z0L2, lidx) : (sel_q == 2'd1) ? txt9(DIR_Z1L2, lidx) :
                     (sel_q == 2'd2) ? txt9(DIR_Z2L2, lidx) : txt9(DIR_Z3L2, lidx);
    wire [4:0] zl0_len = (sel_q == 2'd0) ? DIR_Z0L0_L : (sel_q == 2'd1) ? DIR_Z1L0_L :
                         (sel_q == 2'd2) ? DIR_Z2L0_L : DIR_Z3L0_L;
    wire [4:0] zl1_len = (sel_q == 2'd0) ? DIR_Z0L1_L : (sel_q == 2'd1) ? DIR_Z1L1_L :
                         (sel_q == 2'd2) ? DIR_Z2L1_L : DIR_Z3L1_L;
    wire [4:0] zl2_len = (sel_q == 2'd0) ? DIR_Z0L2_L : (sel_q == 2'd1) ? DIR_Z1L2_L :
                         (sel_q == 2'd2) ? DIR_Z2L2_L : DIR_Z3L2_L;

    // 行文字（y = 10 + 108*r + 42 .. +16）
    wire rtxt0 = (pixel_y >= 12'd52)  && (pixel_y < 12'd68);
    wire rtxt1 = (pixel_y >= 12'd160) && (pixel_y < 12'd176);
    wire rtxt2 = (pixel_y >= 12'd268) && (pixel_y < 12'd284);
    wire rtxt3 = (pixel_y >= 12'd376) && (pixel_y < 12'd392);
    wire rtxt_x = (pixel_x >= 12'd330) && (pixel_x < 12'd620);

    reg  [8:0] t_code;
    reg  [3:0] t_row;
    reg  [3:0] t_col;
    reg        t_use;
    always @* begin
        t_code = 9'd0; t_row = 4'd0; t_col = 4'd0; t_use = 1'b0;
        if (rtxt_x) begin
            if (rtxt0) begin
                t_code = n0; t_row = pixel_y[3:0] - 4'd4; t_col = rcol; t_use = (ridx5 < DIR_N0_L);
            end else if (rtxt1) begin
                t_code = n1; t_row = pixel_y[3:0] - 4'd0; t_col = rcol; t_use = (ridx5 < DIR_N1_L);
            end else if (rtxt2) begin
                t_code = n2; t_row = pixel_y[3:0] - 4'd12; t_col = rcol; t_use = (ridx5 < DIR_N2_L);
            end else if (rtxt3) begin
                t_code = n3; t_row = pixel_y[3:0] - 4'd8; t_col = rcol; t_use = (ridx5 < DIR_N3_L);
            end
        end else if ((pixel_x >= 12'd24) && (pixel_x < 12'd280)) begin
            if ((pixel_y >= 12'd218) && (pixel_y < 12'd234)) begin
                t_code = sel_name; t_row = pixel_y[3:0] - 4'd10; t_col = lcol;
                t_use = (lidx < sel_nlen);
            end else if ((pixel_y >= 12'd262) && (pixel_y < 12'd278)) begin
                t_code = sel_desc; t_row = pixel_y[3:0] - 4'd6; t_col = lcol;
                t_use = (lidx < sel_dlen);
            end else if ((pixel_y >= 12'd290) && (pixel_y < 12'd306)) begin
                t_code = zl0; t_row = pixel_y[3:0] - 4'd2; t_col = lcol;
                t_use = (lidx < zl0_len);
            end else if ((pixel_y >= 12'd322) && (pixel_y < 12'd338)) begin
                t_code = zl1; t_row = pixel_y[3:0] - 4'd2; t_col = lcol;
                t_use = (lidx < zl1_len);
            end else if ((pixel_y >= 12'd354) && (pixel_y < 12'd370)) begin
                t_code = zl2; t_row = pixel_y[3:0] - 4'd2; t_col = lcol;
                t_use = (lidx < zl2_len);
            end else if ((pixel_y >= 12'd406) && (pixel_y < 12'd422)) begin
                t_code = txt9(DIR_HINT, lidx); t_row = pixel_y[3:0] - 4'd6; t_col = lcol;
                t_use = (lidx < DIR_HINT_L);
            end
        end
        // 空格 / 空码不画（ext ROM 里 0x20 槽位没有意义）
        if ((t_code == 9'h020) || (t_code == 9'h000))
            t_use = 1'b0;
    end

    // t_row 用 y 的低 4 位减偏移：y 起点都是 4 的倍数，减完就是 0..15
    wire [10:0] rom_addr = {t_code[6:0], 4'b0} + {7'b0, (4'd15 - t_row)};
    reg  [10:0] rom_addr_q;
    reg        use_s1, use_d;
    reg  [3:0] col_s1, col_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rom_addr_q <= 11'd0;
            use_s1 <= 1'b0;   use_d <= 1'b0;
            col_s1 <= 4'd0;   col_d <= 4'd0;
        end else begin
            rom_addr_q <= rom_addr;
            use_s1     <= t_use;
            use_d      <= use_s1;
            col_s1     <= t_col;
            col_d      <= col_s1;
        end
    end

    wire [15:0] rom_bits;
    // v79：ext 字库搬到顶层（与字幕共用，1024->2048 深 / 64->128 槽），这里只送地址、收数据
    assign fnt_addr = rom_addr_q;
    assign rom_bits = fnt_dout;
    wire ink = use_d && rom_bits[4'd15 - col_d];

    // ------------------------------------------------------------------
    // 底色（组合） + 2 拍流水
    // ------------------------------------------------------------------
    function row_hit;
        input [11:0] y;
        input [2:0]  r;
        begin
            row_hit = (y >= (12'd10 + r * 12'd108)) &&
                      (y <  (12'd10 + r * 12'd108 + 12'd100));
        end
    endfunction

    reg [23:0] base_col;
    integer i;
    always @* begin
        base_col = rgb_in;
        if (active && de) begin
            base_col = C_BG;
            if (in_left || in_right)
                base_col = C_PANEL;
            // 左侧整列跟着展区色走（右侧列表仍用页面蓝）
            if (in_left && ((pixel_x < 12'd8) || (pixel_x >= 12'd286) ||
                            (pixel_y < 12'd8) || (pixel_y >= 12'd450)))
                base_col = z_half_c;
            if (in_right && ((pixel_x < 12'd298) || (pixel_x >= 12'd632) ||
                             (pixel_y < 12'd8) || (pixel_y >= 12'd450)))
                base_col = z_half_c;               // 右侧大框同样跟随展区色

            if (in_upper) begin
                base_col = C_PANEL;
                if ((pixel_x < 12'd18) || (pixel_x >= 12'd276) ||
                    (pixel_y < 12'd18) || (pixel_y >= 12'd184))
                    base_col = z_half_c;
            end

            if (in_lower) begin
                base_col = C_PANEL;
                if ((pixel_x < 12'd14) || (pixel_x >= 12'd280) ||
                    (pixel_y < 12'd206) || (pixel_y >= 12'd444))
                    base_col = z_half_c;
                // 标题下分隔线
                if ((pixel_y >= 12'd244) && (pixel_y < 12'd246) &&
                    (pixel_x >= 12'd24) && (pixel_x < 12'd260))
                    base_col = z_half_c;
            end

            for (i = 0; i < 4; i = i + 1) begin
                if (in_right && row_hit(pixel_y, i[2:0]) &&
                    (pixel_x >= 12'd300) && (pixel_x < 12'd622)) begin
                    base_col = (sel == i[2:0]) ? z_quart_c : C_PANEL;
                    if ((pixel_x < 12'd304) || (pixel_x >= 12'd618) ||
                        (pixel_y == (12'd10 + i[2:0] * 12'd108)) ||
                        (pixel_y == (12'd10 + i[2:0] * 12'd108 + 12'd99)))
                        base_col = (sel == i[2:0]) ? z_acc_c : z_quart_c;
                    // 行首圆点
                    if ((pixel_x >= 12'd312) && (pixel_x < 12'd322) &&
                        (pixel_y >= (12'd44 + i[2:0] * 12'd108)) &&
                        (pixel_y <  (12'd54 + i[2:0] * 12'd108)))
                        base_col = z_acc_c;
                end
            end

            // 右侧滚动条：整条轨道 = 4 行高（12..444），3 道缝把它分成 4 等分，
            // 当前展区那一段实心；最后一段正好顶到底（原来 12..446 的轨道配 100 高的块，
            // 第 4 行会差 10 px 到不了底，板测看得见）。
            if (in_right && (pixel_x >= 12'd626) && (pixel_x < 12'd631) &&
                (pixel_y >= 12'd12) && (pixel_y < 12'd444))
                base_col = z_quart_c;
            // 滑块必须按行距 108 走（原来用 96，每行差 12 px，越往下越对不上缝）
            if (in_right && (pixel_x >= 12'd626) && (pixel_x < 12'd631) &&
                (pixel_y >= (12'd12 + {1'b0, sel, 6'd0} + {2'b0, sel, 5'd0} +
                             {4'b0, sel, 3'd0} + {6'b0, sel, 2'd0})) &&
                (pixel_y <  (12'd12 + {1'b0, sel, 6'd0} + {2'b0, sel, 5'd0} +
                             {4'b0, sel, 3'd0} + {6'b0, sel, 2'd0} + 12'd108)))
                base_col = z_acc_c;
            if (in_right && (pixel_x >= 12'd626) && (pixel_x < 12'd631) &&
                ((pixel_y[11:1] == 12'd60) || (pixel_y[11:1] == 12'd114) ||
                 (pixel_y[11:1] == 12'd168)))
                base_col = C_PANEL;                    // 3 道缝（2 px 宽，露出面板白）

            // 底部原来的深紫提示条（y 458..480）已删除：
            // 目录页只有 4 行、用不到那条"页脚"，屏上只剩两道看不懂的横线。
        end
    end

    reg [23:0] base_d1, base_d2;
    reg [23:0] in_d1, in_d2;
    reg        act_d1, act_d2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            base_d1 <= 24'd0; base_d2 <= 24'd0;
            in_d1   <= 24'd0; in_d2   <= 24'd0;
            act_d1  <= 1'b0;  act_d2  <= 1'b0;
        end else begin
            base_d1 <= base_col;  base_d2 <= base_d1;
            in_d1   <= rgb_in;    in_d2   <= in_d1;
            act_d1  <= active;    act_d2  <= act_d1;
        end
    end

    // 徽标列在第 2 拍之后才能取到（ROM 1 拍 + 地址 1 拍），所以不进 base_col，
    // 在最后按 b_hit_d2 覆盖上去，位置与 base_d2 同一个像素
    assign rgb_out = act_d2 ? (ink      ? C_TEXT :
                               b_hit_d2 ? bdg_col : base_d2) : in_d2;
endmodule


// ===========================================================================
// zone_badge_rom — 4 个展区徽标的 2bpp 材质码表
//
//   数据：rtl/zone_badge.hex（34992 行，每行 1 个 hex 位 = 1 像素）
//   地址：addr = zone*8748 + y*108 + x       (8748 = 108*81)
//   材质码：0 paper / 1 tint / 2 accent / 3 ink
//   容量：34992 x 2 bit = 69984 bit，综合成 8 块 9K BRAM
//   读延迟：1 拍（上游另有 1 拍地址寄存，合计 2 拍，与字模 ROM 一致）
// ===========================================================================
module zone_badge_rom (
    input  wire        clk,
    input  wire [15:0] addr,
    output reg  [1:0]  dout
);
    reg [1:0] mem [0:34991];

    initial begin
        $readmemh("zone_badge.hex", mem);
    end

    always @(posedge clk) begin
        dout <= mem[addr];
    end
endmodule
