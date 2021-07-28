`include "defines.svh"

module shade_specular
(
    input logic     clk,
    input logic     op_vld,
    input fp32_t    n_dot_d,    // dot(n, d)
    input vec3_t    n,          // sphere normal
    output logic    result_vld,
    output vec3_t   result      // rayDirSpecular
);
    // t1 = mul(n, ndotd);
    // t2 = mul(t1, -2.f);

    localparam  MINUS_TWO   = 32'hc0000000; // -2.f

    logic   t1_x_vld, t1_y_vld, t1_z_vld;
    vec3_t  t1;

    logic   t2_x_vld, t2_y_vld;

    // t1 = mul(n, ndotd)
    fp32_mul t1_x(
        .clk(clk),
        .op_vld(op_vld),
        .a(n.x),
        .b(n_dot_d),
        .result_vld(t1_x_vld),
        .result(t1.x));

    fp32_mul t1_y(
        .clk(clk),
        .op_vld(op_vld),
        .a(n.y),
        .b(n_dot_d),
        .result_vld(t1_y_vld),
        .result(t1.y));

    fp32_mul t1_z(
        .clk(clk),
        .op_vld(op_vld),
        .a(n.z),
        .b(n_dot_d),
        .result_vld(t1_z_vld),
        .result(t1.z));

    // t2 = mul(t1, -2.f)
    fp32_mul t2_x(
        .clk(clk),
        .op_vld(t1_x_vld),
        .a(t1.x),
        .b(MINUS_TWO),
        .result_vld(t2_x_vld),
        .result(result.x));

    fp32_mul t2_y(
        .clk(clk),
        .op_vld(t1_x_vld),
        .a(t1.y),
        .b(MINUS_TWO),
        .result_vld(t2_y_vld),
        .result(result.y));

    fp32_mul t2_z(
        .clk(clk),
        .op_vld(t1_x_vld),
        .a(t1.z),
        .b(MINUS_TWO),
        .result_vld(result_vld),
        .result(result.z));
endmodule