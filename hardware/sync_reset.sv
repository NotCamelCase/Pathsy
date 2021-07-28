module sync_reset
#(parameter N = 4) // # of FFs to debounce reset input
(
    input logic     clk,
    input logic     arst,   // Async reset, active-low
    output logic    rst     // Sync reset, active-high
);
    (* ASYNC_REG = "true" *)
    logic           async_rst_meta, async_rst_sync;

    logic[N-1:0]    rst_db;

    // Async reset bridge, active-low
    always_ff @(posedge clk, negedge arst)
    begin
        if (~arst)
        begin
            async_rst_meta <= 1'b0;
            async_rst_sync <= 1'b0;
        end
        else
        begin
            async_rst_meta <= 1'b1;
            async_rst_sync <= async_rst_meta;
        end
    end

    always_ff @(posedge clk)
    begin
        for (integer i = 0; i < N-1; i++)
            rst_db[i+1] <= rst_db[i];

        rst_db[0] <= ~async_rst_sync;
    end

    // Output synchronous active-high reset
    assign rst = &rst_db;
endmodule