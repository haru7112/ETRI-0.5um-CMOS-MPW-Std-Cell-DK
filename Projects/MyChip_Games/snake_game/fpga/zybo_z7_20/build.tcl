#-----------------------------------------------------------------------------
# build.tcl - non project Vivado flow for the Zybo Z7-20 bitstream
#
#     cd fpga/zybo_z7_20
#     vivado -mode batch -source build.tcl
#
# Writes build/snake_zybo.bit plus utilisation and timing reports.
# Tested against the file set as it is; snake_chip.v and snake_chip_pads.v are
# deliberately NOT read - they are the ASIC views and snake_chip_pads
# instantiates ETRI050 pad cells that mean nothing to Vivado.
#-----------------------------------------------------------------------------
set part   xc7z020clg400-1
set here   [file normalize [file dirname [info script]]]
set rtl    [file normalize [file join $here .. .. rtl]]
set outdir [file join $here build]
file mkdir $outdir

read_verilog [list \
    [file join $rtl snake_top.v]   \
    [file join $rtl snake_body.v]  \
    [file join $rtl game_ctrl.v]   \
    [file join $rtl pixel_gen.v]   \
    [file join $rtl font_rom.v]    \
    [file join $rtl oled_ctrl.v]   \
    [file join $rtl i2c_master.v]  \
    [file join $rtl debounce.v]    \
    [file join $rtl lfsr11.v]      \
    [file join $rtl reset_sync.v]  \
    [file join $here snake_zybo_top.v]]

read_xdc [file join $here zybo_z7_20.xdc]

# snake_params.vh is `include`d by several of the modules
synth_design -top snake_zybo_top -part $part -include_dirs $rtl

# The core runs on the BUFG output, so if create_generated_clock missed its
# target pin the 25MHz domain would silently be timed against the 125MHz
# clock - or not at all.  Fail loudly instead.
if {[llength [get_clocks -quiet clk25]] == 0} {
    error "clk25 was not created: check the create_generated_clock target pin\
           (u_bufg25/O) in zybo_z7_20.xdc against the synthesised netlist"
}
report_clocks -file [file join $outdir clocks.rpt]

opt_design
place_design
phys_opt_design
route_design

report_utilization        -file [file join $outdir utilization.rpt]
report_timing_summary     -file [file join $outdir timing.rpt]
report_drc                -file [file join $outdir drc.rpt]

write_bitstream -force [file join $outdir snake_zybo.bit]

set wns [get_property SLACK [get_timing_paths -delay_type max]]
puts "----------------------------------------------------------------"
puts "bitstream : [file join $outdir snake_zybo.bit]"
puts "worst slack: $wns ns   (25MHz core, 40ns period - expect a lot of slack)"
puts "----------------------------------------------------------------"
