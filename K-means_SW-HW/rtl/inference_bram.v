`timescale 1ns / 1ps

// the biggest challenge here was the bram overflow condition
// now problem was if bram overflowed one way was to say to python that stop working if it recieves status full from fpga
// but that would lead to two things : one it is slow since uart_tx is slow (234 clk cycles) and even worse python will be able to send a pixel that will not be recieved thus data lost
// it was extremely difficult to solely resolve this issue on hardware simply cause of slow uart and fast math core

// so instead it better that i chunk the data in python itself make sure it doesnt send more that bram size in one go and wait to recieve data before sending again
// this effectively made sure overflow didnt require communication bw python and fpga 

// NIGHTMARE in debugging: racing around and latency
//  since inside the fsm states due to non blocking assignments there were several bugs coming cause of thinking that the changes were sequential
// bram needed one full clock cycle to transmit data which i didnt took in consideration giving me stupid outputs
// bram_wait now needs two clock cycles to work
// added a seperate state Write_inc to isolate write_addr and let the mux do its job properly
module inference_bram #(
    parameter DEPTH      = 10000,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input  wire clk,
    input  wire rx_pin,
    output wire tx_pin,
    output wire [5:0] led
);

    // OPCODES — host sends these to tell the FSM what to do
    localparam [7:0] OP_LOAD    = 8'hAA; // start streaming pixels
    localparam [7:0] OP_EXECUTE = 8'hBB; // run inference on loaded pixels
    
    // CENTROIDS - preset for testing to R G AND B
    localparam [7:0] C1_R = 8'hFF, C1_G = 8'h00, C1_B = 8'h00;
    localparam [7:0] C2_R = 8'h00, C2_G = 8'hFF, C2_B = 8'h00;
    localparam [7:0] C3_R = 8'h00, C3_G = 8'h00, C3_B = 8'hFF;

    // UART
    wire [7:0] rx_byte;
    wire       rx_ready;
    reg        tx_start = 0;
    reg  [7:0] tx_byte  = 0;
    wire       tx_busy;

    uart_rx rx_inst (
        .clk(clk), .rx_pin(rx_pin), .rx_byte(rx_byte), .rx_ready(rx_ready)
    );
    uart_tx tx_inst (
        .clk(clk), .tx_start(tx_start), .tx_byte(tx_byte), .tx_busy(tx_busy), .tx_pin(tx_pin)
    );
    
    // PIXEL STAGING REGISTERS (R, G, B latched from UART)
    reg [7:0] R = 0;
    reg [7:0] G = 0;
    reg [7:0] B = 0;

    // =========================================================
    // FSM STATE ENCODING 
    // =========================================================
    localparam [3:0]
        IDLE       = 4'd0,
        Rec_R      = 4'd1,
        Rec_G      = 4'd2,
        Rec_B      = 4'd3,
        Write_BRAM = 4'd4,
        Write_Inc  = 4'd9,  // ISOLATION STATE 1
        Proc_Addr  = 4'd5,
        Proc_Wait  = 4'd6,
        Proc_Write = 4'd7,
        Proc_Next  = 4'd10, // ISOLATION STATE 2
        Transmit   = 4'd8;

    reg [3:0] state = IDLE;

    // BRAM 24-BIT (pixel storage)
    reg         we_rx  = 0;
    reg  [23:0] din_rx = 0;
    wire [23:0] pixel_out; // registered output — valid ONE cycle after addr

    // address mux: write_addr during load phase, read_addr during process phase for the 24 bit bram
    reg  [ADDR_WIDTH-1:0] write_addr = 0;
    reg  [ADDR_WIDTH-1:0] read_addr  = 0;
    wire [ADDR_WIDTH-1:0] bram_rx_addr;

    // mux — FSM controls which address goes to the pixel BRAM
    assign bram_rx_addr = (state == Write_BRAM || state == Write_Inc) ? write_addr : read_addr;

    bram_24bit #(.DEPTH(DEPTH), .ADDR_WIDTH(ADDR_WIDTH)) bram_rx (
        .clk(clk),
        .we(we_rx),
        .addr(bram_rx_addr),
        .din(din_rx),
        .dout(pixel_out)
    );

    // BRAM 8-BIT (result storage)
    reg                   we_tx       = 0;
    reg  [7:0]            din_comp    = 0;
    wire [7:0]            dout_tx;            // result byte out (for UART transmit phase)
    reg  [ADDR_WIDTH-1:0] result_addr = 0;    // write address during process phase
    reg  [ADDR_WIDTH-1:0] tx_ptr      = 0;    // read address during transmit phase
    reg  [1:0]            bram_wait   = 0;    // <-- FIXED: Now 2 bits wide to allow counting to 2!

    bram_8bit #(.DEPTH(DEPTH), .ADDR_WIDTH(ADDR_WIDTH)) bram_tx (
        .clk(clk),
        .we(we_tx),
        .addr(result_addr),
        .din(din_comp),
        .dout(dout_tx)
    );

    // MATH CORE (combinational — always live, always computing)
    wire [7:0] px_r = pixel_out[23:16];
    wire [7:0] px_g = pixel_out[15:8];
    wire [7:0] px_b = pixel_out[7:0];

    wire [17:0] dis1, dis2, dis3;
    wire [1:0]  winning_cluster;

    distance_core d1 (
        .sq_distance(dis1),
        .pixel_r(px_r), .pixel_g(px_g), .pixel_b(px_b),
        .centroid_r(C1_R), .centroid_g(C1_G), .centroid_b(C1_B)
    );
    distance_core d2 (
        .sq_distance(dis2),
        .pixel_r(px_r), .pixel_g(px_g), .pixel_b(px_b),
        .centroid_r(C2_R), .centroid_g(C2_G), .centroid_b(C2_B)
    );
    distance_core d3 (
        .sq_distance(dis3),
        .pixel_r(px_r), .pixel_g(px_g), .pixel_b(px_b),
        .centroid_r(C3_R), .centroid_g(C3_G), .centroid_b(C3_B)
    );

    comparator_unit comp (
        .cluster_id(winning_cluster),
        .dist_0(dis1), .dist_1(dis2), .dist_2(dis3)
    );

    // PIXEL COUNT — snapshotted when 0xBB arrives
    reg [ADDR_WIDTH-1:0] pixel_count = 0;

    // FSM — Core control logic
    always @(posedge clk) begin
        // --- DEFAULTS ---
        tx_start <= 0;
        we_rx    <= 0;
        we_tx    <= 0;

        case (state)
            IDLE: begin 
                if(rx_ready) begin
                    case(rx_byte) 
                        OP_LOAD: state <= Rec_R;
                        OP_EXECUTE: begin
                            state <= Proc_Addr;
                        end
                    endcase
                end
            end
            
            Rec_R: begin 
                if(rx_ready) begin
                    if (rx_byte == OP_EXECUTE) begin
                        state <= Proc_Addr;  // Start computing (partial chunk trigger)
                    end else begin
                        R     <= rx_byte;    // Normal pixel byte
                        state <= Rec_G;
                    end
                end
            end
            
            Rec_G: begin 
                if(rx_ready) begin
                    G     <= rx_byte;
                    state <= Rec_B;
                end
            end
            
            Rec_B: begin 
                if(rx_ready) begin
                    B      <= rx_byte;
                    din_rx <= {R, G, rx_byte};
                    state  <= Write_BRAM;
                end
            end
            
            Write_BRAM: begin 
                we_rx <= 1;          // Assert Write Enable
                state <= Write_Inc;  // Move to isolation state
            end
            
            Write_Inc: begin
                we_rx       <= 0;    // Safely deassert Write Enable
                write_addr  <= write_addr + 1;
                pixel_count <= write_addr + 1;

                // AUTO-TRIGGER: if depth is reached
                if (write_addr + 1 >= DEPTH) begin
                    state <= Proc_Addr; // Start computing instantly!
                end else begin
                    state <= Rec_R;     // Keep receiving pixels
                end
            end
            
            Proc_Addr: begin 
                result_addr <= result_addr; // Hold steady
                state       <= Proc_Wait;
            end
            
            Proc_Wait: begin 
                state <= Proc_Write;
            end
            
            Proc_Write: begin 
                we_tx    <= 1;          // Assert Write Enable for TX BRAM
                din_comp <= {6'b000000, winning_cluster}; 
                state    <= Proc_Next;  // Move to isolation state
            end
            
            Proc_Next: begin
                we_tx       <= 0;       // Safely deassert Write Enable
                read_addr   <= read_addr + 1;
                result_addr <= result_addr + 1;

                // Check if we just processed the final pixel in our chunk
                if (read_addr + 1 == pixel_count) begin
                    state <= Transmit;
                end else begin
                    state <= Proc_Addr; // Loop back and grab the next pixel
                end
            end
            
            Transmit: begin 
                result_addr <= tx_ptr; 
                
                if (!tx_busy) begin
                    // Wait for 2 clock cycles: 
                    // 1 cycle for result_addr to update + 1 cycle for BRAM read latency
                    if (bram_wait == 2'd2) begin
                        tx_byte   <= dout_tx;
                        tx_start  <= 1;       
                        bram_wait <= 0;       // Reset wait counter
                        
                        if (tx_ptr + 1 == pixel_count) begin
                            write_addr  <= 0;
                            read_addr   <= 0;
                            result_addr <= 0;
                            tx_ptr      <= 0;
                            state       <= IDLE;
                        end else begin
                            tx_ptr <= tx_ptr + 1; 
                        end
                    end else begin
                        bram_wait <= bram_wait + 1; // Increment the wait counter
                    end
                end
            end
            
            default: state <= IDLE;
        endcase
    end

    assign led = ~{4'b0000, winning_cluster};

endmodule