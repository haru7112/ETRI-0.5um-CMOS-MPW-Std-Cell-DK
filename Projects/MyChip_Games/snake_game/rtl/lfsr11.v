//----------------------------------------------------------------------------
// lfsr11.v
//  Maximal length Galois LFSR used to pick food cells.  Nine bits, 511 states.
//
//  The name is historical.  game_ctrl reads GX_W + GY_W bits of rnd, which is
//  nine at the 4x4 cell size this chip is built for, so the two extra bits the
//  eleven bit version carried were dead weight - they are tied off here rather
//  than clocked.  tb_food walks the whole period and checks that every field
//  column can still hold food.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module lfsr11 (
    input  wire        clk,
    input  wire        rst_n,
    output wire [10:0] rnd
);
    reg [8:0] sr;

    always @(posedge clk)
        if (!rst_n) sr <= 9'h1E5;                  // any non zero seed
        else        sr <= {sr[7:0], sr[8] ^ sr[4]};

    assign rnd = {2'b00, sr};

endmodule
