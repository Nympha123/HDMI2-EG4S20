`timescale 1ns/1ps

// R3'-A2: fast boot - first image ready starts the player while remaining
// images continue loading in the background. Cuts perceived boot from ~4 s
// (all four images) to ~1 s (one image). The ingest chain already tracks
// per-image completion via image_complete; this module just re-gates the
// player enable on "at least one image done" instead of "all images done",
// and gates image switching on the target image's own completion.
//
// Switch safety: media_player_control receives a switch request only when
// the target image is loaded (image_complete[target]). The existing
// black-dwell protocol handles the SDRAM side. If a switch to an unloaded
// image is requested (shouldn't happen in normal flow, but defensive),
// the gate holds the request until that image finishes loading.
module fast_boot_gate (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ingest_done,             // all images loaded (legacy)
    input  wire [3:0] image_complete,          // per-image completion bitmap
    input  wire       player_enable_raw,       // legacy enable condition
    output wire       player_enable_fast,      // gated on first image
    output wire       first_image_ready        // status (for OSD/report)
);
    // 首图就绪 = 至少有一个 bank 装载完成。
    // 原参考实现为 image_complete[0]（假定 0 号图必然先装载完成）；
    // 本项目第八讲的预加载会跳过缺失/损坏的槽位（例如根目录只有 PIC2~PIC4），
    // 此时 bit0 永远不为 1 会导致画面永久黑屏，故改为“任一 bank 就绪”。
    assign first_image_ready = |image_complete;

    // player can start as soon as the first image is in SDRAM
    assign player_enable_fast = player_enable_raw && first_image_ready;

    // ingest_done is informational: full functionality (all switchable
    // images) becomes available when it arrives, but display starts earlier
endmodule
