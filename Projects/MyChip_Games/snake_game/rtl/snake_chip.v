//----------------------------------------------------------------------------
// snake_chip.v
//  ASIC core top for the ETRI 0.5um MPW - this is the module qflow
//  synthesises, places and routes.
//
//  The panel is an SSD1306 on 4-wire SPI, so every pin here is unidirectional
//  and there is no tri-state anywhere in the core: each display signal goes
//  straight onto a PADOUT cell at chip_top level.  The I2C version needed two
//  PADINOUT cells, an ACK read-back path and two 4.7k pull-ups on the board;
//  SPI needs none of that and is 0.1mm2 smaller inside.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module snake_chip (
    input  wire CLK,          // 25MHz crystal oscillator module
    input  wire RST_N,        // external RC power on reset, active low
    input  wire JS_UP,        // 5-way switch, closes to GND, 10k pull-up
    input  wire JS_DOWN,
    input  wire JS_LEFT,
    input  wire JS_RIGHT,
    input  wire JS_OK,
    output wire OLED_RES_N,   // panel reset
    output wire OLED_SCLK,    // SPI clock, 6.25MHz
    output wire OLED_MOSI,    // SPI data
    output wire OLED_DC,      // 0 = command, 1 = display data
    output wire OLED_CS_N,    // low for the length of a burst
    output wire LED           // heartbeat
);
    wire rst_n_s;

    reset_sync u_rst (.clk(CLK), .arst_n(RST_N), .rst_n(rst_n_s));

    snake_top #(
        .CLK_HZ  (25_000_000),
        .SCLK_HZ (6_250_000),   // SSD1306 takes up to 10MHz
        .CELL_SH (2),           // 4x4 pixel cells -> 32 x 16 play grid
        .MAXLEN  (32),
        .LEN_W   (6),
        .INIT_LEN(3),
        .RES_MS  (20),
        .STEP_MS (208)          // fixed step, was a 200->88ms ramp
    ) u_core (
        .clk        (CLK),
        .rst_n      (rst_n_s),
        .btn_n      ({JS_OK, JS_RIGHT, JS_LEFT, JS_DOWN, JS_UP}),
        .oled_res_n (OLED_RES_N),
        .oled_sclk  (OLED_SCLK),
        .oled_mosi  (OLED_MOSI),
        .oled_dc    (OLED_DC),
        .oled_cs_n  (OLED_CS_N),
        .led_alive  (LED)
    );

endmodule
