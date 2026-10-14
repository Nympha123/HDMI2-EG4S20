// page_view.v  (lesson-13 page view: one image per page + a text column)
//
//   Requirement: one image per page, small, placed left and vertically centred;
//   the right side keeps room for a fixed title (图片信息). No selection box.
//
//   Implementation notes (this is the version that AVOIDS the previous failures):
//     * The reader is left in its normal sequential streaming mode (thumb_mode = 0).
//       The old design messed with the read address/cadence, which produced wrap-around
//       and never-published buffers. Here only the *display* side is filtered.
//     * Horizontal x4 shrink: the store keeps every 4th source sample (160 per line,
//       written at px[1:0]==0 into st[px>>2]); the window column k reads st[k], i.e.
//       source column 4k -> 160 window columns cover the whole 640-wide source.
//     * Vertical x4 shrink: the reader is only advanced on every 4th display row
//       (consume = fill_row). On the other rows it simply stalls (safe: its fifo keeps
//       what it has), so the same stored line is shown for 4 display rows.
//     * The store is 160 x RGB565 = 2560 bits, the geometry already proven to route.
//     * Title: 图片信息 = slots 0xCB 0xCC 0xCD 0xCE drawn from its own font_rom.
module page_view (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,        // page mode
    input  wire        de,            // display data enable
    input  wire [11:0] px,
    input  wire [11:0] py,
    input  wire [23:0] rgb_in,        // current streamed source pixel
    output wire        consume,       // 1 = pop one source pixel this cycle
    output reg  [23:0] rgb_out
);
    // window: 160 x 120 at x 0..159, y 180..299  (left side, vertically centred)
        localparam [11:0] WX0 = 12'd0,   WY0 = 12'd120;   // 320x240 -> centred vertically
        localparam [11:0] WXN = 12'd320, WYN = 12'd240;

    // title: 4 glyphs of 16x16 at x 360..423, y 190
    localparam [11:0] TX0 = 12'd360, TY0 = 12'd190;

    wire in_win   = enable & (px < WXN) & (py >= WY0) & (py < (WY0 + WYN));
    wire fill_row = enable & (py[0] == 2'd0);        // advance the reader every 2nd row (x2)          // advance the reader every 4th row

    assign consume = enable ? fill_row : de;

    // ---------------------------------------------------------------- line store
        reg [15:0] st [0:319];                               // 320 x 565 = 5120 bits
    wire [6:0] st_wr = px[8:2];                          // every 4th sample -> 160 entries
    always @(posedge clk) begin
        if (de & fill_row & (px[0] == 1'b0))
            st[px[8:1]] <= {rgb_in[23:19], rgb_in[15:10], rgb_in[7:3]};   // every 2nd sample -> 320   // RGB888 -> 565
    end

    // ---------------------------------------------------------------- title glyphs
    localparam [7:0] TITLE0 = 8'hCB;   // 图
    localparam [7:0] TITLE1 = 8'hCC;   // 片
    localparam [7:0] TITLE2 = 8'hCD;   // 信
    localparam [7:0] TITLE3 = 8'hCE;   // 息

    wire [11:0] tdx = px - TX0;
    wire [11:0] tdy = py - TY0;
    wire in_title = enable & (px >= TX0) & (px < (TX0 + 12'd64)) & (py >= TY0) & (py < (TY0 + 12'd16));
    wire [1:0]  tcol = tdx[5:4];
    wire [7:0]  tslot = (tcol == 2'd0) ? TITLE0 : (tcol == 2'd1) ? TITLE1 : (tcol == 2'd2) ? TITLE2 : TITLE3;
    wire [11:0] taddr = ({4'b0, tslot} << 4) + {8'b0, (4'd15 - tdy[3:0])};

    wire [15:0] tbits;
    font_rom u_pv_font (
        .clk  (clk),
        .addr (taddr),
        .dout (tbits)
    );

    reg in_title_d;
    reg [3:0] tcol_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin in_title_d <= 1'b0; tcol_d <= 4'd0; end
        else        begin in_title_d <= in_title; tcol_d <= tdx[3:0]; end
    end
    wire t_hit = in_title_d & tbits[4'd15 - tcol_d];

    // ---------------------------------------------------------------- output
        wire [23:0] win_rgb = {st[px[8:0]][15:11], st[px[8:0]][15:13],
                           st[px[8:0]][10:5],  st[px[8:0]][10:9],
                           st[px[8:0]][4:0],   st[px[8:0]][4:2]};

    always @* begin
        if (!enable)                rgb_out = rgb_in;
        else if (t_hit)             rgb_out = 24'hFFFFFF;   // title text
        else if (in_win)            rgb_out = win_rgb;
        else                        rgb_out = 24'h101418;   // dark page background
    end
endmodule
