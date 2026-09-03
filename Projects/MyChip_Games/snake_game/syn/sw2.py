import re,subprocess,os
DK='../../../../digital_ETRI050_m2f'
lef=open(os.path.join(DK,'etri050_stdcells.lef')).read()
sz={m.group(1):(float(m.group(2)),float(m.group(3)))
    for m in re.finditer(r'MACRO (\w+).*?SIZE ([\d.]+) BY ([\d.]+)', lef, re.S)}
SRC="../rtl/snake_top.v ../rtl/snake_body.v ../rtl/game_ctrl.v ../rtl/pixel_gen.v ../rtl/font_rom.v ../rtl/pixel_out.v ../rtl/debounce.v ../rtl/lfsr11.v"
ABC="+strash;scorr;ifraig;retime,{D};strash;dch,-f;map,-M,1,{D}"
def run(cs,ml,lw):
    open('t.ys','w').write(f"""read_verilog {SRC}
chparam -set CLK_HZ 25000000 -set CELL_SH {cs} -set MAXLEN {ml} -set LEN_W {lw} -set INIT_LEN 3 snake_top
hierarchy -top snake_top
synth -top snake_top
dfflibmap -liberty {DK}/khu_etri05_stdcells.lib
opt
abc -liberty {DK}/khu_etri05_stdcells.lib -script {ABC}
flatten
setundef -zero
clean -purge
opt
clean
stat
""")
    t=subprocess.run(['yosys','-s','t.ys'],capture_output=True,text=True)
    txt=t.stdout+t.stderr
    if 'Printing statistics' not in txt: return None
    tx=txt[txt.rfind('Printing statistics'):]
    c={m.group(1):int(m.group(2)) for m in re.finditer(r'^[ \t]+([A-Za-z]\w*)[ \t]+(\d+)[ \t]*$',tx,re.M) if m.group(1) in sz}
    return sum(sz[k][0]*sz[k][1]*v for k,v in c.items())/1e6, sum(c.values()), c.get('DFFPOSX1',0)+c.get('DFFSR',0)
print(f"{'grid':>9s} {'MAXLEN':>6s} {'cells':>6s} {'FF':>4s} {'cellA':>7s} {'core':>7s} {'x':>6s}")
for cs,ml,lw in ((2,32,6),(2,24,5),(2,16,5),(3,32,6),(3,16,5)):
    r=run(cs,ml,lw)
    if not r: print(cs,ml,"FAIL"); continue
    a,c,f=r; core=a/0.823
    print(f"{(1<<(7-cs))}x{(1<<(6-cs)):<5d} {ml:6d} {c:6d} {f:4d} {a:7.3f} {core:7.3f} {core/1.032:6.2f}")
