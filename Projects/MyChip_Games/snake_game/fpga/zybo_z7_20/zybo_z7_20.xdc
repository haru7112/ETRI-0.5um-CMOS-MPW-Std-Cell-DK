#-----------------------------------------------------------------------------
# zybo_z7_20.xdc - constraints for snake_zybo_top on a Digilent Zybo Z7-20
#
# Pin numbers follow Digilent's Zybo-Z7-Master.xdc.  Cross check them against
# the master file that ships with your board revision before you build.
#-----------------------------------------------------------------------------

## 125 MHz system clock
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports clk125]
create_clock -period 8.000 -name sys_clk [get_ports clk125]

## the core runs on a divide by five of it
create_generated_clock -name clk25 -source [get_ports clk125] -divide_by 5 \
    [get_pins u_bufg25/O]

## switches / buttons / LEDs
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVCMOS33} [get_ports sw3]
set_property -dict {PACKAGE_PIN K18 IOSTANDARD LVCMOS33} [get_ports btn0]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports led0]

## Pmod JE - SSD1315 OLED (standard Pmod, 200 ohm series protection)
##   JE1 SCL   JE2 SDA   JE3 RES#   JE5 GND   JE6 VCC3V3
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports oled_scl]
set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports oled_sda]
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33}             [get_ports oled_res_n]

## Pmod JC - 5-way navigation switch, common pin to GND
##   JC1 UP  JC2 DOWN  JC3 LEFT  JC4 RIGHT  JC7 OK(centre)  JC5 GND
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports js_up]
set_property -dict {PACKAGE_PIN W15 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports js_down]
set_property -dict {PACKAGE_PIN T11 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports js_left]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports js_right]
set_property -dict {PACKAGE_PIN W14 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports js_ok]

## the switch and the panel are asynchronous to everything
set_false_path -from [get_ports {sw3 btn0 js_*}]
set_false_path -to   [get_ports {led0 oled_res_n}]

## I2C runs at 400 kHz, two orders of magnitude below the clock: no point in
## timing the pad round trip
set_false_path -from [get_ports oled_sda]
