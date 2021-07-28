`include "defines.svh"

module generate_primary_rays_stage
(
    input logic                     clk, rst,
    input logic                     start,
    // Pixel coordinates
    input logic[`PX_WIDTH-1:0]      x,
    input logic[`PY_WIDTH-1:0]      y,
    output logic                    busy,
    // prim_ray is valid to be written
    output logic                    ray_wr_en,
    // Ray index at which prim_ray will be stored
    output logic[`RPP_WIDTH-1:0]    ray_ndx,
    // Generated primary ray
    output ray_t                    prim_ray
);
    // Control/status signals
    logic                   busy_reg, busy_nxt;

    // Loop counter
    logic[`RPP_WIDTH:0]     ray_ctr_reg, ray_ctr_nxt;

    // rayIdx
    logic[`RPP_WIDTH-1:0]   ray_ndx_reg, ray_ndx_nxt;

    // ray_gen
    logic                   ray_gen_op_vld;
    logic                   ray_gen_result_vld;

    // Registers
    always_ff @(posedge clk)
    begin
        if (rst)
        begin
            busy_reg <= 1'b0;
        end
        else
        begin
            busy_reg <= busy_nxt;
            ray_ctr_reg <= ray_ctr_nxt;
            ray_ndx_reg <= ray_ndx_nxt;
        end
    end

    // Control path
    always_comb
    begin
        busy_nxt = busy_reg;
        
        ray_ctr_nxt = ray_ctr_reg;
        ray_ndx_nxt = ray_ndx_reg;

        ray_gen_op_vld = 1'b0;

        if (start)
        begin
            // New request, initialize the index and loop counter and begin rays generation
            ray_ctr_nxt = {`RPP_WIDTH+1{1'b0}};
            ray_ndx_nxt = {`RPP_WIDTH{1'b0}};
            busy_nxt = 1'b1;
        end
        else if (busy_reg)
        begin
            // Issue a new ray gen for RPP iterations
            ray_gen_op_vld = (ray_ctr_reg < `RPP);

            ray_ctr_nxt = ray_gen_op_vld ? (ray_ctr_reg + 1) : ray_ctr_reg;
            ray_ndx_nxt = ray_gen_result_vld ? (ray_ndx_reg + 1) : ray_ndx_reg;

            // Done if RPP primary rays were generated
            if (ray_ndx_reg == `RPP-1)
                busy_nxt = 1'b0;
        end
    end

    ray_gen ray_gen_unit(
        .clk(clk),
        .op_vld(ray_gen_op_vld),
        .x(x),
        .y(y),
        .s(ray_ctr_reg[`RPP_WIDTH-1:0]),
        .result_vld(ray_gen_result_vld),
        .ray(prim_ray));

    // Outputs
    assign busy = busy_reg;
    assign ray_wr_en = ray_gen_result_vld;
    assign ray_ndx = ray_ndx_reg;
endmodule