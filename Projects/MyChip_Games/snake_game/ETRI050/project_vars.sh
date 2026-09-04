#!/bin/tcsh -f
#------------------------------------------------------------
# qflow project variables - SNAKE chip
#
# This file is sourced by tcsh, which parses quotes and backticks even inside
# comment lines and does not take a backslash continued string the way sh
# does.  Keep every set on one line, and keep backticks and apostrophes out of
# the comments; no other project_vars.sh in this design kit has either, and
# both make qflow die with an Unmatched quote error that names no file.
#------------------------------------------------------------

set sta_tool = opensta

# snake_chip is split over several files, so the source list has to be given
# explicitly - qflow reads only the top file otherwise.  Names are relative to
# ./source, and the order does not matter.  Must be one line.
set source_file_list = "snake_chip.v snake_top.v snake_body.v game_ctrl.v pixel_gen.v font_rom.v oled_ctrl.v spi_master.v debounce.v lfsr11.v reset_sync.v"

# The design has no include directives at all: screen geometry is derived once
# in snake_top and handed down as parameters, so no include path is needed.

# Synthesis ------------------------------------------------
# qflow writes its own yosys script, but two hooks let a project replace parts
# of it.  yosys_script is a file whose contents stand in for the default
# "synth -top snake_chip"; the path is read from ./source, so give it in full.
# abc_script is the argument of the -script option on the abc call.
#
# Together these take the chip from 1.242 to 1.075mm2 of cells - 13% - with no
# change to the RTL at all.  What they do:
#
#   -flatten lets the optimiser work across module boundaries, which on a
#   design that passes geometry down as parameters is most of the win.
#
#   map,-a maps for area instead of qflow default map,-M,1 which maps for
#   delay, mfs re-optimises the mapped network against its don t care set, and
#   amap is a second, area-only pass over the result.
#
# The cost is depth: 31 levels of logic where the default recipe gives 21.
# Walking the worst register to register path through the liberty tables puts
# that at 10.6ns against the default 8.6ns, both a long way inside the 40ns
# period, so it is bought cheaply - but confirm it with make sta before tapeout
# rather than taking the number here.  The netlist has also been run against
# the RTL side by side for 220000 clocks with every output compared.
#
# Keep syn/area.py in step with these two lines, or its estimate is not the
# flow that will run.
set yosys_script = "${projectpath}/yosys_hl.ys"
set abc_script = "+strash;dch,-f;map,-a;mfs;amap"

# If make sta ever says this is too slow, "+strash;dch,-f;map,-a;mfs;map;mfs;map"
# gives 1.144mm2 at 15 levels, which is shorter than the default recipe.

# Placement ------------------------------------------------
# The core window is what this sets: measured across the kit's routed designs,
# the density asked for here comes back as the utilisation actually achieved
# (0.85 gave 82.3% on pong_pt1, 0.30 gave 32.7% on picorv32i_ez).  0.85 is
# what the other MyChip games use.  Drop it to 0.80 or 0.75 if qrouter starts
# running out of tracks.
set initial_density = 0.85
set addspacers_options = "-stripe 8 225 PG"

# Routing --------------------------------------------------
# 2 metal process: stacked vias are not allowed.
set route_show = 1
set via_stacks = none

# STA ------------------------------------------------------
# 25MHz, so a 40ns period, given in ps.
set opensta_options = "--period 40000"
