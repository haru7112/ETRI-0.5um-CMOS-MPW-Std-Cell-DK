//----------------------------------------------------------------------------
// oled_ctrl.v
//  SSD1315 bring-up and frame streamer.
//
//  Power-up:  RES# low -> RES# high -> command block (charge pump on, 128x64,
//             horizontal addressing, display on).
//  Steady state, repeated forever:
//      transaction 1 (command) : 21 00 7F   set column range 0..127
//                                22 00 07   set page   range 0..7
//      transaction 2 (data)    : 40 followed by 1024 bytes
//  Horizontal addressing makes the panel pointer wrap back to (0,0) on its own,
//  so a whole frame is one continuous burst - no per page overhead.
//
//  Every byte is checked for its ACK.  A NACK means the panel was unplugged or
//  browned out, so the sequencer drops back to the reset state and brings the
//  display up again by itself.  That is the only "watchdog" a chip with no CPU
//  can afford, and it makes the board hot-pluggable on the bench.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module oled_ctrl #(
    parameter CLK_HZ   = 25_000_000,
    parameter SCL_HZ   = 400_000,
    parameter I2C_ADDR = 7'h3C,
    parameter RES_MS   = 20        // reset pulse / settle time, milliseconds
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ms_pulse,

    // panel side
    output reg        oled_res_n,
    output wire       scl_oe,
    output wire       sda_oe,
    input  wire       sda_i,

    // pixel source
    output reg        pix_req,
    output wire [6:0] pix_x,
    output wire [2:0] pix_page,
    input  wire       pix_valid,
    input  wire [7:0] pix_data,

    // game handshake
    output reg        frame_done,      // 1 clock pulse between two frames
    input  wire       game_busy,

    output wire       display_on       // high once the panel has been initialised
);
    localparam INIT_N = 6'd32;

    // ---- I2C engine ------------------------------------------------------
    reg        i2c_start, i2c_write, i2c_stop;
    reg  [1:0] din_sel;
    wire [7:0] i2c_din = (din_sel == 2'd0) ? {I2C_ADDR, 1'b0}
                       : (din_sel == 2'd1) ? ((phase == P_FDATA) ? 8'h40 : 8'h00)
                       :                     pkt_byte;
    localparam D_ADDR = 2'd0, D_CTRL = 2'd1, D_BYTE = 2'd2;
    wire       i2c_busy, i2c_done, i2c_ack;

    i2c_master #(.CLK_HZ(CLK_HZ), .SCL_HZ(SCL_HZ)) u_i2c (
        .clk(clk), .rst_n(rst_n),
        .start(i2c_start), .write(i2c_write), .stop(i2c_stop), .din(i2c_din),
        .busy(i2c_busy), .done(i2c_done), .ack(i2c_ack),
        .scl_oe(scl_oe), .sda_oe(sda_oe), .sda_i(sda_i));

    // ---- SSD1315 power-up command list -----------------------------------
    reg [7:0] init_rom;
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
        // The addressing window is set once, here: horizontal addressing wraps
        // the panel's own pointer back to (0,0) after the last page, so every
        // later frame is one uninterrupted 1024 byte burst with no command
        // block in front of it.
        6'd25: init_rom = 8'h21;   // column address
        6'd26: init_rom = 8'h00;
        6'd27: init_rom = 8'h7F;
        6'd28: init_rom = 8'h22;   // page address
        6'd29: init_rom = 8'h00;
        6'd30: init_rom = 8'h07;
        6'd31: init_rom = 8'hAF;   // display on
        default: init_rom = 8'hE3; // NOP
    endcase

    // ---- sequencer -------------------------------------------------------
    localparam P_INIT = 1'b0, P_FDATA = 1'b1;

    localparam T_RESLO = 4'd0, T_RESHI = 4'd1, T_ADDR  = 4'd2, T_ADDRW = 4'd3,
               T_CTRL  = 4'd4, T_CTRLW = 4'd5, T_FETCH = 4'd6, T_DATA  = 4'd7,
               T_DATAW = 4'd8, T_STOP  = 4'd9, T_STOPW = 4'd10,
               T_GAP0  = 4'd11, T_GAP = 4'd12;

    reg [3:0]  t_st;
    reg        phase;
    reg [10:0] pkt_idx;
    reg [5:0]  ms_cnt;
    reg        init_done;
    reg        pix_rdy;

    assign pix_x    = pkt_idx[6:0];
    assign pix_page = pkt_idx[9:7];

    assign display_on = init_done;

    wire [10:0] pkt_last = (phase == P_INIT) ? {5'd0, INIT_N} - 11'd1 : 11'd1023;
    wire [7:0]  pkt_byte = (phase == P_INIT) ? init_rom : pix_data;

    always @(posedge clk)
        if (!rst_n) begin
            t_st       <= T_RESLO;
            phase      <= P_INIT;
            pkt_idx    <= 11'd0;
            ms_cnt     <= RES_MS[5:0];
            oled_res_n <= 1'b0;
            init_done  <= 1'b0;
            frame_done <= 1'b0;
            pix_req    <= 1'b0;
            i2c_start  <= 1'b0;
            i2c_write  <= 1'b0;
            i2c_stop   <= 1'b0;
            din_sel    <= D_ADDR;
            pix_rdy    <= 1'b0;
        end else begin
            if (pix_valid) pix_rdy <= 1'b1;
            i2c_start  <= 1'b0;
            i2c_write  <= 1'b0;
            i2c_stop   <= 1'b0;
            pix_req    <= 1'b0;
            frame_done <= 1'b0;

            case (t_st)
            //--------------------------------------------------------------
            T_RESLO: begin
                oled_res_n <= 1'b0;
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
                        pkt_idx <= 11'd0;
                        t_st    <= T_ADDR;
                    end else
                        ms_cnt <= ms_cnt - 6'd1;
                end
            end
            //--------------------------------------------------------------
            T_ADDR: if (!i2c_busy) begin
                din_sel   <= D_ADDR;                // slave address, write
                i2c_start <= 1'b1;
                t_st      <= T_ADDRW;
            end
            T_ADDRW: if (i2c_done) begin
                if (!i2c_ack) t_st <= T_RESLO;      // no panel out there
                else          t_st <= T_CTRL;
            end
            //--------------------------------------------------------------
            T_CTRL: if (!i2c_busy) begin
                // Co=0 D/C#=0 -> everything that follows is a command,
                // Co=0 D/C#=1 -> everything that follows is display data
                din_sel   <= D_CTRL;
                i2c_write <= 1'b1;
                t_st      <= T_CTRLW;
            end
            T_CTRLW: if (i2c_done) begin
                if (!i2c_ack) t_st <= T_RESLO;
                else          t_st <= T_FETCH;
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
                    if (!i2c_busy) begin
                        din_sel   <= D_BYTE;
                        i2c_write <= 1'b1;
                        t_st      <= T_DATAW;
                    end
                end
            end
            T_DATAW: if (i2c_done) begin
                if (!i2c_ack)                 t_st <= T_RESLO;
                else if (pkt_idx == pkt_last) t_st <= T_STOP;
                else begin
                    pkt_idx <= pkt_idx + 11'd1;
                    t_st    <= T_FETCH;
                end
            end
            //--------------------------------------------------------------
            T_STOP: if (!i2c_busy) begin
                i2c_stop <= 1'b1;
                t_st     <= T_STOPW;
            end
            T_STOPW: if (i2c_done) begin
                pkt_idx <= 11'd0;
                if (phase == P_INIT) begin
                    init_done <= 1'b1;
                    phase     <= P_FDATA;
                    t_st      <= T_ADDR;
                end else begin
                    frame_done <= 1'b1;           // let the game advance one step
                    t_st       <= T_GAP0;
                end
            end
            //--------------------------------------------------------------
            // one dead cycle so game_ctrl has registered its busy flag before
            // we look at it, then hold the panel idle until the step is done
            T_GAP0: t_st <= T_GAP;
            T_GAP : if (!game_busy) t_st <= T_ADDR;   // never tear a frame
            //--------------------------------------------------------------
            default: t_st <= T_RESLO;
            endcase
        end

endmodule
