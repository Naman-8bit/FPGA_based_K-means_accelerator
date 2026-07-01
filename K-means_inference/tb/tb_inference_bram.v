`timescale 1ns / 1ps

// this is a dummy testbench with majority of work done in monitors to debug the output incase of a bug being found

module tb_inference_bram();

    reg clk;
    reg rx_pin;
    wire tx_pin;
    wire [5:0] led;

    inference_bram #(
        .DEPTH(10)
    ) uut (
        .clk(clk),
        .rx_pin(rx_pin),
        .tx_pin(tx_pin),
        .led(led)
    );

    // VCD dump
    initial begin
        $dumpfile("tb_inference_bram.vcd");
        $dumpvars(0, tb_inference_bram);
    end

    // Clock
    initial begin
        clk = 0;
        forever #18.5 clk = ~clk;
    end

    // BRAM write monitor — top level, NOT inside any initial block
    always @(posedge clk) begin
        if (uut.we_tx) begin
            $display("Time=%0t | BRAM WRITE | addr=%0d | data=%0d",
                     $time,
                     uut.result_addr,
                     uut.din_comp);
        end
    end
    always @(posedge clk) begin
        if (uut.we_tx) begin
            $display("Time=%0t | BRAM WRITE | addr=%0d | data=%0d | read_addr=%0d | pixel_count=%0d",
                    $time,
                    uut.result_addr,
                    uut.din_comp,
                    uut.read_addr,
                    uut.pixel_count);
        end
    end
    always @(posedge clk) begin
        if (uut.state == 4'd7) begin  // Proc_Write
            $display("Time=%0t | PROC_WRITE | read_addr=%0d | result_addr=%0d | pixel_count=%0d | winning=%0d",
                    $time,
                    uut.read_addr,
                    uut.result_addr,
                    uut.pixel_count,
                    uut.winning_cluster);
        end
    end
    always @(posedge clk) begin
        if (uut.state == 4'd5) begin  // Proc_Addr
            $display("Time=%0t | PROC_ADDR | read_addr=%0d | bram_rx_addr=%0d",
                    $time,
                    uut.read_addr,
                    uut.bram_rx_addr);
        end
        if (uut.state == 4'd6) begin  // Proc_Wait
            $display("Time=%0t | PROC_WAIT | pixel_out=%h | px_r=%h px_g=%h px_b=%h",
                    $time,
                    uut.pixel_out,
                    uut.px_r, uut.px_g, uut.px_b);
        end
    end
    always @(posedge clk) begin
        if (uut.state == 4'd4) begin  // Write_BRAM
            $display("Time=%0t | WRITE_BRAM | bram_addr=%0d | din=%h | write_addr=%0d",
                    $time,
                    uut.bram_rx_addr,
                    uut.din_rx,
                    uut.write_addr);
        end
    end
    always @(posedge clk) begin
        if (uut.state == 4'd1 && uut.rx_ready) // Rec_R catching a byte
            $display("Time=%0t | REC_R caught: %h", $time, uut.rx_byte);
        if (uut.state == 4'd2 && uut.rx_ready) // Rec_G
            $display("Time=%0t | REC_G caught: %h", $time, uut.rx_byte);
        if (uut.state == 4'd3 && uut.rx_ready) // Rec_B
            $display("Time=%0t | REC_B caught: %h", $time, uut.rx_byte);
    end
    // Memory readback — separate initial block, top level
    initial begin
        @(posedge uut.tx_start);
        #100;
        $display("=== BRAM CONTENTS AFTER PROCESSING ===");
        $display("addr[0] = %0d", uut.bram_tx.memory[0]);
        $display("addr[1] = %0d", uut.bram_tx.memory[1]);
        $display("addr[2] = %0d", uut.bram_tx.memory[2]);
        $display("=======================================");
    end

    localparam BIT_PERIOD = 8680;

    task send_byte;
        input [7:0] data;
        integer i;
        begin
            rx_pin = 0;
            #(BIT_PERIOD);
            for (i = 0; i < 8; i = i + 1) begin
                rx_pin = data[i];
                #(BIT_PERIOD);
            end
            rx_pin = 1;
            #(BIT_PERIOD);
            #(BIT_PERIOD);
        end
    endtask

    // Main test sequence
    initial begin
        rx_pin = 1;
        #100000;

        $display("--- STARTING TRANSMISSION ---");

        $display("Sending OP_LOAD (0xAA)...");
        send_byte(8'hAA);

        $display("Sending Pixel 1 (Red)...");
        send_byte(8'hFF);
        send_byte(8'h00);
        send_byte(8'h00);

        $display("Sending Pixel 2 (Green)...");
        send_byte(8'h00);
        send_byte(8'hFF);
        send_byte(8'h00);

        $display("Sending Pixel 3 (Blue)...");
        send_byte(8'h00);
        send_byte(8'h00);
        send_byte(8'hFF);

        $display("Sending Execute Opcode (0xBB)...");
        send_byte(8'hBB);

        $display("--- WAITING FOR FPGA TO COMPUTE AND REPLY ---");
        #500000;

        $display("--- TEST COMPLETE ---");
        $finish;
    end

    // Result monitor
    reg [7:0] fpga_result;
    integer j;

    initial begin
        forever begin
            @(negedge tx_pin);
            #(BIT_PERIOD / 2);
            if (tx_pin == 0) begin
                #(BIT_PERIOD);
                for (j = 0; j < 8; j = j + 1) begin
                    fpga_result[j] = tx_pin;
                    #(BIT_PERIOD);
                end
                $display("Time=%0t | Cluster %0d (raw=%08b)",
                         $time, fpga_result[1:0], fpga_result);
            end
        end
    end

endmodule