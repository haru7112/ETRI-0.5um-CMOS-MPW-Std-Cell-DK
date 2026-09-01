`timescale 1ns/1ps
// Checks the CLK_HZ-derived constants against real elapsed time, with no
// overrides: game tick period, the 1 Hz timer, and the I2C bit rate.
module tb_timing;

    localparam integer CLK_HZ = 25_000_000;

    reg clk = 0; always #20 clk = ~clk;      // 25 MHz -> 40 ns period
    reg rst_n = 0;

    wire scl, sda; pullup(scl); pullup(sda);

    snake_top #(.CLK_HZ(CLK_HZ)) dut (
        .clk(clk), .rst_n(rst_n),
        .joy_up(1'b1), .joy_down(1'b1), .joy_left(1'b1),
        .joy_right(1'b1), .joy_center(1'b1),
        .i2c_scl(scl), .i2c_sda(sda));

    real t0, t1, t_low_min, t_high_min, t_per_min;
    integer n;

    initial begin
        $display("--- derived constants at CLK_HZ = %0d ---", CLK_HZ);
        $display("  engine TICK_INIT = %0d  (%0.1f ms)",
                 dut.u_engine.TICK_INIT, dut.u_engine.TICK_INIT*1000.0/CLK_HZ);
        $display("  engine TICK_MIN  = %0d  (%0.1f ms)",
                 dut.u_engine.TICK_MIN,  dut.u_engine.TICK_MIN*1000.0/CLK_HZ);
        $display("  engine TICK_STEP = %0d  (%0.1f ms)",
                 dut.u_engine.TICK_STEP, dut.u_engine.TICK_STEP*1000.0/CLK_HZ);
        $display("  engine ONE_SEC   = %0d   tick ctr %0d b, 1Hz ctr %0d b",
                 dut.u_engine.ONE_SEC, dut.u_engine.TW, dut.u_engine.SW);
        $display("  debounce TICK_1MS= %0d", dut.u_joy.TICK_1MS);
        $display("  i2c DIV          = %0d  -> SCL = %0d Hz",
                 dut.u_display.DIV, CLK_HZ/(4*dut.u_display.DIV));

        #400 rst_n = 1;

        // --- measured game tick period
        @(posedge dut.u_engine.tick_game); t0 = $realtime;
        @(negedge dut.u_engine.tick_game);
        @(posedge dut.u_engine.tick_game); t1 = $realtime;
        $display("\nmeasured game tick period = %0.1f ms  (target 200)", (t1-t0)/1.0e6);

        // --- measured 1 Hz timer step
        @(dut.u_engine.t_sec_l); t0 = $realtime;
        @(dut.u_engine.t_sec_l); t1 = $realtime;
        $display("measured 1 Hz step        = %0.4f s   (target 1.0000)", (t1-t0)/1.0e9);

        // --- SCL low/high times (what the I2C spec constrains), taking the
        //     minimum seen so gaps between bytes do not mask a short pulse
        t_low_min = 1.0e9; t_high_min = 1.0e9; t_per_min = 1.0e9;
        for (n = 0; n < 200; n = n + 1) begin
            @(negedge scl); t0 = $realtime;
            @(posedge scl); t1 = $realtime;
            if ((t1-t0) < t_low_min) t_low_min = t1-t0;
            t0 = t1;
            @(negedge scl); t1 = $realtime;
            if ((t1-t0) < t_high_min) t_high_min = t1-t0;
        end
        $display("\nmeasured SCL t_LOW  min   = %0.0f ns  (fast-mode min 1300)", t_low_min);
        $display("measured SCL t_HIGH min   = %0.0f ns  (fast-mode min  600)", t_high_min);
        $display("bit rate during a byte    = %0.1f kHz (fast-mode max 400)",
                 1.0e6/(t_low_min+t_high_min));
        $finish;
    end

    initial begin #4000000000; $display("TIMEOUT"); $finish; end
endmodule
