`timescale 1ns/1ps
// Stress TB: force a maximum-length snake and confirm the pixel_valid
// handshake keeps the I2C master from ever transmitting a byte whose scan
// has not finished. Without the handshake this is exactly the case that
// breaks once CLK_HZ/SCL_HZ leaves the ratio the original design happened
// to be tuned for.
module tb_stress;

    localparam integer CLK_HZ  = 25_000_000;
    localparam integer SNAKELEN = 201;          // head_ptr = 200, tail_ptr = 0

    reg clk = 0; always #20 clk = ~clk;         // 25 MHz
    reg rst_n = 0;

    wire scl, sda;
    pullup(scl); pullup(sda);

    snake_top #(.CLK_HZ(CLK_HZ)) dut (
        .clk(clk), .rst_n(rst_n),
        .joy_up(1'b1), .joy_down(1'b1), .joy_left(1'b1),
        .joy_right(1'b1), .joy_center(1'b1),
        .i2c_scl(scl), .i2c_sda(sda));

    integer n_stale, n_stall, n_bytes, i;
    reg [5:0] bx; reg [4:0] by;
    integer t_frame_start;

    initial begin n_stale = 0; n_stall = 0; n_bytes = 0; end

    // every byte the master latches must have pixel_valid asserted
    always @(posedge clk)
        if (dut.u_display.phase_en && dut.u_display.phase == 3
            && dut.u_display.state == 9) begin
            if (dut.u_display.pixel_valid) n_bytes = n_bytes + 1;
            else                           n_stall = n_stall + 1;
            if (dut.u_display.pixel_valid && dut.u_scanner.scanning === 1'b1)
                n_stale = n_stale + 1;
        end

    // count SCL pulses to know when a full frame has gone out
    integer n_scl;
    initial n_scl = 0;
    always @(posedge scl) n_scl = n_scl + 1;

    initial begin
        #400 rst_n = 1;
        @(posedge clk);

        // freeze the game and install a 201-cell serpentine body
        dut.u_engine.tick_max = 32'hFFFF_FFFF;
        dut.u_engine.head_ptr = 8'd200;
        dut.u_engine.tail_ptr = 8'd0;
        for (i = 0; i < SNAKELEN; i = i + 1) begin
            bx = i % 48;
            by = i / 48;
            dut.u_engine.snake_mem[i] = {bx, by};
        end

        t_frame_start = $time;
        wait (n_bytes >= 1024);                 // one full frame of pixel bytes

        $display("snake length      : %0d cells", SNAKELEN);
        $display("pixel bytes sent  : %0d", n_bytes);
        $display("stall cycles      : %0d  (S_LOAD_NEXT held for the scanner)", n_stall);
        $display("STALE bytes       : %0d  <-- must be 0", n_stale);
        $display("frame time        : %0d us -> %0d fps",
                 ($time - t_frame_start)/1000, 1000000/(($time - t_frame_start)/1000));
        if (n_stale != 0) $display("FAIL");
        else if (n_stall == 0) $display("WARNING: handshake never stalled - test is not exercising it");
        else $display("PASS");
        $finish;
    end

    initial begin #200000000; $display("TIMEOUT (deadlock in the handshake?)"); $finish; end
endmodule
