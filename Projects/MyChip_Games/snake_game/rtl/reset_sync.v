//----------------------------------------------------------------------------
// reset_sync.v
//  Reset bridge: asynchronous assert, synchronous release, stretched.
//
//  The chip takes its reset from an external RC network on RST_N which knows
//  nothing about the 25MHz oscillator, and the oscillator itself may still be
//  starting up when RST_N has already risen.  This is the ONLY flop in the
//  design with an asynchronous clear; everything downstream uses a plain
//  synchronous reset off rst_n, which keeps the core on the 36um DFFPOSX1
//  instead of the 72um DFFSR and saves roughly a quarter of the cell area.
//
//  Because the shift register starts cleared, rst_n stays low for STAGES
//  clocks after the clock actually starts running, whatever RST_N did before.
//  Two stages is the whole job - one to catch the metastable sample and one to
//  clean it up - and the extra two were 0.008mm2 of DFFSR, which is twice the
//  size of an ordinary flop on this library.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module reset_sync #(
    parameter STAGES = 2
)(
    input  wire clk,
    input  wire arst_n,     // asynchronous, active low (from the pad)
    output wire rst_n       // synchronised and stretched, active low
);
    reg [STAGES-1:0] sync;

    always @(posedge clk or negedge arst_n)
        if (!arst_n) sync <= {STAGES{1'b0}};
        else         sync <= {sync[STAGES-2:0], 1'b1};

    assign rst_n = sync[STAGES-1];

endmodule
