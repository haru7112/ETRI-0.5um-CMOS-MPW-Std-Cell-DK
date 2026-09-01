# snake — simulation harness

Icarus Verilog testbenches for the SSD1315 snake game.

## tb_snake.v — full chip, I2C level

Instantiates `snake_top`, sniffs the open-drain I2C bus, rebuilds the
SSD1315 GDDRAM image and dumps it as ASCII art. Also measures the timing
margin between `col_x` changing and `i2c_oled_master` latching
`pixel_byte`, and flags every byte latched while `pixel_scanner` is still
scanning ("STALE BYTE").

    iverilog -g2005 -o snake.out ../rtl/*.v tb_snake.v
    vvp snake.out

Slow: one frame is ~28 ms of simulated time.

## tb_engine.v — snake_engine + pixel_scanner only

No I2C. Drives `col_x`/`page_y` directly and freezes the game tick while
scanning, so frames can be grabbed between game steps. Use this for
gameplay and rendering checks.

    iverilog -g2005 -o eng.out ../rtl/snake_engine.v ../rtl/pixel_scanner.v tb_engine.v
    vvp eng.out

Do not enable `$dumpvars` on the full design — `snake_mem` and
`collision_map` produce a multi-GB VCD within a single frame.
