//----------------------------------------------------------------------------
// tb_pixel.v - directed unit test of the body register + procedural renderer.
//  A known body is pushed in, all 1024 bytes are pulled out, and the image is
//  compared cell by cell against what the body register says it should be.
//  Runs for any CELL_SH (override with iverilog -Ptb_pixel.CELL_SH=n).
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_pixel;
    parameter CELL_SH = 1;
    parameter MAXLEN  = 48;
    parameter LEN_W   = 6;

    localparam GX_W   = 7 - CELL_SH;
    localparam GY_W   = 6 - CELL_SH;
    localparam POS_W  = GX_W + GY_W;
    localparam GRID_W = (1 << GX_W);
    localparam GRID_H = (1 << GY_W);
    localparam CPP    = (8 >> CELL_SH);
    localparam SCORE_W= (16 >> CELL_SH);
    localparam NSEG   = 5;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg              load = 0, move = 0, grow = 0;
    reg  [POS_W-1:0] load_pos = 0;
    reg  [1:0]       step_dir = 0;
    reg              req = 0;
    reg  [6:0]       x = 0;
    reg  [2:0]       page = 0;

    wire             p_scan_req, scan_valid, scan_done, cmp_hit, scan_busy;
    wire [POS_W-1:0] scan_pos, head, step_pos;
    wire [LEN_W-1:0] len;
    wire             valid;
    wire [7:0]       dout;

    snake_body #(.POS_W(POS_W), .GX_W(GX_W), .MAXLEN(MAXLEN), .LEN_W(LEN_W)) u_body (
        .clk(clk), .rst_n(rst_n),
        .load(load), .load_pos(load_pos), .move(move), .grow(grow),
        .step_dir(step_dir), .step_pos(step_pos),
        .scan_req(p_scan_req), .cmp_food(1'b0), .cmp_pos({POS_W{1'b0}}),
        .cmp_skip_tail(1'b0),
        .scan_busy(scan_busy), .scan_pos(scan_pos), .scan_valid(scan_valid),
        .scan_done(scan_done), .cmp_hit(cmp_hit), .head(head), .len(len));

    pixel_gen #(.CELL_SH(CELL_SH), .MAXLEN(MAXLEN)) u_pix (
        .clk(clk), .rst_n(rst_n),
        .req(req), .x(x), .page(page), .valid(valid), .dout(dout),
        .st_title(1'b0), .st_over(1'b0), .score_bcd(8'h00),
        .blink(1'b0), .food_en(1'b0),
        .scan_req(p_scan_req), .scan_pos_i({{(11-POS_W){1'b0}}, scan_pos}),
        .scan_valid(scan_valid), .scan_done(scan_done), .food_pos_i(11'd0));

    reg [7:0] img [0:1023];
    integer   i, j, k, lit, errors;

    task push(input [1:0] d);
        begin
            @(posedge clk);
            step_dir <= d;
            @(posedge clk);
            move <= 1'b1;  grow <= 1'b1;
            @(posedge clk);
            move <= 1'b0;  grow <= 1'b0;
            @(posedge clk);
        end
    endtask

    task grab_frame;
        integer n;
        begin
            for (n = 0; n < 1024; n = n + 1) begin
                @(posedge clk);
                x <= n[6:0];  page <= n[9:7];  req <= 1'b1;
                @(posedge clk);
                req <= 1'b0;
                @(posedge valid);
                @(posedge clk);
                img[n] = dout;
            end
        end
    endtask

    // a cell is "lit" when every pixel of its CELL_PX x CELL_PX block is set
    function cell_lit(input [GX_W-1:0] cx, input [GY_W-1:0] cy);
        integer px, py, ok;
        reg [6:0] xx;
        reg [5:0] yy;
        begin
            ok = 1;
            for (px = 0; px < (1<<CELL_SH); px = px + 1)
                for (py = 0; py < (1<<CELL_SH); py = py + 1) begin
                    xx = (cx << CELL_SH) + px;
                    yy = (cy << CELL_SH) + py;
                    if (!img[{yy[5:3], xx}][yy[2:0]]) ok = 0;
                end
            cell_lit = ok[0];
        end
    endfunction

    reg [POS_W-1:0] want [0:NSEG-1];
    reg [GX_W-1:0]  bx, wx;
    reg [GY_W-1:0]  by, wy;

    initial begin
        errors = 0;
        bx = (SCORE_W + GRID_W - 1) / 2;
        by = GRID_H/2;
        #20 rst_n = 1;
        @(posedge clk);
        load_pos <= {by, bx};  load <= 1'b1;
        @(posedge clk);
        load <= 1'b0;
        @(posedge clk);
        want[4] = {by, bx};
        wx = bx + 1;  wy = by;      push(2'b00);  want[3] = {wy, wx};
        wx = bx + 2;  wy = by;      push(2'b00);  want[2] = {wy, wx};
        wx = bx + 2;  wy = by - 1;  push(2'b11);  want[1] = {wy, wx};
        wx = bx + 2;  wy = by - 2;  push(2'b11);  want[0] = {wy, wx};

        $display("CELL_SH=%0d grid=%0dx%0d  len=%0d head=(%0d,%0d)",
                 CELL_SH, GRID_W, GRID_H, len, head[GX_W-1:0], head[POS_W-1:GX_W]);

        grab_frame;

        for (j = 0; j < NSEG; j = j + 1)
            if (!cell_lit(want[j][GX_W-1:0], want[j][POS_W-1:GX_W])) begin
                $display("[FAIL] body cell (%0d,%0d) is dark",
                         want[j][GX_W-1:0], want[j][POS_W-1:GX_W]);
                errors = errors + 1;
            end

        lit = 0;
        for (j = SCORE_W+1; j < GRID_W-1; j = j + 1)
            for (k = 1; k < GRID_H-1; k = k + 1)
                if (cell_lit(j[GX_W-1:0], k[GY_W-1:0])) lit = lit + 1;
        if (lit != NSEG) begin
            $display("[FAIL] %0d lit cells inside the field, expected %0d", lit, NSEG);
            errors = errors + 1;
        end

        // the two rules run the full width, the divider and the right edge
        // close the play field
        for (j = 0; j < GRID_W; j = j + 1)
            if (!cell_lit(j[GX_W-1:0], 0) || !cell_lit(j[GX_W-1:0], (GRID_H-1))) begin
                $display("[FAIL] rule broken at column %0d", j);
                errors = errors + 1;
            end
        for (k = 0; k < GRID_H; k = k + 1)
            if (!cell_lit(SCORE_W[GX_W-1:0], k[GY_W-1:0]) ||
                !cell_lit((GRID_W-1), k[GY_W-1:0])) begin
                $display("[FAIL] wall broken at row %0d", k);
                errors = errors + 1;
            end

        if (errors == 0) $display("==== PIXEL TB PASSED (CELL_SH=%0d) ====", CELL_SH);
        else             $display("==== PIXEL TB FAILED (CELL_SH=%0d, %0d) ====", CELL_SH, errors);
        $finish;
    end
endmodule
