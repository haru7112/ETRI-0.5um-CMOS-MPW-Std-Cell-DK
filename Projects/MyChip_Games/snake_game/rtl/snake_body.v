//----------------------------------------------------------------------------
// snake_body.v
//  The one and only piece of state storage in the chip.
//
//  The body is NOT stored as a list of coordinates.  A snake is a path, so the
//  only thing worth keeping is the head plus the *direction* of every step that
//  built the tail behind it - two bits per segment instead of a full position.
//  At MAXLEN=48 on a 64x32 grid that is 96 flops instead of 528, and on a
//  process where a DFF costs 36x36um that difference is 0.56mm2 of silicon.
//
//    head            : where segment 0 is
//    dq[i]           : the direction the snake was travelling when it laid
//                      down segment i, so   seg[i+1] = seg[i] stepped BACKWARDS
//                      along dq[i]
//
//  Both operations share one shift path, they only differ in direction:
//
//    move : dq[i] <= dq[i-1], dq[0] <= the new heading.  The tail drops out of
//           the valid window [0, len) on its own, so erasing it costs nothing
//           and eating is just "len <= len+1", which re-validates the entry
//           still holding the previous tail step.
//
//    scan : dq[i] <= dq[i+1], dq[MAXLEN-1] <= dq[0] - a rotation, so after
//           MAXLEN steps the queue is bit for bit back where it started.  A
//           walker starts at the head and steps backwards once per rotation,
//           so every segment position appears on scan_pos exactly once, head
//           first.  One comparator riding along that walk answers all three
//           questions the game ever asks:
//             - is this cell part of the snake?   (rendering)
//             - does the new head hit the body?   (self collision)
//             - is the candidate food cell free?  (food placement)
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

    // ---- the direction queue --------------------------------------------
    reg  [1:0] dq [0:MAXLEN-1];
    wire [1:0] dq_out = dq[0];              // segment being walked over

    integer i;
    always @(posedge clk)
        if (move) begin
            for (i = MAXLEN-1; i > 0; i = i - 1)
                dq[i] <= dq[i-1];
            dq[0] <= step_dir;
        end else if (scan_busy) begin
            for (i = 0; i < MAXLEN-1; i = i + 1)
                dq[i] <= dq[i+1];
            dq[MAXLEN-1] <= dq_out;         // rotate, so the queue survives
        end

    // ---- head / length ---------------------------------------------------
    always @(posedge clk)
        if (!rst_n) begin
            head <= {POS_W{1'b0}};
            len  <= {{(LEN_W-1){1'b0}}, 1'b1};
        end else if (load) begin
            head <= load_pos;
            len  <= {{(LEN_W-1){1'b0}}, 1'b1};
        end else if (move) begin
            head <= step_pos;
            if (grow && (len != MAXLEN[LEN_W-1:0]))
                len <= len + 1'b1;
        end

    // ---- the shared walker ----------------------------------------------
    //  during a scan   : one step BACKWARDS from walk along dq_out
    //  otherwise       : one step FORWARDS from head along step_dir
    reg  [POS_W-1:0] walk;
    wire [1:0]       wd = scan_busy ? dq_out : step_dir;
    wire [POS_W-1:0] wp = scan_busy ? walk   : head;
    wire             up = scan_busy ? wd[1]  : ~wd[1];   // backwards flips the sign
    wire [GX_W-1:0]  wx = wp[GX_W-1:0];
    wire [GY_W-1:0]  wy = wp[POS_W-1:GX_W];
    wire [GX_W-1:0]  bx = wd[0] ? wx : (up ? wx + 1'b1 : wx - 1'b1);
    wire [GY_W-1:0]  by = wd[0] ? (up ? wy + 1'b1 : wy - 1'b1) : wy;

    assign step_pos = {by, bx};      // meaningful while no scan is running
    assign scan_pos = walk;

    // ---- scan sequencer --------------------------------------------------
    reg [LEN_W-1:0] scan_cnt;               // index of the segment on scan_pos

    assign scan_valid = scan_busy && (scan_cnt < len);

    // the collision test needs the cell the head is about to enter, which is
    // step_pos - but step_pos follows the walker once a scan starts, so it is
    // sampled into cmp_tgt when the scan is launched
    reg  [POS_W-1:0] cmp_tgt;
    wire cmp_now = scan_valid && (scan_pos == cmp_tgt) &&
                   !(cmp_skip_tail && (scan_cnt == (len - 1'b1)));

    always @(posedge clk)
        if (!rst_n) begin
            scan_busy <= 1'b0;
            scan_cnt  <= {LEN_W{1'b0}};
            scan_done <= 1'b0;
            cmp_hit   <= 1'b0;
            walk      <= {POS_W{1'b0}};
            cmp_tgt   <= {POS_W{1'b0}};
        end else begin
            scan_done <= 1'b0;
            if (scan_req && !scan_busy) begin
                scan_busy <= 1'b1;
                scan_cnt  <= {LEN_W{1'b0}};
                cmp_hit   <= 1'b0;
                walk      <= head;          // segment 0 is the head itself
                cmp_tgt   <= cmp_food ? cmp_pos : step_pos;
            end else if (scan_busy) begin
                cmp_hit <= cmp_hit | cmp_now;
                walk    <= step_pos;        // the walker output, stepping back
                if (scan_cnt == (MAXLEN[LEN_W-1:0] - 1'b1)) begin
                    scan_busy <= 1'b0;
                    scan_done <= 1'b1;
                end else begin
                    scan_cnt <= scan_cnt + 1'b1;
                end
            end
        end

endmodule
