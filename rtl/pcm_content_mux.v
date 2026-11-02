`timescale 1ns/1ps

module pcm_content_mux (
    input  wire signed [15:0] sample0,
    input  wire signed [15:0] sample1,
    input  wire signed [15:0] sample2,
    input  wire signed [15:0] sample3,
    input  wire [1:0] media_id,
    input  wire [7:0] volume,
    output reg signed [15:0] sample_out
);
    reg signed [15:0] selected;
    reg signed [23:0] scaled;
    always @* begin
        case (media_id)
            2'd0: selected = sample0;
            2'd1: selected = sample1;
            2'd2: selected = sample2;
            default: selected = sample3;
        endcase
        scaled = selected * $signed({1'b0, volume});
        if (scaled > 24'sd8388352)
            sample_out = 16'sh7fff;
        else if (scaled < -24'sd8388608)
            sample_out = -16'sd32768;
        else
            sample_out = scaled >>> 8;
    end
endmodule
