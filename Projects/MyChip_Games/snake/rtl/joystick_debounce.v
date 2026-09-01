// joystick_debounce -- 2-FF input synchronisers plus an 8 ms debounce.
//
// The joystick pins are asynchronous to clk, so each one is passed through
// two flip-flops before it reaches any logic; without that a metastable
// sample can propagate into the shift registers below.
module joystick_debounce #(
    parameter integer CLK_HZ = 25_000_000
) (
    input  wire clk,
    input  wire rst_n,
    input  wire in_up, in_down, in_left, in_right, in_center,
    output reg  out_up, out_down, out_left, out_right, out_center
);

    localparam integer TICK_1MS = CLK_HZ / 1000;
    localparam integer TW       = $clog2(TICK_1MS);

    reg  [TW-1:0] tick_cnt;
    wire          tick_1ms = (tick_cnt == TICK_1MS[TW-1:0] - 1'b1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)        tick_cnt <= {TW{1'b0}};
        else if (tick_1ms) tick_cnt <= {TW{1'b0}};
        else               tick_cnt <= tick_cnt + 1'b1;
    end

    // ---- 2-FF synchronisers (pins idle high: the joystick is active low)
    reg [4:0] sync_meta, sync_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_meta <= 5'b11111;
            sync_q    <= 5'b11111;
        end else begin
            sync_meta <= {in_center, in_right, in_left, in_down, in_up};
            sync_q    <= sync_meta;
        end
    end

    wire [4:0] pressed = ~sync_q;      // active low in, active high out

    // ---- 8 consecutive equal 1 ms samples before the output moves
    reg [7:0] sh_up, sh_dn, sh_lf, sh_rt, sh_ct;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sh_up <= 0; sh_dn <= 0; sh_lf <= 0; sh_rt <= 0; sh_ct <= 0;
            out_up <= 0; out_down <= 0; out_left <= 0; out_right <= 0; out_center <= 0;
        end else if (tick_1ms) begin
            sh_up <= {sh_up[6:0], pressed[0]};
            if (sh_up == 8'hFF) out_up <= 1'b1; else if (sh_up == 8'h00) out_up <= 1'b0;

            sh_dn <= {sh_dn[6:0], pressed[1]};
            if (sh_dn == 8'hFF) out_down <= 1'b1; else if (sh_dn == 8'h00) out_down <= 1'b0;

            sh_lf <= {sh_lf[6:0], pressed[2]};
            if (sh_lf == 8'hFF) out_left <= 1'b1; else if (sh_lf == 8'h00) out_left <= 1'b0;

            sh_rt <= {sh_rt[6:0], pressed[3]};
            if (sh_rt == 8'hFF) out_right <= 1'b1; else if (sh_rt == 8'h00) out_right <= 1'b0;

            sh_ct <= {sh_ct[6:0], pressed[4]};
            if (sh_ct == 8'hFF) out_center <= 1'b1; else if (sh_ct == 8'h00) out_center <= 1'b0;
        end
    end
endmodule
