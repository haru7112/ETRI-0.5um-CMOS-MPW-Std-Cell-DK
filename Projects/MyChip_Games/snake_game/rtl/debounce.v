//----------------------------------------------------------------------------
// debounce.v
//  Two stage metastability sync + 2 sample agreement filter, clocked by the
//  frame strobe.  A level has to be stable across two frames (~22ms) before it
//  is accepted, which is well beyond the bounce time of a tactile 5-way
//  switch.
//  Inputs are active low (switch closes to GND, external pull-up).
//
//  Only the previous sample is kept, not two of them: comparing the incoming
//  sample against the stored one is the same filter as comparing two stored
//  ones, one register cheaper.  The press pulse is likewise formed from the
//  transition that is about to be taken rather than from a delayed copy of
//  level, which saves another.  Five registers of width N, not seven.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module debounce #(
    parameter N = 5                       // number of parallel switch inputs
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         sample,           // 1 clock wide, once per frame
    input  wire [N-1:0] pin_n,            // raw, active low
    output reg  [N-1:0] level,            // debounced, active high (1 = pressed)
    output reg  [N-1:0] press             // 1 clock wide pulse on 0->1 of level
);
    reg [N-1:0] s0, s1;
    reg [N-1:0] prev;                     // the previous accepted sample

    wire [N-1:0] now = ~s1;               // active low pin -> active high sample
    wire [N-1:0] agree = ~(now ^ prev);   // this sample matches the last one

    always @(posedge clk)
        if (!rst_n) begin
            s0 <= {N{1'b1}};  s1 <= {N{1'b1}};
        end else begin
            s0 <= pin_n;      s1 <= s0;
        end

    always @(posedge clk)
        if (!rst_n) begin
            prev  <= {N{1'b0}};
            level <= {N{1'b0}};
            press <= {N{1'b0}};
        end else begin
            press <= {N{1'b0}};
            if (sample) begin
                prev  <= now;
                level <= (agree & now) | (~agree & level);
                press <= agree & now & ~level;
            end
        end

endmodule
