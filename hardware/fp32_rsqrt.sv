`include "defines.svh"

module fp32_rsqrt
#(parameter USE_DSP = MED)
(
    input logic     clk,
    input logic     op_vld,
    input fp32_t    a,
    output logic    result_vld,
    output fp32_t   result
);
    generate
        if (USE_DSP == FULL)
            fp32_rsqrt_full_dsp rsqrt(
                .aclk(clk),
                .s_axis_a_tvalid(op_vld),
                .s_axis_a_tdata(a),
                .m_axis_result_tvalid(result_vld),
                .m_axis_result_tdata(result));
        else
            fp32_rsqrt_no_dsp rsqrt(
                .aclk(clk),
                .s_axis_a_tvalid(op_vld),
                .s_axis_a_tdata(a),
                .m_axis_result_tvalid(result_vld),
                .m_axis_result_tdata(result));
    endgenerate
endmodule