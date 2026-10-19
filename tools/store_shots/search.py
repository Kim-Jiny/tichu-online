# App Store 검색결과 이미지: 5244x2950(16:9), 3840x2560 / 1920x1280(3:2). 마스코트 + 카드 부채 + 제목.
import sys, os
sys.path.insert(0,'/private/tmp/claude-501/-Users-jiny-Documents-Jiny-godot-tichu/de966dec-3887-41ce-9d7c-648aff6928e5/scratchpad')
from header import *
from PIL import Image, ImageDraw
OUTS='/Users/jiny/Documents/Jiny/godot/tichu/store_shots/search'
os.makedirs(OUTS,exist_ok=True)

def icon(sz):
    im=Image.open('/Users/jiny/Documents/Jiny/godot/tichu/flutter_app/assets_src/appIcon.png').convert('RGBA').resize((sz,sz),Image.LANCZOS)
    m=Image.new('L',(sz,sz),0);ImageDraw.Draw(m).rounded_rectangle([0,0,sz-1,sz-1],radius=int(sz*0.225),fill=255)
    im.putalpha(m)
    fr=Image.new('RGBA',(sz+int(sz*0.05),sz+int(sz*0.05)),(0,0,0,0))
    ImageDraw.Draw(fr).rounded_rectangle([0,0,fr.size[0]-1,fr.size[1]-1],radius=int(sz*0.25),fill=INK)
    fr.alpha_composite(im,(int(sz*0.025),int(sz*0.025)))
    return fr

def search(W,H,lang):
    base=background(W,H);d=ImageDraw.Draw(base);u=H/2950
    t=TXT[lang]
    r32=W/H<1.7
    cxr=(0.775 if r32 else 0.745)*W
    lim=(0.40 if r32 else 0.44)*W
    # 카드 부채(뒤)
    ch=int(H*0.50)
    for nm,ang,dx,dy in [('phoenix.webp',-30,-0.30,0.46),('sk_skull_king.webp',-11,-0.115,0.40),('ll_Princess.webp',11,0.115,0.40),('dragon.webp',30,0.30,0.46)]:
        put(base,card(nm,ch),cxr+dx*H*1.05,H*dy,ang,blur=int(26*u),off=(0,int(26*u)))
    # 마스코트(앞)
    ds=int(H*0.80)
    dr=Image.open(A+'dragon_full.webp').convert('RGBA').resize((ds,ds),Image.LANCZOS)
    put(base,dr,cxr,H*0.66,0,blur=int(26*u),off=(0,int(26*u)))
    # 왼쪽 글
    x0=0.06*W
    ic=icon(int(H*0.20))
    put(base,ic,x0+ic.size[0]/2,H*0.20,0,blur=int(18*u),off=(0,int(16*u)))
    tsz=H*0.155
    title=t['title']
    while d.textlength(title,font=F(tsz))>lim and tsz>40: tsz-=4
    outlined(d,(x0,H*0.46),title,F(tsz),(255,214,70),int(tsz*0.085))
    ty=H*0.46+tsz*0.95
    for i,ln in enumerate(t['tag'].split('\n')):
        sz=tsz*0.34
        while d.textlength(ln,font=F(sz))>lim and sz>20: sz-=2
        outlined(d,(x0,ty+i*sz*1.25),ln,F(sz),(255,255,255),int(sz*0.12))
    cy=ty+2*tsz*0.34*1.25+tsz*0.30
    fs=tsz*0.27;x=x0
    for lab,col in zip(t['chips'],CHIP):
        f=F(fs);tw=d.textlength(lab,font=f);w=int(tw+fs*1.1);h=int(fs*1.6)
        d.rounded_rectangle([x,cy+int(fs*0.12),x+w,cy+h+int(fs*0.12)],radius=int(h*0.3),fill=INK)
        d.rounded_rectangle([x,cy,x+w,cy+h],radius=int(h*0.3),fill=col,outline=INK,width=max(3,int(fs*0.08)))
        d.text((x+w/2,cy+h/2),lab,font=f,fill=(255,255,255),anchor='mm')
        x+=w+fs*0.35
    return base.convert('RGB')

if __name__=='__main__':
    for lang in ['ko','en']:
        a=search(5244,2950,lang);a.save(f'{OUTS}/{lang}_5244x2950.png',optimize=True)
        b=search(3840,2560,lang);b.save(f'{OUTS}/{lang}_3840x2560.png',optimize=True)
        b.resize((1920,1280),Image.LANCZOS).save(f'{OUTS}/{lang}_1920x1280.png',optimize=True)
        print('done',lang)
