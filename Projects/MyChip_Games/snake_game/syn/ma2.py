import re,subprocess,os
DK='../../../../digital_ETRI050_m2f'
lef=open(os.path.join(DK,'etri050_stdcells.lef')).read()
sz={m.group(1):(float(m.group(2)),float(m.group(3)))
    for m in re.finditer(r'MACRO (\w+).*?SIZE ([\d.]+) BY ([\d.]+)', lef, re.S)}
SRC="../rtl/snake_top.v ../rtl/snake_body.v ../rtl/game_ctrl.v ../rtl/pixel_gen.v ../rtl/font_rom.v ../rtl/pixel_out.v ../rtl/debounce.v ../rtl/lfsr11.v"
ABC="+strash;scorr;ifraig;retime,{D};strash;dch,-f;map,-M,1,{D}"
def run(top,par):
    open('t.ys','w').write(f"""read_verilog {SRC}
{par}
hierarchy -top {top}
synth -top {top}
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
# CELL_SH=2 -> GX_W=5 GY_W=4 POS_W=9 FLD_X0=4 FLD_X1=31 FLD_Y1=15
cfg=[('snake_body','chparam -set POS_W 9 -set GX_W 5 -set MAXLEN 32 -set LEN_W 6 snake_body'),
     ('game_ctrl','chparam -set GX_W 5 -set GY_W 4 -set POS_W 9 -set FLD_X0 4 -set FLD_X1 31 -set FLD_Y0 0 -set FLD_Y1 15 -set MAXLEN 32 -set LEN_W 6 game_ctrl'),
     ('pixel_gen','chparam -set CELL_SH 2 -set GX_W 5 -set GY_W 4 -set POS_W 9 -set FLD_X0 4 -set FLD_X1 31 -set FLD_Y0 0 -set FLD_Y1 15 -set SCORE_P 3 -set MAXLEN 32 pixel_gen'),
     ('font_rom',''),('pixel_out',''),('debounce','chparam -set N 5 debounce'),('lfsr11','')]
tot=0
print(f"{'module':12s} {'cells':>6s} {'FF':>4s} {'mm2':>7s}   (32x16, MAXLEN=32)")
for top,par in cfg:
    r=run(top,par)
    if not r: print(top,"FAIL"); continue
    a,c,f=r; tot+=a
    print(f"{top:12s} {c:6d} {f:4d} {a:7.3f}")
print(f"{'sum':12s} {'':6s} {'':4s} {tot:7.3f}   budget 0.849")
