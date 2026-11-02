`timescale 1ns/1ps

// KEY4 parameter menu. A short press cycles the volume through five steps;
// holding the key for one second before release cycles the slideshow period
// through four steps. The selected value is offered to the persistence
// service through the cfg sampling port, so it takes effect immediately and
// the existing dual-key chord still controls Flash storage.
module param_menu_controller #(
    parameter integer CLKS_PER_MS = 50000,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer LONG_HOLD_MS = 1000
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        key4_n,
    input  wire        service_ready,
    input  wire [7:0]  live_volume,
    input  wire [31:0] live_period_ms,
    output reg         cfg_update_valid,
    output reg  [31:0] cfg_period_ms,
    output reg  [7:0]  cfg_volume,
    output reg         menu_event,
    output reg  [1:0]  menu_kind,   // 0 = volume step, 1 = period step
    output reg  [3:0]  menu_level   // new level index for reporting
);
    localparam integer VOLUME_STEPS = 5;
    localparam integer PERIOD_STEPS = 4;

    // Synthesis-safe lookup tables. TD does not honour `initial`-initialised
    // ROM arrays (they synthesize to undriven nets, HDL-5314), so the tables
    // are expressed as case functions that inline into combinational logic.
    function [7:0] volume_lut;
        input [3:0] level;
        begin
            case (level)
                4'd0:    volume_lut = 8'd0;
                4'd1:    volume_lut = 8'd64;
                4'd2:    volume_lut = 8'd128;
                4'd3:    volume_lut = 8'd192;
                default: volume_lut = 8'd255;
            endcase
        end
    endfunction

    function [31:0] period_lut;
        input [3:0] level;
        begin
            case (level)
                4'd0:    period_lut = 32'd2000;
                4'd1:    period_lut = 32'd5000;
                4'd2:    period_lut = 32'd10000;
                default: period_lut = 32'd30000;
            endcase
        end
    endfunction

    function [3:0] volume_level;
        input [7:0] value;
        begin
            case (value)
                8'd0:   volume_level = 4'd0;
                8'd64:  volume_level = 4'd1;
                8'd128: volume_level = 4'd2;
                8'd192: volume_level = 4'd3;
                default: volume_level = 4'd4;
            endcase
        end
    endfunction

    function [3:0] period_level;
        input [31:0] value;
        begin
            if (value < 32'd3500)       period_level = 4'd0;
            else if (value < 32'd7500)  period_level = 4'd1;
            else if (value < 32'd20000) period_level = 4'd2;
            else                        period_level = 4'd3;
        end
    endfunction

    // Debounce plus press-duration measurement on the raw active-low key.
    reg [1:0] sync;
    reg raw_state;
    reg [19:0] debounce_count;
    reg stable_state;
    reg [31:0] hold_count;
    reg press_active;
    reg long_marked;
    reg [3:0] lvl_next;

    wire pressed_now = (stable_state == 1'b0);
    wire hold_reached = (hold_count >= LONG_HOLD_MS * CLKS_PER_MS);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync <= 2'b11;
            raw_state <= 1'b1;
            debounce_count <= 20'd0;
            stable_state <= 1'b1;
            hold_count <= 32'd0;
            press_active <= 1'b0;
            long_marked <= 1'b0;
            cfg_update_valid <= 1'b0;
            cfg_period_ms <= 32'd5000;
            cfg_volume <= 8'd64;
            menu_event <= 1'b0;
            menu_kind <= 2'd0;
            menu_level <= 4'd0;
        end else begin
            cfg_update_valid <= 1'b0;
            menu_event <= 1'b0;

            sync <= {sync[0], key4_n};
            if (sync[1] != raw_state) begin
                if (debounce_count >= DEBOUNCE_MS * CLKS_PER_MS - 1) begin
                    raw_state <= sync[1];
                    stable_state <= sync[1];
                    debounce_count <= 20'd0;
                end else begin
                    debounce_count <= debounce_count + 1'b1;
                end
            end else begin
                debounce_count <= 20'd0;
            end

            if (!press_active) begin
                if (pressed_now) begin
                    press_active <= 1'b1;
                    hold_count <= 32'd0;
                    long_marked <= 1'b0;
                end
            end else begin
                if (!pressed_now) begin
                    press_active <= 1'b0;
                    if (service_ready) begin
                        cfg_period_ms <= live_period_ms;
                        cfg_volume <= live_volume;
                        if (long_marked) begin
                            lvl_next = period_level(live_period_ms);
                            lvl_next = (lvl_next == PERIOD_STEPS-1) ? 4'd0 : lvl_next + 1'b1;
                            menu_level <= lvl_next;
                            cfg_period_ms <= period_lut(lvl_next);
                            menu_kind <= 2'd1;
                        end else begin
                            lvl_next = volume_level(live_volume);
                            lvl_next = (lvl_next == VOLUME_STEPS-1) ? 4'd0 : lvl_next + 1'b1;
                            menu_level <= lvl_next;
                            cfg_volume <= volume_lut(lvl_next);
                            menu_kind <= 2'd0;
                        end
                        menu_event <= 1'b1;
                        cfg_update_valid <= 1'b1;
                    end
                    hold_count <= 32'd0;
                end else begin
                    if (hold_count < LONG_HOLD_MS * CLKS_PER_MS)
                        hold_count <= hold_count + 1'b1;
                    if (hold_reached)
                        long_marked <= 1'b1;
                end
            end
        end
    end
endmodule
