// this is for storing the result of the winning cluster to send it back to pc during transmission 
// although the winning cluster id width is only 2 bits we have used 8 bit here due to uart expecting a byte and
// so that it maps easily on fpga as a bram module
module bram_8bit #(
    parameter DEPTH = 10000,   // Number of pixels
    parameter ADDR_WIDTH = $clog2(DEPTH)  // clog function is easily synthesizable on fpga
)(
    input wire clk,
    input wire we,                   // Write Enable
    input wire [ADDR_WIDTH-1:0] addr, // Row number
    input wire [7:0] din,           // Data going IN (R,G,B)
    output reg [7:0] dout           // Data coming OUT
);
    reg [7:0] memory [0:DEPTH-1];//this is the bram

    always @(posedge clk) begin
        if (we) begin
            memory[addr] <= din;
        end
        // Always output the data at the current address
        // reads OLD value if we=1 (read-first mode)
        dout <= memory[addr]; //this maps easily on the BRAM rather than using a combinational block that would have been luts
    end


endmodule