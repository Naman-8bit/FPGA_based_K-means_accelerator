`timescale 1ns / 1ps

module tb_dist_unit();
    reg  [7:0] p_r, p_g, p_b;
    reg  [7:0] c_r, c_g, c_b;
    wire [17:0] sq_dist;
    
    integer errors = 0; // Track failures


    distance_core uut (
        .pixel_r(p_r),     .pixel_g(p_g),     .pixel_b(p_b),
        .centroid_r(c_r),  .centroid_g(c_g),  .centroid_b(c_b),
        .sq_distance(sq_dist)
    );

    task check_distance;
        input [7:0] pr, pg, pb;
        input [7:0] cr, cg, cb;
        input [17:0] expected;
        begin
            // Apply the inputs
            p_r = pr; p_g = pg; p_b = pb;
            c_r = cr; c_g = cg; c_b = cb;
            
            // Wait 10 nanoseconds for the combinational logic to settle
            #10; 
            
            // Compare the module's output against our expected math
            if (sq_dist !== expected) begin
                $display("❌ FAIL | P(%0d,%0d,%0d) C(%0d,%0d,%0d) | Expected: %0d, Got: %0d", 
                          pr, pg, pb, cr, cg, cb, expected, sq_dist);
                errors = errors + 1;
            end else begin
                $display("✅ PASS | P(%0d,%0d,%0d) C(%0d,%0d,%0d) | Distance: %0d", 
                          pr, pg, pb, cr, cg, cb, sq_dist);
            end
        end
    endtask

    // 4. Run the Test Sequence
    initial begin
        $display("========================================");
        $display("   Starting Distance Unit Testbench     ");
        $display("========================================");

        check_distance(8'd100, 8'd100, 8'd100,   8'd100, 8'd100, 8'd100,   18'd0);
        check_distance(8'd10,  8'd10,  8'd10,    8'd5,   8'd5,   8'd5,     18'd75);
        check_distance(8'd5,   8'd5,   8'd5,     8'd10,  8'd10,  8'd10,    18'd75);
        check_distance(8'd255, 8'd255, 8'd255,   8'd0,   8'd0,   8'd0,     18'd195075);
        check_distance(8'd100, 8'd50,  8'd200,   8'd150, 8'd50,  8'd100,   18'd12500);
        // edge cases
        check_distance(8'd255, 8'd0,   8'd0,     8'd0,   8'd0,   8'd0,     18'd65025);
        check_distance(8'd0,   8'd0,   8'd0,     8'd0,   8'd255, 8'd0,     18'd65025);
        check_distance(8'd255, 8'd0,   8'd255,   8'd0,   8'd255, 8'd0,     18'd195075);
        check_distance(8'd127, 8'd127, 8'd127,   8'd128, 8'd128, 8'd128,   18'd3);
        check_distance(8'd12,  8'd234, 8'd88,    8'd100, 8'd45,  8'd200,   18'd56009);

        $display("========================================");
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("⚠️ SIMULATION FINISHED WITH %0d ERRORS.", errors);
        $display("========================================");
        
        $finish; // End the simulation
    end

endmodule