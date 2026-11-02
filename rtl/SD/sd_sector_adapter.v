`timescale 1ns/1ps

// SD card sector interface adapter from the lesson 7 reference.
module sd_sector_adapter (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sector_req,
    input  wire [31:0] sector_lba,
    output wire        sector_busy,
    output wire        sector_valid,
    output wire [7:0]  sector_byte,
    output wire [8:0]  sector_byte_index,
    output wire        sector_done,
    output wire [7:0]  sector_error,
    output reg         sd_sec_read,
    output reg  [31:0] sd_sec_read_addr,
    input  wire        sd_sec_read_data_valid,
    input  wire [7:0]  sd_sec_read_data,
    input  wire        sd_sec_read_end,
    // v79：SD 核报告的读失败（和 sd_sec_read_end 同拍）
    input  wire        sd_sec_read_error
);

reg [8:0] byte_cnt;
reg       busy_reg;

assign sector_busy       = busy_reg;
assign sector_valid      = sd_sec_read_data_valid;
assign sector_byte       = sd_sec_read_data;
assign sector_byte_index = byte_cnt;
assign sector_done       = sd_sec_read_end;
// v79：原来恒 0，坏扇区被当成正常数据继续拼图；现在如实上报，上层按失败处理。
assign sector_error      = sd_sec_read_error ? 8'h10 : 8'd0;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        busy_reg        <= 1'b0;
        byte_cnt        <= 9'd0;
        sd_sec_read     <= 1'b0;
        sd_sec_read_addr<= 32'd0;
    end else begin
        if (sector_req && !busy_reg) begin
            sd_sec_read      <= 1'b1;
            sd_sec_read_addr <= sector_lba;
            busy_reg         <= 1'b1;
            byte_cnt         <= 9'd0;
        end else if (sd_sec_read_end) begin
            sd_sec_read      <= 1'b0;
            busy_reg         <= 1'b0;
            byte_cnt         <= 9'd0;
        end else if (sd_sec_read_data_valid) begin
            byte_cnt         <= byte_cnt + 9'd1;
        end
    end
end

endmodule
