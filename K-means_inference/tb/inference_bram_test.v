`timescale 1ns / 1ps

// ============================================================================
// inference_bram_test.v — Self-Checking Testbench for inference_bram_v2
// ============================================================================
//
// Based on the existing tb_inference.v and tb_inference_bram2.v testbenches
// in this repo.  Uses the same UART send_byte task, same BIT_PERIOD, and
// same check methodology (capture UART output, compare to expected).
//
// Test Plan:
//   Phase 1: 3-pixel chunk (Red, Green, Blue) — expect clusters 0, 1, 2
//   Phase 2: 10-pixel alternating chunk, auto-trigger at DEPTH=10
//   Phase 3: 4-pixel partial chunk with explicit OP_EXECUTE
//   Phase 4: Edge case — OP_EXECUTE with no pixels loaded (should be no-op)
//
// Pass criteria:  error_count == 0 at end, all expected cluster IDs match.
// ============================================================================

module inference_bram_test;

    // =====================================================================
    // DUT signals
    // =====================================================================
    reg         clk;
    reg         rx_pin;
    wire        tx_pin;
    wire [5:0]  led;

    // Instantiate the v2 BRAM design with small DEPTH for fast simulation
    inference_bram_v2 #(
        .DEPTH(10)
    ) uut (
        .clk(clk),
        .rx_pin(rx_pin),
        .tx_pin(tx_pin),
        .led(led)
    );

    // =====================================================================
    // Clock generation: 27 MHz -> ~37.04 ns period
    // =====================================================================
    initial clk = 0;
    always #18.5 clk = ~clk;

    // =====================================================================
    // UART timing (same as existing testbenches)
    // 115200 baud: 234 ticks * 37ns ≈ 8658 ns.  Using 8680 for consistency
    // with the existing tb_inference_bram.v / tb_inference_bram2.v.
    // =====================================================================
    localparam BIT_PERIOD = 8680;

    // =====================================================================
    // SELF-CHECKING infrastructure
    // =====================================================================
    integer error_count   = 0;
    integer result_count  = 0;
    integer expected_idx  = 0;

    // Expected results buffer — large enough for biggest test phase
    reg [1:0] expected [0:31];
    integer   expected_len = 0;

    // =====================================================================
    // UART TX task: simulate host sending one byte to FPGA
    // (identical to existing testbenches)
    // =====================================================================
    task send_byte;
        input [7:0] data;
        integer i;
        begin
            rx_pin = 0;            // Start bit
            #(BIT_PERIOD);
            for (i = 0; i < 8; i = i + 1) begin
                rx_pin = data[i];  // Data bits (LSB first)
                #(BIT_PERIOD);
            end
            rx_pin = 1;            // Stop bit
            #(BIT_PERIOD);
            #(BIT_PERIOD);         // Inter-byte gap
        end
    endtask

    // =====================================================================
    // UART RX monitor: capture bytes transmitted by FPGA and check them
    // against the expected[] array.
    //
    // This runs continuously in the background, same pattern as
    // tb_inference.v's receiver block.
    // =====================================================================
    reg [7:0] captured_byte;
    integer j;

    initial begin
        forever begin
            // Wait for start bit (falling edge on tx_pin)
            @(negedge tx_pin);
            #(BIT_PERIOD / 2);     // Center on start bit

            // Confirm it's a real start bit (not a glitch)
            if (tx_pin == 0) begin
                #(BIT_PERIOD);     // Move to first data bit

                for (j = 0; j < 8; j = j + 1) begin
                    captured_byte[j] = tx_pin;
                    #(BIT_PERIOD);
                end
                // Now in stop bit — don't need to wait it out

                result_count = result_count + 1;

                // Self-check against expected value
                if (expected_idx < expected_len) begin
                    if (captured_byte[1:0] === expected[expected_idx]) begin
                        $display("[PASS] Result %0d: Cluster %0d (expected %0d)",
                                 result_count, captured_byte[1:0], expected[expected_idx]);
                    end else begin
                        $display("[FAIL] Result %0d: Cluster %0d (expected %0d)",
                                 result_count, captured_byte[1:0], expected[expected_idx]);
                        error_count = error_count + 1;
                    end
                    expected_idx = expected_idx + 1;
                end else begin
                    // Unexpected extra byte — that's a failure
                    $display("[FAIL] Unexpected extra result byte: %0d", captured_byte);
                    error_count = error_count + 1;
                end
            end
        end
    end

    // =====================================================================
    // Helper task: wait for N results to arrive (with timeout)
    // =====================================================================
    task wait_for_results;
        input integer count;
        input integer timeout_ns;
        integer target;
        integer waited;
        begin
            target = result_count + count;
            waited = 0;
            while (result_count < target && waited < timeout_ns) begin
                #1000;
                waited = waited + 1000;
            end
            if (result_count < target) begin
                $display("[FAIL] Timeout waiting for results. Got %0d, expected %0d",
                         result_count - (target - count), count);
                error_count = error_count + 1;
            end
        end
    endtask

    // =====================================================================
    // Main test sequence
    // =====================================================================
    integer p;

    initial begin
        $dumpfile("inference_bram_test.vcd");
        $dumpvars(0, inference_bram_test);

        // Initialize UART idle
        rx_pin = 1;
        #50000;  // Let the design settle

        // =================================================================
        // PHASE 1: Simple 3-pixel test (Red, Green, Blue)
        //          Manually triggered with OP_EXECUTE
        // =================================================================
        $display("");
        $display("=================================================");
        $display("  PHASE 1: 3 Pixels (Red, Green, Blue)");
        $display("=================================================");

        expected[0] = 2'd0;  // Red -> cluster 0
        expected[1] = 2'd1;  // Green -> cluster 1
        expected[2] = 2'd2;  // Blue -> cluster 2
        expected_len = 3;
        expected_idx = 0;
        result_count = 0;

        send_byte(8'hAA);  // OP_LOAD

        // Pixel 1: Pure Red
        send_byte(8'hFF); send_byte(8'h00); send_byte(8'h00);
        // Pixel 2: Pure Green
        send_byte(8'h00); send_byte(8'hFF); send_byte(8'h00);
        // Pixel 3: Pure Blue
        send_byte(8'h00); send_byte(8'h00); send_byte(8'hFF);

        send_byte(8'hBB);  // OP_EXECUTE

        wait_for_results(3, 2000000);

        // =================================================================
        // PHASE 2: 10-pixel alternating (DEPTH=10, auto-trigger)
        // =================================================================
        $display("");
        $display("=================================================");
        $display("  PHASE 2: 10 Alternating Pixels (auto-trigger)");
        $display("=================================================");

        // Expected: 0,1,2,0,1,2,0,1,2,0
        expected[0] = 2'd0; expected[1] = 2'd1; expected[2] = 2'd2;
        expected[3] = 2'd0; expected[4] = 2'd1; expected[5] = 2'd2;
        expected[6] = 2'd0; expected[7] = 2'd1; expected[8] = 2'd2;
        expected[9] = 2'd0;
        expected_len = 10;
        expected_idx = 0;
        result_count = 0;

        send_byte(8'hAA);  // OP_LOAD

        for (p = 0; p < 10; p = p + 1) begin
            if (p % 3 == 0) begin
                send_byte(8'hFF); send_byte(8'h00); send_byte(8'h00);
            end else if (p % 3 == 1) begin
                send_byte(8'h00); send_byte(8'hFF); send_byte(8'h00);
            end else begin
                send_byte(8'h00); send_byte(8'h00); send_byte(8'hFF);
            end
        end

        // No OP_EXECUTE needed — auto-triggers at DEPTH=10
        wait_for_results(10, 5000000);

        // =================================================================
        // PHASE 3: 4-pixel partial chunk (Green, Green, Blue, Red)
        //          Explicit OP_EXECUTE
        // =================================================================
        $display("");
        $display("=================================================");
        $display("  PHASE 3: 4 Pixels (G, G, B, R) partial chunk");
        $display("=================================================");

        expected[0] = 2'd1; // Green
        expected[1] = 2'd1; // Green
        expected[2] = 2'd2; // Blue
        expected[3] = 2'd0; // Red
        expected_len = 4;
        expected_idx = 0;
        result_count = 0;

        send_byte(8'hAA);  // OP_LOAD

        send_byte(8'h00); send_byte(8'hFF); send_byte(8'h00); // Green
        send_byte(8'h00); send_byte(8'hFF); send_byte(8'h00); // Green
        send_byte(8'h00); send_byte(8'h00); send_byte(8'hFF); // Blue
        send_byte(8'hFF); send_byte(8'h00); send_byte(8'h00); // Red

        send_byte(8'hBB);  // OP_EXECUTE

        wait_for_results(4, 2000000);

        // =================================================================
        // PHASE 4: Edge case — OP_EXECUTE with no pixels
        //          Should be a no-op (no results transmitted)
        // =================================================================
        $display("");
        $display("=================================================");
        $display("  PHASE 4: OP_EXECUTE with no pixels (edge case)");
        $display("=================================================");

        expected_len = 0;
        expected_idx = 0;
        result_count = 0;

        send_byte(8'hBB);  // OP_EXECUTE with nothing loaded

        // Wait a bit — no results should arrive
        #500000;

        if (result_count == 0) begin
            $display("[PASS] No spurious results from empty OP_EXECUTE");
        end else begin
            $display("[FAIL] Got %0d spurious results from empty OP_EXECUTE", result_count);
            error_count = error_count + result_count;
        end

        // After the no-op, verify the FSM is still functional by sending
        // one more chunk:
        $display("");
        $display("=================================================");
        $display("  PHASE 5: Post-noop sanity check (1 pixel)");
        $display("=================================================");

        expected[0] = 2'd2; // Blue
        expected_len = 1;
        expected_idx = 0;
        result_count = 0;

        send_byte(8'hAA);
        send_byte(8'h00); send_byte(8'h00); send_byte(8'hFF);
        send_byte(8'hBB);

        wait_for_results(1, 2000000);

        // =================================================================
        // FINAL SUMMARY
        // =================================================================
        $display("");
        $display("========================================");
        if (error_count == 0) begin
            $display("  ALL TESTS PASSED! (0 Errors)");
        end else begin
            $display("  SIMULATION FAILED WITH %0d ERRORS.", error_count);
        end
        $display("========================================");

        #10000;
        $finish;
    end

endmodule
