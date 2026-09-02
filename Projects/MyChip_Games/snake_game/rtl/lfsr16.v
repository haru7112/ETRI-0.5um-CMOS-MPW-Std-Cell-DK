//----------------------------------------------------------------------------
// lfsr16.v
//  16 bit maximal length Fibonacci LFSR (x^16+x^15+x^13+x^4+1) used to pick
//  food positions.  It free runs on every clock so the sequence is decorrelated
//  from the (human) instant at which a new food cell is requested.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module lfsr16 (
    input  wire        clk,
    input  wire        rst_n,
    output wire [15:0] rnd
);
    reg [15:0] sr;
    wire fb = sr[15] ^ sr[14] ^ sr[12] ^ sr[3];

    always @(posedge clk)
        if (!rst_n) sr <= 16'hACE1;         // any non-zero seed
        else        sr <= {sr[14:0], fb};

    assign rnd = sr;

endmodule
