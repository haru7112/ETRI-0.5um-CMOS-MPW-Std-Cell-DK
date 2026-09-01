`timescale 1ns/1ps
// Testbench: decodes the I2C stream from snake_top, rebuilds the SSD1315
// GDDRAM image and dumps it as ASCII art. Also measures the pixel_scanner
// -> i2c_oled_master timing margin.
module tb_snake;

`ifdef CLK125
    localparam integer CLK_HZ  = 125_000_000;   // Zybo Z7-20 PL clock
    localparam integer HALF_NS = 4;
`else
    localparam integer CLK_HZ  = 25_000_000;    // chip target
    localparam integer HALF_NS = 20;
`endif
    reg clk = 0;
    always #(HALF_NS) clk = ~clk;

    reg rst_n = 0;
    reg joy_up=1, joy_dn=1, joy_lf=1, joy_rt=1, joy_ct=1;   // active low

    wire scl, sda;
    pullup(scl);
    pullup(sda);

    snake_top #(.CLK_HZ(CLK_HZ)) dut (
        .clk(clk), .rst_n(rst_n),
        .joy_up(joy_up), .joy_down(joy_dn), .joy_left(joy_lf),
        .joy_right(joy_rt), .joy_center(joy_ct),
        .i2c_scl(scl), .i2c_sda(sda));

    // ---------------- I2C sniffer ----------------
    reg [7:0] gddram [0:7][0:127];     // [page][col]
    integer   pg, cl;

    reg [7:0] byte_sr;
    reg [3:0] nbits;
    reg [7:0] byte_idx;                // 0=addr, 1=control, 2+=payload
    reg       in_xfer, is_data;
    reg [2:0] cur_page;
    reg [7:0] cur_col;
    integer   n_bytes, n_frames, n_pagecmd;

    initial begin
        for (pg=0; pg<8; pg=pg+1)
            for (cl=0; cl<128; cl=cl+1) gddram[pg][cl] = 8'h00;
        in_xfer=0; is_data=0; nbits=0; byte_idx=0;
        cur_page=0; cur_col=0; n_bytes=0; n_frames=0; n_pagecmd=0;
    end

    always @(negedge sda) if (scl === 1'b1) begin   // START
        in_xfer <= 1; nbits <= 0; byte_idx <= 0; is_data <= 0;
    end
    always @(posedge sda) if (scl === 1'b1) in_xfer <= 0;   // STOP

    always @(posedge scl) if (in_xfer) begin
        if (nbits < 8) begin
            byte_sr <= {byte_sr[6:0], (sda === 1'b0) ? 1'b0 : 1'b1};
            nbits   <= nbits + 1;
        end else begin
            nbits    <= 0;                       // ACK slot
            byte_idx <= byte_idx + 1;
            if (byte_idx == 0) begin
                if (byte_sr != 8'h78) $display("[%0t] BAD ADDR %02h", $time, byte_sr);
            end else if (byte_idx == 1) begin
                is_data <= (byte_sr == 8'h40);
            end else if (is_data) begin
                gddram[cur_page][cur_col[6:0]] = byte_sr;
                n_bytes = n_bytes + 1;
                if (cur_page==7 && cur_col==127) begin
                    n_frames = n_frames + 1;
                    $display("[%0t] --- frame %0d done (%0d px bytes, %0d page cmds) ---",
                             $time, n_frames, n_bytes, n_pagecmd);
                end
                cur_col = cur_col + 1;
            end else begin
                // command byte
                if (byte_sr[7:4] == 4'hB) begin
                    cur_page = byte_sr[2:0]; n_pagecmd = n_pagecmd + 1;
                end else if (byte_sr[7:4] == 4'h0) cur_col = {cur_col[7:4], byte_sr[3:0]};
                else if (byte_sr[7:4] == 4'h1)     cur_col = {byte_sr[3:0], cur_col[3:0]};
            end
        end
    end

    // ---------------- scanner timing margin ----------------
    integer t_colchange, t_latch, worst_margin;
    reg [6:0] prev_col;
    initial begin worst_margin = 1000000; prev_col = 0; t_colchange = 0; end

    always @(posedge clk) begin
        if (dut.col_x !== prev_col) begin
            prev_col    = dut.col_x;
            t_colchange = $time;
        end
    end
    // latch point: i2c master loads pixel_byte in S_LOAD_NEXT at phase==3
    always @(posedge clk) begin
        if (dut.u_display.state == 9 && dut.u_display.phase == 3
            && dut.u_display.phase_en && dut.u_display.pixel_valid) begin
            t_latch = $time;
            if (dut.u_scanner.scanning === 1'b1)
                $display("[%0t] *** STALE BYTE: scan still running at latch (col=%0d page=%0d)",
                         $time, dut.col_x, dut.page_y);
            if ((t_latch - t_colchange) < worst_margin && t_colchange != 0)
                worst_margin = t_latch - t_colchange;
        end
    end

    // ---------------- render ----------------
    task dump_frame;
        integer x, y, b;
        reg [7:0] row;
        begin
            $display("+--------------------------------------------------------------------------------------------------------------------------------+");
            for (y=0; y<64; y=y+1) begin
                $write("|");
                for (x=0; x<128; x=x+1) begin
                    row = gddram[y/8][x];
                    $write("%s", row[y%8] ? "#" : " ");
                end
                $display("|");
            end
            $display("+--------------------------------------------------------------------------------------------------------------------------------+");
        end
    endtask

    initial begin
        // dump disabled
        // dump disabled
        #200 rst_n = 1;

        wait (n_frames == 1);
        $display("\n=== FRAME 1 (t=%0t) ===", $time);
        dump_frame;

        // drive the snake down for a while, then a couple more frames
        wait (n_frames == 2);
        $display("\n=== FRAME 2 (t=%0t) ===", $time);
        dump_frame;

        $display("\nworst pixel_byte margin = %0d ns (%0d core clks)",
                 worst_margin, worst_margin/(2*HALF_NS));
        $finish;
    end

    initial begin #300000000; $display("TIMEOUT"); $finish; end
endmodule
