`timescale 1ns/1ps

// 主界面三按钮菜单 + 目录页控制器。
// 菜单：0 目录，1 设置，2 系统（只读信息层，主菜单保持在底下）。
// 目录：W/S 选行，Enter 进图片，Q 回菜单。
module menu_ctrl (
    input  wire       clk,
    input  wire       rst,
    input  wire       key_up,
    input  wire       key_down,
    input  wire       key_ok,
    input  wire       key_back,
    input  wire       settings_on,
    input  wire       sys_on,          // 「系统」信息层打开：冻结菜单导航
    output reg        menu_active,
    output reg        dir_active,
    output reg        open_settings,
    output reg        open_sysinfo,    // 第三项选中：打一拍打开系统信息页
    output reg        zone_apply,
    output reg        zone_preview,
    output reg  [1:0] zone_sel,
    output reg  [2:0] sel,
    output reg  [2:0] dir_sel
);
    reg up_d, down_d, ok_d, back_d;
    wire up_ev   = key_up   & ~up_d;
    wire down_ev = key_down & ~down_d;
    wire ok_ev   = key_ok   & ~ok_d;
    wire back_ev = key_back & ~back_d;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            up_d          <= 1'b0;
            down_d        <= 1'b0;
            ok_d          <= 1'b0;
            back_d        <= 1'b0;
            menu_active   <= 1'b1;
            dir_active    <= 1'b0;
            open_settings <= 1'b0;
            open_sysinfo  <= 1'b0;
            zone_apply    <= 1'b0;
            zone_preview  <= 1'b0;
            zone_sel      <= 2'd0;
            sel           <= 3'd0;
            dir_sel       <= 3'd0;
        end else begin
            up_d          <= key_up;
            down_d        <= key_down;
            ok_d          <= key_ok;
            back_d        <= key_back;
            open_settings <= 1'b0;
            open_sysinfo  <= 1'b0;
            zone_apply    <= 1'b0;
            zone_preview  <= 1'b0;

            if (dir_active) begin
                if (up_ev) begin
                    dir_sel <= (dir_sel == 3'd0) ? 3'd3 : (dir_sel - 3'd1);
                    zone_sel <= (dir_sel == 3'd0) ? 2'd3 : (dir_sel[1:0] - 2'd1);
                    zone_preview <= 1'b1;
                end
                else if (down_ev) begin
                    dir_sel <= (dir_sel == 3'd3) ? 3'd0 : (dir_sel + 3'd1);
                    zone_sel <= (dir_sel == 3'd3) ? 2'd0 : (dir_sel[1:0] + 2'd1);
                    zone_preview <= 1'b1;
                end
                else if (ok_ev) begin
                    zone_sel   <= dir_sel[1:0];
                    zone_apply <= 1'b1;
                    dir_active <= 1'b0;               // 目录确认 -> 该区图片界面
                end
                else if (back_ev) begin
                    dir_active <= 1'b0;               // Q -> 主菜单
                    menu_active <= 1'b1;
                end
            end else if (menu_active) begin
                if (!settings_on && !sys_on) begin
                    if (up_ev)
                        sel <= (sel == 3'd0) ? 3'd2 : (sel - 3'd1);
                    else if (down_ev)
                        sel <= (sel == 3'd2) ? 3'd0 : (sel + 3'd1);
                    else if (ok_ev) begin
                        if (sel == 3'd1) begin
                            open_settings <= 1'b1;     // 菜单保持，设置叠层
                        end else if (sel == 3'd0) begin
                            menu_active <= 1'b0;
                            dir_active  <= 1'b1;
                            dir_sel     <= 3'd0;
                            zone_sel    <= 2'd0;
                            zone_preview<= 1'b1;
                        end else begin
                            // v44：第三项「系统」= 只读信息层；主菜单保持在底下，
                            // 不离开主界面、也不启动轮播（轮播只在设置页第 5 行切）。
                            open_sysinfo <= 1'b1;
                        end
                    end
                    // v79：主界面上 **Q（返回键）不做事**。
                    //   原来这里 `else if (back_ev) menu_active <= 1'b0;` 会把主菜单直接
                    //   关掉、露出底下的图片页，用户看到的就是"在主界面按返回就跳到别的界面"。
                    //   现在主菜单只有「目录」「设置」「系统简介」三个入口，返回键在这里失效；
                    //   图片页的 Q 仍然回主菜单（见下面 else 分支）。
                end
            end else begin
                if (back_ev && !settings_on)
                    menu_active <= 1'b1;
            end
        end
    end
endmodule
