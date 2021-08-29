`include "defines.svh"

module path_trace_pixel
(
    input logic                     clk, rst,
    input logic                     start,
    input logic[`PX_WIDTH-1:0]      x,
    input logic[`PY_WIDTH-1:0]      y,
    input logic[`BOUNCES_WIDTH-1:0] max_bounces,
    output logic                    busy,
    output logic                    ray_color_wr_en,
    output logic[`RPP_WIDTH-1:0]    ray_color_update_ndx,
    output vec3_t                   ray_color
);
    // Min # of rays traced by TR after which SR can make forward progress without inducing a data race
    localparam  TR_STALL_SR_THRESHOLD   = 58;

    // This delay is necessary due to registered BRAM writes into the secondary ray buffer by SR
    localparam  SR_STALL_TR_THRESHOLD   = 2;

    // FSM for generate_primary_rays_stage
    typedef enum {
        GPR_IDLE,
        GPR_ISSUE_GEN_RAYS,
        GPR_GEN_RAYS
    } gpr_state_t;

    // FSM for trace_rays_stage
    typedef enum {
        TR_IDLE,
        TR_ISSUE_FIRST_BOUNCE,
        TR_FIRST_BOUNCE,
        TR_STALL,
        TR_ISSUE_SUB_BOUNCE,
        TR_SUB_BOUNCE
    } tr_state_t;

    // FSM for shade_rays_stage
    typedef enum {
        SR_IDLE,
        SR_ISSUE_FIRST_BOUNCE,
        SR_FIRST_BOUNCE,
        SR_STALL,
        SR_ISSUE_SUB_BOUNCE,
        SR_SUB_BOUNCE
    } sr_state_t;

    // FSMs
    logic                       busy_reg, busy_nxt;
    gpr_state_t                 gpr_state_reg, gpr_state_nxt;
    tr_state_t                  tr_state_reg, tr_state_nxt;
    sr_state_t                  sr_state_reg, sr_state_nxt;

    // Control/status signals
    logic                       start_gpr;
    logic                       gpr_stall_tr;
    logic                       tr_stall_sr;
    logic                       sr_stall_tr;

    // generate_primary_rays_stage I/O
    logic                       generate_primary_rays_stage_start;
    logic                       generate_primary_rays_stage_busy;
    logic[`PX_WIDTH-1:0]        generate_primary_rays_stage_x;
    logic[`PY_WIDTH-1:0]        generate_primary_rays_stage_y;
    logic                       generate_primary_rays_stage_ray_wr_en;
    logic[`RPP_WIDTH-1:0]       generate_primary_rays_stage_ray_ndx;
    ray_t                       generate_primary_rays_stage_prim_ray;
    // Internal
    logic                       gpr_terminated_reg, gpr_terminated_nxt;

    // trace_rays_stage I/O
    logic                       trace_rays_stage_start;
    logic                       trace_rays_stage_busy;
    logic                       trace_rays_stage_any_hit;
    ray_t                       trace_rays_stage_ray;
    logic[`RPP_WIDTH-1:0]       trace_rays_stage_fetch_ray_ndx;
    logic                       trace_rays_stage_hit_info_wr_en;
    logic[`RPP_WIDTH-1:0]       trace_rays_stage_update_hit_info_ndx;
    hit_info_t                  trace_rays_stage_hit_info_new;
    ray_t                       ray_primary, ray_secondary;
    // Internal
    logic                       tr_first_bounce_reg, tr_first_bounce_nxt;
    logic                       tr_terminated_reg, tr_terminated_nxt;
    logic[`BOUNCES_WIDTH-1:0]   tr_bounce_ctr_reg, tr_bounce_ctr_nxt;

    // shade_rays_stage I/O
    logic                       shade_rays_stage_start;
    logic                       shade_rays_stage_busy;
    hit_info_t                  shade_rays_stage_hit_info;
    vec3_t                      shade_rays_stage_ray_f_current;
    vec3_t                      shade_rays_stage_ray_l_current;
    logic[`RPP_WIDTH-1:0]       shade_rays_stage_fetch_hit_info_ndx;
    logic[`RPP_WIDTH-1:0]       shade_rays_stage_fetch_ray_color_ndx;
    logic                       shade_rays_stage_store_data_wr_en;
    logic                       shade_rays_stage_ray_hit;
    logic[`RPP_WIDTH-1:0]       shade_rays_stage_store_data_ndx;
    ray_t                       shade_rays_stage_ray_new;
    vec3_t                      shade_rays_stage_ray_f_new;
    vec3_t                      shade_rays_stage_ray_l_new;
    // Internal
    logic                       sr_first_bounce_reg, sr_first_bounce_nxt;
    logic                       sr_terminated_reg, sr_terminated_nxt;
    logic[`BOUNCES_WIDTH-1:0]   sr_bounce_ctr_reg, sr_bounce_ctr_nxt;
    vec3_t                      sr_ray_l_current, sr_ray_f_current;

    generate_primary_rays_stage gpr(
        .clk(clk),
        .rst(rst),
        .start(generate_primary_rays_stage_start),
        .x(x),
        .y(y),
        .busy(generate_primary_rays_stage_busy),
        .ray_wr_en(generate_primary_rays_stage_ray_wr_en),
        .ray_ndx(generate_primary_rays_stage_ray_ndx),
        .prim_ray(generate_primary_rays_stage_prim_ray));

    trace_rays_stage tr(
        .clk(clk),
        .rst(rst),
        .start(trace_rays_stage_start),
        .busy(trace_rays_stage_busy),
        .any_hit(trace_rays_stage_any_hit),
        .ray(trace_rays_stage_ray),
        .fetch_ray_ndx(trace_rays_stage_fetch_ray_ndx),
        .hit_info_wr_en(trace_rays_stage_hit_info_wr_en),
        .update_hit_info_ndx(trace_rays_stage_update_hit_info_ndx),
        .hit_info_new(trace_rays_stage_hit_info_new));

    shade_rays_stage sr(
        .clk(clk),
        .rst(rst),
        .start(shade_rays_stage_start),
        .busy(shade_rays_stage_busy),
        .hit_info(shade_rays_stage_hit_info),
        .ray_f_current(shade_rays_stage_ray_f_current),
        .ray_l_current(shade_rays_stage_ray_l_current),
        .fetch_hit_info_ndx(shade_rays_stage_fetch_hit_info_ndx),
        .fetch_ray_color_ndx(shade_rays_stage_fetch_ray_color_ndx),
        .store_data_wr_en(shade_rays_stage_store_data_wr_en),
        .store_data_ndx(shade_rays_stage_store_data_ndx),
        .ray_new(shade_rays_stage_ray_new),
        .ray_f_new(shade_rays_stage_ray_f_new),
        .ray_l_new(shade_rays_stage_ray_l_new));

    bram_1r1w #(.ADDR_WIDTH(`RPP_WIDTH), .DATA_WIDTH($bits(ray_t))) prim_ray_buffer(
        .clk(clk),
        .wr_en(generate_primary_rays_stage_ray_wr_en),
        .rd_addr(trace_rays_stage_fetch_ray_ndx),
        .wr_addr(generate_primary_rays_stage_ray_ndx),
        .wr_data(generate_primary_rays_stage_prim_ray),
        .rd_data(ray_primary));

    bram_1r1w #(.ADDR_WIDTH(`RPP_WIDTH), .DATA_WIDTH($bits(ray_t))) sec_ray_buffer(
        .clk(clk),
        .wr_en(shade_rays_stage_store_data_wr_en),
        .rd_addr(trace_rays_stage_fetch_ray_ndx),
        .wr_addr(shade_rays_stage_store_data_ndx),
        .wr_data(shade_rays_stage_ray_new),
        .rd_data(ray_secondary));

    bram_1r1w #(.ADDR_WIDTH(`RPP_WIDTH), .DATA_WIDTH($bits(hit_info_t))) hit_info_buffer(
        .clk(clk),
        .wr_en(trace_rays_stage_hit_info_wr_en),
        .rd_addr(shade_rays_stage_fetch_hit_info_ndx),
        .wr_addr(trace_rays_stage_update_hit_info_ndx),
        .wr_data(trace_rays_stage_hit_info_new),
        .rd_data(shade_rays_stage_hit_info));

    bram_1r1w #(.ADDR_WIDTH(`RPP_WIDTH), .DATA_WIDTH($bits(vec3_t))) ray_l_buffer(
        .clk(clk),
        .wr_en(shade_rays_stage_store_data_wr_en),
        .rd_addr(shade_rays_stage_fetch_ray_color_ndx),
        .wr_addr(shade_rays_stage_store_data_ndx),
        .wr_data(shade_rays_stage_ray_l_new),
        .rd_data(sr_ray_l_current));

    bram_1r1w #(.ADDR_WIDTH(`RPP_WIDTH), .DATA_WIDTH($bits(vec3_t))) ray_f_buffer(
        .clk(clk),
        .wr_en(shade_rays_stage_store_data_wr_en),
        .rd_addr(shade_rays_stage_fetch_ray_color_ndx),
        .wr_addr(shade_rays_stage_store_data_ndx),
        .wr_data(shade_rays_stage_ray_f_new),
        .rd_data(sr_ray_f_current));

    // Registers
    always_ff @(posedge clk)
    begin
        if (rst)
        begin
            busy_reg <= 1'b0;
            gpr_state_reg <= GPR_IDLE;
            gpr_terminated_reg <= 1'b0;
            tr_state_reg <= TR_IDLE;
            tr_terminated_reg <= 1'b0;
            sr_state_reg <= SR_IDLE;
            sr_terminated_reg <= 1'b0;
        end
        else
        begin
            busy_reg <= busy_nxt;
            gpr_state_reg <= gpr_state_nxt;
            gpr_terminated_reg <= gpr_terminated_nxt;
            tr_state_reg <= tr_state_nxt;
            tr_bounce_ctr_reg <= tr_bounce_ctr_nxt;
            tr_first_bounce_reg <= tr_first_bounce_nxt;
            tr_terminated_reg <= tr_terminated_nxt;
            sr_state_reg <= sr_state_nxt;
            sr_bounce_ctr_reg <= sr_bounce_ctr_nxt;
            sr_first_bounce_reg <= sr_first_bounce_nxt;
            sr_terminated_reg <= sr_terminated_nxt;
        end
    end

    // Deliver primary rays to TR on first bounce only
    assign trace_rays_stage_ray = tr_first_bounce_reg ? ray_primary : ray_secondary;

    // On first bounce, deliver initial L/F values
    assign shade_rays_stage_ray_l_current = sr_first_bounce_reg ? {32'h0, 32'h0, 32'h0} : sr_ray_l_current;
    assign shade_rays_stage_ray_f_current = sr_first_bounce_reg ? {32'h3f800000, 32'h3f800000, 32'h3f800000} : sr_ray_f_current;

    // Control path
    always_comb
    begin
        busy_nxt = busy_reg;

        start_gpr = 1'b0;

        if (start)
        begin
            start_gpr = 1'b1;
            busy_nxt = 1'b1;
        end
        else if (busy_reg)
        begin
            if (gpr_terminated_reg & tr_terminated_reg & sr_terminated_reg)
                busy_nxt = 1'b0; // End of pixel pipe
        end
    end

    // GPR FSM
    always_comb
    begin
        gpr_state_nxt = gpr_state_reg;

        gpr_terminated_nxt = gpr_terminated_reg;

        generate_primary_rays_stage_start = 1'b0;

        gpr_stall_tr = 1'b1;

        case (gpr_state_reg)
            GPR_IDLE:
            begin
                if (start_gpr)
                begin
                    gpr_terminated_nxt = 1'b0;
                    gpr_state_nxt = GPR_ISSUE_GEN_RAYS;
                end
            end

            GPR_ISSUE_GEN_RAYS:
            begin
                generate_primary_rays_stage_start = 1'b1;
                gpr_state_nxt = GPR_GEN_RAYS;
            end

            GPR_GEN_RAYS:
            begin
                if (~generate_primary_rays_stage_busy)
                begin
                    gpr_terminated_nxt = 1'b1;
                    gpr_state_nxt = GPR_IDLE;
                end
                
                gpr_stall_tr = (generate_primary_rays_stage_ray_ndx == 0);
            end

            default: gpr_state_nxt = GPR_IDLE;
        endcase
    end

    // TR FSM
    always_comb
    begin
        tr_state_nxt = tr_state_reg;

        trace_rays_stage_start = 1'b0;

        tr_bounce_ctr_nxt = tr_bounce_ctr_reg;
        tr_first_bounce_nxt = tr_first_bounce_reg;
        tr_terminated_nxt = tr_terminated_reg;

        tr_stall_sr = ~(trace_rays_stage_hit_info_wr_en & (trace_rays_stage_update_hit_info_ndx > TR_STALL_SR_THRESHOLD));

        case (tr_state_reg)
            TR_IDLE:
            begin
                if (~gpr_stall_tr)
                    tr_state_nxt = TR_ISSUE_FIRST_BOUNCE;
            end

            TR_ISSUE_FIRST_BOUNCE:
            begin
                tr_bounce_ctr_nxt = 0;
                tr_first_bounce_nxt = 1'b1;
                tr_terminated_nxt = 1'b0;
                trace_rays_stage_start = 1'b1;
                tr_state_nxt = TR_FIRST_BOUNCE;
            end

            TR_FIRST_BOUNCE:
            begin
                if (~trace_rays_stage_busy) // End of first bounce
                begin
                    if (trace_rays_stage_any_hit) // If any hit was registered
                    begin
                        tr_state_nxt = TR_STALL; // Stall until SR generates new rays to trace
                    end
                    else // No hits
                    begin
                        tr_terminated_nxt = 1'b1; // To terminate after SR completes
                        tr_state_nxt = TR_IDLE;
                    end
                end
            end

            TR_STALL:
            begin
                if (~sr_stall_tr)
                    tr_state_nxt = TR_ISSUE_SUB_BOUNCE;
            end

            TR_ISSUE_SUB_BOUNCE:
            begin
                tr_bounce_ctr_nxt = tr_bounce_ctr_reg + 1;
                tr_first_bounce_nxt = 1'b0;
                trace_rays_stage_start = 1'b1;
                tr_state_nxt = TR_SUB_BOUNCE;
            end

            TR_SUB_BOUNCE:
            begin
                if (~trace_rays_stage_busy) // End of next bounce
                begin
                    if ((tr_bounce_ctr_reg != max_bounces) & trace_rays_stage_any_hit)
                    begin
                        tr_state_nxt = TR_STALL; // There were hits and bounce<maxBounces, stall until SR is ready
                    end
                    else
                    begin
                        tr_terminated_nxt = 1'b1; // No hits or maxBounces reached, terminate after SR finishes
                        tr_state_nxt = TR_IDLE;
                    end
                end
            end

            default: tr_state_nxt = TR_IDLE;
        endcase 
    end

    // SR FSM
    always_comb
    begin
        sr_state_nxt = sr_state_reg;

        shade_rays_stage_start = 1'b0;

        sr_bounce_ctr_nxt = sr_bounce_ctr_reg;
        sr_first_bounce_nxt = sr_first_bounce_reg;
        sr_terminated_nxt = sr_terminated_reg;

        sr_stall_tr = ~(shade_rays_stage_store_data_wr_en & (shade_rays_stage_store_data_ndx > SR_STALL_TR_THRESHOLD));

        case (sr_state_reg)
            SR_IDLE:
            begin
                if (~tr_stall_sr)
                    sr_state_nxt = SR_ISSUE_FIRST_BOUNCE;
            end

            SR_ISSUE_FIRST_BOUNCE:
            begin
                sr_bounce_ctr_nxt = 0;
                sr_first_bounce_nxt = 1'b1;
                sr_terminated_nxt = 1'b0;
                shade_rays_stage_start = 1'b1;
                sr_state_nxt = SR_FIRST_BOUNCE;
            end

            SR_FIRST_BOUNCE:
            begin
                if (~shade_rays_stage_busy) // End of first bounce
                begin
                    if (~tr_terminated_reg) // TR has yet to terminate
                    begin
                        sr_state_nxt = SR_STALL; // Stall until TR fills hit_info buffer
                    end
                    else // SR to terminate
                    begin
                        sr_terminated_nxt = 1'b1;
                        sr_state_nxt = SR_IDLE;
                    end
                end
            end

            SR_STALL:
            begin
                if (~tr_stall_sr)
                    sr_state_nxt = SR_ISSUE_SUB_BOUNCE;
            end

            SR_ISSUE_SUB_BOUNCE:
            begin
                sr_bounce_ctr_nxt = sr_bounce_ctr_reg + 1;
                sr_first_bounce_nxt = 1'b0;
                shade_rays_stage_start = 1'b1;
                sr_state_nxt = SR_SUB_BOUNCE;
            end

            SR_SUB_BOUNCE:
            begin
                if (~shade_rays_stage_busy) // End of next bounce
                begin
                    if ((sr_bounce_ctr_reg != max_bounces) & (~tr_terminated_reg)) // TR hasn't terminated and bounces<maxBounces
                    begin
                        sr_state_nxt = SR_STALL; // Stall until TR generates new rays to shade
                    end
                    else // No hits or maxBounces reached, terminate SR
                    begin
                        sr_terminated_nxt = 1'b1;
                        sr_state_nxt = SR_IDLE;
                    end
                end
            end

            default: sr_state_nxt = SR_IDLE;
        endcase
    end

    // Outputs
    assign busy = busy_reg;
    assign ray_color_wr_en = shade_rays_stage_store_data_wr_en;
    assign ray_color_update_ndx = shade_rays_stage_store_data_ndx;
    assign ray_color = shade_rays_stage_ray_l_new;
endmodule