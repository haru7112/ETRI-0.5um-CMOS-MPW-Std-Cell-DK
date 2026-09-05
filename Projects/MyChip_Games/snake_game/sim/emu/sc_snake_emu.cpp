//=======================================================================
// sc_snake_emu.cpp
//  The five entry points the VPI stub calls.  Mirrors vpi_ALU8_Mult_tb.cpp
//  of the design kit's example.
//=======================================================================
#include <systemc.h>
#include "sc_snake_TB.h"
#include "vpi_snake_emu_ports.h"
#include "vpi_snake_emu_exports.h"

#define SC_TIME_UNIT    SC_NS

sc_snake_TB *u_sc_snake_TB;

// libsystemc expects an sc_main to exist even when the kernel is driven from
// outside, as it is here: iverilog owns main(), and this module is loaded as a
// VPI plugin.  Never called.
int sc_main(int, char *[]) { return 0; }

void init_sc(void)
{
    u_sc_snake_TB = new sc_snake_TB("u_sc_snake_TB");
    sc_start(0, SC_NS);
    cout << "#" << sc_time_stamp() << " SystemC started, SDL window open" << endl;
    cout << "   arrow keys steer, Enter/Space is OK, Esc or closing the "
            "window ends the run" << endl;
}

// Verilog -> SystemC
void sample_hdl(void *In_vector)
{
    IN_VECTOR *p = (IN_VECTOR *)In_vector;
    u_sc_snake_TB->byte_stb.write(p->byte_tick ? true : false);
    u_sc_snake_TB->idle_stb.write(p->idle_tick ? true : false);
    u_sc_snake_TB->byte_val.write(p->byte_val & 0xFF);
    u_sc_snake_TB->byte_dc.write(p->byte_dc ? true : false);
    u_sc_snake_TB->res_n.write(p->res_n ? true : false);
    u_sc_snake_TB->cs_n.write(p->cs_n ? true : false);
    u_sc_snake_TB->led.write(p->led ? true : false);
}

// SystemC -> Verilog
void drive_hdl(void *Out_vector)
{
    OUT_VECTOR *p = (OUT_VECTOR *)Out_vector;
    p->btn_n      = (unsigned long)u_sc_snake_TB->btn_n.read();
    p->end_of_sim = u_sc_snake_TB->sc_Stopped.read() ? 1 : 0;
}

// advance the SystemC kernel far enough for the methods to run
void exec_sc(void *invector, void *outvector)
{
    sample_hdl(invector);
    if (!u_sc_snake_TB->sc_Stopped.read())
        sc_start(1, SC_TIME_UNIT);
    drive_hdl(outvector);
}

void exit_sc(void)
{
    cout << "#" << sc_time_stamp() << " SystemC stopped" << endl;
    sc_stop();
}
