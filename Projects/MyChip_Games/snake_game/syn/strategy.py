import re,subprocess,os
DK='../../../../digital_ETRI050_m2f'
LIB=f"{DK}/khu_etri05_stdcells.lib"
lef=open(os.path.join(DK,'etri050_stdcells.lef')).read()
sz={m.group(1):(float(m.group(2)),float(m.group(3)))
    for m in re.finditer(r'MACRO (\w+).*?SIZE ([\d.]+) BY ([\d.]+)', lef, re.S)}
SRC="../rtl/snake_top.v ../rtl/snake_body.v ../rtl/game_ctrl.v ../rtl/pixel_gen.v ../rtl/font_rom.v ../rtl/oled_ctrl.v ../rtl/i2c_master.v ../rtl/debounce.v ../rtl/lfsr11.v"
PAR="chparam -set CELL_SH 2 -set MAXLEN 32 -set LEN_W 6 -set EN_TEXT 1 snake_top"

AREA_SCRIPT = "+strash;ifraig;scorr;dc2;dretime;strash;dch,-f;map,-a;topo;stime,-c;buffer,-c;upsize,-c;dnsize,-c"

STRATS = {
 "A default (synth -flatten + abc -liberty)":
   f"synth -top snake_top -flatten\ndfflibmap -liberty {LIB}\nabc -liberty {LIB}",
 "B abc area script":
   f"synth -top snake_top -flatten\ndfflibmap -liberty {LIB}\nabc -liberty {LIB} -script {AREA_SCRIPT}",
 "C opt -full + share, abc area":
   f"synth -top snake_top -flatten -run :fine\nopt -full\nshare\nopt -full\nsynth -top snake_top -flatten -run fine:\n"
   f"dfflibmap -liberty {LIB}\nabc -liberty {LIB} -script {AREA_SCRIPT}",
 "D abc -g AND,NAND,OR,NOR,XOR then map area":
   f"synth -top snake_top -flatten\ndfflibmap -liberty {LIB}\nabc -g AND,NAND,OR,NOR,XOR,XNOR,MUX,AOI3,OAI3,AOI4,OAI4\n"
   f"techmap\nabc -liberty {LIB} -script {AREA_SCRIPT}",
}
for name,body in STRATS.items():
    open('t.ys','w').write(f"read_verilog -I../rtl {SRC}\n{PAR}\nhierarchy -top snake_top\n{body}\nopt_clean\nstat\n")
    t=subprocess.run(['yosys','-s','t.ys'],capture_output=True,text=True)
    txt=(t.stdout+t.stderr)
    if 'Printing statistics' not in txt:
        print(f"{name:44s}  FAILED"); continue
    txt=txt[txt.rfind('Printing statistics'):]
    c={}
    for m in re.finditer(r'^[ \t]+([A-Za-z][A-Za-z0-9_]*)[ \t]+([0-9]+)[ \t]*$',txt,re.M):
        if m.group(1) in sz: c[m.group(1)]=int(m.group(2))
    a=sum(sz[k][0]*sz[k][1]*v for k,v in c.items())
    ff=c.get('DFFPOSX1',0)+c.get('DFFSR',0)
    print(f"{name:44s}  cells {sum(c.values()):5d}  FF {ff:4d}  {a/1e6:.3f} mm2  core {a/0.823/1e6:.3f}  {a/0.853e6:.2f}x")
