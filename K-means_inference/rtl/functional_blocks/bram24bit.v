// this is for all the incoming pixels from the pc for the processing 
module bram_24bit #(
    parameter DEPTH = 8192,   // Number of pixels
    parameter ADDR_WIDTH = $clog2(DEPTH)  // clog function is easily synthesizable on fpga
)(
    input wire clk,
    input wire we,                   // Write Enable
    input wire [ADDR_WIDTH-1:0] addr, // Row number
    input wire [23:0] din,           // Data going IN (R,G,B)
    output reg [23:0] dout           // Data coming OUT
);
    reg [23:0] memory [0:DEPTH-1];//this is the bram

    always @(posedge clk) begin
        if (we) begin
            memory[addr] <= din;
        end
        // Always output the data at the current address
        dout <= memory[addr]; //this maps easily on the BRAM rather than using a combinational block that would have been luts
    end


endmodule