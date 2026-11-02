// keypad_scan.v  --  4x3 matrix keypad scanner (J1 1..8, C4 unused)
//
//   Wiring (as specified by the board):
//     rows (driven, active low): R1=D14, R2=G12, R3=H13, R4=J14
//     cols (inputs, internal pull-up, active low): C1=G11, C2=F13, C3=H14
//
//   Key map (row-col):
//     R1C1 = SW1  -> W  (up)
//     R2C1 = SW2  -> A  (dec / left)
//     R3C1 = SW3  -> D  (inc / right)
//     R4C1 = SW4  -> S  (down)
//     R1C2 = SW15 -> Enter (confirm)
//     R1C3 = SW5  -> Q  (back)
//     everything else is reserved and ignored.
//
//   Behaviour:
//     * rows are pulled low one at a time, 250 us each -> 1 kHz frame.
//     * a column is sampled after a short settle delay, then the whole 12-bit
//       matrix is debounced by requiring 20 consecutive identical frames.
//     * one key at a time wins (lowest index) so ghosting cannot produce
//       phantom presses on this small matrix.
//     * confirm also reports a long press (CONFIRM_LONG_MS = 800 ms).
module keypad_scan #(
    parameter integer CLK_HZ         = 50_000_000,
    parameter integer ROW_US         = 250,     // per-row scan time
    parameter integer SETTLE_US      = 8,       // column settle delay
    parameter integer DEBOUNCE_MS    = 20,
    parameter integer CONFIRM_LONG_MS= 800
)(
    input  wire       clk,
    input  wire       rst_n,

    output reg  [3:0] row_n,        // to keypad rows (active low)
    input  wire [2:0] col_n,        // from keypad columns (active low, pulled up)

    output reg        up_pulse,     // W
    output reg        down_pulse,   // S
    output reg        dec_pulse,    // A
    output reg        inc_pulse,    // D
    output reg        back_pulse,   // Q
    output reg        confirm_short,// Enter short press
    output reg        confirm_long, // Enter held >= 800 ms
    output reg  [5:0] key_held      // debug: current stable keys (1 = pressed)
);
    localparam integer ROW_CYC    = (CLK_HZ / 1_000_000) * ROW_US;     // cycles per row
    localparam integer SETTLE_CYC = (CLK_HZ / 1_000_000) * SETTLE_US;  // settle cycles
    localparam integer DB_FRAMES  = (DEBOUNCE_MS * 1000) / (ROW_US * 4);   // frames of stability
    localparam integer LONG_CYC   = (CLK_HZ / 1000) * CONFIRM_LONG_MS;     // cycles for long press

    // ---------------- row scan ----------------
    reg [15:0] row_t;              // time inside the current row
    reg [1:0]  row_i;              // which row is driven low
    reg [2:0]  col_q;              // sampled columns of the current row
    reg [11:0] raw;                // raw matrix image {row3,row2,row1,row0} x 3 cols

    wire [15:0] row_sel = (row_i == 2'd0) ? 16'd1 :
                          (row_i == 2'd1) ? 16'd2 :
                          (row_i == 2'd2) ? 16'd3 : 16'd4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_t <= 16'd0;
            row_i <= 2'd0;
            row_n <= 4'b1110;      // drive R1 low first
            col_q <= 3'b111;
        end else begin
            if (row_t >= ROW_CYC[15:0]) begin
                row_t <= 16'd0;
                row_i <= row_i + 2'd1;
                // one row low at a time
                case (row_i + 2'd1)
                    2'd0: row_n <= 4'b1110;
                    2'd1: row_n <= 4'b1101;
                    2'd2: row_n <= 4'b1011;
                    default: row_n <= 4'b0111;
                endcase
            end else begin
                row_t <= row_t + 16'd1;
            end
            // sample the columns after the settle delay of each row
            if (row_t == SETTLE_CYC[15:0])
                col_q <= col_n;
        end
    end

    // latch the sample into raw once per row (at the end of that row's slot)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) raw <= 12'hFFF;
        else if (row_t == ROW_CYC[15:0] - 16'd1) begin
            case (row_i)
                2'd0: raw[2:0]   <= col_q;
                2'd1: raw[5:3]   <= col_q;
                2'd2: raw[8:6]   <= col_q;
                default: raw[11:9] <= col_q;
            endcase
        end
    end

    // ---------------- frame tick + debounce ----------------
    reg        frame_tick;
    reg [11:0] cand;               // candidate stable image
    reg [11:0] stable;             // debounced image (1 = pressed)
    reg [7:0]  db_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_tick <= 1'b0;
            cand <= 12'h000;
            stable <= 12'h000;
            db_cnt <= 8'd0;
        end else begin
            frame_tick <= (row_i == 2'd3) && (row_t == ROW_CYC[15:0] - 16'd2);

            if (frame_tick) begin
                if (raw != cand) begin
                    cand   <= raw;
                    db_cnt <= 8'd0;
                end else if (db_cnt < DB_FRAMES[7:0]) begin
                    db_cnt <= db_cnt + 8'd1;
                end else begin
                    stable <= cand;
                end
            end
        end
    end

    // ---------------- one key at a time (lowest index wins) ----------------
    wire [11:0] pressed = ~stable;        // active low on the pins -> press = 1

    wire k_up      = pressed[0];          // R1C1  SW1
    wire k_confirm = pressed[1];          // R1C2  SW15
    wire k_back    = pressed[2];          // R1C3  SW5
    wire k_dec     = pressed[3];          // R2C1  SW2
    wire k_inc     = pressed[6];          // R3C1  SW3
    wire k_down    = pressed[9];          // R4C1  SW4

    // priority encoder: only the lowest set bit is accepted this frame
    reg  [5:0] chosen;
    always @* begin
        chosen = 6'b000000;
        if      (k_up)      chosen = 6'b000001;
        else if (k_confirm) chosen = 6'b000010;
        else if (k_back)    chosen = 6'b000100;
        else if (k_dec)     chosen = 6'b001000;
        else if (k_inc)     chosen = 6'b010000;
        else if (k_down)    chosen = 6'b100000;
    end

    // ---------------- edges + long press ----------------
    reg [5:0] chosen_d;
    reg [31:0] hold_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            chosen_d <= 6'b000000;
            hold_cnt <= 32'd0;
            up_pulse <= 1'b0; down_pulse <= 1'b0;
            dec_pulse <= 1'b0; inc_pulse <= 1'b0;
            back_pulse <= 1'b0;
            confirm_short <= 1'b0; confirm_long <= 1'b0;
            key_held <= 6'b000000;
        end else begin
            up_pulse      <= 1'b0;
            down_pulse    <= 1'b0;
            dec_pulse     <= 1'b0;
            inc_pulse     <= 1'b0;
            back_pulse    <= 1'b0;
            confirm_short <= 1'b0;
            confirm_long  <= 1'b0;

            chosen_d <= chosen;
            key_held <= chosen;

            // short-press pulses on the rising edge of the chosen key
            if (chosen[0] && !chosen_d[0]) up_pulse      <= 1'b1;
            if (chosen[1] && !chosen_d[1]) confirm_short <= 1'b1;
            if (chosen[2] && !chosen_d[2]) back_pulse    <= 1'b1;
            if (chosen[3] && !chosen_d[3]) dec_pulse     <= 1'b1;
            if (chosen[4] && !chosen_d[4]) inc_pulse     <= 1'b1;
            if (chosen[5] && !chosen_d[5]) down_pulse    <= 1'b1;

            // long press on the confirm key
            if (chosen[1]) begin
                if (hold_cnt < LONG_CYC[31:0]) begin
                    hold_cnt <= hold_cnt + 32'd1;
                    if (hold_cnt == LONG_CYC[31:0] - 32'd1) confirm_long <= 1'b1;
                end
            end else begin
                hold_cnt <= 32'd0;
            end
        end
    end
endmodule
