`timescale 1ns / 1ps

module tb_uart_rx;

    reg clk;
    reg rx_pin;
    wire [7:0] rx_byte;
    wire rx_ready;

    // 1. Instantiate the Unit Under Test (UUT)
    uart_rx #(
        .CLKS_PER_BIT(234) // Match your 27MHz/115200 timing
    ) uut (
        .clk(clk),
        .rx_pin(rx_pin),
        .rx_byte(rx_byte),
        .rx_ready(rx_ready)
    );

    // 2. Generate the 27 MHz Clock
    // Period is ~37ns -> Half period is 18.5ns
    initial clk = 0;
    always #18.5 clk = ~clk;

    // Timing calculation: 234 clock ticks * 37ns per tick = 8658 ns per bit
    localparam BIT_PERIOD = 234 * 37;

    // 3. Automated Task to Simulate a Serial Byte Stream
    task send_byte(input [7:0] data);
        integer i;
        begin
            // Start Bit (Wire drops Low)
            rx_pin = 1'b0;
            #(BIT_PERIOD);

            // 8 Data Bits (Sent Least Significant Bit first)
            for (i = 0; i < 8; i = i + 1) begin
                rx_pin = data[i];
                #(BIT_PERIOD);
            end

            // Stop Bit (Wire returns High to Idle)
            rx_pin = 1'b1;
            #(BIT_PERIOD);
        end
    endtask

    // 4. Test Stimulus Waveform Execution
    initial begin
        // Initialize line to standard UART Idle state (High)
        rx_pin = 1'b1;
        #200; // Wait a moment for the system to settle

        // Test Case 1: Send alternating bit pattern 0x55 (01010101)
        $display("[SIM TIME: %0t ns] Injecting serial byte: 0x55", $time);
        send_byte(8'h55);
        #500;

        // Test Case 2: Send reverse pattern 0xAA (10101010)
        $display("[SIM TIME: %0t ns] Injecting serial byte: 0xAA", $time);
        send_byte(8'hAA);
        #500;

        // Test Case 3: Send structural pattern 0xC3 (11000011)
        $display("[SIM TIME: %0t ns] Injecting serial byte: 0xC3", $time);
        send_byte(8'hC3);
        #2000;

        $display("[SIM Finished] All vectors pushed. Closing simulation.");
        $finish;
    end

    // 5. Assertions: Monitor Output Ports for Verification
    always @(posedge clk) begin
        if (rx_ready) begin
            $display("[ASSERT SUCCESS] rx_ready went HIGH! Captured Byte value: 0x%h", rx_byte);
        end
    end

endmodule