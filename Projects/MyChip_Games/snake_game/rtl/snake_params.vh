//----------------------------------------------------------------------------
// snake_params.vh
//  Common parameter/derivation macros for the SNAKE chip.
//
//  Include this file inside a module *after* its parameter declarations so the
//  localparams below derive from the module parameter CELL_SH.
//
//  Screen is fixed to the SSD1315 128x64 panel:
//      SCR_W = 128, SCR_H = 64, 8 pages of 8 rows.
//
//  CELL_SH selects the game cell size in pixels:
//      CELL_SH = 1 -> 2x2 px cells -> 64 x 32 grid  (default, best looking)
//      CELL_SH = 2 -> 4x4 px cells -> 32 x 16 grid
//      CELL_SH = 3 -> 8x8 px cells -> 16 x  8 grid  (smallest area)
//
//  Screen layout: a 16 pixel score column down the left, then the play field.
//
//      x=0        16                                             127
//       +-----------------------------------------------------------+  y=0
//       |          |                                                |
//       |    42    |                 play field                     |
//       |          |                                                |
//       +-----------------------------------------------------------+  y=63
//        score      ^ vertical divider, which is also the left wall
//
//  The top and bottom rules run the full width; the divider and the right
//  edge close the field.  Hitting any of the four is death.
//----------------------------------------------------------------------------
localparam GX_W    = 7 - CELL_SH;            // bits of a cell X coordinate
localparam GY_W    = 6 - CELL_SH;            // bits of a cell Y coordinate
localparam POS_W   = GX_W + GY_W;            // packed {y,x} cell position
localparam GRID_W  = (1 << GX_W);            // cells per row
localparam GRID_H  = (1 << GY_W);            // cells per column
localparam CELL_PX = (1 << CELL_SH);         // pixels per cell edge
localparam CPP     = (8 >> CELL_SH);         // cells stacked inside one page
localparam SUB_W   = (3 - CELL_SH);          // bits selecting the cell in a page

localparam SCORE_W = (16 >> CELL_SH);        // width of the score column, in cells
localparam SCORE_P = 3;                      // page the two digits sit on

localparam FLD_X0  = SCORE_W;                // divider column, the left wall
localparam FLD_X1  = GRID_W - 1;             // right wall
localparam FLD_Y0  = 0;                      // top rule
localparam FLD_Y1  = GRID_H - 1;             // bottom rule
