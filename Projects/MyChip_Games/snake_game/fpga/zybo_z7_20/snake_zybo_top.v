//----------------------------------------------------------------------------
// snake_zybo_top.v
//  Digilent Zybo Z7-20 wrapper around the ASIC core.
//
//  The core itself is untouched: this file only creates the 25MHz the chip
//  will get from its crystal oscillator, turns the two open drain enables into
//  real tri-states, and maps the board's buttons/LEDs.
//
//  Board hookup - everything on Pmod JE (see docs/hw_connection.md).
//  Drawn the way you look at the board, pin 1 on the right:
//
//                    +---------------------------------------+
//   VCC = 3V3     6  |  VCC   GND   JS_UP   RES#  SCL   SDA  |  1
//                12  |  VCC   GND   JS_OK  JS_RT JS_LT JS_DN |  7
//                    +---------------------------------------+
//
//      SW3  : reset (slide up = reset)
//      BTN0 : OK / start.  The 5-way switch's centre contact does not fit -
//             SPI needs five panel pins and the joystick four directions,
//             which is nine, and Pmod JE has eight.  On silicon all ten pins
//             exist; this is a bench limitation only.
//      LD0  : heartbeat, fast blink until the panel has been initialised
//
//      The module's CS# is strapped to GND.  The sequencer holds CS# low for a
//      whole burst and only raises it between frames, so tying it low costs
//      the between-frame resynchronisation and nothing else - and the window
//      command is re-sent in front of every frame anyway, which is what the
//      picture actually heals from.
//
//      The game step is fixed at STEP_MS milliseconds (parameter above) -
//      it no longer speeds up as the snake grows.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module snake_zybo_top #(
    // Milliseconds per game step.  Change this one number and rebuild to try
    // a different pace on the bench; the chip build sets the same parameter in
    // rtl/snake_chip.v.  Under 128 keeps the counter at seven bits.
    parameter STEP_MS = 208
)(
    input  wire clk125,          // K17, 125MHz board oscillator

    input  wire sw3,             // reset, active high
    input  wire btn0,            // spare OK button, active high
    output wire led0,

    output wire oled_mosi,       // JE1
    output wire oled_sclk,       // JE2
    output wire oled_res_n,      // JE3
    output wire oled_dc,         // JE4

    input  wire js_up,           // JE7   \
    input  wire js_down,         // JE8    |  4 directions, closes to GND,
    input  wire js_left,         // JE9    |  internal pull-ups enabled in the XDC
    input  wire js_right         // JE10  /
);
    //------------------------------------------------------------------
    // 125MHz -> 25MHz.  A plain divide by five on a BUFG: the core is
    // single edge triggered, so the 40/60 duty is irrelevant and this keeps
    // the wrapper free of any MMCM/IP dependency.
    //------------------------------------------------------------------
    reg [2:0] divcnt  = 3'd0;
    reg       clk25_r = 1'b0;

    always @(posedge clk125) begin
        divcnt  <= (divcnt == 3'd4) ? 3'd0 : divcnt + 3'd1;
        clk25_r <= (divcnt == 3'd4) || (divcnt == 3'd0);
    end

    wire clk25;
    BUFG u_bufg25 (.I(clk25_r), .O(clk25));

    //------------------------------------------------------------------
    // reset: the board switch is active high, the chip wants active low
    //------------------------------------------------------------------
    wire arst_n = ~sw3;
    wire rst_n;

    reset_sync u_rst (.clk(clk25), .arst_n(arst_n), .rst_n(rst_n));

    //------------------------------------------------------------------
    // core
    //------------------------------------------------------------------
    wire ok_n = ~btn0;                       // BTN0 starts the game - see the
                                             // pin note in the header

    snake_top #(
        .CLK_HZ  (25_000_000),
        .SCLK_HZ (6_250_000),
        .CELL_SH (2),          // 4x4 pixel cells -> 32 x 16 play grid
        .MAXLEN  (32),
        .LEN_W   (6),
        .INIT_LEN(3),
        .RES_MS  (20),
        .STEP_MS (STEP_MS)
    ) u_core (
        .clk        (clk25),
        .rst_n      (rst_n),
        .btn_n      ({ok_n, js_right, js_left, js_down, js_up}),
        .oled_res_n (oled_res_n),
        .oled_sclk  (oled_sclk),
        .oled_mosi  (oled_mosi),
        .oled_dc    (oled_dc),
        .oled_cs_n  (),            // strapped to GND on the module, see header
        .led_alive  (led0)
    );

endmodule
