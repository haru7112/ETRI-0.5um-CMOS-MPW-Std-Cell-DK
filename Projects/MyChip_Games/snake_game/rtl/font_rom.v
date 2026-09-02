//----------------------------------------------------------------------------
// font_rom.v
//  5x7 glyphs inside an 8x8 character cell, column major, LSB = top pixel,
//  which is exactly the byte layout the SSD1315 expects in page mode.
//  Column 0 sits in the MSByte of the packed glyph. Columns 5..7 are blank and give the inter character gap for free.
//
//  Only the characters actually needed by the UI are stored.  With
//  WITH_LETTERS = 0 the letter half is dropped and the ROM shrinks to the ten
//  digits used by the score, which matters on a process where a 2 input NAND
//  costs 12x36um.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module font_rom #(
    parameter WITH_LETTERS = 1
)(
    input  wire [4:0] code,      // see the CH_* codes below
    input  wire [2:0] col,       // 0..7, column inside the character cell
    output reg  [7:0] bits
);
    // character codes -------------------------------------------------------
    //  0..9  : digits '0'..'9'
    //  10..23: A C E G H K M N O P R S U V
    //  24    : blank (and every unused code)
    reg [39:0] glyph;            // 5 columns packed, col0 in the LSByte

    always @* begin
        case (code)
            5'd0 : glyph = 40'h3E_51_49_45_3E;   // 0
            5'd1 : glyph = 40'h00_42_7F_40_00;   // 1
            5'd2 : glyph = 40'h42_61_51_49_46;   // 2
            5'd3 : glyph = 40'h21_41_45_4B_31;   // 3
            5'd4 : glyph = 40'h18_14_12_7F_10;   // 4
            5'd5 : glyph = 40'h27_45_45_45_39;   // 5
            5'd6 : glyph = 40'h3C_4A_49_49_30;   // 6
            5'd7 : glyph = 40'h01_71_09_05_03;   // 7
            5'd8 : glyph = 40'h36_49_49_49_36;   // 8
            5'd9 : glyph = 40'h06_49_49_29_1E;   // 9
            default: glyph = 40'h00_00_00_00_00;
        endcase
        if (WITH_LETTERS) begin
            case (code)
                5'd10: glyph = 40'h7E_11_11_11_7E;   // A
                5'd11: glyph = 40'h3E_41_41_41_22;   // C
                5'd12: glyph = 40'h7F_49_49_49_41;   // E
                5'd13: glyph = 40'h3E_41_49_49_7A;   // G
                5'd14: glyph = 40'h7F_08_08_08_7F;   // H
                5'd15: glyph = 40'h7F_08_14_22_41;   // K
                5'd16: glyph = 40'h7F_02_0C_02_7F;   // M
                5'd17: glyph = 40'h7F_04_08_10_7F;   // N
                5'd18: glyph = 40'h3E_41_41_41_3E;   // O
                5'd19: glyph = 40'h7F_09_09_09_06;   // P
                5'd20: glyph = 40'h7F_09_19_29_46;   // R
                5'd21: glyph = 40'h46_49_49_49_31;   // S
                5'd22: glyph = 40'h3F_40_40_40_3F;   // U
                5'd23: glyph = 40'h1F_20_40_20_1F;   // V
                default: ;
            endcase
        end

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
