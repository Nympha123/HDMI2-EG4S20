// brightness_contrast_adjust.v  --  lesson 13 exercise, completed here
//   brightness : out = in * brightness / 256     (3 multipliers, take [15:8])
//   contrast   : center = in - 128 ; scaled = center * contrast / 128 ;
//                out = saturate(scaled + 128)     (signed, one multiplier per channel)
//   contrast = 128 -> identity ; 0 -> flat grey 128 ; 255 -> about 2x
//   Combinational output on purpose: the display chain keeps RGB and DE aligned
//   (the reference skeleton registered the output, which would skew by 1 pixel).
module brightness_contrast_adjust (
    input  wire        clk,          // unused (kept for interface compatibility)
    input  wire        rst_n,        // unused
    input  wire        in_de,        // unused
    input  wire [23:0] rgb_in,
    input  wire [7:0]  brightness,   // 0..255, 255 = neutral (~1.0)
    input  wire [7:0]  contrast,     // 0..255, 128 = identity
    output wire        out_de,
    output wire [23:0] rgb_out
);
    // ---- brightness (1/256 granularity) ----
    wire [15:0] mul_r = rgb_in[23:16] * brightness;
    wire [15:0] mul_g = rgb_in[15:8]  * brightness;
    wire [15:0] mul_b = rgb_in[7:0]   * brightness;
    wire [7:0]  br_r = mul_r[15:8];
    wire [7:0]  br_g = mul_g[15:8];
    wire [7:0]  br_b = mul_b[15:8];

    // ---- contrast: signed centre, x*contrast>>>7, +128, saturate ----
    function [7:0] sat8;
        input signed [17:0] y;
        begin
            if (y[17])          sat8 = 8'd0;          // negative
            else if (y > 18'sd255) sat8 = 8'hFF;      // overflow
            else                sat8 = y[7:0];
        end
    endfunction

    wire signed [17:0] cr = (($signed({1'b0, br_r}) - 18'sd128) * $signed({1'b0, contrast})) >>> 7;
    wire signed [17:0] cg = (($signed({1'b0, br_g}) - 18'sd128) * $signed({1'b0, contrast})) >>> 7;
    wire signed [17:0] cb = (($signed({1'b0, br_b}) - 18'sd128) * $signed({1'b0, contrast})) >>> 7;

    assign rgb_out = { sat8(cr + 18'sd128), sat8(cg + 18'sd128), sat8(cb + 18'sd128) };
    assign out_de  = in_de;
endmodule