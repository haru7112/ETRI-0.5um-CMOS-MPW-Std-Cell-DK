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
        $(RTL)/spi_master.v $(RTL)/debounce.v $(RTL)/lfsr11.v $(RTL)/reset_sync.v
IV    = iverilog -g2005

all: system pixel food lint

system: tb_snake.vvp
	vvp $< | tee run.log | grep -E '^\[|^====' || true

tb_snake.vvp: tb_snake.v ssd1306_model.v $(SRC)
	$(IV) -s tb_snake -o $@ tb_snake.v ssd1306_model.v $(SRC)

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

# -Wall is what catches a port left off an instantiation.  A floating input is
# invisible in RTL simulation - it reads as z, and z through a mux or a compare
# still produces a number - but yosys leaves the net undriven, so the gates get
# an X where the RTL got an answer.  That is exactly how the score display was
# lost when score_bcd moved out of game_ctrl, so the warning is an error here.
lint:
	@$(IV) -Wall -t null -s snake_chip $(RTL)/snake_chip.v $(SRC) 2>&1 | tee lint.log
	@$(IV) -Wall -t null -s snake_zybo_top $(FPGA)/snake_zybo_top.v xil_stub.v $(SRC) 2>&1 | tee -a lint.log
	@if grep -q 'warning:' lint.log; then echo "==== LINT FAILED ===="; exit 1; fi
	@python3 $(FPGA)/check_xdc.py > xdc.log || (cat xdc.log; exit 1)
	@tail -2 xdc.log
	@echo "lint OK"

clean:
	rm -f *.vvp *.vcd run.log lint.log xdc.log dbg*.v* t.ys tmp.ys

.PHONY: all system wave pixel food lint clean
