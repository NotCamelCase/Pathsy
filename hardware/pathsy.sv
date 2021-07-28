`include "defines.svh"

module pathsy
(
    input logic                         clk, rst,
    input logic                         start,
    input logic[`BOUNCES_WIDTH-1:0]     max_bounces,
    output logic                        pathsy_busy,
    output logic                        output_busy,
    output logic                        frame_complete,
    // DDR3 inf
    input logic                         ddr3_app_rdy,
    input logic                         ddr3_app_wdf_rdy,
    output logic                        ddr3_app_en,
    output logic                        ddr3_wdf_wr_en,
    output logic                        ddr3_wdf_end,
    output logic[`FB_ADDR_WIDTH-1:0]    ddr3_app_addr,
    output logic[63:0]                  ddr3_wdf_data
);
    typedef enum {
        IDLE,
        ISSUE_PATH_TRACE,
        PATH_TRACE_PIXEL
    } state_t;

    typedef enum {
        PIXEL_OUTPUT_IDLE,
        ISSUE_PIXEL_OUTPUT,
        OUTPUT_PIXELS
    } output_state_t;

    state_t                     state_reg, state_nxt;
    output_state_t              output_state_reg, output_state_nxt;
    logic                       start_output_calc;

    logic[`PX_WIDTH-1:0]        px_reg, px_nxt;
    logic[`PY_WIDTH-1:0]        py_reg, py_nxt;

    // path_trace_pixel I/O
    logic                       path_trace_pixel_start;
    logic                       path_trace_pixel_busy;
    logic                       path_trace_pixel_ray_color_wr_en;
    logic[`RPP_WIDTH-1:0]       path_trace_pixel_ray_color_update_ndx;
    vec3_t                      path_trace_pixel_ray_color;

    // output_pixels I/O
    logic                       output_pixels_start;
    logic                       output_pixels_busy;
    logic[`RPP_WIDTH-1:0]       output_pixels_ray_color_fetch_ndx;
    vec3_t                      output_pixels_ray_color;

    // Registers
    always_ff @(posedge clk)
    begin
        if (rst)
        begin
            state_reg <= IDLE;
        end
        else
        begin
            state_reg <= state_nxt;
            px_reg <= px_nxt;
            py_reg <= py_nxt;
        end
    end

    always_ff @(posedge clk)
    begin
        if (rst)
            output_state_reg <= PIXEL_OUTPUT_IDLE;
        else
            output_state_reg <= output_state_nxt;
    end

    path_trace_pixel pt(
        .clk(clk),
        .rst(rst),
        .start(path_trace_pixel_start),
        .x(px_reg),
        .y(py_reg),
        .max_bounces(max_bounces),
        .busy(path_trace_pixel_busy),
        .ray_color_wr_en(path_trace_pixel_ray_color_wr_en),
        .ray_color_update_ndx(path_trace_pixel_ray_color_update_ndx),
        .ray_color(path_trace_pixel_ray_color));

    output_pixels pt_pixels(
        .clk(clk),
        .rst(rst),
        .start(output_pixels_start),
        .ray_color(output_pixels_ray_color),
        .busy(output_pixels_busy),
        .render_complete(frame_complete),
        .ray_color_fetch_ndx(output_pixels_ray_color_fetch_ndx),
        .ddr3_app_rdy(ddr3_app_rdy),
        .ddr3_app_wdf_rdy(ddr3_app_wdf_rdy),
        .ddr3_app_en(ddr3_app_en),
        .ddr3_wdf_wr_en(ddr3_wdf_wr_en),
        .ddr3_wdf_end(ddr3_wdf_end),
        .ddr3_app_addr(ddr3_app_addr),
        .ddr3_wdf_data(ddr3_wdf_data));

    bram_1r1w #(.ADDR_WIDTH(`RPP_WIDTH), .DATA_WIDTH($bits(vec3_t))) ray_color_buffer(
        .clk(clk),
        .wr_en(path_trace_pixel_ray_color_wr_en),
        .rd_addr(output_pixels_ray_color_fetch_ndx),
        .wr_addr(path_trace_pixel_ray_color_update_ndx),
        .wr_data(path_trace_pixel_ray_color),
        .rd_data(output_pixels_ray_color));

    // FSM
    always_comb
    begin
        state_nxt = state_reg;

        px_nxt = px_reg;
        py_nxt = py_reg;

        path_trace_pixel_start = 1'b0;
        start_output_calc = 1'b0;

        case (state_reg)
            IDLE:
            begin
                if (start)
                begin
                    px_nxt = {`PX_WIDTH{1'b0}};
                    py_nxt = {`PY_WIDTH{1'b0}};
                    state_nxt = ISSUE_PATH_TRACE;
                end
            end

            ISSUE_PATH_TRACE:
            begin
                path_trace_pixel_start = 1'b1;
                state_nxt = PATH_TRACE_PIXEL;
            end

            PATH_TRACE_PIXEL:
            begin
                if (~path_trace_pixel_busy)
                begin
                    start_output_calc = 1'b1; // Let output_pixels work in parallel
                    if (px_reg == `SCREEN_WIDTH-1)
                    begin
                        if (py_reg == `SCREEN_HEIGHT-1)
                        begin
                            // Frame complete
                            state_nxt = IDLE;
                        end
                        else
                        begin
                            // Row complete, advanced onto the next one
                            px_nxt = {`PX_WIDTH{1'b0}};
                            py_nxt = py_reg + 1;
                            state_nxt = ISSUE_PATH_TRACE;
                        end
                    end
                    else
                    begin
                        // Pixel path-traced
                        px_nxt = px_reg + 1;
                        state_nxt = ISSUE_PATH_TRACE;
                    end
                end
            end
            
            default: state_nxt = IDLE;
        endcase
    end

    // Pixel output path
    always_comb
    begin
        output_state_nxt = output_state_reg;
        output_pixels_start = 1'b0;

        case (output_state_reg)
            PIXEL_OUTPUT_IDLE:
            begin
                if (start_output_calc)
                    output_state_nxt = ISSUE_PIXEL_OUTPUT;
            end

            ISSUE_PIXEL_OUTPUT:
            begin
                output_pixels_start = 1'b1;
                output_state_nxt = OUTPUT_PIXELS;
            end

            OUTPUT_PIXELS:
            begin
                // Output complete
                if (~output_pixels_busy)
                    output_state_nxt = PIXEL_OUTPUT_IDLE;
            end

            default: output_state_nxt = PIXEL_OUTPUT_IDLE;
        endcase    
    end

    // Outputs
    assign pathsy_busy = path_trace_pixel_busy;
    assign output_busy = output_pixels_busy;
endmodule