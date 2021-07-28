`include "defines.svh"

module trace_rays_stage
(
    input logic                     clk, rst,
    input logic                     start,
    output logic                    busy,
    output logic                    any_hit,
    // ray fetch inf
    input ray_t                     ray,
    output logic[`RPP_WIDTH-1:0]    fetch_ray_ndx,
    // hit_info store inf
    output logic                    hit_info_wr_en,
    output logic[`RPP_WIDTH-1:0]    update_hit_info_ndx,
    output hit_info_t               hit_info_new
);
    localparam  LATENCY_RAY_SPHERE_INTERSECT    = 52;
    localparam  DLY_SPHERE_CENTER_COUNT         = LATENCY_RAY_SPHERE_INTERSECT + `LATENCY_FP32_COMPARE;
    localparam  DLY_RAY_COUNT                   = LATENCY_RAY_SPHERE_INTERSECT + `LATENCY_FP32_COMPARE;

    localparam  HIT_EPSILON                     = 32'h38d1b717; // 1e-4
    localparam  MAX_FLOAT                       = 32'h7f7fffff; // 3.4028234663852886e+38

    // Control/status signals
    logic                           busy_reg, busy_nxt;
    logic                           delay_reg, delay_nxt;
    logic                           any_hit_reg, any_hit_nxt;
    logic                           invalidate_hit, valid_hit, loop_active;
    logic                           obj_ctr_loop_done, obj_ndx_loop_done;

    // Loop counters
    logic[`SPHERES_WIDTH-1:0]       obj_ctr_reg, obj_ctr_nxt;
    logic[`RPP_WIDTH:0]             ray_ctr_reg, ray_ctr_nxt;

    // rayIdx, objIdx
    logic[`SPHERES_WIDTH-1:0]       obj_ndx_reg, obj_ndx_nxt;
    logic[`RPP_WIDTH-1:0]           ray_ndx_reg, ray_ndx_nxt;

    // sphere geometry
    sphere_t                        sphere_geo_data;

    // ray_sphere_intersect
    logic                           ray_sphere_intersect_result_vld;
    fp32_t                          ray_sphere_intersect_t0;
    fp32_t                          ray_sphere_intersect_t1;

    // ray_hit_info
    logic                           hit_info_wr_en_reg, hit_info_wr_en_nxt;
    hit_info_t                      hit_info_current_reg, hit_info_current_nxt;
    hit_info_t                      hit_info_new_reg, hit_info_new_nxt;

    // hit checks
    logic                           t0_min_bound_vld, t0_max_bound_vld;
    logic                           t1_min_bound_vld, t1_max_bound_vld;
    logic                           t0_min_bound, t0_max_bound;
    logic                           t1_min_bound, t1_max_bound;
    logic                           t0_vld, t1_vld, hit;

    // Delayed signals
    logic                           loop_active_dly, result_vld;
    logic[`RPP_WIDTH-1:0]           ray_ndx_dly;
    fp32_t                          t0_dly, t1_dly;
    vec3_t                          sphere_center_dly;
    ray_t                           ray_dly;

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
            delay_reg <= delay_nxt;
            obj_ctr_reg <= obj_ctr_nxt;
            ray_ctr_reg <= ray_ctr_nxt;
            obj_ndx_reg <= obj_ndx_nxt;
            ray_ndx_reg <= ray_ndx_nxt;
            any_hit_reg <= any_hit_nxt;
        end
    end

    // Control path
    always_comb
    begin
        busy_nxt = busy_reg;
        delay_nxt = delay_reg;

        obj_ctr_nxt = obj_ctr_reg;
        ray_ctr_nxt = ray_ctr_reg;
        obj_ndx_nxt = obj_ndx_reg;
        ray_ndx_nxt = ray_ndx_reg;

        any_hit_nxt = any_hit_reg;

        obj_ctr_loop_done = 1'b0;
        obj_ndx_loop_done = 1'b0;
        loop_active = 1'b0;
        invalidate_hit = 1'b0;

        if (start)
        begin
            // New request, initialize the index and loop counters and check for intersection
            obj_ctr_nxt = {`SPHERES_WIDTH{1'b0}};
            ray_ctr_nxt = {`RPP_WIDTH+1{1'b0}};
            obj_ndx_nxt = {`SPHERES_WIDTH{1'b0}};
            ray_ndx_nxt = {`RPP_WIDTH{1'b0}};
            any_hit_nxt = 1'b0;
            invalidate_hit = 1'b1;
            delay_nxt = 1'b0;
            busy_nxt = 1'b1;
        end
        else if (busy_reg)
        begin
            // This is super hacky, but it works!!!
            // Because the latency of ray-sphere intersect core is even,
            // DONE ack arrives when a delay was inserted in the previous cycle and
            // as a result, 'else' block is evaluated as should be.
            // Otherwise, it'd hang as loop conditions wouldn't be considered.

            if (~delay_reg)
            begin
                loop_active = (ray_ctr_reg < `RPP);
            end
            else
            begin                
                obj_ctr_loop_done = (obj_ctr_reg == `NUM_SPHERES-1);
                obj_ndx_loop_done = (obj_ndx_reg == `NUM_SPHERES-1);

                obj_ctr_nxt = obj_ctr_loop_done ? {`SPHERES_WIDTH{1'b0}} : (obj_ctr_reg + 1);
                ray_ctr_nxt = obj_ctr_loop_done ? (ray_ctr_reg + 1) : ray_ctr_reg;

                obj_ndx_nxt = result_vld ? (obj_ndx_loop_done ? {`SPHERES_WIDTH{1'b0}} : (obj_ndx_reg + 1)) : obj_ndx_reg;
                ray_ndx_nxt = (result_vld & obj_ndx_loop_done) ? (ray_ndx_reg + 1) : ray_ndx_reg;

                any_hit_nxt = valid_hit ? 1'b1 : any_hit_reg;
                
                invalidate_hit = obj_ndx_loop_done;

                // Done if RPP x NUM_SPHERES intersections were finished
                if ((ray_ndx_reg == `RPP-1) & obj_ndx_loop_done)
                    busy_nxt = 1'b0;
            end

            // Insert an idle cycle to compensate for FP32_CMP latency on feedback path
            delay_nxt = ~delay_reg;
        end
    end

    // Delay loop active post fetching ray, to align w/ ray-sphere intersection
    shift_register #(.WIDTH(1), .DELAY_COUNT(1)) dly_loop_active(
        .clk(clk),
        .d(loop_active),
        .q(loop_active_dly));

    // Delay rayIdx to update ray hit info
    shift_register #(.WIDTH(`RPP_WIDTH), .DELAY_COUNT(1)) dly_ray_ndx(
        .clk(clk),
        .d(ray_ndx_reg),
        .q(ray_ndx_dly));

    // Fetch sphere geometry
    sync_rom #(.ROM_FILE("sphere_geo.mem"), .ADDR_WIDTH(`SPHERES_WIDTH), .DATA_WIDTH($bits(sphere_t))) sphere_geo_rom(
        .clk(clk),
        .addr(obj_ctr_reg),
        .data(sphere_geo_data));

    // Delay sphere center for hit info update
    shift_register #(.WIDTH($bits(vec3_t)), .DELAY_COUNT(DLY_SPHERE_CENTER_COUNT)) dly_sphere_center_count(
        .clk(clk),
        .d(sphere_geo_data.center),
        .q(sphere_center_dly));

    // Delay traced ray for hit_info output
    shift_register #(.WIDTH($bits(ray_t)), .DELAY_COUNT(DLY_RAY_COUNT)) dly_ray(
        .clk(clk),
        .d(ray),
        .q(ray_dly));

    // Perform ray-sphere intersection
    ray_sphere_intersect ray_sphere_intersect_unit(
        .clk(clk),
        .op_vld(loop_active_dly),
        .ray(ray),
        .center(sphere_geo_data.center),
        .radius_2(sphere_geo_data.radius_squared),
        .result_vld(ray_sphere_intersect_result_vld),
        .t0(ray_sphere_intersect_t0),
        .t1(ray_sphere_intersect_t1));

    // Delay intersection results post hit checks
    shift_register #(.WIDTH(32), .DELAY_COUNT(`LATENCY_FP32_COMPARE)) dly_t0(
        .clk(clk),
        .d(ray_sphere_intersect_t0),
        .q(t0_dly));

    shift_register #(.WIDTH(32), .DELAY_COUNT(`LATENCY_FP32_COMPARE)) dly_t1(
        .clk(clk),
        .d(ray_sphere_intersect_t1),
        .q(t1_dly));

    // t0 > HIT_EPSILON
    fp32_cmp #(.OP(GT)) t0_min_bound_cmp(
        .clk(clk),
        .op_vld(ray_sphere_intersect_result_vld),
        .a(ray_sphere_intersect_t0),
        .b(HIT_EPSILON),
        .result_vld(t0_min_bound_vld),
        .result(t0_min_bound));

    // t0 < hitInfo.t
    fp32_cmp #(.OP(LT)) t0_max_bound_cmp(
        .clk(clk),
        .op_vld(ray_sphere_intersect_result_vld),
        .a(ray_sphere_intersect_t0),
        .b(hit_info_current_reg.t),
        .result_vld(t0_max_bound_vld),
        .result(t0_max_bound));

    // t1 > HIT_EPSILON
    fp32_cmp #(.OP(GT)) t1_min_bound_cmp(
        .clk(clk),
        .op_vld(ray_sphere_intersect_result_vld),
        .a(ray_sphere_intersect_t1),
        .b(HIT_EPSILON),
        .result_vld(t1_min_bound_vld),
        .result(t1_min_bound));

    // t1 < hitInfo.t
    fp32_cmp #(.OP(LT)) t1_max_bound_cmp(
        .clk(clk),
        .op_vld(ray_sphere_intersect_result_vld),
        .a(ray_sphere_intersect_t1),
        .b(hit_info_current_reg.t),
        .result_vld(t1_max_bound_vld),
        .result(t1_max_bound));

    // hit_info
    always_ff @(posedge clk)
    begin
        hit_info_current_reg <= hit_info_current_nxt;
        hit_info_new_reg <= hit_info_new_nxt;
        hit_info_wr_en_reg <= hit_info_wr_en_nxt;
    end

    // Hit validity
    assign t0_vld = (t0_min_bound & t0_max_bound);
    assign t1_vld = (t1_min_bound & t1_max_bound);
    assign hit = t0_vld | t1_vld;
    assign valid_hit = t1_max_bound_vld & hit;

    // write-enable hit info only at the end of inner loop
    assign hit_info_wr_en_nxt = obj_ndx_loop_done;

    // Compose new hit info
    always_comb
    begin
        hit_info_current_nxt = hit_info_current_reg;
        hit_info_new_nxt = hit_info_new_reg;

        if (invalidate_hit) // Need to invalidate the hit info before each iteration of the outer loop
        begin
            hit_info_current_nxt.hit = 1'b0;
            hit_info_current_nxt.t = MAX_FLOAT;

            // Last object, update hit info to be written
            if (valid_hit)
            begin
                hit_info_new_nxt.hit = 1'b1;
                hit_info_new_nxt.sphere_id = obj_ndx_reg;
                hit_info_new_nxt.t = t0_vld ? t0_dly : t1_dly;
                hit_info_new_nxt.sphere_center = sphere_center_dly;
                hit_info_new_nxt.ray = ray_dly;
            end
            else
            begin
                hit_info_new_nxt.hit = hit_info_current_reg.hit;
            end
        end
        else if (valid_hit)
        begin
            hit_info_current_nxt.hit = 1'b1;
            hit_info_current_nxt.sphere_id = obj_ndx_reg;
            hit_info_current_nxt.t = t0_vld ? t0_dly : t1_dly;
            hit_info_current_nxt.sphere_center = sphere_center_dly;
            hit_info_current_nxt.ray = ray_dly;

            hit_info_new_nxt.hit = 1'b1;
            hit_info_new_nxt.sphere_id = obj_ndx_reg;
            hit_info_new_nxt.t = t0_vld ? t0_dly : t1_dly;
            hit_info_new_nxt.sphere_center = sphere_center_dly;
            hit_info_new_nxt.ray = ray_dly;
        end
    end
    
    // BRAM read/writes are synchronous, no need to stall
    assign result_vld = t1_max_bound_vld;

    // Outputs
    assign busy = busy_reg;
    assign any_hit = any_hit_reg;
    assign fetch_ray_ndx = ray_ctr_reg[`RPP_WIDTH-1:0];
    assign hit_info_wr_en = hit_info_wr_en_reg;
    assign hit_info_new = hit_info_new_reg;
    assign update_hit_info_ndx = ray_ndx_dly;
endmodule