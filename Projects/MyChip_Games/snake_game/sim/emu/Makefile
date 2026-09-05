#-----------------------------------------------------------------------------
# SNAKE emulator - iverilog + VPI + SystemC + SDL2
#
# Puts the panel on the screen and lets you play the game with the keyboard,
# driven either by the RTL or by the synthesised gate netlist.  Same emulator
# both times, only the DUT changes - which is the point: if the netlist is the
# RTL, it plays the same.
#
#     make rtl     build and run against ../../rtl
#     make gate    build and run against the synthesised netlist + cell delays
#     make clean
#
# Modelled on Projects/RTL/ALU8_Mult/ETRI050/simulation in this design kit.
#
# Prerequisites (the kit's Tools/ has installers for all of them):
#     SystemC      Tools/systemc_build.sh      or  apt install libsystemc-dev
#     SDL2         Tools/sdl2_install.sh       or  apt install libsdl2-dev
#     iverilog     Tools/iverilog_build.sh
#-----------------------------------------------------------------------------
DK        ?= $(HOME)/ETRI050_DesignKit
CELLDIR   ?= $(DK)/digital_ETRI050_m2f
LIBERTY   ?= $(CELLDIR)/khu_etri05_stdcells.lib
CELLS_V   ?= $(CELLDIR)/khu_etri05_stdcells.v

RTLDIR     = ../../rtl
RTL_SRCS   = $(RTLDIR)/snake_chip.v $(RTLDIR)/snake_top.v $(RTLDIR)/snake_body.v \
             $(RTLDIR)/game_ctrl.v $(RTLDIR)/pixel_gen.v $(RTLDIR)/font_rom.v \
             $(RTLDIR)/oled_ctrl.v $(RTLDIR)/spi_master.v $(RTLDIR)/debounce.v \
             $(RTLDIR)/lfsr11.v $(RTLDIR)/reset_sync.v

# SystemC ---------------------------------------------------------------------
# apt's libsystemc-dev puts the headers on the default include path; a
# Tools/systemc_build.sh install puts them under /opt/systemc.
SYSTEMC        ?= /opt/systemc
ifneq ($(wildcard $(SYSTEMC)/include/systemc.h),)
  SC_INC = -I$(SYSTEMC)/include
  SC_LIB = -L$(SYSTEMC)/lib -Wl,-rpath,$(SYSTEMC)/lib
else
  SC_INC =
  SC_LIB =
endif

VPI_TARGET = vpi_snake_emu.vpi
VPI_SRCS   = vpi_stub.cpp sc_snake_emu.cpp sc_ssd1306.cpp
VPI_HDRS   = sc_snake_TB.h sc_ssd1306.h \
             vpi_snake_emu_ports.h vpi_snake_emu_exports.h

IVL_INC   := $(shell test -d /usr/local/include/iverilog && \
                     echo -I/usr/local/include/iverilog || echo -I/usr/include/iverilog)

$(VPI_TARGET) : $(VPI_SRCS) $(VPI_HDRS)
	$(CXX) -g -fPIC -shared -o $@ $(VPI_SRCS) \
	       $(SC_INC) $(IVL_INC) $(shell sdl2-config --cflags) \
	       $(SC_LIB) -lsystemc $(shell sdl2-config --libs)

#-----------------------------------------------------------------------------
# The cell library for simulation.
#
# Two edits, both made here rather than by keeping a modified copy of a design
# kit file in the repository:
#
#   1. udp_dff powers up X.  Real silicon powers up to SOMETHING, and the one
#      register in this design without a reset - the direction queue - would
#      otherwise smear X across the picture.  An initial in a sequential UDP
#      is the standard way to say "power up low".
#   2. udp_tlat, for the same reason.
#-----------------------------------------------------------------------------
stdcells_sim.v : $(CELLS_V)
	sed -e '/^primitive udp_dff /,/^endprimitive/ s/^   reg    out;/   reg    out;\n   initial out = 1'"'"'b0;/' \
	    -e '/^primitive udp_tlat /,/^endprimitive/ s/^   reg    out;/   reg    out;\n   initial out = 1'"'"'b0;/' \
	    $< > $@
	@grep -c 'initial out' $@ | xargs -I{} echo "  power-up initialised {} UDP(s)"

#-----------------------------------------------------------------------------
# gate netlist, built with the same recipe ETRI050/project_vars.sh sets
#-----------------------------------------------------------------------------
snake_chip_gate.v : gate.ys $(RTL_SRCS)
	sed 's|LIBERTY_PATH|$(LIBERTY)|g' gate.ys > .gate.ys
	yosys -s .gate.ys | tail -25
	@rm -f .gate.ys

#-----------------------------------------------------------------------------
# RTL build: fast, for playing
#-----------------------------------------------------------------------------
snake_emu_rtl : snake_emu_TB.v $(RTL_SRCS)
	iverilog -g2005 -o $@ snake_emu_TB.v $(RTL_SRCS)

#-----------------------------------------------------------------------------
# Gate build: the synthesised netlist, functional.  Without -gspecify iverilog
# ignores the specify blocks in the cell library, so the cells switch with no
# delay and the run is fast enough to actually play.  Timing is make sta's job
# - and note the kit comments its own setup/hold checks out, so a timing
# simulation here would not flag a violation even if you asked for one.
#-----------------------------------------------------------------------------
snake_emu_gate : snake_emu_TB.v snake_chip_gate.v stdcells_sim.v
	iverilog -g2005 -o $@ snake_emu_TB.v snake_chip_gate.v stdcells_sim.v

#-----------------------------------------------------------------------------
rtl  : snake_emu_rtl  $(VPI_TARGET)
	vvp -M. -mvpi_snake_emu snake_emu_rtl

gate : snake_emu_gate $(VPI_TARGET)
	@echo "The panel holds RES# low for 20ms before it will take anything,"
	@echo "so the window stays dark for the first 42ms of simulated time."
	vvp -M. -mvpi_snake_emu snake_emu_gate

build_rtl  : snake_emu_rtl  $(VPI_TARGET)
build_gate : snake_emu_gate $(VPI_TARGET)

#-----------------------------------------------------------------------------
# Headless: no window, the panel is printed as ASCII art instead.  This is how
# the emulator gets checked on a machine with no display, and it is what makes
# "same testbench, two DUTs" into an automatic test rather than something you
# have to watch.
#
#     make compare N=3    run both for N frames and diff the pictures
#
# The gate build carries cell delays, so it is far slower than the RTL - a
# handful of frames is a long coffee, not a demo.
#-----------------------------------------------------------------------------
N ?= 2

ascii_rtl.txt : snake_emu_rtl $(VPI_TARGET)
	SNAKE_EMU_ASCII=1 timeout 3600 vvp -M. -mvpi_snake_emu snake_emu_rtl \
	  | awk '/^\+---/{n++} n>$(N){exit} {print}' > $@

ascii_gate.txt : snake_emu_gate $(VPI_TARGET)
	SNAKE_EMU_ASCII=1 timeout 3600 vvp -M. -mvpi_snake_emu snake_emu_gate \
	  | awk '/^\+---/{n++} n>$(N){exit} {print}' > $@

compare : ascii_rtl.txt ascii_gate.txt
	@if diff -q ascii_rtl.txt ascii_gate.txt > /dev/null; then \
	    echo "==== RTL and GATE draw the same $(N) frame(s) ===="; \
	 else \
	    echo "==== MISMATCH ===="; diff ascii_rtl.txt ascii_gate.txt | head -40; \
	    exit 1; \
	 fi

clean :
	rm -f $(VPI_TARGET) snake_emu_rtl snake_emu_gate
	rm -f snake_chip_gate.v stdcells_sim.v .gate.ys *.vcd
	rm -f ascii_rtl.txt ascii_gate.txt

.PHONY: rtl gate build_rtl build_gate compare clean
