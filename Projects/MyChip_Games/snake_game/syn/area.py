#!/usr/bin/env python3
"""
Area estimate for the SNAKE chip on the ETRI 0.5um std-cell library.

The synthesis script below is the one qflow 1.4.100 itself writes for the
etri050 target - taken verbatim from the .ys file of pong_pt1, a design that
was actually taped out through this MPW service and whose routed DEF ships in
this design kit.  Running it on that same RTL reproduces the real tape-out to
within +1.2% of cell area, so the numbers printed here are trustworthy.

Do NOT "improve" the script: a plain `synth -flatten` plus a default
`abc -liberty` comes out 16% SMALLER than qflow does and would flatter the
design.  qflow maps for delay (map,-M,1,{D}), flattens after abc and inserts
output buffers, and that is what the fab flow will actually produce.

    python3 area.py             parameter sweep
    python3 area.py --calibrate re-run the pong_pt1 check
"""
import re, subprocess, os, sys

DK  = '../../../../digital_ETRI050_m2f'
LIB = f'{DK}/khu_etri05_stdcells.lib'
RTL = '../rtl'
PONG = '../../../RTL/pong_pt1/pong_pt1'

# ---- calibration facts, measured from pong_pt1_MPW2025_STD-II ---------------
PONG_CELLS   = 1017            # real cells in pong_pt1.def, FILL excluded
PONG_AREA    = 0.5997e6        # um2, from their LEF SIZE
UTIL         = 0.823           # 0.5997 mm2 of cells inside a 864 x 843 um DIEAREA
CORE_WINDOW  = 1018.0 * 1018.0 # um2, inside the 28-pin frame's pin-route ring
BUDGET       = CORE_WINDOW * UTIL

# the exact abc invocation qflow writes for etri050
QFLOW_ABC = "+strash;scorr;ifraig;retime,{D};strash;dch,-f;map,-M,1,{D}"

lef = open(os.path.join(DK, 'etri050_stdcells.lef')).read()
SIZE = {m.group(1): (float(m.group(2)), float(m.group(3)))
        for m in re.finditer(r'MACRO (\w+).*?SIZE ([\d.]+) BY ([\d.]+)', lef, re.S)}


def synth(read, top, chparam=''):
    """Run qflow's own script and return (area_um2, cells, flops)."""
    open('t.ys', 'w').write(f"""{read}
{chparam}
hierarchy -top {top}
synth -top {top}
dfflibmap -liberty {LIB}
opt
abc -liberty {LIB} -script {QFLOW_ABC}
flatten
setundef -zero
clean -purge
iopadmap -outpad BUFX2 A:Y -bits
opt
clean
stat
""")
    out = subprocess.run(['yosys', '-s', 't.ys'], capture_output=True, text=True)
    txt = out.stdout + out.stderr
    if 'Printing statistics' not in txt:
        sys.exit(txt[-2000:])
    txt = txt[txt.rfind('Printing statistics'):]
    cells = {}
    for m in re.finditer(r'^[ \t]+([A-Za-z][A-Za-z0-9_]*)[ \t]+([0-9]+)[ \t]*$', txt, re.M):
        if m.group(1) in SIZE:
            cells[m.group(1)] = int(m.group(2))
    area = sum(SIZE[k][0] * SIZE[k][1] * n for k, n in cells.items())
    ff = cells.get('DFFPOSX1', 0) + cells.get('DFFSR', 0)
    return area, sum(cells.values()), ff


SNAKE = ('read_verilog -sv ' +
         ' '.join(f'{RTL}/{f}.v' for f in ('snake_top', 'snake_body', 'game_ctrl',
                                           'pixel_gen', 'font_rom', 'oled_ctrl',
                                           'i2c_master', 'debounce', 'lfsr11')))


def calibrate():
    a, c, _ = synth(f'read_verilog -sv {PONG}/pong_pt1.v {PONG}/pixel_gen.v', 'pong_pt1')
    print('calibration against the pong_pt1 tape-out in this design kit')
    print(f'  qflow script here : {c:5d} cells  {a/1e6:.4f} mm2')
    print(f'  real tape-out     : {PONG_CELLS:5d} cells  {PONG_AREA/1e6:.4f} mm2')
    print(f'  error             : {c/PONG_CELLS-1:+.1%} cells  {a/PONG_AREA-1:+.1%} area')


def sweep():
    print(f'28-pin package budget: core {CORE_WINDOW/1e6:.3f} mm2 x {UTIL*100:.1f}% '
          f'= {BUDGET/1e6:.3f} mm2 of cells\n')
    print(f"{'CELL_SH':>7s} {'grid':>8s} {'MAXLEN':>6s} {'cells':>6s} {'FF':>5s} "
          f"{'cell mm2':>9s} {'core mm2':>9s} {'vs budget':>10s}")
    for cs, ml, lw in ((1, 48, 6), (1, 32, 6), (2, 32, 6), (2, 24, 5),
                       (2, 16, 5), (3, 24, 5), (3, 16, 5)):
        p = f'chparam -set CELL_SH {cs} -set MAXLEN {ml} -set LEN_W {lw} snake_top'
        a, c, ff = synth(SNAKE, 'snake_top', p)
        gw, gh = 128 >> cs, 64 >> cs
        print(f'{cs:7d} {f"{gw}x{gh}":>8s} {ml:6d} {c:6d} {ff:5d} '
              f'{a/1e6:9.3f} {a/UTIL/1e6:9.3f} {a/BUDGET:9.2f}x')


if __name__ == '__main__':
    if '--calibrate' in sys.argv:
        calibrate()
    else:
        calibrate()
        print()
        sweep()
