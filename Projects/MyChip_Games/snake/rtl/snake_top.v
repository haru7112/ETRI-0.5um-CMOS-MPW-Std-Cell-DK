module snake_top (
    input  wire clk_100m,   
    input  wire rst_n,      
    input  wire joy_up,     
    input  wire joy_down,
    input  wire joy_left,
    input  wire joy_right,
    input  wire joy_center, 
    output wire i2c_scl,
    inout  wire i2c_sda
);

    wire clk_1m6;
    wire rst_high = ~rst_n; 
    wire btn_up, btn_down, btn_left, btn_right, btn_center;
    wire [6:0] col_x;
    wire [2:0] page_y;
    wire [7:0] pixel_byte;
    wire [7:0] head_ptr, tail_ptr, read_addr;
    wire [10:0] food_pos, read_data;
    wire [3:0] t_sec_l, t_sec_h, t_min_l, t_min_h;
    
    // 누락되었던 점수 와이어 추가
    wire [3:0] s_100, s_10, s_1; 

    clk_div u_clk_div (.clk_125m(clk_100m), .rst_n(rst_n), .clk_1m6(clk_1m6));

    joystick_debounce u_joy (
        .clk(clk_100m), .rst_n(rst_n),
        .in_up(joy_up), .in_down(joy_down), .in_left(joy_left), .in_right(joy_right), .in_center(joy_center),
        .out_up(btn_up), .out_down(btn_down), .out_left(btn_left), .out_right(btn_right), .out_center(btn_center)
    );

    snake_engine u_engine (
        .clk(clk_100m), .rst_n(rst_n), 
        .btn_up(btn_up), .btn_down(btn_down), .btn_left(btn_left), .btn_right(btn_right), .btn_center(btn_center),
        .tail_ptr(tail_ptr), .head_ptr(head_ptr), .food_pos(food_pos), 
        .read_addr(read_addr), .read_data(read_data),
        .t_sec_l(t_sec_l), .t_sec_h(t_sec_h), .t_min_l(t_min_l), .t_min_h(t_min_h),
        .s_100(s_100), .s_10(s_10), .s_1(s_1) // 엔진 출력 연결
    );

    pixel_scanner u_scanner (
        .clk_125m(clk_100m), .rst_n(rst_n),
        .col_x(col_x), .page_y(page_y),
        .head_ptr(head_ptr), .tail_ptr(tail_ptr),
        .food_pos(food_pos), .read_data(read_data),
        .t_sec_l(t_sec_l), .t_sec_h(t_sec_h), .t_min_l(t_min_l), .t_min_h(t_min_h),
        .s_100(s_100), .s_10(s_10), .s_1(s_1), // 스캐너 입력 연결
        .read_addr(read_addr), .pixel_byte(pixel_byte)
    );

    i2c_oled_master u_display (
        .clk(clk_1m6), .reset(rst_high), .pixel_byte(pixel_byte),
        .col_x(col_x), .page_y(page_y), .scl(i2c_scl), .sda(i2c_sda)
    );
endmodule