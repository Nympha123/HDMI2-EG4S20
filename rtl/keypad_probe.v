// keypad_probe.v  --  assumption-free 8-pin connectivity probe for the keypad header
//
//   The keypad occupies eight header pins (J1 1..8). We do NOT assume which of them
//   are rows and which are columns: every pin is configured as an inout with an
//   internal pull-up, and we walk a single low level across all eight pins. If any
//   key is pressed, the pin it connects to reads low while the driven pin is low.
//
//     for k in 0..7:  drive pin k low (others released, pulled up), wait, read the other 7
//                     -> if pin j reads low, then a key bridges pins k and j
//
//   Results:
//     pair_valid  : a bridging pair has been seen at least once
//     first_pin   : the driven pin index (0..7 -> pin 1..8)
//     second_pin  : the pin that read low (0..7 -> pin 1..8)
//
//   This tells the FPGA side exactly how the keypad is wired, whatever the silkscreen
//   says, so the scan mapping can be corrected from data instead of from assumptions.
module keypad_probe #(
    parameter integer CLK_HZ      = 50_000_000,
    parameter integer STEP_HZ     = 2_000   // per-pin step rate
)(
    input  wire       clk,
    input  wire       rst_n,

    inout  wire [3:0] pin_a,     // header pins 1..4
    inout  wire [3:0] pin_b,     // header pins 5..8

    output reg        pair_valid,
    output reg  [2:0] first_pin,
    output reg  [2:0] second_pin,
    output reg  [7:0] all_low    // 1 = that pin read low in the last sweep
);
    localparam integer DIV = CLK_HZ / STEP_HZ;

    reg [31:0] div_cnt;
    reg [2:0]  k;                 // currently driven pin (0..7)
    reg        phase;             // 0 = drive, 1 = sample
    reg [7:0]  drive_low;         // one-hot: pin driven low this step
    reg [7:0]  pins_seen;         // pins observed low this sweep

    wire [7:0] pins_in = {pin_b, pin_a};

    // Each pin: driven low only when selected, otherwise released (pull-up holds it high)
    assign pin_a[0] = drive_low[0] ? 1'b0 : 1'bz;
    assign pin_a[1] = drive_low[1] ? 1'b0 : 1'bz;
    assign pin_a[2] = drive_low[2] ? 1'b0 : 1'bz;
    assign pin_a[3] = drive_low[3] ? 1'b0 : 1'bz;
    assign pin_b[0] = drive_low[4] ? 1'b0 : 1'bz;
    assign pin_b[1] = drive_low[5] ? 1'b0 : 1'bz;
    assign pin_b[2] = drive_low[6] ? 1'b0 : 1'bz;
    assign pin_b[3] = drive_low[7] ? 1'b0 : 1'bz;

    // index of the lowest pin that reads low, excluding the driven one
    reg [2:0] low_idx;
    reg       low_found;
    integer   i;
    always @* begin
        low_idx   = 3'd0;
        low_found = 1'b0;
        for (i = 7; i >= 0; i = i - 1) begin
            if ((i != k) && !pins_in[i]) begin
                low_idx   = i[2:0];
                low_found = 1'b1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt    <= 32'd0;
            k          <= 3'd0;
            phase      <= 1'b0;
            drive_low  <= 8'h00;
            pins_seen  <= 8'h00;
            pair_valid <= 1'b0;
            first_pin  <= 3'd0;
            second_pin <= 3'd0;
            all_low    <= 8'h00;
        end else begin
            if (div_cnt < DIV[31:0]) begin
                div_cnt <= div_cnt + 32'd1;
            end else begin
                div_cnt <= 32'd0;

                if (!phase) begin
                    // drive the selected pin low and let the bus settle
                    drive_low <= (8'h01 << k);
                    phase     <= 1'b1;
                end else begin
                    // sample: remember which pins are low, and latch the first pair seen
                    pins_seen <= pins_in;
                    all_low   <= ~pins_in;
                    if (low_found && !pair_valid) begin
                        pair_valid <= 1'b1;
                        first_pin  <= k;
                        second_pin <= low_idx;
                    end
                    drive_low <= 8'h00;
                    phase     <= 1'b0;
                    k         <= (k == 3'd7) ? 3'd0 : (k + 3'd1);
                end
            end
        end
    end
endmodule
