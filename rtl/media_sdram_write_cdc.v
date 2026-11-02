`timescale 1ns/1ps

module media_sdram_write_cdc #(
    parameter integer ADDR_WIDTH = 21,
    parameter integer FIFO_ADDR_WIDTH = 9,
    parameter integer BURST_SIZE = 128
) (
    input  wire                  src_clk,
    input  wire                  src_rst_n,
    input  wire                  src_wr_en,
    input  wire [ADDR_WIDTH-1:0] src_wr_addr,
    input  wire [3:0]            src_wr_mask,
    input  wire [31:0]           src_wr_data,
    output wire                  src_full,
    output reg                   src_overflow,

    input  wire                  dst_clk,
    input  wire                  dst_rst_n,
    output wire                  dst_app_wr_en,
    output wire [ADDR_WIDTH-1:0] dst_app_wr_addr,
    output wire [3:0]            dst_app_wr_mask,
    output wire [31:0]           dst_app_wr_data,
    output wire                  dst_idle
);
    localparam integer COMMAND_WIDTH = ADDR_WIDTH + 36;
    localparam integer BURST_COUNT_WIDTH = $clog2(BURST_SIZE);
    localparam integer BLOCK_PTR_WIDTH =
        FIFO_ADDR_WIDTH - BURST_COUNT_WIDTH + 1;

    wire [COMMAND_WIDTH-1:0] fifo_rd_data;
    wire fifo_rd_valid;
    wire fifo_empty;
    reg fifo_rd_en;
    reg burst_active;
    reg [$clog2(BURST_SIZE+1)-1:0] burst_remaining;
    reg [BURST_COUNT_WIDTH-1:0] src_burst_word_count;
    reg [BLOCK_PTR_WIDTH-1:0] src_block_binary;
    reg [BLOCK_PTR_WIDTH-1:0] src_block_gray;
    reg [BLOCK_PTR_WIDTH-1:0] src_block_gray_sync1;
    reg [BLOCK_PTR_WIDTH-1:0] src_block_gray_sync2;
    reg [BLOCK_PTR_WIDTH-1:0] dst_block_binary;
    reg [BLOCK_PTR_WIDTH-1:0] dst_block_gray;
    wire src_accept = src_wr_en && !src_full;
    wire block_pending = src_block_gray_sync2 != dst_block_gray;

    async_command_fifo #(
        .DATA_WIDTH(COMMAND_WIDTH),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) u_fifo (
        .wr_clk(src_clk), .wr_rst_n(src_rst_n),
        .wr_en(src_wr_en),
        .wr_data({src_wr_addr, src_wr_mask, src_wr_data}),
        .wr_full(src_full),
        .rd_clk(dst_clk), .rd_rst_n(dst_rst_n),
        .rd_en(fifo_rd_en), .rd_data(fifo_rd_data),
        .rd_valid(fifo_rd_valid), .rd_empty(fifo_empty),
        .rd_level()
    );

    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            src_overflow <= 1'b0;
            src_burst_word_count <= 0;
            src_block_binary <= 0;
            src_block_gray <= 0;
        end else begin
            if (src_wr_en && src_full)
                src_overflow <= 1'b1;
            if (src_accept) begin
                if (src_burst_word_count == BURST_SIZE-1) begin
                    src_burst_word_count <= 0;
                    src_block_binary <= src_block_binary + 1'b1;
                    src_block_gray <= ((src_block_binary + 1'b1) >> 1) ^
                                      (src_block_binary + 1'b1);
                end else begin
                    src_burst_word_count <= src_burst_word_count + 1'b1;
                end
            end
        end
    end

    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            fifo_rd_en <= 1'b0;
            burst_active <= 1'b0;
            burst_remaining <= 0;
            src_block_gray_sync1 <= 0;
            src_block_gray_sync2 <= 0;
            dst_block_binary <= 0;
            dst_block_gray <= 0;
        end else begin
            src_block_gray_sync1 <= src_block_gray;
            src_block_gray_sync2 <= src_block_gray_sync1;
            fifo_rd_en <= 1'b0;
            if (!burst_active && block_pending) begin
                burst_active <= 1'b1;
                burst_remaining <= BURST_SIZE;
            end else if (burst_active) begin
                fifo_rd_en <= 1'b1;
                if (burst_remaining == 1) begin
                    burst_active <= 1'b0;
                    burst_remaining <= 0;
                    dst_block_binary <= dst_block_binary + 1'b1;
                    dst_block_gray <= ((dst_block_binary + 1'b1) >> 1) ^
                                      (dst_block_binary + 1'b1);
                end else begin
                    burst_remaining <= burst_remaining - 1'b1;
                end
            end
        end
    end

    assign dst_app_wr_en = fifo_rd_valid;
    assign dst_app_wr_addr = fifo_rd_data[COMMAND_WIDTH-1:36];
    assign dst_app_wr_mask = fifo_rd_data[35:32];
    assign dst_app_wr_data = fifo_rd_data[31:0];
    assign dst_idle = fifo_empty && !block_pending &&
                      !burst_active && !fifo_rd_valid;
endmodule

module async_command_fifo #(
    parameter integer DATA_WIDTH = 57,
    parameter integer ADDR_WIDTH = 9
) (
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output reg                   wr_full,

    input  wire                  rd_clk,
    input  wire                  rd_rst_n,
    input  wire                  rd_en,
    output reg  [DATA_WIDTH-1:0] rd_data,
    output reg                   rd_valid,
    output reg                   rd_empty,
    output wire [ADDR_WIDTH:0]   rd_level
);
    localparam integer PTR_WIDTH = ADDR_WIDTH + 1;
    localparam integer DEPTH = 1 << ADDR_WIDTH;

    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    reg [PTR_WIDTH-1:0] wr_binary;
    reg [PTR_WIDTH-1:0] wr_gray;
    reg [PTR_WIDTH-1:0] rd_binary;
    reg [PTR_WIDTH-1:0] rd_gray;
    reg [PTR_WIDTH-1:0] rd_gray_sync1;
    reg [PTR_WIDTH-1:0] rd_gray_sync2;
    reg [PTR_WIDTH-1:0] wr_gray_sync1;
    reg [PTR_WIDTH-1:0] wr_gray_sync2;

    wire wr_accept = wr_en && !wr_full;
    wire rd_accept = rd_en && !rd_empty;
    wire [PTR_WIDTH-1:0] wr_binary_next = wr_binary + wr_accept;
    wire [PTR_WIDTH-1:0] rd_binary_next = rd_binary + rd_accept;
    wire [PTR_WIDTH-1:0] wr_gray_next =
        (wr_binary_next >> 1) ^ wr_binary_next;
    wire [PTR_WIDTH-1:0] rd_gray_next =
        (rd_binary_next >> 1) ^ rd_binary_next;
    wire wr_full_next = wr_gray_next ==
        {~rd_gray_sync2[PTR_WIDTH-1:PTR_WIDTH-2],
         rd_gray_sync2[PTR_WIDTH-3:0]};
    wire rd_empty_next = rd_gray_next == wr_gray_sync2;

    function [PTR_WIDTH-1:0] gray_to_binary;
        input [PTR_WIDTH-1:0] value;
        integer bit_index;
        begin
            gray_to_binary[PTR_WIDTH-1] = value[PTR_WIDTH-1];
            for (bit_index = PTR_WIDTH-2; bit_index >= 0;
                 bit_index = bit_index - 1)
                gray_to_binary[bit_index] =
                    gray_to_binary[bit_index+1] ^ value[bit_index];
        end
    endfunction

    wire [PTR_WIDTH-1:0] wr_binary_rd = gray_to_binary(wr_gray_sync2);
    assign rd_level = wr_binary_rd - rd_binary;

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_binary <= 0;
            wr_gray <= 0;
            rd_gray_sync1 <= 0;
            rd_gray_sync2 <= 0;
            wr_full <= 1'b0;
        end else begin
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;
            if (wr_accept)
                memory[wr_binary[ADDR_WIDTH-1:0]] <= wr_data;
            wr_binary <= wr_binary_next;
            wr_gray <= wr_gray_next;
            wr_full <= wr_full_next;
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_binary <= 0;
            rd_gray <= 0;
            wr_gray_sync1 <= 0;
            wr_gray_sync2 <= 0;
            rd_data <= 0;
            rd_valid <= 1'b0;
            rd_empty <= 1'b1;
        end else begin
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
            rd_valid <= rd_accept;
            if (rd_accept)
                rd_data <= memory[rd_binary[ADDR_WIDTH-1:0]];
            rd_binary <= rd_binary_next;
            rd_gray <= rd_gray_next;
            rd_empty <= rd_empty_next;
        end
    end
endmodule
