module debounce_button
#(parameter CTR_WIDTH = 24)
(
    input logic     clk,
    input logic     pb,
    output logic    pb_down
);
    (* ASYNC_REG = "true" *)
    logic                   input_meta, input_sync;

    logic                   input_idle, count_up;
    logic                   pb_reg;
    logic[CTR_WIDTH-1:0]    ctr_reg;

    always_ff @(posedge clk)
    begin
        input_meta <= pb;
        input_sync <= input_meta;
    end

    assign input_idle = (pb_reg == input_sync);
    assign count_up = &ctr_reg;

    always_ff @(posedge clk) ctr_reg <= input_idle ? 0 : ctr_reg + CTR_WIDTH'(1);

    always_ff @(posedge clk) pb_reg <= count_up ? ~pb_reg : pb_reg;

    assign pb_down = count_up & ~input_idle & ~pb_reg;
endmodule