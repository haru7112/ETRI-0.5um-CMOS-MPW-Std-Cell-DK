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

# pin side constraints for graywolf, the same idea as pads_ETRI/games.cel2
./layout/$(TOP_MODULE).cel2 : $(TOP_MODULE).cel2
	@mkdir -p ./layout
	cp $< $@

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
	rm -f ./log/* ./synthesis/*
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

.PHONY: all synthesize place sta route migrate lvs size clean config_m1f config_m2f
