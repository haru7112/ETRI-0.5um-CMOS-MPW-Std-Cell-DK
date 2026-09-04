//----------------------------------------------------------------------------
// spi_master.v
//  Write only SPI shifter for an SSD1306 panel in 4-wire mode.
//
//  All it does is push a byte out MSB first.  D/C# and CS# belong to the
//  sequencer above, not here: they change once per burst, not once per byte,
//  so keeping them out of this block costs nothing and saves the handshake
//  that would carry them.
//
//  Mode 0: SCLK idles low, MOSI changes while SCLK is low, the panel samples
//  on the rising edge.  SSD1306 wants a cycle no shorter than 100ns, so
//  SCLK_HZ must stay at or under 10MHz.
//
//  This replaces i2c_master, which needed a START/STOP generator, an open
//  drain pair and an ACK path for the same job - 0.140mm2 against 0.070.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module spi_master #(
    parameter CLK_HZ  = 25_000_000,
    parameter SCLK_HZ =  6_250_000
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       write,      // pulse: shift din out
    input  wire [7:0] din,
    output reg        busy,
    output reg        done,       // 1 clock pulse when the byte has gone

    output reg        sclk,
    output reg        mosi
);
    // half a SCLK period, in core clocks
    localparam integer DIV   = (CLK_HZ + (2*SCLK_HZ) - 1) / (2*SCLK_HZ);
    localparam integer DIV_W = (DIV <= 2) ? 1 : $clog2(DIV);

    reg [DIV_W-1:0] div;
    reg [7:0]       sh;
    reg [2:0]       bit_n;

    wire tick = (div == DIV[DIV_W-1:0] - 1'b1);

    always @(posedge clk)
        if (!rst_n) begin
            div   <= {DIV_W{1'b0}};
            sh    <= 8'h00;
            bit_n <= 3'd0;
            busy  <= 1'b0;
            done  <= 1'b0;
            sclk  <= 1'b0;
            mosi  <= 1'b0;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                if (write) begin
                    sh    <= {din[6:0], 1'b0};   // bit 7 goes out now
                    mosi  <= din[7];
                    bit_n <= 3'd0;
                    div   <= {DIV_W{1'b0}};
                    sclk  <= 1'b0;
                    busy  <= 1'b1;
                end
            end else if (!tick) begin
                div <= div + 1'b1;
            end else begin
                div <= {DIV_W{1'b0}};
                if (!sclk) begin
                    sclk <= 1'b1;                // panel samples here
                end else begin
                    sclk <= 1'b0;
                    if (bit_n == 3'd7) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                    end else begin
                        bit_n <= bit_n + 3'd1;
                        mosi  <= sh[7];          // next bit, while SCLK is low
                        sh    <= {sh[6:0], 1'b0};
                    end
                end
            end
        end

endmodule
