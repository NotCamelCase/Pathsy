`include "defines.svh"

module ray_gen
(
    input logic                 clk,
    input logic                 op_vld,
    // Pixel coordinates
    input logic[`PX_WIDTH-1:0]  x,
    input logic[`PY_WIDTH-1:0]  y,
    // Sample
    input logic[`RPP_WIDTH-1:0] s,
    output logic                result_vld,
    // Computed ray
    output ray_t                ray
);
    // Fetch (sx, sy) sample offsets
    // Compute sample position in fixed-point
    // Convert result to fp32
    // Normalize ray.dir

    localparam  CX          = 21'h155556; // -1.333333373f    -> SQ2.19
    localparam  CY          = 21'h180000; // -1.0f            -> SQ2.19
    localparam  CZ          = 21'h180000; // -1.0f            -> SQ2.19
    localparam  X_FACTOR    = 24'h01117e; // 0.004173187539f  -> Q0.24
    localparam  Y_FACTOR    = 24'h0111a3; // 0.004173187539f  -> Q0.24

    sample_pos_t            sample_pos_reg, sample_pos_nxt;

    logic[20:0]             px_reg, px_nxt, py_reg, py_nxt;
    logic[20:0]             tx_reg, tx_nxt, ty_reg, ty_nxt;
    logic[44:0]             x_res_tmp, y_res_tmp;

    logic                   cvt_q2_19_fp32_x_vld, cvt_q2_19_fp32_y_vld, cvt_q2_19_fp32_z_vld;
    logic[23:0]             tx_ext, ty_ext, tz_ext;
    vec3_t                  cvt_pixel_coords_fp32;

    logic                   op_vld_reg;
    logic                   sample_pos_vld_reg;
    logic                   p_vld_reg;
    logic                   t_vld_reg;

    // Delayed signals
    logic[`PX_WIDTH-1:0]    x_dly;
    logic[`PY_WIDTH-1:0]    y_dly;

    shift_register #(.WIDTH(`PX_WIDTH), .DELAY_COUNT(2)) dly_x(
        .clk(clk),
        .d(x),
        .q(x_dly));

    shift_register #(.WIDTH(`PY_WIDTH), .DELAY_COUNT(2)) dly_y(
        .clk(clk),
        .d(y),
        .q(y_dly));

    sync_rom #(.ROM_FILE("sample_pos.mem"), .ADDR_WIDTH(`RPP_WIDTH), .DATA_WIDTH($bits(sample_pos_t))) sample_pos_rom(
        .clk(clk),
        .addr(s),
        .data(sample_pos_nxt));

    // Valids
    always_ff @(posedge clk)
    begin
        op_vld_reg <= op_vld;
        sample_pos_vld_reg <= op_vld_reg;
        p_vld_reg <= sample_pos_vld_reg;
        t_vld_reg <= p_vld_reg;
    end

    // Stage 1: Load sample pos from the pre-initialized ROM
    always_ff @(posedge clk)
    begin
        sample_pos_reg <= sample_pos_nxt;
    end

    // Stage 2: Perform p.s * x/y_factor
    always_ff @(posedge clk)
    begin
        px_reg <= px_nxt;
        py_reg <= py_nxt;
    end

    always_comb
    begin
        // Q10.11 * Q0.24 -> Q10.35
        // Q10.35 -> Q10.19
        x_res_tmp = ({x_dly, sample_pos_reg.pos_x} * X_FACTOR) >> 16;
        y_res_tmp = ({y_dly, sample_pos_reg.pos_y} * Y_FACTOR) >> 16;

        // Q10.19 -> Q2.19
        px_nxt = x_res_tmp[20:0];
        py_nxt = y_res_tmp[20:0];
    end

    // Stage 3: Perform c + p.s * x/y_factor
    always_ff @(posedge clk)
    begin
        tx_reg <= tx_nxt;
        ty_reg <= ty_nxt;
    end

    always_comb
    begin
        // SQ2.19 + Q2.19
        tx_nxt = $signed(CX) + $signed(px_reg);
        ty_nxt = $signed(CY) + $signed(py_reg);
    end

    // Stage 4: Convert Q2.19 -> fp32
    // IP interface requires 24-bit fixed-point input
    sign_extender #(.PRE_WIDTH(21), .POST_WIDTH(24)) ext_x(
        .i(tx_reg),
        .o(tx_ext));

    sign_extender #(.PRE_WIDTH(21), .POST_WIDTH(24)) ext_y(
        .i(ty_reg),
        .o(ty_ext));

    sign_extender #(.PRE_WIDTH(21), .POST_WIDTH(24)) ext_z(
        .i(CZ),
        .o(tz_ext));

    cvt_q2_19_fp32 cvt_q2_19_fp32_x(
        .aclk(clk),
        .s_axis_a_tvalid(t_vld_reg),
        .s_axis_a_tdata(tx_ext),
        .m_axis_result_tvalid(cvt_q2_19_fp32_x_vld),
        .m_axis_result_tdata(cvt_pixel_coords_fp32.x));

    cvt_q2_19_fp32 cvt_q2_19_fp32_y(
        .aclk(clk),
        .s_axis_a_tvalid(t_vld_reg),
        .s_axis_a_tdata(ty_ext),
        .m_axis_result_tvalid(cvt_q2_19_fp32_y_vld),
        .m_axis_result_tdata(cvt_pixel_coords_fp32.y));

    cvt_q2_19_fp32 cvt_q2_19_fp32_z(
        .aclk(clk),
        .s_axis_a_tvalid(t_vld_reg),
        .s_axis_a_tdata(tz_ext),
        .m_axis_result_tvalid(cvt_q2_19_fp32_z_vld),
        .m_axis_result_tdata(cvt_pixel_coords_fp32.z));

    // Stage 5: Normalize vec3 ray.dir
    vec3_normalize #(.USE_DSP(LOW)) normalize_ray_dir(
        .clk(clk),
        .op_vld(cvt_q2_19_fp32_x_vld),
        .a(cvt_pixel_coords_fp32),
        .result_vld(result_vld),
        .result(ray.dir));

    // Constant origin at vec3(0, 0, 0)
    assign ray.origin = {32'h0, 32'h0, 32'h0};
endmodule