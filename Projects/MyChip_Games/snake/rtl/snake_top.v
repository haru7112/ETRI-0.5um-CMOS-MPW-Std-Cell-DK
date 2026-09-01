// snake_top -- SSD1315 128x64 OLED snake game, single clock domain.
//
// CLK_HZ is the only place the clock frequency is stated; every derived
// constant (game tick, 1 Hz counter, debounce tick, I2C bit rate) comes
// from it. Target silicon is ETRI 0.5um at 25 MHz; for the Zybo Z7-20's
// 125 MHz PL clock instantiate with .CLK_HZ(125_000_000), or feed 25 MHz
// from an MMCM and leave the default.
module snake_top #(
    parameter integer CLK_HZ = 25_000_000,
    parameter integer SCL_HZ = 390_625        // CLK_HZ must be a multiple of 4*SCL_HZ
) (
    input  wire clk,
    input  wire rst_n,
    input  wire joy_up,
    input  wire joy_down,
    input  wire joy_left,
    input  wire joy_right,
    input  wire joy_center,
    output wire i2c_scl,
    inout  wire i2c_sda
);

    wire btn_up, btn_down, btn_left, btn_right, btn_center;
    wire [6:0]  col_x;
    wire [2:0]  page_y;
    wire [7:0]  pixel_byte;
    wire        pixel_valid;
    wire [7:0]  head_ptr, tail_ptr, read_addr;
    wire [10:0] food_pos, read_data;
    wire [3:0]  t_sec_l, t_sec_h, t_min_l, t_min_h;
    wire [3:0]  s_100, s_10, s_1;

    joystick_debounce #(.CLK_HZ(CLK_HZ)) u_joy (
        .clk(clk), .rst_n(rst_n),
        .in_up(joy_up), .in_down(joy_down), .in_left(joy_left),
        .in_right(joy_right), .in_center(joy_center),
        .out_up(btn_up), .out_down(btn_down), .out_left(btn_left),
        .out_right(btn_right), .out_center(btn_center)
    );

    snake_engine #(.CLK_HZ(CLK_HZ)) u_engine (
        .clk(clk), .rst_n(rst_n),
        .btn_up(btn_up), .btn_down(btn_down), .btn_left(btn_left),
        .btn_right(btn_right), .btn_center(btn_center),
        .tail_ptr(tail_ptr), .head_ptr(head_ptr), .food_pos(food_pos),
        .read_addr(read_addr), .read_data(read_data),
        .t_sec_l(t_sec_l), .t_sec_h(t_sec_h), .t_min_l(t_min_l), .t_min_h(t_min_h),
        .s_100(s_100), .s_10(s_10), .s_1(s_1)
    );

    pixel_scanner u_scanner (
        .clk(clk), .rst_n(rst_n),
        .col_x(col_x), .page_y(page_y),
        .head_ptr(head_ptr), .tail_ptr(tail_ptr),
        .food_pos(food_pos), .read_data(read_data),
        .t_sec_l(t_sec_l), .t_sec_h(t_sec_h), .t_min_l(t_min_l), .t_min_h(t_min_h),
        .s_100(s_100), .s_10(s_10), .s_1(s_1),
        .read_addr(read_addr),
        .pixel_byte(pixel_byte), .pixel_valid(pixel_valid)
    );

    i2c_oled_master #(.CLK_HZ(CLK_HZ), .SCL_HZ(SCL_HZ)) u_display (
        .clk(clk), .rst_n(rst_n),
        .pixel_byte(pixel_byte), .pixel_valid(pixel_valid),
        .col_x(col_x), .page_y(page_y),
        .scl(i2c_scl), .sda(i2c_sda)
    );
endmodule
