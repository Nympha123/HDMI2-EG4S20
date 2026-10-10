`timescale 1ns/1ps

// R3'-A3: audio source selector - WAV stream takes priority over arpeggio
// when active and enabled. Both sources share the same sample_valid /
// sample_ready / sample_left / sample_right interface; the mux is purely
// combinational on the valid/data paths, with the ready signal routed to
// the selected source only (the unselected source sees ready=0 so its
// internal FIFO doesn't drain).
module audio_source_mux (
    input  wire               clk,
    input  wire               rst_n,

    // source A: WAV stream
    input  wire               wav_valid,
    output wire               wav_ready,
    input  wire signed [15:0] wav_left,
    input  wire signed [15:0] wav_right,
    input  wire               wav_active,     // stream playing (level)

    // source B: arpeggio synth (existing pcm_media_tone)
    input  wire               arp_valid,
    output wire               arp_ready,
    input  wire signed [15:0] arp_left,
    input  wire signed [15:0] arp_right,

    // enable override: dip switch or menu can force arpeggio
    input  wire               force_arpeggio,

    // output to m06_pcm_contract_adapter
    output wire               out_valid,
    input  wire               out_ready,
    output wire signed [15:0] out_left,
    output wire signed [15:0] out_right
);
    wire use_wav = wav_active && !force_arpeggio;

    assign out_valid = use_wav ? wav_valid : arp_valid;
    assign out_left  = use_wav ? wav_left  : arp_left;
    assign out_right = use_wav ? wav_right : arp_right;

    assign wav_ready = use_wav ? out_ready : 1'b0;
    assign arp_ready = use_wav ? 1'b0      : out_ready;
endmodule
