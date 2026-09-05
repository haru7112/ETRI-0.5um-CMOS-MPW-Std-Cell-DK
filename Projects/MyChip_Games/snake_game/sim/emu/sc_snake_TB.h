//=======================================================================
// sc_snake_TB.h
//  SystemC testbench top: signals, the panel model, and nothing else.
//  Same shape as sc_ALU8_Mult_TB.h in the design kit's example, except that
//  the clock and the reset are NOT generated here.
//
//  In that example SystemC makes the clock and drives it into Verilog.  This
//  chip runs at 25MHz and needs about a million clocks just to get through
//  the panel power-up, so a VPI round trip per edge is out of the question:
//  the clock is generated in Verilog, and SystemC is woken per SPI byte.
//=======================================================================
#ifndef _SC_SNAKE_TB_H_
#define _SC_SNAKE_TB_H_

#include <systemc.h>
#include "sc_ssd1306.h"

SC_MODULE(sc_snake_TB)
{
    // driven from the Verilog side
    sc_signal<bool>         byte_stb;
    sc_signal<sc_uint<8> >  byte_val;
    sc_signal<bool>         byte_dc;
    sc_signal<bool>         res_n;
    sc_signal<bool>         cs_n;
    sc_signal<bool>         idle_stb;
    sc_signal<bool>         led;

    // read back by the Verilog side
    sc_signal<sc_uint<5> >  btn_n;
    sc_signal<bool>         sc_Stopped;

    sc_ssd1306              *u_panel;

    SC_CTOR(sc_snake_TB)
    {
        btn_n.write(0x1F);          // nothing pressed, switch is active low
        sc_Stopped.write(false);

        u_panel = new sc_ssd1306("u_panel");
        u_panel->byte_stb(byte_stb);
        u_panel->byte_val(byte_val);
        u_panel->byte_dc(byte_dc);
        u_panel->res_n(res_n);
        u_panel->idle_stb(idle_stb);
        u_panel->led(led);
        u_panel->btn_n(btn_n);
        u_panel->quit(sc_Stopped);
    }

    ~sc_snake_TB() { delete u_panel; }
};

#endif
