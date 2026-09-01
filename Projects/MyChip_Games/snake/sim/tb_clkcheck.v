`timescale 1ns/1ps
// Reproduces what happens when the CLK_HZ parameter does not match the
// clock actually fed to the part: BAD is the default 25 MHz parameter set
// driven by a Zybo 125 MHz clock, GOOD is the same board with CLK_HZ
// overridden. Reports SCL and the game tick rate for each.
module tb_clkcheck;

    reg clk125 = 0; always #4 clk125 = ~clk125;   // Zybo PL clock, 125 MHz
    reg rst_n = 0;

    wire scl_bad,  sda_bad;   pullup(scl_bad);  pullup(sda_bad);
    wire scl_good, sda_good;  pullup(scl_good); pullup(sda_good);

    // default parameters (CLK_HZ = 25 MHz) but driven at 125 MHz
    snake_top dut_bad (
        .clk(clk125), .rst_n(rst_n),
        .joy_up(1'b1), .joy_down(1'b1), .joy_left(1'b1),
        .joy_right(1'b1), .joy_center(1'b1),
        .i2c_scl(scl_bad), .i2c_sda(sda_bad));

    // parameter matched to the board
    snake_top #(.CLK_HZ(125_000_000)) dut_good (
        .clk(clk125), .rst_n(rst_n),
        .joy_up(1'b1), .joy_down(1'b1), .joy_left(1'b1),
        .joy_right(1'b1), .joy_center(1'b1),
        .i2c_scl(scl_good), .i2c_sda(sda_good));

    real t0, t1, lo_bad, lo_good;
    integer n;

    task measure_low(input integer which);
        real a, b, m;
        integer i;
        begin
            m = 1.0e9;
            for (i = 0; i < 200; i = i + 1) begin
                if (which == 0) begin
                    @(negedge scl_bad);  a = $realtime; @(posedge scl_bad);  b = $realtime;
                end else begin
                    @(negedge scl_good); a = $realtime; @(posedge scl_good); b = $realtime;
                end
                if ((b-a) < m) m = b-a;
            end
            if (which == 0) lo_bad = m; else lo_good = m;
        end
    endtask

    initial begin
        #400 rst_n = 1;

        $display("board clock = 125 MHz\n");
        $display("MISMATCHED  (snake_top with default CLK_HZ = %0d)", dut_bad.CLK_HZ);
        $display("   DIV = %0d", dut_bad.u_display.DIV);
        measure_low(0);
        $display("   SCL t_LOW   = %0.0f ns   -> SCL = %0.2f MHz", lo_bad, 1.0e3/(2*lo_bad));
        $display("   SSD1315 fast-mode limit is 400 kHz  ->  %s",
                 (1.0e3/(2*lo_bad) > 0.4) ? "OUT OF SPEC, display will not respond" : "ok");
        $display("   game tick   = %0d clk = %0.1f ms",
                 dut_bad.u_engine.TICK_INIT, dut_bad.u_engine.TICK_INIT/125000.0);

        $display("\nMATCHED     (snake_top #(.CLK_HZ(125_000_000)))");
        $display("   DIV = %0d", dut_good.u_display.DIV);
        measure_low(1);
        $display("   SCL t_LOW   = %0.0f ns   -> SCL = %0.1f kHz", lo_good, 1.0e6/(2*lo_good));
        $display("   game tick   = %0d clk = %0.1f ms",
                 dut_good.u_engine.TICK_INIT, dut_good.u_engine.TICK_INIT/125000.0);
        $finish;
    end
    initial begin #200000000; $display("TIMEOUT"); $finish; end
endmodule
