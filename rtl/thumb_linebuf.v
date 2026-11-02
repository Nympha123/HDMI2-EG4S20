// thumb_linebuf.v  (v6 - fixed fill/publish placement)
//   Lesson-13 M1 line-buffer pixel engine, single RGB565 buffer (fits the device:
//   measured 4552 mslices of the 4900 limit; dual 24-bit buffers were 4958 -> fail).
//
//   v4 measured on the board: the four frames and the grid area were correct but the
//   picture was BLACK. Root cause: fill/publish sat in the 'busy==1' branch, but the
//   last dozen returned words arrive AFTER busy drops (busy clears when the last
//   REQUEST is issued), so rcnt never reached LAST and a row was never published.
//
//   v6 puts the fill/publish in the common 'else' of the reset chain - it runs in every
//   state - and nests the fetch FSM inside it. Everything is driven from ONE always
//   block (TD rejects a signal driven from two), and all 'if's hang off the reset edge.
//
//   SDRAM returns strictly in request order, so counting returned words gives the exact
//   buffer slot (no latency guessing). Registered read -> BRAM-friendly.
module thumb_linebuf (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        thumb_de,
    input  wire [1:0]  src_index,
    input  wire [9:0]  src_x,
    input  wire [9:0]  src_y,
    output reg         fetch_req,
    output reg  [9:0]  fetch_x,
    output reg  [9:0]  fetch_y,
    output reg         fetch_idx,
    input  wire        rd_valid,
    input  wire [23:0] rd_data,
    output wire [23:0] rgb_out
);
    localparam [8:0] LAST = 9'd159;
    // SELFTEST=1: fill the line buffer from an internal pattern instead of SDRAM, so one
    // board test tells us whether the fault is in the buffer/display path or in the fetch.
    localparam SELFTEST = 1'b1;
    // PROBE=1: drive the output with internal state instead of pixels, so one board test
    // identifies the broken stage:  R = v (a row was published), G = busy (fetch running),
    // B = hit (the display coordinate matches the buffered row/bank).
    localparam PROBE = 1'b1;
    localparam [9:0] TH   = 10'd120;

    reg [15:0] lb [0:159];
    reg        v;
    reg [9:0]  r;
    reg [1:0]  bnk;

    reg        busy;
    reg [8:0]  cnt;
    reg [1:0]  wbank;
    reg [9:0]  wrow;
    reg [8:0]  rcnt;
    reg        fill_active;

    wire hit  = v & (r == src_y) & (bnk == src_index);
    wire need = enable & thumb_de & (src_y < TH) & ~hit;

    // ---------------------------------------------------------------- fetch + fill
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fetch_req <= 1'b0; fetch_x <= 10'd0; fetch_y <= 10'd0; fetch_idx <= 1'b0;
            busy <= 1'b0; cnt <= 9'd0; wbank <= 2'd0; wrow <= 10'd0;
            rcnt <= 9'd0; fill_active <= 1'b0; v <= 1'b0; r <= 10'd0; bnk <= 2'd0;
        end else if (!enable) begin
            fetch_req <= 1'b0; busy <= 1'b0; cnt <= 9'd0;
            rcnt <= 9'd0; fill_active <= 1'b0; v <= 1'b0;
        end else begin
            // ---- (1) fill / publish: runs in EVERY state, so late returns are caught ----
            if (fill_active & (SELFTEST ? 1'b1 : rd_valid)) begin
                lb[rcnt] <= SELFTEST ? {rcnt[7:0], wrow[7:0]}
                                     : {rd_data[23:19], rd_data[15:10], rd_data[7:3]};
                if (rcnt == LAST) begin
                    r           <= wrow;
                    bnk         <= wbank;
                    v           <= 1'b1;
                    rcnt        <= 9'd0;
                    fill_active <= 1'b0;
                end else begin
                    rcnt <= rcnt + 9'd1;
                end
            end
            // ---- (2) fetch state machine (nested, so the ifs stay on the reset chain) ----
            if (!busy) begin
                fetch_req <= 1'b0;
                if (need) begin
                    busy        <= 1'b1;
                    cnt         <= 9'd0;
                    wbank       <= src_index;
                    wrow        <= src_y;
                    v           <= 1'b0;        // old row is gone; it will be published again
                    rcnt        <= 9'd0;
                    fill_active <= 1'b1;
                end
            end else begin
                fetch_req <= 1'b1;
                fetch_x   <= {cnt, 2'b00};      // 0,4,8,...,636
                fetch_y   <= wrow;
                fetch_idx <= 1'b0;
                if (cnt == LAST) begin
                    busy <= 1'b0;
                    cnt  <= 9'd0;
                end else begin
                    cnt <= cnt + 9'd1;
                end
            end
        end
    end

    // ---------------------------------------------------------------- display read
    reg [15:0] q;
    reg        q_hit;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q <= 16'd0; q_hit <= 1'b0;
        end else begin
            q     <= lb[src_x[9:2]];
            q_hit <= hit;
        end
    end

    wire [23:0] probe_rgb = {{8{v}}, {8{busy}}, {8{hit}}};
    wire [23:0] pix_rgb   = q_hit ? {q[15:11], q[15:13], q[10:5], q[10:9], q[4:0], q[4:2]}
                                  : 24'h000000;
    assign rgb_out = PROBE ? probe_rgb : pix_rgb;
endmodule
