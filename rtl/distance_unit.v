module distance_core (
    // rgb values of the inputed pixel
    input  wire[7:0] pixel_r,
    input  wire[7:0] pixel_g,
    input  wire[7:0] pixel_b,

    // 8-bit rgb values of the target centroid
    input  wire[7:0] centroid_r,
    input  wire[7:0] centroid_g,
    input  wire[7:0] centroid_b,

    // the 18-bit squared distance result
    // (18 bits is required because 3 * (255^2) = 195,075, which takes 18 bits)
    output wire[17:0] sq_distance
);
    // this is the backbone of the project this will be used to find the distances
    // more than one such module will be instantiated to make use of parallel computation
    // all of the work will be done on the square of the distances instead of sq root as sq root module is expensive of hardware

    // this is just calculation in 3d D2 = (PR-CR)2 + (PG-CG)2 + (PB-CB)2
    // temp wires
    wire[17:0] Sr;
    wire[17:0] Sb;
    wire[17:0] Sg;

    assign Sr= ((pixel_r-centroid_r)*(pixel_r-centroid_r)) ;
    assign Sb= ((pixel_b-centroid_b)*(pixel_b-centroid_b)) ;
    assign Sg= ((pixel_g-centroid_g)*(pixel_g-centroid_g)) ;

    assign sq_distance= Sr+Sb+Sg;

endmodule