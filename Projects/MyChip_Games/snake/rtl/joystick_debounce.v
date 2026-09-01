module joystick_debounce (
    input  wire clk,
    input  wire rst_n,
    input  wire in_up, in_down, in_left, in_right, in_center,
    output reg  out_up, out_down, out_left, out_right, out_center
);
    // 1ms 틱 생성기 (125MHz 기준)
    reg [16:0] tick_cnt;
    wire tick_1ms = (tick_cnt == 17'd124_999);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) tick_cnt <= 0;
        else if (tick_1ms) tick_cnt <= 0;
        else tick_cnt <= tick_cnt + 1;
    end

    // Active-Low 입력을 게임 엔진용 Active-High로 반전
    wire up_inv = ~in_up;
    wire dn_inv = ~in_down;
    wire lf_inv = ~in_left;
    wire rt_inv = ~in_right;
    wire ct_inv = ~in_center;

    reg [7:0] sh_up, sh_dn, sh_lf, sh_rt, sh_ct;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sh_up <= 0; sh_dn <= 0; sh_lf <= 0; sh_rt <= 0; sh_ct <= 0;
            out_up <= 0; out_down <= 0; out_left <= 0; out_right <= 0; out_center <= 0;
        end else if (tick_1ms) begin
            // 8번 연속 동일한 값이 들어와야 최종 출력 변경 (8ms 딜레이)
            sh_up <= {sh_up[6:0], up_inv};
            if (sh_up == 8'hFF) out_up <= 1'b1; else if (sh_up == 8'h00) out_up <= 1'b0;

            sh_dn <= {sh_dn[6:0], dn_inv};
            if (sh_dn == 8'hFF) out_down <= 1'b1; else if (sh_dn == 8'h00) out_down <= 1'b0;

            sh_lf <= {sh_lf[6:0], lf_inv};
            if (sh_lf == 8'hFF) out_left <= 1'b1; else if (sh_lf == 8'h00) out_left <= 1'b0;

            sh_rt <= {sh_rt[6:0], rt_inv};
            if (sh_rt == 8'hFF) out_right <= 1'b1; else if (sh_rt == 8'h00) out_right <= 1'b0;

            sh_ct <= {sh_ct[6:0], ct_inv};
            if (sh_ct == 8'hFF) out_center <= 1'b1; else if (sh_ct == 8'h00) out_center <= 1'b0;
        end
    end
endmodule