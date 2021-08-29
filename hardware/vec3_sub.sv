`include "defines.svh"

// vec3(c_x, c_y, c_z) = vec3(a_x, a_y, a_z) - vec3(b_x, b_y, b_z)
module vec3_sub
#(parameter USE_DSP = MED)
(
    input logic     clk,
    input logic     op_vld,
    input vec3_t    a, b,
    output logic    result_vld,
    output vec3_t   result
);
    // Parallel fp32_adders
    // c_x = a_x - b_x
    // c_y = a_y - b_y
    // c_z = a_z - b_z

    logic   sub_x_vld, sub_y_vld, sub_z_vld;

    fp32_sub #(.USE_DSP(USE_DSP)) sub_x(
        .clk(clk),
        .op_vld(op_vld),
        .a(a.x),
        .b(b.x),
        .result_vld(sub_x_vld),
        .result(result.x));

    fp32_sub #(.USE_DSP(USE_DSP)) sub_y(
        .clk(clk),
        .op_vld(op_vld),
        .a(a.y),
        .b(b.y),
        .result_vld(sub_y_vld),
        .result(result.y));

    fp32_sub #(.USE_DSP(USE_DSP)) sub_z(
        .clk(clk),
        .op_vld(op_vld),
        .a(a.z),
        .b(b.z),
        .result_vld(sub_z_vld),
        .result(result.z));

    assign result_vld = sub_x_vld;
endmodule