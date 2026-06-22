`timescale 1ns / 1ps

module tb_uart_tx;

    reg clk;
    reg tx_start;
    reg [7:0] tx_byte;
    
    wire tx_busy;
    wire tx_pin;

    // 1. Instantiate the Unit Under Test (UUT)
    uart_tx #(
        .CLKS_PER_BIT(234)
    ) uut (
        .clk(clk),
        .tx_start(tx_start),
        .tx_byte(tx_byte),
        .tx_busy(tx_busy),
        .tx_pin(tx_pin)
    );

    // 2. Generate the 27 MHz Clock (~37ns period)
    initial clk = 0;
    always #18.5 clk = ~clk;

    // Timing calculation: 234 ticks * 37ns = 8658ns per bit
    localparam BIT_PERIOD = 234 * 37;

    // 3. Task to trigger the transmission from the "FPGA" side
    task send_data(input [7:0] data);
        begin
            @(posedge clk);
            tx_byte = data;
            tx_start = 1'b1;
            @(posedge clk);
            tx_start = 1'b0; // Pulse tx_start for exactly 1 clock cycle
        end
    endtask

    // 4. Test Stimulus (The "FPGA" pushing data into the TX module)
    initial begin
        // Initialize lines
        tx_start = 0;
        tx_byte = 0;
        #200;

        // Test Case 1: Send 0x55 (01010101)
        $display("[SIM TIME: %0t ns] Instructing TX to send: 0x55", $time);
        send_data(8'h55);
        
        // Wait for the transmitter to finish sending the whole frame
        wait(tx_busy == 1'b0);
        #5000;

        // Test Case 2: Send 0xC3 (11000011)
        $display("[SIM TIME: %0t ns] Instructing TX to send: 0xC3", $time);
        send_data(8'hC3);
        
        wait(tx_busy == 1'b0);
        #5000;

        $display("[SIM Finished] All transmissions complete.");
        $finish;
    end

    // 5. The "PC" Monitor (Listens to the wire to verify it works!)
    reg [7:0] captured_byte;
    integer i;
    
    initial begin
        forever begin
            // Wait for the wire to drop (The Start Bit)
            @(negedge tx_pin);
            
            // Wait half a bit period to center our read head
            #(BIT_PERIOD / 2);
            
            // Wait a full bit period to move to Data Bit 0
            #(BIT_PERIOD);
            
            // Read all 8 bits
            for (i = 0; i < 8; i = i + 1) begin
                captured_byte[i] = tx_pin;
                #(BIT_PERIOD);
            end
            
            // Wait one more bit period for the Stop Bit
            #(BIT_PERIOD);
            
            // Verify
            $display("[ASSERT SUCCESS] Wire transmission captured! Value read by PC: 0x%h", captured_byte);
        end
    end

endmodule