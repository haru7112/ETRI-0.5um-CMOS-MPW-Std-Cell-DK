import re,subprocess,os
DK='../../../../digital_ETRI050_m2f'
lef=open(os.path.join(DK,'etri050_stdcells.lef')).read()
sz={m.group(1):(float(m.group(2)),float(m.group(3)))
    for m in re.finditer(r'MACRO (\w+).*?SIZE ([\d.]+) BY ([\d.]+)', lef, re.S)}
SRC="../rtl/snake_top.v ../rtl/snake_body.v ../rtl/game_ctrl.v ../rtl/pixel_gen.v ../rtl/font_rom.v ../rtl/oled_ctrl.v ../rtl/spi_master.v ../rtl/debounce.v ../rtl/lfsr11.v"
# the recipe ETRI050/project_vars.sh sets - see area.py
HL  = "synth -top {top} -flatten\nopt -full\ntechmap\nopt -full"
ABC = "+strash;dch,-f;map,-a;mfs;amap"

def run(top, params=""):
    # the project recipe - see area.py
    open('t.ys','w').write(f"""
read_verilog -sv {SRC}
{params}
hierarchy -top {top}
{HL.format(top=top)}
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
                ('game_ctrl','chparam -set GX_W 5 -set GY_W 4 -set POS_W 9 -set FLD_X0 4 -set FLD_X1 31 -set FLD_Y0 0 -set FLD_Y1 15 -set MAXLEN 32 -set LEN_W 6 game_ctrl'),
                ('pixel_gen','chparam -set CELL_SH 2 -set GX_W 5 -set GY_W 4 -set POS_W 9 -set FLD_X0 4 -set FLD_X1 31 -set SCORE_P 3 -set MAXLEN 32 pixel_gen'),
                ('font_rom',''),('oled_ctrl',''),('spi_master',''),
                ('debounce','chparam -set N 5 debounce'),("lfsr11","")):
    a,c,f=run(top,par); tot+=a
    print(f"{top:14s} {c:6d} {f:5d} {a/1e6:9.3f}")
print(f"{'sum of parts':14s} {'':6s} {'':5s} {tot/1e6:9.3f}")
