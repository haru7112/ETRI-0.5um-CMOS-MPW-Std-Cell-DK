//----------------------------------------------------------------------------
// snake_chip.v
//  ASIC core top for the ETRI 0.5um MPW - this is the module qflow
//  synthesises, places and routes.
//
//  It carries NO tri-state logic: like the other MyChip games in this design
//  kit, the pad ring is a separate magic cell stitched around the routed core
//  at chip_top level.  The two open drain I2C lines therefore leave the core
//  as an output enable plus an input:
//
//      SCL_OE  -> PADINOUT.OEN   with PADINOUT.DO tied low
//      SDA_OE  -> PADINOUT.OEN   with PADINOUT.DO tied low
//      SDA_I   <- PADINOUT.DI
//
//  Pulling the line low is the only thing the chip ever does to the bus; the
//  external 4.7k resistors define the high level, which is what lets a 5V
//  chip drive a 3.3V panel by pulling those resistors up to 3.3V.
//  See snake_chip_pads.v for the wiring written out in Verilog.
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
    output wire SCL_OE,       // 1 = pull SCL low
    output wire SDA_OE,       // 1 = pull SDA low
    input  wire SDA_I,        // SDA read back, for the ACK bit
    output wire LED           // heartbeat
);
    wire rst_n_s;

    reset_sync u_rst (.clk(CLK), .arst_n(RST_N), .rst_n(rst_n_s));

    snake_top #(
        .CLK_HZ  (25_000_000),
        .SCL_HZ  (400_000),
        .CELL_SH (2),           // 4x4 pixel cells -> 32 x 16 play grid
        .MAXLEN  (32),
        .LEN_W   (6),
        .INIT_LEN(3),
        .RES_MS  (20),
        .STEP_MS (208)         // fixed step, was a 200->88ms ramp
    ) u_core (
        .clk        (CLK),
        .rst_n      (rst_n_s),
        .btn_n      ({JS_OK, JS_RIGHT, JS_LEFT, JS_DOWN, JS_UP}),
        .oled_res_n (OLED_RES_N),
        .scl_oe     (SCL_OE),
        .sda_oe     (SDA_OE),
        .sda_i      (SDA_I),
        .led_alive  (LED)
    );

endmodule
