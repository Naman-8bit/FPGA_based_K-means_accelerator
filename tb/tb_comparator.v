`timescale 1ns / 1ps

module tb_comparator();

    reg  [17:0] d0, d1, d2;
    wire [1:0]  id;
    integer errors = 0;

    comparator_unit uut (
        .dist_0(d0),
        .dist_1(d1),
        .dist_2(d2),
        .cluster_id(id)
    );

    task check_min;
        input [17:0] in0, in1, in2;
        input [1:0] expected;
        begin
            d0 = in0; d1 = in1; d2 = in2;
            #10; // Wait for logic to settle
            
            if (id !== expected) begin
                $display("❌ FAIL | Distances: %0d, %0d, %0d | Expected ID: %0d, Got: %0d",
                         in0, in1, in2, expected, id);
                errors = errors + 1;
            end else begin
                $display("✅ PASS | Distances: %0d, %0d, %0d | Winner ID: %0d",
                         in0, in1, in2, id);
            end
        end
    endtask

    initial begin
        $display("========================================");
        $display("   Starting Comparator Testbench        ");
        $display("========================================");

        // Test 1: Centroid 0 is the clear winner
        check_min(18'd10,   18'd50,   18'd100,  2'b00);

        // Test 2: Centroid 1 is the clear winner
        check_min(18'd500,  18'd20,   18'd300,  2'b01);

        // Test 3: Centroid 2 is the clear winner
        check_min(18'd9000, 18'd8000, 18'd1000, 2'b10);

        // Test 4: Tie between 0 and 1 (Should default to 0)
        check_min(18'd50,   18'd50,   18'd100,  2'b00);

        // Test 5: Tie between 1 and 2 (Should default to 1)
        check_min(18'd900,  18'd45,   18'd45,   2'b01);

        // Test 6: Massive absolute numbers
        check_min(18'd195000, 18'd194999, 18'd195075, 2'b01);

        $display("========================================");
        if (errors == 0)
            $display("🎉 ALL TESTS PASSED! Combinational Datapath Complete.");
        else
            $display("⚠️ SIMULATION FINISHED WITH %0d ERRORS.", errors);
        $display("========================================");
        $finish;
    end
endmodule