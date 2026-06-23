`timescale 1ns / 1ps

module uart_tx #(
    parameter CLKS_PER_BIT = 234 // 27MHz / 115200 Baud
)(
    input  wire clk,
    input  wire tx_start,  // Trigger pulse to send
    input  wire[7:0] tx_byte,   // Data to send
    output reg tx_busy = 0, // 1 = Busy, 0 = Ready
    output reg tx_pin  = 1  
);
    reg [1:0] txState = 0; //state reg
    reg [12:0] txCounter = 0;   // to count no of clock cycle
    reg [2:0] txBitNumber = 0; // no of bits sent
    reg [7:0] dataToTx = 0;    // data copied temporarily 

    // FSM States
    localparam [1:0]
        IDLE = 2'd0,
        START_BIT = 2'd1,
        DATA = 2'd2,
        STOP_BIT = 2'd3;

    always @(posedge clk) begin
        case(txState)
            
            IDLE: begin
                tx_pin  <= 1'b1; // Idle HIGH
                tx_busy <= 1'b0; // Ready for data
                txCounter   <= 0;
                txBitNumber <= 0;

                if (tx_start == 1'b1) begin
                    tx_busy  <= 1'b1;      // Lock interface
                    dataToTx <= tx_byte; 
                    txState  <= START_BIT; 
                end
            end
            
            START_BIT: begin
                tx_pin <= 1'b0; // Start bit is LOW
                
                if ((txCounter + 1) == CLKS_PER_BIT) begin
                    txCounter <= 0;
                    txState   <= DATA; 
                end else begin
                    txCounter <= txCounter + 1;
                end
            end
            
            DATA: begin
                tx_pin <= dataToTx[txBitNumber]; // Drive current bit
                
                if ((txCounter + 1) == CLKS_PER_BIT) begin
                    txCounter <= 0; 
                    
                    if (txBitNumber == 3'b111) begin
                        txState <= STOP_BIT; // 8 bits sent
                    end else begin
                        txBitNumber <= txBitNumber + 1; 
                    end
                end else begin
                    txCounter <= txCounter + 1;
                end
            end
            
            STOP_BIT: begin
                tx_pin <= 1'b1; // Stop bit is HIGH
                
                if ((txCounter + 1) == CLKS_PER_BIT) begin
                    txCounter <= 0;
                    txState   <= IDLE; // Frame done
                end else begin
                    txCounter <= txCounter + 1;
                end
            end
            
            default: txState <= IDLE;
            
        endcase
    end

endmodule