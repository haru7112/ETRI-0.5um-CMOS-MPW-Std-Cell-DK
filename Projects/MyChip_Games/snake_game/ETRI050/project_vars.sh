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
set source_file_list = "snake_chip.v snake_top.v snake_body.v game_ctrl.v pixel_gen.v font_rom.v oled_ctrl.v i2c_master.v debounce.v lfsr11.v reset_sync.v"

# The design has no include directives at all: screen geometry is derived once
# in snake_top and handed down as parameters, so no include path is needed.

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
