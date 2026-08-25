
//
// Pseudo RNG: 6-bits
//
module lfsr_6bit (
    input clk,
    input rst,
    input enable,
    output reg [5:0] rand_out
);
    wire feedback;

    assign feedback = rand_out[5] ^ rand_out[4]; // Taps at 6th and 5th bits (indices 5 and 4)

    always @(posedge clk or posedge rst) begin
        if (rst)
            rand_out <= 6'b100000; // Seed value (must not be all zeros)
        else
            if (enable)
                rand_out <= {rand_out[4:0], feedback};
    end
endmodule
