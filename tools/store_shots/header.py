# App Store 헤더(히어로) 이미지: 5244x2950, 3840x1646. 왼쪽 제목·마스코트, 오른쪽 폰 세 대와 카드.
import sys, os, math, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter
S='/private/tmp/claude-501/-Users-jiny-Documents-Jiny-godot-tichu/de966dec-3887-41ce-9d7c-648aff6928e5/scratchpad'
A='/Users/jiny/Documents/Jiny/godot/tichu/flutter_app/assets/'
OUTD='/Users/jiny/Documents/Jiny/godot/tichu/store_shots/header'
os.makedirs(OUTD,exist_ok=True)
INK=(59,42,32); FONT=S+'/fontwork/Jua-Regular.ttf'
def F(sz): return ImageFont.truetype(FONT,int(sz))

def outlined(d,xy,text,font,fill,stroke,anchor='lm'):
    d.text(xy,text,font=font,fill=INK,anchor=anchor,stroke_width=stroke,stroke_fill=INK)
    d.text(xy,text,font=font,fill=fill,anchor=anchor)

def background(W,H):
    im=Image.new('RGB',(W,H));d=ImageDraw.Draw(im)
    c1,c2,c3=(120,190,248),(190,224,252),(255,226,190)
    for x in range(W):   # 가로로 하늘색 → 노을빛
        t=x/(W-1)
        c=tuple(int(c1[i]+(c2[i]-c1[i])*t/0.55) for i in range(3)) if t<0.55 else tuple(int(c2[i]+(c3[i]-c2[i])*(t-0.55)/0.45) for i in range(3))
        d.line([(x,0),(x,H)],fill=c)
    im=im.convert('RGBA')
    ov=Image.new('RGBA',(W,H),(0,0,0,0));od=ImageDraw.Draw(ov)
    gap=int(H*0.085);r=int(gap*0.17)
    for row,y in enumerate(range(-gap,H+gap,gap)):
        for x in range(-gap+(gap//2 if row%2 else 0),W+gap,gap):
            od.ellipse([x-r,y-r,x+r,y+r],fill=(255,255,255,45))
    im=Image.alpha_composite(im,ov)
    # 큰 구름
    cl=Image.new('RGBA',(W,H),(0,0,0,0));cd=ImageDraw.Draw(cl)
    random.seed(7)
    for cx,cy,s in [(0.08,0.92,1.0),(0.30,0.98,1.3),(0.55,1.0,1.1),(0.92,0.9,1.2),(0.75,0.04,0.9),(0.12,0.06,0.7)]:
        for k in range(6):
            rx=int(H*0.12*s*(0.7+random.random()*0.5));ry=int(rx*0.7)
            x=int(cx*W+(k-3)*H*0.07*s);y=int(cy*H+random.randint(-15,15))
            cd.ellipse([x-rx,y-ry,x+rx,y+ry],fill=(255,255,255,190))
    cl=cl.filter(ImageFilter.GaussianBlur(H*0.006))
    return Image.alpha_composite(im,cl)

def phone(shot,width):
    sh=Image.open(shot).convert('RGB');sw,shh=sh.size
    sh=sh.resize((width,int(shh*width/sw)),Image.LANCZOS)
    pad=int(width*0.024);fw,fh=sh.size[0]+pad*2,sh.size[1]+pad*2
    rad=int(width*0.145)
    frame=Image.new('RGBA',(fw,fh),(0,0,0,0))
    m=Image.new('L',(fw,fh),0);ImageDraw.Draw(m).rounded_rectangle([0,0,fw-1,fh-1],radius=rad,fill=255)
    frame.paste(Image.new('RGBA',(fw,fh),INK+(255,)),(0,0),m)
    inner=Image.new('L',(fw,fh),0);ImageDraw.Draw(inner).rounded_rectangle([pad,pad,fw-pad-1,fh-pad-1],radius=rad-pad,fill=255)
    lay=Image.new('RGBA',(fw,fh),(0,0,0,0));lay.paste(sh.convert('RGBA'),(pad,pad))
    frame.paste(lay,(0,0),inner)
    return frame

def shadowed(im,blur,off,alpha=120):
    pad=blur*3
    sh=Image.new('RGBA',(im.size[0]+pad*2,im.size[1]+pad*2),(0,0,0,0))
    a=im.getchannel('A').point(lambda v:alpha if v>0 else 0)
    sh.paste((59,42,32,255),(pad+off[0],pad+off[1]),a)
    sh=sh.filter(ImageFilter.GaussianBlur(blur))
    sh.alpha_composite(im,(pad,pad))
    return sh,pad

def put(base,im,cx,cy,angle=0,blur=18,off=(0,24)):
    if angle: im=im.rotate(angle,expand=True,resample=Image.BICUBIC)
    sh,pad=shadowed(im,blur,off)
    base.alpha_composite(sh,(int(cx-sh.size[0]/2),int(cy-sh.size[1]/2)))

def card(name,h):
    im=Image.open(A+'cards/'+name).convert('RGBA');w=int(im.size[0]*h/im.size[1]);im=im.resize((w,h),Image.LANCZOS)
    m=Image.new('L',im.size,0);ImageDraw.Draw(m).rounded_rectangle([0,0,im.size[0]-1,im.size[1]-1],radius=int(w*0.07),fill=255)
    im.putalpha(m);return im

TXT={
 'ko':{'title':'티츄 온라인','tag':'친구와 함께 즐기는\n카드게임 한 곳에서','chips':['티츄','마이티','스컬킹','러브레터']},
 'en':{'title':'Tichu Online','tag':'Four card games,\nplay together with friends','chips':['Tichu','Mighty','Skull King','Love Letter']},
}
CHIP=[(100,181,246),(92,107,192),(33,69,95),(233,30,99)]

def banner(W,H,lang,shots):
    wide=W/H>2.0
    base=background(W,H)
    d=ImageDraw.Draw(base)
    u=H/2950
    # --- 오른쪽: 카드 부채 + 폰 세 대
    right=0.745*W
    ph_w=int(H*(0.36 if not wide else 0.52))
    fan=[('phoenix.webp',-24,-0.42),('sk_skull_king.webp',-9,-0.24),('dragon.webp',10,0.0+0.0),('ll_Princess.webp',26,0.30)]
    # 카드는 폰 뒤 위쪽에 부채꼴
    ch=int(H*0.50)
    for nm,ang,dx in [('phoenix.webp',-28,-0.30),('sk_skull_king.webp',-10,-0.12),('ll_Princess.webp',10,0.12),('dragon.webp',28,0.30)]:
        put(base,card(nm,ch),right+dx*W*0.42,H*0.20,ang,blur=int(14*u*2),off=(0,int(20*u)))
    left=phone(shots[0],ph_w);cen=phone(shots[1],int(ph_w*1.12));rig=phone(shots[2],ph_w)
    gap=ph_w*0.60
    put(base,left,right-gap*1.5,H*(0.62 if not wide else 0.66),-7,blur=int(30*u),off=(0,int(30*u)))
    put(base,rig,right+gap*1.5,H*(0.62 if not wide else 0.66),7,blur=int(30*u),off=(0,int(30*u)))
    put(base,cen,right,H*(0.60 if not wide else 0.64),0,blur=int(36*u),off=(0,int(34*u)))
    # --- 왼쪽: 제목, 태그, 칩, 마스코트
    x0=0.06*W
    t=TXT[lang]
    tsz=H*(0.150 if not wide else 0.19)
    title=t['title']
    while d.textlength(title,font=F(tsz))>0.36*W and tsz>40: tsz-=4
    outlined(d,(x0,H*0.20),title,F(tsz),(255,214,70),int(tsz*0.085))
    ty=H*0.20+tsz*0.95
    for i,ln in enumerate(t['tag'].split('\n')):
        sz=tsz*0.34
        while d.textlength(ln,font=F(sz))>0.36*W and sz>20: sz-=2
        outlined(d,(x0,ty+i*sz*1.25),ln,F(sz),(255,255,255),int(sz*0.12))
    cy=ty+2*tsz*0.34*1.25+tsz*0.22
    fs=tsz*0.27
    x=x0
    for lab,col in ([] if wide else zip(t['chips'],CHIP)):
        f=F(fs);tw=d.textlength(lab,font=f);w=int(tw+fs*1.1);h=int(fs*1.6)
        d.rounded_rectangle([x,cy+int(fs*0.12),x+w,cy+h+int(fs*0.12)],radius=int(h*0.3),fill=INK)
        d.rounded_rectangle([x,cy,x+w,cy+h],radius=int(h*0.3),fill=col,outline=INK,width=max(3,int(fs*0.08)))
        d.text((x+w/2,cy+h/2),lab,font=f,fill=(255,255,255),anchor='mm')
        x+=w+fs*0.35
        if x>0.46*W: break
    dr=Image.open(A+'dragon_full.webp').convert('RGBA')
    ds=int(H*(0.50 if not wide else 0.46));dr=dr.resize((ds,ds),Image.LANCZOS)
    put(base,dr,x0+ds*0.45 if not wide else 0.30*W,H-ds*0.45,0,blur=int(18*u),off=(0,int(20*u)))
    return base.convert('RGB')

if __name__=='__main__':
    for lang,shotdir in [('ko','shots'),('en','shots_en')]:
        SH='/Users/jiny/Documents/Jiny/godot/tichu/flutter_app/build/'+shotdir+'/'
        shots=[SH+'01_lobby.png',SH+'04_tichu_play.png',SH+'11_sk_play.png']
        for W,H in [(5244,2950),(3840,1646)]:
            out=f'{OUTD}/{lang}_{W}x{H}.png'
            banner(W,H,lang,shots).save(out,optimize=True);print('wrote',out)
