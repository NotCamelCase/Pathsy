`include "defines.svh"

module shade_rays_stage
(
    input logic                     clk, rst,
    input logic                     start,
    output logic                    busy,
    input hit_info_t                hit_info,
    input vec3_t                    ray_f_current,
    input vec3_t                    ray_l_current,
    // hit_info fetch ndx
    output logic[`RPP_WIDTH-1:0]    fetch_hit_info_ndx,
    // L/F fetch ndx
    output logic[`RPP_WIDTH-1:0]    fetch_ray_color_ndx,
    output logic                    store_data_wr_en,
    // data store ndx
    output logic[`RPP_WIDTH-1:0]    store_data_ndx,
    output logic                    ray_hit,
    output ray_t                    ray_new,
    output vec3_t                   ray_f_new,
    output vec3_t                   ray_l_new
);
    localparam  LATENCY_COMPUTE_HIT_POINT       = `LATENCY_FP32_MULTIPLIER + `LATENCY_FP32_ADDER;
    localparam  LATENCY_COMPUTE_SPHERE_NORMAL   = `LATENCY_FP32_ADDER + `LATENCY_VEC3_NORMALIZE;
    localparam  LATENCY_SHADE_SPECULAR          = 2 * `LATENCY_FP32_MULTIPLIER;
    localparam  LATENCY_SHADE_DIFFUSE           = 35;

    localparam  DLY_RAY_DIR_NDOTD_COUNT         = LATENCY_COMPUTE_HIT_POINT + LATENCY_COMPUTE_SPHERE_NORMAL;
    localparam  DLY_RAY_DIR_ADD_COUNT           = `LATENCY_VEC3_DOT + LATENCY_SHADE_SPECULAR;
    localparam  DLY_SHADE_DIFFUSE_ISSUE_COUNT   = 1 + LATENCY_COMPUTE_HIT_POINT + LATENCY_COMPUTE_SPHERE_NORMAL + `LATENCY_VEC3_DOT + LATENCY_SHADE_SPECULAR - LATENCY_SHADE_DIFFUSE;
    localparam  DLY_RAY_ORIGIN_COUNT            = LATENCY_SHADE_SPECULAR + `LATENCY_FP32_ADDER + `LATENCY_VEC3_NORMALIZE - (`LATENCY_FP32_MULTIPLIER + `LATENCY_FP32_ADDER);
    localparam  DLY_HIT_POINT_COUNT             = LATENCY_COMPUTE_SPHERE_NORMAL + `LATENCY_VEC3_DOT + `LATENCY_FP32_MULTIPLIER;
    localparam  DLY_COLOR_UPDATE_OP_VLD_COUNT   = 1 + LATENCY_COMPUTE_HIT_POINT + LATENCY_COMPUTE_SPHERE_NORMAL + `LATENCY_VEC3_DOT + LATENCY_SHADE_SPECULAR + `LATENCY_FP32_ADDER + `LATENCY_VEC3_NORMALIZE - (`LATENCY_FP32_MULTIPLIER + `LATENCY_FP32_ADDER);
    localparam  DLY_RAY_HIT_MATERIAL_COUNT      = DLY_COLOR_UPDATE_OP_VLD_COUNT - 1;
    localparam  DLY_MATERIAL_TYPE_COUNT         = LATENCY_COMPUTE_HIT_POINT + LATENCY_COMPUTE_SPHERE_NORMAL + `LATENCY_VEC3_DOT + LATENCY_SHADE_SPECULAR;
    localparam  DLY_MATERIAL_NDX_COUNT          = DLY_COLOR_UPDATE_OP_VLD_COUNT - 2;
    localparam  DLY_RAY_HIT_OUTPUT_COUNT        = `LATENCY_FP32_MULTIPLIER + `LATENCY_FP32_ADDER;
    localparam  DLY_RAY_NDX_COLOR_FETCH_COUNT   = DLY_COLOR_UPDATE_OP_VLD_COUNT - 1;

    // Control/status signals
    logic                       busy_reg, busy_nxt;
    logic                       loop_active, result_vld;

    // Loop counter
    logic[`RPP_WIDTH:0]         ray_ctr_reg, ray_ctr_nxt;

    // rayIdx
    logic[`RPP_WIDTH-1:0]       ray_ndx_reg, ray_ndx_nxt;

    // prng
    logic                       prng_on_dly;
    logic[14:0]                 prng_final_r1, prng_final_r2;
    logic[15:0]                 prng_tmp_r1, prng_tmp_r2;
    logic[15:0]                 prng_r1, prng_r2;
    logic[15:0]                 r1, r2;

    // compute_hit_point
    logic                       mul_rd_t_vld, compute_hit_point_result_vld;
    vec3_t                      rt, hit_point;

    // compute_sphere_normal
    logic                       v_vld, compute_sphere_normal_result_vld;
    vec3_t                      v, n_raw;

    // dot(n, r.d)
    logic                       ndotd_vld;
    fp32_t                      ndotd;
    vec3_t                      n;

    // shade_specular
    logic                       shade_specular_result_vld;
    vec3_t                      ray_dir_specular;

    // shade_diffuse
    logic                       shade_diffuse_op_vld, shade_diffuse_result_vld;
    vec3_t                      ray_dir_diffuse;

    // ray_new
    logic                       n_eps_mul_vld, add_n_p_vld, ray_dir_unnormalized_vld;
    vec3_t                      n_eps_mul, ray_dir_raw, ray_origin;
    vec3_t                      new_ray_dir;

    // Material data
    logic                       material_type;
    material_info_t             material_info;

    // ray color
    logic                       mul_fp_vld;
    vec3_t                      mul_fp_emission_result, mul_fp_albedo_result;

    // Delayed signals
    logic                       op_vld_dly;
    logic                       ray_hit_material_dly, ray_hit_output_dly;
    logic                       material_type_dly, color_update_op_vld_dly;
    logic[`SPHERES_WIDTH-1:0]   material_ndx_dly;
    logic[`RPP_WIDTH-1:0]       ray_color_fetch_ndx_dly;
    vec3_t                      sphere_center_dly;
    vec3_t                      ray_dir_ndotd_dly, ray_dir_add_dly;
    vec3_t                      n_raw_dly, n_dly, hit_point_dly;
    vec3_t                      ro_dly, ray_l_dly;

    // Registers
    always_ff @(posedge clk)
    begin
        if (rst)
        begin
            busy_reg <= 1'b0;
        end
        else
        begin
            busy_reg <= busy_nxt;
            ray_ctr_reg <= ray_ctr_nxt;
            ray_ndx_reg <= ray_ndx_nxt;
        end
    end

    // Control path
    always_comb
    begin
        busy_nxt = busy_reg;

        ray_ctr_nxt = ray_ctr_reg;
        ray_ndx_nxt = ray_ndx_reg;

        loop_active = 1'b0;
        
        if (start)
        begin
            // New request, initialize the index and loop counter and begin shading rays
            ray_ctr_nxt = {`RPP_WIDTH+1{1'b0}};
            ray_ndx_nxt = {`RPP_WIDTH{1'b0}};
            busy_nxt = 1'b1;
        end
        else if (busy_reg)
        begin
            // Issue a new ray to be shaded for RPP iterations
            loop_active = (ray_ctr_reg < `RPP);

            ray_ctr_nxt = loop_active ? (ray_ctr_reg + 1) : ray_ctr_reg;
            ray_ndx_nxt = result_vld ? (ray_ndx_reg + 1) : ray_ndx_reg;

            // Done if RPP rays were shaded
            if (ray_ndx_reg == `RPP-1)
                busy_nxt = 1'b0;
        end
    end

    // Generate pseudo-random numbers
    prng #(.SEED(16'hdead)) prng_r1_unit(
        .clk(clk),
        .rst(rst),
        .enable(prng_on_dly & ~material_type_dly),
        .rand_number(prng_r1));

    prng #(.SEED(16'hbeef)) prng_r2_unit(
        .clk(clk),
        .rst(rst),
        .enable(prng_on_dly & ~material_type_dly),
        .rand_number(prng_r2));

    // Ready r1/r2 for shade_diffuse inf
    sign_extender #(.PRE_WIDTH(15), .POST_WIDTH(16)) ext_prng_r1(
        .i(prng_final_r1),
        .o(r1)); // Q3.13

    sign_extender #(.PRE_WIDTH(15), .POST_WIDTH(16)) ext_prng_r2(
        .i(prng_final_r2),
        .o(r2)); // Q3.13

    // Map prng output from [0, 1) to [-1, 1)
    assign prng_tmp_r1 = prng_r1 >> 1;
    assign prng_tmp_r2 = prng_r2 >> 1;
    assign prng_final_r1 = prng_tmp_r1[15:1] - 15'b010000000000000;
    assign prng_final_r2 = prng_tmp_r2[15:1] - 15'b010000000000000;

    // Shading type, keep in sync!
    true_rom  #(.ROM_FILE("material_types.mem"), .ADDR_WIDTH(`SPHERES_WIDTH), .DATA_WIDTH(1)) material_types(
    	.addr(hit_info.sphere_id),
        .data(material_type));

    // Delay material type
    shift_register #(.WIDTH(1), .DELAY_COUNT(DLY_MATERIAL_TYPE_COUNT)) dly_material_type(
        .clk(clk),
        .d(material_type),
        .q(material_type_dly));

    // Delay hit_info.hit
    shift_register #(.WIDTH(1), .DELAY_COUNT(DLY_RAY_HIT_MATERIAL_COUNT)) dly_ray_hit_material(
        .clk(clk),
        .d(hit_info.hit),
        .q(ray_hit_material_dly));

    shift_register #(.WIDTH(1), .DELAY_COUNT(DLY_RAY_HIT_OUTPUT_COUNT)) dly_ray_hit_output(
        .clk(clk),
        .d(ray_hit_material_dly),
        .q(ray_hit_output_dly));

    // Delay ray.dir for dot(n_raw, ray.dir)
    shift_register #(.WIDTH($bits(vec3_t)), .DELAY_COUNT(DLY_RAY_DIR_NDOTD_COUNT)) dly_ray_dir_ndotd(
        .clk(clk),
        .d(hit_info.ray.dir),
        .q(ray_dir_ndotd_dly));

    // Delay ray.dir for new ray.dir prep
    shift_register #(.WIDTH($bits(vec3_t)), .DELAY_COUNT(DLY_RAY_DIR_ADD_COUNT)) dly_ray_dir_add(
        .clk(clk),
        .d(ray_dir_ndotd_dly),
        .q(ray_dir_add_dly));

    // Delay sphere_center post compute_hit_point
    shift_register #(.WIDTH($bits(vec3_t)), .DELAY_COUNT(LATENCY_COMPUTE_HIT_POINT)) dly_sphere_center(
        .clk(clk),
        .d(hit_info.sphere_center),
        .q(sphere_center_dly));

    // Delay vld post fetching hit_info
    shift_register #(.WIDTH(1), .DELAY_COUNT(1)) dly_loop_active(
        .clk(clk),
        .d(loop_active),
        .q(op_vld_dly));

    // Issue shade_diffuse to align it with shade_specular arrival
    shift_register #(.WIDTH(1), .DELAY_COUNT(DLY_SHADE_DIFFUSE_ISSUE_COUNT)) dly_shade_diffuse_vld(
        .clk(clk),
        .d(loop_active),
        .q(shade_diffuse_op_vld));

    // Delay PRNG to prepare for shade_diffuse
    shift_register  #(.WIDTH(1), .DELAY_COUNT(DLY_SHADE_DIFFUSE_ISSUE_COUNT-2/*mapping delay*/)) dly_prng_vld(
        .clk(clk ),
        .d(loop_active),
        .q(prng_on_dly));

    // Delay p for origin calculation
    shift_register #(.WIDTH($bits(vec3_t)), .DELAY_COUNT(DLY_HIT_POINT_COUNT)) dly_hit_point(
        .clk(clk),
        .d(hit_point),
        .q(hit_point_dly));

    // Delay rt post mul
    shift_register #(.WIDTH($bits(vec3_t)), .DELAY_COUNT(`LATENCY_FP32_MULTIPLIER)) dly_ro(
        .clk(clk),
        .d(hit_info.ray.origin),
        .q(ro_dly));

    // Hit point calculation
    // rt = mul(ray.dir, t)
    vec3_mul mul_rd_t(
        .clk(clk),
        .op_vld(op_vld_dly),
        .a(hit_info.ray.dir),
        .b({hit_info.t, hit_info.t, hit_info.t}),
        .result_vld(mul_rd_t_vld),
        .result(rt));

    // p = add(ro, rt)
    vec3_add add_ro_t(
        .clk(clk),
        .op_vld(mul_rd_t_vld),
        .a(ro_dly),
        .b(rt),
        .result_vld(compute_hit_point_result_vld),
        .result(hit_point));

    // Normal at hit point (non-oriented!)
    // v = sub(p, c)
    vec3_sub sub_p_c(
        .clk(clk),
        .op_vld(compute_hit_point_result_vld),
        .a(hit_point),
        .b(sphere_center_dly),
        .result_vld(v_vld),
        .result(v));

    // r = normalize(v)
    vec3_normalize normalize_v(
        .clk(clk),
        .op_vld(v_vld),
        .a(v),
        .result_vld(compute_sphere_normal_result_vld),
        .result(n_raw));

    // Delay n_raw for orientation post dot
    shift_register #(.WIDTH($bits(vec3_t)), .DELAY_COUNT(`LATENCY_VEC3_DOT)) dly_n_raw(
        .clk(clk),
        .d(n_raw),
        .q(n_raw_dly));

    // ndotd = dot(n_raw, ray.dir)
    vec3_dot #(.USE_DSP(FULL)) calc_ndotd(
        .clk(clk),
        .op_vld(compute_sphere_normal_result_vld),
        .a(n_raw),
        .b(ray_dir_ndotd_dly),
        .result_vld(ndotd_vld),
        .result(ndotd));

    // Re-orient the normal such that it's on the same side as the ray
    // Simplified logic for: n = (ndotd < 0.f) ? nRaw : Vec3Mul(nRaw, -1.f)
    assign n.x = {~ndotd[31] ^ n_raw_dly.x[31], n_raw_dly.x[30:0]};
    assign n.y = {~ndotd[31] ^ n_raw_dly.y[31], n_raw_dly.y[30:0]};
    assign n.z = {~ndotd[31] ^ n_raw_dly.z[31], n_raw_dly.z[30:0]};

    // Delay n for add post shading
    shift_register #(.WIDTH($bits(vec3_t)), .DELAY_COUNT(LATENCY_SHADE_SPECULAR)) dly_n(
        .clk(clk),
        .d(n),
        .q(n_dly));

    // Nudge off the hit point a little
    vec3_mul mul_n_eps(
        .clk(clk),
        .op_vld(ndotd_vld),
        .a(n),
        .b({32'h3a83126f, 32'h3a83126f, 32'h3a83126f}), //1e-3
        .result_vld(n_eps_mul_vld),
        .result(n_eps_mul));

    vec3_add add_n_p(
        .clk(clk),
        .op_vld(n_eps_mul_vld),
        .a(hit_point_dly),
        .b(n_eps_mul),
        .result_vld(add_n_p_vld),
        .result(ray_origin));

    // Delay ray_new.origin for output
    shift_register #(.WIDTH($bits(vec3_t)), .DELAY_COUNT(DLY_RAY_ORIGIN_COUNT)) dly_ray_origin(
        .clk(clk),
        .d(ray_origin),
        .q(ray_new.origin));

    // Issue shade_diffuse
    shade_diffuse shade_diffuse_unit(
        .clk(clk),
        .op_vld(shade_diffuse_op_vld),
        .r1(r1),
        .r2(r2),
        .result_vld(shade_diffuse_result_vld),
        .result(ray_dir_diffuse));

    // Issue shade_specular
    shade_specular shade_specular_unit(
        .clk(clk),
        .op_vld(ndotd_vld),
        .n_dot_d(ndotd),
        .n(n),
        .result_vld(shade_specular_result_vld),
        .result(ray_dir_specular)); // Not the reflection vector, but that which, when subtracted from from ray.dir, would give the ideal mirror reflection

    // New ray_new dir calculations
    vec3_add calc_unnormalized_ray_dir(
        .clk(clk),
        .op_vld(shade_specular_result_vld),
        .a((material_type_dly == `MATERIAL_DIFFUSE) ? n_dly : ray_dir_add_dly),
        .b((material_type_dly == `MATERIAL_DIFFUSE) ? ray_dir_diffuse : ray_dir_specular),
        .result_vld(ray_dir_unnormalized_vld),
        .result(ray_dir_raw));

    // ray_sphere_intersect receives normalized ray.dir
    vec3_normalize #(.USE_DSP(FULL)) normalize_ray_dir(
        .clk(clk),
        .op_vld(ray_dir_unnormalized_vld),
        .a(ray_dir_raw),
        .result_vld(result_vld),
        .result(new_ray_dir));

    // Color update path
    shift_register #(.WIDTH(`SPHERES_WIDTH), .DELAY_COUNT(DLY_MATERIAL_NDX_COUNT)) dly_material_ndx(
        .clk(clk),
        .d(hit_info.sphere_id),
        .q(material_ndx_dly));

    // Delay rayIdx for color fetch
    shift_register #(.WIDTH(`RPP_WIDTH), .DELAY_COUNT(DLY_RAY_NDX_COLOR_FETCH_COUNT)) dly_ray_ndx_color_fetch(
        .clk(clk),
        .d(ray_ctr_reg[`RPP_WIDTH-1:0]),
        .q(ray_color_fetch_ndx_dly));

    shift_register #(.WIDTH(1), .DELAY_COUNT(DLY_COLOR_UPDATE_OP_VLD_COUNT)) dly_color_update_op_vld(
        .clk(clk),
        .d(loop_active),
        .q(color_update_op_vld_dly));

    // Delay Lp post mul for the adder
    shift_register #(.WIDTH($bits(vec3_t)), .DELAY_COUNT(`LATENCY_FP32_MULTIPLIER)) dly_l_current(
        .clk(clk),
        .d(ray_l_current),
        .q(ray_l_dly));

    // Align F[rayIdx] output with L[rayIdx]
    shift_register #(.WIDTH($bits(vec3_t)), .DELAY_COUNT(`LATENCY_FP32_ADDER)) dly_lp_result(
        .clk(clk),
        .d(mul_fp_albedo_result),
        .q(ray_f_new));

    // Materials data
    sync_rom #(.ROM_FILE("material_data.mem"), .ADDR_WIDTH(`SPHERES_WIDTH), .DATA_WIDTH($bits(material_info_t))) materials_rom(
    	.clk(clk),
        .addr(material_ndx_dly),
        .data(material_info));
    
    // Vec3Mul(Fp, emission)
    vec3_mul mul_fp_emission(
        .clk(clk),
        .op_vld(color_update_op_vld_dly),
        .a(ray_f_current),
        .b(ray_hit_material_dly ? material_info.emission : {32'h3f000000, 32'h3f333333, 32'h3f800000}), // Background color: vec3(.5, .7, .1)
        .result_vld(mul_fp_vld),
        .result(mul_fp_emission_result));

    // Vec3Mul(Lp, albedo)
    vec3_mul mul_fp_albedo(
        .clk(clk),
        .op_vld(color_update_op_vld_dly),
        .a(ray_f_current),
        .b(ray_hit_material_dly ? material_info.albedo : {32'h0, 32'h0, 32'h0}),
        .result_vld(),
        .result(mul_fp_albedo_result));

    // L[rayIdx] = Lp + Fp * emission
    vec3_add add_lp_fp_result(
        .clk(clk),
        .op_vld(mul_fp_vld),
        .a(ray_l_dly),
        .b(mul_fp_emission_result),
        .result_vld(),
        .result(ray_l_new));

    // Outputs
    assign busy = busy_reg;
    assign fetch_hit_info_ndx = ray_ctr_reg[`RPP_WIDTH-1:0];
    assign fetch_ray_color_ndx = ray_color_fetch_ndx_dly;
    assign store_data_wr_en = result_vld;
    assign ray_hit = ray_hit_output_dly;
    assign store_data_ndx = ray_ndx_reg;
    assign ray_new.dir.x = new_ray_dir.x;
    assign ray_new.dir.y = new_ray_dir.y;
    // If no-hit, output NaN for ray.dir.z to terminate in next bounce
    assign ray_new.dir.z = ray_hit_output_dly ? new_ray_dir.z : 32'hFFFFFFFF;
endmodule