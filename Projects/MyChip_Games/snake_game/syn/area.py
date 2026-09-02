import re,subprocess,sys,os
DK='../../../../digital_ETRI050_m2f'
lef=open(os.path.join(DK,'etri050_stdcells.lef')).read()
sz={m.group(1):(float(m.group(2)),float(m.group(3)))
    for m in re.finditer(r'MACRO (\w+).*?SIZE ([\d.]+) BY ([\d.]+)', lef, re.S)}

def run(cell_sh, maxlen, len_w, en_text, top='snake_top'):
    ys = f"""
read_verilog -I../rtl ../rtl/snake_top.v ../rtl/snake_body.v ../rtl/game_ctrl.v \\
             ../rtl/pixel_gen.v ../rtl/font_rom.v ../rtl/oled_ctrl.v \\
             ../rtl/i2c_master.v ../rtl/debounce.v ../rtl/lfsr16.v
chparam -set CELL_SH {cell_sh} -set MAXLEN {maxlen} -set LEN_W {len_w} -set EN_TEXT {en_text} {top}
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

print(f"{'CELL_SH':>7s} {'grid':>8s} {'MAXLEN':>6s} {'TEXT':>4s} {'cells':>6s} {'FF':>5s} "
      f"{'cell mm2':>9s} {'core@60% mm2':>12s} {'frame':>7s}")
for cs,ml,lw in ((1,48,6),(1,32,6),(2,32,6),(2,24,5),(3,24,5),(3,16,5)):
    for et in (1,0):
        a,c,ff,_ = run(cs,ml,lw,et)
        gw,gh = 128>>cs, 64>>cs
        core=a/0.60
        frame = '28pin' if core<=1.0e6 else '84pin' if core<=8.4e6 else 'TOO BIG'
        print(f"{cs:7d} {f'{gw}x{gh}':>8s} {ml:6d} {et:4d} {c:6d} {ff:5d} "
              f"{a/1e6:9.3f} {core/1e6:12.3f} {frame:>7s}")
