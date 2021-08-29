-- Copyright 1986-2020 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2020.2 (lin64) Build 3064766 Wed Nov 18 09:12:47 MST 2020
-- Date        : Wed Aug  4 13:34:46 2021
-- Host        : BTK running 64-bit Ubuntu 18.04.5 LTS
-- Command     : write_vhdl -force -mode synth_stub
--               /home/tayfun/Documents/DEV/Pathsy/Xilinx/Pathsy.runs/pll_gen_synth_1/pll_gen_stub.vhdl
-- Design      : pll_gen
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7s50csga324-1
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity pll_gen is
  Port ( 
    clk_ref : out STD_LOGIC;
    clk_sys : out STD_LOGIC;
    resetn : in STD_LOGIC;
    locked : out STD_LOGIC;
    clk100 : in STD_LOGIC
  );

end pll_gen;

architecture stub of pll_gen is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "clk_ref,clk_sys,resetn,locked,clk100";
begin
end;
