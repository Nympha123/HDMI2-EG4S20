`timescale 1ns/1ps

module fifo_prefetch_2 #(
    parameter DATA_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  raw_empty,
    input  wire                  raw_valid,
    input  wire [DATA_WIDTH-1:0] raw_data,
    output wire                  raw_read_en,
    input  wire                  consume,
    output wire                  out_valid,
    output wire                  out_empty,
    output wire [DATA_WIDTH-1:0] out_data
);

    reg [DATA_WIDTH-1:0] slot0;
    reg [DATA_WIDTH-1:0] slot1;
    reg [1:0]            count;
    reg [1:0]            outstanding;

    wire pop = consume && (count != 0);
    wire [2:0] reserved = {1'b0, count} + {1'b0, outstanding};

    assign raw_read_en = !raw_empty &&
                         ((reserved < 3'd2) || (pop && (reserved == 3'd2)));
    assign out_valid = (count != 0);
    assign out_empty = (count == 0);
    assign out_data  = slot0;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            slot0       <= {DATA_WIDTH{1'b0}};
            slot1       <= {DATA_WIDTH{1'b0}};
            count       <= 2'd0;
            outstanding <= 2'd0;
        end else begin
            case ({raw_read_en, raw_valid})
                2'b10: outstanding <= outstanding + 2'd1;
                2'b01: outstanding <= outstanding - 2'd1;
                default: outstanding <= outstanding;
            endcase

            case ({pop, raw_valid})
                2'b00: count <= count;
                2'b01: begin
                    if (count == 2'd0)
                        slot0 <= raw_data;
                    else
                        slot1 <= raw_data;
                    count <= count + 2'd1;
                end
                2'b10: begin
                    if (count == 2'd2)
                        slot0 <= slot1;
                    count <= count - 2'd1;
                end
                2'b11: begin
                    if (count == 2'd1)
                        slot0 <= raw_data;
                    else begin
                        slot0 <= slot1;
                        slot1 <= raw_data;
                    end
                    count <= count;
                end
            endcase
        end
    end

endmodule
