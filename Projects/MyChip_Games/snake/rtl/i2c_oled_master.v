`timescale 1ns / 1ps

// i2c_oled_master -- SSD1315 page-addressed writer.
//
// Runs on the system clock with a bit-phase clock enable rather than its own
// divided clock, so the design is a single clock domain: one clock tree, no
// CDC, and nothing for STA to cut. phase advances at 4 x SCL_HZ.
module i2c_oled_master #(
    parameter integer CLK_HZ = 25_000_000,
    parameter integer SCL_HZ = 367_647
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] pixel_byte,
    input  wire       pixel_valid,
    output reg  [6:0] col_x,
    output reg  [2:0] page_y,
    output wire       scl,
    inout  wire       sda
);

    // one phase_en pulse per quarter SCL period
    localparam integer DIV = CLK_HZ / (4 * SCL_HZ);
    localparam integer DW  = $clog2(DIV);

    reg  [DW-1:0] div_cnt;
    wire          phase_en = (div_cnt == DIV[DW-1:0] - 1'b1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)        div_cnt <= {DW{1'b0}};
        else if (phase_en) div_cnt <= {DW{1'b0}};
        else               div_cnt <= div_cnt + 1'b1;
    end

    reg               scl_en, sda_en, init_done, setup_page, setup_col_l, setup_col_h;
    reg         [1:0] phase;
    reg         [2:0] bit_cnt;
    reg         [3:0] init_idx, state;
    reg         [7:0] init_data, shift_reg;
    
    localparam S_IDLE       = 0;
    localparam S_START      = 1;
    localparam S_SEND_ADDR  = 2;
    localparam S_ACK_ADDR   = 3;
    localparam S_SEND_CTRL  = 4;
    localparam S_ACK_CTRL   = 5;
    localparam S_SEND_DATA  = 6;
    localparam S_ACK_DATA   = 7;
    localparam S_STOP       = 8;
    localparam S_LOAD_NEXT  = 9;

    assign scl = scl_en ? 1'b0 : 1'bz;
    assign sda = sda_en ? 1'b0 : 1'bz;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)        phase <= 0;
        else if (phase_en) phase <= phase + 1'b1;
    end

    always @(*) begin
        case(init_idx)
            0: init_data = 8'hAE; // Display OFF
            1: init_data = 8'h20; // Set Memory Addressing Mode
            2: init_data = 8'h02; // Page Addressing Mode
            3: init_data = 8'hA1; // Set Segment Re-map
            4: init_data = 8'hC8; // Set COM Output Scan Direction
            5: init_data = 8'h8D; // Charge Pump
            6: init_data = 8'h14; // Enable Charge Pump
            7: init_data = 8'hAF; // Display ON
            default: init_data = 8'h00;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_en <= 0;
            sda_en <= 0;
        end
        else if (phase_en) begin
            case (state)
                S_START: begin
                    case (phase)
                      0: begin
                        scl_en <= 0;
                        sda_en <= 0;
                      end
                      1: begin
                        scl_en <= 0;
                        sda_en <= 0;
                      end
                      2: begin
                        scl_en <= 0;
                        sda_en <= 1;
                      end
                      3: begin
                        scl_en <= 1;
                        sda_en <= 1;
                      end
                    endcase
                end
                S_STOP: begin
                    case (phase)
                      0: begin
                        scl_en <= 1;
                        sda_en <= 1;
                      end
                      1: begin
                        scl_en <= 0;
                        sda_en <= 1;
                      end
                      2: begin
                        scl_en <= 0;
                        sda_en <= 0;
                      end
                      3: begin
                        scl_en <= 0;
                        sda_en <= 0;
                      end
                    endcase
                end
                S_SEND_ADDR, S_SEND_CTRL, S_SEND_DATA: begin
                    case (phase)
                      0: begin
                        scl_en <= 1;
                        sda_en <= shift_reg[7] ? 0 : 1;
                      end
                      1: begin
                        scl_en <= 0;
                      end
                      2: begin
                        scl_en <= 0;
                      end
                      3: begin
                        scl_en <= 1;
                      end
                    endcase
                end
                S_ACK_ADDR, S_ACK_CTRL, S_ACK_DATA: begin
                    case (phase)
                      0: begin
                        scl_en <= 1;
                        sda_en <= 0;
                      end
                      1: begin
                        scl_en <= 0;
                      end
                      2: begin
                        scl_en <= 0;
                      end
                      3: begin
                        scl_en <= 1;
                      end
                    endcase
                end
                S_LOAD_NEXT: begin
                    scl_en <= 1;
                    sda_en <= 1;
                end
                default: begin
                    scl_en <= 0;
                    sda_en <= 0;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            init_idx <= 0;
            init_done <= 0;
            page_y <= 0;
            col_x <= 0;
            setup_page <= 1;
            setup_col_l <= 1;
            setup_col_h <= 1;
            shift_reg <= 8'h00;
            bit_cnt <= 3'd0;
        end
        else if (phase_en && phase == 3) begin
            case (state)
                S_IDLE: begin
                  state <= S_START;
                end
                S_START: begin
                    shift_reg <= 8'h78;
                    bit_cnt <= 7;
                    state <= S_SEND_ADDR;
                end
                S_SEND_ADDR: begin
                    if (bit_cnt == 0) begin
                      state <= S_ACK_ADDR;
                    end
                    else begin
                      shift_reg <= {shift_reg[6:0], 1'b0};
                      bit_cnt <= bit_cnt - 1;
                    end
                end
                S_ACK_ADDR: begin
                    shift_reg <= (!init_done || setup_page || setup_col_l || setup_col_h) ? 8'h00 : 8'h40;
                    bit_cnt <= 7;
                    state <= S_SEND_CTRL;
                end
                S_SEND_CTRL: begin
                    if (bit_cnt == 0) begin
                      state <= S_ACK_CTRL;
                    end
                    else begin
                      shift_reg <= {shift_reg[6:0], 1'b0};
                      bit_cnt <= bit_cnt - 1;
                    end
                end
                S_ACK_CTRL: begin
                    bit_cnt <= 7;
                    if (!init_done) begin
                      shift_reg <= init_data;   state <= S_SEND_DATA;
                    end
                    else if (setup_page) begin
                      shift_reg <= 8'hB0 + page_y; state <= S_SEND_DATA;
                    end
                    else if (setup_col_l) begin
                      shift_reg <= 8'h00;       state <= S_SEND_DATA;
                    end
                    else if (setup_col_h) begin
                      shift_reg <= 8'h10;       state <= S_SEND_DATA;
                    end
                    else begin
                      // first pixel byte of the page: take the same stalling
                      // path as every other pixel byte
                      state <= S_LOAD_NEXT;
                    end
                end
                S_SEND_DATA: begin
                    if (bit_cnt == 0) begin
                      state <= S_ACK_DATA;
                    end
                    else begin
                      shift_reg <= {shift_reg[6:0], 1'b0};
                      bit_cnt <= bit_cnt - 1;
                    end
                end
                S_ACK_DATA: begin
                    if (!init_done) begin
                        if (init_idx == 7) begin
                          init_done <= 1;
                          state <= S_STOP;
                        end
                        else begin
                          init_idx <= init_idx + 1;
                          state <= S_STOP;
                        end
                    end
                    else if (setup_page) begin
                      setup_page <= 0;
                      state <= S_STOP;
                    end
                    else if (setup_col_l) begin
                      setup_col_l <= 0;
                      state <= S_STOP;
                    end
                    else if (setup_col_h) begin
                      setup_col_h <= 0;
                      state <= S_STOP;
                    end
                    else begin
                        if (col_x == 127) begin
                            col_x <= 0; page_y <= page_y + 1;
                            setup_page <= 1;
                            setup_col_l <= 1;
                            setup_col_h <= 1;
                            state <= S_STOP;
                        end
                        else begin
                            col_x <= col_x + 1;
                            state <= S_LOAD_NEXT;
                        end
                    end
                end
                S_LOAD_NEXT: begin
                    // Hold here until pixel_scanner has the byte for the
                    // current col_x/page_y. SCL is held low throughout this
                    // state, so waiting is ordinary I2C clock stretching.
                    if (pixel_valid) begin
                        shift_reg <= pixel_byte;
                        bit_cnt <= 7;
                        state <= S_SEND_DATA;
                    end
                end
                S_STOP: begin
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule