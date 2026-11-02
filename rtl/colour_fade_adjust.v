// colour_fade_adjust.v
//   One combined colour stage: brightness + contrast + transition fade in a single
//   multiply-add per channel, placed at the END of the display chain.
//
//     out = sat( (x * K1) >>> 15  +  K2 )
//
//   with (both supplied by the top, quasi-static):
//     K1 = (B * C * (A+1)) >> 8      B = brightness 0..255 (255 ~ 1.0)
//                                    C = contrast   0..255 (128 = identity)
//                                    A = fade alpha 0..255 (255 = no fade)
//     K2 = 128 - C                   signed offset (-128 .. +128)
//
//   Identity check at the power-on defaults (B=192, C=128, A=255):
//     K1 = (192*128*256)>>8 = 24576  ->  (x*24576)>>>15 = floor(x*0.75)
//     which is bit-identical to the previous (x*192)>>8 = floor(x*0.75).
//     K2 = 0.  So the default picture is unchanged, pixel for pixel.
//
//   Combinational on purpose: keeps RGB and DE aligned (no extra pixel skew).
module colour_fade_adjust (
    input  wire        clk,        // unused, kept for interface symmetry
    input  wire        rst_n,      // unused
    input  wire        de,         // unused
    input  wire [23:0] rgb_in,
    input  wire [16:0] k1,         // Q15 gain, 0 .. 65025 (about 0 .. 2.0)
    input  wire signed [8:0] k2,   // offset -128 .. +128
    output wire [23:0] rgb_out
);
    function [7:0] sat8;
        input signed [25:0] y;
        begin
            if (y[25])             sat8 = 8'd0;      // negative -> 0
            else if (y > 26'sd255) sat8 = 8'hFF;     // overflow -> 255
            else                   sat8 = y[7:0];
        end
    endfunction

    wire signed [25:0] r = ((($signed({1'b0, rgb_in[23:16]}) * $signed({1'b0, k1})) >>> 15) + k2);
    wire signed [25:0] g = ((($signed({1'b0, rgb_in[15:8]})  * $signed({1'b0, k1})) >>> 15) + k2);
    wire signed [25:0] b = ((($signed({1'b0, rgb_in[7:0]})   * $signed({1'b0, k1})) >>> 15) + k2);

    assign rgb_out = { sat8(r), sat8(g), sat8(b) };
endmodule
