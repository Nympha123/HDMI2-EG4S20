`timescale 1ns/1ps

// ===========================================================================
// 第九讲：跨时钟域字幕帧提交（动态字幕的"防撕裂"骨架）
//
// 参考实现：参考文件\第九讲：OSD字幕叠加\第9课_OSD字幕叠加\subtitle_frame_commit.v
// 说明：本模块为纯接口、无参数依赖，与本工程无耦合，因此**原样移植**，
//       仅在注释中标注本工程的实际接法：
//         src 侧（文本来源）：与按键/文本源同域（本项目用 sd_card_clk，
//                              文本来自小字库 ROM + 按键选择的文本组）
//         dst 侧（显示侧）  ：视频域 video_clk，frame_start 复用 reader_frame_start
//       机制：src_commit 翻转 toggle → 2FF 同步到显示域 → 只在 frame_start
//             且 toggle 有变化（或首次）时锁存 text/length/enable
//             → 文本整帧切换，永不帧内撕裂。
// ===========================================================================
module subtitle_frame_commit (
    input  wire         src_clk,
    input  wire         src_rst_n,
    input  wire         src_commit,
    input  wire [95:0]  src_text,
    input  wire [5:0]   src_length,
    input  wire         src_enable,
    input  wire         dst_clk,
    input  wire         dst_rst_n,
    input  wire         frame_start,
    output reg  [95:0]  dst_text,
    output reg  [5:0]   dst_length,
    output reg          dst_enable
);

    reg commit_toggle;
    reg commit_sync1;
    reg commit_sync2;
    reg commit_seen;
    reg dst_initialized;

    // 源域：每次提交翻转一次 toggle
    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n)
            commit_toggle <= 1'b0;
        else if (src_commit)
            commit_toggle <= ~commit_toggle;
    end

    // 显示域：同步 toggle，并在帧边界整帧锁存文本
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            commit_sync1    <= 1'b0;
            commit_sync2    <= 1'b0;
            commit_seen     <= 1'b0;
            dst_initialized <= 1'b0;
            dst_text        <= 96'd0;
            dst_length      <= 6'd0;
            dst_enable      <= 1'b0;
        end else begin
            commit_sync1 <= commit_toggle;
            commit_sync2 <= commit_sync1;
            if (frame_start && (!dst_initialized || commit_sync2 != commit_seen)) begin
                dst_text        <= src_text;
                dst_length      <= src_length;
                dst_enable      <= src_enable;
                commit_seen     <= commit_sync2;
                dst_initialized <= 1'b1;
            end
        end
    end

endmodule
