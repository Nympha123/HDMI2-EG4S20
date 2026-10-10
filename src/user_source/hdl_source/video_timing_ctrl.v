`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// lesson22 video_timing_ctrl
// 视频时序控制器(VTC)：像素时钟域内的行/场计数器加同拍组合译码。
// 输出合同（模块五冻结，见课程00_工程目录与文件放置清单.md）：
//   x/y      : 行/场计数器本体，0 .. H_TOTAL-1 / V_TOTAL-1；de=1时即有效像素坐标
//   de       : 有效显示区标志，(x < H_ACT) && (y < V_ACT)
//   hsync    : 低有效行同步脉冲，位于 [H_ACT+H_FP, H_ACT+H_FP+H_SYNC)
//   vsync    : 低有效场同步脉冲，位于 [V_ACT+V_FP, V_ACT+V_FP+V_SYNC)
// 段顺序固定为 ACTIVE -> FRONT PORCH -> SYNC -> BACK PORCH。
// 本课边界：所有输出为计数器的同拍组合译码；对整组信号统一寄存一拍是第24课
// rgb_video_adapter的职责。四段参数各自必须 >= 1，某段为0不在合同内。
// 640x480@60规格参数为默认值；ModelSim主门用缩小参数跑整帧。
// -----------------------------------------------------------------------------
module video_timing_ctrl #(
    parameter H_ACT  = 640,  // 水平有效像素
    parameter H_FP   = 16,   // 水平前肩
    parameter H_SYNC = 96,   // 水平同步脉宽
    parameter H_BP   = 48,   // 水平后肩
    parameter V_ACT  = 480,  // 垂直有效行
    parameter V_FP   = 10,   // 垂直前肩
    parameter V_SYNC = 2,    // 垂直同步脉宽
    parameter V_BP   = 33,   // 垂直后肩
    parameter ACTIVE_LAST = 0
)(
    input  wire        pclk,   // 像素时钟（生产环境25 MHz，由TD PLL从50 MHz生成）
    input  wire        rst_n,  // 低有效复位
    output wire        hsync,  // 低有效
    output wire        vsync,  // 低有效
    output wire        de,     // 有效显示区
    output reg  [11:0] x,      // 行计数器；de=1时为有效像素列坐标
    output reg  [11:0] y       // 场计数器；de=1时为有效像素行坐标
);

    localparam H_TOTAL = H_ACT + H_FP + H_SYNC + H_BP;
    localparam V_TOTAL = V_ACT + V_FP + V_SYNC + V_BP;

    // 行/场计数：x走完一行，y走一步；两个都走完回到帧起点(0,0)
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            x <= 12'd0;
            y <= 12'd0;
        end else if (x == H_TOTAL - 1) begin
            x <= 12'd0;
            y <= (y == V_TOTAL - 1) ? 12'd0 : y + 12'd1;
        end else begin
            x <= x + 12'd1;
        end
    end

    // 同拍组合译码：de/hsync/vsync与x/y永远对齐，不存在错拍问题
    assign de    = ACTIVE_LAST ?
                   ((x >= H_TOTAL - H_ACT) && (y >= V_TOTAL - V_ACT)) :
                   ((x < H_ACT) && (y < V_ACT));
    assign hsync = ACTIVE_LAST ?
                   ~((x >= H_FP) && (x < H_FP + H_SYNC)) :
                   ~((x >= H_ACT + H_FP) && (x < H_ACT + H_FP + H_SYNC));
    assign vsync = ACTIVE_LAST ?
                   ~((y >= V_FP) && (y < V_FP + V_SYNC)) :
                   ~((y >= V_ACT + V_FP) && (y < V_ACT + V_FP + V_SYNC));

endmodule
