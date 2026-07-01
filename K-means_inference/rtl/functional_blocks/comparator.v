module comparator_unit(
    // input squared obtained from the 3 distance units
    input wire[17:0] dist_0,
    input wire[17:0] dist_1,
    input wire[17:0] dist_2,

    // output is the cluster id
    output reg[1:0] cluster_id
);
    // this compared the distances squared obtained from the 3 units (can be scaled easily)
    // since this is a simple implementation with less to compare a combinational simple block works 
    // when working with more centroids research papers suggest to use a tournament tree to make it faster clock cycle wise(will do comparision over several clocks)
    // also in the higher centroid count recommended to use the traingular inequality and stuff to make it simpler

    // incase of tie default assigning lower numbered cluster
    always @(*) begin
        if(dist_0<=dist_1)begin
            if(dist_0<=dist_2) cluster_id = 2'b00;
            else cluster_id=2'b10;
        end else begin
            if(dist_1<=dist_2) cluster_id = 2'b01;
            else cluster_id=2'b10;
        end
    end
    
endmodule