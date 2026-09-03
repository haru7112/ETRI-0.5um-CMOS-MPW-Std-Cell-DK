//----------------------------------------------------------------------------
// pixel_out.v
//  MyChip Games raster interface - the replacement for oled_ctrl + i2c_master.
//
//  The MyChip application board expects a game to hand it one bit per pixel in
//  raster order, exactly as pong_vh does:
//
//      p_tick   1 clock wide strobe, pixel is valid while it is high
//      pixel    the bit for (x, y), x sweeping fastest
//      v_sync   pulses after the last pixel of a frame
//
//  The frame is 128 x 64, the same geometry the SSD1315 had.  This block walks
//  the raster cursor and asks pixel_gen to resolve one pixel at a time; there
//  is nothing to cache, because consecutive pixels of a row are consecutive
//  columns, never consecutive rows.
//
//  Cost of a frame: 128 x 64 pixels x one body scan each.  With MAXLEN = 32
//  that is ~280k clocks, 11ms at 25MHz, about 90 frames per second - far more
//  than the panel ever got over I2C, and it is the design's time base: the
//  game step, the debouncer and the blink all count v_sync pulses.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module pixel_out #(
    parameter SCR_W  = 128,      // pixels per row
    parameter SCR_H  = 64,       // rows per frame
    parameter VS_LEN = 8         // clocks v_sync stays high
)(
    input  wire       clk,
    input  wire       rst_n,

    // ---- pixel source (pixel_gen) ---------------------------------------
    output reg        req,
    output wire [6:0] x,
    output wire [5:0] y,
    input  wire       valid,
    input  wire       din,

    // ---- platform stream -------------------------------------------------
    output reg        p_tick,
    output reg        pixel,
    output reg        v_sync,

    // ---- game handshake --------------------------------------------------
    output reg        frame_done,   // 1 clock pulse after the last pixel
    input  wire       game_busy     // hold the next frame off while it is high
);
    localparam S_IDLE = 2'd0,   // between frames, waiting for the game
               S_REQ  = 2'd1,   // ask pixel_gen for the byte under the cursor
               S_WAIT = 2'd2,   // wait for valid, emit the strobe
               S_VS   = 2'd3;   // vertical sync

    reg [1:0] st;
    reg [6:0] cx;
    reg [5:0] cy;
    reg [3:0] vs_cnt;

    assign x = cx;
    assign y = cy;

    wire last_x = (cx == (SCR_W-1));
    wire last_y = (cy == (SCR_H-1));

    always @(posedge clk)
        if (!rst_n) begin
            st         <= S_IDLE;
            cx         <= 7'd0;
            cy         <= 6'd0;
            vs_cnt     <= 4'd0;
            req        <= 1'b0;
            p_tick     <= 1'b0;
            pixel      <= 1'b0;
            v_sync     <= 1'b0;
            frame_done <= 1'b0;
        end else begin
            req        <= 1'b0;
            p_tick     <= 1'b0;
            frame_done <= 1'b0;

            case (st)
                S_IDLE: if (!game_busy) begin
                    cx  <= 7'd0;
                    cy  <= 6'd0;
                    req <= 1'b1;
                    st  <= S_WAIT;
                end

                S_REQ: begin
                    req <= 1'b1;
                    st  <= S_WAIT;
                end

                S_WAIT: if (valid) begin
                    pixel  <= din;
                    p_tick <= 1'b1;
                    if (!last_x) begin
                        cx <= cx + 7'd1;
                        st <= S_REQ;
                    end else begin
                        cx <= 7'd0;
                        if (!last_y) begin
                            cy <= cy + 6'd1;
                            st <= S_REQ;
                        end else begin
                            v_sync     <= 1'b1;
                            vs_cnt     <= VS_LEN[3:0];
                            frame_done <= 1'b1;
                            st         <= S_VS;
                        end
                    end
                end

                S_VS: if (vs_cnt == 4'd0) begin
                    v_sync <= 1'b0;
                    st     <= S_IDLE;
                end else
                    vs_cnt <= vs_cnt - 4'd1;

                default: st <= S_IDLE;
            endcase
        end

endmodule
