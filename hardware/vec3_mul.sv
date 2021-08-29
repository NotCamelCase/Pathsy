`include "defines.svh"

// vec3(c) = vec3(a_x, a_y, a_z) * vec3(b_x, b_y, b_z)
module vec3_mul
#(parameter USE_DSP = MED)
(
    input logic     clk,
    input logic     op_vld,
    input vec3_t    a, b,
    output logic    result_vld,
    output vec3_t   result
);
    // vec3 c = (a_x * b_x, a_y * b_y, a_z * b_z)

    logic   mul_x_vld, mul_y_vld, mul_z_vld;

    // Parallel multipliers
    fp32_mul #(.USE_DSP(USE_DSP)) mulx(
        .clk(clk),
        .op_vld(op_vld),
        .a(a.x),
        .b(b.x),
        .result_vld(mul_x_vld),
        .result(result.x));

    fp32_mul #(.USE_DSP(USE_DSP)) muly(
        .clk(clk),
        .op_vld(op_vld),
        .a(a.y),
        .b(b.y),
        .result_vld(mul_y_vld),
        .result(result.y));

    fp32_mul #(.USE_DSP(USE_DSP)) mulz(
        .clk(clk),
        .op_vld(op_vld),
        .a(a.z),
        .b(b.z),
        .result_vld(mul_z_vld),
        .result(result.z));

    assign result_vld = mul_x_vld;
endmodule