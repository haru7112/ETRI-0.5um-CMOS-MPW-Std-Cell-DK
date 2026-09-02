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
//  Walking backwards simply flips the sign bit.
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
    input  wire              move,        // pulse: step to move_pos heading move_dir
    input  wire              grow,        // pulse (with move): keep the old tail
    input  wire [POS_W-1:0]  move_pos,
    input  wire [1:0]        move_dir,

    // ---- serial scan port ------------------------------------------------
    input  wire              scan_req,    // pulse: run a full MAXLEN step scan
    input  wire [POS_W-1:0]  cmp_pos,     // position tested during the scan
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
            dq[0] <= move_dir;
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
            head <= move_pos;
            len  <= {{(LEN_W-1){1'b0}}, 1'b1};
        end else if (move) begin
            head <= move_pos;
            if (grow && (len != MAXLEN[LEN_W-1:0]))
                len <= len + 1'b1;
        end

    // ---- the walker ------------------------------------------------------
    //  one step backwards along dq_out: bit0 picks the axis, bit1 the sign,
    //  and going backwards is the same delta with the sign inverted
    reg  [POS_W-1:0] walk;
    wire [GX_W-1:0]  wx = walk[GX_W-1:0];
    wire [GY_W-1:0]  wy = walk[POS_W-1:GX_W];
    wire [GX_W-1:0]  bx = dq_out[0] ? wx : (dq_out[1] ? wx + 1'b1 : wx - 1'b1);
    wire [GY_W-1:0]  by = dq_out[0] ? (dq_out[1] ? wy + 1'b1 : wy - 1'b1) : wy;

    assign scan_pos = walk;

    // ---- scan sequencer --------------------------------------------------
    reg [LEN_W-1:0] scan_cnt;               // index of the segment on scan_pos

    assign scan_valid = scan_busy && (scan_cnt < len);

    wire cmp_now = scan_valid && (scan_pos == cmp_pos) &&
                   !(cmp_skip_tail && (scan_cnt == (len - 1'b1)));

    always @(posedge clk)
        if (!rst_n) begin
            scan_busy <= 1'b0;
            scan_cnt  <= {LEN_W{1'b0}};
            scan_done <= 1'b0;
            cmp_hit   <= 1'b0;
            walk      <= {POS_W{1'b0}};
        end else begin
            scan_done <= 1'b0;
            if (scan_req && !scan_busy) begin
                scan_busy <= 1'b1;
                scan_cnt  <= {LEN_W{1'b0}};
                cmp_hit   <= 1'b0;
                walk      <= head;          // segment 0 is the head itself
            end else if (scan_busy) begin
                cmp_hit <= cmp_hit | cmp_now;
                walk    <= {by, bx};
                if (scan_cnt == (MAXLEN[LEN_W-1:0] - 1'b1)) begin
                    scan_busy <= 1'b0;
                    scan_done <= 1'b1;
                end else begin
                    scan_cnt <= scan_cnt + 1'b1;
                end
            end
        end

endmodule
