//----------------------------------------------------------------------------
// snake_body.v
//  The one and only piece of state storage in the chip.
//
//  The snake body is held in a CIRCULAR shift register of MAXLEN entries, each
//  entry a packed cell position {y,x}.  There is no addressable memory and no
//  frame buffer anywhere in the design - the ETRI 0.5um std-cell library has no
//  RAM macro and a DFF costs 36x36um, so every stored bit has to earn its area.
//
//  Two operations share the very same shift path, they only differ in what is
//  fed into stage 0:
//
//    move : seg[0] <= new head,  seg[i] <= seg[i-1]
//           The old tail simply falls out of the valid window [0 .. len-1], so
//           erasing the tail costs nothing.  Eating is just "len <= len+1",
//           which re-validates the entry that still holds the previous tail.
//
//    scan : seg[0] <= seg[MAXLEN-1] (rotate).  After MAXLEN rotations the
//           register is bit for bit back where it started, and every segment
//           has been presented once on scan_pos.  One 11 bit comparator is
//           therefore enough to answer all three questions the game asks:
//             - is this cell part of the snake?      (rendering)
//             - does the new head hit the body?      (self collision)
//             - is the candidate food cell free?     (food placement)
//
//  Because the array is only ever written through the shift path, the segment
//  flops need no set/reset and map onto the cheap DFFPOSX1 (36x36um) instead of
//  DFFSR (72x36um).  Entries above 'len' may hold garbage after power up; they
//  are masked by scan_valid and never observed.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module snake_body #(
    parameter POS_W  = 11,
    parameter MAXLEN = 48,
    parameter LEN_W  = 6
)(
    input  wire              clk,
    input  wire              rst_n,

    // ---- body update -----------------------------------------------------
    input  wire              load,        // pulse: restart with a 1 cell snake
    input  wire              move,        // pulse: shift move_pos in as new head
    input  wire              grow,        // pulse (with move): keep the old tail
    input  wire [POS_W-1:0]  move_pos,

    // ---- serial scan port ------------------------------------------------
    input  wire              scan_req,    // pulse: run a full MAXLEN step scan
    input  wire [POS_W-1:0]  cmp_pos,     // position tested during the scan
    input  wire              cmp_skip_tail,// ignore the last segment (it moves away)
    output reg               scan_busy,
    output wire [POS_W-1:0]  scan_pos,    // segment presented this cycle
    output wire              scan_valid,  // 1 while scan_pos is a real segment
    output reg               scan_done,   // 1 clock pulse, scan finished
    output reg               cmp_hit,     // valid from scan_done until next scan

    // ---- status ----------------------------------------------------------
    output reg  [POS_W-1:0]  head,
    output reg  [LEN_W-1:0]  len
);
    // ---- the shift register ---------------------------------------------
    reg  [POS_W-1:0] seg [0:MAXLEN-1];
    wire [POS_W-1:0] tail_out = seg[MAXLEN-1];

    wire             shift_en = move | scan_shift;
    wire [POS_W-1:0] shift_in = move ? move_pos : tail_out;

    integer i;
    always @(posedge clk)
        if (shift_en) begin
            for (i = MAXLEN-1; i > 0; i = i - 1)
                seg[i] <= seg[i-1];
            seg[0] <= shift_in;
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

    // ---- scan sequencer --------------------------------------------------
    // scan_cnt is the index of the segment currently visible on scan_pos: the
    // register rotates one step per cycle so seg[MAXLEN-1] walks backwards
    // through the whole body, from index MAXLEN-1 down to 0.
    reg  [LEN_W-1:0] scan_cnt;
    wire             scan_shift = scan_busy;

    assign scan_pos   = tail_out;
    assign scan_valid = scan_busy && (scan_cnt < len);

    wire cmp_eq   = (scan_pos == cmp_pos);
    wire is_tail  = (scan_cnt == (len - 1'b1));
    wire cmp_now  = scan_valid && cmp_eq && !(cmp_skip_tail && is_tail);

    always @(posedge clk)
        if (!rst_n) begin
            scan_busy <= 1'b0;
            scan_cnt  <= {LEN_W{1'b0}};
            scan_done <= 1'b0;
            cmp_hit   <= 1'b0;
        end else begin
            scan_done <= 1'b0;
            if (scan_req && !scan_busy) begin
                scan_busy <= 1'b1;
                scan_cnt  <= MAXLEN[LEN_W-1:0] - 1'b1;
                cmp_hit   <= 1'b0;
            end else if (scan_busy) begin
                cmp_hit <= cmp_hit | cmp_now;
                if (scan_cnt == {LEN_W{1'b0}}) begin
                    scan_busy <= 1'b0;
                    scan_done <= 1'b1;
                end else begin
                    scan_cnt <= scan_cnt - 1'b1;
                end
            end
        end

endmodule
