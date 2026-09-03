//----------------------------------------------------------------------------
// game_ctrl.v
//  Game rules and the only sequencer that mutates the snake.
//
//  All state changes happen in the gap between two OLED frames (frame_done ->
//  busy -> idle).  That keeps the picture tear free and, more importantly,
//  guarantees that the body queue is never asked to shift and to rotate for a
//  scan in the same cycle.
//
//  This block deliberately owns NO position arithmetic and only one position
//  register (the food).  On a 0.5um process the mux tree that feeds a 9 bit
//  register from nine FSM states costs more than the adder it would save, so
//  the next head position is computed inside snake_body - which already has
//  the incrementer pair for its scan walk - and comes back on step_pos.
//
//  Direction encoding (chosen so that "opposite" is a single bit flip):
//      00 RIGHT (x+1)   01 DOWN (y+1)   10 LEFT (x-1)   11 UP (y-1)
//      bit0 = axis, bit1 = sign, opposite(d) = d ^ 2'b10
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module game_ctrl #(
    // Screen geometry is derived once in snake_top and handed down, so there
    // is exactly one place in the design that decides where the walls are.
    // The elaboration guards at the bottom of this file refuse to build if a
    // caller passes a set that does not hang together.
    parameter GX_W     = 6,      // bits of a cell X coordinate
    parameter GY_W     = 5,      // bits of a cell Y coordinate
    parameter POS_W    = 11,     // packed {y,x}, = GX_W + GY_W
    parameter FLD_X0   = 8,      // divider column, the left wall
    parameter FLD_X1   = 63,     // right wall
    parameter FLD_Y0   = 0,      // top rule
    parameter FLD_Y1   = 31,     // bottom rule
    parameter MAXLEN   = 48,
    parameter LEN_W    = 6,
    parameter INIT_LEN = 3,
    // Milliseconds per game step, fixed.  Keep it under 128 and the counter
    // below is seven bits instead of eight - see the comment at the timer.
    parameter STEP_MS  = 120
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ms_pulse,

    // buttons: [0]=UP [1]=DOWN [2]=LEFT [3]=RIGHT [4]=OK(centre)
    input  wire [4:0]  btn_level,
    input  wire [4:0]  btn_press,

    // handshake with the display sequencer
    input  wire        frame_done,
    output reg         busy,

    // body control
    output reg         body_load,
    output reg         body_move,
    output reg         body_grow,
    output wire [10:0] load_pos,
    output wire [1:0]  step_dir,
    input  wire [10:0] step_pos,
    output reg         scan_req,
    output reg         cmp_food,
    output wire [10:0] cmp_pos,
    output reg         cmp_skip_tail,
    input  wire        scan_done,
    input  wire        cmp_hit,
    input  wire [LEN_W-1:0] len,

    // rendering state
    output wire        st_title,
    output wire        st_over,
    output reg  [7:0]  score_bcd,       // 2 BCD digits, {tens, units}
    output wire [10:0] food_pos,
    output reg         food_en,

    input  wire [10:0] rnd
);
    localparam CX0 = ((FLD_X0 + FLD_X1) / 2) - INIT_LEN;  // freshly loaded head
    localparam CY0 =  (FLD_Y0 + FLD_Y1) / 2;              // middle of the field

    localparam S_TITLE = 4'd0,
               S_NEW   = 4'd1,
               S_BUILD = 4'd2,
               S_FOOD  = 4'd3,
               S_FSCAN = 4'd4,
               S_IDLE  = 4'd5,
               S_STEP  = 4'd6,
               S_SSCAN = 4'd7,
               S_OVER  = 4'd8;

    reg  [3:0]       st;
    reg  [1:0]       dir, dir_nxt;
    // Width follows STEP_MS: 120 needs seven bits, 200 would need eight.
    localparam integer      MS_W     = $clog2(STEP_MS + 1);
    localparam [MS_W-1:0]   STEP_CNT = STEP_MS[MS_W-1:0];

    reg  [MS_W-1:0]  ms_cnt;
    reg              tick_pend;
    reg              ok_pend;
    reg  [LEN_W-1:0] build_cnt;
    reg  [2:0]       food_try;
    reg  [POS_W-1:0] food_r;

    assign st_title = (st == S_TITLE);
    assign st_over  = (st == S_OVER);
    assign step_dir = dir;
    assign load_pos = {{(11-POS_W){1'b0}}, CY0[GY_W-1:0], CX0[GX_W-1:0]};
    assign cmp_pos  = {{(11-POS_W){1'b0}}, food_r};
    assign food_pos = {{(11-POS_W){1'b0}}, food_r};

    //------------------------------------------------------------------
    // direction capture (free running, applied at the next game step)
    //------------------------------------------------------------------
    reg  [1:0] want;
    reg        want_v;
    always @* begin
        want_v = 1'b1;
        if      (btn_level[0]) want = 2'b11;      // up
        else if (btn_level[1]) want = 2'b01;      // down
        else if (btn_level[2]) want = 2'b10;      // left
        else if (btn_level[3]) want = 2'b00;      // right
        else begin want = dir; want_v = 1'b0; end
    end

    // A reversal is tested against the direction actually in use, never against
    // a still pending one, so a fast up/left/down sequence inside one step can
    // not fold the snake back onto itself.
    always @(posedge clk)
        if (!rst_n)                                dir_nxt <= 2'b00;
        else if (st == S_NEW)                      dir_nxt <= 2'b00;
        else if (want_v && (want != (dir ^ 2'b10))) dir_nxt <= want;

    //------------------------------------------------------------------
    // Game step timer: a millisecond prescaler counting down from a constant.
    //
    // The step used to shorten as the snake grew, 200ms down to 88ms in eight
    // steps off len.  That ramp cost a subtractor and the mux tree that fed
    // it - measured at 0.020mm2 on the ETRI cells, which is 2% of the whole
    // core budget - so it is gone and the step is one number.  Keeping
    // STEP_MS under 128 also takes the counter from eight bits to seven.
    //------------------------------------------------------------------

    wire in_play = (st != S_TITLE) && (st != S_OVER) && (st != S_NEW);

    always @(posedge clk)
        if (!rst_n) begin
            ms_cnt    <= STEP_CNT;
            tick_pend <= 1'b0;
        end else if (!in_play) begin
            ms_cnt    <= STEP_CNT;
            tick_pend <= 1'b0;
        end else begin
            if (ms_pulse) begin
                if (ms_cnt == {MS_W{1'b0}}) begin
                    ms_cnt    <= STEP_CNT;
                    tick_pend <= 1'b1;
                end else begin
                    ms_cnt <= ms_cnt - 1'b1;
                end
            end
            if (st == S_STEP) tick_pend <= 1'b0;
        end

    // latch OK so a short press survives until the next inter frame window
    always @(posedge clk)
        if (!rst_n)            ok_pend <= 1'b0;
        else if (st == S_NEW)  ok_pend <= 1'b0;
        else if (btn_press[4]) ok_pend <= 1'b1;

    //------------------------------------------------------------------
    // the wall test and the meal test both ride on step_pos
    //------------------------------------------------------------------
    wire [GX_W-1:0] nx = step_pos[GX_W-1:0];
    wire [GY_W-1:0] ny = step_pos[POS_W-1:GX_W];

    wire hit_wall = (nx == FLD_X0[GX_W-1:0]) || (nx == FLD_X1[GX_W-1:0]) ||
                    (ny == FLD_Y0[GY_W-1:0]) || (ny == FLD_Y1[GY_W-1:0]);

    wire eat_now  = food_en && (food_r == step_pos[POS_W-1:0]);

    //------------------------------------------------------------------
    // Food candidate: taken off the LFSR and re-rolled until it lands inside
    // the play field.  There is deliberately NO give-up on this test.
    //
    // A give-up that accepts an out of range cell puts the food under a wall,
    // where the 0xFF wall byte hides it completely - that is exactly what a
    // 3 bit counter used to do on roughly one placement in fifty, because 2.2%
    // of the LFSR period has eight consecutive out of range candidates.
    //
    // Looping forever is safe here because the sequence is finite and known:
    // over the LFSR's full 2047 states the longest run of out of range
    // candidates is 21, for every supported cell size.  So this state exits
    // within 21 clocks - 840ns - against a 100ms game step.  Clamping into
    // range would also terminate, but it piles 19% of all food onto the first
    // column, which is very visible in play.  tb_food checks the whole period.
    //------------------------------------------------------------------
    wire [GX_W-1:0] fx_c = rnd[GX_W-1:0];
    wire [GY_W-1:0] fy_c = rnd[GX_W+GY_W-1:GX_W];
    wire food_in_range = (fx_c > FLD_X0[GX_W-1:0]) && (fx_c < FLD_X1[GX_W-1:0]) &&
                         (fy_c > FLD_Y0[GY_W-1:0]) && (fy_c < FLD_Y1[GY_W-1:0]);

    //------------------------------------------------------------------
    // main sequencer
    //------------------------------------------------------------------
    always @(posedge clk)
        if (!rst_n) begin
            st            <= S_TITLE;
            busy          <= 1'b0;
            body_load     <= 1'b0;
            body_move     <= 1'b0;
            body_grow     <= 1'b0;
            scan_req      <= 1'b0;
            cmp_food      <= 1'b0;
            cmp_skip_tail <= 1'b0;
            dir           <= 2'b00;
            score_bcd     <= 8'h00;
            food_r        <= {POS_W{1'b0}};
            food_en       <= 1'b0;
            build_cnt     <= {LEN_W{1'b0}};
            food_try      <= 3'd0;
        end else begin
            body_load <= 1'b0;
            body_move <= 1'b0;
            body_grow <= 1'b0;
            scan_req  <= 1'b0;

            case (st)
            //--------------------------------------------------------------
            S_TITLE: begin
                busy <= 1'b0;
                if (frame_done && ok_pend) begin
                    busy <= 1'b1;
                    st   <= S_NEW;
                end
            end
            //--------------------------------------------------------------
            S_NEW: begin
                busy      <= 1'b1;
                body_load <= 1'b1;             // head <= load_pos, len <= 1
                dir       <= 2'b00;
                score_bcd <= 8'h00;
                food_en   <= 1'b0;
                build_cnt <= INIT_LEN[LEN_W-1:0] - 1'b1;
                st        <= S_BUILD;
            end
            //--------------------------------------------------------------
            S_BUILD: begin              // walk right to reach the initial length
                if (build_cnt == {LEN_W{1'b0}}) begin
                    food_try <= 3'd0;
                    st       <= S_FOOD;
                end else begin
                    body_move <= 1'b1;         // dir is still RIGHT here
                    body_grow <= 1'b1;
                    build_cnt <= build_cnt - 1'b1;
                end
            end
            //--------------------------------------------------------------
            S_FOOD: begin               // re-roll until it is inside the field
                if (food_in_range) begin
                    food_r        <= {fy_c, fx_c};
                    cmp_food      <= 1'b1;
                    cmp_skip_tail <= 1'b0;
                    scan_req      <= 1'b1;
                    st            <= S_FSCAN;
                end
            end
            //--------------------------------------------------------------
            // Landing on the snake is the only thing that sends us back, and
            // that retry does have a give-up: after 7 goes the cell is taken as
            // it is.  Harmless - it is inside the field, and the tail vacates
            // it within a few steps.
            S_FSCAN: begin
                if (scan_done) begin
                    if (!cmp_hit || (food_try == 3'd7)) begin
                        food_en <= 1'b1;
                        st      <= S_IDLE;
                    end else begin
                        food_try <= food_try + 3'd1;
                        st       <= S_FOOD;
                    end
                end
            end
            //--------------------------------------------------------------
            S_IDLE: begin
                busy <= 1'b0;
                if (frame_done && tick_pend) begin
                    busy <= 1'b1;
                    dir  <= dir_nxt;
                    st   <= S_STEP;
                end
            end
            //--------------------------------------------------------------
            S_STEP: begin               // walls are pure combinational, no scan
                busy <= 1'b1;
                if (hit_wall) begin
                    st <= S_OVER;
                end else begin
                    cmp_food      <= 1'b0;     // test step_pos against the body
                    cmp_skip_tail <= 1'b1;     // the tail vacates this step
                    scan_req      <= 1'b1;
                    st            <= S_SSCAN;
                end
            end
            //--------------------------------------------------------------
            S_SSCAN: begin
                if (scan_done) begin
                    if (cmp_hit) begin
                        st <= S_OVER;
                    end else begin
                        body_move <= 1'b1;
                        if (eat_now) begin
                            body_grow <= 1'b1;
                            food_try  <= 3'd0;
                            st        <= S_FOOD;
                            if (score_bcd[3:0] != 4'd9)
                                score_bcd[3:0] <= score_bcd[3:0] + 4'd1;
                            else begin
                                score_bcd[3:0] <= 4'd0;
                                if (score_bcd[7:4] != 4'd9)
                                    score_bcd[7:4] <= score_bcd[7:4] + 4'd1;
                            end
                        end else begin
                            st <= S_IDLE;
                        end
                    end
                end
            end
            //--------------------------------------------------------------
            S_OVER: begin
                busy <= 1'b0;
                if (frame_done && ok_pend) begin
                    busy <= 1'b1;
                    st   <= S_NEW;
                end
            end
            default: st <= S_TITLE;
            endcase
        end

    //------------------------------------------------------------------
    // Elaboration guards.  Passing geometry in as parameters is only safe if
    // an inconsistent set cannot build: each of these instantiates a module
    // that does not exist, so the error names the parameter that is wrong.
    //------------------------------------------------------------------
    generate
        if (POS_W != GX_W + GY_W)
            ERROR_POS_W_must_equal_GX_W_plus_GY_W u_chk_pos ();
        if (FLD_X1 != (1 << GX_W) - 1)
            ERROR_FLD_X1_must_be_last_column u_chk_x1 ();
        if (FLD_Y1 != (1 << GY_W) - 1)
            ERROR_FLD_Y1_must_be_last_row u_chk_y1 ();
        if (FLD_X0 <= 0 || FLD_X0 >= FLD_X1)
            ERROR_FLD_X0_must_be_inside_the_grid u_chk_x0 ();
    endgenerate

endmodule
