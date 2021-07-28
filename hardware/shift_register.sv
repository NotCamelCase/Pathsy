module shift_register
#
(
    parameter WIDTH         = 1,    // delayed register width
    parameter DELAY_COUNT   = 3     // number of clocks to delay a register
)
(
    input logic             clk,
    input logic[WIDTH-1:0]  d,
    output logic[WIDTH-1:0] q 
);
    logic[WIDTH-1:0]   q_reg[DELAY_COUNT-1:0];

    always_ff @(posedge clk)
    begin
        for (integer i = 0; i < DELAY_COUNT-1; i=i+1)
            q_reg[i + 1] <= q_reg[i];

        q_reg[0] <= d;
    end

    assign q = q_reg[DELAY_COUNT-1];
endmodule