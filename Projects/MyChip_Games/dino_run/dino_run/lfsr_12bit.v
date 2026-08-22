//
// lfsr_12bit.v
//  Delay for Cactus 0[3:0],1[7:4],2[11:8]
//

module lfsr_12bit (clk, rst, enable, lfsr_out);
input           clk;
input           rst;
input           enable;
output [11:0]   lfsr_out;

    reg [11:0]  lfsr_out;
 
    // Feedback wire using maximal-period taps for 12 bits: X^12 + X^11 + X^10 + X^4 + 1
    // Note: Verilog arrays are 0-indexed, so bit 11 corresponds to X^12, bit 3 to X^4, etc.
    wire feedback = lfsr_out[11] ^ lfsr_out[10] ^ lfsr_out[9] ^ lfsr_out[3];

    always @(posedge clk or posedge rst)
    begin
        if (rst)
        begin
            // LFSR must be initialized to a non-zero value.
            // If initialized to 0, it will lock up.
            lfsr_out <= 12'h001; 
        end
        else
        begin
            // Shift left and insert feedback bit at the LSB
            if (enable)
                lfsr_out <= {lfsr_out[10:0], feedback};
        end
    end

endmodule
