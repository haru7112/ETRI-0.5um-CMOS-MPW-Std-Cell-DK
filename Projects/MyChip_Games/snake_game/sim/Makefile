#-----------------------------------------------------------------------------
# Simulation of the SNAKE chip with Icarus Verilog.
#
#   make            run every test
#   make system     full chip + SSD1315 model + scripted player (~2 min)
#   make pixel      renderer unit test for every supported cell size
#   make food       exhaustive food placement check over the whole LFSR period
#   make lint       elaborate the ASIC top and the Zybo wrapper
#   make wave       system test with a VCD for gtkwave
#-----------------------------------------------------------------------------
RTL   = ../rtl
FPGA  = ../fpga/zybo_z7_20
SRC   = $(RTL)/snake_top.v $(RTL)/snake_body.v $(RTL)/game_ctrl.v \
        $(RTL)/pixel_gen.v $(RTL)/font_rom.v $(RTL)/oled_ctrl.v \
        $(RTL)/i2c_master.v $(RTL)/debounce.v $(RTL)/lfsr11.v $(RTL)/reset_sync.v
IV    = iverilog -g2005 -I$(RTL)

all: system pixel food lint

system: tb_snake.vvp
	vvp $< | tee run.log | grep -E '^\[|^====' || true

tb_snake.vvp: tb_snake.v ssd1315_model.v $(SRC)
	$(IV) -s tb_snake -o $@ tb_snake.v ssd1315_model.v $(SRC)

wave: tb_snake.vvp
	vvp $< +vcd | tail -5

pixel:
	@for c in 1 2 3; do \
	   $(IV) -s tb_pixel -Ptb_pixel.CELL_SH=$$c -o tb_p$$c.vvp \
	         tb_pixel.v $(RTL)/snake_body.v $(RTL)/pixel_gen.v $(RTL)/font_rom.v && \
	   vvp tb_p$$c.vvp | grep -E '^\[|^===='; \
	done

DK   = ../../../..

food:
	@for c in 1 2 3; do \
	   $(IV) -s tb_food -Ptb_food.CELL_SH=$$c -o tbf$$c.vvp \
	         tb_food.v $(RTL)/game_ctrl.v $(RTL)/lfsr11.v && \
	   vvp tbf$$c.vvp | grep -E '^\[|^===='; \
	done

lint:
	$(IV) -t null -s snake_chip $(RTL)/snake_chip.v $(SRC)
	$(IV) -t null -s snake_zybo_top $(FPGA)/snake_zybo_top.v xil_stub.v $(SRC)
	$(IV) -t null -s snake_chip_pads $(RTL)/snake_chip_pads.v $(RTL)/snake_chip.v \
	      $(SRC) $(DK)/digital_ETRI050_m2f/khu_etri05_stdcells.v
	@echo "lint OK"

clean:
	rm -f *.vvp *.vcd run.log dbg*.v* t.ys tmp.ys

.PHONY: all system wave pixel food lint clean
