//----------------------------------------------------------------------------
// debounce.v
//  Two stage metastability sync + 3 sample majority filter clocked by a 1ms
//  strobe.  A level therefore has to be stable for ~3ms before it is accepted,
//  which is well beyond the bounce time of a tactile 5-way switch.
//  Inputs are active low (switch closes to GND, external pull-up).
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module debounce #(
    parameter N = 5                       // number of parallel switch inputs
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         ms_pulse,         // 1 clock wide, once per millisecond
    input  wire [N-1:0] pin_n,            // raw, active low
    output reg  [N-1:0] level,            // debounced, active high (1 = pressed)
    output reg  [N-1:0] press             // 1 clock wide pulse on 0->1 of level
);
    reg [N-1:0] s0, s1;
    reg [N-1:0] h0, h1, h2;
    reg [N-1:0] level_d;
    integer i;

    always @(posedge clk)
        if (!rst_n) begin
            s0 <= {N{1'b1}};  s1 <= {N{1'b1}};
        end else begin
            s0 <= pin_n;      s1 <= s0;
        end

    always @(posedge clk)
        if (!rst_n) begin
            h0 <= {N{1'b0}};  h1 <= {N{1'b0}};  h2 <= {N{1'b0}};
        end else if (ms_pulse) begin
            h0 <= ~s1;                    // active low pin -> active high sample
            h1 <= h0;
            h2 <= h1;
        end

    always @(posedge clk)
        if (!rst_n) begin
            level <= {N{1'b0}};
        end else begin
            for (i = 0; i < N; i = i + 1) begin
                if       ( h0[i] &  h1[i] &  h2[i]) level[i] <= 1'b1;
                else if (~h0[i] & ~h1[i] & ~h2[i]) level[i] <= 1'b0;
            end
        end

    always @(posedge clk)
        if (!rst_n) begin
            level_d <= {N{1'b0}};
            press   <= {N{1'b0}};
        end else begin
            level_d <= level;
            press   <= level & ~level_d;
        end

endmodule
