#!/bin/tcsh -f
#------------------------------------------------------------
# qflow project variables - SNAKE chip
#------------------------------------------------------------

set sta_tool = opensta

# snake_chip is split over several files, so the source list has to be given
# explicitly.  Order does not matter, qflow feeds them all to yosys.
set source_file_list = "snake_chip.v snake_top.v snake_body.v game_ctrl.v \
                        pixel_gen.v font_rom.v pixel_out.v \
                        debounce.v lfsr11.v reset_sync.v"

# The design contains no `include at all: screen geometry is derived once in
# snake_top and handed down as parameters, so no include path is needed.

# Placement ------------------------------------------------
#  0.85 is what the other MyChip games use; the snake core is dominated by a
#  528 flop shift register, so drop it if qrouter starts running out of tracks.
set initial_density = 0.85
set addspacers_options = "-stripe 8 225 PG"

# Routing --------------------------------------------------
# set qrouter_options =

# Post processing ------------------------------------------
set migrate_options = ""
