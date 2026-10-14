// page_view.v  (lesson-13 page view, CROP version - deliberately has NO line store)
//
//   Requirement: one image per page, shown on the left and vertically centred, with the
//   right side kept for a fixed title. The previous attempts used a line buffer to make a
//   scaled thumbnail; they were distorted on the board (and the store disturbed the place
//   and route of the video path). This version does NO scaling:
//     * the window is a straight 1:1 pass-through of the streamed source pixels, so it
//       uses the already-proven display path - nothing to misalign, no phase guesswork;
//     * consume = de, exactly the normal streaming cadence (the reader never stalls);
//     * the window shows source columns 0..319 / rows 120..359 of the current bank;
//     * the right side is a dark text area; the title (????) is drawn from its own
//       font_rom instance.
module page_view (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,        // page mode
    input  wire        de,
    input  wire [11:0] px,
    input  wire [11:0] py,
    input  wire [23:0] rgb_in,        // current streamed source pixel
    output wire        consume,
    output reg  [23:0] rgb_out
);
    // window: 320 x 240, left side, vertically centred
    localparam [11:0] WXN = 12'd480;
    localparam [11:0] WY0 = 12'd60;
    localparam [11:0] WYN = 12'd360;

    // title: 4 glyphs of 16x16 at x 360..423, y 190
    localparam [11:0] TX0 = 12'd500;
    localparam [11:0] TY0 = 12'd232;

    wire in_win = enable & (px < WXN) & (py >= WY0) & (py < (WY0 + WYN));

    assign consume = de;              // normal 1:1 streaming - no stall, no store

    localparam [7:0] TITLE0 = 8'hCB;  // ?
    localparam [7:0] TITLE1 = 8'hCC;  // ?
    localparam [7:0] TITLE2 = 8'hCD;  // ?
    localparam [7:0] TITLE3 = 8'hCE;  // ?

    wire [11:0] tdx = px - TX0;
    wire [11:0] tdy = py - TY0;
    wire in_title = enable & (px >= TX0) & (px < (TX0 + 12'd64)) &
                             (py >= TY0) & (py < (TY0 + 12'd16));
    wire [1:0]  tcol  = tdx[5:4];
    wire [7:0]  tslot = (tcol == 2'd0) ? TITLE0 : (tcol == 2'd1) ? TITLE1 :
                        (tcol == 2'd2) ? TITLE2 : TITLE3;
    wire [11:0] taddr = ({4'b0, tslot} << 4) + {8'b0, (4'd15 - tdy[3:0])};

    wire [15:0] tbits;
    font_rom u_pv_font (
        .clk  (clk),
        .addr (taddr),
        .dout (tbits)
    );

    reg       in_title_d;
    reg [3:0] tcol_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_title_d <= 1'b0;
            tcol_d     <= 4'd0;
        end else begin
            in_title_d <= in_title;
            tcol_d     <= tdx[3:0];
        end
    end
    wire t_hit = in_title_d & tbits[4'd15 - tcol_d];

    always @* begin
        if (!enable)     rgb_out = rgb_in;        // full screen: untouched pass-through
        else if (t_hit)  rgb_out = 24'hFFFFFF;    // title text
        else if (in_win) rgb_out = rgb_in;        // 1:1 crop of the source
        else             rgb_out = 24'h101418;    // dark page background
    end
endmodule
