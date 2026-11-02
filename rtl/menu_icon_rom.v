`timescale 1ns/1ps
// ===========================================================================
// menu_icon_rom — 主菜单右侧 4 个展品图标的 1bpp 精灵表
//
//   数据：rtl/menu_icon.hex（8192 行，1 bit/行）
//   布局：addr = icon_idx * 1936 + ly * 44 + lx     （1936 = 44 * 44）
//         icon_idx: 0 编钟 / 1 青铜鼎 / 2 唐三彩马 / 3 剑
//   容量：4 x 1936 = 7744 bit，用一块 9K BRAM（8192x1 模式）
//   读延迟：1 拍（上游另有 1 拍地址寄存，合计 2 拍，与字体 ROM 一致）
// ===========================================================================
module menu_icon_rom (
    input  wire        clk,
    input  wire [12:0] addr,
    output reg         dout
);
    reg mem [0:8191];

    initial begin
        $readmemh("menu_icon.hex", mem);
    end

    always @(posedge clk) begin
        dout <= mem[addr];
    end
endmodule
