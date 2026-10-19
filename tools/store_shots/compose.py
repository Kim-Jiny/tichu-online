# 스토어 설명 이미지 합성: 배경 + 큰 문구 + 폰 틀에 넣은 실제 화면. 1206x2622.
import sys, os, json
from PIL import Image, ImageDraw, ImageFont, ImageFilter
S='/private/tmp/claude-501/-Users-jiny-Documents-Jiny-godot-tichu/de966dec-3887-41ce-9d7c-648aff6928e5/scratchpad'
SHOTS='/Users/jiny/Documents/Jiny/godot/tichu/flutter_app/build/shots'
OUT=sys.argv[1] if len(sys.argv)>1 else '/Users/jiny/Documents/Jiny/godot/tichu/store_shots/ko'
LANG=sys.argv[2] if len(sys.argv)>2 else 'ko'
os.makedirs(OUT,exist_ok=True)
W,H=1206,2622
INK=(59,42,32)
FONT=S+'/fontwork/Jua-Regular.ttf'
dragon=Image.open('/Users/jiny/Documents/Jiny/godot/tichu/flutter_app/assets/dragon_head.webp').convert('RGBA')

def grad(c1,c2,c3=None):
    im=Image.new('RGB',(W,H));d=ImageDraw.Draw(im)
    for y in range(H):
        t=y/(H-1)
        if c3 is None: c=tuple(int(c1[i]+(c2[i]-c1[i])*t) for i in range(3))
        else:
            if t<.5: u=t/.5;c=tuple(int(c1[i]+(c2[i]-c1[i])*u) for i in range(3))
            else: u=(t-.5)/.5;c=tuple(int(c2[i]+(c3[i]-c2[i])*u) for i in range(3))
        d.line([(0,y),(W,y)],fill=c)
    return im

def dots(im,color,alpha=40,gap=130,r=22):
    ov=Image.new('RGBA',im.size,(0,0,0,0));d=ImageDraw.Draw(ov)
    for row,y in enumerate(range(-gap//2,H+gap,gap)):
        for x in range(-gap+(gap//2 if row%2 else 0),W+gap,gap):
            d.ellipse([x-r,y-r,x+r,y+r],fill=color+(alpha,))
    return Image.alpha_composite(im.convert('RGBA'),ov)

def outlined(d,xy,text,font,fill,stroke=14,anchor='mm'):
    d.text(xy,text,font=font,fill=INK,anchor=anchor,stroke_width=stroke,stroke_fill=INK)
    d.text(xy,text,font=font,fill=fill,anchor=anchor)

def phone(shot,width=900):
    sh=Image.open(shot).convert('RGB')
    sw,shh=sh.size
    scale=width/sw
    sh=sh.resize((width,int(shh*scale)),Image.LANCZOS)
    pad=22
    fw,fh=sh.size[0]+pad*2,sh.size[1]+pad*2
    frame=Image.new('RGBA',(fw,fh),(0,0,0,0))
    mask=Image.new('L',(fw,fh),0);ImageDraw.Draw(mask).rounded_rectangle([0,0,fw-1,fh-1],radius=130,fill=255)
    body=Image.new('RGBA',(fw,fh),INK+(255,))
    frame.paste(body,(0,0),mask)
    inner=Image.new('L',(fw,fh),0);ImageDraw.Draw(inner).rounded_rectangle([pad,pad,fw-pad-1,fh-pad-1],radius=108,fill=255)
    layer=Image.new('RGBA',(fw,fh),(0,0,0,0));layer.paste(sh.convert('RGBA'),(pad,pad))
    frame.paste(layer,(0,0),inner)
    return frame

def shadow(im,off=(0,26),blur=30,alpha=110):
    sh=Image.new('RGBA',(im.size[0]+200,im.size[1]+200),(0,0,0,0))
    a=im.getchannel('A').point(lambda v:alpha if v>0 else 0)
    sh.paste((59,42,32,255),(100+off[0],100+off[1]),a)
    return sh.filter(ImageFilter.GaussianBlur(blur))

def make(name,shot,title,sub,bg,accent,dot=(255,255,255),mascot=True,crop_top=0,phone_top=610,flip=False):
    base=dots(grad(*bg),dot).convert('RGBA')
    d=ImageDraw.Draw(base)
    f1=ImageFont.truetype(FONT,128); f2=ImageFont.truetype(FONT,58)
    lines=title.split('\n')
    y=190
    for ln in lines:
        outlined(d,(W//2,y),ln,f1,(255,255,255) if accent is None else accent,stroke=16)
        y+=150
    outlined(d,(W//2,y+30),sub,f2,(255,246,214),stroke=9)
    ph=phone(SHOTS+'/'+shot)
    if crop_top: pass
    px=(W-ph.size[0])//2
    py=phone_top
    sd=shadow(ph)
    base.alpha_composite(sd,(px-100,py-100))
    base.alpha_composite(ph,(px,py))
    if mascot:
        dr=dragon.copy();dr.thumbnail((330,330))
        base.alpha_composite(dr,(W-dr.size[0]-40,phone_top-dr.size[1]+60)) if False else None
    base.convert('RGB').save(f'{OUT}/{name}.png',optimize=True)
    print('wrote',name)

TEXT=json.load(open(S+'/captions_'+LANG+'.json'))
SPEC=[
 ('01_lobby','01_lobby.png',((166,214,250),(222,236,252),(255,236,206)),(255,214,70)),
 ('02_tichu','04_tichu_play.png',((255,196,120),(255,224,170),(255,243,214)),(255,255,255)),
 ('03_skullking','11_sk_play.png',((120,150,214),(176,196,236),(236,226,248)),(255,255,255)),
 ('04_mighty','21_mighty_play.png',((154,140,222),(196,186,240),(238,232,252)),(255,255,255)),
 ('05_loveletter','31_ll_play.png',((248,160,180),(252,196,210),(255,232,238)),(255,255,255)),
 ('06_friends','44_friends.png',((255,210,110),(255,230,160),(255,246,214)),(255,255,255)),
 ('07_shop','40_shop.png',((130,206,170),(190,230,206),(236,248,238)),(255,255,255)),
 ('08_missions','42_missions.png',((255,176,128),(255,208,170),(255,238,214)),(255,255,255)),
]
only=sys.argv[3].split(',') if len(sys.argv)>3 else None
for name,shot,bg,accent in SPEC:
    if only and name not in only: continue
    if not os.path.exists(SHOTS+'/'+shot): print('skip',name);continue
    t=TEXT[name]
    make(name,shot,t['title'],t['sub'],bg,accent)
