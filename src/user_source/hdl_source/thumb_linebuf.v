// thumb_linebuf.v
//   Lesson-13 M1 (2x2 thumbnail screen) pixel engine, line-buffer architecture.
//
//   WHY: the previous per-pixel point-read design (thumb_req into media_frame_reader)
//   could never be aligned: the SDRAM + FIFO return latency N is unknown and varies
//   with controller arbitration, so the display always showed the pixel requested N
//   cycles EARLIER -> the image wrapped horizontally. Measured on the board twice.
//
//   HOW: fetch a whole source row of one thumbnail into a line buffer, then display
//   from the buffer at exact coordinates -> phase error is zero by construction.
//     * thumbnail_layout gives (thumb_de, source_index, source_x, source_y) for the
//       display pixel; source_y = local_y*4, source_x = local_x*4 (nearest, x4 zoom).
//     * For a given display row, one source row is needed (4 display rows share it).
//     * This engine fetches that row (160 pixels, source_x = 0,4,8,...,636) into the
//       inactive buffer while the previous row is displayed from the active one.
//     * Display reads buf_active[local_x >> 2] -> exact, no wrap.
//
//   Interface with the reader: the engine does NOT get direct SDRAM access. The top
//   muxes the reader's src_x/src_y/thumb_req from this engine while a fetch is in
//   progress (the reader is otherwise idle in thumbnail mode), and feeds the returned
//   sdram_rd_data back in as rd_data/rd_valid. Every returned word belongs to this
//   engine while thumb_mode is on.
//
//   Zero phase error, low bandwidth: 160 reads per source row, 120 source rows per
//   thumbnail per frame, 4 thumbs -> 76,800 reads/frame (~4.6 M/s at 60 Hz), i.e.
//   far below the full-screen path's 18.4 M/s.
module thumb_linebuf (
    input  wire        clk,        // video_clk (25 MHz)
    input  wire        rst_n,
    input  wire        enable,     // thumbnail mode
    // display side (from thumbnail_layout)
    input  wire        thumb_de,   // inside a thumbnail that has data
    input  wire [1:0]  src_index,  // which bank this thumbnail shows
    input  wire [9:0]  src_x,      // source column of the *current display pixel* (local_x*4)
    input  wire [9:0]  src_y,      // source row of the current display pixel (local_y*4)
    // fetch side out to the reader mux
    output reg         fetch_req,  // one read request this cycle
    output reg  [9:0]  fetch_x,    // source column to read (0,4,...,636)
    output reg  [9:0]  fetch_y,    // source row to read
    output reg         fetch_idx,  // buffer index being filled (0 = A, 1 = B)
    // returned data from the reader
    input  wire        rd_valid,
    input  wire [23:0] rd_data,
    // display side out
    output wire [23:0] rgb_out
);
    // ---------------------------------------------------------------- state
    localparam [9:0] TW = 10'd160;      // thumbnail width in source pixels
    localparam [9:0] TH = 10'd120;

    reg        buf_v[0:1];              // buffer valid flags
    reg [9:0]  buf_row[0:1];            // source row held (0 = invalid)
    reg [1:0]  buf_bank[0:1];
    reg [23:0] linebuf0[0:159];         // buffer A
    reg [23:0] linebuf1[0:159];         // buffer B

    reg        fetch_busy;
    reg [9:0]  fetch_cnt;               // 0..159 fetched so far
    reg [1:0]  want_bank;
    reg [9:0]  want_row;

    // which buffer is displayed / filled
    wire [1:0] buf_idx_now = want_row[0];   // simple ping-pong on the source row parity

    // ---------------------------------------------------------------- fetch trigger
    // Start a new row when the display enters a source row that is not buffered yet.
    wire need_new = enable & thumb_de & (src_y < TH) & (src_x < TW) &
                    ~(buf_v[1'b0] & (buf_row[0] == src_y) & (buf_bank[0] == src_index)) &
                    ~(buf_v[1'b1] & (buf_row[1] == src_y) & (buf_bank[1] == src_index));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fetch_req  <= 1'b0;
            fetch_x    <= 10'd0;
            fetch_y    <= 10'd0;
            fetch_idx  <= 1'b0;
            fetch_busy <= 1'b0;
            fetch_cnt  <= 10'd0;
            want_bank  <= 2'd0;
            want_row   <= 10'd0;
            buf_v[0]   <= 1'b0;
            buf_v[1]   <= 1'b0;
            buf_row[0] <= 10'd0;
            buf_row[1] <= 10'd0;
            buf_bank[0]<= 2'd0;
            buf_bank[1]<= 2'd0;
        end else if (!enable) begin
            // leave thumbnail mode: invalidate everything so the next entry refetches
            fetch_req  <= 1'b0;
            fetch_busy <= 1'b0;
            fetch_cnt  <= 10'd0;
            buf_v[0]   <= 1'b0;
            buf_v[1]   <= 1'b0;
        end else if (!fetch_busy) begin
            fetch_req <= 1'b0;
            if (need_new) begin
                // pick the buffer that is NOT currently displayed
                fetch_idx <= ~buf_idx_now;
                want_bank <= src_index;
                want_row  <= src_y;
                fetch_cnt <= 10'd0;
                fetch_busy<= 1'b1;
                buf_v[fetch_idx] <= 1'b0;      // invalidate the target while filling
            end
        end else begin
            // issue one read per cycle for 160 source pixels: x = 0,4,8,...,636
            fetch_y   <= want_row;
            fetch_x   <= fetch_cnt << 2;       // *4
            fetch_req <= 1'b1;
            if (fetch_cnt == (TW - 1'b1)) begin
                fetch_busy <= 1'b0;
                fetch_cnt  <= 10'd0;
            end else begin
                fetch_cnt <= fetch_cnt + 1'b1;
            end
        end
    end

    // ---------------------------------------------------------------- fill
    // Returned words arrive in request order: index = the fetch_cnt of that request,
    // which is 2 cycles behind on the wire. Keep a small pipeline of the index.
    reg [9:0] idx_d0, idx_d1, idx_d2;
    reg       busy_d0, busy_d1, busy_d2;
    reg [1:0] bk_d0, bk_d1, bk_d2;
    reg [9:0] rw_d0, rw_d1, rw_d2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idx_d0 <= 10'd0; idx_d1 <= 10'd0; idx_d2 <= 10'd0;
            busy_d0<= 1'b0;  busy_d1<= 1'b0;  busy_d2<= 1'b0;
            bk_d0  <= 2'd0;  bk_d1  <= 2'd0;  bk_d2  <= 2'd0;
            rw_d0  <= 10'd0; rw_d1  <= 10'd0; rw_d2  <= 10'd0;
        end else begin
            idx_d0 <= fetch_cnt; idx_d1 <= idx_d0; idx_d2 <= idx_d1;
            busy_d0<= fetch_busy; busy_d1<= busy_d0; busy_d2<= busy_d1;
            bk_d0  <= want_bank;  bk_d1  <= bk_d0;  bk_d2  <= bk_d1;
            rw_d0  <= want_row;   rw_d1  <= rw_d0;  rw_d2  <= rw_d1;
        end
    end

    always @(posedge clk) begin
        if (enable & rd_valid & busy_d2) begin
            if (fetch_idx) linebuf1[idx_d2] <= rd_data[23:0];
            else           linebuf0[idx_d2] <= rd_data[23:0];
            if (idx_d2 == (TW - 1'b1)) begin
                buf_row[fetch_idx]  <= rw_d2;
                buf_bank[fetch_idx] <= bk_d2;
                buf_v[fetch_idx]    <= 1'b1;
            end
        end
    end

    // ---------------------------------------------------------------- display
    // Exact slice: source column index = local_x / 4, buffer index = src_x >> 2.
    wire [8:0] rd_idx = src_x[9:2];        // 0..159
    wire       use_a  = buf_v[0] & (buf_row[0] == src_y) & (buf_bank[0] == src_index);
    wire       use_b  = buf_v[1] & (buf_row[1] == src_y) & (buf_bank[1] == src_index);

    assign rgb_out = use_a ? linebuf0[rd_idx] :
                     use_b ? linebuf1[rd_idx] : 24'h000000;
endmodule
