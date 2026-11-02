`timescale 1ns/1ps
// ===========================================================================
// font_rom_ext — 字幕 + 目录页共用的小字库（2048 x 16 = 4 块 9K BRAM）
//
// 为什么要单独一片：
//   主字库 font_rom 是 4096 深（256 槽 x 16 行），8 bit 字符码 0x00..0xFF 已排满。
//   如果把新字模放到 0x100+ 槽位并让主字库也吃 9 bit 码，主字库会被推断成 8192 深，
//   单实例 BRAM 8 -> 15 块（实测整设计 55 -> 62 / 64）。这里单独做一片
//   小 ROM，只装字幕/目录新增的字，主字库保持原样。
//
// v79：
//   * 深度 1024 -> 2048（64 槽 -> 128 槽），给目录页左下角的"展区简介"腾字位。
//   * 这一片 ROM 只在顶层实例化一次，字幕（info_bands）与目录页（directory_ui）
//     共用 —— 两者永不同屏。扩容后 4 块 BRAM，替代原来的 2 份 x 2 块，总数不变。
//
// 数据：rtl/font_rom_ext.hex（tools/make_subtitle_font.py 生成，2048 行）
//       addr = idx * 16 + (15 - 显示行)，idx = 0..127，对应字符码 0x100 + idx
//       每个 16 bit 字：bit15 = 最左像素
// 读延迟：与 font_rom 相同（1 拍输出寄存；上游另有 1 拍地址寄存，合计 2 拍）
// ===========================================================================
module font_rom_ext (
    input  wire        clk,
    input  wire [10:0] addr,
    output reg  [15:0] dout
);
    reg [15:0] grom [0:2047];

    initial begin
        $readmemh("font_rom_ext.hex", grom);
    end

    always @(posedge clk) begin
        dout <= grom[addr];
    end
endmodule
