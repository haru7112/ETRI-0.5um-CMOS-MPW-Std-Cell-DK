#-----------------------------------------------------------------------------
# build.tcl - non project Vivado flow for the Zybo Z7-20 bitstream
#   vivado -mode batch -source build.tcl
#-----------------------------------------------------------------------------
set part   xc7z020clg400-1
set rtl    [file normalize [file join [file dirname [info script]] ../../rtl]]
set outdir [file join [file dirname [info script]] build]
file mkdir $outdir

read_verilog -sv_off [glob $rtl/*.v]
read_verilog [file join [file dirname [info script]] snake_zybo_top.v]
read_xdc     [file join [file dirname [info script]] zybo_z7_20.xdc]

set_property include_dirs $rtl [current_fileset]

synth_design -top snake_zybo_top -part $part -include_dirs $rtl
opt_design
place_design
route_design

report_utilization -file $outdir/utilization.rpt
report_timing_summary -file $outdir/timing.rpt
write_bitstream -force $outdir/snake_zybo.bit
puts "bitstream written to $outdir/snake_zybo.bit"
