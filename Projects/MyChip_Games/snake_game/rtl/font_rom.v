//----------------------------------------------------------------------------
// font_rom.v
//  Ten 5x7 digit glyphs inside an 8x8 character cell, column major, LSB = top
//  pixel, which is exactly the byte layout the SSD1315 expects in page mode.
//  Column 0 sits in the MSByte of the packed glyph; columns 5..7 are blank and
//  give the inter character gap for free.
//
//  Digits only.  The UI carries no words - the border blinks instead of
//  spelling GAME OVER - which on a process where a 2 input NAND costs
//  12x36um is worth about 0.06mm2 of silicon.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module font_rom (
    input  wire [3:0] digit,     // 0..9, anything else renders blank
    input  wire [2:0] col,       // 0..7, column inside the character cell
    output reg  [7:0] bits
);
    reg [39:0] glyph;            // 5 columns packed, col 0 in the MSByte

    always @* begin
        case (digit)
            4'd0 : glyph = 40'h3E_51_49_45_3E;
            4'd1 : glyph = 40'h00_42_7F_40_00;
            4'd2 : glyph = 40'h42_61_51_49_46;
            4'd3 : glyph = 40'h21_41_45_4B_31;
            4'd4 : glyph = 40'h18_14_12_7F_10;
            4'd5 : glyph = 40'h27_45_45_45_39;
            4'd6 : glyph = 40'h3C_4A_49_49_30;
            4'd7 : glyph = 40'h01_71_09_05_03;
            4'd8 : glyph = 40'h36_49_49_49_36;
            4'd9 : glyph = 40'h06_49_49_29_1E;
            default: glyph = 40'h00_00_00_00_00;
        endcase

        case (col)
            3'd0: bits = glyph[39:32];
            3'd1: bits = glyph[31:24];
            3'd2: bits = glyph[23:16];
            3'd3: bits = glyph[15:8];
            3'd4: bits = glyph[7:0];
            default: bits = 8'h00;
        endcase
    end

endmodule
