`timescale 1ns / 1ps

module tb_inference;

    reg clk;
    reg rx_pin;
    wire tx_pin;
    wire [5:0] led;

    // 1. Instantiate Your Module
    inference uut (
        .clk(clk),
        .rx_pin(rx_pin),
        .tx_pin(tx_pin),
        .led(led)
    );

    // 2. Generate the 27 MHz Clock (~37ns period)
    initial clk = 0;
    always #18.5 clk = ~clk;

    // Timing calculation: 234 ticks * 37ns = 8658ns per bit
    localparam BIT_PERIOD = 234 * 37;

    // --- SELF CHECKING VARIABLES ---
    reg [1:0] expected_cluster;
    integer error_count = 0;
    // -------------------------------

    // 3. PC Transmitter Task (Sends 1 Byte to FPGA)
    task send_byte(input [7:0] data);
        integer i;
        begin
            rx_pin = 1'b0; // Start Bit
            #(BIT_PERIOD);
            for (i = 0; i < 8; i = i + 1) begin
                rx_pin = data[i]; // Data Bits
                #(BIT_PERIOD);
            end
            rx_pin = 1'b1; // Stop Bit
            #(BIT_PERIOD);
        end
    endtask

    // 4. PC Pixel Streamer (Sends R, G, B sequentially)
    task send_pixel(input [7:0] r, input [7:0] g, input [7:0] b);
        begin
            send_byte(r);
            #(BIT_PERIOD); 
            send_byte(g);
            #(BIT_PERIOD);
            send_byte(b);
        end
    endtask

    // 5. PC Receiver & Checker Logic
    reg [7:0] captured_byte;
    integer j;
    initial begin
        forever begin
            // Wait for the TX wire to drop (Start Bit from FPGA)
            @(negedge tx_pin);
            
            #(BIT_PERIOD / 2); // Center read head
            #(BIT_PERIOD);     // Move to first bit
            
            // Read all 8 bits
            for (j = 0; j < 8; j = j + 1) begin
                captured_byte[j] = tx_pin;
                #(BIT_PERIOD);
            end
            #(BIT_PERIOD); // Wait out Stop Bit
            
            // SELF-CHECKING LOGIC
            if (captured_byte[1:0] === expected_cluster) begin
                $display("[PASS] FPGA returned %d. Matches expected!", captured_byte[1:0]);
            end else begin
                $display("[FAIL] FPGA returned %d. Expected %d!", captured_byte[1:0], expected_cluster);
                error_count = error_count + 1;
            end
        end
    end

    // 6. The Master Test Sequence
    initial begin
        $dumpfile("sim.vcd");
        $dumpvars(0, tb_inference);

        // Initialize line
        rx_pin = 1'b1;
        #1000;

        // Test Case 1: purely RED pixel -> Expect Cluster 0
        expected_cluster = 2'd0;
        $display("[SIM TIME: %0t ns] Sending RED Pixel...", $time);
        send_pixel(8'hFF, 8'h00, 8'h00);
        #500000;

        // Test Case 2: purely GREEN pixel -> Expect Cluster 1
        expected_cluster = 2'd1;
        $display("[SIM TIME: %0t ns] Sending GREEN Pixel...", $time);
        send_pixel(8'h00, 8'hFF, 8'h00);
        #500000;

        // Test Case 3: purely BLUE pixel -> Expect Cluster 2
        expected_cluster = 2'd2;
        $display("[SIM TIME: %0t ns] Sending BLUE Pixel...", $time);
        send_pixel(8'h00, 8'h00, 8'hFF);
        #500000;

        // Test Case 4: MIXED pixel (Mostly Green) -> Expect Cluster 1
        expected_cluster = 2'd1;
        $display("[SIM TIME: %0t ns] Sending DARK GREEN Pixel...", $time);
        send_pixel(8'd10, 8'd200, 8'd50);
        #500000;

        // Print final summary
        $display("========================================");
        if (error_count == 0) begin
            $display("  ALL TESTS PASSED! (0 Errors)");
        end else begin
            $display("  SIMULATION FAILED WITH %d ERRORS.", error_count);
        end
        $display("========================================");
        
        $finish;
    end

endmodule