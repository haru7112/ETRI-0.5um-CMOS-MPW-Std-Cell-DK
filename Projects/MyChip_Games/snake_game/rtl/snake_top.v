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
    // millisecond time base, shared by the debouncer, the game step timer
    // and the panel reset delay
    //------------------------------------------------------------------
    localparam integer MS_DIV = CLK_HZ / 1000;
    localparam integer MS_W   = $clog2(MS_DIV);

    reg [MS_W-1:0] ms_div;
    reg        ms_pulse;
    reg [9:0]  ms_free;

    always @(posedge clk)
        if (!rst_n) begin
            ms_div   <= {MS_W{1'b0}};
            ms_pulse <= 1'b0;
            ms_free  <= 10'd0;
        end else if (ms_div == (MS_DIV-1)) begin
            ms_div   <= {MS_W{1'b0}};
            ms_pulse <= 1'b1;
            ms_free  <= ms_free + 10'd1;
        end else begin
            ms_div   <= ms_div + 1'b1;
            ms_pulse <= 1'b0;
        end

    // The game step is counted in 16ms ticks rather than milliseconds, which
    // is what lets its counter be four bits wide instead of eight.  Both parts
    // are already here, so the tick costs one comparison and no flops.
    wire step_tick = ms_pulse && (ms_free[3:0] == 4'd0);

    // The blink phase is sampled once per frame.  A frame takes ~25ms to
    // shift out, so a free running blink would toggle in the middle of one and
    // leave the border half drawn.
    wire blink_raw = |ms_free[7:6];  // on for 3/4 of a 256ms period
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
    wire             body_load, body_move, body_grow, cmp_food;
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
        .move(body_move), .grow(body_grow),
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
    wire [7:0]  score_bcd;
    wire [10:0] food_pos;

    game_ctrl #(.GX_W(GX_W), .GY_W(GY_W), .POS_W(POS_W),
                .FLD_X0(FLD_X0), .FLD_X1(FLD_X1),
                .FLD_Y0(FLD_Y0), .FLD_Y1(FLD_Y1),
                .MAXLEN(MAXLEN), .LEN_W(LEN_W), .INIT_LEN(INIT_LEN),
                .STEP_MS(STEP_MS)) u_game (
        .clk(clk), .rst_n(rst_n), .tick(step_tick),
        .btn_level(btn_level), .btn_press(btn_press),
        .frame_done(frame_done), .busy(game_busy),
        .body_load(body_load), .body_move(body_move), .body_grow(body_grow),
        .load_pos(load_pos), .step_dir(step_dir), .step_pos(step_pos),
        .scan_req(g_scan_req), .cmp_food(cmp_food),
        .cmp_pos(cmp_pos), .cmp_skip_tail(cmp_skip_tail),
        .scan_done(scan_done), .cmp_hit(cmp_hit),
        .len(len),
        .st_title(st_title), .st_over(st_over), .score_bcd(score_bcd),
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
        .blink(blink), .food_en(food_en),
        .scan_req(p_scan_req), .scan_pos_i(scan_pos), .scan_valid(scan_valid),
        .scan_done(scan_done), .food_pos_i(food_pos));

    wire display_on;

    oled_ctrl #(.RES_MS(RES_MS),
                .CLK_HZ(CLK_HZ), .SCLK_HZ(SCLK_HZ)) u_oled (
        .clk(clk), .rst_n(rst_n), .ms_pulse(ms_pulse),
        .oled_res_n(oled_res_n),
        .oled_sclk(oled_sclk), .oled_mosi(oled_mosi),
        .oled_dc(oled_dc), .oled_cs_n(oled_cs_n),
        .pix_req(pix_req), .pix_x(pix_x), .pix_page(pix_page),
        .pix_valid(pix_valid), .pix_data(pix_data),
        .frame_done(frame_done), .game_busy(game_busy),
        .display_on(display_on));

    // slow heartbeat once the panel answered, fast blink while it does not
    assign led_alive = display_on ? ms_free[9] : ms_free[6];

endmodule
