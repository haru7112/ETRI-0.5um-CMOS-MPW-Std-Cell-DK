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
//     static part  : walls, status bar, food, UI text  -> pure combinational
//     snake part   : one rotation of the body register, ORing a cell mask into
//                    the accumulator whenever a segment lands on this byte
//
//  A body scan is MAXLEN clocks (48 @25MHz = 1.9us), comfortably inside the
//  I2C byte time, so the snake costs no display bandwidth at all.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module pixel_gen #(
    parameter CELL_SH  = 1,
    parameter MAXLEN   = 48,
    parameter EN_TEXT  = 1
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
    input  wire        blink,             // ~4Hz, makes the food distinguishable
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

    // character codes of font_rom
    localparam C_A=10, C_C=11, C_E=12, C_G=13, C_H=14, C_K=15, C_M=16,
               C_N=17, C_O=18, C_P=19, C_R=20, C_S=21, C_U=22, C_V=23, C_SP=24;

    wire [GX_W-1:0] food_x = food_pos_i[GX_W-1:0];
    wire [GY_W-1:0] food_y = food_pos_i[POS_W-1:GX_W];
    wire [GX_W-1:0] cell_x = x[6:CELL_SH];

    //------------------------------------------------------------------
    // Text layer
    //------------------------------------------------------------------
    wire [3:0] ch_idx = x[6:3];
    wire [2:0] ch_col = x[2:0];
    reg  [4:0] ch_code;
    wire [7:0] font_bits;

    font_rom #(.WITH_LETTERS(EN_TEXT)) u_font (
        .code (ch_code), .col (ch_col), .bits (font_bits));

    wire txt_title = EN_TEXT && st_title && ((page == 3'd3) || (page == 3'd5));
    wire txt_over  = EN_TEXT && st_over  &&  (page == 3'd3);
    wire txt_page  = (page == 3'd0) || txt_title || txt_over;

    always @* begin
        ch_code = C_SP;
        if (page == 3'd0) begin
            // status bar: "SCORE nnn"  (digits only when letters are compiled out)
            if (EN_TEXT) begin
                case (ch_idx)
                    4'd0: ch_code = C_S;
                    4'd1: ch_code = C_C;
                    4'd2: ch_code = C_O;
                    4'd3: ch_code = C_R;
                    4'd4: ch_code = C_E;
                    4'd6: ch_code = {1'b0, score_bcd[7:4]};
                    4'd7: ch_code = {1'b0, score_bcd[3:0]};
                    default: ch_code = C_SP;
                endcase
            end else begin
                case (ch_idx)
                    4'd0: ch_code = {1'b0, score_bcd[7:4]};
                    4'd1: ch_code = {1'b0, score_bcd[3:0]};
                    default: ch_code = C_SP;
                endcase
            end
        end else if (txt_over) begin
            case (ch_idx)                       // "GAME OVER"
                4'd3 : ch_code = C_G;
                4'd4 : ch_code = C_A;
                4'd5 : ch_code = C_M;
                4'd6 : ch_code = C_E;
                4'd8 : ch_code = C_O;
                4'd9 : ch_code = C_V;
                4'd10: ch_code = C_E;
                4'd11: ch_code = C_R;
                default: ch_code = C_SP;
            endcase
        end else if (txt_title && (page == 3'd3)) begin
            case (ch_idx)                       // "SNAKE"
                4'd5 : ch_code = C_S;
                4'd6 : ch_code = C_N;
                4'd7 : ch_code = C_A;
                4'd8 : ch_code = C_K;
                4'd9 : ch_code = C_E;
                default: ch_code = C_SP;
            endcase
        end else if (txt_title) begin
            case (ch_idx)                       // "PUSH OK"
                4'd4 : ch_code = C_P;
                4'd5 : ch_code = C_U;
                4'd6 : ch_code = C_S;
                4'd7 : ch_code = C_H;
                4'd9 : ch_code = C_O;
                4'd10: ch_code = C_K;
                default: ch_code = C_SP;
            endcase
        end
    end

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
    // Static layer: walls and food.
    //
    // The border needs no per pixel loop.  A side wall column is a solid
    // 0xFF whatever the page is, and the top and bottom walls always land on
    // page 1 and page 7 - FLD_Y0 = CPP and FLD_Y1 = GRID_H-1 shift down to
    // page 1 and page 7 for every supported cell size - so each is a single
    // constant mask.
    //------------------------------------------------------------------
    localparam [7:0] TOP_MASK = CELL_BITS[7:0];
    localparam [7:0] BOT_MASK = CELL_BITS[7:0] << ((CPP-1) << CELL_SH);

    wire side_wall = (cell_x == FLD_X0[GX_W-1:0]) || (cell_x == FLD_X1[GX_W-1:0]);

    reg [7:0] wall_byte;
    always @* begin
        if (side_wall)          wall_byte = 8'hFF;
        else if (page == 3'd1)  wall_byte = TOP_MASK;
        else if (page == 3'd7)  wall_byte = BOT_MASK;
        else                    wall_byte = 8'h00;
    end

    wire [7:0] food_byte = (food_en && blink && tgt_here) ? cell_mask : 8'h00;

    // page 0 is the status bar and owns its byte, a message page keeps the
    // side walls underneath so the frame never looks broken
    reg [7:0] static_byte;
    always @* begin
        if (page == 3'd0)      static_byte = font_bits;
        else if (txt_page)     static_byte = font_bits | wall_byte;
        else                   static_byte = wall_byte | food_byte;
    end

    //------------------------------------------------------------------
    // Snake layer: accumulate one rotation of the body register
    //------------------------------------------------------------------
    wire seg_here = scan_valid && !txt_page && !st_title && tgt_here;

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
                    dout  <= seg_here ? (acc | cell_mask) : acc;
                    valid <= 1'b1;
                    busy  <= 1'b0;
                end
            end
        end

endmodule
