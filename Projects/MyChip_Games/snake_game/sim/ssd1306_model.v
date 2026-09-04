//----------------------------------------------------------------------------
// ssd1306_model.v
//  Simulation only.  Behavioural SSD1306 slave on 4-wire SPI: it follows the
//  part of the command set this design uses, keeps a real 128x64 GDDRAM and
//  can print it as ASCII art so a frame can be eyeballed in the log.
//
//  Mode 0 - MOSI is sampled on the rising edge of SCLK while CS# is low, MSB
//  first.  D/C# is read with the eighth bit, which is how the real part
//  decides whether the byte it just took is a command or display data.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module ssd1306_model (
    input  wire sclk,
    input  wire mosi,
    input  wire dc,
    input  wire cs_n,
    input  wire res_n
);
    reg  [7:0] gddram [0:1023];      // 8 pages x 128 columns

    reg  [3:0] bitc;
    reg  [7:0] shifter;
    reg  [1:0] cmd_param;            // remaining parameters of 0x21 / 0x22
    reg  [7:0] pending_cmd;
    reg  [6:0] col, col_s, col_e;
    reg  [2:0] page, page_s, page_e;
    reg        disp_on;
    integer    frame_bytes, frames, nak_cnt, i;

    initial begin
        bitc = 0; shifter = 0; cmd_param = 0; pending_cmd = 0;
        col = 0; col_s = 0; col_e = 127; page = 0; page_s = 0; page_e = 7;
        disp_on = 1'b0; frame_bytes = 0; frames = 0; nak_cnt = 0;
        for (i = 0; i < 1024; i = i + 1) gddram[i] = 8'h00;
    end

    // the panel clears its RAM pointer while RES# is low
    always @(negedge res_n) begin
        disp_on <= 1'b0;
        col     <= 0;
        page    <= 0;
    end

    // CS# rising resynchronises the bit counter - this is the property SPI has
    // and I2C did not, and it is why a glitch heals here without help.
    always @(posedge cs_n) bitc <= 0;

    // ---- bit sampling -----------------------------------------------------
    always @(posedge sclk) if (!cs_n) begin
        shifter <= {shifter[6:0], (mosi === 1'b1)};
        if (bitc == 7) begin
            bitc <= 0;
            take_byte({shifter[6:0], (mosi === 1'b1)}, dc);
        end else
            bitc <= bitc + 1;
    end

    task take_byte;
        input [7:0] b;
        input       is_data;
        begin
            if (is_data) begin
                gddram[{page, col}] = b;
                frame_bytes = frame_bytes + 1;
                if (frame_bytes == 1024) begin
                    frame_bytes = 0;
                    frames      = frames + 1;
                end
                if (col == col_e) begin
                    col  = col_s;
                    page = (page == page_e) ? page_s : page + 1;
                end else
                    col = col + 1;
            end else begin
                if (cmd_param != 0) begin
                    cmd_param = cmd_param - 1;
                    if (pending_cmd == 8'h21) begin
                        if (cmd_param == 1) begin col_s = b[6:0]; col = b[6:0]; end
                        else                      col_e = b[6:0];
                    end else if (pending_cmd == 8'h22) begin
                        if (cmd_param == 1) begin page_s = b[2:0]; page = b[2:0]; end
                        else                      page_e = b[2:0];
                    end
                end else begin
                    pending_cmd = b;
                    case (b)
                        8'h21, 8'h22: cmd_param = 2;
                        8'hAF:        disp_on   = 1'b1;
                        8'hAE:        disp_on   = 1'b0;
                        default:      ;
                    endcase
                end
            end
        end
    endtask

    // ---- ASCII dump -------------------------------------------------------
    task dump;
        input [8*24:1] title;
        integer x, y, p, b;
        reg [127:0] line;
        begin
            $display("+---- %0s  (frames=%0d disp_on=%0d) ----", title, frames, disp_on);
            for (y = 0; y < 64; y = y + 1) begin
                p = y / 8;  b = y % 8;
                for (x = 0; x < 128; x = x + 1)
                    line[127-x] = gddram[{p[2:0], x[6:0]}][b];
                $write("|");
                for (x = 0; x < 128; x = x + 1)
                    $write("%s", line[127-x] ? "#" : ".");
                $write("|\n");
            end
            $display("+%0s+", {128{"-"}});
        end
    endtask

    // Lit pixels inside one page, between two columns.  The score digits are
    // the only thing drawn in page SCORE_P left of the divider, so counting
    // that box is a direct read of what the panel is showing - which is the
    // check that would have caught score_bcd being left off the pixel_gen
    // instantiation, where the internal wire was right and the picture was not.
    function [31:0] box_pixels;
        input [2:0]  p;
        input [6:0]  x0;
        input [6:0]  x1;
        integer x, s;
        begin
            s = 0;
            for (x = x0; x <= x1; x = x + 1)
                s = s + gddram[{p, x[6:0]}][0] + gddram[{p, x[6:0]}][1] +
                        gddram[{p, x[6:0]}][2] + gddram[{p, x[6:0]}][3] +
                        gddram[{p, x[6:0]}][4] + gddram[{p, x[6:0]}][5] +
                        gddram[{p, x[6:0]}][6] + gddram[{p, x[6:0]}][7];
            box_pixels = s;
        end
    endfunction

    function [31:0] lit_pixels;      // set pixels, cheap sanity metric
        input dummy;
        integer x, s;
        begin
            s = 0;
            for (x = 0; x < 1024; x = x + 1)
                s = s + gddram[x][0] + gddram[x][1] + gddram[x][2] + gddram[x][3] +
                        gddram[x][4] + gddram[x][5] + gddram[x][6] + gddram[x][7];
            lit_pixels = s;
        end
    endfunction

endmodule
