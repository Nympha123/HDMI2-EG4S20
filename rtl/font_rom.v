`timescale 1ns/1ps
// 纯 RTL 字库 ROM（方案 R）：数据来自 FONT_ROM.mif 转换出的 font_rom.hex
//   WIDTH=16, DEPTH=2816 = 176 槽 x 16 行
//   addr = 槽号*16 + (15 - 显示行)   槽号：0x20..0x7E=ASCII，0x80..0xAF=48 汉字，
//                                    0x01..0x0F=菜单用 15 汉字，0x00=空
//   读延迟 = 1 拍（仅输出寄存）
module font_rom (
    input  wire        clk,
    input  wire [13:0] addr,
    output reg  [15:0] dout
);
    reg [15:0] grom [0:16383];
    initial begin
        $readmemh("font_rom.hex", grom);
    end
    always @(posedge clk) begin
        dout <= grom[addr];
    end
endmodule