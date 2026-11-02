`timescale 1ns/1ps
// ===========================================================================
// sysinfo_panel — 「系统简介」四页说明页（主菜单第三项，只读）
//
//   v69：整页重做。4 页图文，A/D（左右键）翻页，Back 退出：
//       页 1 四个展区 / 页 2 分区配乐 / 页 3 自适应缩放 / 页 4 参数口径
//
//   版面（640x480，与 tools/make_sysintro_page.py 一一对应）：
//     卡片 80..560 x 78..412；标题「系统简介」16 px 居中 (288,92)；
//     分隔线 y=120；页标题 2 倍 32 px (96,168)；正文 8 px 一格 56 格/行
//     (96,224) 行距 40、3 行；按键提示 (96,372)；页码 "n/4" (520,372)。
//
//   字库（2 块 ROM，全部由脚本生成，RTL 里没有硬编码字槽）：
//     * sysintro_text.hex  1024 x 9 bit（1 块 BRAM9K）
//         addr = {page[1:0], line[1:0], slot[5:0]}，slot = 8 px 一格
//         line0 = 页标题（slot 0..4）+ 标题字（slot 8..11）
//         line1..3 = 正文
//         码值 0x000..0x07F = ASCII，0x080|n = 汉字左半，0x100|n = 汉字右半
//     * font_rom_sys.hex   128 槽 x 16 行（4 块 BRAM9K），汉字 16x16
//     ASCII 仍走主字库 font_rom（与设置面板共用），取其中 8 px 宽的字心
//     （bit11..bit4），所以数字/英文不再占 16 px 格。
//
//   流水：地址（组合）-> 文本 ROM 输出/坐标寄存 -> 字模 ROM 输出 = 2 拍，
//         与 settings_panel 相同，叠层不错位。
// ===========================================================================
module sysinfo_panel (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        de,
    input  wire [11:0] px,
    input  wire [11:0] py,
    input  wire [23:0] rgb_in,
    input  wire        active,
    input  wire [1:0]  page,
    input  wire [15:0] fnt_dout,      // 主字库输出（ASCII）
    output wire [13:0] fnt_addr,      // 主字库地址
    output wire [23:0] rgb_out
);

    // ---------------- 版面 ----------------
    localparam [11:0] X0 = 12'd80,  X1 = 12'd560;
    localparam [11:0] Y0 = 12'd78,  Y1 = 12'd412;
    localparam [11:0] TTL_X = 12'd288, TTL_Y = 12'd92;      // 16 px 网格, 4 字
    localparam [11:0] SEP_Y = 12'd120, SEP_X0 = 12'd96, SEP_X1 = 12'd544;
    localparam [11:0] HG_X = 12'd96,  HG_Y = 12'd168;       // 32 px 网格, 5 字
    localparam [11:0] BD_X = 12'd96,  BD_Y = 12'd224;       // 8 px 一格, 56 格
    localparam [11:0] FT_X = 12'd96,  FT_Y = 12'd372;       // 21 格
    localparam [11:0] PG_X = 12'd520, PG_Y = 12'd372;       // 3 格
    localparam [11:0] BD_END = 12'd120;                     // 3 行 x 40

    localparam [23:0] C_EDGE  = 24'h6E5FD8;
    localparam [23:0] C_PANEL = 24'h171B22;
    localparam [23:0] C_LINE  = 24'h3A424E;
    localparam [23:0] C_TITLE = 24'hF0CB4D;
    localparam [23:0] C_VAL   = 24'hCFE8F2;
    localparam [23:0] C_FOOT  = 24'h8A93A6;

    // ---------------- 区域 ----------------
    wire in_card = de && (px >= X0) && (px < X1) && (py >= Y0) && (py < Y1);
    wire in_ttl  = de && (px >= TTL_X) && (px < (TTL_X + 12'd64)) &&
                        (py >= TTL_Y) && (py < (TTL_Y + 12'd16));
    wire in_head = de && (px >= HG_X) && (px < (HG_X + 12'd160)) &&
                        (py >= HG_Y) && (py < (HG_Y + 12'd32));

    wire [11:0] dby = py - BD_Y;
    wire        bd_v = de && (py >= BD_Y) && (dby < BD_END);
    wire [1:0]  bline = (dby < 12'd40) ? 2'd0 : ((dby < 12'd80) ? 2'd1 : 2'd2);
    wire [5:0]  boff  = (dby < 12'd40) ? dby[5:0] :
                        ((dby < 12'd80) ? (dby - 12'd40) : (dby - 12'd80));
    wire        in_bd = bd_v && (boff < 6'd16) &&
                        (px >= BD_X) && (px < (BD_X + 12'd448));

    wire in_ft = de && (px >= FT_X) && (px < (FT_X + 12'd176)) &&
                      (py >= FT_Y) && (py < (FT_Y + 12'd16));
    wire in_pg = de && (px >= PG_X) && (px < (PG_X + 12'd24)) &&
                      (py >= PG_Y) && (py < (PG_Y + 12'd16));

    // ---------------- 坐标 -> 字槽 / 行 / 列 ----------------
    wire [11:0] tx = px - TTL_X;
    wire [11:0] ty = py - TTL_Y;
    wire [11:0] hx = px - HG_X;
    wire [11:0] hy = py - HG_Y;
    wire [11:0] bx = px - BD_X;

    // 注意：一行里不能混着写不同位宽的 wire！`wire [1:0] a = ..., b = ...;`
    // 会把 b 也声明成 2 bit。v69 初版就是 `wire [1:0] tcol=..., tgx3=tx[3:0]`
    // 让 tgx3 只剩 2 bit（列号 0..3 循环）、hgx3 只剩 3 bit（0..7 循环），
    // 屏上表现就是标题/页标题"重影"（一个字被画成 4 份 / 2 份叠在一起）。
    wire [1:0] tcol = tx[5:4];                      // 16 px 格，字格 0..3
    wire [3:0] tgx3 = tx[3:0];                      // 字内列 0..15
    wire [2:0] hcol = hx[8:5];                      // 32 px 格，字格 0..4
    wire [3:0] hgx3 = hx[4:1];                      // 字内列 0..15（2 倍放大）
    wire [3:0] hgy3 = hy[4:1];
    wire [5:0] bslot = bx[8:3];
    wire [2:0] bxoff = bx[2:0];

    // 文本 ROM 地址：{page, line, slot}
    wire [5:0] ttl_slot = 6'd8 + {4'd0, tcol};
    wire [5:0] head_slot = {3'd0, hcol};
    wire [1:0] bd_line = 2'd1 + bline;
    wire [9:0] taddr = in_ttl  ? {page, 2'd0, ttl_slot} :
                       in_head ? {page, 2'd0, head_slot} :
                                 {page, bd_line, bslot};

    // ---------------- 8 px ASCII：按键提示 + 页码 ----------------
    wire [11:0] ftx = px - FT_X;
    wire [11:0] pgx = px - PG_X;
    wire [11:0] fty = py - FT_Y;
    wire [2:0] axoff = in_pg ? pgx[2:0] : ftx[2:0];
    wire [3:0] arow  = fty[3:0];
    wire [2:0] pg_ci = pgx[4:3];

    reg [6:0] ft_code;
    always @* begin
        if (in_pg) begin
            case (pg_ci)
                3'd0:    ft_code = 7'h31 + {5'd0, page};   // 1..4
                3'd1:    ft_code = 7'h2F;                  // /
                default: ft_code = 7'h34;                  // 4
            endcase
        end else begin
            case (px[11:3] - (FT_X >> 3))              // 8 px 格序号 0..21
                5'd0:  ft_code = 7'h41;   // A
                5'd1:  ft_code = 7'h2F;   // /
                5'd2:  ft_code = 7'h44;   // D
                5'd3:  ft_code = 7'h3A;   // :
                5'd4:  ft_code = 7'h53;   // S
                5'd5:  ft_code = 7'h57;   // W
                5'd6:  ft_code = 7'h49;   // I
                5'd7:  ft_code = 7'h54;   // T
                5'd8:  ft_code = 7'h43;   // C
                5'd9:  ft_code = 7'h48;   // H
                5'd10: ft_code = 7'h20;
                5'd11: ft_code = 7'h20;
                5'd12: ft_code = 7'h42;   // B
                5'd13: ft_code = 7'h41;   // A
                5'd14: ft_code = 7'h43;   // C
                5'd15: ft_code = 7'h4B;   // K
                5'd16: ft_code = 7'h3A;   // :
                5'd17: ft_code = 7'h45;   // E
                5'd18: ft_code = 7'h58;   // X
                5'd19: ft_code = 7'h49;   // I
                5'd20: ft_code = 7'h54;   // T
                default: ft_code = 7'h20;
            endcase
        end
    end

    // ---------------- 第 1 拍：文本 ROM 读出 + 坐标寄存 ----------------
    wire [8:0] rom_q;
    sysintro_text_rom u_text (
        .clk  (clk),
        .addr (taddr),
        .dout (rom_q)
    );

    reg [3:0] row_s1;
    reg [2:0] xoff_s1;
    reg [6:0] acode_s1;
    reg [3:0] arow_s1;
    reg       ttl_s1, head_s1, bd_s1, ft_s1;
    reg       act_s1, card_s1, sep_s1, pbd_s1;
    reg [3:0] tgx_s1, hgx_s1;

    wire sep_hit = de && (py == SEP_Y) && (px >= SEP_X0) && (px < SEP_X1);
    wire pbd_hit = in_card && ((px == X0) || (px == (X1 - 12'd1)) ||
                               (py == Y0) || (py == (Y1 - 12'd1)));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_s1  <= 4'd0;
            xoff_s1 <= 3'd0;
            acode_s1 <= 7'd32;
            arow_s1 <= 4'd0;
            ttl_s1  <= 1'b0;
            head_s1 <= 1'b0;
            bd_s1   <= 1'b0;
            ft_s1   <= 1'b0;
            act_s1  <= 1'b0;
            card_s1 <= 1'b0;
            sep_s1  <= 1'b0;
            pbd_s1  <= 1'b0;
            tgx_s1  <= 4'd0;
            hgx_s1  <= 4'd0;
        end else begin
            row_s1   <= in_ttl ? ty[3:0] : (in_head ? hgy3 : boff[3:0]);
            xoff_s1  <= in_bd ? bxoff : axoff;
            acode_s1 <= ft_code;
            arow_s1  <= arow;
            ttl_s1   <= in_ttl;
            head_s1  <= in_head;
            bd_s1    <= in_bd;
            ft_s1    <= in_ft || in_pg;
            act_s1   <= active;
            card_s1  <= in_card;
            sep_s1   <= sep_hit;
            pbd_s1   <= pbd_hit;
            tgx_s1   <= tgx3;
            hgx_s1   <= hgx3;
        end
    end

    // ---------------- 第 2 拍：字模口径 ----------------
    // 文本 ROM 是"组合地址 + 输出寄存"（1 拍），所以这一拍直接用 rom_q 组字模地址；
    // 若再把 rom_q 打一拍，码值会比坐标晚 1 像素，8 px 格边界上会插进前一个字的残边。
    // 汉字：标题/页标题固定整格，正文按码值的左右半决定 x 偏移；
    // 空槽（0x020 = 空格）走 ASCII 分支、点阵为空，不会误取小字库的怪字。
    // 注意：底栏/页码是纯 ASCII，它们那几列的文本 ROM 地址会落到正文行上，
    //       所以必须用 !ft_s1 把汉字分支挡掉，否则底栏会画出正文的汉字。
    wire       cjk_s1  = rom_q[7] & ~ft_s1;
    wire [3:0] gxs     = ttl_s1  ? tgx_s1 :
                         head_s1 ? hgx_s1 :
                                   {rom_q[8], xoff_s1};
    wire [6:0] asc     = ft_s1 ? acode_s1 : rom_q[6:0];
    wire [3:0] asc_row = ft_s1 ? arow_s1  : row_s1;

    wire [10:0] sys_addr_c = {rom_q[6:0], (4'd15 - row_s1)};
    assign fnt_addr = {3'b000, asc, 4'h0} + {10'd0, (4'd15 - asc_row)};

    wire [15:0] sys_dout;
    font_rom_sys u_font_sys (
        .clk  (clk),
        .addr (sys_addr_c),
        .dout (sys_dout)
    );

    reg       act_s2, card_s2, sep_s2, gold_s2, txt_s2, cjk_s2, foot_s2, pbd_s2;
    reg [3:0] gx_s2;
    reg [2:0] xoff_s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            act_s2  <= 1'b0;
            card_s2 <= 1'b0;
            sep_s2  <= 1'b0;
            pbd_s2  <= 1'b0;
            gold_s2 <= 1'b0;
            txt_s2  <= 1'b0;
            cjk_s2  <= 1'b0;
            foot_s2 <= 1'b0;
            gx_s2   <= 4'd0;
            xoff_s2 <= 3'd0;
        end else begin
            act_s2  <= act_s1;
            card_s2 <= card_s1;
            sep_s2  <= sep_s1;
            pbd_s2  <= pbd_s1;
            gold_s2 <= ttl_s1 | head_s1;
            txt_s2  <= ttl_s1 | head_s1 | bd_s1 | ft_s1;
            cjk_s2  <= cjk_s1;
            foot_s2 <= ft_s1;
            gx_s2   <= gxs;
            xoff_s2 <= xoff_s1;
        end
    end

    wire       pix_on = cjk_s2 ? sys_dout[15 - gx_s2] : fnt_dout[11 - xoff_s2];
    wire [23:0] glyph_col = gold_s2 ? C_TITLE : (foot_s2 ? C_FOOT : C_VAL);
    wire [23:0] bg_dim = {1'b0, rgb_in[23:17], 1'b0, rgb_in[15:9], 1'b0, rgb_in[7:1]};

    assign rgb_out = !act_s2            ? rgb_in  :
                     (txt_s2 && pix_on) ? glyph_col :
                     sep_s2             ? C_LINE :
                     pbd_s2             ? C_EDGE :
                     card_s2            ? C_PANEL : bg_dim;
endmodule

// ---------------------------------------------------------------------------
// 文本 ROM：1024 x 9，addr = {page[1:0], line[1:0], slot[5:0]}（1 块 BRAM9K）
// ---------------------------------------------------------------------------
module sysintro_text_rom (
    input  wire        clk,
    input  wire [9:0]  addr,
    output reg  [8:0]  dout
);
    reg [8:0] mem [0:1023];
    initial begin
        $readmemh("sysintro_text.hex", mem);
    end
    always @(posedge clk) begin
        dout <= mem[addr];
    end
endmodule

// ---------------------------------------------------------------------------
// 小字库：128 槽 x 16 行 = 2048 x 16（4 块 BRAM9K）
// addr = 槽号*16 + (15 - 显示行)
// ---------------------------------------------------------------------------
module font_rom_sys (
    input  wire        clk,
    input  wire [10:0] addr,
    output reg  [15:0] dout
);
    reg [15:0] mem [0:2047];
    initial begin
        $readmemh("font_rom_sys.hex", mem);
    end
    always @(posedge clk) begin
        dout <= mem[addr];
    end
endmodule
