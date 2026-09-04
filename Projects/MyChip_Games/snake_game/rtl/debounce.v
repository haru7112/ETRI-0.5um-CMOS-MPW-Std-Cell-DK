//----------------------------------------------------------------------------
// debounce.v
//  Two stage metastability sync for every input, and a 2 sample agreement
//  filter for the ones that need one.  Inputs are active low (switch closes to
//  GND, external pull-up).
//
//  NOT EVERY BUTTON NEEDS DEBOUNCING, and on this library that matters: with
//  no enable flop in the cell list, a filtered input costs three registers and
//  the mux trees that feed them, times N.
//
//  The four direction inputs are read as a LEVEL, and only at a game step -
//  208ms apart.  game_ctrl latches the heading continuously into dir_nxt and
//  only when a direction is actually held, so a contact bouncing through
//  "released" for a few hundred microseconds leaves the last held direction
//  standing.  There is nothing for a filter to fix, so those four get the
//  synchroniser and nothing else.
//
//  OK is the one input that is edge sensitive - one press starts or restarts
//  the game - so a bounce there really would be several presses.  That bit
//  keeps the full filter: a level has to be stable across two millisecond
//  samples before it is accepted, well beyond the bounce time of a tactile
//  5-way switch.  Only the previous sample is kept, not two of them, and the
//  press pulse is formed from the transition that is about to be taken rather
//  than from a delayed copy of level - three registers for that one bit
//  instead of five.
//
//  press is meaningful only where FILT has a 1; it reads zero elsewhere.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module debounce #(
    parameter N    = 5,                   // number of parallel switch inputs
    parameter FILT = 5'b10000             // which of them get the filter
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         ms_pulse,         // 1 clock wide, once per millisecond
    input  wire [N-1:0] pin_n,            // raw, active low
    output wire [N-1:0] level,            // active high (1 = pressed)
    output wire [N-1:0] press             // 1 clock wide pulse on 0->1 of level
);
    reg  [N-1:0] s0, s1;
    wire [N-1:0] now = ~s1;               // active low pin -> active high sample

    always @(posedge clk)
        if (!rst_n) begin
            s0 <= {N{1'b1}};  s1 <= {N{1'b1}};
        end else begin
            s0 <= pin_n;      s1 <= s0;
        end

    genvar g;
    generate for (g = 0; g < N; g = g + 1) begin : sw
        if (FILT[g]) begin : filtered
            reg  prev;                    // the previous accepted sample
            reg  lvl, prs;
            wire agree = ~(now[g] ^ prev);   // this sample matches the last one

            always @(posedge clk)
                if (!rst_n) begin
                    prev <= 1'b0;  lvl <= 1'b0;  prs <= 1'b0;
                end else begin
                    prs <= 1'b0;
                    if (ms_pulse) begin
                        prev <= now[g];
                        lvl  <= (agree & now[g]) | (~agree & lvl);
                        prs  <= agree & now[g] & ~lvl;
                    end
                end

            assign level[g] = lvl;
            assign press[g] = prs;
        end else begin : plain
            assign level[g] = now[g];
            assign press[g] = 1'b0;
        end
    end endgenerate

endmodule
