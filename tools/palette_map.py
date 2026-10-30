#!/usr/bin/env python3
"""AshFall dark-mood palette mapper.
Usage: python3 palette_map.py in.png out.png [--keep-outline] [--dither 0]
       python3 palette_map.py --dir IN_DIR OUT_DIR      (recursive, keeps tree)
Maps every opaque pixel to the nearest colour of the 41-colour ASHFALL palette in CIE Lab,
with a value bias so light/dark order is kept. Near-black pixels -> outline #141B1B.
Ember colours are accents: only reachable with ember=True (flames, lit windows, eyes)."""
import sys,os,numpy as np
from PIL import Image
HEX="""141B1B
2a2a30 3d3c44 54535b 6e6c72 8a878a a6a2a0
c8c0b0 e2dccb
2e3640 435060 5c6c7c 7a8a98
2a3322 3c4a2e 52603a 6c7a48 8a9460
2a2234 3e3048 584462 74607a
32261e 4a3628 664a34 846444 a4845a c0a070
6a2418 9a3420 c8562a e8843a f4b45a fff0c8
7a2a2a
8a6a58 b08a70 d0ac8c""".split()
PALETTE=[tuple(int(h[i:i+2],16) for i in (0,2,4)) for h in HEX]
EMBER=set(range(HEX.index('6a2418'),HEX.index('fff0c8')+1))|{HEX.index('7a2a2a')}
def to_lab(rgb):
    c=rgb/255.0; c=np.where(c>0.04045,((c+0.055)/1.055)**2.4,c/12.92)
    M=np.array([[0.4124,0.3576,0.1805],[0.2126,0.7152,0.0722],[0.0193,0.1192,0.9505]])
    xyz=c@M.T/np.array([0.9505,1.0,1.089]); f=np.where(xyz>0.008856,np.cbrt(xyz),7.787*xyz+16/116)
    return np.stack([116*f[...,1]-16,500*(f[...,0]-f[...,1]),200*(f[...,1]-f[...,2])],-1)
PL=to_lab(np.array(PALETTE,float))
def map_array(a,mute=0.75,darken=0.9,ember=False):
    """a: HxWx4 uint8. mute/darken pre-grade toward dark mood before snapping."""
    out=a.copy(); m=a[:,:,3]>0
    rgb=a[m,:3].astype(float); g=rgb.mean(1,keepdims=True); rgb=(g+(rgb-g)*mute)*darken
    lab=to_lab(rgb); sat=np.hypot(lab[:,1],lab[:,2])
    d=((lab[:,None,:]-PL[None])**2*np.array([1.6,1,1])).sum(2)
    warm=((lab[:,1]>8)&(lab[:,2]>20)&(sat>38)) if ember else np.zeros(len(lab),bool)
    for i in EMBER: d[~warm,i]+=1e6           # embers only for strongly warm source pixels
    idx=d.argmin(1); idx[lab[:,0]<14]=0       # near-black -> outline
    out[m,:3]=np.array(PALETTE,np.uint8)[idx]; out[m,3]=np.where(a[m,3]>0,255,0); return out
def map_image(im,**k): return Image.fromarray(map_array(np.array(im.convert('RGBA')),**k))
def palette_png(path,scale=12):
    im=Image.new('RGB',(len(PALETTE),1)); [im.putpixel((i,0),c) for i,c in enumerate(PALETTE)]
    im.resize((len(PALETTE)*scale,scale),0).save(path)
if __name__=='__main__':
    if sys.argv[1]=='--dir':
        src,dst=sys.argv[2],sys.argv[3]
        for r,_,fs in os.walk(src):
            for f in fs:
                if f.lower().endswith('.png'):
                    o=os.path.join(dst,os.path.relpath(os.path.join(r,f),src)); os.makedirs(os.path.dirname(o),exist_ok=True)
                    map_image(Image.open(os.path.join(r,f))).save(o)
    else: map_image(Image.open(sys.argv[1])).save(sys.argv[2])
