`timescale 1ns/1ps
// ===========================================================================
//  rotary_brightness.v  --  EC11 旋转编码器调亮度  (v3)
//
//  两个模块：
//    rotary_brightness: 输入同步 + 去抖 + 正交译码 + 按键屏蔽 + 亮度寄存器
//    video_brightness : 按 level/16 缩放 RGB（纯组合）
//
//  v3（2026-10-12）相对 v2 的改动：**按实测接线改正脚号**，并删掉
//  key_from_probe 那套"靠猜"的按键检测。
//    实测：S1 = M15 ｜ S2 = N16 ｜ KEY = P16（J1 pin31/33/35）
//    v2 把 P16（其实是按键）当成一相、M15 当成另一相，KEY 靠"其余探针脚有低"
//    去猜，于是：
//      · 按下 → P16 落地 → 译码器见到一次假转动 → 数字 −1；
//      · 松开 → P16 回高 → 反向假转动 → 数字 +1（看起来"恢复了"）；
//      · 按住期间 P16 恒低，正交序列凑不满一个定位点 → 旋转几乎没反应；
//      · 频繁操作时假边沿叠加 → 随机变大变小。
//    真正的 S2（N16）当时连约束都没有，等于没接进设计。
//    现在三个脚全部用实测球号，按键也有正常的 20ms 消抖与 60ms 屏蔽窗。
//
//  去抖/译码参数（v2 起沿用）：
//    250us 采样、连续 3 次一致才认（等效 750us）；一次定位点 = 4 个单相跳变。
//    比 2ms 的旧参数快，避免快速旋转时把中间状态整段跳过。
// ===========================================================================
module rotary_brightness #(
    parameter integer CLK_FREQ_HZ  = 25_000_000,   // video_clk
    parameter integer SAMPLE_US    = 250,          // A/B 采样周期（微秒）
    parameter integer CONFIRM      = 3,            // 连续几次一致才认
    parameter integer KEY_DEBOUNCE_MS = 20,
    parameter integer KEY_BLANK_MS    = 60,        // 松开后再屏蔽这么久
    parameter         RESET_ON_KEY    = 1'b1,      // 1 = 短按恢复默认亮度
    parameter [4:0]   LEVEL_INIT   = 5'd12,        // 上电默认亮度 12/16
    parameter [4:0]   LEVEL_MAX    = 5'd16
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       enc_a,        // EC11 S1
    input  wire       enc_b,        // EC11 S2
    input  wire       enc_key,      // EC11 KEY（低有效）
    output reg  [4:0] level,
    output reg        key_pulse     // 按键短按（1 拍）
);

    localparam integer TICK_DIV  = (CLK_FREQ_HZ / 1_000_000) * SAMPLE_US;
    localparam integer KEY_DIV   = (CLK_FREQ_HZ / 1000) * KEY_DEBOUNCE_MS;
    localparam integer BLANK_DIV = (CLK_FREQ_HZ / 1000) * KEY_BLANK_MS;

    // ---------------- 1) 输入同步 ----------------
    reg a0, a1, b0, b1, k0, k1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a0 <= 1'b1; a1 <= 1'b1;
            b0 <= 1'b1; b1 <= 1'b1;
            k0 <= 1'b1; k1 <= 1'b1;
        end else begin
            a0 <= enc_a; a1 <= a0;
            b0 <= enc_b; b1 <= b0;
            k0 <= enc_key; k1 <= k0;
        end
    end

    // ---------------- 2) 按键：消抖 + 屏蔽窗口 ----------------
    reg [31:0] kcnt;
    reg        k_stable;          // 1 = 松开, 0 = 按住
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            kcnt      <= 32'd0;
            k_stable  <= 1'b1;
            key_pulse <= 1'b0;
        end else begin
            key_pulse <= 1'b0;
            if (k1 == k_stable) begin
                kcnt <= 32'd0;
            end else if (kcnt >= (KEY_DIV - 1)) begin
                if (k_stable && !k1)
                    key_pulse <= 1'b1;      // 按下那一拍
                k_stable <= k1;
                kcnt     <= 32'd0;
            end else begin
                kcnt <= kcnt + 32'd1;
            end
        end
    end

    // 按住期间一直保持计数，松开后再倒数 BLANK_MS
    reg [31:0] blank_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            blank_cnt <= 32'd0;
        else if (!k_stable)
            blank_cnt <= BLANK_DIV;
        else if (blank_cnt != 32'd0)
            blank_cnt <= blank_cnt - 32'd1;
    end
    wire enc_blank = (blank_cnt != 32'd0);

    // ---------------- 3) 采样节拍 ----------------
    reg [31:0] tick_cnt;
    wire       tick = (tick_cnt >= (TICK_DIV - 1));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tick_cnt <= 32'd0;
        else
            tick_cnt <= tick ? 32'd0 : (tick_cnt + 32'd1);
    end

    // ---------------- 4) 去抖 + 正交译码 + 定位点计数 ----------------
    wire [1:0] ab_now = {a1, b1};
    reg  [1:0] ab_cand, ab_stable, detent;
    reg  [3:0] same_cnt;
    reg        step_up, step_down;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ab_cand   <= 2'b11;
            ab_stable <= 2'b11;
            detent    <= 2'd0;
            same_cnt  <= 4'd0;
            step_up   <= 1'b0;
            step_down <= 1'b0;
        end else begin
            step_up   <= 1'b0;
            step_down <= 1'b0;
            if (tick) begin
                if (enc_blank) begin
                    // 按键期间：只跟着输入走，不计数；顺手把半个定位点清掉
                    ab_cand   <= ab_now;
                    ab_stable <= ab_now;
                    same_cnt  <= 4'd0;
                    detent    <= 2'd0;
                end else if (ab_now == ab_stable) begin
                    ab_cand  <= ab_now;
                    same_cnt <= 4'd0;
                end else if (ab_now == ab_cand) begin
                    if (same_cnt >= (CONFIRM - 1)) begin
                        ab_stable <= ab_now;       // 连续 CONFIRM 次一致 -> 认
                        same_cnt  <= 4'd0;
                        case ({ab_stable, ab_now}) // 老值, 新值
                            4'b0001, 4'b0111, 4'b1110, 4'b1000: begin
                                detent <= detent + 2'd1;
                                if (detent == 2'd3) step_up <= 1'b1;
                            end
                            4'b0010, 4'b1011, 4'b1101, 4'b0100: begin
                                detent <= detent - 2'd1;
                                if (detent == 2'd0) step_down <= 1'b1;
                            end
                            default: ;             // 两相同时变（跳步/抖动）忽略
                        endcase
                    end else begin
                        same_cnt <= same_cnt + 4'd1;
                    end
                end else begin
                    ab_cand  <= ab_now;            // 第一次看到新值，等后续确认
                    same_cnt <= 4'd0;
                end
            end
        end
    end

    // ---------------- 5) 亮度寄存器 ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            level <= LEVEL_INIT;
        else if (key_pulse && RESET_ON_KEY)
            level <= LEVEL_INIT;                   // 短按恢复默认
        else if (step_up && (level < LEVEL_MAX))
            level <= level + 5'd1;
        else if (step_down && (level != 5'd0))
            level <= level - 5'd1;
    end

endmodule


// ===========================================================================
//  video_brightness  --  按 level/16 缩放 RGB（纯组合）
// ===========================================================================
module video_brightness (
    input  wire [4:0]  level,      // 0..16
    input  wire [23:0] rgb_in,
    output wire [23:0] rgb_out
);

    wire [12:0] rp = rgb_in[23:16] * level;
    wire [12:0] gp = rgb_in[15:8]  * level;
    wire [12:0] bp = rgb_in[7:0]   * level;

    // /16：取 [11:4]（c*16 最大 4080，仍在 12 位内）
    assign rgb_out = { rp[11:4], gp[11:4], bp[11:4] };

endmodule
