`timescale 1ns / 1ps

module uart_rx #(
    // 27,000,000 Hz / 115,200 Baud = ~234
    // its parametrized so can be changed according to the need
    parameter CLKS_PER_BIT = 234 
)(
    input  wire clk,       // 27 MHz System Clock
    input  wire rx_pin,    //(1 = Idle, 0 = Start)
    output reg[7:0] rx_byte,   // 8bit data
    output reg rx_ready   // Goes HIGH for exactly 1 clock cycle when data is valid
);

    localparam  HALF_CLK_CYCLE = CLKS_PER_BIT/2;

    reg [3:0] rxState = 0;// state if the uart in fsm
    reg [12:0] rxCounter = 0;//clk cycle counter
    reg [2:0] rxBitNumber = 0;//no of bits or bit count
    reg [7:0] dataIn = 0;//temp reg to store the data before valid is hit (prolly a sipo mode reg)
    reg byteReady = 0;//flagged 0 when output is ready
    
    // fsm states
    localparam[2:0]
    IDLE = 0,
    START_BIT = 1,
    READ_WAIT = 2,
    READ = 3,
    STOP =4;

    // the core fsm logic
    always @(posedge clk) begin
        case(rxState) 
            IDLE: begin
                rx_ready <= 0;    // Reset the flag!
                rxCounter <= 1;   // Reset the stopwatch!
                rxBitNumber <= 0;
                if(rx_pin == 1'b0) begin
                    rxState <= START_BIT;
                end
            end
            START_BIT: begin
                if(rxCounter == HALF_CLK_CYCLE)begin
                    rxState <= READ_WAIT;
                    rxCounter<=1;
                end
                else begin
                    rxCounter <= rxCounter + 1;
                end
            end
            READ_WAIT: begin
                rxCounter <= rxCounter + 1;
                if((rxCounter+1) == CLKS_PER_BIT)begin
                    rxState <= READ;
                end
            end
            READ: begin
                // push the data in shift reg
                rxCounter<=1;
                rxBitNumber <= rxBitNumber+1;
                rx_byte <= {rx_pin, rx_byte[7:1]};
                if (rxBitNumber == 3'b111) begin
                    rxState <= STOP;
                end else begin
                    rxState <= READ_WAIT;
                end
            end
            STOP: begin
                rxCounter <= rxCounter + 1;
                if ((rxCounter + 1) == CLKS_PER_BIT) begin
                    rxState <= IDLE;
                    rxCounter <= 0;
                    rx_ready <=1;
                end
            end
        endcase
    end

endmodule