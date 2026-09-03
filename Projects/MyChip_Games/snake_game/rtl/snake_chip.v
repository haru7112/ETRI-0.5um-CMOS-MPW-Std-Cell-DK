//----------------------------------------------------------------------------
// snake_chip.v
//  ASIC core top for the ETRI 0.5um MPW - this is the module qflow
//  synthesises, places and routes.
//
//  The port list is the fixed MyChip Games interface, so the part drops into
//  the standard SOP28 frame (pads_ETRI/MPW_PAD_28Pin_IO_Games.mag) and the
//  standard application board:
//
//                    +------\_/------+
//        (VDD)VDD7---|1            28|---BTN_LEFT
//                ... |               |---BTN_RIGHT
//                    |               |---BTN_DOWN
//                    |               |---BTN_UP
//     GAME_COMPLETE---|9           24|---GAME_NEW
//         GAME_OVER---|10          23|---RESET
//             PIXEL---|11          22|---CLK
//            P_TICK---|12          21|---GND7(GND)
//            V_SYNC---|13          20|---GND6(NC)
//                    +---------------+
//
//  Every port is unidirectional and there is no tri-state anywhere in the
//  synthesised core; the pad ring is stitched around it at chip_top level.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module snake_chip (
    input  wire clk,             // 25MHz crystal oscillator module
    input  wire reset,           // active HIGH, as the application board drives it

    input  wire btn_up,          // 5-way switch, closes to GND, 10k pull-up
    input  wire btn_down,
    input  wire btn_left,
    input  wire btn_right,
    input  wire game_new,        // centre button: start / restart

    output wire pixel,           // raster stream to the application board
    output wire p_tick,
    output wire v_sync,
    output wire game_over,
    output wire game_complete
);
    wire arst_n = ~reset;
    wire rst_n_s;

    reset_sync u_rst (.clk(clk), .arst_n(arst_n), .rst_n(rst_n_s));

    snake_top #(
        .CLK_HZ  (25_000_000),
        .CELL_SH (2),           // 4x4 pixel cells -> 32 x 16 play grid
        .MAXLEN  (32),
        .LEN_W   (6),
        .INIT_LEN(3)
    ) u_core (
        .clk           (clk),
        .rst_n         (rst_n_s),
        .btn_n         ({game_new, btn_right, btn_left, btn_down, btn_up}),
        .pixel         (pixel),
        .p_tick        (p_tick),
        .v_sync        (v_sync),
        .game_over     (game_over),
        .game_complete (game_complete)
    );

endmodule
