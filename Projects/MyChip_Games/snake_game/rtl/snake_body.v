//----------------------------------------------------------------------------
// snake_body.v
//  The one and only piece of state storage in the chip.
//
//  The body is NOT stored as a list of coordinates.  A snake is a path, so the
//  only thing worth keeping is the head plus the *direction* of every step that
//  built the tail behind it - two bits per segment instead of a full position.
//  At MAXLEN=32 on a 32x16 grid that is 64 flops instead of 288, and on a
//  process where a DFF costs 36x36um that difference is 0.29mm2 of silicon.
//
//    head            : where segment 0 is
//    dq[i]           : the direction the snake was travelling when it laid
//                      down segment i, so   seg[i+1] = seg[i] stepped BACKWARDS
//                      along dq[i]
//
//  THE QUEUE NEVER STOPS TURNING.
//
//  This library has no flop with an enable - the cell list is DFFPOSX1 and
//  DFFSR and nothing else - so every register that can hold its value pays for
//  a feedback mux built out of gates, and every register that can be written
//  two different ways pays for another.  The queue used to be exactly that:
//
//      dq[i] <= move ? dq[i-1] : (scan_busy ? dq[i+1] : dq[i])
//
//  two mux levels on all 64 bits, and the single largest lump of combinational
//  logic in the chip.  So the queue is now a plain rotator that turns on every
//  clock, for ever, and dq[1] .. dq[MAXLEN-1] have no input logic left at all -
//  each one is wired straight to its neighbour.
//
//  A free running rotation is only useful if you know where you are in it, so
//  a phase counter rides along and the invariant is
//
//      at phase p,   dq[i] == seg[(i + p) mod MAXLEN]
//
//  which makes both operations fall out of the rotation itself:
//
//    scan : at phase p the head of the queue, dq[0], is segment p.  So a scan
//           is not a mode the queue enters - it is just watching dq[0] for one
//           full turn, starting at phase 0.  The segment index IS the phase,
//           which is why there is no scan counter here any more.  One walker
//           stepping backwards once per phase turns that into positions, and
//           one comparator riding along answers all three questions the game
//           ever asks:
//             - is this cell part of the snake?   (rendering)
//             - does the new head hit the body?   (self collision)
//             - is the candidate food cell free?  (food placement)
//
//    move : prepending a segment and dropping the last one is, on a ring, the
//           same thing as turning it one notch too far.  Rotating by MAXLEN-1
//           lands every old entry where the new list wants it; doing that in
//           MAXLEN-1 clocks would be slow, but the rotation is running anyway,
//           so the move costs nothing more than SKIPPING ONE PHASE.  At phase
//           MAXLEN-2 the queue rotates as usual, dq[0] takes the new heading
//           instead of its neighbour, and the phase counter jumps to 0.  The
//           tail drops out of the valid window [0, len) on its own, so erasing
//           it costs nothing and eating is just "len <= len+1", which
//           re-validates the entry still holding the previous tail step.
//
//  The price is latency, not gates: a move waits for phase MAXLEN-2 and a scan
//  waits for phase 0, up to MAXLEN-1 clocks each.  A game step is 208ms and a
//  panel byte is 32 clocks, so nothing notices.  What the caller must do is
//  wait: move_busy is high from the request until the queue takes it, and a
//  scan request is answered by scan_done as before.
//
//  Direction encoding (shared with game_ctrl):
//      00 RIGHT (x+1)  01 DOWN (y+1)  10 LEFT (x-1)  11 UP (y-1)
//  bit0 picks the axis, bit1 the sign, and walking backwards just flips the
//  sign - so ONE incrementer pair serves both the scan walk and the "where
//  does the head go next" question.  step_pos carries that answer out to
//  game_ctrl, which therefore needs no position arithmetic and no position
//  registers of its own: on this process a spare 9 bit register plus the mux
//  tree that feeds it from nine FSM states costs more than the adder does.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module snake_body #(
    parameter POS_W  = 11,
    parameter GX_W   = 6,
    parameter MAXLEN = 48,
    parameter LEN_W  = 6
)(
    input  wire              clk,
    input  wire              rst_n,

    // ---- body update -----------------------------------------------------
    input  wire              load,        // pulse: restart as a 1 cell snake
    input  wire [POS_W-1:0]  load_pos,    // its start cell (a constant, not a register)
    input  wire              move,        // pulse: advance the head along step_dir
    input  wire              grow,        // pulse (with move): keep the old tail
    input  wire [1:0]        step_dir,    // heading of the next step
    output wire [POS_W-1:0]  step_pos,    // where that step lands - the next head
    output wire              move_busy,   // 1 from a move request until it lands

    // ---- serial scan port ------------------------------------------------
    input  wire              scan_req,    // pulse: run a full MAXLEN step scan
    input  wire              cmp_food,    // 0 = test step_pos, 1 = test cmp_pos
    input  wire [POS_W-1:0]  cmp_pos,     // the candidate food cell
    input  wire              cmp_skip_tail,// ignore the tail, it moves away
    output reg               scan_busy,
    output wire [POS_W-1:0]  scan_pos,    // segment presented this cycle
    output wire              scan_valid,  // 1 while scan_pos is a real segment
    output reg               scan_done,   // 1 clock pulse, scan finished
    output reg               cmp_hit,     // valid from scan_done until next scan

    // ---- status ----------------------------------------------------------
    output reg  [POS_W-1:0]  head,
    output reg  [LEN_W-1:0]  len
);
    localparam GY_W = POS_W - GX_W;
    localparam integer PH_W = (MAXLEN <= 2)  ? 1 : (MAXLEN <=   4) ? 2 :
                              (MAXLEN <= 8)  ? 3 : (MAXLEN <=  16) ? 4 :
                              (MAXLEN <= 32) ? 5 : (MAXLEN <=  64) ? 6 : 7;

    // ---- pending requests ------------------------------------------------
    //  Both are levels the caller does not have to hold, and both are honoured
    //  at a fixed point in the rotation.  A scan never starts while a move is
    //  waiting, so a scan always sees the body the game just asked for.
    reg              mv_pend, mv_grow, scan_pend;
    reg  [1:0]       mv_dir;
    reg  [PH_W-1:0]  phase;

    localparam [PH_W-1:0] PH_MOVE = MAXLEN - 2;   // where a move is applied
    localparam [PH_W-1:0] PH_LAST = MAXLEN - 1;   // last notch of a turn

    wire at_move = (phase == PH_MOVE);
    wire at_scan = (phase == PH_LAST);

    wire mv_go   = mv_pend   && !scan_busy && at_move;
    wire sc_go   = scan_pend && !scan_busy && !mv_pend && at_scan;

    assign move_busy = mv_pend;

    always @(posedge clk)
        if (!rst_n) begin
            mv_pend   <= 1'b0;
            mv_grow   <= 1'b0;
            mv_dir    <= 2'b00;
            scan_pend <= 1'b0;
            phase     <= {PH_W{1'b0}};
        end else begin
            // one notch per clock, one skipped notch per move.  The wrap is
            // written out rather than left to the counter width, so MAXLEN
            // does not have to be a power of two.
            phase <= (at_scan || mv_go) ? {PH_W{1'b0}} : (phase + 1'b1);

            if (move) begin
                mv_pend <= 1'b1;
                mv_grow <= grow;
                mv_dir  <= step_dir;
            end else if (mv_go)
                mv_pend <= 1'b0;

            if (scan_req)   scan_pend <= 1'b1;
            else if (sc_go) scan_pend <= 1'b0;
        end

    // ---- the direction queue --------------------------------------------
    //  Everything above dq[0] is a bare shift.  dq[0] is the only bit pair
    //  with a mux on it, and that mux is what makes a move a move.
    reg  [1:0] dq [0:MAXLEN-1];
    wire [1:0] dq_out = dq[0];              // segment being walked over

    integer i;
    always @(posedge clk) begin
        dq[0] <= mv_go ? mv_dir : dq[1];
        for (i = 1; i < MAXLEN-1; i = i + 1)
            dq[i] <= dq[i+1];
        dq[MAXLEN-1] <= dq_out;
    end

    // ---- head / length ---------------------------------------------------
    always @(posedge clk)
        if (!rst_n) begin
            head <= {POS_W{1'b0}};
            len  <= {{(LEN_W-1){1'b0}}, 1'b1};
        end else if (load) begin
            head <= load_pos;
            len  <= {{(LEN_W-1){1'b0}}, 1'b1};
        end else if (mv_go) begin
            head <= step_pos;
            if (mv_grow && (len != MAXLEN[LEN_W-1:0]))
                len <= len + 1'b1;
        end

    // ---- the shared walker ----------------------------------------------
    //  during a scan   : one step BACKWARDS from walk along dq_out
    //  otherwise       : one step FORWARDS from head along the heading, which
    //                    is the latched one once a move is waiting - the caller
    //                    is free to change its mind about direction in between
    reg  [POS_W-1:0] walk;
    wire [1:0]       hd = mv_pend ? mv_dir : step_dir;
    wire [1:0]       wd = scan_busy ? dq_out : hd;
    wire [POS_W-1:0] wp = scan_busy ? walk   : head;
    wire             up = scan_busy ? wd[1]  : ~wd[1];   // backwards flips the sign
    wire [GX_W-1:0]  wx = wp[GX_W-1:0];
    wire [GY_W-1:0]  wy = wp[POS_W-1:GX_W];
    wire [GX_W-1:0]  bx = wd[0] ? wx : (up ? wx + 1'b1 : wx - 1'b1);
    wire [GY_W-1:0]  by = wd[0] ? (up ? wy + 1'b1 : wy - 1'b1) : wy;

    assign step_pos = {by, bx};      // meaningful while no scan is running
    assign scan_pos = walk;

    // ---- scan sequencer --------------------------------------------------
    //  The segment index is the phase, so there is no counter here.  A scan
    //  runs from phase 0 to phase MAXLEN-1 inclusive; the phase cannot skip
    //  while it runs, because a move waits for the scan to finish.
    wire [LEN_W-1:0] seg_idx = phase;      // the segment index IS the phase
    assign scan_valid = scan_busy && (seg_idx < len);

    // the collision test needs the cell the head is about to enter, which is
    // step_pos - but step_pos follows the walker once a scan starts, so it is
    // sampled into cmp_tgt when the scan is launched
    reg  [POS_W-1:0] cmp_tgt;
    wire cmp_now = scan_valid && (scan_pos == cmp_tgt) &&
                   !(cmp_skip_tail && (seg_idx == (len - 1'b1)));

    always @(posedge clk)
        if (!rst_n) begin
            scan_busy <= 1'b0;
            scan_done <= 1'b0;
            cmp_hit   <= 1'b0;
            walk      <= {POS_W{1'b0}};
            cmp_tgt   <= {POS_W{1'b0}};
        end else begin
            scan_done <= 1'b0;
            if (sc_go) begin
                scan_busy <= 1'b1;
                cmp_hit   <= 1'b0;
                walk      <= head;          // segment 0 is the head itself
                cmp_tgt   <= cmp_food ? cmp_pos : step_pos;
            end else if (scan_busy) begin
                cmp_hit <= cmp_hit | cmp_now;
                walk    <= step_pos;        // the walker output, stepping back
                if (at_scan) begin
                    scan_busy <= 1'b0;
                    scan_done <= 1'b1;
                end
            end
        end

    //------------------------------------------------------------------
    // Elaboration guards, same idea as game_ctrl: an inconsistent parameter
    // set must not build.  seg_idx is the phase widened to LEN_W, and the
    // rotation needs at least four notches for the move and the scan to land
    // on different ones.
    //------------------------------------------------------------------
    generate
        if (LEN_W < PH_W)
            ERROR_LEN_W_must_cover_MAXLEN u_chk_len ();
        if (MAXLEN < 4)
            ERROR_MAXLEN_must_be_at_least_4 u_chk_maxlen ();
    endgenerate

endmodule
