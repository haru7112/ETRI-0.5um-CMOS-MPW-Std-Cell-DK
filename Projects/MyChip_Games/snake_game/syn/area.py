import re,subprocess,sys,os
DK='../../../../digital_ETRI050_m2f'
lef=open(os.path.join(DK,'etri050_stdcells.lef')).read()
sz={m.group(1):(float(m.group(2)),float(m.group(3)))
    for m in re.finditer(r'MACRO (\w+).*?SIZE ([\d.]+) BY ([\d.]+)', lef, re.S)}

def run(cell_sh, maxlen, len_w, top='snake_top'):
    ys = f"""
read_verilog -I../rtl ../rtl/snake_top.v ../rtl/snake_body.v ../rtl/game_ctrl.v \\
             ../rtl/pixel_gen.v ../rtl/font_rom.v ../rtl/oled_ctrl.v \\
             ../rtl/i2c_master.v ../rtl/debounce.v ../rtl/lfsr11.v
chparam -set CELL_SH {cell_sh} -set MAXLEN {maxlen} -set LEN_W {len_w} {top}
hierarchy -top {top}
synth -top {top} -flatten
dfflibmap -liberty {DK}/khu_etri05_stdcells.lib
abc -liberty {DK}/khu_etri05_stdcells.lib
opt_clean
stat
"""
    open('tmp.ys','w').write(ys)
    out = subprocess.run(['yosys','-s','tmp.ys'],capture_output=True,text=True)
    txt = out.stdout + out.stderr
    counts={}
    for m in re.finditer(r'^[ \t]+([A-Z][A-Z0-9]*)[ \t]+([0-9]+)[ \t]*$', txt, re.M):
        if m.group(1) in sz: counts[m.group(1)]=int(m.group(2))
    area=sum(sz[c][0]*sz[c][1]*n for c,n in counts.items())
    ff=counts.get('DFFPOSX1',0)+counts.get('DFFSR',0)
    return area, sum(counts.values()), ff, counts

# Calibration, both measured from the pong_pt1 2025 tape-out shipped in this
# design kit (see docs/area.md):
#   utilisation    routed DIEAREA vs the sum of the placed cells' LEF SIZE
#   CORE_WINDOW    inside of the 28-pin frame's pin-route ring
UTIL        = 0.823
CORE_WINDOW = 1018.0 * 1018.0          # um2, the MPW_PAD_28pin core budget
BUDGET      = CORE_WINDOW * UTIL       # um2 of standard cells

print(f"28-pin package budget: core {CORE_WINDOW/1e6:.3f} mm2 x {UTIL*100:.1f}% "
      f"= {BUDGET/1e6:.3f} mm2 of cells\n")
print(f"{'CELL_SH':>7s} {'grid':>8s} {'MAXLEN':>6s} {'cells':>6s} {'FF':>5s} "
      f"{'cell mm2':>9s} {'core mm2':>9s} {'vs budget':>10s}")
for cs,ml,lw in ((1,48,6),(1,32,6),(2,32,6),(2,24,5),(2,16,5),(3,24,5),(3,16,5)):
    a,c,ff,_ = run(cs,ml,lw)
    gw,gh = 128>>cs, 64>>cs
    core = a/UTIL
    print(f"{cs:7d} {f'{gw}x{gh}':>8s} {ml:6d} {c:6d} {ff:5d} "
          f"{a/1e6:9.3f} {core/1e6:9.3f} {a/BUDGET:9.2f}x")
