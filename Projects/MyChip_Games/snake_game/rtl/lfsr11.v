//----------------------------------------------------------------------------
// lfsr11.v
//  11 bit maximal length LFSR (x^11 + x^9 + 1) used to pick food positions.
//  Eleven bits is exactly the widest packed cell position the design can use
//  (2x2 pixel cells on a 64x32 grid), so the whole state is the candidate and
//  no bits are wasted.  It free runs on every clock, which decorrelates the
//  sequence from the instant a new food cell happens to be needed.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module lfsr11 (
    input  wire        clk,
    input  wire        rst_n,
    output wire [10:0] rnd
);
    reg [10:0] sr;

    always @(posedge clk)
        if (!rst_n) sr <= 11'h2E5;              // any non-zero seed
        else        sr <= {sr[9:0], sr[10] ^ sr[8]};

    assign rnd = sr;

endmodule
