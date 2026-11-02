// panel_values.v  --  settings-panel value state machine (web semantics)
//
//   W/S pick the row outside this module (sel_row); this module owns the values:
//     row 0/1: handled in top_tf_hdmi_audio.v (5-level brightness/contrast)
//     row 2  ??      0..2 (25/50/100 %), A/D step +/-1; Enter = audio on/off
//     row 3  ??      wave_on toggle plus opacity step 0..2 (25/50/100 %)
//     row 4  ??      period step 0..2 (5/10/15 s) while auto_on is set;
//                    Enter toggles auto_on independently
//     row 5  ??      time-edit fields (loaded into the internal time_clock)
//   Keys arrive as ~40 ms wide levels, so they are edge-detected here; the panel
//   only reacts while active, which keeps the image screen unaffected.
module panel_values (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        active,
    input  wire [2:0]  sel_row,
    input  wire        key_dec,       // A
    input  wire        key_inc,       // D
    input  wire        key_ok,        // Enter
    output reg  [2:0]  vol,
    output reg         audio_on,      // 音量行 Enter：音频总开关（0 = 静音）
    output reg         wave_on,
    output reg  [1:0]  wave_step,
    output reg         auto_on,
    output reg  [1:0]  autoper
);
    reg dec_d, inc_d, ok_d;
    wire dec_ev = key_dec & ~dec_d;
    wire inc_ev = key_inc & ~inc_d;
    wire ok_ev  = key_ok  & ~ok_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dec_d    <= 1'b0;
            inc_d    <= 1'b0;
            ok_d     <= 1'b0;
            vol      <= 3'd1;              // 50%
            audio_on <= 1'b1;
            wave_on  <= 1'b1;
            wave_step <= 2'd0;
            auto_on  <= 1'b0;
            autoper  <= 2'd0;
        end else begin
            dec_d <= key_dec;
            inc_d <= key_inc;
            ok_d  <= key_ok;
            if (active) begin
                if (inc_ev) begin
                    case (sel_row)
                        3'd2: vol      <= (vol < 3'd2) ? (vol + 3'd1) : 3'd2;   // 25/50/100%
                        3'd3: if (wave_on && (wave_step < 2'd2)) wave_step <= wave_step + 2'd1;
                        3'd4: if (auto_on && (autoper < 2'd2)) autoper <= autoper + 2'd1;   // 5/10/15 s
                        default: ;
                    endcase
                end else if (dec_ev) begin
                    case (sel_row)
                        3'd2: vol      <= (vol > 3'd0) ? (vol - 3'd1) : 3'd0;
                        3'd3: if (wave_on && (wave_step > 2'd0)) wave_step <= wave_step - 2'd1;
                        3'd4: if (auto_on && (autoper > 2'd0)) autoper <= autoper - 2'd1;
                        default: ;
                    endcase
                end else if (ok_ev) begin
                    if (sel_row == 3'd2)      audio_on <= ~audio_on;   // 音量行 Enter: audio on/off
                    else if (sel_row == 3'd3) wave_on  <= ~wave_on;
                    else if (sel_row == 3'd4) auto_on  <= ~auto_on;
                end
            end
        end
    end
endmodule
