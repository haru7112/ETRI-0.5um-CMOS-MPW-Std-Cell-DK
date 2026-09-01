module pixel_scanner(
    input  wire clk,
    input  wire rst_n,
    input  wire [6:0] col_x,
    input  wire [2:0] page_y,
    input  wire [7:0] head_ptr,
    input  wire [7:0] tail_ptr,
    input  wire [10:0] food_pos,
    input  wire [10:0] read_data,
    
    input  wire [3:0] t_sec_l, t_sec_h, t_min_l, t_min_h,
    input  wire [3:0] s_100, s_10, s_1,
    
    output reg  [7:0] read_addr,
    output reg  [7:0] pixel_byte,
    // High only while pixel_byte matches the col_x/page_y currently applied.
    // Drops combinationally the instant the address changes, so the I2C
    // master can never latch a byte belonging to the previous cell.
    output wire       pixel_valid
);

    wire is_ui = (col_x < 31);
    wire is_border = (col_x == 31);
    
    wire [4:0] ui_col = col_x[4:0];
    
    // 5x5 폰트용 셀 계산 (6픽셀 간격)
    wire [2:0] font_col_5x5 = (ui_col % 6);
    wire [2:0] ui_cell_5x5  = (ui_col / 6);
    
    // 3x5 폰트용 셀 계산 (4픽셀 간격)
    wire [1:0] font_col_3x5 = (ui_col % 4);
    wire [3:0] ui_cell_3x5  = (ui_col / 4);

    reg [4:0] char_val; 
    
    // UI 레이아웃 지정 (영역별로 다른 셀 기준 적용)
    always @(*) begin
        char_val = 5'd11; // 기본 공백
        if (page_y == 0) begin 
            case(ui_cell_5x5)
                0: char_val = 5'd12; 1: char_val = 5'd13; 2: char_val = 5'd14; 
                3: char_val = 5'd15; 4: char_val = 5'd16; default: char_val = 5'd11;
            endcase
        end else if (page_y == 1) begin 
            case(ui_cell_5x5)
                0: char_val = 5'd17; 1: char_val = 5'd14; 2: char_val = 5'd18; 
                3: char_val = 5'd16; default: char_val = 5'd11;
            endcase
        end else if (page_y == 4) begin 
            case(ui_cell_3x5)
                0: char_val = {1'b0, t_min_h}; 1: char_val = {1'b0, t_min_l}; 2: char_val = 5'd10;
                3: char_val = {1'b0, t_sec_h}; 4: char_val = {1'b0, t_sec_l}; default: char_val = 5'd11;
            endcase
        end else if (page_y == 6) begin 
            case(ui_cell_3x5)
                0: char_val = {1'b0, s_100}; 1: char_val = {1'b0, s_10}; 2: char_val = {1'b0, s_1}; 
                default: char_val = 5'd11;
            endcase
        end
    end

    reg [7:0] timer_data;
    
    // 영역별 폰트 데이터 분기 렌더링
    always @(*) begin
        timer_data = 8'h00;
        
        if (page_y <= 1) begin
            // 5x5 알파벳 폰트 (SNAKE GAME 영역)
            if (font_col_5x5 == 5 || char_val == 11) timer_data = 8'h00;
            else begin
                case (char_val)
                    5'd12: case(font_col_5x5) 0: timer_data=8'h24; 1: timer_data=8'h2A; 2: timer_data=8'h2A; 3: timer_data=8'h2A; 4: timer_data=8'h12; default: timer_data=8'h00; endcase // S
                    5'd13: case(font_col_5x5) 0: timer_data=8'h3E; 1: timer_data=8'h04; 2: timer_data=8'h08; 3: timer_data=8'h10; 4: timer_data=8'h3E; default: timer_data=8'h00; endcase // N
                    5'd14: case(font_col_5x5) 0: timer_data=8'h3E; 1: timer_data=8'h0A; 2: timer_data=8'h0A; 3: timer_data=8'h0A; 4: timer_data=8'h3E; default: timer_data=8'h00; endcase // A
                    5'd15: case(font_col_5x5) 0: timer_data=8'h3E; 1: timer_data=8'h08; 2: timer_data=8'h14; 3: timer_data=8'h22; 4: timer_data=8'h00; default: timer_data=8'h00; endcase // K
                    5'd16: case(font_col_5x5) 0: timer_data=8'h3E; 1: timer_data=8'h2A; 2: timer_data=8'h2A; 3: timer_data=8'h2A; 4: timer_data=8'h22; default: timer_data=8'h00; endcase // E
                    5'd17: case(font_col_5x5) 0: timer_data=8'h3C; 1: timer_data=8'h22; 2: timer_data=8'h2A; 3: timer_data=8'h2A; 4: timer_data=8'h1A; default: timer_data=8'h00; endcase // G
                    5'd18: case(font_col_5x5) 0: timer_data=8'h3E; 1: timer_data=8'h02; 2: timer_data=8'h04; 3: timer_data=8'h02; 4: timer_data=8'h3E; default: timer_data=8'h00; endcase // M
                    default: timer_data = 8'h00;
                endcase
            end
        end else begin
            // 3x5 숫자 폰트 (시간 및 점수 영역)
            if (font_col_3x5 == 3 || char_val == 11) timer_data = 8'h00;
            else begin
                case (char_val)
                    5'd0:  case(font_col_3x5) 0: timer_data=8'h3E; 1: timer_data=8'h22; 2: timer_data=8'h3E; default: timer_data=8'h00; endcase
                    5'd1:  case(font_col_3x5) 0: timer_data=8'h00; 1: timer_data=8'h3E; 2: timer_data=8'h00; default: timer_data=8'h00; endcase
                    5'd2:  case(font_col_3x5) 0: timer_data=8'h3A; 1: timer_data=8'h2A; 2: timer_data=8'h2E; default: timer_data=8'h00; endcase
                    5'd3:  case(font_col_3x5) 0: timer_data=8'h2A; 1: timer_data=8'h2A; 2: timer_data=8'h3E; default: timer_data=8'h00; endcase
                    5'd4:  case(font_col_3x5) 0: timer_data=8'h0E; 1: timer_data=8'h08; 2: timer_data=8'h3E; default: timer_data=8'h00; endcase
                    5'd5:  case(font_col_3x5) 0: timer_data=8'h2E; 1: timer_data=8'h2A; 2: timer_data=8'h3A; default: timer_data=8'h00; endcase
                    5'd6:  case(font_col_3x5) 0: timer_data=8'h3E; 1: timer_data=8'h2A; 2: timer_data=8'h3A; default: timer_data=8'h00; endcase
                    5'd7:  case(font_col_3x5) 0: timer_data=8'h02; 1: timer_data=8'h02; 2: timer_data=8'h3E; default: timer_data=8'h00; endcase
                    5'd8:  case(font_col_3x5) 0: timer_data=8'h3E; 1: timer_data=8'h2A; 2: timer_data=8'h3E; default: timer_data=8'h00; endcase
                    5'd9:  case(font_col_3x5) 0: timer_data=8'h2E; 1: timer_data=8'h2A; 2: timer_data=8'h3E; default: timer_data=8'h00; endcase
                    5'd10: case(font_col_3x5) 0: timer_data=8'h00; 1: timer_data=8'h14; 2: timer_data=8'h00; default: timer_data=8'h00; endcase // :
                    default: timer_data = 8'h00;
                endcase
            end
        end
    end

    reg [6:0] last_col;
    reg [2:0] last_page;
    reg [7:0] scan_byte, scan_ptr;
    reg scanning;

    wire [6:0] game_col = col_x - 7'd32;
    wire [5:0] cx  = game_col[6:1];
    wire [4:0] cy0 = {page_y, 2'd0}; wire [4:0] cy1 = {page_y, 2'd1};
    wire [4:0] cy2 = {page_y, 2'd2}; wire [4:0] cy3 = {page_y, 2'd3};

    // 이번 스캔 단계가 더하는 픽셀들. scan_byte 에 반영되기 전의 조합 논리라
    // 마지막 세그먼트(머리)까지 포함해 pixel_byte 로 바로 넘길 수 있다.
    wire [7:0] scan_hit = {(read_data == {cx, cy3}) ? 2'b11 : 2'b00,
                           (read_data == {cx, cy2}) ? 2'b11 : 2'b00,
                           (read_data == {cx, cy1}) ? 2'b11 : 2'b00,
                           (read_data == {cx, cy0}) ? 2'b11 : 2'b00};
    wire [7:0] scan_byte_next = scan_byte | scan_hit;

    wire addr_changed = (col_x != last_col) || (page_y != last_page);
    reg  byte_ready;
    assign pixel_valid = byte_ready && !addr_changed;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_col <= 7'h7F; last_page <= 3'h7; scanning <= 0;
            pixel_byte <= 8'h00; read_addr <= 0; byte_ready <= 0;
            scan_byte <= 8'h00; scan_ptr <= 8'h00;
        end else begin
            if (addr_changed) begin
                last_col <= col_x; last_page <= page_y;
                
                if (is_border) begin
                    pixel_byte <= 8'hFF; scanning <= 0; byte_ready <= 1;
                end else if (is_ui) begin
                    pixel_byte <= timer_data; scanning <= 0; byte_ready <= 1;
                end else begin
                    scanning <= 1; byte_ready <= 0;
                    scan_ptr <= tail_ptr; read_addr <= tail_ptr;
                    scan_byte <= 8'h00;
                    if (food_pos == {cx, cy0}) scan_byte[1:0] <= 2'b11;
                    if (food_pos == {cx, cy1}) scan_byte[3:2] <= 2'b11;
                    if (food_pos == {cx, cy2}) scan_byte[5:4] <= 2'b11;
                    if (food_pos == {cx, cy3}) scan_byte[7:6] <= 2'b11;
                end
            end else if (scanning) begin
                scan_byte <= scan_byte_next;

                if (scan_ptr == head_ptr) begin
                    scanning <= 0; pixel_byte <= scan_byte_next; byte_ready <= 1;
                end else begin
                    scan_ptr <= scan_ptr + 1; read_addr <= scan_ptr + 1;
                end
            end
        end
    end
endmodule