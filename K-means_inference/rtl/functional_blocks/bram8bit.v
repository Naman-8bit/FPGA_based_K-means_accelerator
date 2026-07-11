// this is for storing the result of the winning cluster to send it back to pc during transmission 
// although the winning cluster id width is only 2 bits we have used 8 bit here due to uart expecting a byte and
// so that it maps easily on fpga as a bram module
`timescale 1ns / 1ps
// Same design as bram24bit:
//   - Separate read and write address ports (no combinational mux)
//   - Registered read output (1-cycle latency)
//   - No reliance on initial memory contents
module bram8bit_v2 #(
    parameter DEPTH      = 8192,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input  wire                    clk,

    // Write port
    input  wire                    we,
    input  wire [ADDR_WIDTH-1:0]   wr_addr,
    input  wire [7:0]              din,

    // Read port (independent address)
    input  wire [ADDR_WIDTH-1:0]   rd_addr,
    output reg  [7:0]              dout
);

    reg [7:0] memory [0:DEPTH-1];

    always @(posedge clk) begin
        if (we) begin
            memory[wr_addr] <= din;
        end
        dout <= memory[rd_addr];
    end

endmodule