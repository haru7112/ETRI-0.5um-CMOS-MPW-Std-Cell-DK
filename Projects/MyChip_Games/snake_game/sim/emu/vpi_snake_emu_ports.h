//=======================================================================
// vpi_snake_emu_ports.h
//  The two vectors that cross between iverilog and SystemC.
//  Mirrors vpi_ALU8_Mult_tb_ports.h of the design kit's example.
//=======================================================================
#ifndef VPI_SNAKE_EMU_PORTS_H
#define VPI_SNAKE_EMU_PORTS_H

// from the Verilog testbench into SystemC
typedef struct tag_Input
{
    unsigned long   byte_tick;  // toggles once per assembled SPI byte
    unsigned long   idle_tick;  // slow strobe, keeps the window alive
    unsigned long   byte_val;   // the byte
    unsigned long   byte_dc;    // 0 = command, 1 = display data
    unsigned long   res_n;      // panel RES#
    unsigned long   cs_n;       // panel CS#
    unsigned long   led;        // heartbeat LED
} IN_VECTOR;

// from SystemC back into the Verilog testbench
typedef struct tag_Output
{
    unsigned long   btn_n;      // 5-way switch, active low
    unsigned long   end_of_sim; // set when the window is closed
} OUT_VECTOR;

#endif
