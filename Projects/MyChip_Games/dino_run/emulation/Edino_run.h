/**********************************************************************
Filename: Edino_run.h
Purpose : Wrapper for FPGA Emulated dino_run
Author  : goodkook@gmail.com
History : Aug. 2026, First release
***********************************************************************/

#ifndef _Edino_run_H_
#define _Edino_run_H_

#include <systemc.h>

// Includes for accessing Arduino via serial port
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>

SC_MODULE(Edino_run)
{
    sc_in<bool>     clk;
    sc_in<bool>     reset;
    sc_in<bool>     jump;
    sc_in<bool>     game_new;

    sc_out<bool>    v_sync;
    sc_out<bool>    pixel;
    sc_out<bool>    p_tick;
    sc_out<bool>    game_over;

#define N_TX    1
#define N_RX    1

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

    inline void _EMU_IO_(void)
    {
        uint8_t _Rx_, _Tx_, _txPacket_[N_TX], _rxPacket_[N_RX];

        _txPacket_[0] = (uint8_t)(
                        (game_new.read()?   0x01:0x00) |
                        (jump.read()?       0x02:0x00) |
                        (reset.read()?      0x04:0x00) |
                        (clk.read()?        0x08:0x00));

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
    void dino_run_CA_thread(void)
    {
        while(true)
        {
            wait(clk.posedge_event());
            _EMU_IO_();
        }
    }
#else
    void dino_run_method(void)
    {
        _EMU_IO_();
    }
#endif

    // Arduino Serial IF
    int fd;                 // Serial port file descriptor
    struct termios options; // Serial port setting

    sc_trace_file* fp;  // VCD file

    SC_CTOR(Edino_run): clk("clk")
    {
#if defined(CA)
        SC_THREAD(dino_run_CA_thread);
        sensitive << clk;
#else
        SC_METHOD(dino_run_method);
        sensitive << clk << reset << jump << game_new;
#endif
        // WAVE ----------------------------------------------------------
        fp = sc_create_vcd_trace_file("Edino_run");
        fp->set_time_unit(100, SC_PS);  // resolution (trace) ps
        sc_trace(fp, clk,           "clk");
        sc_trace(fp, reset,         "reset");
        sc_trace(fp, jump,          "jump");
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
    
    ~Edino_run(void)
    {
    }
};

#endif

