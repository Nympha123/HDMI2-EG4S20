`timescale 1ns/1ps

// ===========================================================================
// 第九讲：24 位 RGB OSD 封装（状态 OSD）
//
// 参考实现：参考文件\第九讲：OSD字幕叠加\第9课_OSD字幕叠加\osd_overlay_24.v
// 本工程改写点：
//   1. pixel_x / pixel_y 直接取 video_timing_ctrl 的 x / y（该模块已保证
//      de=1 时为有效像素坐标），因此参考实现里"本地行计数器重建 Y"整段省略，
//      不需要 vsync 参与坐标生成；
//   2. frame_start 由外部提供（顶层直接复用 reader_frame_start，即 vsync
//      下降沿），与媒体控制器的帧边界同源，避免两处各生一个帧脉冲；
//   3. 24→12 位取法、12→24 位展开、区域外透传、de 直通等与参考完全一致
//      （保持与参考逐位等价，便于对照）。
//
// 纯组合（仅状态锁存寄存器），零流水延迟，不改变 de/时序对齐。
// ===========================================================================
module osd_overlay_24 #(
    parameter integer OSD_X = 8,
    parameter integer OSD_Y = 8
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_start,     // vsync 下降沿（顶层复用 reader_frame_start）
    input  wire        de,              // 与 HDMI 核同一路 de
    input  wire [23:0] rgb_in,          // 来自 rgb_video_adapter 的 vout_data_raw
    input  wire [11:0] pixel_x,         // video_timing_ctrl.x
    input  wire [11:0] pixel_y,         // video_timing_ctrl.y
    input  wire [1:0]  active_index,    // reader_index（当前显示 bank）
    input  wire        auto_enabled,    // ctrl_auto_enabled
    input  wire [7:0]  error_code,      // {4'b0, state_code}
    output wire [23:0] rgb_out,
    output wire        de_out,
    output wire        osd_active
);

    wire [11:0] osd_rgb12;
    wire        osd_hit;

    // 状态量（active_index/auto_enabled/error_code）来自 sd_card_clk 域，
    // 在视频域直接进核心的帧边界锁存会形成一条跨域长组合路径（实测 Setup 差 -168ps / 1 端点）。
    // 这里先做两级同步，使真正的时序路径变成 reg->reg，跨域只在第一级采样处发生。
    // 这三个量都是慢变量（每帧才可能变化），两级同步对显示内容无影响。
    reg [1:0]  active_index_s1, active_index_s2;
    reg        auto_enabled_s1, auto_enabled_s2;
    reg [7:0]  error_code_s1,   error_code_s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_index_s1 <= 2'd0;  active_index_s2 <= 2'd0;
            auto_enabled_s1 <= 1'b0;  auto_enabled_s2 <= 1'b0;
            error_code_s1   <= 8'd0;  error_code_s2   <= 8'd0;
        end else begin
            active_index_s1 <= active_index;  active_index_s2 <= active_index_s1;
            auto_enabled_s1 <= auto_enabled;  auto_enabled_s2 <= auto_enabled_s1;
            error_code_s1   <= error_code;    error_code_s2   <= error_code_s1;
        end
    end

    status_osd_overlay #(
        .OSD_X (OSD_X),
        .OSD_Y (OSD_Y)
    ) u_osd (
        .clk          (clk),
        .rst_n        (rst_n),
        .frame_start  (frame_start),
        .active_index (active_index_s2),
        .auto_enabled (auto_enabled_s2),
        .error_code   (error_code_s2),
        .in_de        (de),
        // 24 位里每个字节取高 4 位，拼成 12 位（与参考逐位一致）
        .in_rgb       ({rgb_in[23:20], rgb_in[15:12], rgb_in[7:4]}),
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y),
        .out_rgb      (osd_rgb12),
        .out_de       (),
        .osd_pixel    (osd_hit)
    );

    // 非 OSD 像素原样透传；OSD 像素用 12 位高亮色，每个 nibble 复制两次展开成 24 位
    assign rgb_out = osd_hit ?
        {osd_rgb12[11:8], osd_rgb12[11:8],
         osd_rgb12[7:4],  osd_rgb12[7:4],
         osd_rgb12[3:0],  osd_rgb12[3:0]} : rgb_in;

    assign de_out     = de;
    assign osd_active = osd_hit;

endmodule
