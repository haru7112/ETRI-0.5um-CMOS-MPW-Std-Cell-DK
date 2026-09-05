//=======================================================================
// sc_ssd1306.h
//  SystemC model of the SSD1306 panel, with an SDL2 window.
//
//  Modelled on Projects/SC/glcd128x64 in this design kit, which does the same
//  job for a KS0108 GLCD.  The memory organisation is the same idea - 128
//  columns by 8 pages, each byte a vertical run of 8 pixels - so the renderer
//  is nearly theirs.  What differs is the front end: the KS0108 has a parallel
//  bus, the SSD1306 takes bytes over 4-wire SPI, and it is the D/C# pin rather
//  than an RS pin that says whether a byte is a command or picture.
//
//  Bytes arrive already assembled - see the comment in snake_emu_TB.v for why
//  the bit shifting is left on the Verilog side.
//
//  Only the part of the command set the chip actually uses is implemented,
//  which is the same subset sim/ssd1306_model.v covers:
//      21 c0 c1   column address range, and reset the column pointer
//      22 p0 p1   page address range, and reset the page pointer
//      AF / AE    display on / off
//  Everything else is accepted and ignored, exactly as the real part would
//  for the settings this design leaves at their reset value.
//=======================================================================
#ifndef _SC_SSD1306_H_
#define _SC_SSD1306_H_

#include <systemc.h>
#include <SDL2/SDL.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>

#define SSD1306_W       128
#define SSD1306_H       64
#define SSD1306_PAGES   8
#define EMU_SCALE       6       // window is 768 x 384

SC_MODULE(sc_ssd1306)
{
    // ---- from the chip -------------------------------------------------
    sc_in<bool>           byte_stb;   // toggles once per byte
    sc_in<sc_uint<8> >    byte_val;
    sc_in<bool>           byte_dc;    // 0 = command, 1 = display data
    sc_in<bool>           res_n;
    sc_in<bool>           idle_stb;   // slow strobe, repaint and read keys
    sc_in<bool>           led;

    // ---- back to the chip ----------------------------------------------
    sc_out<sc_uint<5> >   btn_n;      // active low
    sc_out<bool>          quit;

    void Byte_Method(void);           // a byte arrived, or RES# moved
    void Idle_Method(void);           // repaint, and poll the keyboard

    // ---- panel state ---------------------------------------------------
    uint8_t  gMemory[SSD1306_PAGES][SSD1306_W];
    uint32_t col, col_s, col_e;
    uint32_t page, page_s, page_e;
    uint8_t  pending_cmd;
    int      cmd_param;
    bool     disp_on;
    bool     last_stb;
    long     bytes_seen, frames;

    // ---- SDL -----------------------------------------------------------
    SDL_Window   *window;
    SDL_Renderer *renderer;
    SDL_Texture  *texture;
    uint32_t     *pixels;             // 128 x 64, ARGB
    bool          dirty;

    void take_byte(uint8_t b, bool is_data);
    void reset_panel(void);
    void render(void);
    void poll_keys(void);
    void dump_ascii(void);

    // Headless mode.  SNAKE_EMU_ASCII=<n> prints the panel as ASCII art every
    // n frames and opens no window at all, which is how this gets checked on a
    // machine with no display - and how it can be run in a regression.
    bool     headless;
    int      ascii_every;
    long     last_dumped;

    SC_CTOR(sc_ssd1306)
    {
        SC_METHOD(Byte_Method);
        sensitive << byte_stb << res_n;
        dont_initialize();

        SC_METHOD(Idle_Method);
        sensitive << idle_stb;
        dont_initialize();

        reset_panel();
        {
            const char *e = getenv("SNAKE_EMU_ASCII");
            ascii_every = (e && atoi(e) > 0) ? atoi(e) : 0;
            headless    = (ascii_every > 0);
        }
        last_dumped = -1;
        bytes_seen = 0;
        frames     = 0;
        last_stb   = false;
        dirty      = true;

        window   = NULL;
        renderer = NULL;
        texture  = NULL;
        pixels   = new uint32_t[SSD1306_W * SSD1306_H];
        for (int i = 0; i < SSD1306_W * SSD1306_H; i++) pixels[i] = 0xFF000000;

        if (headless) {
            printf("SSD1306 emulator: headless, ASCII every %d frame(s)\n",
                   ascii_every);
            return;
        }
        if (SDL_Init(SDL_INIT_VIDEO) < 0) {
            fprintf(stderr, "SDL init failed: %s\n", SDL_GetError());
            return;
        }
        window = SDL_CreateWindow("SNAKE - SSD1306 128x64",
                                  SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
                                  SSD1306_W * EMU_SCALE, SSD1306_H * EMU_SCALE,
                                  SDL_WINDOW_SHOWN);
        if (!window) {
            fprintf(stderr, "SDL window failed: %s\n", SDL_GetError());
            SDL_Quit();
            return;
        }
        renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
        if (!renderer)
            renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_SOFTWARE);
        texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888,
                                    SDL_TEXTUREACCESS_STREAMING,
                                    SSD1306_W, SSD1306_H);
    }

    ~sc_ssd1306()
    {
        delete [] pixels;
        if (texture)  SDL_DestroyTexture(texture);
        if (renderer) SDL_DestroyRenderer(renderer);
        if (window)   SDL_DestroyWindow(window);
        SDL_Quit();
    }
};

#endif
