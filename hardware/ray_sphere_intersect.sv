`include "defines.svh"

module ray_sphere_intersect
(
    input logic     clk,
    input logic     op_vld,
    input ray_t     ray,        // ray
    input vec3_t    center,     // sphere center
    input fp32_t    radius_2,   // sphere radius squared
    output logic    result_vld,
    output fp32_t   t0,         // hit result t0
    output fp32_t   t1          // hit result t1
);
    localparam  DLY_B_COUNT     = `LATENCY_FP32_MULTIPLIER + `LATENCY_FP32_ADDER + `LATENCY_FP32_SQRT;
    localparam  DLY_C_COUNT     = `LATENCY_FP32_MULTIPLIER - `LATENCY_FP32_ADDER;
    localparam  DLY_R2_COUNT    = 1 + `LATENCY_VEC3_DOT + `LATENCY_FP32_ADDER;

    logic       oc_vld;
    vec3_t      oc;
    
    logic       b_vld, b2_vld;
    fp32_t      b_tmp, b2;
    
    logic       oc_l2_vld;
    fp32_t      oc_l2;
    
    logic       c_vld;
    fp32_t      c_tmp;
    
    logic       discriminant_vld;
    fp32_t      discriminant;
    
    logic       disc_vld;
    fp32_t      disc;
    
    logic       t0_vld, t1_vld;
    fp32_t      t0_tmp, t1_tmp;

    logic       t0_min_bound_vld, t1_min_bound_vld;
    logic       t0_min_bound, t1_min_bound;

    // Registered inputs
    logic       op_vld_reg;
    vec3_t      center_reg;
    ray_t       ray_reg;

    // Delayed signals
    vec3_t      r_dir_dly;
    fp32_t      r2_dly, b_dly, c_dly;

    // Inputs to this core are on the critical path, register them
    always_ff @(posedge clk)
    begin
        op_vld_reg <= op_vld;
        center_reg <= center;
        ray_reg <= ray;
    end

    // Delay ray.dir, r^2 post computations
    shift_register #(.WIDTH($bits(vec3_t)), .DELAY_COUNT(`LATENCY_FP32_ADDER)) dly_r_dir(
        .clk(clk),
        .d(ray_reg.dir),
        .q(r_dir_dly));

    shift_register #(.WIDTH(32), .DELAY_COUNT(DLY_R2_COUNT)) dly_r2(
        .clk(clk),
        .d(radius_2),
        .q(r2_dly));
    
    // oc = sub(c, origin)
    vec3_sub sub_c_origin(
        .clk(clk),
        .op_vld(op_vld_reg),
        .a(center_reg),
        .b(ray_reg.origin),
        .result_vld(oc_vld),
        .result(oc));

    // oc_l2 = dot(oc, oc)
    vec3_dot dot_oc_oc(
        .clk(clk),
        .op_vld(oc_vld),
        .a(oc),
        .b(oc),
        .result_vld(oc_l2_vld),
        .result(oc_l2));

    // b = dot(oc, r.dir)
    vec3_dot dot_oc_dir(
        .clk(clk),
        .op_vld(oc_vld),
        .a(oc),
        .b(r_dir_dly),
        .result_vld(b_vld),
        .result(b_tmp));

    shift_register #(.WIDTH(32), .DELAY_COUNT(DLY_B_COUNT)) b_dly_unit(
        .clk(clk),
        .d(b_tmp),
        .q(b_dly));

    // b2 = b * b
    fp32_mul mul_b_b(
        .clk(clk),
        .op_vld(b_vld),
        .a(b_tmp),
        .b(b_tmp),
        .result_vld(b2_vld),
        .result(b2));

    // c = r^2 - dot(oc, oc)
    fp32_sub sub_r2_oc_l2(
        .clk(clk),
        .op_vld(b_vld),
        .a(r2_dly),
        .b(oc_l2),
        .result_vld(c_vld),
        .result(c_tmp));

    shift_register #(.WIDTH(32), .DELAY_COUNT(DLY_C_COUNT)) c_dly_unit(
        .clk(clk),
        .d(c_tmp),
        .q(c_dly));

    // discriminant = b * b + c
    fp32_add add_b2_c(
        .clk(clk),
        .op_vld(b2_vld),
        .a(b2),
        .b(c_dly),
        .result_vld(discriminant_vld),
        .result(discriminant));

    // disc = sqrt(discriminant)
    fp32_sqrt sqrt_discriminant(
        .clk(clk),
        .op_vld(discriminant_vld),
        .a(discriminant),
        .result_vld(disc_vld),
        .result(disc));

    // t0 = b - disc
    fp32_sub sub_b_disc(
        .clk(clk),
        .op_vld(disc_vld),
        .a(b_dly),
        .b(disc),
        .result_vld(t0_vld),
        .result(t0));

    // t1 = b + disc
    fp32_add add_b_disc(
        .clk(clk),
        .op_vld(disc_vld),
        .a(b_dly),
        .b(disc),
        .result_vld(result_vld),
        .result(t1));
endmodule
