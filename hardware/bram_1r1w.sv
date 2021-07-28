module bram_1r1w
#
(
    parameter   ADDR_WIDTH = 4,
    parameter   DATA_WIDTH = 8
)
(
    input logic                     clk,
    input logic                     wr_en,
    input logic[ADDR_WIDTH-1:0]     rd_addr, wr_addr,
    input logic[DATA_WIDTH-1:0]     wr_data,
    output logic[DATA_WIDTH-1:0]    rd_data
);
    logic[DATA_WIDTH-1:0]   buffer[2**ADDR_WIDTH-1:0];
    logic[DATA_WIDTH-1:0]   data_reg;

    // Write port
    always_ff @(posedge clk)
    begin
        if (wr_en)
            buffer[wr_addr] <= wr_data;
    end

    // Read port
    always_ff @(posedge clk)
    begin
        data_reg <= buffer[rd_addr];
    end

    assign rd_data = data_reg;
endmodule