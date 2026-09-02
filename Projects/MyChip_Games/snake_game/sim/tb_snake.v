//----------------------------------------------------------------------------
// tb_snake.v
//  System level test bench: the RTL core, an SSD1315 model on a real open
//  drain bus with pull-ups, and a scripted player on the 5-way switch.
//
//  The clock is scaled down (CLK_HZ = 1MHz) so a game step is 200k cycles
//  instead of 5M; every ratio inside the design stays the same, only the wall
//  clock of the simulation changes.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_snake;

    localparam CLK_HZ  = 1_000_000;
    localparam SCL_HZ  =   250_000;
    localparam CELL_SH = 1;
    localparam MAXLEN  = 48;

    reg clk = 1'b0;
    reg arst_n = 1'b0;
    always #500 clk = ~clk;             // 1MHz

    // joystick, active low
    reg [4:0] btn_n = 5'b11111;
    localparam B_UP = 0, B_DN = 1, B_LT = 2, B_RT = 3, B_OK = 4;

    tri1 scl, sda;                      // 4.7k pull-ups
    wire oled_res_n, led;
    wire scl_oe, sda_oe, rst_n;

    reset_sync u_rst (.clk(clk), .arst_n(arst_n), .rst_n(rst_n));

    snake_top #(
        .CLK_HZ(CLK_HZ), .SCL_HZ(SCL_HZ), .CELL_SH(CELL_SH), .MAXLEN(MAXLEN),
        .LEN_W(6), .INIT_LEN(3), .EN_TEXT(1), .RES_MS(4)
    ) dut (
        .clk(clk), .rst_n(rst_n), .btn_n(btn_n),
        .oled_res_n(oled_res_n),
        .scl_oe(scl_oe), .sda_oe(sda_oe), .sda_i(sda),
        .led_alive(led));

    assign scl = scl_oe ? 1'b0 : 1'bz;
    assign sda = sda_oe ? 1'b0 : 1'bz;

    ssd1315_model u_panel (.scl(scl), .sda(sda), .res_n(oled_res_n));

    //------------------------------------------------------------------
    // helpers
    //------------------------------------------------------------------
    localparam MS = 1_000_000;              // one millisecond of this clock

    integer errors = 0;

    task check(input cond, input [8*44:1] what);
        begin
            if (cond) $display("[PASS] %0s", what);
            else begin $display("[FAIL] %0s", what); errors = errors + 1; end
        end
    endtask

    task hold_ms(input integer b, input integer ms);
        begin
            btn_n[b] = 1'b0;
            #(ms * MS);
            btn_n[b] = 1'b1;
        end
    endtask

    task wait_frames(input integer n);
        integer target;
        begin
            target = u_panel.frames + n;
            while (u_panel.frames < target) @(posedge clk);
        end
    endtask

    //------------------------------------------------------------------
    // state observation
    //------------------------------------------------------------------
    localparam S_TITLE=0, S_NEW=1, S_BUILD=2, S_FOOD=3, S_FSCAN=4,
               S_IDLE=5, S_STEP=6, S_SSCAN=7, S_OVER=8;

    wire [3:0]  g_st    = dut.u_game.st;
    wire [5:0]  g_len   = dut.u_body.len;
    wire [10:0] g_head  = dut.u_body.head;
    wire [7:0]  g_score = dut.u_game.score_bcd;
    wire [5:0]  g_hx    = g_head[5:0];
    wire [4:0]  g_hy    = g_head[10:6];

    integer steps = 0;
    integer last_st = -1;
    always @(posedge clk) begin
        if (g_st !== last_st) begin
            if (g_st == S_STEP) steps = steps + 1;
            if (g_st == S_IDLE && last_st == S_SSCAN)
                $display("%0t ps : step %0d  head=(%0d,%0d) dir=%0d len=%0d score=%02h",
                         $time, steps, g_hx, g_hy, dut.u_game.dir, g_len, g_score);
            last_st = g_st;
        end
    end

    // wait for n completed game steps, measured on the head itself so the
    // task can not be fooled by the pipeline delay of the control outputs
    task wait_steps(input integer n);
        integer i;
        reg [10:0] h0;
        begin
            for (i = 0; i < n; i = i + 1) begin
                h0 = g_head;
                while ((g_head === h0) && (g_st != S_OVER)) @(posedge clk);
                @(posedge clk);
            end
        end
    endtask

    //------------------------------------------------------------------
    // stimulus
    //------------------------------------------------------------------
    integer x_before, y_before;

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_snake.vcd");
            $dumpvars(0, tb_snake);
        end

        #(10 * MS) arst_n = 1'b1;

        // ---- 1. power up: RES# pulse, then the init burst -----------------
        wait (u_panel.disp_on === 1'b1);
        $display("%0t ps : panel reports display ON", $time);
        check(u_panel.nak_cnt == 0, "no address NAK during bring-up");
        check(u_panel.col_e == 7'd127 && u_panel.page_e == 3'd7,
              "window set to the full 128x64 panel");

        // ---- 2. title screen ---------------------------------------------
        wait_frames(2);
        u_panel.dump("TITLE");
        check(u_panel.frames >= 2, "frames are streaming");
        check(g_st == S_TITLE, "sitting in the title state");

        // ---- 3. start the game -------------------------------------------
        hold_ms(4, 20);                                  // OK
        while (g_st == S_TITLE) @(posedge clk);
        wait (g_st == S_IDLE);
        wait_frames(1);
        dump_body;
        u_panel.dump("AFTER START");
        check(g_len == 3, "initial snake length is 3");
        check(dut.u_game.food_en === 1'b1, "food has been placed");
        check(dut.u_game.dir == 2'b00, "starts heading right");

        // ---- 4. it must crawl to the right --------------------------------
        x_before = g_hx;
        wait_steps(2);
        check(g_hx == x_before + 2, "head advanced two cells to the right");

        // ---- 5. steer up ---------------------------------------------------
        y_before = g_hy;
        btn_n[0] = 1'b0;                                 // UP
        #(20 * MS);
        btn_n[0] = 1'b1;
        wait_steps(2);
        check(g_hy == y_before - 2, "head turned upwards");
        wait_frames(1);
        dump_body;
        u_panel.dump("MOVING UP");

        // ---- 6. a 180 degree reversal must be refused -----------------------
        btn_n[1] = 1'b0;                                 // DOWN, straight back
        #(20 * MS);
        btn_n[1] = 1'b1;
        y_before = g_hy;
        wait_steps(1);
        check(g_hy == y_before - 1, "reversal onto its own neck was rejected");

        // ---- 7. force a meal: put the food right in front of the head -------
        force_food_ahead;
        wait_steps(1);
        check(g_len == 4, "snake grew after eating");
        check(g_score == 8'h01, "score counted the meal");
        wait_frames(1);
        dump_body;
        u_panel.dump("AFTER EATING");

        // ---- 8. keep going up until the wall kills it ------------------------
        btn_n[0] = 1'b0;
        wait (g_st == S_OVER);
        btn_n[0] = 1'b1;
        $display("%0t ps : game over reached after %0d steps", $time, steps);
        check(dut.u_game.st_over === 1'b1, "game over state is rendered");
        wait_frames(2);
        u_panel.dump("GAME OVER");

        // ---- 9. restart -------------------------------------------------------
        hold_ms(4, 20);
        wait (g_st == S_IDLE);
        check(g_len == 3, "OK restarts the game");
        check(g_score == 8'h00, "score cleared on restart");
        wait_frames(1);
        u_panel.dump("RESTARTED");

        // ---- 10. grow, then bite its own body ------------------------------
        //  len 6 heading right, then down / left / up folds the head back onto
        //  a cell the body still occupies - the classic snake death.
        force_food_ahead;  wait_steps(1);
        force_food_ahead;  wait_steps(1);
        force_food_ahead;  wait_steps(1);
        check(g_len == 6, "snake fed up to length 6");
        dump_body;
        y_before = g_hy;
        hold_ms(1, 20);    wait_steps(1);          // DOWN
        hold_ms(2, 20);    wait_steps(1);          // LEFT
        dump_body;
        hold_ms(0, 20);                            // UP, back into the body
        wait (g_st == S_OVER);
        check(g_hy > 6 && g_hy < 30, "died in open field, not on a wall");
        check(dut.u_game.st_over === 1'b1, "self collision ends the game");
        wait_frames(1);
        u_panel.dump("SELF COLLISION");

        check(u_panel.nak_cnt == 0, "still no bus errors");

        $display("");
        if (errors == 0) $display("==== TB PASSED ====");
        else             $display("==== TB FAILED, %0d error(s) ====", errors);
        $finish;
    end

    // print what the body register really holds, next to what the panel shows
    //  the body is a head plus a direction queue, so walk it the same way the
    //  hardware does to print the segment positions
    task dump_body;
        integer i;
        reg [5:0] px;
        reg [4:0] py;
        reg [1:0] d;
        begin
            $write("%0t ps : body len=%0d :", $time, g_len);
            px = g_hx;  py = g_hy;
            for (i = 0; i < g_len; i = i + 1) begin
                $write(" (%0d,%0d)", px, py);
                d = dut.u_body.dq[i];
                case (d)
                    2'b00: px = px - 1;
                    2'b10: px = px + 1;
                    2'b01: py = py - 1;
                    default: py = py + 1;
                endcase
            end
            $write("   food=(%0d,%0d)/%b\n",
                   dut.u_game.food_pos[5:0], dut.u_game.food_pos[10:6],
                   dut.u_game.food_en);
        end
    endtask

    // put the food one cell in front of the head, whatever the direction
    task force_food_ahead;
        reg [5:0] hx; reg [4:0] hy; reg [1:0] d;
        begin
            // the game re-rolls the food right after a meal, so wait until it
            // is parked in S_IDLE before overriding the position
            while (g_st != S_IDLE) @(posedge clk);
            @(posedge clk);
            hx = g_hx;
            hy = g_hy;
            d  = dut.u_game.dir;
            case (d)
                2'b00: hx = hx + 1;
                2'b10: hx = hx - 1;
                2'b01: hy = hy + 1;
                default: hy = hy - 1;
            endcase
            force dut.u_game.food_r = {hy, hx};
            @(posedge clk);
            release dut.u_game.food_r;
            $display("%0t ps : food forced to (%0d,%0d)", $time, hx, hy);
        end
    endtask

    initial begin
        repeat (12000) #(MS);            // 12s of model time, watchdog
        $display("==== TB TIMEOUT ====");
        $finish;
    end

endmodule
