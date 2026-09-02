//----------------------------------------------------------------------------
// snake_zybo_top.v
//  Digilent Zybo Z7-20 wrapper around the ASIC core.
//
//  The core itself is untouched: this file only creates the 25MHz the chip
//  will get from its crystal oscillator, turns the two open drain enables into
//  real tri-states, and maps the board's buttons/LEDs.
//
//  Board hookup (see docs/hw_connection.md):
//      Pmod JE : SSD1315 OLED   JE1=SCL  JE2=SDA  JE3=RES#  (5=GND 6=VCC3V3)
//      Pmod JC : 5-way switch   JC1=UP JC2=DOWN JC3=LEFT JC4=RIGHT JC7=OK
//      SW3     : reset (slide up = reset)
//      BTN0    : extra OK/start button, works without the joystick fitted
//      LD0     : heartbeat, fast blink until the panel answers on I2C
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module snake_zybo_top (
    input  wire clk125,          // K17, 125MHz board oscillator

    input  wire sw3,             // reset, active high
    input  wire btn0,            // spare OK button, active high
    output wire led0,

    inout  wire oled_scl,        // JE1
    inout  wire oled_sda,        // JE2
    output wire oled_res_n,      // JE3

    input  wire js_up,           // JC1  \
    input  wire js_down,         // JC2   |  5-way switch, closes to GND,
    input  wire js_left,         // JC3   |  internal pull-ups enabled in the XDC
    input  wire js_right,        // JC4   |
    input  wire js_ok            // JC7  /
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
    wire scl_oe, sda_oe;
    wire ok_n = js_ok & ~btn0;               // either input starts the game

    snake_top #(
        .CLK_HZ  (25_000_000),
        .SCL_HZ  (400_000),
        .CELL_SH (1),          // 2x2 pixel cells -> 64 x 32 play grid
        .MAXLEN  (48),
        .LEN_W   (6),
        .INIT_LEN(3),
        .EN_TEXT (1),
        .RES_MS  (20)
    ) u_core (
        .clk        (clk25),
        .rst_n      (rst_n),
        .btn_n      ({ok_n, js_right, js_left, js_down, js_up}),
        .oled_res_n (oled_res_n),
        .scl_oe     (scl_oe),
        .sda_oe     (sda_oe),
        .sda_i      (oled_sda),
        .led_alive  (led0)
    );

    // open drain: drive low or let the bus pull-up win, exactly like the
    // PADINOUT cells will do on silicon
    assign oled_scl = scl_oe ? 1'b0 : 1'bz;
    assign oled_sda = sda_oe ? 1'b0 : 1'bz;

endmodule
