// snake_engine -- game state: body list, food, collision, timer, score.
//
// NOTE: snake_mem (256 x 11) and collision_map (32 x 64) synthesise to
// ~4900 flip-flops plus the muxes that read them, which is far too large
// for the ETRI 0.5um MPW slot. See docs/AREA.md -- this module is the one
// that needs the direction-chain rewrite before tape-out.
module snake_engine #(
    parameter integer CLK_HZ = 25_000_000
) (
    input  wire clk,
    input  wire rst_n,
    input  wire btn_up, btn_down, btn_left, btn_right, btn_center,

    output reg  [7:0]  tail_ptr,
    output reg  [7:0]  head_ptr,
    output reg  [10:0] food_pos,
    input  wire [7:0]  read_addr,
    output wire [10:0] read_data,

    output reg  [3:0] t_sec_l, t_sec_h, t_min_l, t_min_h,
    output reg  [3:0] s_100, s_10, s_1
);

    // ---- everything time-related derives from CLK_HZ ----------------
    localparam integer TICK_INIT = CLK_HZ / 5;            // 200 ms per step
    localparam integer TICK_MIN  = CLK_HZ * 56 / 1000;    //  56 ms floor
    localparam integer TICK_STEP = CLK_HZ * 16 / 1000;    //  16 ms faster per food
    localparam integer ONE_SEC   = CLK_HZ;

    localparam integer TW = $clog2(TICK_INIT);            // game tick counter
    localparam integer SW = $clog2(ONE_SEC);              // 1 Hz counter

    reg [10:0] snake_mem [0:255];
    reg [63:0] collision_map [0:31];
    reg [10:0] lfsr;
    reg        game_over;

    assign read_data = snake_mem[read_addr];

    reg  [TW-1:0] tick_max;
    reg  [TW-1:0] tick_cnt;
    wire          tick_game = (tick_cnt >= tick_max);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) tick_cnt <= {TW{1'b0}};
        else if (!game_over) begin
            if (tick_game) tick_cnt <= {TW{1'b0}};
            else           tick_cnt <= tick_cnt + 1'b1;
        end
    end

    reg [1:0] dir;
    reg       dir_locked;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dir <= 2'd3; dir_locked <= 1'b0;
        end else if (tick_game) begin
            dir_locked <= 1'b0;
        end else if (!dir_locked && !game_over) begin
            if      (btn_up    && dir != 2'd1) begin dir <= 2'd0; dir_locked <= 1'b1; end
            else if (btn_down  && dir != 2'd0) begin dir <= 2'd1; dir_locked <= 1'b1; end
            else if (btn_left  && dir != 2'd3) begin dir <= 2'd2; dir_locked <= 1'b1; end
            else if (btn_right && dir != 2'd2) begin dir <= 2'd3; dir_locked <= 1'b1; end
        end
    end

    wire [5:0] head_x = snake_mem[head_ptr][10:5];
    wire [4:0] head_y = snake_mem[head_ptr][4:0];
    reg  [5:0] next_x;
    reg  [4:0] next_y;

    always @(*) begin
        next_x = head_x; next_y = head_y;
        case (dir)
            2'd0: next_y = head_y - 1'b1;
            2'd1: next_y = head_y + 1'b1;
            2'd2: next_x = head_x - 1'b1;
            2'd3: next_x = head_x + 1'b1;
        endcase
    end

    wire [5:0] tail_x = snake_mem[tail_ptr][10:5];
    wire [4:0] tail_y = snake_mem[tail_ptr][4:0];

    // playfield is 48 x 32 cells (96 x 64 px at 2x2 px per cell)
    wire hit_wall = (head_x == 0  && dir == 2'd2) ||
                    (head_x == 47 && dir == 2'd3) ||
                    (head_y == 0  && dir == 2'd0) ||
                    (head_y == 31 && dir == 2'd1);

    // the cell the tail is about to vacate does not count as a hit
    wire on_tail  = ({next_x, next_y} == {tail_x, tail_y});
    wire hit_self = collision_map[next_y][next_x] && !on_tail;

    reg [SW-1:0] cnt_1hz;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_1hz <= {SW{1'b0}};
            t_sec_l <= 0; t_sec_h <= 0; t_min_l <= 0; t_min_h <= 0;
        end else if (!game_over) begin
            if (cnt_1hz == ONE_SEC[SW-1:0] - 1'b1) begin
                cnt_1hz <= {SW{1'b0}};
                if (t_sec_l == 9) begin t_sec_l <= 0;
                    if (t_sec_h == 5) begin t_sec_h <= 0;
                        if (t_min_l == 9) begin t_min_l <= 0; t_min_h <= t_min_h + 1'b1; end
                        else t_min_l <= t_min_l + 1'b1;
                    end else t_sec_h <= t_sec_h + 1'b1;
                end else t_sec_l <= t_sec_l + 1'b1;
            end else cnt_1hz <= cnt_1hz + 1'b1;
        end
    end

    wire [7:0] next_head = head_ptr + 1'b1;
    wire [7:0] next_tail = tail_ptr + 1'b1;
    wire [5:0] rand_x    = (lfsr[10:5] < 48) ? lfsr[10:5] : lfsr[10:5] - 6'd16;  // 0..47
    integer j;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head_ptr <= 8'd2; tail_ptr <= 8'd0; game_over <= 1'b0;
            tick_max <= TICK_INIT[TW-1:0] - 1'b1;
            s_100 <= 0; s_10 <= 0; s_1 <= 0;

            snake_mem[0] <= {6'd15, 5'd16};
            snake_mem[1] <= {6'd16, 5'd16};
            snake_mem[2] <= {6'd17, 5'd16};

            for (j = 0; j < 32; j = j + 1) collision_map[j] <= 64'd0;
            collision_map[16][15] <= 1'b1;
            collision_map[16][16] <= 1'b1;
            collision_map[16][17] <= 1'b1;

            food_pos <= {6'd35, 5'd16}; lfsr <= 11'h5AA;
        end else begin
            lfsr <= {lfsr[9:0], lfsr[10] ^ lfsr[8]};       // x^11 + x^9 + 1
            if (tick_game && !game_over) begin
                if (hit_wall || hit_self) begin
                    game_over <= 1'b1;
                end else begin
                    head_ptr <= next_head;
                    snake_mem[next_head] <= {next_x, next_y};
                    collision_map[next_y][next_x] <= 1'b1;

                    if ({next_x, next_y} == food_pos) begin
                        if (tick_max > TICK_MIN[TW-1:0])
                            tick_max <= tick_max - TICK_STEP[TW-1:0];
                        food_pos <= {rand_x, lfsr[4:0]};

                        if (s_1 == 9) begin s_1 <= 0;
                            if (s_10 == 9) begin s_10 <= 0; s_100 <= s_100 + 1'b1; end
                            else s_10 <= s_10 + 1'b1;
                        end else s_1 <= s_1 + 1'b1;
                    end else begin
                        tail_ptr <= next_tail;
                        // When the head moves onto the cell the tail is
                        // leaving, both writes target the same bit and the
                        // clear would win, losing the head from the map.
                        if (!on_tail)
                            collision_map[tail_y][tail_x] <= 1'b0;
                    end
                end
            end
        end
    end
endmodule
