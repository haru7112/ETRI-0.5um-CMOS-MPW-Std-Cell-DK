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
    parameter CELL_SH  = 1,
    parameter MAXLEN   = 48
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- byte request ----------------------------------------------------
    input  wire        req,               // pulse: build the byte for x/page
    input  wire [6:0]  x,
    input  wire [2:0]  page,
    output reg         valid,             // 1 clock pulse, dout is good
    output reg  [7:0]  dout,

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
`include "snake_params.vh"

    reg  busy;                      // high while a byte is being accumulated

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

    wire [7:0] food_byte = (food_en && blink && tgt_here) ? cell_mask : 8'h00;

    wire [7:0] score_byte = (page == SCORE_P[2:0]) ? font_bits : 8'h00;

    wire [7:0] static_byte = in_score ? (wall_byte | score_byte)
                                      : (wall_byte | food_byte);

    //------------------------------------------------------------------
    // Snake layer: accumulate one rotation of the body queue
    //------------------------------------------------------------------
    wire seg_here = scan_valid && !st_title && !in_score && tgt_here;

    reg [7:0] acc;

    always @(posedge clk)
        if (!rst_n) begin
            acc      <= 8'h00;
            busy     <= 1'b0;
            valid    <= 1'b0;
            dout     <= 8'h00;
            scan_req <= 1'b0;
        end else begin
            valid    <= 1'b0;
            scan_req <= 1'b0;
            if (req && !busy) begin
                acc      <= static_byte;
                busy     <= 1'b1;
                scan_req <= 1'b1;
            end else if (busy) begin
                if (seg_here)
                    acc <= acc | cell_mask;
                if (scan_done) begin
                    dout  <= acc;
                    valid <= 1'b1;
                    busy  <= 1'b0;
                end
            end
        end

endmodule
