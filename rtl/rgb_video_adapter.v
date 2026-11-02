`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// lesson24 rgb_video_adapter
// RGB视频流适配器：位于课程视频合同(VTC+TPG)与厂商HDMI发送IP之间的最后一级。
// 三个职责：
//   1) 统一寄存一拍：hs/vs/de/rgb整组同拍寄存（00M对齐规则——动一个就动一组），
//      让下游IP拿到干净的寄存器输出；
//   2) 极性适配：课程合同sync为低有效；HS/VS_OUT_ACTIVE_LOW参数按IP要求翻转，
//      不回头改VTC；
//   3) 消隐防护：de=0时video_rgb强制为0，上游脏数据出不了门。
// video_clk = pclk 直通（时钟不走寄存器，走时钟资源）。
// 本课边界：厂商HDMI/TMDS发送IP、25 MHz PLL板级配置、差分管脚与显示器观察
// 均为PENDING（见证据索引"接口带与板级基准"）；本模块的输出捆
// {video_clk, video_rgb, video_de, video_hs, video_vs} 即冻结的IP接口带。
// -----------------------------------------------------------------------------
module rgb_video_adapter #(
    parameter HS_IN_ACTIVE_LOW  = 1,  // 课程合同：低有效
    parameter VS_IN_ACTIVE_LOW  = 1,
    parameter HS_OUT_ACTIVE_LOW = 1,  // 按厂商IP要求配置；1=维持低有效
    parameter VS_OUT_ACTIVE_LOW = 1
)(
    input  wire        pclk,       // 像素时钟
    input  wire        rst_n,      // 低有效复位
    input  wire        hs_in,      // 课程视频流
    input  wire        vs_in,
    input  wire        de_in,
    input  wire [23:0] rgb_in,
    output wire        video_clk,  // = pclk，直通不寄存
    output reg         video_hs,   // 极性由输出参数决定
    output reg         video_vs,
    output reg         video_de,
    output reg  [23:0] video_rgb   // 消隐期恒0
);

    // 先归一化成"高有效"内部语义，再按输出参数生成——两端极性互相独立
    wire hs_act = HS_IN_ACTIVE_LOW ? ~hs_in : hs_in;
    wire vs_act = VS_IN_ACTIVE_LOW ? ~vs_in : vs_in;

    assign video_clk = pclk;

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位=空闲电平：不在同步脉冲里、无有效像素、全黑
            video_hs  <= HS_OUT_ACTIVE_LOW ? 1'b1 : 1'b0;
            video_vs  <= VS_OUT_ACTIVE_LOW ? 1'b1 : 1'b0;
            video_de  <= 1'b0;
            video_rgb <= 24'h000000;
        end else begin
            video_hs  <= HS_OUT_ACTIVE_LOW ? ~hs_act : hs_act;
            video_vs  <= VS_OUT_ACTIVE_LOW ? ~vs_act : vs_act;
            video_de  <= de_in;
            video_rgb <= de_in ? rgb_in : 24'h000000;  // 消隐防护
        end
    end

endmodule
