//----------------------------------------------------------------------------
// pixel_gen.v
//  Procedural frame generator - the reason this chip needs no frame buffer.
//
//  The application board takes the frame one bit at a time in raster order, so
//  this block answers exactly one question per request: is pixel (x, y) lit?
//
//     static part  : the two rules, the divider, the score, the food
//     snake part   : one rotation of the body queue, setting the accumulator
//                    if any segment lands on this pixel's cell
//
//  It used to build a whole 8 row page byte at a time, because the SSD1315 is
//  addressed by page - that cost a shifted cell mask, an eight bit
//  accumulator and two constant page masks for the rules.  Working a pixel at
//  a time deletes all of it: everything below is a comparison on cell
//  coordinates.
//
//  A body scan is MAXLEN clocks (32 @25MHz = 1.3us) and the board never asks
//  for pixels faster than that, so the snake costs no display bandwidth.
//
//  There is no text anywhere: the border blinks while the game waits for OK,
//  which reads as clearly as the word GAME OVER and costs two gates instead
//  of fourteen letters of font ROM.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module pixel_gen #(
    // CELL_SH stays because this block works in pixels: it needs the cell size
    // to turn a pixel coordinate into a cell coordinate and to find the pixel's
    // position inside its cell.  Everything that is a *decision* about the
    // screen layout comes down from snake_top instead, so there is one place
    // that defines it.
    parameter CELL_SH  = 1,      // cell edge = 2^CELL_SH pixels
    parameter GX_W     = 6,      // bits of a cell X coordinate
    parameter GY_W     = 5,      // bits of a cell Y coordinate
    parameter POS_W    = 11,     // packed {y,x}, = GX_W + GY_W
    parameter FLD_X0   = 8,      // divider column, the left wall
    parameter FLD_X1   = 63,     // right wall
    parameter FLD_Y0   = 0,      // top rule
    parameter FLD_Y1   = 31,     // bottom rule
    parameter SCORE_P  = 3,      // page the two score digits sit on
    parameter MAXLEN   = 48
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- pixel request ---------------------------------------------------
    input  wire        req,               // pulse: resolve the pixel at x/y
    input  wire [6:0]  x,
    input  wire [5:0]  y,
    output reg         valid,             // 1 clock pulse, dout is good
    output reg         dout,

    // ---- game state ------------------------------------------------------
    input  wire        st_title,
    input  wire        st_over,
    input  wire [7:0]  score_bcd,         // 2 BCD digits, {tens, units}
    input  wire        blink,             // ~4Hz
    input  wire        food_en,

    // ---- body scan port --------------------------------------------------
    output reg         scan_req,
    input  wire [10:0] scan_pos_i,        // widest supported POS_W
    input  wire        scan_valid,
    input  wire        scan_done,
    input  wire [10:0] food_pos_i
);
    reg  busy;                      // high while a pixel is being resolved

    localparam CELL_PX = (1 << CELL_SH);        // pixels per cell edge

    wire [GX_W-1:0] cell_x = x[6:CELL_SH];
    wire [GY_W-1:0] cell_y = y[5:CELL_SH];

    //------------------------------------------------------------------
    // Score: two digits in the left column, on one page only
    //------------------------------------------------------------------
    wire       in_score = (cell_x < FLD_X0[GX_W-1:0]);
    wire [3:0] digit    = x[3] ? score_bcd[3:0] : score_bcd[7:4];
    wire [7:0] font_bits;

    font_rom u_font (.digit(digit), .col(x[2:0]), .bits(font_bits));

    wire score_on = (y[5:3] == SCORE_P[2:0]) && font_bits[y[2:0]];

    //------------------------------------------------------------------
    // Cell comparator, shared between the food and the body scan.
    //
    // The two never need it in the same cycle - the food is resolved when the
    // pixel is requested, the body during the rotation that follows - so one
    // comparator serves both.
    //------------------------------------------------------------------
    wire [POS_W-1:0] tgt   = busy ? scan_pos_i[POS_W-1:0] : food_pos_i[POS_W-1:0];
    wire             tgt_here = (tgt == {cell_y, cell_x});

    //------------------------------------------------------------------
    // Border.  In cell coordinates each wall is one comparison.
    //
    // While the game waits for OK (title, or after a crash) the whole border
    // blinks.  That is the only "GAME OVER" this chip needs.
    //------------------------------------------------------------------
    wire border_on = ~(st_title | st_over) | blink;

    wire wall = (cell_x == FLD_X0[GX_W-1:0]) || (cell_x == FLD_X1[GX_W-1:0]) ||
                (cell_y == FLD_Y0[GY_W-1:0]) || (cell_y == FLD_Y1[GY_W-1:0]);

    wire wall_on = border_on && wall;

    //------------------------------------------------------------------
    // Food.  It used to blink so it could not be mistaken for a body
    // segment; drawing it hollow says the same thing without the flicker.
    //
    //   body            food
    //   # # # #         # # # #
    //   # # # #         # . . #
    //   # # # #         # . . #
    //   # # # #         # # # #
    //
    // A 2x2 cell has no room for an outline, so that build - and only that
    // build - falls back to blinking; the term folds away otherwise.
    //------------------------------------------------------------------
    localparam FOOD_SOLID = (CELL_PX < 4);

    wire [2:0] xin = x[2:0] & (CELL_PX[2:0] - 3'd1);   // position inside the cell
    wire [2:0] yin = y[2:0] & (CELL_PX[2:0] - 3'd1);
    wire ring = (xin == 3'd0) || (xin == (CELL_PX[2:0] - 3'd1)) ||
                (yin == 3'd0) || (yin == (CELL_PX[2:0] - 3'd1));

    wire food_on = food_en && tgt_here && (FOOD_SOLID ? blink : ring);

    wire static_on = in_score ? (wall_on | score_on)
                              : (wall_on | food_on);

    //------------------------------------------------------------------
    // Snake layer: one rotation of the body queue sets the accumulator
    //------------------------------------------------------------------
    wire seg_here = scan_valid && !st_title && !in_score && tgt_here;

    reg acc;

    always @(posedge clk)
        if (!rst_n) begin
            acc      <= 1'b0;
            busy     <= 1'b0;
            valid    <= 1'b0;
            dout     <= 1'b0;
            scan_req <= 1'b0;
        end else begin
            valid    <= 1'b0;
            scan_req <= 1'b0;
            if (req && !busy) begin
                acc      <= static_on;
                busy     <= 1'b1;
                scan_req <= 1'b1;
            end else if (busy) begin
                if (seg_here)
                    acc <= 1'b1;
                if (scan_done) begin
                    // seg_here is ORed in here as well: when the snake is at
                    // full length its last segment is presented on the same
                    // clock as scan_done, and reading acc alone would drop it
                    dout  <= acc | seg_here;
                    valid <= 1'b1;
                    busy  <= 1'b0;
                end
            end
        end

endmodule
