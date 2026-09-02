import re,subprocess,os,shutil,tempfile
DK='../../../../digital_ETRI050_m2f'
LIB=f"{DK}/khu_etri05_stdcells.lib"
lef=open(os.path.join(DK,'etri050_stdcells.lef')).read()
sz={m.group(1):(float(m.group(2)),float(m.group(3)))
    for m in re.finditer(r'MACRO (\w+).*?SIZE ([\d.]+) BY ([\d.]+)', lef, re.S)}
FILES=['snake_top.v','snake_body.v','game_ctrl.v','pixel_gen.v','font_rom.v',
       'oled_ctrl.v','i2c_master.v','debounce.v','lfsr11.v']
def measure(top,par,edits):
    d=tempfile.mkdtemp()
    for f in FILES+['snake_params.vh']:
        shutil.copy(f'../rtl/{f}', d)
    for fn,old,new in edits:
        p=os.path.join(d,fn); s=open(p).read()
        assert old in s, f"pattern not found in {fn}: {old[:60]}"
        open(p,'w').write(s.replace(old,new))
    src=' '.join(os.path.join(d,f) for f in FILES)
    open('t.ys','w').write(f"read_verilog -I{d} {src}\n{par}\nhierarchy -top {top}\n"
        f"synth -top {top} -flatten\ndfflibmap -liberty {LIB}\nabc -liberty {LIB}\nopt_clean\nstat\n")
    t=subprocess.run(['yosys','-s','t.ys'],capture_output=True,text=True)
    txt=(t.stdout+t.stderr)
    if 'Printing statistics' not in txt: return None
    txt=txt[txt.rfind('Printing statistics'):]
    c={}
    for m in re.finditer(r'^[ \t]+([A-Za-z][A-Za-z0-9_]*)[ \t]+([0-9]+)[ \t]*$',txt,re.M):
        if m.group(1) in sz: c[m.group(1)]=int(m.group(2))
    shutil.rmtree(d)
    return sum(sz[k][0]*sz[k][1]*v for k,v in c.items())

GP="chparam -set CELL_SH 2 -set MAXLEN 32 -set LEN_W 6 game_ctrl"
OP=""
base_g=measure('game_ctrl',GP,[]); base_o=measure('oled_ctrl',OP,[])
print(f"game_ctrl baseline {base_g/432:6.0f} GE     oled_ctrl baseline {base_o/432:6.0f} GE\n")

ABL_G=[
 ("score BCD 3 digits -> none", [('game_ctrl.v',
    "                            if (score_bcd[3:0] != 4'd9)","                            if (1'b0)")]),
 ("speed table -> fixed 200ms", [('game_ctrl.v',
    "    wire [7:0] speed_ms = 8'd200 - {1'b0, level, 4'b0};    // 200ms .. 88ms",
    "    wire [7:0] speed_ms = 8'd200;")]),
 ("food range check -> always ok", [('game_ctrl.v',
    "    wire food_in_range = (fx_c > FLD_X0[GX_W-1:0]) && (fx_c < FLD_X1[GX_W-1:0]) &&\n"
    "                         (fy_c > FLD_Y0[GY_W-1:0]) && (fy_c < FLD_Y1[GY_W-1:0]);",
    "    wire food_in_range = 1'b1;")]),
 ("next_head adders -> head", [('game_ctrl.v',
    "    wire [POS_W-1:0] next_head = {ny, nx};","    wire [POS_W-1:0] next_head = head[POS_W-1:0];")]),
 ("wall test -> never", [('game_ctrl.v',
    "    wire hit_wall = (nx == FLD_X0[GX_W-1:0]) || (nx == FLD_X1[GX_W-1:0]) ||\n"
    "                    (ny == FLD_Y0[GY_W-1:0]) || (ny == FLD_Y1[GY_W-1:0]);",
    "    wire hit_wall = 1'b0;")]),
]
for name,ed in ABL_G:
    a=measure('game_ctrl',GP,ed)
    print(f"  game_ctrl  -{name:34s} {(base_g-a)/432:6.0f} GE  ({(base_g-a)/1e6:.3f} mm2)")

ABL_O=[
 ("init ROM -> constant", [('oled_ctrl.v',
   "    always @* case (pkt_idx[5:0])","    always @* case (6'd0)")]),
 ("frame window ROM -> constant", [('oled_ctrl.v',
   "    always @* case (pkt_idx[2:0])","    always @* case (3'd0)")]),
 ("pix_x/pix_page regs", [('oled_ctrl.v',
   "                    pix_x    <= pkt_idx[6:0];\n                    pix_page <= pkt_idx[9:7];",
   "                    pix_x    <= 7'd0;\n                    pix_page <= 3'd0;")]),
]
for name,ed in ABL_O:
    a=measure('oled_ctrl',OP,ed)
    print(f"  oled_ctrl  -{name:34s} {(base_o-a)/432:6.0f} GE  ({(base_o-a)/1e6:.3f} mm2)")
