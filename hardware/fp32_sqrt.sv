`include "defines.svh"

module fp32_sqrt
(
    input logic     clk,
    input logic     op_vld,
    input fp32_t    a,
    output logic    result_vld,
    output fp32_t   result
);
    fp32_sqrt_no_dsp sqrt(
        .aclk(clk),
        .s_axis_a_tvalid(op_vld),
        .s_axis_a_tdata(a),
        .m_axis_result_tvalid(result_vld),
        .m_axis_result_tdata(result));
endmodule