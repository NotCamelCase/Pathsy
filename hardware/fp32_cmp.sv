`include "defines.svh"

module fp32_cmp
#(parameter OP = LT)
(
    input logic     clk,
    input logic     op_vld,
    input fp32_t    a, b,
    output logic    result_vld,
    output logic    result
);
    logic[7:0]  cmp_result;

    generate
        if (OP == LT)
        begin
            fp32_comp_lt cmp(
                .aclk(clk),
                .s_axis_a_tvalid(op_vld),
                .s_axis_a_tdata(a),
                .s_axis_b_tvalid(op_vld),
                .s_axis_b_tdata(b),
                .m_axis_result_tvalid(result_vld),
                .m_axis_result_tdata(cmp_result));
        end
        else if (OP == GT)
        begin
            fp32_comp_gt cmp(
                .aclk(clk),
                .s_axis_a_tvalid(op_vld),
                .s_axis_a_tdata(a),
                .s_axis_b_tvalid(op_vld),
                .s_axis_b_tdata(b),
                .m_axis_result_tvalid(result_vld),
                .m_axis_result_tdata(cmp_result));
        end
        else
        begin
            assign result_vld = 1'b0;
        end
    endgenerate

    assign result = cmp_result[0];
endmodule