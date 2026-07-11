// this is for all the incoming pixels from the pc for the processing 
`timescale 1ns / 1ps
// Key design decisions for FPGA correctness:
//
// 1. SEPARATE read and write address ports — eliminates the combinational
//    address mux from the original design that could glitch during state
//    transitions and violate BRAM setup timing.
//
// 2. Read output is REGISTERED (dout valid one clock after rd_addr is
//    presented). This matches real Gowin BSRAM behavior. The FSM must
//    account for this 1-cycle latency explicitly.
//
// 3. No reliance on initial memory contents. All locations must be written
//    before they are read; the FSM enforces this.
module bram24bit_v2 #(
    parameter DEPTH      = 8192,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input  wire                    clk,

    // Write port
    input  wire                    we,
    input  wire [ADDR_WIDTH-1:0]   wr_addr,
    input  wire [23:0]             din,

    // Read port (independent address)
    input  wire [ADDR_WIDTH-1:0]   rd_addr,
    output reg  [23:0]             dout
);

    // Inference-friendly memory declaration.
    // No initializer — FPGA BSRAM powers up with undefined contents, and we
    // do not rely on any particular initial value. The FSM only reads
    // addresses that have been previously written.
    reg [23:0] memory [0:DEPTH-1];

    // Single-clock, dual-address pattern.
    // Write-first on address collision (wr_addr == rd_addr && we) is the
    // safest for Gowin BSRAM, but our FSM never reads and writes the same
    // address simultaneously, so the collision policy doesn't matter in
    // practice.
    always @(posedge clk) begin
        if (we) begin
            memory[wr_addr] <= din;
        end
        // Registered read — output valid ONE cycle after rd_addr is presented.
        // This is the natural behavior of real block RAM.
        dout <= memory[rd_addr];
    end

endmodule
