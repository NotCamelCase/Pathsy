`include "defines.svh"

module shade_diffuse
(
    input logic         clk,
    input logic         op_vld,
    input logic[15:0]   r1, r2,     // Randomized Q3.13 numbers in (-1.0, 1.0)
    output logic        result_vld,
    output vec3_t       result      // rayDirDiffuse
);
    localparam  LATENCY_CORDIC_SIN_COS  = 19;

    localparam  DLY_CORDIC_OP_VLD_COUNT = (`LATENCY_CVT_QNM_FP32 + `LATENCY_FP32_MULTIPLIER + `LATENCY_FP32_ADDER + `LATENCY_FP32_SQRT) - (LATENCY_CORDIC_SIN_COS + `LATENCY_CVT_QNM_FP32);
    localparam  DLY_Z_COUNT             = `LATENCY_FP32_MULTIPLIER + `LATENCY_FP32_ADDER + `LATENCY_FP32_SQRT + `LATENCY_FP32_MULTIPLIER;

    // CORDIC
    logic       cordic_result_vld;
    logic[31:0] cordic_result; // cos=0..15, sin=16..31

    // Q2.14 to fp32 conversion
    logic       cos_r2_vld, sin_r2_vld;
    fp32_t      cos_r2, sin_r2;

    // sqrt computation
    logic       z_vld, z2_vld, r_vld, r_sqrt_vld;
    fp32_t      z, z2, r, r_sqrt;

    // Delayed signals
    logic       cordic_op_vld_dly;
    logic[15:0] cordic_input_dly;

    // Delay CORDIC computation to align with fp32_sqrt arrival
    shift_register #(.WIDTH(1), .DELAY_COUNT(DLY_CORDIC_OP_VLD_COUNT)) dly_cordic_op_vld(
        .clk(clk),
        .d(op_vld),
        .q(cordic_op_vld_dly));

    shift_register #(.WIDTH(16), .DELAY_COUNT(DLY_CORDIC_OP_VLD_COUNT)) dly_cordic_input(
        .clk(clk),
        .d(r2),
        .q(cordic_input_dly));

    // Compute cos(r2), sin(r2)
    cordic_sin_cos sin_cos_calc(
        .aclk(clk),
        .s_axis_phase_tvalid(cordic_op_vld_dly),
        .s_axis_phase_tdata(cordic_input_dly),
        .m_axis_dout_tvalid(cordic_result_vld),
        .m_axis_dout_tdata(cordic_result));

    // Convert CORDIC results to fp32
    cvt_q2_14_fp32 cvt_cos(
        .aclk(clk),
        .s_axis_a_tvalid(cordic_result_vld),
        .s_axis_a_tdata(cordic_result[15:0]), // cos(x)
        .m_axis_result_tvalid(cos_r2_vld),
        .m_axis_result_tdata(cos_r2));

    cvt_q2_14_fp32 cvt_sin(
        .aclk(clk),
        .s_axis_a_tvalid(cordic_result_vld),
        .s_axis_a_tdata(cordic_result[31:16]), // sin(x)
        .m_axis_result_tvalid(sin_r2_vld),
        .m_axis_result_tdata(sin_r2));

    // Convert Q3.13 input to fp32
    cvt_q3_13_fp32 cvt_r1_fp32(
        .aclk(clk),
        .s_axis_a_tvalid(op_vld),
        .s_axis_a_tdata(r1),
        .m_axis_result_tvalid(z_vld),
        .m_axis_result_tdata(z));

    // z^2 = z * z
    fp32_mul mul_z_z(
        .clk(clk),
        .op_vld(z_vld),
        .a(z),
        .b(z),
        .result_vld(z2_vld),
        .result(z2));

    // r = 1 - z^2
    fp32_sub sub_1_z2(
        .clk(clk),
        .op_vld(z2_vld),
        .a(32'h3f800000), // 1.f
        .b(z2),
        .result_vld(r_vld),
        .result(r));

    // r = sqrt(r)
    fp32_sqrt sqrt_r(
        .clk(clk),
        .op_vld(r_vld),
        .a(r),
        .result_vld(r_sqrt_vld),
        .result(r_sqrt));

    // x = cos(r2) * r
    fp32_mul calc_x(
        .clk(clk),
        .op_vld(r_sqrt_vld),
        .a(r_sqrt),
        .b(cos_r2),
        .result_vld(),
        .result(result.x));

    // y = sin(r2) * r
    fp32_mul calc_y(
        .clk(clk),
        .op_vld(r_sqrt_vld),
        .a(r_sqrt),
        .b(sin_r2),
        .result_vld(result_vld),
        .result(result.y));

    // Delay z
    shift_register #(.WIDTH(32), .DELAY_COUNT(DLY_Z_COUNT)) dly_z(
        .clk(clk),
        .d(z),
        .q(result.z));
endmodule