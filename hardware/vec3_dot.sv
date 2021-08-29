`include "defines.svh"

// float(s) = dot(vec3(a_x, a_y, a_z), vec3(b_x, b_y, b_z))
module vec3_dot
#(parameter USE_DSP = MED)
(
    input logic     clk,
    input logic     op_vld,
    input vec3_t    a, b,
    output logic    result_vld,
    output fp32_t   result
);
    // s = (a_x * b_x) + (a_y * b_y) + (a_z * b_z)
    // xy = x + y
    // s = xy + z

    logic   mul_xyz_vld, add_xy_vld;
    vec3_t  mul_xyz;
    fp32_t  add_xy;
    fp32_t  mul_z_dly;

    vec3_mul #(.USE_DSP(USE_DSP)) mulxyz(
        .clk(clk),
        .op_vld(op_vld),
        .a(a),
        .b(b),
        .result_vld(mul_xyz_vld),
        .result(mul_xyz));

    // delay (a_z * b_z) for (xy + z)
    shift_register #(.WIDTH(32), .DELAY_COUNT(`LATENCY_FP32_ADDER)) mulz_dly(
        .clk(clk),
        .d(mul_xyz.z),
        .q(mul_z_dly));

    fp32_add #(.USE_DSP(USE_DSP)) addxy(
        .clk(clk),
        .op_vld(mul_xyz_vld),
        .a(mul_xyz.x),
        .b(mul_xyz.y),
        .result_vld(add_xy_vld),
        .result(add_xy));

    fp32_add #(.USE_DSP(USE_DSP)) addxyz(
        .clk(clk),
        .op_vld(add_xy_vld),
        .a(add_xy),
        .b(mul_z_dly),
        .result_vld(result_vld),
        .result(result));
endmodule