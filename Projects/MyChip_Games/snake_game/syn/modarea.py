import re,subprocess,os
DK='../../../../digital_ETRI050_m2f'
lef=open(os.path.join(DK,'etri050_stdcells.lef')).read()
sz={m.group(1):(float(m.group(2)),float(m.group(3)))
    for m in re.finditer(r'MACRO (\w+).*?SIZE ([\d.]+) BY ([\d.]+)', lef, re.S)}
SRC="../rtl/snake_top.v ../rtl/snake_body.v ../rtl/game_ctrl.v ../rtl/pixel_gen.v ../rtl/font_rom.v ../rtl/oled_ctrl.v ../rtl/i2c_master.v ../rtl/debounce.v ../rtl/lfsr11.v"
QFLOW_ABC = "+strash;scorr;ifraig;retime,{D};strash;dch,-f;map,-M,1,{D}"

def run(top, params=""):
    # qflow's own script - see area.py for why the default yosys flow is not used
    open('t.ys','w').write(f"""
read_verilog -sv {SRC}
{params}
hierarchy -top {top}
synth -top {top}
dfflibmap -liberty {DK}/khu_etri05_stdcells.lib
opt
abc -liberty {DK}/khu_etri05_stdcells.lib -script {QFLOW_ABC}
flatten
setundef -zero
clean -purge
opt
clean
stat
""")
    t=subprocess.run(['yosys','-s','t.ys'],capture_output=True,text=True)
    txt=(t.stdout+t.stderr); txt=txt[txt.rfind('Printing statistics'):]
    c={}
    for m in re.finditer(r'^[ \t]+([A-Za-z][A-Za-z0-9_]*)[ \t]+([0-9]+)[ \t]*$',txt,re.M):
        if m.group(1) in sz: c[m.group(1)]=int(m.group(2))
    a=sum(sz[k][0]*sz[k][1]*v for k,v in c.items())
    ff=c.get('DFFPOSX1',0)+c.get('DFFSR',0)
    return a, sum(c.values()), ff
print(f"{'module':14s} {'cells':>6s} {'FF':>5s} {'area mm2':>9s}")
tot=0
for top,par in (('snake_body','chparam -set POS_W 9 -set GX_W 5 -set MAXLEN 32 -set LEN_W 6 snake_body'),
                ('game_ctrl','chparam -set CELL_SH 2 -set MAXLEN 32 -set LEN_W 6 game_ctrl'),
                ('pixel_gen','chparam -set CELL_SH 2 -set MAXLEN 32 pixel_gen'),
                ('font_rom',''),('oled_ctrl',''),('i2c_master',''),
                ('debounce','chparam -set N 5 debounce'),("lfsr11","")):
    a,c,f=run(top,par); tot+=a
    print(f"{top:14s} {c:6d} {f:5d} {a/1e6:9.3f}")
print(f"{'sum of parts':14s} {'':6s} {'':5s} {tot/1e6:9.3f}")
