//----------------------------------------------------------------------------
// pixel_gen.v
//  Procedural frame generator - the reason this chip needs no frame buffer.
//
//  The SSD1315 is written in horizontal addressing mode, so the panel asks for
//  1024 bytes in a fixed order; byte n covers column x = n[6:0] of page
//  p = n[9:7], i.e. the 8 pixels (x, 8p) .. (x, 8p+7) with bit0 on top.
//  Each byte is produced on demand, in the ~22us the I2C link needs to shift
//  the previous one out:
//
//     static part  : the two rules, the divider, the score, the food
//     snake part   : one rotation of the body queue, ORing a cell mask into
//                    the accumulator whenever a segment lands on this byte
//
//  A body scan is MAXLEN clocks (32 @25MHz = 1.3us), comfortably inside the
//  I2C byte time, so the snake costs no display bandwidth at all.
//
//  There is no text anywhere: the border blinks while the game waits for OK,
//  which reads as clearly as the word GAME OVER and costs two gates instead
//  of fourteen letters of font ROM.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module pixel_gen #(
    // CELL_SH stays because this block works in pixels: it needs the cell size
    // to slice a column index and to place a cell mask inside a page byte.
    // Everything that is a *decision* about the screen layout comes down from
    // snake_top instead, so there is one place that defines it.
    parameter CELL_SH  = 1,      // cell edge = 2^CELL_SH pixels
    parameter GX_W     = 6,      // bits of a cell X coordinate
    parameter GY_W     = 5,      // bits of a cell Y coordinate
    parameter POS_W    = 11,     // packed {y,x}, = GX_W + GY_W
    parameter FLD_X0   = 8,      // divider column, the left wall
    parameter FLD_X1   = 63,     // right wall
    parameter SCORE_P  = 3,      // page the two score digits sit on
    parameter MAXLEN   = 48
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- byte request ----------------------------------------------------
    input  wire        req,               // pulse: build the byte for x/page
    input  wire [6:0]  x,
    input  wire [2:0]  page,
    output wire        valid,             // 1 clock pulse, dout is good
    output wire [7:0]  dout,

    // ---- game state ------------------------------------------------------
    input  wire        st_title,
    input  wire        st_over,
    input  wire [7:0]  score_bcd,         // 2 BCD digits, {tens, units}
    input  wire        score_full,        // body is at MAXLEN: blink the digits
    input  wire        blink,             // ~4Hz
    input  wire        food_en,

    // ---- body scan port --------------------------------------------------
    output wire        scan_req,
    input  wire [10:0] scan_pos_i,        // widest supported POS_W
    input  wire        scan_valid,
    input  wire        scan_done,
    input  wire [10:0] food_pos_i
);
    reg  busy;                      // high while a byte is being accumulated

    // pure unit conversions from the cell size - no layout policy in them, so
    // they belong here rather than in the parameter list
    localparam CELL_PX   = (1 << CELL_SH);       // pixels per cell edge
    localparam CPP       = (8 >> CELL_SH);       // cells stacked in one page
    localparam SUB_W     = (3 - CELL_SH);        // bits selecting the cell in a page
    localparam CELL_BITS = (1 << CELL_PX) - 1;   // 2'b11 / 4'hF / 8'hFF
    localparam CPP_MASK  = CPP - 1;

    wire [GX_W-1:0] cell_x = x[6:CELL_SH];

    //------------------------------------------------------------------
    // Score: two digits in the left column, on one page only
    //------------------------------------------------------------------
    wire       in_score = (cell_x < FLD_X0[GX_W-1:0]);
    wire [3:0] digit    = x[3] ? score_bcd[3:0] : score_bcd[7:4];
    wire [7:0] font_bits;

    font_rom u_font (.digit(digit), .col(x[2:0]), .bits(font_bits));

    //------------------------------------------------------------------
    // Cell mask generator, shared between the food and the body scan.
    //
    // The two never need it in the same cycle - the food goes into the
    // accumulator when the byte is requested, the body during the rotation
    // that follows - so one comparator and one shifter serve both.
    //------------------------------------------------------------------
    wire [POS_W-1:0] tgt   = busy ? scan_pos_i[POS_W-1:0] : food_pos_i[POS_W-1:0];
    wire [GX_W-1:0]  tgt_x = tgt[GX_W-1:0];
    wire [GY_W-1:0]  tgt_y = tgt[POS_W-1:GX_W];
    wire [1:0]       sub   = tgt_y[1:0] & CPP_MASK[1:0];

    // NOTE: the width of a shift is the width of its left operand, so the shift
    // amount is widened first - (sub << CELL_SH) alone would wrap inside 2 bits.
    wire [3:0]       shamt = {2'b00, sub} << CELL_SH;
    wire [7:0]  cell_mask  = CELL_BITS[7:0] << shamt;
    wire        tgt_here   = (tgt_x == cell_x) && ((tgt_y >> SUB_W) == page);

    //------------------------------------------------------------------
    // Border.  No per pixel loop is needed: a wall column is a solid 0xFF
    // whatever the page, and the two rules always land on page 0 and page 7
    // - cell row 0 and row GRID_H-1 shift down to those pages for every
    // supported cell size - so each is a single constant mask.
    //
    // While the game waits for OK (title, or after a crash) the whole border
    // blinks.  That is the only "GAME OVER" this chip needs.
    //------------------------------------------------------------------
    localparam [7:0] TOP_MASK = CELL_BITS[7:0];
    localparam [7:0] BOT_MASK = CELL_BITS[7:0] << ((CPP-1) << CELL_SH);

    wire border_on = ~(st_title | st_over) | blink;

    wire [7:0] rules = ((page == 3'd0) ? TOP_MASK : 8'h00) |
                       ((page == 3'd7) ? BOT_MASK : 8'h00);
    wire side_wall   = (cell_x == FLD_X0[GX_W-1:0]) || (cell_x == FLD_X1[GX_W-1:0]);
    wire [7:0] wall_byte = border_on ? (side_wall ? 8'hFF : rules) : 8'h00;

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
    localparam [7:0] RING_MID = 8'h01 | (8'h01 << (CELL_PX - 1));

    wire [2:0] xin       = x[2:0] & (CELL_PX[2:0] - 3'd1);   // column in the cell
    wire       edge_col  = (xin == 3'd0) || (xin == (CELL_PX[2:0] - 3'd1));
    wire [7:0] food_pat  = edge_col ? CELL_BITS[7:0] : RING_MID;
    wire [7:0] food_mask = food_pat << shamt;

    wire food_show = food_en && tgt_here && (!FOOD_SOLID || blink);
    wire [7:0] food_byte = food_show ? food_mask : 8'h00;

    // The score cannot go past MAXLEN - INIT_LEN because the body register is
    // full there, so the two digits blink at the top instead of sitting still
    // and reading like a counter that has jammed.  It reuses the border blink,
    // which snake_top samples once per frame, so the tens and the units are
    // never caught in opposite phases - the score column is sixteen separate
    // byte requests and a free running blink would tear across them.
    wire score_on = ~score_full | blink;

    wire [7:0] score_byte = ((page == SCORE_P[2:0]) && score_on) ? font_bits
                                                                : 8'h00;

    wire [7:0] static_byte = in_score ? (wall_byte | score_byte)
                                      : (wall_byte | food_byte);

    //------------------------------------------------------------------
    // Snake layer: accumulate one rotation of the body queue
    //------------------------------------------------------------------
    wire seg_here = scan_valid && !st_title && !in_score && tgt_here;

    // The accumulator IS the output.  It used to be copied into a dout
    // register when the scan finished, which is eight flops and their mux to
    // buy a byte that is already stable: once busy drops, nothing writes acc
    // until the next req, and the next req cannot come until oled_ctrl has
    // handed the byte to the SPI shifter, which latches it on write.  So dout
    // is a wire and valid alone says when to look at it.
    reg [7:0] acc;
    assign dout = acc;

    // Both of these are one clock wide and both are already written on the
    // face of busy, so they are decodes rather than registers.  On a library
    // with no enable flop a registered pulse is a flop AND the feedback mux
    // that holds it low the rest of the time.
    assign scan_req = req && !busy;
    assign valid    = busy && scan_done;

    always @(posedge clk)
        if (!rst_n) begin
            acc      <= 8'h00;
            busy     <= 1'b0;
        end else begin
            if (req && !busy) begin
                acc  <= static_byte;
                busy <= 1'b1;
            end else if (busy) begin
                if (seg_here)
                    acc <= acc | cell_mask;
                if (scan_done) busy <= 1'b0;
            end
        end

    //------------------------------------------------------------------
    // Elaboration guards - see game_ctrl for why these are here
    //------------------------------------------------------------------
    generate
        if (POS_W != GX_W + GY_W)
            ERROR_POS_W_must_equal_GX_W_plus_GY_W u_chk_pos ();
        if (GX_W != 7 - CELL_SH)
            ERROR_GX_W_does_not_match_CELL_SH u_chk_gx ();
        if (GY_W != 6 - CELL_SH)
            ERROR_GY_W_does_not_match_CELL_SH u_chk_gy ();
        if (FLD_X1 != (1 << GX_W) - 1)
            ERROR_FLD_X1_must_be_last_column u_chk_x1 ();
    endgenerate

endmodule
