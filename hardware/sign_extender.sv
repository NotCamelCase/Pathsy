module sign_extender
#
(
    parameter   PRE_WIDTH   = 8,
    parameter   POST_WIDTH  = 16 
)
(
    input logic[PRE_WIDTH-1:0]      i,
    output logic[POST_WIDTH-1:0]    o
);
    assign o = {{POST_WIDTH-PRE_WIDTH{i[PRE_WIDTH-1]}}, i};
endmodule
