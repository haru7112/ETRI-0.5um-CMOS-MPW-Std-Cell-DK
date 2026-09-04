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
//  CS# rising between bursts already resynchronises the panel, but 9 bytes in
//  1033 is cheap insurance and it costs nothing in gates.
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
    reg [10:0] pkt_idx;

    assign oled_dc = (phase == P_FDATA);

    wire [7:0] init_rom_q;
    wire [7:0] pkt_byte = (phase == P_FDATA) ? pix_data : init_rom_q;

    spi_master #(.CLK_HZ(CLK_HZ), .SCLK_HZ(SCLK_HZ)) u_spi (
        .clk(clk), .rst_n(rst_n),
        .write(spi_write), .din(pkt_byte),
        .busy(spi_busy), .done(spi_done),
        .sclk(oled_sclk), .mosi(oled_mosi));

    // ---- SSD1306 power-up command list -----------------------------------
    reg [7:0] init_rom;
    assign init_rom_q = init_rom;

    always @* case (pkt_idx[5:0])
        6'd0 : init_rom = 8'hAE;   // display off
        6'd1 : init_rom = 8'hD5;   // display clock divide
        6'd2 : init_rom = 8'h80;
        6'd3 : init_rom = 8'hA8;   // multiplex ratio
        6'd4 : init_rom = 8'h3F;   //   = 64 rows
        6'd5 : init_rom = 8'hD3;   // display offset
        6'd6 : init_rom = 8'h00;
        6'd7 : init_rom = 8'h40;   // start line 0
        6'd8 : init_rom = 8'h8D;   // charge pump
        6'd9 : init_rom = 8'h14;   //   = enable
        6'd10: init_rom = 8'h20;   // memory addressing mode
        6'd11: init_rom = 8'h00;   //   = horizontal
        6'd12: init_rom = 8'hA1;   // segment remap
        6'd13: init_rom = 8'hC8;   // COM scan direction remapped
        6'd14: init_rom = 8'hDA;   // COM pin configuration
        6'd15: init_rom = 8'h12;   //   = alternative
        6'd16: init_rom = 8'h81;   // contrast
        6'd17: init_rom = 8'h7F;
        6'd18: init_rom = 8'hD9;   // pre-charge period
        6'd19: init_rom = 8'hF1;
        6'd20: init_rom = 8'hDB;   // VCOMH deselect level
        6'd21: init_rom = 8'h40;
        6'd22: init_rom = 8'hA4;   // resume from RAM
        6'd23: init_rom = 8'hA6;   // normal (not inverted)
        6'd24: init_rom = 8'h2E;   // scrolling off
        // The addressing window.  These six bytes are ALSO re-sent in front of
        // every frame - see the P_FCMD phase - so the same ROM serves both.
        6'd25: init_rom = 8'h21;   // column address
        6'd26: init_rom = 8'h00;
        6'd27: init_rom = 8'h7F;
        6'd28: init_rom = 8'h22;   // page address
        6'd29: init_rom = 8'h00;
        6'd30: init_rom = 8'h07;
        6'd31: init_rom = 8'hAF;   // display on
        default: init_rom = 8'hE3; // NOP
    endcase

    localparam [10:0] INIT_N    = 11'd32;
    localparam [10:0] WIN_FIRST = 11'd25;   // index of 0x21 in init_rom
    localparam [10:0] WIN_LAST  = 11'd30;   // index of the last window byte

    // ---- sequencer -------------------------------------------------------
    localparam T_RESLO = 3'd0, T_RESHI = 3'd1, T_FETCH = 3'd2,
               T_DATA  = 3'd3, T_DATAW = 3'd4, T_GAP0  = 3'd5, T_GAP = 3'd6;

    reg [2:0]  t_st;
    reg [5:0]  ms_cnt;
    reg        init_done;
    reg        pix_rdy;

    assign pix_x      = pkt_idx[6:0];
    assign pix_page   = pkt_idx[9:7];
    assign display_on = init_done;

    wire [10:0] pkt_last = (phase == P_INIT) ? INIT_N - 11'd1 :
                           (phase == P_FCMD) ? WIN_LAST : 11'd1023;

    always @(posedge clk)
        if (!rst_n) begin
            t_st       <= T_RESLO;
            phase      <= P_INIT;
            pkt_idx    <= 11'd0;
            ms_cnt     <= RES_MS[5:0];
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
                    if (ms_cnt == 6'd0) begin
                        ms_cnt <= RES_MS[5:0];
                        t_st   <= T_RESHI;
                    end else
                        ms_cnt <= ms_cnt - 6'd1;
                end
            end
            T_RESHI: begin
                oled_res_n <= 1'b1;
                if (ms_pulse) begin
                    if (ms_cnt == 6'd0) begin
                        pkt_idx   <= 11'd0;
                        oled_cs_n <= 1'b0;        // select for the whole burst
                        t_st      <= T_FETCH;
                    end else
                        ms_cnt <= ms_cnt - 6'd1;
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
                    pkt_idx <= pkt_idx + 11'd1;
                    t_st    <= T_FETCH;
                end else begin
                    // end of the burst: raise CS# so the panel resynchronises
                    oled_cs_n <= 1'b1;
                    case (phase)
                    P_INIT : begin
                        init_done <= 1'b1;
                        phase     <= P_FCMD;
                        pkt_idx   <= WIN_FIRST;
                        oled_cs_n <= 1'b0;
                        t_st      <= T_FETCH;
                    end
                    P_FCMD : begin
                        phase     <= P_FDATA;
                        pkt_idx   <= 11'd0;
                        oled_cs_n <= 1'b0;
                        t_st      <= T_FETCH;
                    end
                    default: begin
                        frame_done <= 1'b1;       // let the game advance a step
                        phase      <= P_FCMD;
                        pkt_idx    <= WIN_FIRST;
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
