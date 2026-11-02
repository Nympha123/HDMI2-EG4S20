`timescale 1ns / 1ps

// Asynchronous assertion and synchronous release for one clock domain.
module reset_sync (
    input  wire clk,
    input  wire ext_rst_n,
    output wire rst_n_sync
);

    (* async_reg = "true" *) reg s1, s2;

    always @(posedge clk or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            s1 <= 1'b0;
            s2 <= 1'b0;
        end else begin
            s1 <= 1'b1;
            s2 <= s1;
        end
    end

    assign rst_n_sync = s2;

endmodule
