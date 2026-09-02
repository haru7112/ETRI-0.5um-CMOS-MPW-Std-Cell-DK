//----------------------------------------------------------------------------
// snake_chip_pads.v
//  The complete chip: routed core plus the ETRI050 pad ring, written out in
//  Verilog.  qflow does not use this file (the pad frame is stitched in magic
//  at chip_top level) - it exists so the pad wiring is unambiguous, and so a
//  chip level simulation can be run against the same net list the bonding
//  diagram describes.
//
//  Pin list, 11 signal pads plus power:
//      in   CLK RST_N JS_UP JS_DOWN JS_LEFT JS_RIGHT JS_OK
//      out  OLED_RES_N LED
//      i/o  SCL SDA   (open drain, external 4.7k pull-ups)
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module snake_chip_pads (
    inout wire CLK, RST_N,
    inout wire JS_UP, JS_DOWN, JS_LEFT, JS_RIGHT, JS_OK,
    inout wire OLED_RES_N, LED,
    inout wire SCL, SDA
);
    wire clk_i, rst_n_i, up_i, dn_i, lt_i, rt_i, ok_i;
    wire res_n_o, led_o, scl_oe, sda_oe, sda_i;

    PADINC u_pad_clk   (.YPAD(CLK),      .DI(clk_i));
    PADINC u_pad_rst   (.YPAD(RST_N),    .DI(rst_n_i));
    PADINC u_pad_up    (.YPAD(JS_UP),    .DI(up_i));
    PADINC u_pad_dn    (.YPAD(JS_DOWN),  .DI(dn_i));
    PADINC u_pad_lt    (.YPAD(JS_LEFT),  .DI(lt_i));
    PADINC u_pad_rt    (.YPAD(JS_RIGHT), .DI(rt_i));
    PADINC u_pad_ok    (.YPAD(JS_OK),    .DI(ok_i));

    PADOUT u_pad_res   (.DO(res_n_o), .YPAD(OLED_RES_N));
    PADOUT u_pad_led   (.DO(led_o),   .YPAD(LED));

    // open drain: DO tied low, the core only ever decides whether to drive
    PADINOUT u_pad_scl (.DO(1'b0), .OEN(scl_oe), .DI(),      .YPAD(SCL));
    PADINOUT u_pad_sda (.DO(1'b0), .OEN(sda_oe), .DI(sda_i), .YPAD(SDA));

    snake_chip u_chip (
        .CLK(clk_i), .RST_N(rst_n_i),
        .JS_UP(up_i), .JS_DOWN(dn_i), .JS_LEFT(lt_i),
        .JS_RIGHT(rt_i), .JS_OK(ok_i),
        .OLED_RES_N(res_n_o),
        .SCL_OE(scl_oe), .SDA_OE(sda_oe), .SDA_I(sda_i),
        .LED(led_o));

endmodule
