//----------------------------------------------------------------------------
// game_ctrl.v
//  Game rules and the only sequencer that mutates the snake.
//
//  All state changes happen in the gap between two OLED frames (frame_done ->
//  busy -> idle).  That keeps the picture tear free and, more importantly,
//  guarantees that the body shift register is never asked to move and to
//  rotate for a scan in the same cycle.
//
//  Direction encoding (chosen so that "opposite" is a single bit flip):
//      00 RIGHT (x+1)   01 DOWN (y+1)   10 LEFT (x-1)   11 UP (y-1)
//      bit0 = axis, bit1 = sign, opposite(d) = d ^ 2'b10
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module game_ctrl #(
    parameter CELL_SH  = 1,
    parameter MAXLEN   = 48,
    parameter LEN_W    = 6,
    parameter INIT_LEN = 3
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

    // body register control
    output reg         body_load,
    output reg         body_move,
    output reg         body_grow,
    output reg  [10:0] body_pos,
    output reg         scan_req,
    output reg  [10:0] cmp_pos,
    output reg         cmp_skip_tail,
    input  wire        scan_done,
    input  wire        cmp_hit,
    input  wire [10:0] head,
    input  wire [LEN_W-1:0] len,

    // rendering state
    output wire        st_title,
    output wire        st_over,
    output reg  [11:0] score_bcd,
    output reg  [10:0] food_pos,
    output reg         food_en,

    input  wire [15:0] rnd
);
`include "snake_params.vh"

    localparam CX0 = (GRID_W/2) - INIT_LEN;      // head of the freshly loaded snake
    localparam CY0 = (FLD_Y0 + FLD_Y1) / 2;

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
    reg  [7:0]       eaten;
    reg  [7:0]       ms_cnt;
    reg              tick_pend;
    reg              ok_pend;
    reg  [LEN_W-1:0] build_cnt;
    reg  [5:0]       food_try;

    assign st_title = (st == S_TITLE);
    assign st_over  = (st == S_OVER);

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
    // game step timer: millisecond prescaler, speed rises with the score
    //------------------------------------------------------------------
    wire [2:0] level    = (eaten[7:2] > 6'd7) ? 3'd7 : eaten[4:2];
    wire [7:0] speed_ms = 8'd200 - {1'b0, level, 4'b0};    // 200ms .. 88ms

    wire in_play = (st != S_TITLE) && (st != S_OVER) && (st != S_NEW);

    always @(posedge clk)
        if (!rst_n) begin
            ms_cnt    <= 8'd200;
            tick_pend <= 1'b0;
        end else if (!in_play) begin
            ms_cnt    <= speed_ms;
            tick_pend <= 1'b0;
        end else begin
            if (ms_pulse) begin
                if (ms_cnt == 8'd0) begin
                    ms_cnt    <= speed_ms;
                    tick_pend <= 1'b1;
                end else begin
                    ms_cnt <= ms_cnt - 8'd1;
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
    // next head position and the wall test
    //------------------------------------------------------------------
    wire [GX_W-1:0]  hx = head[GX_W-1:0];
    wire [GY_W-1:0]  hy = head[POS_W-1:GX_W];
    wire [GX_W-1:0]  nx = dir[0] ? hx : (dir[1] ? hx - 1'b1 : hx + 1'b1);
    wire [GY_W-1:0]  ny = dir[0] ? (dir[1] ? hy - 1'b1 : hy + 1'b1) : hy;
    wire [POS_W-1:0] next_head = {ny, nx};

    wire hit_wall = (nx == FLD_X0[GX_W-1:0]) || (nx == FLD_X1[GX_W-1:0]) ||
                    (ny == FLD_Y0[GY_W-1:0]) || (ny == FLD_Y1[GY_W-1:0]);

    wire eat_now  = food_en && (food_pos[POS_W-1:0] == next_head);

    //------------------------------------------------------------------
    // food candidate straight out of the LFSR, rejection sampled
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
            body_pos      <= 11'd0;
            scan_req      <= 1'b0;
            cmp_pos       <= 11'd0;
            cmp_skip_tail <= 1'b0;
            dir           <= 2'b00;
            eaten         <= 8'd0;
            score_bcd     <= 12'h000;
            food_pos      <= 11'd0;
            food_en       <= 1'b0;
            build_cnt     <= {LEN_W{1'b0}};
            food_try      <= 6'd0;
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
            // load == move with the length forced back to 1 (see snake_body)
            S_NEW: begin
                busy      <= 1'b1;
                body_load <= 1'b1;
                body_move <= 1'b1;
                body_pos  <= {{(11-POS_W){1'b0}}, CY0[GY_W-1:0], CX0[GX_W-1:0]};
                dir       <= 2'b00;
                eaten     <= 8'd0;
                score_bcd <= 12'h000;
                food_en   <= 1'b0;
                build_cnt <= INIT_LEN[LEN_W-1:0] - 1'b1;
                st        <= S_BUILD;
            end
            //--------------------------------------------------------------
            // The body control outputs are registered, so 'head' is one cycle
            // behind this state.  The build walk therefore advances body_pos
            // itself (x sits in the low bits of the packed position) instead of
            // reading head back, otherwise every step would write the same cell.
            S_BUILD: begin              // walk right to reach the initial length
                if (build_cnt == {LEN_W{1'b0}}) begin
                    food_try <= 6'd0;
                    st       <= S_FOOD;
                end else begin
                    body_move <= 1'b1;
                    body_grow <= 1'b1;
                    body_pos  <= body_pos + 11'd1;
                    build_cnt <= build_cnt - 1'b1;
                end
            end
            //--------------------------------------------------------------
            S_FOOD: begin               // draw a candidate inside the play area
                if (food_in_range || (food_try == 6'd63)) begin
                    cmp_pos       <= {{(11-POS_W){1'b0}}, fy_c, fx_c};
                    cmp_skip_tail <= 1'b0;
                    scan_req      <= 1'b1;
                    st            <= S_FSCAN;
                end
                if (food_try != 6'd63) food_try <= food_try + 6'd1;
            end
            //--------------------------------------------------------------
            S_FSCAN: begin              // reject it when it lands on the snake
                if (scan_done) begin
                    if (!cmp_hit || (food_try == 6'd63)) begin
                        food_pos <= cmp_pos;
                        food_en  <= 1'b1;
                        st       <= S_IDLE;
                    end else begin
                        st <= S_FOOD;
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
                    cmp_pos       <= {{(11-POS_W){1'b0}}, next_head};
                    cmp_skip_tail <= 1'b1;   // the tail vacates this step
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
                        body_pos  <= {{(11-POS_W){1'b0}}, next_head};
                        if (eat_now) begin
                            body_grow <= 1'b1;
                            eaten     <= eaten + 8'd1;
                            food_try  <= 6'd0;
                            st        <= S_FOOD;
                            // BCD score, 3 digits
                            if (score_bcd[3:0] != 4'd9)
                                score_bcd[3:0] <= score_bcd[3:0] + 4'd1;
                            else begin
                                score_bcd[3:0] <= 4'd0;
                                if (score_bcd[7:4] != 4'd9)
                                    score_bcd[7:4] <= score_bcd[7:4] + 4'd1;
                                else begin
                                    score_bcd[7:4] <= 4'd0;
                                    if (score_bcd[11:8] != 4'd9)
                                        score_bcd[11:8] <= score_bcd[11:8] + 4'd1;
                                end
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

endmodule
