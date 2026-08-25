//
// Pseudo RNG: 7-bits
//

module lfsr_7bit (
    input wire clk,
    input wire rst,
    input wire enable,
    output reg [6:0] rand_out
);

    // Feedback using primitive polynomial x^7 + x^6 + 1 (taps at index 6 and 5)
    wire feedback = rand_out[6] ^ rand_out[5];

    always @(posedge clk or posedge rst)
        if (rst)
            rand_out <= 7'b0000001; // Seed value must not be all-zeros
        else
            if (enable)
                rand_out <= {rand_out[5:0], feedback};

endmodule
