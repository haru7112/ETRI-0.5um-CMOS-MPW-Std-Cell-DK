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
//  The open drain bus is presented as separate *_oe / *_i signals so that the
//  ASIC top can wire them straight onto PADINOUT cells and the FPGA top onto
//  an IOBUF, without a tri-state net crossing the synthesised core.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module snake_top #(
    parameter CLK_HZ   = 25_000_000,
    parameter SCL_HZ   = 400_000,
    parameter CELL_SH  = 1,          // 1 = 2x2px cells -> 64x32 grid
    parameter MAXLEN   = 48,         // longest snake the register can hold
    parameter LEN_W    = 6,          // must cover MAXLEN
    parameter INIT_LEN = 3,
    parameter EN_TEXT  = 1,          // compile the letters of the UI messages
    parameter RES_MS   = 20
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire [4:0] btn_n,         // [0]UP [1]DOWN [2]LEFT [3]RIGHT [4]OK, active low
    output wire       oled_res_n,
    output wire       scl_oe,        // 1 = pull the line low
    output wire       sda_oe,
    input  wire       sda_i,
    output wire       led_alive
);
`include "snake_params.vh"

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

    wire blink = |ms_free[7:6];      // food on 3/4 of a 256ms period

    //------------------------------------------------------------------
    // inputs
    //------------------------------------------------------------------
    wire [4:0] btn_level, btn_press;

    debounce #(.N(5)) u_deb (
        .clk(clk), .rst_n(rst_n), .ms_pulse(ms_pulse),
        .pin_n(btn_n), .level(btn_level), .press(btn_press));

    wire [15:0] rnd;
    lfsr16 u_rnd (.clk(clk), .rst_n(rst_n), .rnd(rnd));

    //------------------------------------------------------------------
    // snake body register + its serial scan port
    //------------------------------------------------------------------
    wire             body_load, body_move, body_grow;
    wire [10:0]      body_pos;
    wire [1:0]       body_dir;
    wire             g_scan_req, p_scan_req;
    wire [10:0]      cmp_pos;
    wire             cmp_skip_tail, scan_done, cmp_hit;
    wire [10:0]      scan_pos;
    wire             scan_valid;
    wire [10:0]      head;
    wire [LEN_W-1:0] len;

    wire [POS_W-1:0] scan_pos_n;
    wire [POS_W-1:0] head_n;
    assign scan_pos = {{(11-POS_W){1'b0}}, scan_pos_n};
    assign head     = {{(11-POS_W){1'b0}}, head_n};

    snake_body #(.POS_W(POS_W), .GX_W(GX_W), .MAXLEN(MAXLEN), .LEN_W(LEN_W)) u_body (
        .clk(clk), .rst_n(rst_n),
        .load(body_load), .move(body_move), .grow(body_grow),
        .move_pos(body_pos[POS_W-1:0]), .move_dir(body_dir),
        .scan_req(g_scan_req | p_scan_req),
        .cmp_pos(cmp_pos[POS_W-1:0]),
        .cmp_skip_tail(cmp_skip_tail),
        .scan_busy(),
        .scan_pos(scan_pos_n), .scan_valid(scan_valid), .scan_done(scan_done),
        .cmp_hit(cmp_hit),
        .head(head_n), .len(len));

    //------------------------------------------------------------------
    // game rules
    //------------------------------------------------------------------
    wire        st_title, st_over, game_busy, frame_done, food_en;
    wire [11:0] score_bcd;
    wire [10:0] food_pos;

    game_ctrl #(.CELL_SH(CELL_SH), .MAXLEN(MAXLEN), .LEN_W(LEN_W),
                .INIT_LEN(INIT_LEN)) u_game (
        .clk(clk), .rst_n(rst_n), .ms_pulse(ms_pulse),
        .btn_level(btn_level), .btn_press(btn_press),
        .frame_done(frame_done), .busy(game_busy),
        .body_load(body_load), .body_move(body_move), .body_grow(body_grow),
        .body_pos(body_pos), .body_dir(body_dir),
        .scan_req(g_scan_req), .cmp_pos(cmp_pos), .cmp_skip_tail(cmp_skip_tail),
        .scan_done(scan_done), .cmp_hit(cmp_hit),
        .head(head), .len(len),
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

    pixel_gen #(.CELL_SH(CELL_SH), .MAXLEN(MAXLEN), .EN_TEXT(EN_TEXT)) u_pix (
        .clk(clk), .rst_n(rst_n),
        .req(pix_req), .x(pix_x), .page(pix_page),
        .valid(pix_valid), .dout(pix_data),
        .st_title(st_title), .st_over(st_over), .score_bcd(score_bcd),
        .blink(blink), .food_en(food_en),
        .scan_req(p_scan_req), .scan_pos_i(scan_pos), .scan_valid(scan_valid),
        .scan_done(scan_done), .food_pos_i(food_pos));

    wire display_on;

    oled_ctrl #(.I2C_ADDR(7'h3C), .RES_MS(RES_MS),
                .CLK_HZ(CLK_HZ), .SCL_HZ(SCL_HZ)) u_oled (
        .clk(clk), .rst_n(rst_n), .ms_pulse(ms_pulse),
        .oled_res_n(oled_res_n),
        .scl_oe(scl_oe), .sda_oe(sda_oe), .sda_i(sda_i),
        .pix_req(pix_req), .pix_x(pix_x), .pix_page(pix_page),
        .pix_valid(pix_valid), .pix_data(pix_data),
        .frame_done(frame_done), .game_busy(game_busy),
        .display_on(display_on));

    // slow heartbeat once the panel answered, fast blink while it does not
    assign led_alive = display_on ? ms_free[9] : ms_free[6];

endmodule
