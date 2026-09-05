//=======================================================================
// snake_emu_TB.v
//  Verilog side of the SNAKE emulator.  Follows the co-simulation pattern
//  of Projects/RTL/ALU8_Mult/ETRI050/simulation in this design kit: iverilog
//  runs the DUT, a VPI task hands signals to a SystemC model, and the SystemC
//  model puts the panel on the screen with SDL2.
//
//  The DUT is snake_chip, and which snake_chip is decided at compile time:
//
//      -DDUT_GATE   the synthesised gate netlist, with the cell delays out of
//                   khu_etri05_stdcells.v (iverilog -gspecify)
//      (otherwise)  the RTL
//
//  Both are driven by exactly the same testbench, which is the whole point:
//  if the netlist really is the RTL, the game plays the same.
//
//  WHAT CROSSES INTO SystemC, and why it is bytes and not wires.
//
//  The obvious thing is to hand SCLK/MOSI/DC/CS# straight over and let the
//  SystemC panel sample them, the way the design kit's GLCD model watches its
//  E strobe.  That needs a VPI callback on every SCLK edge - 16,480 of them
//  per frame - and, worse, it needs every one of those callbacks to arrive.
//  So the physical layer stays here, in Verilog, where it cannot miss an edge:
//  this block shifts the bits, and SystemC is woken once per assembled BYTE.
//  The panel behaviour - the command set, the GDDRAM, the picture - is all on
//  the SystemC side, which is where the emulator actually lives.
//=======================================================================
`timescale 1ns/10ps

module snake_emu_TB;

    //-------------------------------------------------------------------
    // 25MHz crystal, and a power-on reset long enough for reset_sync
    //-------------------------------------------------------------------
    reg CLK = 1'b0;
    always #20 CLK = ~CLK;              // 40ns period

    reg RST_N = 1'b0;
    initial #1000 RST_N = 1'b1;

    //-------------------------------------------------------------------
    // the 5-way switch, driven from SystemC (active low, as on the board)
    //-------------------------------------------------------------------
    reg [4:0] btn_n = 5'b11111;         // [0]UP [1]DOWN [2]LEFT [3]RIGHT [4]OK

    wire OLED_RES_N, OLED_SCLK, OLED_MOSI, OLED_DC, OLED_CS_N, LED;

    snake_chip dut (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .JS_UP      (btn_n[0]),
        .JS_DOWN    (btn_n[1]),
        .JS_LEFT    (btn_n[2]),
        .JS_RIGHT   (btn_n[3]),
        .JS_OK      (btn_n[4]),
        .OLED_RES_N (OLED_RES_N),
        .OLED_SCLK  (OLED_SCLK),
        .OLED_MOSI  (OLED_MOSI),
        .OLED_DC    (OLED_DC),
        .OLED_CS_N  (OLED_CS_N),
        .LED        (LED));

    //-------------------------------------------------------------------
    // SPI physical layer: mode 0, MSB first, sampled on the rising edge of
    // SCLK while CS# is low.  D/C# is read with the eighth bit, which is how
    // the real part decides what the byte it just took was.
    //
    // Blocking assignments, and byte_tick written LAST, so that by the time
    // the VPI callback runs, byte_val and byte_dc are already the byte that
    // caused it.
    //-------------------------------------------------------------------
    reg [2:0] bitc      = 3'd0;
    reg [7:0] shreg     = 8'h00;
    reg [7:0] byte_val  = 8'h00;
    reg       byte_dc   = 1'b0;
    reg       byte_tick = 1'b0;         // toggles once per complete byte

    always @(posedge OLED_SCLK) if (!OLED_CS_N) begin
        if (bitc == 3'd7) begin
            byte_val  = {shreg[6:0], (OLED_MOSI === 1'b1)};
            byte_dc   = (OLED_DC === 1'b1);
            bitc      = 3'd0;
            byte_tick = ~byte_tick;
        end else begin
            shreg = {shreg[6:0], (OLED_MOSI === 1'b1)};
            bitc  = bitc + 3'd1;
        end
    end

    // CS# rising resynchronises the bit counter - the property SPI has and
    // I2C did not, and the reason a framing glitch heals here without help.
    always @(posedge OLED_CS_N) bitc = 3'd0;

    //-------------------------------------------------------------------
    // A second, slow strobe on its own process.  It is what gets the
    // keyboard polled and the window repainted while the panel is quiet -
    // during the 42ms power-up wait, for instance, nothing is sent at all.
    //
    // Two strobes on two processes rather than one shared flag: a shared one
    // could have both processes toggle it in the same time step and lose an
    // event, and losing a byte event would corrupt the picture.
    //-------------------------------------------------------------------
    reg idle_tick = 1'b0;
    always #200000 idle_tick = ~idle_tick;      // every 200us of sim time

    //-------------------------------------------------------------------
    // hand-off to SystemC.  Positional - see snake_emu_tf() in vpi_stub.cpp
    //-------------------------------------------------------------------
    reg end_of_sim = 1'b0;

    initial begin
        $display("iverilog started");
        $snake_emu(
            // wake-ups
            byte_tick,
            idle_tick,
            // panel side, into SystemC
            byte_val,
            byte_dc,
            OLED_RES_N,
            OLED_CS_N,
            LED,
            // back out of SystemC
            btn_n,
            end_of_sim);
    end

    always @(end_of_sim) if (end_of_sim) begin
        $display("SDL window closed, stopping");
        $finish;
    end

endmodule
