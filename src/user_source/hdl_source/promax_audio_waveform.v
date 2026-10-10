`timescale 1ns/1ps

// ===========================================================================
// 第十二讲：音频波形可视化（本工程版）—— 版本 X2
//
// 出发点：你已验证“正常”的居中最细线版 X1（..._L12_x1_44E80338）
// 本版只把“绘图”换成你验证过的**矩形条**版画法（即 421DE115 的画法）：
//   V1  采样缓冲存完整 16 位，增益 >>>7（起伏约 8 倍），并限幅 ±(H/2-2)
//   V2  实心矩形条：自中心线向上下展开；间隙 BAR_GAP（现为 1，曾 2）
// 同时保持 V4（居中 Y=208）与 V3b（25% 浅灰），但**灰色改用纯加法写法**
// （四项相加再 >>2），刻意避开乘法器 —— 用于排除“乘法写法”这一嫌疑：
//   blend = (GRAY + rgb*3) / 4 = (GRAY + rgb + rgb + rgb) >> 2
// 其余与已验证版一致：DECIMATE=12、原换 bank 逻辑、原峰值条。
// ===========================================================================
module promax_audio_waveform #(
    parameter integer WAVE_X = 64,
    parameter integer WAVE_Y = 176,
    parameter integer WAVE_WIDTH = 512,
    parameter integer WAVE_HEIGHT = 128,
    parameter integer DECIMATE = 24
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vsync,
    input  wire        de,
    input  wire [23:0] rgb_in,
    input  wire [9:0]  pixel_x,
    input  wire        enable,
    input  wire        pcm_tap_valid,
    input  wire signed [15:0] pcm_tap_left,
    output wire [23:0] rgb_out,
    output wire        waveform_active
);
    localparam integer SAMPLE_COUNT = 32;
    localparam integer SAMPLE_SPACING = WAVE_WIDTH / SAMPLE_COUNT;
    localparam integer CENTER_Y = WAVE_Y + WAVE_HEIGHT/2;
    localparam integer CENTER_X = WAVE_X + WAVE_WIDTH/2;   // V5: 窗型中心（屏幕中心）
    localparam integer HALF_H  = WAVE_HEIGHT/2 - 2;   // 条最大半高（留边）
    localparam integer BAR_GAP = 1;                   // V6: 条间间隙减半（2 -> 1）
    localparam [7:0]   GRAY    = 8'hD8;               // 浅灰

    reg [11:0] line_y;
    reg de_q;
    reg vs_q;
    wire frame_start = vs_q && !vsync;

    // V1: 存完整 16 位样本
    reg signed [15:0] sample_bank0 [0:SAMPLE_COUNT-1];
    reg signed [15:0] sample_bank1 [0:SAMPLE_COUNT-1];
    reg write_bank;
    reg display_bank;
    reg display_valid;
    reg [5:0] capture_count;
    reg [7:0] decimate_count;
    reg [7:0] peak_bank0;
    reg [7:0] peak_bank1;
    reg [7:0] display_peak;
    integer wsample;                                  // V5c: 采集侧加权后的样本
    wire [7:0] sample_abs = pcm_tap_left[15] ?
                            (~pcm_tap_left[15:8] + 1'b1) : pcm_tap_left[15:8];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            line_y <= 12'd0;
            de_q <= 1'b0;
            vs_q <= 1'b1;
            write_bank <= 1'b0;
            display_bank <= 1'b1;
            display_valid <= 1'b0;
            capture_count <= 6'd0;
            decimate_count <= 8'd0;
            peak_bank0 <= 8'd0;
            peak_bank1 <= 8'd0;
            display_peak <= 8'd0;
        end else begin
            de_q <= de;
            vs_q <= vsync;
            if (!vsync)
                line_y <= 12'd0;
            else if (de_q && !de)
                line_y <= line_y + 1'b1;

            if (frame_start) begin
                if (capture_count == SAMPLE_COUNT) begin
                    display_bank <= write_bank;
                    display_valid <= 1'b1;
                    display_peak <= write_bank ? peak_bank1 : peak_bank0;
                    write_bank <= ~write_bank;
                end
                capture_count <= 6'd0;
                decimate_count <= 8'd0;
                if (write_bank) peak_bank0 <= 8'd0;
                else peak_bank1 <= 8'd0;
            end else if (pcm_tap_valid && capture_count < SAMPLE_COUNT) begin
                if (decimate_count == 0) begin
                    // V5c: 窗型加权移到采集侧（显示逻辑与已验证版 X3 完全一致，零新增显示路径）
                    //   条序号 12..19 -> x1.00 ; 8..23 -> x0.75 ; 4..27 -> x0.50 ; 其余 -> x0.25
                    if (capture_count >= 6'd12 && capture_count <= 6'd19)
                        wsample = $signed(pcm_tap_left);
                    else if (capture_count >= 6'd8 && capture_count <= 6'd23)
                        wsample = $signed(pcm_tap_left) - ($signed(pcm_tap_left) >>> 2);
                    else if (capture_count >= 6'd4 && capture_count <= 6'd27)
                        wsample = $signed(pcm_tap_left) >>> 1;
                    else
                        wsample = $signed(pcm_tap_left) >>> 2;
                    if (write_bank)
                        sample_bank1[capture_count] <= wsample[15:0];   // V1 + V5c
                    else
                        sample_bank0[capture_count] <= wsample[15:0];   // V1 + V5c
                    capture_count <= capture_count + 1'b1;
                    decimate_count <= DECIMATE-1;
                    if (write_bank) begin
                        if (sample_abs > peak_bank1) peak_bank1 <= sample_abs;
                    end else begin
                        if (sample_abs > peak_bank0) peak_bank0 <= sample_abs;
                    end
                end else begin
                    decimate_count <= decimate_count - 1'b1;
                end
            end
        end
    end

    integer sample_index;
    integer sample_value;
    integer delta;
    integer bar_delta;
    integer wdelta;                                   // V5: 加权后的半高
    integer dist_x;                                   // V5: 到屏幕中心的横向距离
    integer bar_lo;
    integer bar_hi;
    integer peak_height;
    reg signed [15:0] selected_sample;
    reg wave_pixel;
    reg axis_pixel;
    reg peak_pixel;
    reg [9:0] bar_x;

    always @* begin
        sample_index = 0;
        selected_sample = 16'sd0;
        sample_value = 0;
        delta = 0;
        bar_delta = 0;
        wdelta = 0;
        dist_x = 0;
        bar_lo = CENTER_Y;
        bar_hi = CENTER_Y;
        peak_height = display_peak >> 2;
        wave_pixel = 1'b0;
        axis_pixel = 1'b0;
        peak_pixel = 1'b0;
        bar_x = 10'd0;

        if (enable && de && pixel_x >= WAVE_X &&
            pixel_x < WAVE_X + WAVE_WIDTH &&
            line_y >= WAVE_Y && line_y < WAVE_Y + WAVE_HEIGHT) begin
            axis_pixel = (line_y == CENTER_Y);
            sample_index = (pixel_x-WAVE_X) / SAMPLE_SPACING;
            bar_x = (pixel_x-WAVE_X) % SAMPLE_SPACING;
            if (display_valid && sample_index < SAMPLE_COUNT &&
                bar_x < (SAMPLE_SPACING - BAR_GAP)) begin
                selected_sample = display_bank ?
                                  sample_bank1[sample_index] : sample_bank0[sample_index];
                sample_value = $signed(selected_sample);
                delta = sample_value >>> 7;                 // V1
                if (delta >  HALF_H) delta =  HALF_H;
                if (delta < -HALF_H) delta = -HALF_H;
                bar_delta = (delta >= 0) ? delta : -delta;
                bar_lo = CENTER_Y - bar_delta;
                bar_hi = CENTER_Y + bar_delta;
                if (line_y >= bar_lo && line_y <= bar_hi) wave_pixel = 1'b1;   // V2
            end
        end

        if (enable && de && pixel_x >= WAVE_X+WAVE_WIDTH+8 &&
            pixel_x < WAVE_X+WAVE_WIDTH+16 &&
            line_y >= WAVE_Y+WAVE_HEIGHT-peak_height &&
            line_y < WAVE_Y+WAVE_HEIGHT)
            peak_pixel = 1'b1;
    end

    // V3b: 半透明浅灰 25%（纯加法写法：(GRAY + 原×3) / 4，不用乘法器）
    wire [11:0] sum_r = {2'b0, GRAY} + {2'b0, rgb_in[23:16]}
                                   + {2'b0, rgb_in[23:16]} + {2'b0, rgb_in[23:16]};
    wire [11:0] sum_g = {2'b0, GRAY} + {2'b0, rgb_in[15:8]}
                                   + {2'b0, rgb_in[15:8]}  + {2'b0, rgb_in[15:8]};
    wire [11:0] sum_b = {2'b0, GRAY} + {2'b0, rgb_in[7:0]}
                                   + {2'b0, rgb_in[7:0]}   + {2'b0, rgb_in[7:0]};
    wire [7:0]  blend_r = sum_r >> 2;
    wire [7:0]  blend_g = sum_g >> 2;
    wire [7:0]  blend_b = sum_b >> 2;

    assign waveform_active = wave_pixel || axis_pixel || peak_pixel;
    assign rgb_out = (wave_pixel || axis_pixel) ? {blend_r, blend_g, blend_b} :
                     peak_pixel ? 24'hffb020 : rgb_in;
endmodule
