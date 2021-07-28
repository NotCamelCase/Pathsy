module bram_shift_register
#
(
    parameter   WIDTH   = 8,
    parameter   DELAY_COUNT = 4
)
(
    input logic             clk,
    input logic             reset, // synchronous reset, active-high
    input logic[WIDTH-1:0]  d,
    output logic[WIDTH-1:0] q
);
    localparam  DEPTH_WIDTH = $clog2(DELAY_COUNT);

    logic[DEPTH_WIDTH-1:0]  wr_ptr;

    bram_1r1w #(.ADDR_WIDTH(DEPTH_WIDTH), .DATA_WIDTH(WIDTH)) buffer(
        .clk(clk),
        .wr_en(1'b1),
        .rd_addr(wr_ptr),
        .wr_addr(wr_ptr),
        .wr_data(d),
        .rd_data(q));

    always_ff @(posedge clk)
    begin
        if (reset)
            wr_ptr <= 0;
        else
            wr_ptr <= (wr_ptr == DELAY_COUNT-2) ? 0 : wr_ptr + 1;
    end
endmodule