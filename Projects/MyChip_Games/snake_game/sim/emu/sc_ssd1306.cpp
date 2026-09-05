//=======================================================================
// sc_ssd1306.cpp
//  Behaviour and rendering for the SSD1306 panel model.  See sc_ssd1306.h.
//=======================================================================
#include "sc_ssd1306.h"

//-----------------------------------------------------------------------
void sc_ssd1306::reset_panel(void)
{
    // Reset defaults, from the datasheet: the whole panel addressable, the
    // pointer at the top left, display off.  This is what lets the chip's
    // init list be as short as it is - it only sends the four settings the
    // reset state gets wrong.
    for (int p = 0; p < SSD1306_PAGES; p++)
        for (int c = 0; c < SSD1306_W; c++)
            gMemory[p][c] = 0x00;

    col  = col_s  = 0;   col_e  = SSD1306_W - 1;
    page = page_s = 0;   page_e = SSD1306_PAGES - 1;
    pending_cmd = 0;
    cmd_param   = 0;
    disp_on     = false;
}

//-----------------------------------------------------------------------
void sc_ssd1306::take_byte(uint8_t b, bool is_data)
{
    if (is_data)
    {
        gMemory[page][col] = b;
        dirty = true;

        // horizontal addressing mode: walk the column, then the page, and
        // wrap back to the start of the window.  The chip relies on this
        // wrap - it is why 1024 data bytes land exactly on a full screen.
        if (col == col_e) {
            col  = col_s;
            page = (page == page_e) ? page_s : page + 1;
            if (page == page_s) frames++;
        } else {
            col++;
        }
        return;
    }

    if (cmd_param != 0)
    {
        cmd_param--;
        if (pending_cmd == 0x21) {              // column address
            if (cmd_param == 1) { col_s = b & 0x7F; col = col_s; }
            else                  col_e = b & 0x7F;
        } else if (pending_cmd == 0x22) {       // page address
            if (cmd_param == 1) { page_s = b & 0x07; page = page_s; }
            else                  page_e = b & 0x07;
        }
        return;
    }

    pending_cmd = b;
    switch (b) {
        case 0x21: case 0x22: cmd_param = 2;    break;
        case 0xAF: disp_on = true;  dirty = true; break;
        case 0xAE: disp_on = false; dirty = true; break;
        default:   break;                       // accepted and ignored
    }
}

//-----------------------------------------------------------------------
void sc_ssd1306::Byte_Method(void)
{
    if (!res_n.read()) {        // the panel clears itself while RES# is low
        reset_panel();
        dirty = true;
        return;
    }

    bool s = byte_stb.read();
    if (s == last_stb) return;  // RES# moved, no new byte
    last_stb = s;

    take_byte((uint8_t)byte_val.read(), byte_dc.read());
    bytes_seen++;
}

//-----------------------------------------------------------------------
void sc_ssd1306::render(void)
{
    if (!renderer || !texture) return;

    for (int y = 0; y < SSD1306_H; y++)
        for (int x = 0; x < SSD1306_W; x++)
        {
            bool on = disp_on &&
                      (gMemory[y >> 3][x] & (1 << (y & 7))) != 0;
            // an OLED is black glass with pale blue pixels
            pixels[y * SSD1306_W + x] = on ? 0xFF9BD8FF : 0xFF101018;
        }

    SDL_UpdateTexture(texture, NULL, pixels, SSD1306_W * sizeof(uint32_t));
    SDL_RenderClear(renderer);
    SDL_RenderCopy(renderer, texture, NULL, NULL);
    SDL_RenderPresent(renderer);
}

//-----------------------------------------------------------------------
void sc_ssd1306::poll_keys(void)
{
    SDL_Event ev;
    sc_uint<5> b = btn_n.read();

    while (SDL_PollEvent(&ev))
    {
        if (ev.type == SDL_QUIT) { quit.write(true); return; }

        if (ev.type == SDL_KEYDOWN || ev.type == SDL_KEYUP)
        {
            bool down = (ev.type == SDL_KEYDOWN);   // switch closes to GND
            int  bit  = -1;
            switch (ev.key.keysym.sym) {
                case SDLK_UP:     bit = 0; break;
                case SDLK_DOWN:   bit = 1; break;
                case SDLK_LEFT:   bit = 2; break;
                case SDLK_RIGHT:  bit = 3; break;
                case SDLK_RETURN:
                case SDLK_SPACE:  bit = 4; break;
                case SDLK_ESCAPE: if (down) { quit.write(true); return; } break;
                default: break;
            }
            if (bit >= 0) b[bit] = down ? 0 : 1;
        }
    }
    btn_n.write(b);
}

//-----------------------------------------------------------------------
//  The same picture the window shows, as text.  128 columns is too wide for
//  a terminal, so two panel pixels share one character cell horizontally.
void sc_ssd1306::dump_ascii(void)
{
    printf("+%.*s+  frame %ld, %ld bytes, display %s\n",
           SSD1306_W / 2, "--------------------------------------------------"
                          "--------------------------------------------------",
           frames, bytes_seen, disp_on ? "ON" : "off");
    for (int y = 0; y < SSD1306_H; y += 2) {
        putchar('|');
        for (int x = 0; x < SSD1306_W; x += 2) {
            int n = 0;
            for (int dy = 0; dy < 2; dy++)
                for (int dx = 0; dx < 2; dx++)
                    if (disp_on && (gMemory[(y+dy) >> 3][x+dx] &
                                    (1 << ((y+dy) & 7)))) n++;
            putchar(n == 0 ? ' ' : n < 3 ? '.' : '#');
        }
        printf("|\n");
    }
    fflush(stdout);
}

//-----------------------------------------------------------------------
void sc_ssd1306::Idle_Method(void)
{
    if (headless) {
        if (frames != last_dumped && frames > 0 &&
            (frames % ascii_every) == 0) {
            last_dumped = frames;
            dump_ascii();
        }
        return;
    }
    poll_keys();
    if (dirty) { render(); dirty = false; }
}
