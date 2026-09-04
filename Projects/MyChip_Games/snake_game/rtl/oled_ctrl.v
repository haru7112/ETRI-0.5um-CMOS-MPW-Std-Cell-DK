//----------------------------------------------------------------------------
// oled_ctrl.v
//  SSD1306 panel sequencer, 4-wire SPI.
//
//  Three phases:
//      P_INIT   the power-up command list, once after reset
//      P_FCMD   the addressing window, re-sent in front of every frame
//      P_FDATA  1024 bytes of picture, fetched from pixel_gen on demand
//
//  This was I2C.  SPI is the same job with most of the protocol deleted: no
//  slave address, no control byte in front of every payload byte, no ACK to
//  check, no open drain pair.  Command versus data is the D/C# pin, held for a
//  whole burst instead of prefixed to each byte, so the sequencer loses four
//  states as well - measured together at 0.140 -> 0.070mm2 for the shifter and
//  another 0.03 here.
//
//  Re-sending the window every frame is kept.  On I2C it was the only way a
//  framing glitch could heal, since the panel ACKs whatever it is sent; on SPI
//  CS# rising between bursts already resynchronises the panel.  It is not free
//  - dropping it, and with it the six window bytes and one bit of phase, is
//  worth 0.032mm2, measured - but it is the only thing standing between one
//  lost bit on the SCLK wire and a picture that stays wrong until someone
//  presses reset.  Six bytes in 1030 buys that back every frame.
//
//  Two things about the counters, both measured at 0.015mm2 together:
//    - pkt_idx is 10 bits, not 11.  The longest burst is 1024 bytes, so 1023
//      is the largest value it ever holds and the eleventh bit was dead.
//    - every burst starts at index zero, including the per frame window, which
//      is why the window sits at the FRONT of the init ROM.  A reload with a
//      constant costs a mux on every bit; a reload with zero is a clear.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module oled_ctrl #(
    parameter RES_MS  = 20,          // RES# low, and then settle, in ms
    parameter CLK_HZ  = 25_000_000,
    parameter SCLK_HZ =  6_250_000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ms_pulse,

    output reg         oled_res_n,

    // ---- 4-wire SPI to the panel ----------------------------------------
    output wire        oled_sclk,
    output wire        oled_mosi,
    output wire        oled_dc,     // 0 = command, 1 = display data
    output reg         oled_cs_n,

    // ---- picture source --------------------------------------------------
    output reg         pix_req,
    output wire [6:0]  pix_x,
    output wire [2:0]  pix_page,
    input  wire        pix_valid,
    input  wire [7:0]  pix_data,

    // ---- game handshake --------------------------------------------------
    output reg         frame_done,
    input  wire        game_busy,
    output wire        display_on   // high once the panel has been initialised
);
    reg        spi_write;
    wire       spi_busy, spi_done;

    localparam P_INIT = 2'd0, P_FCMD = 2'd1, P_FDATA = 2'd2;

    reg [1:0]  phase;
    reg [9:0]  pkt_idx;

    assign oled_dc = (phase == P_FDATA);

    wire [7:0] init_rom_q;
    wire [7:0] pkt_byte = (phase == P_FDATA) ? pix_data : init_rom_q;

    spi_master #(.CLK_HZ(CLK_HZ), .SCLK_HZ(SCLK_HZ)) u_spi (
        .clk(clk), .rst_n(rst_n),
        .write(spi_write), .din(pkt_byte),
        .busy(spi_busy), .done(spi_done),
        .sclk(oled_sclk), .mosi(oled_mosi));

    // ---- SSD1306 power-up command list -----------------------------------
    //
    // RES# is driven low and released above, so every register is at its reset
    // default when this list runs, and most of what a typical init sequence
    // sends is that default written back.  Only the four settings the default
    // gets wrong are here:
    //
    //   8D 14  charge pump on   - default is off, and nothing lights without it
    //   20 00  horizontal mode  - default is page mode, which does not wrap
    //   A1     segment remap    - default A0, mirrors the picture
    //   C8     COM scan up      - default C0, flips the picture
    //
    // Dropped as already correct after reset: D5 80 (clock divide), A8 3F
    // (multiplex), D3 00 (offset), 40 (start line), DA 12 (COM pins, which is
    // the 128x64 default), 81 7F (contrast), A4 (resume from RAM), A6 (not
    // inverted), 2E (scrolling off).  D9 F1 and DB 40 tune pre-charge and
    // VCOMH; the defaults 22 and 20 drive this panel perfectly well.
    //
    // 32 bytes of ROM become 14, and the case that decodes them shrinks with
    // it.
    reg [7:0] init_rom;
    assign init_rom_q = init_rom;

    always @* case (pkt_idx[3:0])
        // The addressing window comes FIRST so that every burst this block
        // ever sends starts at index zero - the init list, the per frame
        // window, and the 1024 data bytes alike.  pkt_idx therefore only ever
        // reloads with a zero, which is a clear and not a constant mux.
        4'd0 : init_rom = 8'h21;   // column address
        4'd1 : init_rom = 8'h00;
        4'd2 : init_rom = 8'h7F;
        4'd3 : init_rom = 8'h22;   // page address
        4'd4 : init_rom = 8'h00;
        4'd5 : init_rom = 8'h07;
        4'd6 : init_rom = 8'hAE;   // display off while we set the rest up
        4'd7 : init_rom = 8'h8D;   // charge pump
        4'd8 : init_rom = 8'h14;   //   = enable
        4'd9 : init_rom = 8'h20;   // memory addressing mode
        4'd10: init_rom = 8'h00;   //   = horizontal, so it wraps for us
        4'd11: init_rom = 8'hA1;   // segment remap
        4'd12: init_rom = 8'hC8;   // COM scan direction remapped
        4'd13: init_rom = 8'hAF;   // display on
        default: init_rom = 8'hE3; // NOP
    endcase

    localparam [9:0]  INIT_N   = 10'd14;
    localparam [9:0]  WIN_LAST = 10'd5;    // last byte of the window burst

    // ---- sequencer -------------------------------------------------------
    localparam T_RESLO = 3'd0, T_RESHI = 3'd1, T_FETCH = 3'd2,
               T_DATA  = 3'd3, T_DATAW = 3'd4, T_GAP0  = 3'd5, T_GAP = 3'd6;

    reg [2:0]  t_st;
    reg [4:0]  ms_cnt;
    reg        init_done;
    reg        pix_rdy;

    assign pix_x      = pkt_idx[6:0];
    assign pix_page   = pkt_idx[9:7];
    assign display_on = init_done;

    wire [9:0]  pkt_last = (phase == P_INIT) ? INIT_N - 10'd1 :
                           (phase == P_FCMD) ? WIN_LAST : 10'd1023;


    always @(posedge clk)
        if (!rst_n) begin
            t_st       <= T_RESLO;
            phase      <= P_INIT;
            pkt_idx    <= 10'd0;
            ms_cnt     <= RES_MS[4:0];
            oled_res_n <= 1'b0;
            oled_cs_n  <= 1'b1;
            init_done  <= 1'b0;
            frame_done <= 1'b0;
            pix_req    <= 1'b0;
            spi_write  <= 1'b0;
            pix_rdy    <= 1'b0;
        end else begin
            if (pix_valid) pix_rdy <= 1'b1;
            spi_write  <= 1'b0;
            pix_req    <= 1'b0;
            frame_done <= 1'b0;

            case (t_st)
            //--------------------------------------------------------------
            T_RESLO: begin
                oled_res_n <= 1'b0;
                oled_cs_n  <= 1'b1;
                init_done  <= 1'b0;
                phase      <= P_INIT;
                if (ms_pulse) begin
                    if (ms_cnt == 5'd0) begin
                        ms_cnt <= RES_MS[4:0];
                        t_st   <= T_RESHI;
                    end else
                        ms_cnt <= ms_cnt - 5'd1;
                end
            end
            T_RESHI: begin
                oled_res_n <= 1'b1;
                if (ms_pulse) begin
                    if (ms_cnt == 5'd0) begin
                        pkt_idx   <= 10'd0;
                        oled_cs_n <= 1'b0;        // select for the whole burst
                        t_st      <= T_FETCH;
                    end else
                        ms_cnt <= ms_cnt - 5'd1;
                end
            end
            //--------------------------------------------------------------
            T_FETCH: begin
                if (phase == P_FDATA) begin
                    pix_req <= 1'b1;
                    pix_rdy <= 1'b0;
                end
                t_st <= T_DATA;
            end
            T_DATA: begin
                if ((phase != P_FDATA) || pix_rdy) begin
                    if (!spi_busy) begin
                        spi_write <= 1'b1;
                        t_st      <= T_DATAW;
                    end
                end
            end
            T_DATAW: if (spi_done) begin
                if (pkt_idx != pkt_last) begin
                    pkt_idx <= pkt_idx + 10'd1;
                    t_st    <= T_FETCH;
                end else begin
                    // end of the burst: raise CS# so the panel resynchronises
                    oled_cs_n <= 1'b1;
                    case (phase)
                    P_INIT : begin
                        init_done <= 1'b1;
                        phase     <= P_FCMD;
                        pkt_idx   <= 10'd0;
                        oled_cs_n <= 1'b0;
                        t_st      <= T_FETCH;
                    end
                    P_FCMD : begin
                        phase     <= P_FDATA;
                        pkt_idx   <= 10'd0;
                        oled_cs_n <= 1'b0;
                        t_st      <= T_FETCH;
                    end
                    default: begin
                        frame_done <= 1'b1;       // let the game advance a step
                        phase      <= P_FCMD;
                        pkt_idx    <= 10'd0;
                        t_st       <= T_GAP0;
                    end
                    endcase
                end
            end
            //--------------------------------------------------------------
            // one dead cycle so game_ctrl has registered its busy flag before
            // we look at it, then hold the panel idle until the step is done
            T_GAP0: t_st <= T_GAP;
            T_GAP : if (!game_busy) begin
                oled_cs_n <= 1'b0;
                t_st      <= T_FETCH;             // never tear a frame
            end
            //--------------------------------------------------------------
            default: t_st <= T_RESLO;
            endcase
        end

endmodule
