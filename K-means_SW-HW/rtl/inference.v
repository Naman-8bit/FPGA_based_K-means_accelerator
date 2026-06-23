`timescale 1ns / 1ps

// note debugging
// case of false positive occured where tx_state was not initialised it worked for the simulation but didnt work on fpga
// always look out and check in the waveform to see if any core signal doesnt go uninitialised or gives X

module inference (
    input  wire clk,      // 27 MHz clock 
    input  wire rx_pin,   // UART RX PIN
    output wire tx_pin,   // UART TX PIN
    output wire [5:0] led // debugging
);

    // so right now this is a inference model that only classify with given centroid then will be building the same for dynamic centroids
    localparam [7:0] C1_R = 8'hFF, C1_G = 8'h00, C1_B = 8'h00; // Centroid 1: Red
    localparam [7:0] C2_R = 8'h00, C2_G = 8'hFF, C2_B = 8'h00; // Centroid 2: Green
    localparam [7:0] C3_R = 8'h00, C3_G = 8'h00, C3_B = 8'hFF; // Centroid 3: Blue
    // basically we will classify the incoming pixels into R or G or B

    // uart wires
    wire[7:0] rx_byte;
    wire rx_ready;
    reg tx_start = 0;
    reg[7:0] tx_byte  = 0;
    wire tx_busy;

    //recieved pixels
    reg [7:0] R = 0;
    reg [7:0] G = 0;
    reg [7:0] B = 0;

    wire[1:0] winning_cluster;

    // core logic starts here
    wire[17:0] dis1;
    wire[17:0] dis2;
    wire[17:0] dis3;

    uart_rx rx (.clk(clk), .rx_pin(rx_pin), .rx_byte(rx_byte), .rx_ready(rx_ready));
    uart_tx tx (.clk(clk), .tx_start(tx_start), .tx_byte(tx_byte), .tx_busy(tx_busy), .tx_pin(tx_pin));

    distance_core d1(.sq_distance(dis1), .pixel_r(R) , .pixel_b(B) , .pixel_g(G) , .centroid_r(C1_R), .centroid_b(C1_B) , .centroid_g(C1_G));
    distance_core d2(.sq_distance(dis2), .pixel_r(R) , .pixel_b(B) , .pixel_g(G) , .centroid_r(C2_R), .centroid_b(C2_B) , .centroid_g(C2_G));
    distance_core d3(.sq_distance(dis3), .pixel_r(R) , .pixel_b(B) , .pixel_g(G) , .centroid_r(C3_R), .centroid_b(C3_B) , .centroid_g(C3_G));

    comparator_unit comp(.cluster_id(winning_cluster) , .dist_0(dis1) , .dist_1(dis2) , .dist_2(dis3));

    // fsm states
    localparam[2:0]
    Wait_R = 0,
    Wait_G = 1,
    Wait_B = 2,
    Compute = 3,
    Transmit = 4;

    reg[2:0] tx_state;

    always @(posedge clk) begin
        tx_start<=0;
        case (tx_state)
            Wait_R : begin
                if(rx_ready) begin
                    R<=rx_byte;
                    tx_state<=Wait_G;
                end
            end
            Wait_G : begin
                if(rx_ready) begin
                    G<=rx_byte;
                    tx_state<=Wait_B;
                end
            end
            Wait_B : begin
                if(rx_ready) begin
                    B<=rx_byte;
                    tx_state<=Compute;
                end
            end
            Compute : begin
                tx_byte<={6'd0,winning_cluster};
                tx_state<=Transmit;
            end
            Transmit : begin
                if (!tx_busy) begin
                    tx_start <= 1'b1;  
                    tx_state<= Wait_R; 
                end
            end
            default : tx_state = 2'b00;
        endcase
    end

    assign led = ~{4'b0000, winning_cluster};

endmodule