//----------------------------------------------------------------------------
// snake_top.v
//  Core top level of the SNAKE chip: 25MHz in, an SSD1315 panel and a 5-way
//  switch out, nothing else.  No CPU, no memory macro, no frame buffer.
//
//  Everything the chip remembers is:
//      - MAXLEN x POS_W  body shift register   (snake_body)
//      - head, length, direction, score, food  (~50 flops)
//      - the display sequencer and I2C engine  (~60 flops)
//
//  The panel is on 4-wire SPI (SSD1306), so every display pin is a plain
//  output - no open drain, no tri-state net crossing the synthesised core,
//  and no pull-up resistors on the board.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module snake_top #(
    parameter CLK_HZ   = 25_000_000,
    parameter SCLK_HZ  = 6_250_000,
    parameter CELL_SH  = 1,          // 1 = 2x2px cells -> 64x32 grid
    parameter MAXLEN   = 48,         // longest snake the register can hold
    parameter LEN_W    = 6,          // must cover MAXLEN
    parameter INIT_LEN = 3,
    parameter RES_MS   = 20,
    parameter STEP_MS  = 208         // ms per game step, fixed (no ramp)
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire [4:0] btn_n,         // [0]UP [1]DOWN [2]LEFT [3]RIGHT [4]OK, active low
    output wire       oled_res_n,
    output wire       oled_sclk,     // 4-wire SPI to the SSD1306
    output wire       oled_mosi,
    output wire       oled_dc,       // 0 = command, 1 = display data
    output wire       oled_cs_n,
    output wire       led_alive
);
    //------------------------------------------------------------------
    // Screen geometry.  THIS IS THE ONLY PLACE IT IS DEFINED.
    //
    // The panel is fixed at 128 x 64 in 8 pages of 8 rows.  CELL_SH sets the
    // game cell size, everything else follows, and the sub-blocks receive the
    // results as parameters rather than deriving them again - so changing the
    // layout means editing these lines and nothing else.
    //
    //      CELL_SH = 1 -> 2x2 px cells -> 64 x 32 grid
    //      CELL_SH = 2 -> 4x4 px cells -> 32 x 16 grid   (default)
    //      CELL_SH = 3 -> 8x8 px cells -> 16 x  8 grid
    //
    //      x=0        16                                             127
    //       +-----------------------------------------------------------+ y=0
    //       |          |                                                |
    //       |    42    |                 play field                     |
    //       +-----------------------------------------------------------+ y=63
    //        score      ^ vertical divider, which is also the left wall
    //------------------------------------------------------------------
    localparam GX_W    = 7 - CELL_SH;        // bits of a cell X coordinate
    localparam GY_W    = 6 - CELL_SH;        // bits of a cell Y coordinate
    localparam POS_W   = GX_W + GY_W;        // packed {y,x} cell position
    localparam GRID_W  = (1 << GX_W);        // cells per row
    localparam GRID_H  = (1 << GY_W);        // cells per column
    localparam SCORE_W = (16 >> CELL_SH);    // score column width, in cells
    localparam SCORE_P = 3;                  // page the two digits sit on
    localparam FLD_X0  = SCORE_W;            // divider column, the left wall
    localparam FLD_X1  = GRID_W - 1;         // right wall
    localparam FLD_Y0  = 0;                  // top rule
    localparam FLD_Y1  = GRID_H - 1;         // bottom rule

    //------------------------------------------------------------------
    // Time base: one free running counter, and every slow event is an edge on
    // one of its bits.
    //
    // This was a divide-by-25000 down to a millisecond strobe plus a second
    // counter of milliseconds - two incrementers, a 15 bit comparator and a
    // reload mux on the first one.  Nothing here needs a round number of
    // milliseconds, only a steady tick, so the comparator and the reload go
    // and the two counters become one.  Bit n toggles every 2^n clocks, which
    // at 25MHz is:
    //
    //      bit 14 ->  1.31ms      bit 21 ->  84ms
    //      bit 18 -> 21.0ms       bit 22 -> 168ms
    //
    // The counter is only as wide as the highest tap anyone uses.  It was two
    // bits wider to give the heartbeat a 1.3s period; 0.67s looks the same and
    // the two bits, with their two stages of carry, do not.
    //
    // The taps follow CLK_HZ, so a test bench can run the core on a slower
    // clock and every ratio in the design stays where it is.  TICK_MS tells
    // game_ctrl what a step tick is worth, so STEP_MS stays in milliseconds.
    //------------------------------------------------------------------
    localparam integer TAP_MS   = $clog2(CLK_HZ / 1000) - 1;   // ~1ms
    localparam integer TAP_STEP = TAP_MS + 4;                  // ~16x that
    localparam integer TMR_W    = TAP_MS + 9;
    localparam integer TICK_MS  = ((1 << (TAP_STEP + 1)) + (CLK_HZ/2000))
                                  / (CLK_HZ / 1000);

    reg [TMR_W-1:0] tmr;
    reg             ms_d, step_d;

    always @(posedge clk)
        if (!rst_n) begin
            tmr    <= {TMR_W{1'b0}};
            ms_d   <= 1'b0;
            step_d <= 1'b0;
        end else begin
            tmr    <= tmr + 1'b1;
            ms_d   <= tmr[TAP_MS];
            step_d <= tmr[TAP_STEP];
        end

    wire ms_pulse  = tmr[TAP_MS]   & ~ms_d;    // panel reset, debouncer
    wire step_tick = tmr[TAP_STEP] & ~step_d;  // the game step

    // The blink phase is sampled once per frame so a border is never drawn
    // half lit.
    wire blink_raw = |tmr[TAP_MS+8 : TAP_MS+7];   // 3/4 of a ~170ms period
    reg  blink;

    always @(posedge clk)
        if (!rst_n)          blink <= 1'b1;
        else if (frame_done) blink <= blink_raw;

    //------------------------------------------------------------------
    // inputs
    //------------------------------------------------------------------
    wire [4:0] btn_level, btn_press;

    debounce #(.N(5)) u_deb (
        .clk(clk), .rst_n(rst_n), .ms_pulse(ms_pulse),
        .pin_n(btn_n), .level(btn_level), .press(btn_press));

    wire [10:0] rnd;
    lfsr11 u_rnd (.clk(clk), .rst_n(rst_n), .rnd(rnd));

    //------------------------------------------------------------------
    // snake body register + its serial scan port
    //------------------------------------------------------------------
    wire             body_load, body_move, body_grow, cmp_food, move_busy;
    wire [10:0]      load_pos, step_pos;
    wire [1:0]       step_dir;
    wire             g_scan_req, p_scan_req;
    wire [10:0]      cmp_pos;
    wire             cmp_skip_tail, scan_done, cmp_hit;
    wire [10:0]      scan_pos;
    wire             scan_valid;
    wire [LEN_W-1:0] len;

    wire [POS_W-1:0] scan_pos_n;
    wire [POS_W-1:0] head_n;
    wire [POS_W-1:0] step_pos_n;
    assign scan_pos = {{(11-POS_W){1'b0}}, scan_pos_n};

    snake_body #(.POS_W(POS_W), .GX_W(GX_W), .MAXLEN(MAXLEN), .LEN_W(LEN_W)) u_body (
        .clk(clk), .rst_n(rst_n),
        .load(body_load), .load_pos(load_pos[POS_W-1:0]),
        .move(body_move), .grow(body_grow), .move_busy(move_busy),
        .step_dir(step_dir), .step_pos(step_pos_n),
        .scan_req(g_scan_req | p_scan_req),
        .cmp_food(cmp_food),
        .cmp_pos(cmp_pos[POS_W-1:0]),
        .cmp_skip_tail(cmp_skip_tail),
        .scan_busy(),
        .scan_pos(scan_pos_n), .scan_valid(scan_valid), .scan_done(scan_done),
        .cmp_hit(cmp_hit),
        .head(head_n), .len(len));

    assign step_pos = {{(11-POS_W){1'b0}}, step_pos_n};

    //------------------------------------------------------------------
    // game rules
    //------------------------------------------------------------------
    wire        st_title, st_over, game_busy, frame_done, food_en;
    wire [10:0] food_pos;

    // The score is not counted; it is read off the snake.  Every meal grows
    // the body by one, so meals eaten is len - INIT_LEN and game_ctrl needs no
    // counter of its own - which was an 8 bit BCD register with a carry
    // between its digits, 0.038mm2 of game_ctrl.  Converting the binary length
    // to two digits for the font costs a pair of comparisons instead.
    wire [LEN_W-1:0] score = len - INIT_LEN[LEN_W-1:0];
    wire [3:0] sc_tens = (score >= 20) ? 4'd2 : (score >= 10) ? 4'd1 : 4'd0;
    wire [LEN_W-1:0] sc_sub = (sc_tens == 4'd2) ? 6'd20 :
                              (sc_tens == 4'd1) ? 6'd10 : 6'd0;
    wire [LEN_W-1:0] sc_rem  = score - sc_sub;
    wire [7:0] score_bcd = {sc_tens, sc_rem[3:0]};

    // The body register holds MAXLEN segments, so the length - and with it the
    // score - stops there.  len can never exceed MAXLEN (snake_body guards the
    // increment), so this is the "you filled it" flag and pixel_gen blinks the
    // digits on it.
    wire score_full = (len == MAXLEN[LEN_W-1:0]);

    game_ctrl #(.GX_W(GX_W), .GY_W(GY_W), .POS_W(POS_W),
                .FLD_X0(FLD_X0), .FLD_X1(FLD_X1),
                .FLD_Y0(FLD_Y0), .FLD_Y1(FLD_Y1),
                .MAXLEN(MAXLEN), .LEN_W(LEN_W), .INIT_LEN(INIT_LEN),
                .STEP_MS(STEP_MS), .TICK_MS(TICK_MS)) u_game (
        .clk(clk), .rst_n(rst_n), .tick(step_tick),
        .btn_level(btn_level), .btn_press(btn_press),
        .frame_done(frame_done), .busy(game_busy),
        .body_load(body_load), .body_move(body_move), .body_grow(body_grow),
        .load_pos(load_pos), .step_dir(step_dir), .step_pos(step_pos),
        .move_busy(move_busy),
        .scan_req(g_scan_req), .cmp_food(cmp_food),
        .cmp_pos(cmp_pos), .cmp_skip_tail(cmp_skip_tail),
        .scan_done(scan_done), .cmp_hit(cmp_hit),
        .len(len),
        .st_title(st_title), .st_over(st_over),
        .food_pos(food_pos), .food_en(food_en),
        .rnd(rnd));

    //------------------------------------------------------------------
    // frame generation + panel driver
    //------------------------------------------------------------------
    wire       pix_req, pix_valid;
    wire [7:0] pix_data;
    wire [6:0] pix_x;
    wire [2:0] pix_page;

    pixel_gen #(.CELL_SH(CELL_SH), .GX_W(GX_W), .GY_W(GY_W), .POS_W(POS_W),
                .FLD_X0(FLD_X0), .FLD_X1(FLD_X1), .SCORE_P(SCORE_P),
                .MAXLEN(MAXLEN)) u_pix (
        .clk(clk), .rst_n(rst_n),
        .req(pix_req), .x(pix_x), .page(pix_page),
        .valid(pix_valid), .dout(pix_data),
        .st_title(st_title), .st_over(st_over), .score_bcd(score_bcd),
        .score_full(score_full),
        .blink(blink), .food_en(food_en),
        .scan_req(p_scan_req), .scan_pos_i(scan_pos), .scan_valid(scan_valid),
        .scan_done(scan_done), .food_pos_i(food_pos));

    wire display_on;

    oled_ctrl #(.RES_MS(RES_MS), .TICK_MS(TICK_MS),
                .CLK_HZ(CLK_HZ), .SCLK_HZ(SCLK_HZ)) u_oled (
        .clk(clk), .rst_n(rst_n), .tick(step_tick),
        .oled_res_n(oled_res_n),
        .oled_sclk(oled_sclk), .oled_mosi(oled_mosi),
        .oled_dc(oled_dc), .oled_cs_n(oled_cs_n),
        .pix_req(pix_req), .pix_x(pix_x), .pix_page(pix_page),
        .pix_valid(pix_valid), .pix_data(pix_data),
        .frame_done(frame_done), .game_busy(game_busy),
        .display_on(display_on));

    // slow heartbeat once the panel answered, fast blink while it does not
    assign led_alive = display_on ? tmr[TAP_MS+8] : tmr[TAP_MS+5];

endmodule
