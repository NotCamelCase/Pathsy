`include "defines.svh"

module vga_framebuffer
(
    input logic                         clk, rst,
    input logic                         render_complete,
    // DDR3 inf
    input logic                         ddr3_app_rdy,
    input logic                         ddr3_rd_data_valid,
    input logic[63:0]                   ddr3_rd_data,
    output logic                        ddr3_app_en,
    output logic[`FB_ADDR_WIDTH-1:0]    ddr3_app_addr,
    // VGA inf
    output logic[3:0]                   r, g, b,
    output logic                        hsync, vsync
);
    // VGA video out timings
    localparam  HSYNC_START         = 656;
    localparam  HSYNC_END           = 752;
    localparam  HMAX                = 800;
    localparam  VSYNC_START         = 490;
    localparam  VSYNC_END           = 492;
    localparam  VMAX                = 525;

    localparam  PIXEL_BURST_LENGTH  = 8;
    localparam  PIXEL_BURST_WIDTH   = $clog2(PIXEL_BURST_LENGTH);

    typedef enum {
        IDLE,
        WAIT_FRAME_START,
        WAIT_FIFO_SPACE,
        BURST_READ_COMMAND,
        BURST_READ_DATA
    } state_t;

    state_t                         state_reg, state_nxt;

    // VGA CE
    logic[15:0]                     clk_div;
    logic                           vga_ce;
    logic                           clk_vga;

    // DDR3 read inf
    logic                           ddr3_app_en_reg, ddr3_app_en_nxt;
    logic[`FB_ADDR_WIDTH-1:0]       ddr3_addr_reg, ddr3_addr_nxt;

    logic[PIXEL_BURST_WIDTH-1:0]    rd_burst_ctr_reg, rd_burst_ctr_nxt;
    logic[PIXEL_BURST_WIDTH:0]      rd_data_ctr_reg, rd_data_ctr_nxt; // 2:1 DDR3

    // FIFO
    logic                           clear_fifo;
    logic                           full, empty, almost_empty;
    logic[15:0]                     dout;

    // Counters
    logic[9:0]                      h_ctr_reg, v_ctr_reg;

    // Video sync signals
    logic                           hsync_reg, vsync_reg;
    logic                           video_on, vblank;

    // RGB output
    logic[3:0]                      r_reg, g_reg, b_reg, q;

    // VGA clk generation
    always_ff @(posedge clk)
    begin
        {vga_ce, clk_div} <= clk_div + 16'd10240;
    end

    // 160.00 Mhz DDR3 UI clock divided by 6.4 ==> 25.00 VGA output
    assign clk_vga = vga_ce;

    always_ff @(posedge clk)
    begin
        if (rst)
        begin
            state_reg <= IDLE;
        end
        else
        begin
            state_reg <= state_nxt;
            rd_burst_ctr_reg <= rd_burst_ctr_nxt;
            rd_data_ctr_reg <= rd_data_ctr_nxt;
            ddr3_app_en_reg <= ddr3_app_en_nxt;
            ddr3_addr_reg <= ddr3_addr_nxt;
        end
    end

    // 32-deep burst FIFO to buffer up pixels
    fifo_gen burst_fifo(
        .clk(clk),
        .srst(clear_fifo),
        .din(ddr3_rd_data),
        .wr_en(ddr3_rd_data_valid),
        .rd_en(vga_ce & video_on & (~empty)),
        .dout(dout),
        .full(full),
        .empty(empty),
        .prog_empty(almost_empty));

    // Framebuffer fetch FSM
    always_comb
    begin
        state_nxt = state_reg;

        clear_fifo = 1'b0;

        ddr3_app_en_nxt = ddr3_app_en_reg;
        ddr3_addr_nxt = ddr3_addr_reg;

        rd_burst_ctr_nxt = rd_burst_ctr_reg;
        rd_data_ctr_nxt = rd_data_ctr_reg;

        case (state_reg)
            IDLE:
            begin
                if (render_complete)
                    state_nxt = WAIT_FRAME_START;
            end

            WAIT_FRAME_START:
            begin
                clear_fifo = 1'b1;
                rd_burst_ctr_nxt = 0;
                rd_data_ctr_nxt = 0;
                ddr3_addr_nxt = 19'(0);
                if (vblank) // Start fetching from DRAM on v-blank
                begin
                    ddr3_app_en_nxt = 1'b1;
                    state_nxt = BURST_READ_COMMAND;
                end
            end

            WAIT_FIFO_SPACE:
            begin
                rd_burst_ctr_nxt = 0;
                rd_data_ctr_nxt = 0;
                if (almost_empty)
                begin
                    ddr3_app_en_nxt = 1'b1;
                    state_nxt = BURST_READ_COMMAND;
                end
            end

            BURST_READ_COMMAND:
            begin
                if (ddr3_app_rdy) // Read bursts
                begin
                    if (rd_burst_ctr_reg == PIXEL_BURST_LENGTH-1)
                    begin
                        ddr3_app_en_nxt = 1'b0;
                        state_nxt = BURST_READ_DATA;
                    end
                    else
                    begin
                        ddr3_addr_nxt = ddr3_addr_reg + 19'(PIXEL_BURST_LENGTH);
                        rd_burst_ctr_nxt = rd_burst_ctr_reg + 1;
                    end
                end
            end

            BURST_READ_DATA:
            begin
                if (ddr3_rd_data_valid) // Burst data ack
                begin
                    if (rd_data_ctr_reg == 2*PIXEL_BURST_LENGTH-1)
                    begin
                        ddr3_addr_nxt = ddr3_addr_reg + 19'(PIXEL_BURST_LENGTH);
                        if (ddr3_addr_reg == 19'(`FB_MAX_ADDR-PIXEL_BURST_LENGTH))
                            state_nxt = WAIT_FRAME_START; // Frame complete
                        else
                            state_nxt = WAIT_FIFO_SPACE; // Burst complete
                    end
                    else
                    begin
                        rd_data_ctr_nxt = rd_data_ctr_reg + 1;
                    end
                end
            end
            
            default: state_nxt = IDLE;
        endcase
    end

    // VGA hsync & vsync gen
    always_ff @(posedge clk_vga)
    begin
        if (rst)
        begin
            h_ctr_reg <= 10'b0;
            v_ctr_reg <= 10'b0;

            hsync_reg <= 1'b1;
            vsync_reg <= 1'b1;
        end
        else
        begin
            h_ctr_reg <= (h_ctr_reg == HMAX-1) ? 0 : (h_ctr_reg + 1);
            v_ctr_reg <= (h_ctr_reg == HMAX-1) ? ((v_ctr_reg == VMAX-1) ? 0 : (v_ctr_reg + 1)) : v_ctr_reg;

            hsync_reg <= ~((h_ctr_reg >= HSYNC_START) & (h_ctr_reg < HSYNC_END));
            vsync_reg <= ~((v_ctr_reg >= VSYNC_START) & (v_ctr_reg < VSYNC_END));
        end
    end

    assign video_on = (h_ctr_reg < `SCREEN_WIDTH) & (v_ctr_reg < `SCREEN_HEIGHT);
    assign vblank = ~vsync_reg;

    // RGB
    always_ff @(posedge clk_vga)
    begin
        r_reg <= video_on ? dout[3:0] : 4'b0;
        g_reg <= video_on ? dout[7:4] : 4'b0;
        b_reg <= video_on ? dout[11:8] : 4'b0;
    end

    // Outputs
    assign r = r_reg;
    assign g = g_reg;
    assign b = b_reg;
    assign hsync = hsync_reg;
    assign vsync = vsync_reg;
    assign ddr3_app_en = ddr3_app_en_reg;
    assign ddr3_app_addr = ddr3_addr_reg;
endmodule