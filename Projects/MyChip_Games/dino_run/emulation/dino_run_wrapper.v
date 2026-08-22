//
// Poorman's Standard-Emulator by GoodKook, goodkook@gmail.com
//  Co-Emulation warapper for the "dino_run"
//

module dino_run_wrapper(Din_emu, Dout_emu, Addr_emu, load_emu, get_emu, clk_emu, clk_dut, io_req);
    input  [7:0]    Din_emu;
    output [7:0]    Dout_emu;
    input  [2:0]    Addr_emu;
    input           load_emu, get_emu, clk_emu;
    input           clk_dut;
    output          io_req;
    
    // Std. Emulation wrapper: Stimulus & Output capture for DUT
    parameter   NUM_STIM_ARRAY  = 1,
                NUM_OUT_ARRAY   = 1;
    reg [7:0]   stimIn[0:NUM_STIM_ARRAY-1];
    reg [7:0]   vectOut[0:NUM_OUT_ARRAY-1];
    reg [7:0]   Dout_emu;

// Emulation Transactor -------------------------------
// DUT's input bitmap               DUT's output bitmap
//      +-------+-+-+-+-+               +-------+-+-+-+-+
//  [0] |7 6 5 4|3|2|1|0|           [0] |7 6 5 4|3|2|1|0|
//      +-------+-+-+-+-+               +-------+-+-+-+-+
//               | | | |                         | | | |
//               | | | +---game_new              | | | +---v_sync
//               | | +---jump                    | | +---pixel
//               | +---reset                     | +---p_tick
//               +---clk                         +---game_over
//

    // DUT interface: registered input
    reg     reset, jump, game_new;
    // DUT interface: output wire. DUT's output will be captured
    wire    v_sync, pixel, p_tick, game_over;

    always @(posedge clk_emu)
    begin
        if (load_emu)   // Input stimulus to DUT
        begin
            game_new <= stimIn[0][0];
            jump     <= stimIn[0][1];
            reset    <= stimIn[0][2];
        end
        else if (get_emu)   // Capure output from DUT
        begin
            vectOut[0][0] <= v_sync;
            vectOut[0][1] <= pixel;
            vectOut[0][2] <= p_tick;
            vectOut[0][3] <= game_over;
        end
        else
        begin
            stimIn[Addr_emu] <= Din_emu;
            Dout_emu <= vectOut[Addr_emu];
        end
    end
    
    // DUT
    dino_run u_dino_run(
        .clk(clk_dut),  // Controlled Clock
        .reset(reset),
        .v_sync(v_sync),
        .pixel(pixel),
        .p_tick(p_tick),
        .jump(jump),    // btn_up
        .game_over(game_over),
        .game_new(game_new));

    assign io_req = clk_dut;

endmodule

