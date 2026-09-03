//----------------------------------------------------------------------------
// font_rom.v
//  Ten 3x5 digit glyphs inside an 8x8 character cell, column major, LSB = top
//  pixel, which is exactly the byte layout the SSD1315 expects in page mode.
//
//  The glyph is centred in the cell rather than sitting in its corner:
//  columns 2..4 of eight, and rows 1..5 of eight.  Centring is free - the
//  vertical offset is baked into the constants below (each column is already
//  shifted up by one) and the horizontal offset is which values the column
//  case matches on.  Neither costs a gate.
//
//      col   0 1 2 3 4 5 6 7
//    row 0   . . . . . . . .
//    row 1   . . # # # . . .
//    row 2   . . # . # . . .
//    row 3   . . # . # . . .
//    row 4   . . # . # . . .
//    row 5   . . # # # . . .
//    row 6   . . . . . . . .
//    row 7   . . . . . . . .
//
//  This was a 5x7 font.  Ten glyphs of five columns is 400 bits of mux; three
//  columns is 240, and measured on the ETRI cells the block goes from
//  0.0592mm2 to 0.0262mm2 - 56% off, for digits that are still perfectly
//  legible on a 128x64 panel.  On a process where a 2 input NAND costs
//  12x36um that is worth more than it looks.
//
//  Digits only.  The UI carries no words - the border blinks instead of
//  spelling GAME OVER.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module font_rom (
    input  wire [3:0] digit,     // 0..9, anything else renders blank
    input  wire [2:0] col,       // 0..7, column inside the character cell
    output reg  [7:0] bits
);
    // 3 columns packed, col 0 in the MSByte, each already shifted up one row
    reg [23:0] glyph;

    always @* begin
        case (digit)
            4'd0 : glyph = 24'h3E_22_3E;
            4'd1 : glyph = 24'h24_3E_20;
            4'd2 : glyph = 24'h3A_2A_2E;
            4'd3 : glyph = 24'h22_2A_3E;
            4'd4 : glyph = 24'h0E_08_3E;
            4'd5 : glyph = 24'h2E_2A_3A;
            4'd6 : glyph = 24'h3E_2A_3A;
            4'd7 : glyph = 24'h02_02_3E;
            4'd8 : glyph = 24'h3E_2A_3E;
            4'd9 : glyph = 24'h2E_2A_3E;
            default: glyph = 24'h00_00_00;
        endcase

        case (col)
            3'd2: bits = glyph[23:16];
            3'd3: bits = glyph[15:8];
            3'd4: bits = glyph[7:0];
            default: bits = 8'h00;
        endcase
    end

endmodule
