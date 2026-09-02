//----------------------------------------------------------------------------
// tb_food.v - exhaustive check of food placement.
//
//  The LFSR has 2047 states, so "every candidate the chip can ever produce" is
//  a finite list and can be checked completely rather than sampled.  This test
//  walks the whole period, for every supported cell size, and checks:
//
//    1. food_in_range never accepts a cell outside the play field.  A cell on
//       a wall is invisible - the 0xFF wall byte covers it - so this is the
//       failure the player actually sees.
//    2. the re-roll loop in S_FOOD terminates: it measures the longest run of
//       consecutive rejected candidates, which bounds how long that state can
//       spin.  There is no give-up on this test by design, so the bound is the
//       only thing keeping it finite.
//    3. accepted cells are spread over the field rather than piling onto one
//       column, which is what clamping into range would have done (19% of all
//       food on the first column).
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_food;
    parameter CELL_SH = 2;

    localparam GX_W    = 7 - CELL_SH;
    localparam GY_W    = 6 - CELL_SH;
    localparam GRID_W  = (1 << GX_W);
    localparam GRID_H  = (1 << GY_W);
    localparam SCORE_W = (16 >> CELL_SH);
    localparam FLD_X0  = SCORE_W;
    localparam FLD_X1  = GRID_W - 1;
    localparam FLD_Y1  = GRID_H - 1;
    localparam PERIOD  = 2047;
    localparam MAX_RUN = 64;            // generous ceiling on the re-roll loop

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    wire [10:0] rnd;
    lfsr11 u_rnd (.clk(clk), .rst_n(rst_n), .rnd(rnd));

    // game_ctrl is instantiated so the REAL range predicate is exercised; it
    // stays in its title state and drives nothing here.
    game_ctrl #(.CELL_SH(CELL_SH), .MAXLEN(32), .LEN_W(6), .INIT_LEN(3)) u_game (
        .clk(clk), .rst_n(rst_n), .ms_pulse(1'b0),
        .btn_level(5'd0), .btn_press(5'd0),
        .frame_done(1'b0), .busy(),
        .body_load(), .body_move(), .body_grow(),
        .load_pos(), .step_dir(), .step_pos(11'd0),
        .scan_req(), .cmp_food(), .cmp_pos(), .cmp_skip_tail(),
        .scan_done(1'b0), .cmp_hit(1'b0), .len(6'd3),
        .st_title(), .st_over(), .score_bcd(), .food_pos(), .food_en(),
        .rnd(rnd));

    integer i, errors, run, worst, accepted;
    integer col_min, col_max, c;
    integer col_hits [0:127];
    reg [GX_W-1:0] fx;
    reg [GY_W-1:0] fy;

    initial begin
        errors = 0; run = 0; worst = 0; accepted = 0;
        for (i = 0; i < 128; i = i + 1) col_hits[i] = 0;
        #20 rst_n = 1;
        @(posedge clk);

        for (i = 0; i < PERIOD; i = i + 1) begin
            fx = u_game.fx_c;
            fy = u_game.fy_c;
            if (u_game.food_in_range) begin
                if (fx <= FLD_X0 || fx >= FLD_X1 || fy == 0 || fy >= FLD_Y1) begin
                    if (errors < 5)
                        $display("[FAIL] state %0d accepted (%0d,%0d), outside x %0d..%0d y 1..%0d",
                                 i, fx, fy, FLD_X0+1, FLD_X1-1, FLD_Y1-1);
                    errors = errors + 1;
                end
                accepted = accepted + 1;
                col_hits[fx] = col_hits[fx] + 1;
                run = 0;
            end else begin
                run = run + 1;
                if (run > worst) worst = run;
            end
            @(posedge clk);
        end

        col_min = PERIOD; col_max = 0;
        for (c = FLD_X0 + 1; c <= FLD_X1 - 1; c = c + 1) begin
            if (col_hits[c] < col_min) col_min = col_hits[c];
            if (col_hits[c] > col_max) col_max = col_hits[c];
        end

        $display("CELL_SH=%0d  grid %0dx%0d  field x %0d..%0d, y 1..%0d",
                 CELL_SH, GRID_W, GRID_H, FLD_X0+1, FLD_X1-1, FLD_Y1-1);
        $display("  %0d LFSR states, %0d accepted, %0d accepted outside the field",
                 PERIOD, accepted, errors);
        $display("  longest re-roll run = %0d clocks (%0d ns @25MHz)", worst, worst*40);
        $display("  per column hits: min %0d, max %0d", col_min, col_max);

        if (worst >= MAX_RUN) begin
            $display("[FAIL] re-roll loop can spin %0d clocks, ceiling is %0d",
                     worst, MAX_RUN);
            errors = errors + 1;
        end
        if (col_min == 0) begin
            $display("[FAIL] some field columns can never hold food");
            errors = errors + 1;
        end
        if (col_max > 4 * col_min) begin
            $display("[FAIL] food distribution is lopsided: max %0d vs min %0d",
                     col_max, col_min);
            errors = errors + 1;
        end

        if (errors == 0) $display("==== FOOD TB PASSED (CELL_SH=%0d) ====", CELL_SH);
        else             $display("==== FOOD TB FAILED (CELL_SH=%0d, %0d) ====", CELL_SH, errors);
        $finish;
    end
endmodule
