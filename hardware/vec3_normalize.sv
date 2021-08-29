`include "defines.svh"

// vec3(n) = normalize(vec3(x, y, z))
module vec3_normalize
#(parameter USE_DSP = MED)
(
    input logic     clk,
    input logic     op_vld,
    input vec3_t    a,
    output logic    result_vld,
    output vec3_t   result
);
    // l2 = dot(a, a)
    // l = rsqrt(l2)
    // n = mul(a, l)

    localparam  DLY_A_COUNT = `LATENCY_VEC3_DOT + `LATENCY_FP32_RSQRT;

    logic   l2_vld;
    fp32_t  l2;

    logic   l_vld;
    fp32_t  l;

    logic   mul_x_vld, mul_y_vld, mul_z_vld;

    // Delayed signals
    vec3_t  a_dly;

    shift_register #(.WIDTH($bits(vec3_t)), .DELAY_COUNT(DLY_A_COUNT)) dly_a(
        .clk(clk),
        .d(a),
        .q(a_dly));

    // l2 = dot(a, a)
    vec3_dot #(.USE_DSP(USE_DSP)) dot_a_a(
        .clk(clk),
        .op_vld(op_vld),
        .a(a),
        .b(a),
        .result_vld(l2_vld),
        .result(l2));

    // l = rsqrt(l2)
    fp32_rsqrt #(.USE_DSP(FULL)) rsqrt_l2(
        .clk(clk),
        .op_vld(l2_vld),
        .a(l2),
        .result_vld(l_vld),
        .result(l));

    // mul(a, l)
    fp32_mul #(.USE_DSP(USE_DSP)) mul_a_x_l(
        .clk(clk),
        .a(a_dly.x),
        .b(l),
        .op_vld(l_vld),
        .result_vld(mul_x_vld),
        .result(result.x));

    fp32_mul #(.USE_DSP(USE_DSP)) mul_a_y_l(
        .clk(clk),
        .a(a_dly.y),
        .b(l),
        .op_vld(l_vld),
        .result_vld(mul_y_vld),
        .result(result.y));

    fp32_mul #(.USE_DSP(USE_DSP)) mul_a_z_l(
        .clk(clk),
        .a(a_dly.z),
        .b(l),
        .op_vld(l_vld),
        .result_vld(mul_z_vld),
        .result(result.z));

    assign result_vld = mul_x_vld;
endmodule