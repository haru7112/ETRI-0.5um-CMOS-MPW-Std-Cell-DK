/**********************************************************************
Filename: Epong_vh.h
Purpose : Wrapper for FPGA Emulated pong_vh
Author  : goodkook@gmail.com
History : Aug. 2026, First release
***********************************************************************/

#ifndef _Epong_vh_H_
#define _Epong_vh_H_

#include <systemc.h>

// Includes for accessing Arduino via serial port
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>

SC_MODULE(Epong_vh)
{
    sc_in<bool>     clk;
    sc_in<bool>     reset;
    sc_in<bool>     btn_left;
    sc_in<bool>     btn_right;
    sc_in<bool>     btn_up;
    sc_in<bool>     btn_down;
    sc_in<bool>     game_new;

    sc_out<bool>    v_sync;
    sc_out<bool>    pixel;
    sc_out<bool>    p_tick;
    sc_out<bool>    game_over;

#define N_TX    1
#define N_RX    1

// Emulation Transactor -------------------------------
// DUT's input bitmap               DUT's output bitmap
//      +-+-+-+-+-+-+-+-+               +-------+-+-+-+-+
//  [0] |7|6|5|4|3|2|1|0|           [0] |7 6 5 4|3|2|1|0|
//      +-+-+-+-+-+-+-+-+               +-------+-+-+-+-+
//         | | | | | | |                         | | | |
//         | | | | | | +---game_new              | | | +---v_sync
//         | | | | | +---btn_left                | | +---pixel
//         | | | | +---btn_right                 | +---p_tick
//         | | | +---btn_up                      +---game_over
//         | | +---btn_down
//         | +---reset
//         +---clk
//

    inline void _EMU_IO_(void)
    {
        uint8_t _Rx_, _Tx_, _txPacket_[N_TX], _rxPacket_[N_RX];

        _txPacket_[0] = (uint8_t)(
                        (game_new.read()?   0x01:0x00) |
                        (btn_left.read()?   0x02:0x00) |
                        (btn_right.read()?  0x04:0x00) |
                        (btn_up.read()?     0x08:0x00) |
                        (btn_down.read()?   0x10:0x00) |
                        (reset.read()?      0x20:0x00) |
                        (clk.read()?        0x40:0x00));

        // Send to Emulator
        for (int i=0; i<N_TX; i++)
        {
            _Tx_ = _txPacket_[i];
            while(write(fd, &_Tx_, 1)<=0)  usleep(1);
        }
        // Receive from Emulator
        for (int i=0; i<N_RX; i++)
        {
            while(read(fd, &_Rx_, 1)<=0)   usleep(1);
            _rxPacket_[i] = _Rx_;
        }

        v_sync.write(       (_rxPacket_[0] & 0x01)? true:false);
        pixel.write(        (_rxPacket_[0] & 0x02)? true:false);
        p_tick.write(       (_rxPacket_[0] & 0x04)? true:false);
        game_over.write(    (_rxPacket_[0] & 0x08)? true:false);
    }

//
// Cycle-Accurate(CA) Output Monitor
//
#if defined(CA)
    void pong_vh_CA_thread(void)
    {
        while(true)
        {
            wait(clk.posedge_event());
            _EMU_IO_();
        }
    }
#else
    void pong_vh_method(void)
    {
        _EMU_IO_();
    }
#endif

    // Arduino Serial IF
    int fd;                 // Serial port file descriptor
    struct termios options; // Serial port setting

    sc_trace_file* fp;  // VCD file

    SC_CTOR(Epong_vh): clk("clk")
    {
#if defined(CA)
        SC_THREAD(pong_vh_CA_thread);
        sensitive << clk;
#else
        SC_METHOD(pong_vh_method);
        sensitive << clk << reset << jump << game_new;
#endif
        // WAVE ----------------------------------------------------------
        fp = sc_create_vcd_trace_file("Epong_vh");
        fp->set_time_unit(100, SC_PS);  // resolution (trace) ps
        sc_trace(fp, clk,           "clk");
        sc_trace(fp, reset,         "reset");
        sc_trace(fp, btn_left,      "btn_left");
        sc_trace(fp, btn_right,     "btn_right");
        sc_trace(fp, btn_up,        "btn_up");
        sc_trace(fp, btn_down,      "btn_down");
        sc_trace(fp, game_new,      "game_new");
        sc_trace(fp, v_sync,        "v_sync");
        sc_trace(fp, pixel,         "pixel");
        sc_trace(fp, p_tick,        "p_tick");
        sc_trace(fp, game_over,     "game_over");

        // Connecting Arduino DUT -----------------------------------------
        //fd = open("/dev/ttyACM0", O_RDWR | O_NDELAY | O_NOCTTY);
        fd = open("/dev/ttyACM0", O_RDWR | O_NOCTTY);
        if (fd < 0)
        {
            perror("Error opening serial port");
            return;
        }
        // Set up serial port
        options.c_cflag = B115200 | CS8 | CLOCAL | CREAD;
        options.c_iflag = IGNPAR;
        options.c_oflag = 0;
        options.c_lflag = 0;
        // Apply the settings
        tcflush(fd, TCIFLUSH);
        tcsetattr(fd, TCSANOW, &options);

        // Establish Contact
        fprintf(stderr, "Request emulator connection......\n");
        unsigned char _rx, _tx = 'A';
        while(write(fd, &_tx, 1)<=0)  usleep(10);
        while(read(fd, &_rx, 1)<=0)   usleep(10);
        if (_rx=='A')
            fprintf(stderr, "Connection established...\n");
        else
        {
            fprintf(stderr, "Connection failed...\n");
            sc_stop();
        }
    }
    
    ~Epong_vh(void)
    {
    }
};

#endif

