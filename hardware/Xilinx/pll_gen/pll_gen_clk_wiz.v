
// file: pll_gen.v
// 
// (c) Copyright 2008 - 2013 Xilinx, Inc. All rights reserved.
// 
// This file contains confidential and proprietary information
// of Xilinx, Inc. and is protected under U.S. and
// international copyright and other intellectual property
// laws.
// 
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// Xilinx, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) Xilinx shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or Xilinx had been advised of the
// possibility of the same.
// 
// CRITICAL APPLICATIONS
// Xilinx products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of Xilinx products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
// 
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.
// 
//----------------------------------------------------------------------------
// User entered comments
//----------------------------------------------------------------------------
// None
//
//----------------------------------------------------------------------------
//  Output     Output      Phase    Duty Cycle   Pk-to-Pk     Phase
//   Clock     Freq (MHz)  (degrees)    (%)     Jitter (ps)  Error (ps)
//----------------------------------------------------------------------------
// _clk_ref__200.00000______0.000______50.0______100.303_____87.180
// _clk_sys__80.00000______0.000______50.0______119.159_____87.180
//
//----------------------------------------------------------------------------
// Input Clock   Freq (MHz)    Input Jitter (UI)
//----------------------------------------------------------------------------
// __primary_________100.000_____________0.00

`timescale 1ps/1ps

module pll_gen_clk_wiz 

 (// Clock in ports
  // Clock out ports
  output        clk_ref,
  output        clk_sys,
  // Status and control signals
  input         resetn,
  output        locked,
  input         clk100
 );
  // Input buffering
  //------------------------------------
wire clk100_pll_gen;
wire clk_in2_pll_gen;
  IBUF clkin1_ibufg
   (.O (clk100_pll_gen),
    .I (clk100));




  // Clocking PRIMITIVE
  //------------------------------------

  // Instantiation of the MMCM PRIMITIVE
  //    * Unused inputs are tied off
  //    * Unused outputs are labeled unused

  wire        clk_ref_pll_gen;
  wire        clk_sys_pll_gen;
  wire        clk_vga_pll_gen;
  wire        clk_out4_pll_gen;
  wire        clk_out5_pll_gen;
  wire        clk_out6_pll_gen;
  wire        clk_out7_pll_gen;

  wire [15:0] do_unused;
  wire        drdy_unused;
  wire        psdone_unused;
  wire        locked_int;
  wire        clkfbout_pll_gen;
  wire        clkfbout_buf_pll_gen;
  wire        clkfboutb_unused;
   wire clkout2_unused;
   wire clkout3_unused;
   wire clkout4_unused;
  wire        clkout5_unused;
  wire        clkout6_unused;
  wire        clkfbstopped_unused;
  wire        clkinstopped_unused;
  wire        reset_high;
  (* KEEP = "TRUE" *) 
  (* ASYNC_REG = "TRUE" *)
  reg  [7 :0] seq_reg1 = 0;
  (* KEEP = "TRUE" *) 
  (* ASYNC_REG = "TRUE" *)
  reg  [7 :0] seq_reg2 = 0;

  PLLE2_ADV
  #(.BANDWIDTH            ("OPTIMIZED"),
    .COMPENSATION         ("ZHOLD"),
    .STARTUP_WAIT         ("TRUE"),
    .DIVCLK_DIVIDE        (1),
    .CLKFBOUT_MULT        (12),
    .CLKFBOUT_PHASE       (0.000),
    .CLKOUT0_DIVIDE       (6),
    .CLKOUT0_PHASE        (0.000),
    .CLKOUT0_DUTY_CYCLE   (0.500),
    .CLKOUT1_DIVIDE       (15),
    .CLKOUT1_PHASE        (0.000),
    .CLKOUT1_DUTY_CYCLE   (0.500),
    .CLKIN1_PERIOD        (10.000))
  plle2_adv_inst
    // Output clocks
   (
    .CLKFBOUT            (clkfbout_pll_gen),
    .CLKOUT0             (clk_ref_pll_gen),
    .CLKOUT1             (clk_sys_pll_gen),
    .CLKOUT2             (clkout2_unused),
    .CLKOUT3             (clkout3_unused),
    .CLKOUT4             (clkout4_unused),
    .CLKOUT5             (clkout5_unused),
     // Input clock control
    .CLKFBIN             (clkfbout_buf_pll_gen),
    .CLKIN1              (clk100_pll_gen),
    .CLKIN2              (1'b0),
     // Tied to always select the primary input clock
    .CLKINSEL            (1'b1),
    // Ports for dynamic reconfiguration
    .DADDR               (7'h0),
    .DCLK                (1'b0),
    .DEN                 (1'b0),
    .DI                  (16'h0),
    .DO                  (do_unused),
    .DRDY                (drdy_unused),
    .DWE                 (1'b0),
    // Other control and status signals
    .LOCKED              (locked_int),
    .PWRDWN              (1'b0),
    .RST                 (reset_high));
  assign reset_high = ~resetn; 

  assign locked = locked_int;
// Clock Monitor clock assigning
//--------------------------------------
 // Output buffering
  //-----------------------------------

  BUFG clkf_buf
   (.O (clkfbout_buf_pll_gen),
    .I (clkfbout_pll_gen));







  BUFGCE clkout1_buf
   (.O   (clk_ref),
    .CE  (seq_reg1[7]),
    .I   (clk_ref_pll_gen));

  BUFH clkout1_buf_en
   (.O   (clk_ref_pll_gen_en_clk),
    .I   (clk_ref_pll_gen));
  always @(posedge clk_ref_pll_gen_en_clk or posedge reset_high) begin
    if(reset_high == 1'b1) begin
	    seq_reg1 <= 8'h00;
    end
    else begin
        seq_reg1 <= {seq_reg1[6:0],locked_int};
  
    end
  end


  BUFGCE clkout2_buf
   (.O   (clk_sys),
    .CE  (seq_reg2[7]),
    .I   (clk_sys_pll_gen));
 
  BUFH clkout2_buf_en
   (.O   (clk_sys_pll_gen_en_clk),
    .I   (clk_sys_pll_gen));
 
  always @(posedge clk_sys_pll_gen_en_clk or posedge reset_high) begin
    if(reset_high == 1'b1) begin
	  seq_reg2 <= 8'h00;
    end
    else begin
        seq_reg2 <= {seq_reg2[6:0],locked_int};
  
    end
  end





endmodule
