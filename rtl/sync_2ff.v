`timescale 1ns / 1ps

// Synchronizes a slowly changing single-bit level into a destination domain.
module sync_2ff #(
    parameter RESET_VAL = 1'b0
) (
    input  wire clk,
    input  wire rst_n,
    input  wire async_in,
    output wire sync_out
);

    (* async_reg = "true" *) reg s1, s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1 <= RESET_VAL;
            s2 <= RESET_VAL;
        end else begin
            s1 <= async_in;
            s2 <= s1;
        end
    end

    assign sync_out = s2;

endmodule
