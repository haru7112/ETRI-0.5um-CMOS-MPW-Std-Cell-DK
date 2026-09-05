//=======================================================================
// vpi_stub.cpp
//  VPI stub for the SNAKE emulator: registers $snake_emu, picks up the
//  arguments positionally, and wakes SystemC whenever the testbench says
//  something happened.
//
//  Modelled on vpi_stub.cpp of Projects/RTL/ALU8_Mult/ETRI050/simulation.
//  One difference: that example hangs a single callback on one strobe and
//  gates it on the value being high.  Here there are TWO strobes on two
//  Verilog processes - one per SPI byte, one slow one for the keyboard - and
//  both simply toggle, so the callback runs on every change and never has to
//  guess which edge it is on.  A dropped byte event would corrupt the picture.
//=======================================================================
#include <stdio.h>
#include <stdlib.h>
#include <vpi_user.h>

#include "vpi_snake_emu_ports.h"
#include "vpi_snake_emu_exports.h"

// handles onto the Verilog testbench
typedef struct snake_emu
{
    vpiHandle   byte_tick;
    vpiHandle   idle_tick;
    vpiHandle   byte_val;
    vpiHandle   byte_dc;
    vpiHandle   res_n;
    vpiHandle   cs_n;
    vpiHandle   led;
    vpiHandle   btn_n;
    vpiHandle   end_of_sim;
} t_if;

static int snake_emu_tf(char *user_data);
static int sc_sync_callback(p_cb_data cb_data);

static int snake_emu_tf(char * /*user_data*/)
{
    vpiHandle   inst_h, args;
    s_vpi_value value_s;
    s_vpi_time  time_s;
    s_cb_data   cb_data_s;
    t_if        *ip;

    ip = (t_if *)malloc(sizeof(t_if));

    //---------------------------------------------------------------
    // arguments, positional - must match $snake_emu(...) in snake_emu_TB.v
    inst_h = vpi_handle(vpiSysTfCall, 0);
    args   = vpi_iterate(vpiArgument, inst_h);

    ip->byte_tick  = vpi_scan(args);
    ip->idle_tick  = vpi_scan(args);
    ip->byte_val   = vpi_scan(args);
    ip->byte_dc    = vpi_scan(args);
    ip->res_n      = vpi_scan(args);
    ip->cs_n       = vpi_scan(args);
    ip->led        = vpi_scan(args);
    ip->btn_n      = vpi_scan(args);
    ip->end_of_sim = vpi_scan(args);

    vpi_free_object(args);

    //---------------------------------------------------------------
    // one callback, hung on both strobes
    time_s.type    = vpiSimTime;
    value_s.format = vpiIntVal;

    cb_data_s.user_data = (char *)ip;
    cb_data_s.reason    = cbValueChange;
    cb_data_s.cb_rtn    = sc_sync_callback;
    cb_data_s.time      = &time_s;
    cb_data_s.value     = &value_s;

    cb_data_s.obj = ip->byte_tick;
    vpi_register_cb(&cb_data_s);

    cb_data_s.obj = ip->idle_tick;
    vpi_register_cb(&cb_data_s);

    init_sc();

    return 0;
}

static int sc_sync_callback(p_cb_data cb_data)
{
    t_if        *ip;
    s_vpi_value value_s;

    static IN_VECTOR  invector;
    static OUT_VECTOR outvector;

    ip = (t_if *)cb_data->user_data;

    value_s.format = vpiIntVal;

    vpi_get_value(ip->byte_tick, &value_s);
    invector.byte_tick = value_s.value.integer;
    vpi_get_value(ip->idle_tick, &value_s);
    invector.idle_tick = value_s.value.integer;
    vpi_get_value(ip->byte_val, &value_s);
    invector.byte_val = value_s.value.integer;
    vpi_get_value(ip->byte_dc, &value_s);
    invector.byte_dc = value_s.value.integer;
    vpi_get_value(ip->res_n, &value_s);
    invector.res_n = value_s.value.integer;
    vpi_get_value(ip->cs_n, &value_s);
    invector.cs_n = value_s.value.integer;
    vpi_get_value(ip->led, &value_s);
    invector.led = value_s.value.integer;

    //---------------------------------------------------------------
    exec_sc(&invector, &outvector);

    //---------------------------------------------------------------
    // The joystick goes back with no delay.  It is an asynchronous input to
    // the chip and the debouncer synchronises it anyway, so there is nothing
    // to line it up with.
    value_s.value.integer = (int)outvector.btn_n;
    vpi_put_value(ip->btn_n, &value_s, NULL, vpiNoDelay);

    value_s.value.integer = (int)outvector.end_of_sim;
    vpi_put_value(ip->end_of_sim, &value_s, NULL, vpiNoDelay);

    return 0;
}

static void snake_emu_register(void)
{
    s_vpi_systf_data tf_data;

    tf_data.type      = vpiSysTask;
    tf_data.tfname    = (PLI_BYTE8 *)"$snake_emu";
    tf_data.calltf    = snake_emu_tf;
    tf_data.compiletf = 0;
    tf_data.sizetf    = 0;
    tf_data.user_data = 0;
    vpi_register_systf(&tf_data);
}

void (*vlog_startup_routines[])(void) = {
    snake_emu_register,
    0
};
