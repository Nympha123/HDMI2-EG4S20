// brightness_contrast_adjust.v —— 第13课练习骨架（完赛工程未单独实现）
module brightness_contrast_adjust (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_de,
    input  wire [23:0] rgb_in,
    input  wire [7:0]  brightness,   // 帧边界锁存后的亮度
    input  wire [7:0]  contrast,     // 帧边界锁存后的对比度
    output reg         out_de,
    output reg  [23:0] rgb_out
);
    // ---- 亮度通路（已给）：每通道 × brightness 后取高8位，即 /256 ----
    wire [15:0] mul_r = rgb_in[23:16] * brightness;
    wire [15:0] mul_g = rgb_in[15:8]  * brightness;
    wire [15:0] mul_b = rgb_in[7:0]   * brightness;
    wire [7:0] bright_r = mul_r[15:8];
    wire [7:0] bright_g = mul_g[15:8];
    wire [7:0] bright_b = mul_b[15:8];

    // ===== TODO(学员完成)：对比度 + 饱和截断 =====
    // 对 bright_r/g/b 分别做：
    //   center = x - 128;
    //   scaled = center * contrast / 128;   // /128 用算术右移7位 >>>7
    //   y      = scaled + 128;
    //   final  = saturate(y)  即 y<0 取0、y>255 取255，否则取y
    // 注意 center/scaled 是有符号数，请用 signed 声明并给足位宽防止溢出。
    // 下面三行是直通占位，补完后删掉直通、换成你的对比度结果：
    wire [7:0] final_r = bright_r;
    wire [7:0] final_g = bright_g;
    wire [7:0] final_b = bright_b;

    // 打一拍输出（流水线寄存器），DE 跟着打拍
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_de <= 1'b0;
            rgb_out <= 24'h000000;
        end else begin
            out_de <= in_de;
            rgb_out <= {final_r, final_g, final_b};
        end
    end
endmodule
