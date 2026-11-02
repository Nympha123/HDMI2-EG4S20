`timescale 1ns/1ps

// 目录缩略图缓存：96x72，RGB444（8192 x 12 = 12 块 BRAM）。
// 写口：显示扫描时按 5x5 抽样（水平 5 点平均），读口：目录页放大到 266x162。
module thumb_mem (
    input  wire        wr_clk,
    input  wire        we,
    input  wire [12:0] waddr,
    input  wire [11:0] wdata,
    input  wire        rd_clk,
    input  wire [12:0] raddr,
    output reg  [11:0] rdata
);
    reg [11:0] mem [0:8191];
    always @(posedge wr_clk) begin
        if (we)
            mem[waddr] <= wdata;
    end
    always @(posedge rd_clk) begin
        rdata <= mem[raddr];
    end
endmodule
