`timescale 1ns / 1ps

module tb_inference_bram();

    // 1. Signals matching the top module
    reg clk;
    reg rx_pin;
    wire tx_pin;
    wire [5:0] led;

    // 2. Instantiate the Unit Under Test (UUT)
    // We set DEPTH to 10 to test the auto-trigger chunking!
    inference_bram #(
        .DEPTH(10) 
    ) uut (
        .clk(clk),
        .rx_pin(rx_pin),
        .tx_pin(tx_pin),
        .led(led)
    );

    // 3. Clock Generation (27 MHz -> ~37.03 ns period)
    initial begin
        clk = 0;
        forever #18.5 clk = ~clk;
    end

    // 4. UART Configuration
    // 115200 baud = ~8680 ns per bit
    localparam BIT_PERIOD = 8680; 

    // 5. Task to simulate Python sending a byte over UART
    task send_byte;
        input [7:0] data;
        integer i;
        begin
            rx_pin = 0; // Start bit
            #(BIT_PERIOD);
            
            for (i = 0; i < 8; i = i + 1) begin // Data bits
                rx_pin = data[i];
                #(BIT_PERIOD);
            end
            
            rx_pin = 1; // Stop bit
            #(BIT_PERIOD);
            #(BIT_PERIOD); // Small gap between bytes to simulate software overhead
        end
    endtask

    // 6. Main Test Sequence
    integer p;
    initial begin
        // Initialize
        rx_pin = 1; 
        
        // Optional: Dump waveform for GTKWave
        $dumpfile("tb_inference_bram.vcd");
        $dumpvars(0, tb_inference_bram);
        
        #100000; 

        $display("=================================================");
        $display("  TEST PHASE 1: SCRAMBLED CHUNK (10 Pixels)      ");
        $display("=================================================");
        
        $display("Sending OP_LOAD (0xAA) to wake up FPGA...");
        send_byte(8'hAA);

        // Send 10 Pixels alternating: Red, Green, Blue, Red, Green...
        // Expected clusters: 0, 1, 2, 0, 1, 2, 0, 1, 2, 0
        for (p = 0; p < 10; p = p + 1) begin
            if (p % 3 == 0) begin
                send_byte(8'hFF); send_byte(8'h00); send_byte(8'h00); // Red -> Cluster 0
            end else if (p % 3 == 1) begin
                send_byte(8'h00); send_byte(8'hFF); send_byte(8'h00); // Green -> Cluster 1
            end else begin
                send_byte(8'h00); send_byte(8'h00); send_byte(8'hFF); // Blue -> Cluster 2
            end
        end
        
        $display("10 Alternating Pixels sent! FPGA should auto-compute now...");

        // Wait for FPGA to transmit 10 bytes back
        // 10 bytes * ~86.8us = ~868us. Waiting 1.5ms to be safe.
        #1500000; 

        $display("\n=================================================");
        $display("  TEST PHASE 2: MIXED PARTIAL CHUNK (4 Pixels)   ");
        $display("=================================================");
        
        // Since the FSM went back to IDLE, wake it up again for the next batch
        $display("Sending OP_LOAD (0xAA) to wake up FPGA...");
        send_byte(8'hAA);

        // Send 4 Pixels: Green, Green, Blue, Red
        // Expected clusters: 1, 1, 2, 0
        send_byte(8'h00); send_byte(8'hFF); send_byte(8'h00); // Pixel 11: Green
        send_byte(8'h00); send_byte(8'hFF); send_byte(8'h00); // Pixel 12: Green
        send_byte(8'h00); send_byte(8'h00); send_byte(8'hFF); // Pixel 13: Blue
        send_byte(8'hFF); send_byte(8'h00); send_byte(8'h00); // Pixel 14: Red
        
        $display("Sending Execute Opcode (0xBB)...");
        send_byte(8'hBB);

        // Wait for FPGA to transmit 4 bytes back
        #1000000;

        $display("\n--- TEST COMPLETE ---");
        $finish;
    end

    // 7. UART Monitor to print received results exactly like Python's ser.read()
    reg [7:0] fpga_result;
    integer j;
    integer result_count = 0;
    
    always @(negedge tx_pin) begin
        #(BIT_PERIOD / 2); // Wait to middle of start bit
        if (tx_pin == 0) begin // Confirm it's a start bit
            #(BIT_PERIOD);     // Move to first data bit
            
            for (j = 0; j < 8; j = j + 1) begin
                fpga_result[j] = tx_pin;
                #(BIT_PERIOD);
            end
            
            result_count = result_count + 1;
            $display("[%0t] Received Result %0d: Cluster %0d", $time, result_count, fpga_result);
        end
    end

endmodule