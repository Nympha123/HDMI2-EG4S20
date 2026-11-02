// matrix_keyboard_scan.v  --  1x6 直连键盘 (2026-11-01 最终版, 无扫描)
//
//   硬件结构（J1 的 7 个引脚；J13 释放不用）：
//     * 6 个键（上/下/确认/返回/加/减）的"公共端"全部并到 key_row，
//       key_row 由 FPGA 恒定驱动为**低电平**（相当于公共地）。
//     * 每个键的另一端接一根独立感应线 key_col[5:0]，IO 内部上拉。
//     * 键按下 -> 感应线被拉低 -> 读到 0 = 触发。常态（未按）上拉读 1。
//     * 无扫描、无三态：key_row 是纯正输出，key_col 是纯输入，
//       比 4x4 矩阵版省掉分频轮询/两相位/行三态控制，也比 1x6 扫描版省掉扫描状态机。
//
//   消抖：每个键独立计数，采样节拍 1kHz（SAMPLE_HZ），连续 DEBOUNCE_CNT
//   次采样电平一致才确认状态翻转（默认 5ms 消抖）。
//
//   对外接口与旧 4x4 版完全一致（顶层无需任何修改）：
//     key_state 位定义: bit0=上(W) bit3=下(A) bit4=确认(D)
//                       bit8=返回(S) bit2=加(Q) bit1=减(CR)
//     key_event/key_code/key_pressed 语义不变。
//
//   感应线 -> 键位 映射（要改接线顺序只需改 PIN_ADC 的引脚分配，
//   或同时改下面 state_bit / key_code_from_col 两个函数）：
//     col[0]=上   col[1]=下   col[2]=确认
//     col[3]=返回 col[4]=加   col[5]=减
module matrix_keyboard_scan #(
    parameter integer CLK_HZ       = 50_000_000,
    parameter integer SAMPLE_HZ    = 1_000,    // 消抖采样节拍
    parameter integer DEBOUNCE_CNT = 5
)(
    input  wire        clk,          // 50 MHz
    input  wire        rst_n,

    output wire        key_row,      // 公共线, 恒定输出低电平 (=公共地)
    input  wire [5:0]  key_col,      // 6 根感应线, 内部上拉, 按下为0

    output reg         key_event,    // one-clock pulse on a key change
    output reg  [7:0]  key_code,     // ASCII of that key
    output reg         key_pressed,  // 1 = press, 0 = release
    output reg  [15:0] key_state     // current debounced state (1 = pressed)
);
    localparam integer DIV_VALUE = CLK_HZ / SAMPLE_HZ - 1;

    // 公共线恒定拉低（弱驱动即可, 键按下时由 IO 上拉与它形成确定电平）
    assign key_row = 1'b0;

    reg [31:0] div_cnt;
    reg        tick;

    reg [3:0]  debounce_cnt [0:5];

    integer i;

    // 列号 -> key_state 位号（与旧 4x4 矩阵的位定义保持一致）
    function [3:0] state_bit;
        input [2:0] col;
        begin
            case (col)
                3'd0:    state_bit = 4'd0;   // 上
                3'd1:    state_bit = 4'd3;   // 下
                3'd2:    state_bit = 4'd4;   // 确认
                3'd3:    state_bit = 4'd8;   // 返回
                3'd4:    state_bit = 4'd2;   // 加
                default: state_bit = 4'd1;   // 减
            endcase
        end
    endfunction

    // 列号 -> ASCII（仅事件用, 顶层真正消费的是 key_state）
    function [7:0] key_code_from_col;
        input [2:0] col;
        begin
            case (col)
                3'd0:    key_code_from_col = 8'h57;   // W  上
                3'd1:    key_code_from_col = 8'h41;   // A  下
                3'd2:    key_code_from_col = 8'h44;   // D  确认
                3'd3:    key_code_from_col = 8'h53;   // S  返回
                3'd4:    key_code_from_col = 8'h51;   // Q  加
                default: key_code_from_col = 8'h0D;   // CR 减
            endcase
        end
    endfunction

    // 1kHz 采样节拍
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt <= 32'd0;
            tick    <= 1'b0;
        end else if (div_cnt < DIV_VALUE) begin
            div_cnt <= div_cnt + 1'b1;
            tick    <= 1'b0;
        end else begin
            div_cnt <= 32'd0;
            tick    <= 1'b1;
        end
    end

    // 每个键独立消抖：连续 DEBOUNCE_CNT 次采样电平一致才确认翻转
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_event   <= 1'b0;
            key_code    <= 8'h00;
            key_pressed <= 1'b0;
            key_state   <= 16'd0;
            for (i = 0; i < 6; i = i + 1) debounce_cnt[i] <= 4'd0;
        end else begin
            key_event <= 1'b0;

            if (tick) begin
                for (i = 0; i < 6; i = i + 1) begin
                    // 按下 = 感应线为低
                    if ((key_col[i] == 1'b0) != key_state[state_bit(i[2:0])]) begin
                        if (debounce_cnt[i] < DEBOUNCE_CNT - 1) begin
                            debounce_cnt[i] <= debounce_cnt[i] + 1'b1;
                        end else begin
                            debounce_cnt[i] <= 4'd0;
                            key_state[state_bit(i[2:0])] <= (key_col[i] == 1'b0);
                            key_event   <= 1'b1;
                            key_code    <= key_code_from_col(i[2:0]);
                            key_pressed <= (key_col[i] == 1'b0);
                        end
                    end else begin
                        debounce_cnt[i] <= 4'd0;
                    end
                end
            end
        end
    end
endmodule
