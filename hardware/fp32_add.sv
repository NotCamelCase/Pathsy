`include "defines.svh"

module fp32_add
#(parameter USE_DSP = MED)
(
    input logic     clk,
    input logic     op_vld,
    input fp32_t    a, b,
    output logic    result_vld,
    output fp32_t   result
);
    generate
        if (USE_DSP == FULL)
            fp32_adder_full_dsp adder(
                .aclk(clk),
                .s_axis_a_tvalid(op_vld),
                .s_axis_a_tdata(a),
                .s_axis_b_tvalid(op_vld),
                .s_axis_b_tdata(b),
                .m_axis_result_tvalid(result_vld),
                .m_axis_result_tdata(result));
        else if (USE_DSP == MED)
            fp32_adder_med_dsp adder(
                .aclk(clk),
                .s_axis_a_tvalid(op_vld),
                .s_axis_a_tdata(a),
                .s_axis_b_tvalid(op_vld),
                .s_axis_b_tdata(b),
                .m_axis_result_tvalid(result_vld),
                .m_axis_result_tdata(result));
        else
            fp32_adder_low_dsp adder(
                .aclk(clk),
                .s_axis_a_tvalid(op_vld),
                .s_axis_a_tdata(a),
                .s_axis_b_tvalid(op_vld),
                .s_axis_b_tdata(b),
                .m_axis_result_tvalid(result_vld),
                .m_axis_result_tdata(result));
    endgenerate
endmodule