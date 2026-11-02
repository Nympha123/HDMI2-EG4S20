// directory_screen.v  --  web directory page (geometry taken from index.html)
//
//   background #EEF5FC
//   left outer panel   x 4..290,  y 4..454   fill #FFFFFF, 1 px #BFE0F5
//     upper picture box x 14..280, y 14..192  fill #EAF4FD, 1 px #BFE0F5
//     lower text box    x 10..280, y 202..444 fill #FFFFFF, 1 px #BFE0F5
//   right list         x 294..636, y 4..454   fill #FFFFFF, 1 px #BFE0F5
//     rows x 300..622, y0 = 10 + 54*r, y1 = y0 + 49  (8 rows)
//       selected: fill #BCDEFB + 2 px accent border; idle: fill #FFFFFF + 1 px
//       dot at x 316, centre of the row, radius 5, the row's own accent
//   scrollbar x 626..630
module directory_screen (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        de,
    input  wire [11:0] px,
    input  wire [11:0] py,
    input  wire [23:0] rgb_in,
    input  wire        active,
    input  wire [2:0]  sel,
    input  wire [1:0]  scheme,
    output wire [23:0] rgb_out
);
    localparam [23:0] C_BG    = 24'hEEF5FC;
    localparam [23:0] C_PANEL = 24'hFFFFFF;
    localparam [23:0] C_LN    = 24'hBFE0F5;
    localparam [23:0] C_CHIP  = 24'hEAF4FD;
    localparam [23:0] C_SEL   = 24'hBCDEFB;

    wire [23:0] accent = (scheme == 2'd0) ? 24'h3F9ED8 : (scheme == 2'd1) ? 24'h45CEE4 :
                         (scheme == 2'd2) ? 24'h6B8CE0 : 24'h8A79E6;

    // row window decode (compares only - a divider would be huge)
    reg [3:0]  rrow;
    reg [11:0] ry;
    always @* begin
        rrow = 4'd15; ry = 12'd0;
        if ((px >= 12'd300) && (px < 12'd622)) begin
            if      ((py >= 12'd10)  && (py < 12'd59))  begin rrow = 4'd0; ry = py - 12'd10;  end
            else if ((py >= 12'd64)  && (py < 12'd113)) begin rrow = 4'd1; ry = py - 12'd64;  end
            else if ((py >= 12'd118) && (py < 12'd167)) begin rrow = 4'd2; ry = py - 12'd118; end
            else if ((py >= 12'd172) && (py < 12'd221)) begin rrow = 4'd3; ry = py - 12'd172; end
            else if ((py >= 12'd226) && (py < 12'd275)) begin rrow = 4'd4; ry = py - 12'd226; end
            else if ((py >= 12'd280) && (py < 12'd329)) begin rrow = 4'd5; ry = py - 12'd280; end
            else if ((py >= 12'd334) && (py < 12'd383)) begin rrow = 4'd6; ry = py - 12'd334; end
            else if ((py >= 12'd388) && (py < 12'd437)) begin rrow = 4'd7; ry = py - 12'd388; end
        end
    end

    // scrollbar (fixed 8-row window)
    wire in_thumb = (px >= 12'd626) && (px < 12'd630) && (py >= 12'd12) && (py < 12'd446);

    reg [23:0] pix;
    always @* begin
        pix = rgb_in;
        if (active) begin
            pix = C_BG;
            // left outer panel
            if ((px >= 12'd4) && (px < 12'd290) && (py >= 12'd4) && (py < 12'd454)) pix = C_PANEL;
            if (((px == 12'd4) || (px == 12'd289)) && (py >= 12'd4) && (py < 12'd454)) pix = C_LN;
            if ((py == 12'd4) || (py == 12'd453)) begin if ((px >= 12'd4) && (px < 12'd290)) pix = C_LN; end
            // upper picture box
            if ((px >= 12'd14) && (px < 12'd280) && (py >= 12'd14) && (py < 12'd192)) pix = C_CHIP;
            if (((px == 12'd14) || (px == 12'd279)) && (py >= 12'd14) && (py < 12'd192)) pix = C_LN;
            if (((py == 12'd14) || (py == 12'd191)) && (px >= 12'd14) && (px < 12'd280)) pix = C_LN;
            // lower text box
            if ((px >= 12'd10) && (px < 12'd280) && (py >= 12'd202) && (py < 12'd444)) pix = C_PANEL;
            if (((px == 12'd10) || (px == 12'd279)) && (py >= 12'd202) && (py < 12'd444)) pix = C_LN;
            if (((py == 12'd202) || (py == 12'd443)) && (px >= 12'd10) && (px < 12'd280)) pix = C_LN;
            // right list panel
            if ((px >= 12'd294) && (px < 12'd636) && (py >= 12'd4) && (py < 12'd454)) pix = C_PANEL;
            if (((px == 12'd294) || (px == 12'd635)) && (py >= 12'd4) && (py < 12'd454)) pix = C_LN;
            if (((py == 12'd4) || (py == 12'd453)) && (px >= 12'd294) && (px < 12'd636)) pix = C_LN;
            // rows: fill + 1 px (2 px when selected) outline
            if (rrow != 4'd15) begin
                if ((rrow == {1'b0, sel})) begin
                    pix = C_SEL;
                    if ((ry < 12'd2) || (ry >= 12'd48)) pix = accent;
                    if ((px < 12'd302) || (px >= 12'd620)) pix = accent;
                end else begin
                    pix = C_PANEL;
                    if ((ry == 12'd0) || (ry == 12'd48)) pix = C_LN;
                    if ((px == 12'd300) || (px == 12'd621)) pix = C_LN;
                end
                // per-row dot at x 316, centre y ~ 24
                if ((ry >= 12'd18) && (ry < 12'd30) &&
                    (px >= 12'd310) && (px < 12'd322)) begin
                    // 12x12 block with the corners trimmed = round enough at this size
                    if (!( (ry == 12'd18) && ((px < 12'd312) || (px >= 12'd320)) ) &&
                        !( (ry == 12'd29) && ((px < 12'd312) || (px >= 12'd320)) ))
                        pix = accent;
                end
            end
            // scrollbar
            if (in_thumb) pix = C_LN;
        end
    end

    reg act_s1, act_s2;
    reg [23:0] pix_s1, pix_s2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            act_s1 <= 1'b0; act_s2 <= 1'b0;
            pix_s1 <= 24'h0; pix_s2 <= 24'h0;
        end else begin
            act_s1 <= active; act_s2 <= act_s1;
            pix_s1 <= pix;    pix_s2 <= pix_s1;
        end
    end
    assign rgb_out = act_s2 ? pix_s2 : rgb_in;
endmodule