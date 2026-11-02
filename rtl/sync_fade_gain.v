`timescale 1ns/1ps

// R3a-5: audio-side gain envelope locked to the video fade alpha
// (docs/29 "音画同步转场"). The video fade engine already produces an
// 8-bit alpha ramp in the pixel domain (alpha_out of video_fade_transition);
// this module moves that envelope into the audio sample domain so the
// audible volume follows the visible fade exactly - picture black means
// silence, picture full means full volume. The alpha crosses pix->audio via
// the established 2FF + quasi-static bank idiom (subtitle_frame_commit).
//
// Gain mapping: gain = alpha when fading, 255 when idle. The audio path
// multiplies this into the existing volume ladder, so user volume remains
// an independent factor on top of the fade envelope.
module sync_fade_gain #(
    parameter integer SYNC_STAGES = 2
) (
    input  wire       pix_clk,
    input  wire       pix_rst_n,
    input  wire       frame_start,       // pixel-domain vsync edge
    input  wire [7:0] alpha_pix,         // live fade alpha (pixel domain)
    input  wire       fade_active,       // alpha_pix is meaningful

    input  wire       aud_clk,           // 48 kHz-class sample domain
    input  wire       aud_rst_n,
    output reg  [7:0] gain_aud           // audio-domain gain envelope
);
    // pixel side: latch alpha at frame boundaries (quasi-static bank)
    reg [7:0] alpha_latch;
    reg       fade_latch;
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            alpha_latch <= 8'd255;
            fade_latch  <= 1'b0;
        end else if (frame_start) begin
            alpha_latch <= alpha_pix;
            fade_latch  <= fade_active;
        end
    end

    // audio side: 2FF sync of the latch change, then adopt
    reg [7:0] sync1, sync2;
    reg       fsync1, fsync2;
    reg [7:0] seen_alpha;
    reg       seen_fade;

    always @(posedge aud_clk or negedge aud_rst_n) begin
        if (!aud_rst_n) begin
            sync1 <= 8'd255;
            sync2 <= 8'd255;
            fsync1 <= 1'b0;
            fsync2 <= 1'b0;
            seen_alpha <= 8'd255;
            seen_fade <= 1'b0;
            gain_aud <= 8'd255;
        end else begin
            sync1 <= alpha_latch;
            sync2 <= sync1;
            fsync1 <= fade_latch;
            fsync2 <= fsync1;

            if (sync2 != seen_alpha) begin
                seen_alpha <= sync2;
                gain_aud <= sync2;
            end else if (!fsync2 && seen_fade) begin
                // fade retired with alpha back at full: release to 255
                seen_fade <= 1'b0;
                if (gain_aud != 8'd255)
                    gain_aud <= 8'd255;
            end else if (fsync2) begin
                seen_fade <= 1'b1;
                gain_aud <= sync2;
            end
        end
    end
endmodule
