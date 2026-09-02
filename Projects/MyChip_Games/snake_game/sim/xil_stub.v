//----------------------------------------------------------------------------
// xil_stub.v - simulation-only stand-in for the Xilinx primitives used by the
// Zybo wrapper, so that snake_zybo_top can be lint checked with iverilog.
// Vivado never sees this file (build.tcl does not read it).
//----------------------------------------------------------------------------
`timescale 1ns/1ps
module BUFG (input wire I, output wire O);
    assign O = I;
endmodule
