import importlib.util
from PIL import Image, ImageDraw, ImageFont
spec=importlib.util.spec_from_file_location('cut','cut-hires.py'); cut=importlib.util.module_from_spec(spec); spec.loader.exec_module(cut)

PICKS=[('3c57','WX-3C57','P. CHECKWELL','INSPECTOR',1),
       ('7a19','WX-7A19','BOLT K. FIXIT','FLOOR — GENERALIST',1),
       ('9b72','WX-9B72','G. SPARKHAND','HEAVY',1)]
CREAM=(0xF2,0xE8,0xD0); MANILA=(0xE6,0xD2,0xA6); KRAFT=(0xC8,0xB0,0x8A)
GUN=(0x4C,0x51,0x56); MACHINE=(0x2E,0x31,0x34); STEEL=(0x7B,0x80,0x86); STAMPRED=(0xB2,0x22,0x22)
def font(sz,bold=False):
    for p in (['/System/Library/Fonts/Supplemental/Courier New Bold.ttf'] if bold else ['/System/Library/Fonts/Supplemental/Courier New.ttf'])+['/System/Library/Fonts/Supplemental/Arial.ttf']:
        try: return ImageFont.truetype(p,sz)
        except: pass
    return ImageFont.load_default()

# isolate + scale all figures to a common height
FIG_H=420
figs=[]
for folder,pid,name,title,att in PICKS:
    iso=cut.isolate(f'sprites/crew-front/{folder}/attempt1-{att}.png', thr=185)
    s=FIG_H/iso.height
    figs.append((iso.resize((max(1,int(iso.width*s)),FIG_H),Image.LANCZOS),pid,name,title))

W,H=1000,820
img=Image.new('RGB',(W,H),CREAM); d=ImageDraw.Draw(img)
d.rectangle((8,8,W-9,H-9),outline=GUN,width=6)
d.rectangle((20,20,W-21,H-21),outline=KRAFT,width=2)
d.rectangle((20,20,W-21,96),fill=MACHINE)
d.text((40,34),'WERKZ INDUSTRIES',font=font(30,True),fill=CREAM)
d.text((42,70),'PERSONNEL REGISTER — FLOOR CREW',font=font(15),fill=(0xBF,0xB6,0xA0))
stamp=Image.new('RGBA',(180,60),(0,0,0,0)); sd=ImageDraw.Draw(stamp)
sd.rectangle((2,2,177,57),outline=STAMPRED,width=4); sd.text((16,16),'ON FILE',font=font(24,True),fill=STAMPRED)
stamp=stamp.rotate(8,expand=True); img.paste(stamp,(W-230,28),stamp)

# EDGE-BASED even spacing: equal air between figure boxes, centered in the content width
inner_l, inner_r = 40, W-40
avail = inner_r-inner_l
fig_ws=[f[0].width for f in figs]
# inter-figure gaps get MORE air than the end margins (inter = 2 x end) so the
# wide Bolt/Sparkhand clearly read as separate figures.
free = avail - sum(fig_ws)
end = free / 6.0            # 2 ends + 2 inter, inter = 2*end  ->  6*end
inter = 2*end
base_y = H-150
centers=[]
x = inner_l + end
for i,((fig,pid,name,title),fw) in enumerate(zip(figs,fig_ws)):
    cx = int(x + fw/2); centers.append(cx)
    sh=Image.new('RGBA',(fw,40),(0,0,0,0)); ImageDraw.Draw(sh).ellipse((fw*0.1,6,fw*0.9,34),fill=(0,0,0,70))
    img.paste(sh,(int(x),base_y-14),sh)
    img.paste(fig,(int(x),base_y-FIG_H),fig)
    x += fw + inter

# STEEL BEAM floor girder under the lineup, with a riveted WERKZ plate
beam_y = base_y+2; beam_h=34
d.rectangle((28,beam_y,W-29,beam_y+beam_h),fill=STEEL,outline=GUN,width=3)
d.line([(28,beam_y+5),(W-29,beam_y+5)],fill=(0x9A,0x9F,0xA5),width=2)  # top highlight
# rivets along the beam
for rx in range(60,W-40,70):
    d.ellipse((rx-4,beam_y+beam_h//2-4,rx+4,beam_y+beam_h//2+4),fill=(0x3A,0x3E,0x42),outline=(0x9A,0x9F,0xA5))
# central riveted WERKZ plate
pw,ph=150,30; px=W//2-pw//2; py=beam_y+beam_h//2-ph//2
d.rectangle((px,py,px+pw,py+ph),fill=MACHINE,outline=(0x9A,0x9F,0xA5),width=2)
for cxp in (px+8,px+pw-8):
    for cyp in (py+7,py+ph-7): d.ellipse((cxp-3,cyp-3,cxp+3,cyp+3),fill=(0x1A,0x1C,0x1E),outline=STEEL)
tw=d.textlength('WERKZ',font=font(18,True)); d.text((W//2-tw/2,py+5),'WERKZ',font=font(18,True),fill=CREAM)

# nameplates under each figure (kept as-is)
for (fig,pid,name,title),cx in zip(figs,centers):
    pw2=250; px2=cx-pw2//2; py2=beam_y+beam_h+12
    d.rectangle((px2,py2,px2+pw2,py2+52),fill=MANILA,outline=GUN,width=2)
    d.text((px2+10,py2+7),name,font=font(17,True),fill=MACHINE)
    d.text((px2+10,py2+30),f'{pid} · {title}',font=font(11),fill=GUN)

out='sprites/parts-hires/_crew-register.png'
img.save(out); print('saved',out,img.size,'end',round(end),'inter',round(inter))
