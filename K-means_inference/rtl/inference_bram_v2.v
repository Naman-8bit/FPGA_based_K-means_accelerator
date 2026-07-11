`timescale 1ns / 1ps
//
// FIX FOR THE "OPCODE IN PIXEL DATA" BUG:
// In previous versions, the FSM checked for OP_EXECUTE during the REC_R state.
// If any image pixel had a Red value of 0xBB (187), the FSM falsely interpreted
// it as an opcode, stopped receiving, and started computing early. This caused
// the FPGA to send back fewer bytes than Python expected, leading to a timeout!
//
// PROTOCOL v2 (Length-prefixed):
//   1. Host sends OP_LOAD (0xAA)
//   2. Host sends High byte of pixel count
//   3. Host sends Low byte of pixel count (N)
//   4. Host streams exactly N pixels (3 bytes each: R, G, B)
//   5. FPGA processes all N pixels without ever checking for opcodes inside data
//   6. FPGA streams back exactly N result bytes
//   7. FSM returns to IDLE
// the length protocol is inspired from the standard solutions to common problem called IN BAND SIGNALLING and used in protocols like 
// cameras SPI USB etc
module inference_bram_v2 #(
    parameter DEPTH      = 8192,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input  wire        clk,       // 27 MHz system clock
    input  wire        rx_pin,    // UART RX from host
    output wire        tx_pin,    // UART TX to host
    output wire [5:0]  led        // Debug LEDs
);

    localparam [7:0] OP_LOAD = 8'hAA;

    // Centroids
    localparam [7:0] C1_R = 8'hFF, C1_G = 8'h00, C1_B = 8'h00; // Red
    localparam [7:0] C2_R = 8'h00, C2_G = 8'hFF, C2_B = 8'h00; // Green
    localparam [7:0] C3_R = 8'h00, C3_G = 8'h00, C3_B = 8'hFF; // Blue

    // UART
    wire [7:0] rx_byte;
    wire       rx_ready;
    reg        tx_start = 0;
    reg  [7:0] tx_byte  = 0;
    wire       tx_busy;

    uart_rx rx_inst (
        .clk(clk), .rx_pin(rx_pin),
        .rx_byte(rx_byte), .rx_ready(rx_ready)
    );
    uart_tx tx_inst (
        .clk(clk), .tx_start(tx_start), .tx_byte(tx_byte),
        .tx_busy(tx_busy), .tx_pin(tx_pin)
    );

    // =====================================================================
    // FSM STATE ENCODING
    // =====================================================================
    localparam [3:0]
        IDLE         = 4'd0,
        REC_LEN_H    = 4'd1,
        REC_LEN_L    = 4'd2,
        REC_R        = 4'd3,
        REC_G        = 4'd4,
        REC_B        = 4'd5,
        WRITE_PIXEL  = 4'd6,
        PROC_ISSUE   = 4'd7,
        PROC_LATCH   = 4'd8,
        PROC_STORE   = 4'd9,
        TX_SETTLE    = 4'd10,
        TX_ISSUE     = 4'd11,
        TX_LATCH     = 4'd12,
        TX_SEND      = 4'd13,
        TX_WAIT      = 4'd14;

    reg [3:0] state = IDLE;

    // Pixel staging
    reg [7:0] R = 0;
    reg [7:0] G = 0;
    reg [7:0] B = 0;

    // BRAMs
    reg                    px_we       = 0;
    reg  [ADDR_WIDTH-1:0]  px_wr_addr  = 0;
    reg  [23:0]            px_din      = 0;
    reg  [ADDR_WIDTH-1:0]  px_rd_addr  = 0;
    wire [23:0]            px_dout;

    bram24bit_v2 #(.DEPTH(DEPTH), .ADDR_WIDTH(ADDR_WIDTH)) pixel_bram (
        .clk(clk),
        .we(px_we),         .wr_addr(px_wr_addr), .din(px_din),
        .rd_addr(px_rd_addr), .dout(px_dout)
    );

    reg                    res_we      = 0;
    reg  [ADDR_WIDTH-1:0]  res_wr_addr = 0;
    reg  [7:0]             res_din     = 0;
    reg  [ADDR_WIDTH-1:0]  res_rd_addr = 0;
    wire [7:0]             res_dout;

    bram8bit_v2 #(.DEPTH(DEPTH), .ADDR_WIDTH(ADDR_WIDTH)) result_bram (
        .clk(clk),
        .we(res_we),         .wr_addr(res_wr_addr), .din(res_din),
        .rd_addr(res_rd_addr), .dout(res_dout)
    );

    // Math Core
    wire [7:0] px_r = px_dout[23:16];
    wire [7:0] px_g = px_dout[15:8];
    wire [7:0] px_b = px_dout[7:0];

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

    // Tracking
    reg [15:0] target_count = 0;
    reg [15:0] pixel_count  = 0;
    reg [15:0] proc_idx     = 0;
    reg [15:0] tx_ptr       = 0;

    // FSM
    always @(posedge clk) begin
        tx_start <= 0;
        px_we    <= 0;
        res_we   <= 0;

        case (state)
            IDLE: begin
                if (rx_ready && rx_byte == OP_LOAD) begin
                    px_wr_addr  <= 0;
                    pixel_count <= 0;
                    target_count<= 0;
                    state       <= REC_LEN_H;
                end
            end
            
            REC_LEN_H: begin
                if (rx_ready) begin
                    target_count[15:8] <= rx_byte;
                    state              <= REC_LEN_L;
                end
            end
            
            REC_LEN_L: begin
                if (rx_ready) begin
                    target_count[7:0] <= rx_byte;
                    
                    // Quick check: if host sent 0 length, just abort back to IDLE
                    if ({target_count[15:8], rx_byte} == 16'd0) begin
                        state <= IDLE;
                    end else begin
                        state <= REC_R;
                    end
                end
            end

            REC_R: begin
                if (rx_ready) begin
                    // NO OPCODE CHECKING HERE ANYMORE! Just pure data.
                    R     <= rx_byte;
                    state <= REC_G;
                end
            end

            REC_G: begin
                if (rx_ready) begin
                    G     <= rx_byte;
                    state <= REC_B;
                end
            end

            REC_B: begin
                if (rx_ready) begin
                    B     <= rx_byte;
                    px_din     <= {R, G, rx_byte};
                    px_wr_addr <= pixel_count[ADDR_WIDTH-1:0];
                    state      <= WRITE_PIXEL;
                end
            end

            WRITE_PIXEL: begin
                px_we       <= 1;
                pixel_count <= pixel_count + 1;

                if (pixel_count + 1 == target_count) begin
                    proc_idx   <= 0;
                    px_rd_addr <= 0;
                    state      <= PROC_ISSUE;
                end else begin
                    state <= REC_R;
                end
            end

            // --- PROCESS PHASE ---
            PROC_ISSUE: begin
                state <= PROC_LATCH;
            end

            PROC_LATCH: begin
                res_din     <= {6'b000000, winning_cluster};
                res_wr_addr <= proc_idx[ADDR_WIDTH-1:0];
                state       <= PROC_STORE;
            end

            PROC_STORE: begin
                res_we <= 1;
                if (proc_idx + 1 == pixel_count) begin
                    tx_ptr      <= 0;
                    res_rd_addr <= 0;
                    state       <= TX_SETTLE;
                end else begin
                    proc_idx   <= proc_idx + 1;
                    px_rd_addr <= proc_idx[ADDR_WIDTH-1:0] + 1;
                    state      <= PROC_ISSUE;
                end
            end

            // --- TRANSMIT PHASE ---
            TX_SETTLE: begin
                state <= TX_ISSUE;
            end

            TX_ISSUE: begin
                state <= TX_LATCH;
            end

            TX_LATCH: begin
                tx_byte <= res_dout;
                state   <= TX_SEND;
            end

            TX_SEND: begin
                if (!tx_busy) begin
                    tx_start <= 1;
                    state    <= TX_WAIT;
                end
            end

            TX_WAIT: begin
                if (!tx_busy) begin
                    if (tx_ptr + 1 == pixel_count) begin
                        px_wr_addr  <= 0;
                        pixel_count <= 0;
                        proc_idx    <= 0;
                        tx_ptr      <= 0;
                        state       <= IDLE;
                    end else begin
                        tx_ptr      <= tx_ptr + 1;
                        res_rd_addr <= tx_ptr[ADDR_WIDTH-1:0] + 1;
                        state       <= TX_ISSUE;
                    end
                end
            end

            default: state <= IDLE;
        endcase
    end

    assign led = ~{4'b0000, winning_cluster};

endmodule
