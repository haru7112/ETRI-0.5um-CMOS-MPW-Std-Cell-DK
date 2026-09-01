`timescale 1ns/1ps
// Fast unit TB: snake_engine + pixel_scanner only (no I2C).
// Drives col_x/page_y directly and renders, so game ticks can be sped up.
module tb_engine;

    reg clk = 0; always #4 clk = ~clk;      // 125 MHz
    reg rst_n = 0;
    reg up=0, dn=0, lf=0, rt=0, ct=0;       // active high (post-debounce)

    wire [7:0] tail_ptr, head_ptr, read_addr;
    wire [10:0] food_pos, read_data;
    wire [3:0] t_sec_l, t_sec_h, t_min_l, t_min_h, s_100, s_10, s_1;

    reg  [6:0] col_x = 0;
    reg  [2:0] page_y = 0;
    wire [7:0] pixel_byte;

    snake_engine u_engine (
        .clk(clk), .rst_n(rst_n),
        .btn_up(up), .btn_down(dn), .btn_left(lf), .btn_right(rt), .btn_center(ct),
        .tail_ptr(tail_ptr), .head_ptr(head_ptr), .food_pos(food_pos),
        .read_addr(read_addr), .read_data(read_data),
        .t_sec_l(t_sec_l), .t_sec_h(t_sec_h), .t_min_l(t_min_l), .t_min_h(t_min_h),
        .s_100(s_100), .s_10(s_10), .s_1(s_1));

    pixel_scanner u_scanner (
        .clk_125m(clk), .rst_n(rst_n), .col_x(col_x), .page_y(page_y),
        .head_ptr(head_ptr), .tail_ptr(tail_ptr), .food_pos(food_pos),
        .read_data(read_data),
        .t_sec_l(t_sec_l), .t_sec_h(t_sec_h), .t_min_l(t_min_l), .t_min_h(t_min_h),
        .s_100(s_100), .s_10(s_10), .s_1(s_1),
        .read_addr(read_addr), .pixel_byte(pixel_byte));

    reg [7:0] fb [0:7][0:127];
    integer x, y, k;

    task grab_frame;   // sweep every (col,page), allow 400 clks to settle
        begin
            u_engine.tick_max = 25'h1FFFFFF;      // freeze the game while scanning
            for (y=0; y<8; y=y+1)
                for (x=0; x<128; x=x+1) begin
                    @(posedge clk); page_y = y[2:0]; col_x = x[6:0];
                    for (k=0; k<400; k=k+1) @(posedge clk);
                    fb[y][x] = pixel_byte;
                end
            u_engine.tick_max = 25'd399;          // resume
        end
    endtask

    task show(input [255:0] label);
        integer xx, yy; reg [7:0] row;
        begin
            $display("\n--- %0s  (head=%0d tail=%0d len=%0d food=%0d,%0d score=%0d%0d%0d) ---",
                     label, head_ptr, tail_ptr, head_ptr-tail_ptr+1,
                     food_pos[10:5], food_pos[4:0], s_100, s_10, s_1);
            for (yy=28; yy<40; yy=yy+1) begin
                $write("%2d |", yy);
                for (xx=32; xx<128; xx=xx+1) begin
                    row = fb[yy/8][xx];
                    $write("%s", row[yy%8] ? "#" : ".");
                end
                $display("|");
            end
        end
    endtask

    integer t;
    initial begin
        #200 rst_n = 1;
        @(posedge clk);
        u_engine.tick_max = 25'd399;          // speed up game ticks for sim
        u_engine.cnt_1hz  = 27'd0;

        grab_frame; show("initial (3 segments at x=15,16,17 y=16)");

        // let it run right for 4 ticks
        for (t=0; t<4; t=t+1) @(posedge u_engine.tick_game);
        grab_frame; show("after 4 ticks moving right");

        $display("\nsnake_mem[tail..head]:");
        for (k=tail_ptr; k<=head_ptr; k=k+1)
            $display("  [%0d] x=%0d y=%0d", k, u_engine.snake_mem[k][10:5], u_engine.snake_mem[k][4:0]);

        $finish;
    end
    initial begin #50000000; $display("TIMEOUT"); $finish; end
endmodule
