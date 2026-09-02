//----------------------------------------------------------------------------
// ssd1315_model.v
//  Simulation only.  Behavioural I2C slave that follows the part of the
//  SSD1315 command set this design uses, keeps a real 128x64 GDDRAM and can
//  print it as ASCII art so a frame can be eyeballed in the log.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module ssd1315_model #(
    parameter [6:0] ADDR = 7'h3C
)(
    input  wire scl,
    inout  wire sda,
    input  wire res_n
);
    reg  [7:0] gddram [0:1023];      // 8 pages x 128 columns
    reg        ack_drv;
    assign sda = ack_drv ? 1'b0 : 1'bz;

    reg        in_xfer;
    reg        addr_phase, ctrl_phase, data_mode;
    reg  [3:0] bitc;
    reg  [7:0] shifter;
    reg  [1:0] cmd_param;            // remaining parameters of 0x21 / 0x22
    reg  [7:0] pending_cmd;
    reg  [6:0] col, col_s, col_e;
    reg  [2:0] page, page_s, page_e;
    reg        disp_on;
    integer    frame_bytes, frames, nak_cnt, i;

    initial begin
        ack_drv = 1'b0; in_xfer = 1'b0; addr_phase = 1'b0; ctrl_phase = 1'b0;
        data_mode = 1'b0; bitc = 0; shifter = 0; cmd_param = 0; pending_cmd = 0;
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

    // ---- START / STOP -----------------------------------------------------
    always @(negedge sda) if (scl === 1'b1) begin
        in_xfer <= 1'b1; addr_phase <= 1'b1; ctrl_phase <= 1'b0;
        bitc <= 0; ack_drv <= 1'b0;
    end
    always @(posedge sda) if (scl === 1'b1) begin
        in_xfer <= 1'b0; ack_drv <= 1'b0; bitc <= 0;
    end

    // ---- bit sampling -----------------------------------------------------
    always @(posedge scl) if (in_xfer) begin
        if (bitc < 8) shifter <= {shifter[6:0], (sda === 1'b1)};
        bitc <= bitc + 1;
    end

    always @(negedge scl) if (in_xfer) begin
        if (bitc == 8) begin
            if (addr_phase) begin
                addr_phase <= 1'b0;
                if (shifter[7:1] == ADDR) begin
                    ack_drv    <= 1'b1;
                    ctrl_phase <= 1'b1;
                end else begin
                    ack_drv <= 1'b0;
                    nak_cnt <= nak_cnt + 1;
                end
            end else if (ctrl_phase) begin
                ctrl_phase <= 1'b0;
                data_mode  <= shifter[6];        // 0x40 -> data, 0x00 -> command
                ack_drv    <= 1'b1;
            end else begin
                ack_drv <= 1'b1;
                if (data_mode) begin
                    gddram[{page, col}] <= shifter;
                    frame_bytes = frame_bytes + 1;
                    if (frame_bytes == 1024) begin
                        frame_bytes = 0;
                        frames      = frames + 1;
                    end
                    if (col == col_e) begin
                        col  <= col_s;
                        page <= (page == page_e) ? page_s : page + 1;
                    end else
                        col <= col + 1;
                end else begin
                    if (cmd_param != 0) begin
                        cmd_param <= cmd_param - 1;
                        if (pending_cmd == 8'h21) begin
                            if (cmd_param == 2) begin col_s <= shifter[6:0]; col <= shifter[6:0]; end
                            else                       col_e <= shifter[6:0];
                        end else if (pending_cmd == 8'h22) begin
                            if (cmd_param == 2) begin page_s <= shifter[2:0]; page <= shifter[2:0]; end
                            else                       page_e <= shifter[2:0];
                        end
                    end else begin
                        pending_cmd <= shifter;
                        case (shifter)
                            8'h21, 8'h22: cmd_param <= 2;
                            8'hAF:        disp_on   <= 1'b1;
                            8'hAE:        disp_on   <= 1'b0;
                            default:      ;
                        endcase
                    end
                end
            end
        end else if (bitc == 9) begin
            ack_drv <= 1'b0;
            bitc    <= 0;
        end
    end

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
