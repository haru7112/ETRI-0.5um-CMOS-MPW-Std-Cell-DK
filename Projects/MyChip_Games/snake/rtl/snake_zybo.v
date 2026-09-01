// snake_zybo -- Zybo Z7-20 top level.
//
// Synthesise THIS as the top module for the board. It pins CLK_HZ to the
// Zybo's 125 MHz PL clock so the FPGA build cannot silently inherit
// snake_top's 25 MHz silicon default; that mismatch makes the I2C run at
// 1.84 MHz, far outside the SSD1315's 400 kHz limit, and the panel simply
// never responds.
//
// The board's reset button is active high, so it is inverted here and
// snake_top keeps its active-low reset.
module snake_zybo (
    input  wire clk_125m,     // K17, 125 MHz PL clock
    input  wire btn_reset,    // active high push button
    input  wire joy_up,       // joystick contacts, active low (pull-ups on)
    input  wire joy_down,
    input  wire joy_left,
    input  wire joy_right,
    input  wire joy_center,
    output wire i2c_scl,      // open drain, needs an external pull-up
    inout  wire i2c_sda
);

    snake_top #(.CLK_HZ(125_000_000)) u_snake (
        .clk(clk_125m),
        .rst_n(~btn_reset),
        .joy_up(joy_up), .joy_down(joy_down), .joy_left(joy_left),
        .joy_right(joy_right), .joy_center(joy_center),
        .i2c_scl(i2c_scl), .i2c_sda(i2c_sda)
    );
endmodule
