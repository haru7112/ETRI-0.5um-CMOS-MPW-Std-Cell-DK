module clk_div (
    input  wire clk_125m,
    input  wire rst_n,
    output reg  clk_1m6
);
    reg [5:0] cnt_i2c;

    always @(posedge clk_125m or negedge rst_n) begin
        if (!rst_n) begin 
            cnt_i2c <= 0; 
            clk_1m6 <= 0; 
        end else if (cnt_i2c == 6'd38) begin // 125MHz / 78 ≒ 1.6MHz
            cnt_i2c <= 0; 
            clk_1m6 <= ~clk_1m6; 
        end else begin
            cnt_i2c <= cnt_i2c + 1;
        end
    end
endmodule