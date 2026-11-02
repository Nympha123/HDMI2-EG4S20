// bilinear_8q8.v —— 双线性插值（R 通道为参考骨架原文，G/B 通道已在本工程补完）
// 输入：4个相邻像素 p00/p10/p01/p11（左上/右上/左下/右下）
//       wx = (x的小数部分)<<8, wy = (y的小数部分)<<8  (0~255)
// 思路：先按行加权，再按列加权，每步乘16位再取高8位
// 三个通道结构完全一致，只换信号后缀，保证同一像素的 G/B 与 R 同拍输出。
module bilinear_8q8 (
    input  wire [7:0] p00_r, p10_r, p01_r, p11_r,
    input  wire [7:0] p00_g, p10_g, p01_g, p11_g,   // G通道：已接入
    input  wire [7:0] p00_b, p10_b, p01_b, p11_b,   // B通道：已接入
    input  wire [7:0] wx, wy,
    output wire [7:0] out_r, out_g, out_b
);
    // 两个综合陷阱（安路TD实测实锤，见逐课TD综合验证报告第八节，L12日志HDL-5007）：
    // ① 8'd256 会把256截进8位字面量变成0 —— 权重补数必须用 9'd256；
    // ② 行加权结果最大 255*256=65280，若不取高8位直接做列加权，
    //    乘积最大 65280*256≈1670万，16位装不下会被静默截断 —— 每步先取 [15:8]。
    wire [8:0]  inv_wx = 9'd256 - {1'b0, wx};                    // 256-wx，范围1~256
    wire [8:0]  inv_wy = 9'd256 - {1'b0, wy};

    // ---- R通道（骨架原文，未改动）----
    wire [15:0] row_top_r    = p00_r * inv_wx + p10_r * wx;
    wire [15:0] row_bottom_r = p01_r * inv_wx + p11_r * wx;
    wire [15:0] out_r_full   = row_top_r[15:8] * inv_wy + row_bottom_r[15:8] * wy;
    assign out_r = out_r_full[15:8];

    // ---- G通道（照抄 R，后缀换 _g）----
    wire [15:0] row_top_g    = p00_g * inv_wx + p10_g * wx;
    wire [15:0] row_bottom_g = p01_g * inv_wx + p11_g * wx;
    wire [15:0] out_g_full   = row_top_g[15:8] * inv_wy + row_bottom_g[15:8] * wy;
    assign out_g = out_g_full[15:8];

    // ---- B通道（照抄 R，后缀换 _b）----
    wire [15:0] row_top_b    = p00_b * inv_wx + p10_b * wx;
    wire [15:0] row_bottom_b = p01_b * inv_wx + p11_b * wx;
    wire [15:0] out_b_full   = row_top_b[15:8] * inv_wy + row_bottom_b[15:8] * wy;
    assign out_b = out_b_full[15:8];
endmodule
