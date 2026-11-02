// settings_panel.v  --  settings panel matching the web build exactly (v4)
//
//   All numbers are taken from index.html:
//     SET_PANEL      x0=80 y0=78 x1=560 y1=412
//     SET_ROW_Y      128 168 208 248 288 328      (40 px pitch)
//     SET_LBL_X      122                          (label ink origin, 16 px cells)
//     SET_BAR_X0/X1  260 / 520,  SET_BAR_H 20,  handle 5 px
//     colours        panel #171B22, border #6E5FD8, selected box #FFFFFF,
//                    track #1A1E24, bar accent #F0CB4D / idle #A8B0BD, ink #E8EEF2
//     toggle         14x14, 2 px frame, lit fill #F0CB4D with a white tick
//   Rows: 亮度 对比度 波形 | 音量 轮播 | 时间
module settings_panel (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        de,
    input  wire [11:0] px,
    input  wire [11:0] py,
    input  wire [23:0] rgb_in,
    input  wire        active,
    input  wire [15:0] fnt_dout,      // 共用 font_rom 的输出
    output wire [13:0] fnt_addr,      // 取字地址
    input  wire [2:0]  sel_row,
    input  wire        time_edit,     // clock correction active
    input  wire [1:0]  time_field,    // 0 = hh, 1 = mm, 2 = ss
    input  wire [7:0]  bright,
    input  wire [7:0]  contrast,
    input  wire        wave_on,
    input  wire [1:0]  wave_step,
    input  wire [2:0]  vol_step,
    input  wire        audio_on,      // 音量行 Enter 的音频总开关
    input  wire        auto_on,
    input  wire [1:0]  auto_step,
    input  wire [7:0]  hh, mm, ss,
    output wire [23:0] rgb_out
);
    localparam [11:0] PX0 = 12'd80,  PY0 = 12'd78;
    localparam [11:0] PX1 = 12'd560, PY1 = 12'd412;
    localparam [11:0] LBL_X = 12'd122;
    localparam [11:0] BAR_X0 = 12'd260, BAR_X1 = 12'd520;
    localparam [11:0] BAR_H  = 12'd20;

    localparam [23:0] C_OUT_BG   = 24'h0E1116;
    localparam [23:0] C_PANEL_BG = 24'h171B22;
    localparam [23:0] C_PANEL_LN = 24'h6E5FD8;
    localparam [23:0] C_SEL_BOX  = 24'hFFFFFF;
    localparam [23:0] C_TRACK    = 24'h1A1E24;
    localparam [23:0] C_ACCENT   = 24'hF0CB4D;
    localparam [23:0] C_IDLE     = 24'hA8B0BD;
    localparam [23:0] C_INK      = 24'hE8EEF2;

    reg  [13:0] rom_addr;
    wire [15:0] rom_data = fnt_dout;   // 共用 top 里的 font_rom
    assign fnt_addr = rom_addr_q;

    // row window decode
    reg [2:0]  rrow;
    reg [11:0] rbase;
    reg [11:0] sel_base;
    always @* begin
        case (sel_row)
            3'd0: sel_base = 12'd128;
            3'd1: sel_base = 12'd168;
            3'd2: sel_base = 12'd208;
            3'd3: sel_base = 12'd248;
            3'd4: sel_base = 12'd288;
            default: sel_base = 12'd328;
        endcase
    end
    reg [11:0] ry;
    always @* begin
        rrow = 3'd7; ry = 12'd0; rbase = 12'd0;
        if      ((py >= 12'd128) && (py < 12'd128 + BAR_H)) begin rrow = 3'd0; ry = py - 12'd128; rbase = 12'd128; end
        else if ((py >= 12'd168) && (py < 12'd168 + BAR_H)) begin rrow = 3'd1; ry = py - 12'd168; rbase = 12'd168; end
        else if ((py >= 12'd208) && (py < 12'd208 + BAR_H)) begin rrow = 3'd2; ry = py - 12'd208; rbase = 12'd208; end
        else if ((py >= 12'd248) && (py < 12'd248 + BAR_H)) begin rrow = 3'd3; ry = py - 12'd248; rbase = 12'd248; end
        else if ((py >= 12'd288) && (py < 12'd288 + BAR_H)) begin rrow = 3'd4; ry = py - 12'd288; rbase = 12'd288; end
        else if ((py >= 12'd328) && (py < 12'd328 + BAR_H)) begin rrow = 3'd5; ry = py - 12'd328; rbase = 12'd328; end
    end

    // label ink rows are the top 16 px of each row window
    wire lbl_row_ok = (ry < 12'd16);

    // bar fill fraction in pixels (0..260)
    wire [11:0] bar_w = BAR_X1 - BAR_X0;
    wire [11:0] fill_b = {4'd0, bright};                    // /255 of 260 ~ bright
    wire [11:0] fill_c = {4'd0, contrast};

    // step-value text windows (audio row 2, wave row 3, auto row 4)
    wire in_audio_step = (rrow == 3'd2) && (px >= 12'd288) && (px < 12'd352);
    wire in_wave_step  = (rrow == 3'd3) && (px >= 12'd288) && (px < 12'd352);
    wire in_auto_step  = (rrow == 3'd4) && (px >= 12'd288) && (px < 12'd336);

    reg [7:0]  gcode;
    reg [3:0]  grow, gcol;
    reg        guse;
    reg [11:0] fx0, fx1;
    reg        boxhit, boxink;
    reg        gacc;      // this glyph uses the accent colour (enabled toggle value)
    reg [23:0] pix;
    reg [11:0] lx, lw;

    always @* begin
        gcode = 8'h20; grow = 4'd0; gcol = 4'd0; guse = 1'b0; gacc = 1'b0; boxhit = 1'b0; boxink = 1'b0;
        pix   = rgb_in;

        if (active) begin
            // 面板外不再涂死黑：把底层画面压到一半亮度（原来是 C_OUT_BG = #0E1116，
            // 屏上整个背景变黑，观感像"死机"）。菜单那一层在 settings 打开时已经
            // 整层让开（main_menu.blank），所以这里不会有共用字库的字模泄漏。
            pix = {1'b0, rgb_in[23:17], 1'b0, rgb_in[15:9], 1'b0, rgb_in[7:1]};

            // ---- panel body + 1 px border ----
            if ((px >= PX0) && (px < PX1) && (py >= PY0) && (py < PY1)) begin
                pix = C_PANEL_BG;
                if ((px == PX0) || (px == (PX1 - 12'd1)) ||
                    (py == PY0) || (py == (PY1 - 12'd1))) pix = C_PANEL_LN;
            end

            // ---- selected row: white hollow box (web uses a 1 px box) ----
            // web style selection: a white hollow box around the row (C_SEL_BOX)
            // web selection box: drawHollowRect(SET_LBL_X-16, y-12, SET_BAR_X1+16, y+SET_BAR_H+12, white, 2)
            if ((px >= 12'd106) && (px < 12'd536) &&
                (py >= (sel_base - 12'd12)) && (py < (sel_base + 12'd32))) begin
                pix = C_PANEL_BG;
                if ((py < (sel_base - 12'd10)) || (py >= (sel_base + 12'd30)) ||
                    (px < 12'd108) || (px >= 12'd534))
                    pix = C_SEL_BOX;                        // 2 px white frame
            end

            // ---- title 设置 ----
            if ((px >= 12'd296) && (px < 12'd328) &&
                (py >= (PY0 + 12'd12)) && (py < (PY0 + 12'd28))) begin
                gcode = (px < 12'd312) ? 8'hCF : 8'hD0;
                grow  = py - (PY0 + 12'd12);
                gcol  = px - 12'd296;      // 296 is not 16-aligned: use the offset, not px[3:0]
                guse  = 1'b1;
            end

            // ---- labels ----
            if ((rrow != 3'd7) && lbl_row_ok) begin
                lx = px - LBL_X;
                lw = (rrow == 3'd1) ? 12'd48 : 12'd32;
                if ((px >= LBL_X) && (lx < lw)) begin
                    gcol = lx[3:0];
                    grow = ry[3:0];
                    case (rrow)
                        3'd0: gcode = (lx < 12'd16) ? 8'h80 : 8'h81;
                        3'd1: if (lx < 12'd16)      gcode = 8'hC7;
                              else if (lx < 12'd32) gcode = 8'hC8;
                              else                  gcode = 8'h81;
                        3'd2: gcode = (lx < 12'd16) ? 8'hF0 : 8'hF1;   // 音量 (web row 2)
                        3'd3: gcode = (lx < 12'd16) ? 8'hF2 : 8'hF7;   // 波形 (web row 3)
                        3'd4: gcode = (lx < 12'd16) ? 8'h87 : 8'h88;
                        default: gcode = (lx < 12'd16) ? 8'hFD : 8'h9F;
                    endcase
                    guse = 1'b1;
                end
            end

            // ---- bar rows (0,1): brightness / contrast ----
            if ((rrow <= 3'd1) && (px >= BAR_X0 - 12'd1) && (px < BAR_X1 + 12'd1) &&
                (py >= (rbase) - 12'd1) &&
                (py < (rbase) + BAR_H + 12'd1)) begin
                pix = C_TRACK;
                // 1 px outer frame
                if ((px == BAR_X0 - 12'd1) || (px == BAR_X1) ||
                    (py == (rbase) - 12'd1) ||
                    (py == (rbase) + BAR_H))
                    pix = (sel_row == rrow) ? C_ACCENT : 24'h3A424E;
                // fill
                if ((px >= BAR_X0) && (px < BAR_X1) &&
                    (py >= (rbase)) &&
                    (py < (rbase) + BAR_H)) begin
                    if (px < (BAR_X0 + (rrow == 3'd0 ? fill_b : fill_c)))
                        pix = (sel_row == rrow) ? C_ACCENT : C_IDLE;
                end
            end

            // ---- toggle rows (2,3,4): 14x14 box with a tick when on ----
            // row 2 = audio on/off + level, rows 3/4 = wave / auto
            if ((rrow == 3'd2) || (rrow == 3'd3) || (rrow == 3'd4)) begin
                if ((px >= BAR_X0) && (px < (BAR_X0 + 12'd14)) &&
                    (py >= (rbase)) &&
                    (py < (rbase) + 12'd14)) begin
                    pix = ((px == BAR_X0) || (px == BAR_X0 + 12'd13) ||
                           (py == (rbase)) ||
                           (py == (rbase) + 12'd13))
                          ? C_INK
                          : ((rrow == 3'd2) ? (audio_on ? C_ACCENT : C_PANEL_BG)
                             : (rrow == 3'd3) ? (wave_on ? C_ACCENT : C_PANEL_BG)
                                              : (auto_on ? C_ACCENT : C_PANEL_BG));
                end
            end

            // web: an enabled toggle value is drawn in the accent colour
            if ((((rrow == 3'd2) && audio_on) ||
                 ((rrow == 3'd3) && wave_on) ||
                 ((rrow == 3'd4) && auto_on)) &&
                (ry < 12'd16) && (px >= 12'd288) && (px < 12'd352))
                gacc = 1'b1;

            // web: 2 px accent frame around the field being corrected (TIME_FIELDS spans)
            if (time_edit) begin
                // field x range: hh 260..308, mm 308..356, ss 356..404
                fx0 = (time_field == 2'd0) ? 12'd260 : ((time_field == 2'd1) ? 12'd308 : 12'd356);
                fx1 = (time_field == 2'd0) ? 12'd308 : ((time_field == 2'd1) ? 12'd356 : 12'd404);
                if ((px >= (fx0 - 12'd3)) && (px < (fx1 + 12'd3)) &&
                    (py >= 12'd324) && (py < 12'd352)) begin
                    boxhit = 1'b1;
                    if ((px < (fx0 - 12'd1)) || (px >= (fx1 + 12'd1)) ||
                        (py < 12'd326) || (py >= 12'd350))
                        boxink = 1'b1;          // 2 px frame
                end
            end

            // step values: audio 25/50/100, wave 25/50/100, auto 5/10/15 秒
            if ((in_audio_step || in_wave_step || in_auto_step) && (ry < 12'd16)) begin
                gcol = (px - 12'd288);
                grow = ry[3:0];
                if (rrow == 3'd2) begin
                    // 音量行：方框开关 + 25/50/100%（关闭时显示“关”）
                    case ((px - 12'd288) >> 4)
                        2'd0: gcode = !audio_on ? 8'hF3 :
                                          ((vol_step == 2'd0) ? 8'h31 :
                                           ((vol_step == 2'd1) ? 8'h32 :
                                            ((vol_step == 2'd2) ? 8'h35 : 8'h31)));
                        2'd1: gcode = !audio_on ? 8'h20 :
                                          ((vol_step == 2'd0) ? 8'h30 :
                                           ((vol_step == 2'd1) ? 8'h35 :
                                            ((vol_step == 2'd2) ? 8'h30 : 8'h30)));
                        2'd2: gcode = !audio_on ? 8'h20 :
                                          ((vol_step == 2'd3) ? 8'h30 : 8'h25);
                        default: gcode = (audio_on && (vol_step == 2'd3)) ? 8'h25 : 8'h20;
                    endcase
                    guse = 1'b1;
                end else if (rrow == 3'd3) begin
                    case ((px - 12'd288) >> 4)
                        2'd0: gcode = !wave_on ? 8'hF3 :
                                          ((wave_step == 2'd0) ? 8'h32 :
                                           ((wave_step == 2'd1) ? 8'h35 : 8'h31));
                        2'd1: gcode = !wave_on ? 8'h20 :
                                          ((wave_step == 2'd0) ? 8'h35 : 8'h30);
                        2'd2: gcode = !wave_on ? 8'h20 :
                                          ((wave_step == 2'd2) ? 8'h30 : 8'h25);
                        default: gcode = (wave_on && (wave_step == 2'd2)) ? 8'h25 : 8'h20;
                    endcase
                    guse = 1'b1;
                end else begin
                    // 轮播行：方框开关 + 5/10/15 秒（2 秒档已移除）
                    case ((px - 12'd288) >> 4)
                        2'd0: gcode = !auto_on ? 8'hF3 :
                                          ((auto_step == 2'd0) ? 8'h35 : 8'h31);
                        2'd1: gcode = !auto_on ? 8'h20 :
                                          ((auto_step == 2'd0) ? 8'hF4 :
                                           ((auto_step == 2'd1) ? 8'h30 : 8'h35));
                        default: gcode = !auto_on ? 8'h20 :
                                          ((auto_step == 2'd0) ? 8'h20 : 8'hF4);
                    endcase
                    guse = 1'b1;
                end
            end
            // ---- time row (5): HH:MM:SS, 16 px cells from x = 260 ----
            // web: the field being corrected is drawn in the accent colour inside a 2 px box
            if (time_edit && (rrow == 3'd5) && (ry < 12'd16)) begin
                if (((time_field == 2'd0) && (px >= 12'd260) && (px < 12'd308)) ||
                    ((time_field == 2'd1) && (px >= 12'd308) && (px < 12'd356)) ||
                    ((time_field == 2'd2) && (px >= 12'd356) && (px < 12'd404)))
                    gacc = 1'b1;
                if ((px >= 12'd257) && (px < 12'd411) &&
                    (((px - 12'd257) < 12'd2) || ((px - 12'd257) >= 12'd152) ||
                     (((px >= 12'd306) && (px < 12'd309)) || ((px >= 12'd354) && (px < 12'd357))))) begin
                    // frame edges only (vertical strokes at field boundaries)
                end
            end
            if ((rrow == 3'd5) && (ry < 12'd16) && (px >= 12'd260) && (px < (12'd260 + 12'd128))) begin
                lx   = px - 12'd260;
                gcol = lx[3:0];
                grow = ry[3:0];
                case (lx[7:4])
                    4'd0: gcode = 8'h30 + {4'd0, hh[7:4]};
                    4'd1: gcode = 8'h30 + {4'd0, hh[3:0]};
                    4'd2: gcode = 8'h3A;
                    4'd3: gcode = 8'h30 + {4'd0, mm[7:4]};
                    4'd4: gcode = 8'h30 + {4'd0, mm[3:0]};
                    4'd5: gcode = 8'h3A;
                    4'd6: gcode = 8'h30 + {4'd0, ss[7:4]};
                    default: gcode = 8'h30 + {4'd0, ss[3:0]};
                endcase
                guse = 1'b1;
            end
        end
    end

    always @* rom_addr = {4'b0, gcode} * 16 + {9'b0, (4'd15 - grow)};

    reg  [13:0] rom_addr_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rom_addr_q <= 14'd0;
        else        rom_addr_q <= rom_addr;
    end

    // font_rom has TWO cycles of latency (see the FIX 14 note in the other modules),
    // so the geometry is delayed by two cycles as well.
    reg        use_s1, use_s2, act_s1, act_s2;
    reg [3:0]  col_s1, col_s2;
    reg        gacc_s1, gacc_s2, boxink_s1, boxink_s2;
    reg [23:0] pix_s1, pix_s2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            use_s1 <= 1'b0; use_s2 <= 1'b0; act_s1 <= 1'b0; act_s2 <= 1'b0;
            col_s1 <= 4'd0; col_s2 <= 4'd0;
            gacc_s1 <= 1'b0; gacc_s2 <= 1'b0;
            boxink_s1 <= 1'b0; boxink_s2 <= 1'b0;
            pix_s1 <= 24'h0; pix_s2 <= 24'h0;
        end else begin
            use_s1 <= guse;   use_s2 <= use_s1;
            act_s1 <= active; act_s2 <= act_s1;
            col_s1 <= gcol;   col_s2 <= col_s1;
            gacc_s1 <= gacc;  gacc_s2 <= gacc_s1;
            boxink_s1 <= boxink; boxink_s2 <= boxink_s1;
            pix_s1 <= pix;    pix_s2 <= pix_s1;
        end
    end

    wire ink = use_s2 & rom_data[4'd15 - col_s2];

    // 2026-10-25 v27：面板外那层"压暗背景"必须用**当前像素**。
    // 以前它走的是 pix → pix_s1 → pix_s2 这条 2 拍流水（为了和字模对齐），
    // 于是设置一打开，整层背景（连同底下的主菜单）就右移 2 px，左边还会露出
    // 上一行末尾的像素 —— 用户看到的就是"背景轻微右移 + 左边一条白竖线"。
    // 现在：只压暗当前 rgb_in（零延迟，和不开面板时完全对齐）；面板自己的
    // 框/条/文字仍走 pix_s2（它们本来就是按 2 拍流水调的位置）。
    wire [23:0] bg_dim = {1'b0, rgb_in[23:17], 1'b0, rgb_in[15:9], 1'b0, rgb_in[7:1]};
    wire        pix_is_bg = (pix == bg_dim);      // 这一拍 pix 只是"压暗的背景"
    reg         pbg_s1, pbg_s2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin pbg_s1 <= 1'b0; pbg_s2 <= 1'b0; end
        else        begin pbg_s1 <= pix_is_bg; pbg_s2 <= pbg_s1; end
    end

    assign rgb_out = !active     ? rgb_in :
                     pbg_s2      ? bg_dim :
                     boxink_s2   ? 24'hF0CB4D :
                     (ink ? (gacc_s2 ? 24'hF0CB4D : C_INK) : pix_s2);   // enabled toggle values in the accent colour
endmodule
