// Copyright 1986-2020 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2020.2 (lin64) Build 3064766 Wed Nov 18 09:12:47 MST 2020
// Date        : Wed Aug  4 13:34:46 2021
// Host        : BTK running 64-bit Ubuntu 18.04.5 LTS
// Command     : write_verilog -force -mode synth_stub
//               /home/tayfun/Documents/DEV/Pathsy/Xilinx/Pathsy.runs/pll_gen_synth_1/pll_gen_stub.v
// Design      : pll_gen
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7s50csga324-1
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
module pll_gen(clk_ref, clk_sys, resetn, locked, clk100)
/* synthesis syn_black_box black_box_pad_pin="clk_ref,clk_sys,resetn,locked,clk100" */;
  output clk_ref;
  output clk_sys;
  input resetn;
  output locked;
  input clk100;
endmodule
