//----------------------------------------------------------------------------
// snake_params.vh
//  Common parameter/derivation macros for the SNAKE chip.
//
//  Include this file inside a module *after* its parameter declarations so the
//  localparams below derive from the module parameters CELL_SH / MAXLEN.
//
//  Screen is fixed to the SSD1315 128x64 panel:
//      SCR_W = 128, SCR_H = 64, 8 pages of 8 rows.
//
//  CELL_SH selects the game cell size in pixels:
//      CELL_SH = 1 -> 2x2 px cells -> 64 x 32 grid  (default, best looking)
//      CELL_SH = 2 -> 4x4 px cells -> 32 x 16 grid
//      CELL_SH = 3 -> 8x8 px cells -> 16 x  8 grid  (smallest area)
//----------------------------------------------------------------------------
localparam GX_W    = 7 - CELL_SH;            // bits of a cell X coordinate
localparam GY_W    = 6 - CELL_SH;            // bits of a cell Y coordinate
localparam POS_W   = GX_W + GY_W;            // packed {y,x} cell position
localparam GRID_W  = (1 << GX_W);            // cells per row
localparam GRID_H  = (1 << GY_W);            // cells per column
localparam CELL_PX = (1 << CELL_SH);         // pixels per cell edge
localparam CPP     = (8 >> CELL_SH);         // cells stacked inside one page
localparam SUB_W   = (3 - CELL_SH);          // bits selecting the cell in a page

// Page 0 (y = 0..7) is the status bar, the play field owns pages 1..7.
localparam FLD_Y0  = CPP;                    // first field cell row (wall)
localparam FLD_Y1  = GRID_H - 1;             // last  field cell row (wall)
localparam FLD_X0  = 0;                      // left  wall column
localparam FLD_X1  = GRID_W - 1;             // right wall column
