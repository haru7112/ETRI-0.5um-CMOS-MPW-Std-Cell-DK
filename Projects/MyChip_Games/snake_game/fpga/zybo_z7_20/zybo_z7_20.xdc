#-----------------------------------------------------------------------------
# zybo_z7_20.xdc - constraints for snake_zybo_top on a Digilent Zybo Z7-20
#
# Every pin below was taken from Digilent's Zybo-Z7-Master.xdc (Rev. B), not
# from memory.
#
# Everything lives on Pmod JE, on purpose:
#   * JE is a STANDARD Pmod - it has 200 ohm series protection resistors, which
#     is what you want in front of hand wired modules.
#   * JE needs exactly the 8 signals this design uses.
#   * Its master-XDC comments carry the physical pin numbers (Sch=je[1] ..
#     je[10]), so there is no ambiguity.  Do NOT move this to JB/JC/JD without
#     re-deriving the pins: those are differential Pmods whose array index runs
#     p[1], n[1], p[2], n[2] ... which is NOT the physical pin order.
#-----------------------------------------------------------------------------

## 125 MHz system clock
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports clk125]
create_clock -period 8.000 -name sys_clk [get_ports clk125]

## the core runs on a divide by five of it
create_generated_clock -name clk25 -source [get_ports clk125] -divide_by 5 \
    [get_pins u_bufg25/O]

## board switches / buttons / LEDs
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVCMOS33} [get_ports sw3]    ;# sw[3]
set_property -dict {PACKAGE_PIN K18 IOSTANDARD LVCMOS33} [get_ports btn0]   ;# btn[0]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports led0]   ;# led[0]

#-----------------------------------------------------------------------------
# Pmod JE - as wired on the bench.  The board is drawn the way you look at it,
# pin 1 on the right:
#
#                       +---------------------------------------+
#   (3V3 on VCC)     6  |  VCC   GND    D/C#   RES#  SCLK  MOSI |  1
#                   12  |  VCC   GND   JS_RT  JS_LT JS_DN JS_UP |  7
#                       +---------------------------------------+
#
# SPI needs five panel pins and the joystick four directions - nine, and JE has
# eight - so the panel's CS# is strapped to GND on the module and BTN0 is the
# OK button.  All ten pins exist on silicon; this is a bench limitation.
#
# Which signal sits on which pin is free - the core does not care - so this
# follows the harness rather than the other way round.  check_xdc.py verifies
# the mapping against the Verilog ports and the Digilent master XDC either way.
#-----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33}             [get_ports oled_mosi]  ;# JE1
set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVCMOS33}             [get_ports oled_sclk]  ;# JE2
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33}             [get_ports oled_res_n] ;# JE3
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33}             [get_ports oled_dc]    ;# JE4
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports js_up]      ;# JE7
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports js_down]    ;# JE8
set_property -dict {PACKAGE_PIN T17 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports js_left]    ;# JE9
set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports js_right]   ;# JE10

## the switch, the buttons and the panel are all asynchronous to the core
set_false_path -from [get_ports {sw3 btn0 js_up js_down js_left js_right}]
set_false_path -to   [get_ports {led0 oled_res_n}]

## SPI runs at 6.25 MHz and the panel is a hand wired module, so there is no
## point timing the pad round trip
set_false_path -to   [get_ports {oled_sclk oled_mosi oled_dc}]
