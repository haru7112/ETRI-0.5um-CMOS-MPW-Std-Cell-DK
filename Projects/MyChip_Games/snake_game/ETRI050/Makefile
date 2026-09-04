#------------------------------------------------------------------------------
# QFlow RTL-to-Layout for the SNAKE chip, ETRI 0.5um CMOS node.
#
# Modelled on the other MyChip_Games projects of this design kit.  The core top
# is snake_chip (no tri-states, see rtl/snake_chip.v); the pad ring is stitched
# around the routed core in ./chip_top.
#
# Before the first run, link the design kit as ~/ETRI050_DesignKit and pick the
# metal stack:   make config_m2f      (or config_m1f)
#------------------------------------------------------------------------------
TOP_MODULE   = snake_chip
VERILOG_SRCS = $(wildcard ./source/*.v)

all :
	@if [ ! -e "./source" ]; then \
		echo "Symbolic link './source' to RTL..."; \
		ln -s ../rtl ./source; \
	fi
	@if [ ! -e "./synthesis" ]; then mkdir ./synthesis; fi
	@if [ ! -e "./log" ]; then mkdir ./log; fi
	@if [ ! -e "./layout" ]; then mkdir ./layout; fi
	touch project_vars.sh
	@echo
	@echo 'QFlow RTL-to-Layout, ETRI 0.5um CMOS, TOP = $(TOP_MODULE)'
	@echo
	@echo '    make config_m2f      # install the 2 metal std-cell views'
	@echo '    make synthesize'
	@echo '    make check_pins      # cross check snake_chip.cel2 before placing'
	@echo '    make preflight       # parse the .cel with graywolf own checker'
	@echo '    make place'
	@echo '    make sta'
	@echo '    make route'
	@echo '    make migrate'
	@echo '    make lvs'
	@echo '    make size            # measure the routed core, feeds chip_top'
	@echo
	@echo 'Area estimate before you start:  cd ../syn && python3 area.py'
	@echo 'It runs qflow own synthesis script and is calibrated against the'
	@echo 'pong_pt1 tape-out that ships in this kit (+1.2% on cell area).'
	@echo

# -----------------------------------------------------
synthesize : ./log/synth.log

./log/synth.log : $(VERILOG_SRCS) project_vars.sh
	qflow synthesize -T etri050 $(TOP_MODULE)

# -----------------------------------------------------
place : ./log/place.log

./log/place.log : ./layout/$(TOP_MODULE).cel2 ./log/synth.log project_vars.sh
	qflow place -T etri050 $(TOP_MODULE)

# Pin side constraints for graywolf, the same idea as pads_ETRI/games.cel2.
# A typo in a twpin_ name silently leaves that pin unconstrained, so the file
# is cross checked against the RTL ports and the frame's slots per side before
# it is handed to the placer.
./layout/$(TOP_MODULE).cel2 : $(TOP_MODULE).cel2 check_cel2.py
	python3 check_cel2.py
	@mkdir -p ./layout
	cp $< $@

check_pins :
	python3 check_cel2.py

# -----------------------------------------------------
# Pre-flight the placement input.
#
# graywolf pipes its parser errors into log/place.log and shows the terminal
# nothing but "exit status 255", so a malformed .cel costs a full place run to
# find.  This runs the same two steps qflow does - vlog2Cel, then graywolf own
# syntax checker - on the netlist that is sitting in ./synthesis, in a second.
#
# Run it after make synthesize and before make place.
QFLOW_TECH = /usr/local/share/qflow/tech/etri050
GW_SYNTAX  = /usr/local/lib/graywolf/bin/syntax

preflight : ./synthesis/$(TOP_MODULE).rtlnopwr.v $(TOP_MODULE).cel2
	python3 check_cel2.py
	@rm -rf ./preflight && mkdir -p ./preflight
	vlog2Cel -l $(QFLOW_TECH)/etri050_stdcells.lef -u 100 -o ./preflight/$(TOP_MODULE).cel ./synthesis/$(TOP_MODULE).rtlnopwr.v
	@cat $(TOP_MODULE).cel2 >> ./preflight/$(TOP_MODULE).cel
	@echo "cells: `grep -c '^cell ' ./preflight/$(TOP_MODULE).cel`  pads: `grep -c '^pad ' ./preflight/$(TOP_MODULE).cel`"
	@cd ./preflight && $(GW_SYNTAX) $(TOP_MODULE) 2>&1 | grep -vE 'objects so far|^$$' | tail -6

# -----------------------------------------------------
sta : ./log/sta.log

./log/sta.log : ./synthesis/$(TOP_MODULE).rtlnopwr.v ./log/place.log project_vars.sh
	qflow sta -T etri050 $(TOP_MODULE)

# -----------------------------------------------------
route : ./log/route.log

./log/route.log : ./log/place.log ./layout/$(TOP_MODULE).def \
                  ./layout/$(TOP_MODULE)_unroute.def project_vars.sh
	qflow route -T etri050 $(TOP_MODULE)

# -----------------------------------------------------
migrate : ./log/magic_db.log project_vars.sh

./log/magic_db.log : ./log/route.log
	qflow migrate -T etri050 $(TOP_MODULE)

# -----------------------------------------------------
lvs : ./log/lvs.log project_vars.sh

./log/lvs.log : ./synthesis/$(TOP_MODULE).spc ./layout/$(TOP_MODULE).mag ./log/magic_db.log
	~/ETRI050_DesignKit/scripts/fix_net_name.sh ./synthesis/$(TOP_MODULE).spc
	qflow lvs -T etri050 $(TOP_MODULE)

size : ./layout/$(TOP_MODULE).mag ./log/magic_db.log
	~/ETRI050_DesignKit/scripts/size_core.sh $(TOP_MODULE)

clean :
	rm -rf ./log/* ./synthesis/* ./preflight
	rm -f ./source
	touch project_vars.sh

#------------------------------------------------------------------------------
CELL_SRC1 = ~/ETRI050_DesignKit/digital_ETRI050_m1f
CELL_SRC2 = ~/ETRI050_DesignKit/digital_ETRI050_m2f
CELL_LIB  = ~/ETRI050_DesignKit/digital_ETRI

config_m1f :
	cp -f $(CELL_SRC1)/*.mag $(CELL_LIB)/
	cd $(CELL_LIB) && $(MAKE) clean && $(MAKE)
	@echo 'Std-Cell configured with $(CELL_SRC1)'

config_m2f :
	cp -f $(CELL_SRC2)/*.mag $(CELL_LIB)/
	cd $(CELL_LIB) && $(MAKE) clean && $(MAKE)
	@echo 'Std-Cell configured with $(CELL_SRC2)'

.PHONY: all synthesize place sta route migrate lvs size check_pins preflight clean config_m1f config_m2f
