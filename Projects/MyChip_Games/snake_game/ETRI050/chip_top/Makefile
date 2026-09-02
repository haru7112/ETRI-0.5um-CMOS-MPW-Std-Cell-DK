#-----------------------------------------------------------------
# Stitch the routed snake_chip core into an ETRI050 pad frame.
#
# Fill PAD_X/PAD_Y, PIN_ROUTE_X/Y and CORE_X/Y in from
#     ../../ETRI050 : make size
#     ~/ETRI050_DesignKit/scripts/get_pad_pos.sh       <chip>
#     ~/ETRI050_DesignKit/scripts/get_pin_route_pos.sh <chip>
#     ~/ETRI050_DesignKit/scripts/get_core_pos.sh      <chip>
# exactly as the other MyChip_Games chip_top makefiles do.
#
# NOTE ON THE FRAME: the My Chip service only packages the standard
# MPW_PAD_28pin layout, whose pin-route ring leaves a core window of exactly
# 1018 x 1018 um (measured from the pong_pt1 2025 tape-out in this kit).  With
# the default parameters the routed core needs about 2.16 mm2, so it does NOT
# fit yet - see ../docs/area.md for the measured numbers and what is left to
# cut.  A larger die is possible after prior arrangement but comes as bare die
# with no package.
#-----------------------------------------------------------------
export DK_HOME=~/ETRI050_DesignKit

TOP_MODULE = snake_chip
CHIP_NAME  = $(TOP_MODULE)

SCRIPTS_PATH = ~/ETRI050_DesignKit/scripts
PAD_PATH     = ~/ETRI050_DesignKit/pads_ETRI
LAYOUT_PATH  = ../layout

PAD_FRAME    = MPW_PAD_28Pin_IO

PAD_X        =
PAD_Y        =
PIN_ROUTE_X  =
PIN_ROUTE_Y  =
CORE_X       =
CORE_Y       =

all:
	@echo
	@echo 'Generate Chip-Top: $(CHIP_NAME)_Top.gds'
	@echo
	@echo '    make copy_pad_frame'
	@echo '    make copy_core'
	@echo '    make extract_pad'
	@echo '    make extract_pin_route'
	@echo '    make generate_gds'
	@echo

copy_pad_frame:
	cp $(PAD_PATH)/$(PAD_FRAME).mag ./$(CHIP_NAME)_Top.mag

copy_core:
	cp $(LAYOUT_PATH)/$(TOP_MODULE).mag ./$(CHIP_NAME)_Core.mag

extract_pad: $(CHIP_NAME)_Top.mag
	python3 $(SCRIPTS_PATH)/xPad.py $(CHIP_NAME)

extract_pin_route: $(CHIP_NAME)_Top.mag
	python3 $(SCRIPTS_PATH)/xPin_Route_Metal.py $(CHIP_NAME)

generate_gds:
	$(SCRIPTS_PATH)/generate_chip.sh $(CHIP_NAME) \
		$(PAD_X) $(PAD_Y) $(PIN_ROUTE_X) $(PIN_ROUTE_Y) $(CORE_X) $(CORE_Y)

clean:
	rm -f $(CHIP_NAME)_Pad*.mag $(CHIP_NAME)_Pin_Route*.mag \
	      $(CHIP_NAME)_Core_*.mag $(CHIP_NAME)_Top_F.mag
