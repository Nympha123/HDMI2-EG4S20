// time_clock.v  --  software wall clock for the settings panel's time row
//
//   Counts real seconds from the video clock and exposes HH:MM:SS as BCD bytes.
//   The values can be loaded (settings-panel correction); this is the project's
//   only time source -- there is no external RTC.
//
//   One-second tick is derived by counting VIDEO_CLK_HZ cycles, so the accuracy is
//   as good as the crystal (no drift accumulation: the counter reloads exactly).
module time_clock #(
    parameter integer CLK_HZ = 25_000_000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        load,          // pulse: take hh_in/mm_in/ss_in
    input  wire [7:0]  hh_in,         // BCD, 0x00..0x23
    input  wire [7:0]  mm_in,         // BCD, 0x00..0x59
    input  wire [7:0]  ss_in,         // BCD, 0x00..0x59
    output reg  [7:0]  hh,
    output reg  [7:0]  mm,
    output reg  [7:0]  ss
);
    // Keep the divider in two halves so the common low 16-bit increment does
    // not force a 32-bit carry chain through the clocked logic.  The compare
    // remains equivalent to the original `div >= SEC_CNT` check.
    localparam [31:0] SEC_CNT_VALUE = CLK_HZ - 1;
    localparam [15:0] SEC_CNT_HI = SEC_CNT_VALUE[31:16];
    localparam [15:0] SEC_CNT_LO = SEC_CNT_VALUE[15:0];

    reg [15:0] div_lo;
    reg [15:0] div_hi;
    reg        tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_lo <= 16'd0;
            div_hi <= 16'd0;
            tick <= 1'b0;
        end else if ((div_hi > SEC_CNT_HI) ||
                     ((div_hi == SEC_CNT_HI) && (div_lo >= SEC_CNT_LO))) begin
            div_lo <= 16'd0;
            div_hi <= 16'd0;
            tick <= 1'b1;                 // one-cycle tick
        end else if (div_lo == 16'hffff) begin
            div_lo <= 16'd0;
            div_hi <= div_hi + 16'd1;
            tick <= 1'b0;
        end else begin
            div_lo <= div_lo + 16'd1;
            tick <= 1'b0;
        end
    end

    // BCD increment helpers
    function [7:0] bcd_inc;
        input [7:0] v;
        begin
            if (v[3:0] == 4'd9) bcd_inc = {v[7:4] + 4'd1, 4'd0};
            else                bcd_inc = {v[7:4], v[3:0] + 4'd1};
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hh <= 8'h12;
            mm <= 8'h47;
            ss <= 8'h36;
        end else if (load) begin
            hh <= (hh_in > 8'h23) ? 8'h23 : hh_in;
            mm <= (mm_in > 8'h59) ? 8'h59 : mm_in;
            ss <= (ss_in > 8'h59) ? 8'h59 : ss_in;
        end else if (tick) begin
            if (ss == 8'h59) begin
                ss <= 8'h00;
                if (mm == 8'h59) begin
                    mm <= 8'h00;
                    if (hh == 8'h23) hh <= 8'h00;
                    else             hh <= bcd_inc(hh);
                end else begin
                    mm <= bcd_inc(mm);
                end
            end else begin
                ss <= bcd_inc(ss);
            end
        end
    end
endmodule
