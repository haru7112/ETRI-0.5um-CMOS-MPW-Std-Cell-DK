//----------------------------------------------------------------------------
// i2c_master.v
//  Minimal write-only I2C master for the SSD1315 panel.
//
//  Both lines are true open drain: the module only ever pulls low, the bus
//  pull-ups do the rest, which is what the PADINOUT cell of the ETRI 0.5um
//  library gives us and what lets a 5V chip share the bus with a 3.3V panel
//  through its own pull-ups.
//
//  One bit is four quarter phases:  q0 drive data / SCL low
//                                   q1 SCL high
//                                   q2 SCL high  (slave samples, we sample ACK)
//                                   q3 SCL low
//  START and STOP get their own phases so the setup/hold times around them are
//  a full quarter bit.
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module i2c_master #(
    parameter CLK_HZ = 25_000_000,
    parameter SCL_HZ = 400_000
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       start,     // pulse: START condition, then send din
    input  wire       write,     // pulse: send din
    input  wire       stop,      // pulse: STOP condition
    input  wire [7:0] din,
    output reg        busy,
    output reg        done,      // 1 clock pulse when a request completes
    output reg        ack,       // ACK of the byte that just went out

    output wire       scl_oe,    // 1 = pull SCL low, 0 = release
    output wire       sda_oe,    // 1 = pull SDA low, 0 = release
    input  wire       sda_i
);
    localparam integer DIV   = (CLK_HZ + (4*SCL_HZ) - 1) / (4*SCL_HZ);
    localparam integer DIV_W = (DIV <= 2) ? 1 : $clog2(DIV);

    // Each of these states owns exactly one quarter bit, so START and STOP are
    // built edge by edge and never move SDA and SCL in the same cycle - that
    // matters at high SCL_HZ where a quarter bit is a single clock.
    localparam ST_IDLE   = 4'd0,
               ST_STARTA = 4'd1,   // release SDA   (SCL still low)
               ST_STARTB = 4'd2,   // release SCL
               ST_STARTC = 4'd3,   // SDA falls while SCL is high  <- START
               ST_STARTD = 4'd4,   // SCL falls
               ST_BIT    = 4'd5,
               ST_ACK    = 4'd6,
               ST_STOPA  = 4'd7,   // SCL low, SDA low
               ST_STOPB  = 4'd8,   // SCL rises
               ST_STOPC  = 4'd9;   // SDA rises while SCL is high  <- STOP

    reg [3:0]  st;
    reg [1:0]  q;                       // quarter bit phase
    reg [2:0]  bitcnt;
    reg [7:0]  sh;
    reg        scl_r, sda_r;            // wanted bus levels (1 = released)

    assign scl_oe = ~scl_r;
    assign sda_oe = ~sda_r;

    // quarter bit strobe
    reg [DIV_W-1:0] div_cnt;
    wire            qtick = (div_cnt == (DIV-1));

    always @(posedge clk)
        if (!rst_n)                        div_cnt <= {DIV_W{1'b0}};
        else if ((st == ST_IDLE) || qtick) div_cnt <= {DIV_W{1'b0}};
        else                               div_cnt <= div_cnt + 1'b1;

    always @(posedge clk)
        if (!rst_n) begin
            st     <= ST_IDLE;
            q      <= 2'd0;
            bitcnt <= 3'd7;
            sh     <= 8'h00;
            scl_r  <= 1'b1;
            sda_r  <= 1'b1;
            busy   <= 1'b0;
            done   <= 1'b0;
            ack    <= 1'b0;
        end else begin
            done <= 1'b0;
            case (st)
            //--------------------------------------------------------------
            ST_IDLE: begin
                busy <= 1'b0;
                q    <= 2'd0;
                if (start) begin
                    sh <= din;  bitcnt <= 3'd7;  busy <= 1'b1;  st <= ST_STARTA;
                end else if (write) begin
                    sh <= din;  bitcnt <= 3'd7;  busy <= 1'b1;  st <= ST_BIT;
                end else if (stop) begin
                    busy <= 1'b1;  st <= ST_STOPA;
                end
            end
            //--------------------------------------------------------------
            ST_STARTA: begin
                sda_r <= 1'b1;
                if (qtick) st <= ST_STARTB;
            end
            ST_STARTB: begin
                scl_r <= 1'b1;
                if (qtick) st <= ST_STARTC;
            end
            ST_STARTC: begin
                sda_r <= 1'b0;                     // START condition
                if (qtick) st <= ST_STARTD;
            end
            ST_STARTD: begin
                scl_r <= 1'b0;
                if (qtick) begin
                    st <= ST_BIT;
                    q  <= 2'd0;
                end
            end
            //--------------------------------------------------------------
            ST_BIT: begin
                case (q)
                2'd0: begin scl_r <= 1'b0; sda_r <= sh[7]; end
                2'd1:       scl_r <= 1'b1;
                2'd2:       ;
                2'd3:       scl_r <= 1'b0;
                endcase
                if (qtick) begin
                    q <= q + 2'd1;
                    if (q == 2'd3) begin
                        sh <= {sh[6:0], 1'b0};
                        if (bitcnt == 3'd0) st     <= ST_ACK;
                        else                bitcnt <= bitcnt - 3'd1;
                    end
                end
            end
            //--------------------------------------------------------------
            ST_ACK: begin
                case (q)
                2'd0: begin scl_r <= 1'b0; sda_r <= 1'b1; end   // release for the slave
                2'd1:       scl_r <= 1'b1;
                2'd2:  if (qtick) ack <= ~sda_i;                // ACK = pulled low
                2'd3:       scl_r <= 1'b0;
                endcase
                if (qtick) begin
                    q <= q + 2'd1;
                    if (q == 2'd3) begin
                        sda_r <= 1'b0;          // park SDA low, ready for a STOP
                        done  <= 1'b1;
                        busy  <= 1'b0;
                        st    <= ST_IDLE;
                    end
                end
            end
            //--------------------------------------------------------------
            ST_STOPA: begin                        // SCL low, SDA low
                scl_r <= 1'b0;  sda_r <= 1'b0;
                if (qtick) st <= ST_STOPB;
            end
            ST_STOPB: begin                        // SCL rises, SDA still low
                scl_r <= 1'b1;
                if (qtick) st <= ST_STOPC;
            end
            ST_STOPC: begin                        // SDA rises while SCL high
                sda_r <= 1'b1;
                if (qtick) begin
                    done <= 1'b1;
                    busy <= 1'b0;
                    st   <= ST_IDLE;
                end
            end
            endcase
        end

endmodule
