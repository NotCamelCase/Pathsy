`include "defines.svh"

module fp32_mul
#(parameter USE_DSP = MED)
(
    input logic     clk,
    input logic     op_vld,
    input fp32_t    a, b,
    output logic    result_vld,
    output fp32_t   result
);
    generate
        if (USE_DSP == 0)
            fp32_multiplier_full_dsp multiplier(
                .aclk(clk),
                .s_axis_a_tvalid(op_vld),
                .s_axis_a_tdata(a),
                .s_axis_b_tvalid(op_vld),
                .s_axis_b_tdata(b),
                .m_axis_result_tvalid(result_vld),
                .m_axis_result_tdata(result));
        else if (USE_DSP == MED)
            fp32_multiplier_med_dsp multiplier(
                .aclk(clk),
                .s_axis_a_tvalid(op_vld),
                .s_axis_a_tdata(a),
                .s_axis_b_tvalid(op_vld),
                .s_axis_b_tdata(b),
                .m_axis_result_tvalid(result_vld),
                .m_axis_result_tdata(result));
        else
            fp32_multiplier_low_dsp multiplier(
                .aclk(clk),
                .s_axis_a_tvalid(op_vld),
                .s_axis_a_tdata(a),
                .s_axis_b_tvalid(op_vld),
                .s_axis_b_tdata(b),
                .m_axis_result_tvalid(result_vld),
                .m_axis_result_tdata(result));
    endgenerate
endmodule