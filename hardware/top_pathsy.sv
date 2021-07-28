`include "defines.svh"

module top_pathsy
(
    input logic         clk100,
    input logic         arst,
    input logic[3:0]    btn,
    input logic[3:0]    sw,
    output logic[3:0]   led,
    // DDR3 inf
    output logic        ddr3_reset_n,
    output logic        ddr3_cke,
    output logic        ddr3_ck_p, 
    output logic        ddr3_ck_n,
    output logic        ddr3_cs_n,
    output logic        ddr3_ras_n, 
    output logic        ddr3_cas_n, 
    output logic        ddr3_we_n,
    output logic[2:0]   ddr3_ba,
    output logic[13:0]  ddr3_addr,
    output logic[0:0]   ddr3_odt,
    output logic[1:0]   ddr3_dm,
    inout logic[1:0]    ddr3_dqs_p,
    inout logic[1:0]    ddr3_dqs_n,
    inout logic[15:0]   ddr3_dq,
    // VGA inf
    output logic[3:0]   r, g, b,
    output logic        hsync, vsync
);
    // Generated clocks
    logic                       clk_ddr_ref;
    logic                       clk_ddr_sys;

    logic                       sync_rst;

    // DDR3             
    logic                       ddr3_init_calib_complete;
    logic[27:0]                 ddr3_app_addr;
    logic[2:0]                  ddr3_app_cmd;
    logic                       ddr3_app_en;
    logic[63:0]                 ddr3_app_wdf_data;
    logic                       ddr3_app_wdf_end;
    logic                       ddr3_app_wdf_wren;
    logic[63:0]                 ddr3_app_rd_data;
    logic                       ddr3_app_rd_data_end;
    logic                       ddr3_app_rd_data_valid;
    logic                       ddr3_app_rdy;
    logic                       ddr3_app_wdf_rdy;
    logic                       ddr3_app_sr_req;
    logic                       ddr3_app_ref_req;
    logic                       ddr3_app_zq_req;
    logic                       ddr3_app_sr_active;
    logic                       ddr3_app_ref_ack;
    logic                       ddr3_app_zq_ack;
    logic                       ddr3_ui_clk;
    logic                       ddr3_ui_clk_sync_rst;
    logic[7:0]                  ddr3_app_wdf_mask;
    logic                       ddr3_sys_clk_i;
    logic                       ddr3_clk_ref_i;
    logic                       ddr3_sys_rst;

    // pathsy
    logic                       pathsy_start, pathsy_busy, output_busy;
    logic                       pathsy_app_en;
    logic                       pathsy_frame_complete;
    logic[`BOUNCES_WIDTH-1:0]   max_bounces_reg;
    logic[`FB_ADDR_WIDTH-1:0]   pathsy_app_addr;

    // VGA framebuffer
    logic                       vga_app_en;
    logic[`FB_ADDR_WIDTH-1:0]   vga_app_addr;

    logic                       debouncer_pb;
    logic[3:0]                  led_reg;

    // PLL to generate DDR3 ref clk (200 Mhz), input clk (80 Mhz)
    pll_gen pll(
        .clk_ref(clk_ddr_ref),
        .clk_sys(clk_ddr_sys),
        .resetn(arst),
        .locked(ddr3_sys_rst),
        .clk100(clk100));

    // MIG DDR3
    mig mig_ddr3(
        .ddr3_addr(ddr3_addr),
        .ddr3_ba(ddr3_ba),
        .ddr3_cas_n(ddr3_cas_n),
        .ddr3_ck_n(ddr3_ck_n),
        .ddr3_ck_p(ddr3_ck_p),
        .ddr3_cke(ddr3_cke),
        .ddr3_ras_n(ddr3_ras_n),
        .ddr3_reset_n(ddr3_reset_n),
        .ddr3_we_n(ddr3_we_n),
        .ddr3_dq(ddr3_dq),
        .ddr3_dqs_n(ddr3_dqs_n),
        .ddr3_dqs_p(ddr3_dqs_p),
        .init_calib_complete(ddr3_init_calib_complete),      
        .ddr3_cs_n(ddr3_cs_n),
        .ddr3_dm (ddr3_dm),
        .ddr3_odt(ddr3_odt),
        .app_addr(ddr3_app_addr),
        .app_cmd(ddr3_app_cmd),
        .app_en(ddr3_app_en),
        .app_wdf_data(ddr3_app_wdf_data),
        .app_wdf_end(ddr3_app_wdf_end),
        .app_wdf_wren(ddr3_app_wdf_wren),
        .app_rd_data(ddr3_app_rd_data),
        .app_rd_data_end(ddr3_app_rd_data_end),
        .app_rd_data_valid(ddr3_app_rd_data_valid),
        .app_rdy(ddr3_app_rdy),
        .app_wdf_rdy(ddr3_app_wdf_rdy),
        .app_sr_req(ddr3_app_sr_req),
        .app_ref_req(ddr3_app_ref_req),
        .app_zq_req(ddr3_app_zq_req),
        .app_sr_active(ddr3_app_sr_active),
        .app_ref_ack(ddr3_app_ref_ack),
        .app_zq_ack(ddr3_app_zq_ack),
        .ui_clk(ddr3_ui_clk),
        .ui_clk_sync_rst(ddr3_ui_clk_sync_rst),
        .app_wdf_mask(ddr3_app_wdf_mask),
        .sys_clk_i(clk_ddr_sys),
        .clk_ref_i(clk_ddr_ref),
        .sys_rst(ddr3_sys_rst));

    // Held high until DDR3 is brought up
    assign sync_rst = ddr3_ui_clk_sync_rst | (~ddr3_init_calib_complete);

    // DDR3
    assign ddr3_app_sr_req = 1'b0;
    assign ddr3_app_ref_req = 1'b0;
    assign ddr3_app_zq_req = 1'b0;
    assign ddr3_app_wdf_mask = 8'b0;

    // Poor man's arbitrater for DDR3 read/write clients (pathsy vs display)
    assign ddr3_app_addr = {9'b0, pathsy_frame_complete ? vga_app_addr : pathsy_app_addr};
    assign ddr3_app_cmd = {2'b0, pathsy_frame_complete ? 1'b1 : 1'b0};
    assign ddr3_app_en = pathsy_frame_complete ? vga_app_en : pathsy_app_en;

    // "The" core
    pathsy pt(
        .clk(ddr3_ui_clk),
        .rst(sync_rst),
        .start(pathsy_start),
        .max_bounces(max_bounces_reg),
        .pathsy_busy(pathsy_busy),
        .output_busy(output_busy),
        .frame_complete(pathsy_frame_complete),
        .ddr3_app_rdy(ddr3_app_rdy),
        .ddr3_app_wdf_rdy(ddr3_app_wdf_rdy),
        .ddr3_app_en(pathsy_app_en),
        .ddr3_wdf_wr_en(ddr3_app_wdf_wren),
        .ddr3_wdf_end(ddr3_app_wdf_end),
        .ddr3_app_addr(pathsy_app_addr),
        .ddr3_wdf_data(ddr3_app_wdf_data));

    // Display
    vga_framebuffer vga(
        .clk(ddr3_ui_clk),
        .rst(ddr3_ui_clk_sync_rst),
        .render_complete(pathsy_frame_complete),
        .ddr3_app_rdy(ddr3_app_rdy),
        .ddr3_rd_data_valid(ddr3_app_rd_data_valid),
        .ddr3_rd_data(ddr3_app_rd_data),
        .ddr3_app_en(vga_app_en),
        .ddr3_app_addr(vga_app_addr),
        .r(r),
        .g(g),
        .b(b),
        .hsync(hsync),
        .vsync(vsync));

    debounce_button debouncer(
        .clk(ddr3_ui_clk),
        .pb(btn[0]),
        .pb_down(pathsy_start));

    always_ff @(posedge ddr3_ui_clk)
    begin
        max_bounces_reg <= sw[1:0]; // Must be >= 1!

        led_reg[0] <= ddr3_init_calib_complete;
        led_reg[1] <= pathsy_busy;
        led_reg[2] <= output_busy;
        led_reg[3] <= pathsy_frame_complete;
    end
    
    assign led = led_reg;
endmodule