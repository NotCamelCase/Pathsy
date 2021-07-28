`include "defines.svh"

module output_pixels
(
    input logic                         clk, rst,
    input logic                         start,
    input vec3_t                        ray_color,
    output logic                        busy,
    output logic                        render_complete,
    output logic[`RPP_WIDTH-1:0]        ray_color_fetch_ndx,
    // DDR3 inf
    input logic                         ddr3_app_rdy,
    input logic                         ddr3_app_wdf_rdy,
    output logic                        ddr3_app_en,
    output logic                        ddr3_wdf_wr_en,
    output logic                        ddr3_wdf_end,
    output logic[`FB_ADDR_WIDTH-1:0]    ddr3_app_addr,
    output logic[63:0]                  ddr3_wdf_data
);
    localparam  PIXEL_BURST_LENGTH  = 8;
    localparam  PIXEL_BUFFER_LENGTH = PIXEL_BURST_LENGTH;
    localparam  PIXEL_BUFFER_WIDTH  = $clog2(PIXEL_BUFFER_LENGTH);

    localparam  COLOR_MUL_FACTOR    = 6'd1; // FloatToFixed(1/RPP, RPP)

    typedef enum {
        IDLE,
        SUM_UP_FETCH,
        SUM_UP_CVT,
        SUM_UP_DELAY,
        SUM_UP_ADD,
        COLOR_MUL,
        COLOR_CLAMP,
        COLOR_UPDATE_GAMMA_CORRECT
    } color_state_t;

    typedef enum {
        OUTPUT_IDLE,
        OUTPUT_ISSUE,
        STORE_PIXELS_DATA_LQW,
        STORE_PIXELS_DATA_UQW,
        STORE_PIXELS_COMMAND
    } output_state_t;

    color_state_t                   state_reg, state_nxt;
    output_state_t                  output_state_reg, output_state_nxt;
    logic                           busy_reg, busy_nxt;
    logic                           render_complete_reg, render_complete_nxt;
    logic                           start_output, pixel_buffer_update_en;
    logic[`RPP_WIDTH-1:0]           ray_ctr_reg, ray_ctr_nxt;

    logic[PIXEL_BUFFER_WIDTH-1:0]   pixel_ctr_reg, pixel_ctr_nxt;
    logic[15:0]                     pixel_buffer[PIXEL_BUFFER_LENGTH-1:0];

    // cvt fp32->Q4.9 I/O
    logic                           cvt_fp32_q4_9_vld;
    // Q4.9
    logic[15:0]                     cvt_fp32_q4_9_result_x;
    logic[15:0]                     cvt_fp32_q4_9_result_y;
    logic[15:0]                     cvt_fp32_q4_9_result_z;

    // Q9.9 color accumulators
    logic[17:0]                     pr_reg, pr_nxt;
    logic[17:0]                     pg_reg, pg_nxt;
    logic[17:0]                     pb_reg, pb_nxt;
    // Q9.15
    logic[23:0]                     pr_res_reg, pr_res_nxt, pr_tmp;
    logic[23:0]                     pg_res_reg, pg_res_nxt, pg_tmp;
    logic[23:0]                     pb_res_reg, pb_res_nxt, pb_tmp;

    // Gamma LUT
    logic[7:0]                      gamma_lut_addr_r, gamma_lut_addr_g, gamma_lut_addr_b;
    logic[7:0]                      pr_gamma_correct, pg_gamma_correct, pb_gamma_correct;

    // DDR3 write inf
    logic                           ddr3_app_en_reg, ddr3_app_en_nxt;
    logic                           ddr3_wr_en_reg, ddr3_wr_en_nxt;
    logic                           ddr3_wr_end_reg, ddr3_wr_end_nxt;
    logic[`FB_ADDR_WIDTH-1:0]       ddr3_wr_addr_reg, ddr3_wr_addr_nxt;
    logic[63:0]                     ddr3_wr_data_reg, ddr3_wr_data_nxt;

    // Registers
    always_ff @(posedge clk)
    begin
        if (rst)
        begin
            state_reg <= IDLE;
            output_state_reg <= OUTPUT_IDLE;
            render_complete_reg <= 1'b0;
            pixel_ctr_reg <= {PIXEL_BUFFER_WIDTH{1'b0}};
        end
        else
        begin
            state_reg <= state_nxt;
            output_state_reg <= output_state_nxt;
            busy_reg <= busy_nxt;
            render_complete_reg <= render_complete_nxt;
            ray_ctr_reg <= ray_ctr_nxt;
            pixel_ctr_reg <= pixel_ctr_nxt;
            pr_reg <= pr_nxt;
            pg_reg <= pg_nxt;
            pb_reg <= pb_nxt;
            pr_res_reg <= pr_res_nxt;
            pg_res_reg <= pg_res_nxt;
            pb_res_reg <= pb_res_nxt;
        end
    end

    always_ff @(posedge clk)
    begin
        if (rst)
        begin
            ddr3_wr_addr_reg <= {`FB_ADDR_WIDTH{1'b0}};
        end
        else
        begin
            ddr3_app_en_reg <= ddr3_app_en_nxt;
            ddr3_wr_en_reg <= ddr3_wr_en_nxt;
            ddr3_wr_end_reg <= ddr3_wr_end_nxt;
            ddr3_wr_addr_reg <= ddr3_wr_addr_nxt;
            ddr3_wr_data_reg <= ddr3_wr_data_nxt;
        end
    end

    // Buffer up gamma-corrected RGBX4 pixels to be sent to DRAM in a single burst
    always_ff @(posedge clk)
    begin
        if (pixel_buffer_update_en)
            pixel_buffer[pixel_ctr_reg] <= {4'b0, pb_gamma_correct[7:4], pg_gamma_correct[7:4], pr_gamma_correct[7:4]};
    end

    // Convert fp32 ray color input to Q4.9 (3 MSBs ignored)
    cvt_fp32_fixedp4_9 cvt_x(
        .aclk(clk),
        .s_axis_a_tvalid(cvt_fp32_q4_9_vld),
        .s_axis_a_tdata(ray_color.x),
        .m_axis_result_tvalid(),
        .m_axis_result_tdata(cvt_fp32_q4_9_result_x));

    cvt_fp32_fixedp4_9 cvt_y(
        .aclk(clk),
        .s_axis_a_tvalid(cvt_fp32_q4_9_vld),
        .s_axis_a_tdata(ray_color.y),
        .m_axis_result_tvalid(),
        .m_axis_result_tdata(cvt_fp32_q4_9_result_y));

    cvt_fp32_fixedp4_9 cvt_z(
        .aclk(clk),
        .s_axis_a_tvalid(cvt_fp32_q4_9_vld),
        .s_axis_a_tdata(ray_color.z),
        .m_axis_result_tvalid(),
        .m_axis_result_tdata(cvt_fp32_q4_9_result_z));

    // Gamma-correction LUTs
    sync_rom #(.ROM_FILE("gamma_lut.mem"), .ADDR_WIDTH($clog2(256)), .DATA_WIDTH(8)) gamma_lut_r(
        .clk(clk),
        .addr(gamma_lut_addr_r),
        .data(pr_gamma_correct));

    sync_rom #(.ROM_FILE("gamma_lut.mem"), .ADDR_WIDTH($clog2(256)), .DATA_WIDTH(8)) gamma_lut_g(
        .clk(clk),
        .addr(gamma_lut_addr_g),
        .data(pg_gamma_correct));

    sync_rom #(.ROM_FILE("gamma_lut.mem"), .ADDR_WIDTH($clog2(256)), .DATA_WIDTH(8)) gamma_lut_b(
        .clk(clk),
        .addr(gamma_lut_addr_b),
        .data(pb_gamma_correct));

    // Next-state logic
    always_comb
    begin
        state_nxt = state_reg;

        ray_ctr_nxt = ray_ctr_reg;
        pixel_ctr_nxt = pixel_ctr_reg;
        
        cvt_fp32_q4_9_vld = 1'b0;
        pixel_buffer_update_en = 1'b0;
        start_output = 1'b0;
        
        gamma_lut_addr_r = 8'b0;
        gamma_lut_addr_g = 8'b0;
        gamma_lut_addr_b = 8'b0;

        pr_nxt = pr_reg;
        pg_nxt = pg_reg;
        pb_nxt = pb_reg;

        pr_res_nxt = pr_res_reg;
        pg_res_nxt = pg_res_reg;
        pb_res_nxt = pb_res_reg;

        case (state_reg)
            IDLE:
            begin
                if (start)
                begin
                    ray_ctr_nxt = {`RPP_WIDTH{1'b0}};
                    pr_nxt = 18'(0);
                    pg_nxt = 18'(0);
                    pb_nxt = 18'(0);
                    state_nxt = SUM_UP_FETCH;
                end
            end

            SUM_UP_FETCH:
            begin
                state_nxt = SUM_UP_CVT;
            end

            SUM_UP_CVT:
            begin
                cvt_fp32_q4_9_vld = 1'b1;

                // Conversion core has 2 cycle latency!
                state_nxt = SUM_UP_DELAY;
            end

            SUM_UP_DELAY:
            begin
                state_nxt = SUM_UP_ADD;
            end

            SUM_UP_ADD:
            begin
                // Q9.9 + Q9.9
                pr_nxt = pr_reg + {2'b0, cvt_fp32_q4_9_result_x};
                pg_nxt = pg_reg + {2'b0, cvt_fp32_q4_9_result_y};
                pb_nxt = pb_reg + {2'b0, cvt_fp32_q4_9_result_z};

                if (ray_ctr_reg == `RPP-1) // All rays processed, prepare pixel color
                begin
                    state_nxt = COLOR_MUL;
                end
                else // Fetch next ray color
                begin
                    ray_ctr_nxt = ray_ctr_reg + 1;

                    state_nxt = SUM_UP_FETCH;
                end
            end

            COLOR_MUL:
            begin
                // Q9.9 x Q0.6
                pr_res_nxt = pr_reg * COLOR_MUL_FACTOR;
                pg_res_nxt = pg_reg * COLOR_MUL_FACTOR;
                pb_res_nxt = pb_reg * COLOR_MUL_FACTOR;

                state_nxt = COLOR_CLAMP;
            end

            COLOR_CLAMP:
            begin
                // Q9.15 -> Q9.8
                pr_tmp = pr_res_reg >> 7;
                pg_tmp = pg_res_reg >> 7;
                pb_tmp = pb_res_reg >> 7;

                // p > 255 ? 255 : p
                gamma_lut_addr_r = (|pr_tmp[16:8]) ? 8'hff : pr_tmp[7:0];
                gamma_lut_addr_g = (|pg_tmp[16:8]) ? 8'hff : pg_tmp[7:0];
                gamma_lut_addr_b = (|pb_tmp[16:8]) ? 8'hff : pb_tmp[7:0];

                state_nxt = COLOR_UPDATE_GAMMA_CORRECT;
            end

            COLOR_UPDATE_GAMMA_CORRECT:
            begin                
                pixel_buffer_update_en = 1'b1;
                if (pixel_ctr_reg == PIXEL_BUFFER_LENGTH-1)
                begin
                    pixel_ctr_nxt = {PIXEL_BUFFER_WIDTH{1'b0}};
                    start_output = 1'b1;
                end
                else
                begin
                    pixel_ctr_nxt = pixel_ctr_reg + 1;
                end

                state_nxt = IDLE;
            end

            default: state_nxt = IDLE;
        endcase
    end

    always_comb
    begin
        output_state_nxt = output_state_reg;
        busy_nxt = busy_reg;
        
        render_complete_nxt = render_complete_reg;

        ddr3_app_en_nxt = ddr3_app_en_reg;
        ddr3_wr_en_nxt = ddr3_wr_en_reg;
        ddr3_wr_end_nxt = ddr3_wr_end_reg;
        ddr3_wr_addr_nxt = ddr3_wr_addr_reg;
        ddr3_wr_data_nxt = ddr3_wr_data_reg;

        case (output_state_reg)
            OUTPUT_IDLE:
            begin
                busy_nxt = 1'b0;
                ddr3_app_en_nxt = 1'b0;
                ddr3_wr_en_nxt = 1'b0;
                ddr3_wr_end_nxt = 1'b0;
                if (start_output)
                begin
                    busy_nxt = 1'b1;
                    output_state_nxt = OUTPUT_ISSUE;
                end
            end

            OUTPUT_ISSUE:
            begin
                ddr3_wr_en_nxt = 1'b1;
                ddr3_wr_data_nxt = {pixel_buffer[0], pixel_buffer[1], pixel_buffer[2], pixel_buffer[3]}; // Asymmetric FIFO order
                output_state_nxt = STORE_PIXELS_DATA_LQW;
            end

            STORE_PIXELS_DATA_LQW:
            begin
                if (ddr3_app_wdf_rdy) // Write FIFO ack
                begin
                    ddr3_wr_end_nxt = 1'b1;
                    ddr3_wr_data_nxt = {pixel_buffer[4], pixel_buffer[5], pixel_buffer[6], pixel_buffer[7]}; // Asymmetric FIFO order
                    output_state_nxt = STORE_PIXELS_DATA_UQW;
                end
            end

            STORE_PIXELS_DATA_UQW:
            begin
                if (ddr3_app_wdf_rdy) // Write FIFO ack
                begin
                    ddr3_wr_en_nxt = 1'b0;
                    ddr3_wr_end_nxt = 1'b0;
                    ddr3_app_en_nxt = 1'b1;
                    output_state_nxt = STORE_PIXELS_COMMAND;
                end
            end

            STORE_PIXELS_COMMAND:
            begin
                if (ddr3_app_rdy) // Write command ack
                begin
                    ddr3_app_en_nxt = 1'b0;
                    if (ddr3_wr_addr_reg == 19'(`FB_MAX_ADDR-PIXEL_BURST_LENGTH))
                        render_complete_nxt = 1'b1; // Frame complete
                    else
                        ddr3_wr_addr_nxt = ddr3_wr_addr_reg + 19'(PIXEL_BURST_LENGTH);

                    output_state_nxt = OUTPUT_IDLE;
                end
            end
            
            default: output_state_nxt = OUTPUT_IDLE;
        endcase    
    end

    // Outputs
    assign ray_color_fetch_ndx = ray_ctr_reg[`RPP_WIDTH-1:0];
    assign busy = busy_reg;
    assign render_complete = render_complete_reg;
    assign ddr3_app_en = ddr3_app_en_reg;
    assign ddr3_wdf_wr_en = ddr3_wr_en_reg;
    assign ddr3_wdf_end = ddr3_wr_end_reg;
    assign ddr3_app_addr = ddr3_wr_addr_reg;
    assign ddr3_wdf_data = ddr3_wr_data_reg;
endmodule