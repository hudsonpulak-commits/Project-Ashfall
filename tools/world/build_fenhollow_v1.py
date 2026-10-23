"""0.3.13 Fenhollow redesign: a palisaded marsh town built from the designer's Fenhollow v1 set
(art_handoff/towns/fenhollow, read-only; copied to assets/sprites/towns/fenhollow).

Geometry follows the designer's preview.py (74x60, same seeds): a winding creek and marsh pools, one
continuous wooden palisade ring (de-saddled) with straight runs into 4 wooden gates (N back, S front,
E/W side views), 4 watchtowers, natural mud paths (no grid) that become raised boardwalks where they
cross water, and a narrow mud spur from every door. Buildings are tile-snapped; every design gets an
invisible 1-tile collision rim (top/left/right, inset_x/origin_y in town_art.json) so the whole drawn
floor is walk-in and the roof fades. New players start at Kell's lodge by the S gate.

Writes:
  assets/sprites/towns/fenhollow/{tiles,buildings,props,rows}/ + ground_decal.png
  data/town_art.json (merged), data/towns/fenhollow.json, data/churches.json (fenhollow),
  data/town_npcs.json (fenhollow), data/sprites.json + data/objects.json (fh_* props)
  build/fenhollow_layout_check.png
Exits 1 on overlap, unreachable door/stand/prop/gate, a ring gap (ring_qa) or a ring leak.
"""
import json, math, os, random, shutil, sys, collections
from collections import deque
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SRC = '/workspace/art_handoff/towns/fenhollow'
DST = os.path.join(REPO, 'assets/sprites/towns/fenhollow')
RES = 'res://assets/sprites/towns/fenhollow'
T = 16
S = 1.6   # 0.3.14 v2: the designer grew the map 1.6x for the bigger buildings
GW, GH = int(74 * S), int(60 * S)
SW, SH = GW * T, GH * T
ORIGIN = [-GW // 2, -GH // 2]
CXt, CYt, RX, RY = int(37 * S), int(30 * S), 29 * S, 23 * S
def _s(q): return (q[0] * S, q[1] * S)

# ---------------------------------------------------------------- copy art (never write into art_handoff)
# 0.3.14 sprite bot's v2 set (min 5x5, walk-in floors, *_night window layers) overlays v1;
# the boardwalk blob47 sheet + masks come from the v1 tiles dir (boardwalk fix)
SRC2 = os.path.join(SRC, 'v2')
for sub in ('tiles', 'buildings', 'props'):
    os.makedirs(os.path.join(DST, sub), exist_ok=True)
    if sub == 'buildings':
        for f in os.listdir(os.path.join(DST, sub)):
            if f.endswith('.png') or f.endswith('.png.import'): os.remove(os.path.join(DST, sub, f))
    for root in ((SRC2,) if sub == 'buildings' else (SRC, SRC2)):
        for f in sorted(os.listdir(os.path.join(root, sub))):
            if f.endswith('.png') or f.endswith('_masks.json'): shutil.copyfile(os.path.join(root, sub, f), os.path.join(DST, sub, f))
shutil.copyfile(os.path.join(SRC2, 'manifest.json'), os.path.join(DST, 'manifest_designer.json'))
shutil.copyfile(os.path.join(SRC, 'README.md'), os.path.join(DST, 'README_designer.md'))
M = json.load(open(os.path.join(SRC2, 'manifest.json')))
BLOB = json.load(open(os.path.join(SRC, 'manifest.json')))['boardwalk_blob47']
BM = {b['name']: b for b in M['buildings']}; GM = M['palisade']['gates']
_LC = {}
def L(sub, n):
    n = n if n.endswith('.png') else n + '.png'
    if (sub, n) not in _LC: _LC[(sub, n)] = Image.open(os.path.join(DST, sub, n)).convert('RGBA')
    return _LC[(sub, n)]
sys.path.insert(0, os.path.join(SRC, 'src'))
import diagtiles as dg

# ---------------------------------------------------------------- per-design plans: walk-in floor + invisible rim
# The designer draws thin outline walls at the very edge of each footprint, so the whole drawn floor (all rows
# but the facade) is walkable; collision walls sit one tile outside on the top/left/right (the rim) and the
# facade row is wall except the door. canvas = (at.x*16 + inset_x, at.y*16 - origin_y).
def plan_of(b):
    n = b['name']; E = b['footprint_origin_px'][1]; W, H = b['tiles']; d = tuple(b['door_tile']); H = d[1] + 1   # rows below the door (fh_house_03 porch) are decor, not floor
    f = np.array(L('buildings', n + '_floor'))[..., 3] > 0
    S = {(x, y) for y in range(H) for x in range(W) if f[E + y * T:E + y * T + T, x * T:x * T + T].sum() >= 160} | {d}
    rows = ['#' * (W + 2)]
    for y in range(H):
        r = '#'
        for x in range(W):
            if (x, y) == d: r += 'D'
            elif y == H - 1: r += '#'
            elif (x, y) in S: r += 'o'
            else: r += '#'
        rows.append(r + '#')
    return rows
def plan_of_v2(b):
    # 0.3.14 v2 art: walls sit on the footprint edge; walkable = the designer's clear area + door lane + door
    E = b['footprint_origin_px'][1]; W, H = b['tiles']; d = tuple(b['door_tile']); H = d[1] + 1
    def inr(r, cx, cy): return r[0] <= cx < r[0] + r[2] and r[1] <= cy < r[1] + r[3]
    rows = []
    for y in range(H):
        r = ''
        for x in range(W):
            cx, cy = x * T + 8, E + y * T + 8
            if (x, y) == d: r += 'D'
            elif y < H - 1 and (inr(b['clear_area_px'], cx, cy) or inr(b['door_lane_px'], cx, cy)): r += 'o'
            else: r += '#'
        rows.append(r)
    return rows
V2 = 'clear_area_px' in M['buildings'][0]; RIM = 0 if V2 else 1
ART = {}
for b in M['buildings']:
    lay = b['layers']
    ART[b['name']] = dict(tiles=[b['tiles'][0], b['door_tile'][1] + 1], px=b['px'], origin_y=b['footprint_origin_px'][1] - (0 if V2 else T), inset_x=(0 if V2 else T), door_tile=b['door_tile'], storeys=b['storeys'],
                          floor=f"{RES}/buildings/{lay[0][:-4] if lay[0].endswith('.png') else lay[0]}.png".replace('.png.png', '.png'),
                          walls=f"{RES}/buildings/{lay[1][:-4] if lay[1].endswith('.png') else lay[1]}.png".replace('.png.png', '.png'),
                          fade=[f"{RES}/buildings/{l}".replace('.png.png', '.png') if l.endswith('.png') else f"{RES}/buildings/{l}.png" for l in b['fade_group']],
                          night=(f"{RES}/buildings/{b['night_layer']}" if b.get('night_layer') else ''), plan=(plan_of_v2(b) if V2 else plan_of(b)), note='0.3.13 Fenhollow v1: plan has a 1-tile invisible collision rim (top/left/right)')
def flip_plan(rows): return [r[::-1] for r in rows]
def LB(l): return L('buildings', l[:-4] if l.endswith('.png') else l)

# ---------------------------------------------------------------- terrain (designer preview.py geometry, same seeds)
rnd = random.Random(5); nr = np.random.RandomState(5)
VY, VX = np.mgrid[:GH + 1, :GW + 1].astype(float)
nz = ndi.gaussian_filter(nr.rand(GH + 1, GW + 1), 3.2); nz = (nz - nz.min()) / (nz.max() - nz.min())
ang = np.degrees(np.arctan2((VY - CYt) / RY, (VX - CXt) / RX)) % 360
wob = 1 + .035 * np.sin(np.radians(ang) * 4 + .7) + .02 * np.sin(np.radians(ang) * 9)
def ell(rx, ry): return np.hypot((VX - CXt) / rx, (VY - CYt) / ry) / wob <= 1
inside = ell(RX - 1, RY - 1)
creek = dg.line_mask(VY.shape, [_s(q) for q in [(0, 22), (10, 25), (19, 21), (28, 26), (38, 24), (47, 29), (56, 26), (64, 31), (74, 28)]], 1.6 * S)
WAT = (nz < .30) | creek | (~ell(RX + 3, RY + 3) & (nz < .55))
WAT &= ~(ell(RX + 2.2, RY + 2.2) & ~ell(RX - 2.2, RY - 2.2))
WAT[(np.abs(VX - CXt) < 4) & (VY > CYt + RY - 3)] = False; WAT[(np.abs(VX - CXt) < 4) & (VY < CYt - RY + 3)] = False
# 0.3.14 organic outer shore: no water within a noisy 2.5-6.5 tile band of the rect edge, so the
# marsh-bank autotile (grass/mud/shallows) makes a wobbly shoreline inside the town instead of
# straight decal water meeting world grass at the rect boundary
EDG = np.minimum(np.minimum(VX, GW - VX), np.minimum(VY, GH - VY))
_n2 = ndi.gaussian_filter(np.random.RandomState(11).rand(GH + 1, GW + 1), 1.6); _n2 = (_n2 - _n2.min()) / (_n2.max() - _n2.min())
WAT &= ~(EDG < 2.5 + 4 * _n2)
LV = ~WAT
CR = np.array([[0, 1, 0], [1, 1, 1], [0, 1, 0]], bool)
_E = ell(RX, RY); _B = _E & ~ndi.binary_erosion(_E, CR); PV = _B | (ndi.binary_dilation(_B, CR) & ~_E); GATE = []
def desaddle(V):
    for _ in range(6):
        F = dg.frames_of(V); bad = (F == 5) | (F == 10)
        if not bad.any(): break
        for y, x in zip(*np.nonzero(bad)): V[y:y + 2, x:x + 2] = True
    return V
GATE_TILES = {}; GATE_LINE = {}; ROOF_TILES = {}; SIDE = {270: 'north', 90: 'south', 0: 'east', 180: 'west'}
for g, view in [(270, 'back'), (90, 'front'), (0, 'side'), (180, 'side')]:
    side = SIDE[g]
    if view == 'side':
        c = int(round(CXt + math.cos(math.radians(g)) * RX)); c = c - 1 if g == 0 else c; cy = CYt + (-3 if g == 0 else 4)
        PV[cy - 6:cy + 7, c - 3:c + 5] = False; PV[cy - 6:cy + 7, c:c + 2] = True; PV[cy - 1:cy + 2, c - 1:c + 3] = False
        GATE.append(('fh_gate_side', int((c + .5) * 16) - 24, cy * 16 - 57, g, cy))
        GATE_TILES[side] = [[x, y] for x in (c - 1, c, c + 1) for y in (cy - 1, cy)]
        GATE_LINE[side] = [[c, cy - 1], [c, cy]]
        ROOF_TILES[side] = [[x, y] for x in range(c - 1, c + 2) for y in (cy - 1, cy)]
    else:
        r = int(round(CYt + math.sin(math.radians(g)) * RY)); r = r - 1 if g == 90 else r; cx = CXt
        PV[r - 3:r + 5, cx - 6:cx + 7] = False; PV[r:r + 2, cx - 6:cx + 7] = True; PV[r - 1:r + 3, cx - 1:cx + 2] = False
        GATE.append((f'fh_gate_{view}', cx * 16 - 32, int((r + .5) * 16) - 16, g, r))
        GATE_TILES[side] = [[x, y] for x in (cx - 1, cx) for y in (r - 1, r, r + 1)]
        GATE_LINE[side] = [[cx - 1, r], [cx, r]]
        ROOF_TILES[side] = [[x, y] for x in (cx - 1, cx) for y in range(r - 1, r + 3)]
LV |= ndi.binary_dilation(PV, iterations=2)
G = {g: (x0, y0) for n, x0, y0, g, _ in GATE}
gw = ((G[180][0] - 8) / 16, (G[180][1] + 57) / 16); ge = ((G[0][0] + 56) / 16, (G[0][1] + 57) / 16)
gn = ((G[270][0] + 32) / 16, G[270][1] / 16); gs = ((G[90][0] + 32) / 16, (G[90][1] + 72) / 16)
# 0.3.13 the 4 gate roads run on to the town edge (the world roads join there)
_M = lambda l: [_s(q) for q in l]
PATHS = [[(CXt, GH + 1), gs, (CXt, CYt + RY + 5)] + _M([(36.5, 48), (39, 41), (35, 35), (37, 30)]),
         [(CXt, -1), gn, (CXt, 4 * S)] + _M([(36, 12), (39, 19), (36, 25), (37, 30)]),
         [(-1, gw[1]), gw, (3 * S, gw[1]), (13 * S, gw[1] + S)] + _M([(20, 36), (29, 33), (37, 30)]),
         [(GW + 1, ge[1]), ge, (GW - 3 * S, ge[1]), (62 * S, ge[1] - .5 * S)] + _M([(55, 26), (46, 31), (37, 30)]),
         _M([(36.5, 48), (27, 46), (19, 41), (15, 34)]), _M([(39, 41), (48, 44), (56, 41), (61, 36)]), _M([(36, 12), (28, 13), (19, 17)]), _M([(39, 19), (49, 15), (57, 18)]),
         _M([(37, 30), (31, 28), (24, 27), (15, 26)])]
MV = np.zeros_like(LV)
for i, p in enumerate(PATHS): MV |= dg.line_mask(VY.shape, p, 1.0 if i < 4 else .8)
MV |= ((VX - 37 * S) / (4.5 * S)) ** 2 + ((VY - 30 * S) / (3.2 * S)) ** 2 <= 1
for n, x0, y0, g, _ in GATE:
    if 'side' in n: MV |= dg.line_mask(VY.shape, [((x0 - 8) / 16, (y0 + 57) / 16), ((x0 + 56) / 16, (y0 + 57) / 16)], 1.0)
    else: MV |= dg.line_mask(VY.shape, [((x0 + 32) / 16, (y0) / 16), ((x0 + 32) / 16, (y0 + 72) / 16)], .9)
PV &= ~MV
for n, x0, y0, g, c_ in GATE:
    if 'side' in n: cc = (x0 + 24) // 16; PV[c_ - 6:c_ - 1, cc:cc + 2] = True; PV[c_ + 2:c_ + 7, cc:cc + 2] = True
    else: cx_ = (x0 + 32) // 16; PV[c_:c_ + 2, cx_ - 6:cx_ - 1] = True; PV[c_:c_ + 2, cx_ + 2:cx_ + 7] = True
ring0 = _B | (ndi.binary_dilation(_B, CR) & ~_E)
for n, x0, y0, g, c_ in GATE:
    if 'side' not in n: continue
    cc = (x0 + 24) // 16
    for ye, sgn in ((c_ - 6, -1), (c_ + 6, 1)):
        ry, rx = np.nonzero(ring0 & ((VY - ye) * sgn >= 1) & (np.abs(VX - cc) < 8)); i = np.argmin((rx - cc) ** 2 + (ry - ye) ** 2)
        PV |= ndi.binary_dilation(dg.line_mask(VY.shape, [(cc + .5, ye), (rx[i] + .5 * (rx[i] < cc) - .0, ry[i])], .5), CR)
PV &= ~MV
PV = desaddle(PV)
fr = lambda V: dg.frames_of(V)
landT = fr(LV) == 15; pathT = fr(MV) > 0
BWt = pathT & ~landT
BWt = ndi.binary_dilation(BWt, CR) & pathT & ~(fr(LV) == 15) | BWt
for (x0, y0, dx, dy, n) in [(int(a * S), int(b * S), c, d, e) for a, b, c, d, e in [(9, 25, 0, 1, 4), (52, 27, 0, 1, 3), (28, 27, 0, 1, 3), (46, 58, 0, -1, 4), (64, 8, 0, 1, 3)]]:   # fishing jetties
    for k in range(n):
        yy, xx = y0 + dy * k, x0 + dx * k
        if 0 <= yy < GH and 0 <= xx < GW and not landT[yy, xx]: BWt[yy, xx] = True
MVl = MV & LV
bits = np.vectorize(lambda f: bin(int(f)).count('1'))
CNT_L = bits(fr(LV)); CNT_P = bits(fr(PV))

# ---------------------------------------------------------------- base ground (water, marsh bank, main mud paths, boardwalk)
def strip(n): return np.array(L('tiles', n))
WD, WS = strip('fh_water_deep_4f'), strip('fh_water_shallow_4f'); dT = ndi.distance_transform_edt(~landT)
BW_FILLED = []
def render_ground(U):
    base = np.zeros((SH, SW, 4), np.uint8)
    for y in range(GH):
        for x in range(GW): base[y * 16:y * 16 + 16, x * 16:x * 16 + 16] = (WD if dT[y, x] > 2.5 else WS)[:, (x + y) % 4 * 16:(x + y) % 4 * 16 + 16]
    img = Image.fromarray(base); cover = {}
    for n, V in [('fh_diag_marsh_bank', LV), ('fh_diag_mud_path', U)]:
        F = dg.frames_of(V); A = strip(n); lay = np.zeros((SH, SW, 4), np.uint8)
        for y in range(GH):
            for x in range(GW):
                if F[y, x] and not (n == 'fh_diag_mud_path' and BWt[y, x] and F[y, x] != 15): lay[y * 16:y * 16 + 16, x * 16:x * 16 + 16] = A[:, F[y, x] * 16:F[y, x] * 16 + 16]
        cover[n] = lay[..., 3] > 0; img.alpha_composite(Image.fromarray(lay))
    BW_FILLED.clear()
    # 0.3.14 blob47 boardwalk (8-neighbour mask N1 NE2 E4 SE8 S16 SW32 W64 NW128, diagonals only with
    # both edge neighbours); replaces the 16-frame autotile + the old code corner patch
    BA = strip('fh_boardwalk_blob47'); bwpx = np.zeros((SH, SW), bool); FOM = BLOB['frame_of_mask']
    def on(yy, xx, edge):
        if not (0 <= yy < GH and 0 <= xx < GW): return False
        return bool(BWt[yy, xx]) or (edge and bool(pathT[yy, xx] and landT[yy, xx]))
    for y in range(GH):
        for x in range(GW):
            if BWt[y, x]:
                n_, e_, s_, w_ = on(y - 1, x, 1), on(y, x + 1, 1), on(y + 1, x, 1), on(y, x - 1, 1)
                m = n_ * 1 | e_ * 4 | s_ * 16 | w_ * 64
                if n_ and e_ and on(y - 1, x + 1, 0): m |= 2
                if s_ and e_ and on(y + 1, x + 1, 0): m |= 8
                if s_ and w_ and on(y + 1, x - 1, 0): m |= 32
                if n_ and w_ and on(y - 1, x - 1, 0): m |= 128
                k = FOM[str(m)]; fa = BA[:, k * 16:k * 16 + 16]
                f = Image.fromarray(fa); img.alpha_composite(f, (x * 16, y * 16)) if y * 16 + 20 <= SH else img.alpha_composite(f.crop((0, 0, 16, SH - y * 16)), (x * 16, y * 16))
                bwpx[y * 16:min(SH, y * 16 + 20), x * 16:x * 16 + 16] |= np.array(f)[:min(20, SH - y * 16), :, 3] > 0
    return img, cover['fh_diag_marsh_bank'], cover['fh_diag_mud_path'], bwpx
img0, landpx, pathpx, bwpx = render_ground(MVl)
print('boardwalk tiles', int(BWt.sum()), 'corner joins filled', len(BW_FILLED), 'sample', sorted(set(BW_FILLED))[:0] + sorted(set(BW_FILLED))[::25])
waterpx = ~landpx & ~bwpx

# ---------------------------------------------------------------- palisade rows, watchtowers, gates
PA = L('tiles', 'fh_diag_palisade'); PF = dg.frames_of(PV); wallpx = np.zeros((SH + 30, SW), bool)
for n, x0, y0, g, _ in GATE:
    w_, h_ = GM[n]['size_px']
    for y in range(GH):
        for x in range(GW):
            if x * 16 >= x0 and x * 16 + 16 <= x0 + w_ and y * 16 >= y0 and y * 16 + 16 <= y0 + h_ - 8: PF[y, x] = 0
YSORT = []; FADES = []
os.makedirs(os.path.join(DST, 'rows'), exist_ok=True)
for f_ in os.listdir(os.path.join(DST, 'rows')): os.remove(os.path.join(DST, 'rows', f_))
for y in range(GH):
    if not PF[y].any(): continue
    xs_ = np.nonzero(PF[y])[0]
    # one sprite per contiguous run so the y-sort stays local
    runs = []; s0 = xs_[0]; pv = xs_[0]
    for x in list(xs_[1:]) + [None]:
        if x is None or x != pv + 1: runs.append((s0, pv + 1)); s0 = x
        if x is not None: pv = x
    for k, (xa, xb) in enumerate(runs):
        row = Image.new('RGBA', ((xb - xa) * T, 30))
        for x in range(xa, xb): row.alpha_composite(PA.crop((PF[y, x] * 16, 0, PF[y, x] * 16 + 16, 30)), ((x - xa) * T, 0))
        nm = f'pal_row_{y:02d}_{k}.png'; row.save(os.path.join(DST, 'rows', nm))
        YSORT.append(dict(path=f'{RES}/rows/{nm}', pos=[int(xa * T), int(y * T)], base=T))
        wallpx[y * T:y * T + 30, xa * T:xb * T] |= np.array(row)[..., 3] > 0
wallpx = wallpx[:SH]
TOW = []; TOW_T = []
wy_, wx_ = np.nonzero(PF == 15)
for a_ in (40, 140, 220, 320):
    x = CXt + RX * math.cos(math.radians(a_)); y = CYt + RY * math.sin(math.radians(a_)); i = np.argmin((wx_ - x) ** 2 + (wy_ - y) ** 2)
    TOW.append((int(wx_[i] * 16 + 8 - 24), int(wy_[i] * 16 + 18 - 80))); TOW_T.append((int(wx_[i]), int(wy_[i])))
for x, y in TOW:
    YSORT.append(dict(path=f'{RES}/tiles/fh_palisade_watchtower.png', pos=[x, y], base=80))
    wallpx[max(0, y):y + 80, x:x + 48] |= np.array(L('tiles', 'fh_palisade_watchtower'))[max(0, -y):, :, 3] > 0
for n, x0, y0, g, _ in GATE:
    w_, h_ = GM[n]['size_px']
    YSORT.append(dict(path=f'{RES}/tiles/{n}_walls.png', pos=[x0, y0], base=h_))
    FADES.append(dict(path=f'{RES}/tiles/{n}_roof.png', pos=[x0, y0], tiles=ROOF_TILES[SIDE[g]]))
    wallpx[y0:y0 + h_, x0:x0 + w_] |= np.array(L('tiles', n + '_walls'))[..., 3] > 0

# wall tiles: >= 2 palisade corners; gate passages open; towers block; the diagonal rule (no corner slip-throughs)
wall_t = CNT_P >= 2
GSET = {tuple(p) for v in GATE_TILES.values() for p in v}
for n, x0, y0, g, _ in GATE:   # the gate's side towers / pillars block (all sprite tiles except the passage)
    w_, h_ = GM[n]['size_px']
    for ty in range(max(0, (y0 + 8) // T), (y0 + h_) // T):
        for tx in range(x0 // T, (x0 + w_ + T - 1) // T):
            if (tx, ty) not in GSET and 0 <= ty < GH and 0 <= tx < GW:
                # only the band of the wall line (the sprite's front ground stays walkable)
                if 'side' in n or abs(ty - _) <= 1: wall_t[ty, tx] = True
for p in GSET: wall_t[p[1], p[0]] = False
for (tx, ty) in TOW_T: wall_t[ty, tx] = True
blk = lambda x, y: wall_t[y, x]
for _ in range(3):
    for y in range(GH - 1):
        for x in range(GW - 1):
            for (p1, p2, o1, o2) in (((x, y), (x + 1, y + 1), (x + 1, y), (x, y + 1)), ((x + 1, y), (x, y + 1), (x, y), (x + 1, y + 1))):
                if blk(*p1) and blk(*p2) and not blk(*o1) and not blk(*o2):
                    cand = [o for o in (o1, o2) if o not in GSET]
                    if not cand: continue
                    o = max(cand, key=lambda q: (CNT_P[q[1], q[0]], -abs(q[0] - CXt) - abs(q[1] - CYt)))
                    wall_t[o[1], o[0]] = True

# ---------------------------------------------------------------- tile grid
grid = [['g'] * GW for _ in range(GH)]
CNT_M = bits(fr(MVl))
for y in range(GH):
    for x in range(GW):
        if wall_t[y, x]: grid[y][x] = '#'
        elif BWt[y, x]: grid[y][x] = '='
        elif CNT_L[y, x] < 3: grid[y][x] = '~'
        elif CNT_M[y, x] >= 3: grid[y][x] = ':'
for p in GSET: grid[p[1]][p[0]] = ':'
GATES = dict(north=[[36, 0], [37, 0], [38, 0]], south=[[36, GH - 1], [37, GH - 1], [38, GH - 1]],
             west=[[0, int(gw[1]) - 1], [0, int(gw[1])], [0, int(gw[1]) + 1]], east=[[GW - 1, int(ge[1]) - 1], [GW - 1, int(ge[1])], [GW - 1, int(ge[1]) + 1]])
for v in GATES.values():
    for (x, y) in v:
        if grid[y][x] not in ':=': grid[y][x] = '='
INNER_T = (inside[:-1, :-1] & inside[1:, 1:] & inside[:-1, 1:] & inside[1:, :-1])
insidepx = np.kron(ell(RX - 1.6, RY - 1.6)[:-1, :-1], np.ones((16, 16), bool)).astype(bool)

# ---------------------------------------------------------------- building placement (tile-snapped)
occ = pathpx | waterpx | bwpx | ndi.binary_dilation(wallpx, iterations=2)   # 0.3.14 v2: art may meet the mud edge
for n, x0, y0, g, _ in GATE: w_, h_ = GM[n]['size_px']; occ[max(0, y0 - 4):y0 + h_ + 4, max(0, x0 - 20):x0 + w_ + 20] = True
for x, y in TOW: occ[max(0, y):y + 80, max(0, x):x + 48] = True
tile_used = np.array([[grid[y][x] in '~=#' for x in range(GW)] for y in range(GH)])
reserved = set(); RIM_T = set(); INNER_B = set()
blds = []
def drawn(n, flip):
    b = BM[n]; im = Image.new('RGBA', tuple(b['px']))
    for l in b['layers']: im.alpha_composite(LB(l))
    if flip: im = im.transpose(Image.FLIP_LEFT_RIGHT)
    return np.array(im)[..., 3] > 0
def plan_tiles(n, flip):
    rows = ART[n]['plan']; rows = flip_plan(rows) if flip else rows
    return rows, [(x, y) for y, r in enumerate(rows) for x, c in enumerate(r) if c != '.']
def door_local(rows):
    for y, r in enumerate(rows):
        if 'D' in r: return (r.index('D'), y)
def spur_route(fx, fy, extra_block=()):
    """BFS over dry, free tiles from the door front to the nearest main path tile; returns the tile route or None."""
    if not (0 <= fx < GW and 0 <= fy < GH): return None
    eb = set(extra_block); prev = {(fx, fy): None}; dq = deque([(fx, fy)])
    while dq:
        c = dq.popleft()
        if grid[c[1]][c[0]] in ':=' and c != (fx, fy) or grid[c[1]][c[0]] == ':' and len(prev) > 0 and prev[c] is None and False:
            r = []; k = c
            while k: r.append(k); k = prev[k]
            return r[::-1]
        if grid[c[1]][c[0]] == ':' :
            r = []; k = c
            while k: r.append(k); k = prev[k]
            return r[::-1]
        for dx, dy in ((0, 1), (1, 0), (-1, 0), (0, -1)):
            q = (c[0] + dx, c[1] + dy)
            if 0 <= q[0] < GW and 0 <= q[1] < GH and q not in prev and q not in eb and not tile_used[q[1], q[0]] and grid[q[1]][q[0]] in 'g:':
                prev[q] = c; dq.append(q)
    return None
def place(n, tx, ty, flip=False, role=None, reach=80, quiet=False):
    al = drawn(n, flip); h, w = al.shape; E = BM[n]['footprint_origin_px'][1]
    rows, tiles = plan_tiles(n, flip); dl = door_local(rows); PWt, PHt = len(rows[0]), len(rows)
    rimloc = {(x, y) for (x, y) in tiles if y == 0 or x == 0 or x == PWt - 1}
    for r in range(0, reach, 2):
        for t in range(0, 360, 15 if r else 360):
            px = tx * T + r * math.cos(math.radians(t)) - w / 2; py = ty * T + r * math.sin(math.radians(t)) - h / 2
            ox, oy = int(round(px / T)) - RIM, int(round((py + E) / T)) - RIM
            x0, y0 = (ox + RIM) * T, (oy + RIM) * T - E
            if ox < 1 or oy < 1 or ox + PWt > GW - 1 or oy + PHt > GH - 4 or y0 < 0 or x0 + w > SW: continue
            if (occ[y0:y0 + h, x0:x0 + w] & al).any(): continue
            if not insidepx[y0:y0 + h, x0:x0 + w][al].all(): continue
            bad = False
            for (lx, ly) in tiles:
                q = (ox + lx, oy + ly)
                if tile_used[q[1], q[0]] or q in reserved or grid[q[1]][q[0]] != 'g' or not INNER_T[q[1], q[0]]: bad = True; break
            if bad: continue
            dx_, dy_ = ox + dl[0], oy + dl[1]
            front = [(dx_, dy_ + k) for k in (1, 2, 3)]
            if tile_used[front[0][1], front[0][0]] or grid[front[0][1]][front[0][0]] not in 'g:' or grid[front[1][1]][front[1][0]] not in 'g:=' or (role == 'church' and grid[front[2][1]][front[2][0]] not in 'g:='): continue
            for (lx, ly) in tiles: tile_used[oy + ly, ox + lx] = True
            route = spur_route(dx_, dy_ + 1)
            if route is None:
                for (lx, ly) in tiles: tile_used[oy + ly, ox + lx] = False
                continue
            occ[y0:y0 + h, x0:x0 + w] |= al
            for (lx, ly) in tiles: reserved.add((ox + lx, oy + ly))   # the invisible rim already spaces neighbours
            for q in route: reserved.add(q)
            d = dict(art=n, flip=flip, at=[ox, oy], role=role, px=[x0, y0], rows=rows, door=[dx_, dy_], route=route)
            blds.append(d); return d
    if not quiet: print('no room for', n, role)
    return None
def remove_reserved_route(d):
    pass
CIVIC = [('fh_church', (37, 14), 'church', False), ('fh_kell_lodge', (30, 46), 'kell', False), ('fh_guard_post', (44, 47), 'guard', False),
         ('fh_bank', (44, 24), 'bank', False), ('fh_general_store', (29, 23), 'general', False), ('fh_kell_lodge', (52, 36), 'smithy', True),
         ('fh_cookhouse', (24, 36), 'cook', False), ('fh_player_shop', (46, 38), 'player', False),
         ('fh_smithy', (55, 20), 'helmets', False), ('fh_house_12', (20, 20), 'archery', False)]
left = []
LAYOUT = json.load(open(os.path.join(SRC2, 'layout', 'layout.json')))['buildings']
_LP = {}
for lb in LAYOUT: _LP.setdefault(lb['name'], []).append(((lb['x'] + lb['w'] / 2) / T, (lb['y'] + lb['h'] / 2) / T))
for n, p, role, flip in CIVIC:
    p = _LP[n].pop(0) if _LP.get(n) else _s(p)
    if not place(n, *p, flip=flip, role=role, reach=900): left.append((n, role))
HOUSES = [h for h in M['houses'] if h != 'fh_house_12'] + ['fh_house_12']
rr = random.Random(7)
mud_d = ndi.distance_transform_edt(~(pathpx | bwpx))
cands = [(x, y) for y in range(8, GH - 6, 2) for x in range(6, GW - 6, 2) if INNER_T[y, x] and landT[y, x]]
rr.shuffle(cands); cands.sort(key=lambda c: mud_d[c[1] * 16, c[0] * 16])
use = collections.Counter(); nh = 0
# 0.3.14 first every house at (or next to) its slot in the designer's v2 layout, then the free-search passes
for n in list(HOUSES):
    for lp in _LP.get(n, []):
        if place(n, lp[0], lp[1], role='home', reach=64, quiet=True): use[n] += 1; nh += 1
for rnd_pass in range(2):
    for n in HOUSES:
        if rnd_pass and use[n] >= 2 or not rnd_pass and use[n]: continue
        for c in cands:
            if place(n, c[0], c[1], flip=(use[n] % 2 == 1), role='home', reach=48, quiet=True):
                use[n] += 1; nh += 1; break
        else:
            if not rnd_pass: left.append((n, 'home'))
print('houses', nh, 'designs used', len(set(b['art'] for b in blds)), 'not placed', left)

# ---------------------------------------------------------------- doorway spurs (drawn as mud; designer gap: no spur tiles)
SPUR = np.zeros_like(LV)
for b in blds:
    route = b['route']; dx_, dy_ = b['door']
    pts = [(dx_ + .5, dy_ + .3), (dx_ + .5, dy_ + 1.5)] + [(c[0] + .5 + rnd.uniform(-.2, .2), c[1] + .5 + rnd.uniform(-.2, .2)) for c in route[1:-1]] + [(route[-1][0] + .5, route[-1][1] + .5)]
    SPUR |= dg.line_mask(VY.shape, pts, .62)
    for q in route:
        if grid[q[1]][q[0]] == 'g': grid[q[1]][q[0]] = ':'
SPUR &= LV
U = MVl | SPUR
# 0.3.14 mud landings where a boardwalk meets land: a ragged mud apron (posts placed later)
LANDINGS = []
for y in range(1, GH - 1):
    for x in range(1, GW - 1):
        if BWt[y, x]:
            for a_, b_ in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = (x + a_, y + b_)
                if landT[q[1], q[0]] and not BWt[q[1], q[0]]: LANDINGS.append((q, (a_, b_)))
_rl = np.random.RandomState(13)
for (qx, qy), _d in LANDINGS:
    r = 1.3 + _rl.rand() * .9
    U |= (((VX - qx - .5 - _d[0] * .8) / (r + .4 * _rl.rand())) ** 2 + ((VY - qy - .5 - _d[1] * .8) / (r + .4 * _rl.rand())) ** 2 <= 1) & LV
print('mud landings', len(LANDINGS))
BT = set()
for b in blds:
    for y, r in enumerate(b['rows']):
        for x, c in enumerate(r):
            if c != '.': BT.add((b['at'][0] + x, b['at'][1] + y))
for _ in range(4):
    F = dg.frames_of(U); bad = ((F == 5) | (F == 10)) & ~BWt
    if not bad.any(): break
    for y, x in zip(*np.nonzero(bad)): U[y:y + 2, x:x + 2] = True
U &= LV
img, landpx, pathpx, bwpx = render_ground(U)
for n, x0, y0, g, _ in GATE: img.alpha_composite(L('tiles', n + '_floor'), (x0, y0))
waterpx = ~landpx & ~bwpx
# land/mud/water fade over the last 2 tiles of every edge into the world terrain
dec = np.array(img)
# 0.3.14 grass thins into mud near the palisade: dithered mud-fill clumps, densest at the wall
_rp = np.random.RandomState(17)
_pal = ndi.distance_transform_edt(~np.kron(PV[:GH, :GW], np.ones((T, T), bool)))
_cl = ndi.gaussian_filter(_rp.rand(SH, SW), 3.0); _cl = (_cl - _cl.min()) / (_cl.max() - _cl.min())
_mf = np.array(L('tiles', 'fh_mud_fill').convert('RGBA'))[:16, :16]; _mft = np.tile(_mf, (GH, GW, 1))
_mud = landpx & ~pathpx & ~bwpx & (_cl > .35 + .5 * np.clip(_pal / (4.5 * T), 0, 1)) & (_mft[..., 3] > 0)
dec[_mud] = _mft[_mud]
# organic edge: binary, noise-dithered fade (pixel clumps, no straight runs) over the last 1-4.5 tiles
ex = np.minimum(np.arange(SW), SW - 1 - np.arange(SW))[None, :] / T
ey = np.minimum(np.arange(SH), SH - 1 - np.arange(SH))[:, None] / T
_ed = np.minimum(ex, ey)
_c1 = ndi.gaussian_filter(_rp.rand(SH, SW), 7.0); _c1 = (_c1 - _c1.min()) / (_c1.max() - _c1.min())
_c2 = _rp.rand(SH, SW)
_keep = _ed > (.6 + 3.2 * _c1 + .9 * (_c2 - .5))
dec[..., 3] = np.where(_keep, dec[..., 3], 0).astype(np.uint8)
Image.fromarray(dec).save(os.path.join(DST, 'ground_decal.png'))
CNT_U = bits(fr(U))
for y in range(GH):
    for x in range(GW):
        if grid[y][x] == 'g' and CNT_U[y, x] >= 3 and (x, y) not in BT: grid[y][x] = ':'

# ---------------------------------------------------------------- roles -> buildings
sys.path.insert(0, os.path.dirname(__file__))
import itertools
def interior(b):
    ox, oy = b['at']
    return sorted([(ox + x, oy + y) for y, r in enumerate(b['rows']) for x, c in enumerate(r) if c == 'o'], key=lambda p: (p[1], p[0]))
def solve(inn, door, n_items, prefer=None):
    inn = list(inn); ad = (door[0], door[1] - 1)
    stands = ([ad] if ad in inn else []) + [p for p in inn if p != ad and abs(p[0] - door[0]) + abs(p[1] - door[1]) == 1]
    rest_all = sorted(inn, key=prefer or (lambda p: (p[1], abs(p[0] - door[0]))))
    for st in stands:
        rest = [p for p in rest_all if p != st]
        for combo in itertools.combinations(rest, n_items):
            free = set(inn) - set(combo); seen = {tuple(door)}; q = [tuple(door)]
            while q:
                c = q.pop()
                for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nn = (c[0] + d[0], c[1] + d[1])
                    if nn in free and nn not in seen: seen.add(nn); q.append(nn)
            if st in seen and all(any((p[0] + a, p[1] + c) in seen for a, c in ((1, 0), (-1, 0), (0, 1), (0, -1))) for p in combo):
                return st, list(combo), seen
    return None
def rel(p): return [int(p[0]), int(p[1])]
def sign_tile(b):
    dx, dy = b['door']
    for sx in (dx + 1, dx - 1):
        lx = sx - b['at'][0]
        if 0 <= lx < len(b['rows'][0]) and b['rows'][dy - b['at'][1]][lx] == '#': return [sx, dy]
    return [dx, dy]
OLD = {b['id']: b for b in json.load(open('/tmp/fh/fenhollow_old.json'))['buildings']} if os.path.exists('/tmp/fh/fenhollow_old.json') else \
      {b['id']: b for b in json.load(open(os.path.join(REPO, 'data/towns/fenhollow.json'))).get('buildings', [])}
_ck = json.load(open(os.path.join(REPO, 'data/churches.json'))); OLD_CH = _ck['towns'].get('fenhollow', {})
KEEP_OLD = ('id', 'kind', 'shop', 'name', 'keeper', 'keeper_sprite', 'sign_sprite', 'greet', 'roof', 'style')
def from_old(bid, **kw):
    o = OLD.get(bid, {}); d = {k: o[k] for k in KEEP_OLD if k in o}; d['id'] = bid; d.update(kw); return d
HOMES = [("The Reedwells' house", 'Edda Reedwell'), ("Old Mossby's", 'Hob Mossby'), ("Eel Cottage", 'Tilda Fenn'), ("The Sedges' house", 'Caro Sedge'),
         ("Withy House", 'Aldo Withy'), ("Bulrush Cottage", 'Nell Marsh'), ("The Peats' house", 'Ivo Peat'), ("Heron's Rest", 'Wenna Heron'),
         ("Mudlark House", 'Pim Lark'), ("The Alders' house", 'Bran Alder'), ("Creekside", 'Oda Creel'), ("Stiltwalk House", 'Garr Stilt'),
         ("The Rushes' house", 'Mab Rush'), ("Willow End", 'Tam Willow'), ("Frogmore", 'Lise Frogg'), ("Bog Cottage", 'Ned Boggart'),
         ("The Wades' house", 'Sorrel Wade'), ("Lantern House", 'Joss Wick'), ("Fenside", 'Ula Fenwick'), ("Punt House", 'Rolf Punter'),
         ("The Carrs' house", 'Effie Carr'), ("Snipe Cottage", 'Dob Snipe'), ("Netter's house", 'Hal Netter'), ("Mere View", 'Ysolde Mere')]
out_b = []; church = None; hi = 0; kell_b = None
for b in blds:
    role = b['role']; inn = interior(b); door = tuple(b['door']); ad = (door[0], door[1] - 1)
    base = dict(art=b['art'], flip=b['flip'], at=b['at'], door=[list(door)], sign=sign_tile(b), props=[], counter=[], style='timber', roof='#9a8a5a')
    note = '0.3.13 Fenhollow v1 (designer %s%s)' % (b['art'], ', flipped' if b['flip'] else '')
    if role == 'church':
        st, it, _ = solve(inn, door, 2, prefer=lambda p: (p[1], abs(p[0] - door[0])))
        alt, pri = it
        base.update(id='fenhollow_church', kind='church', name=OLD_CH.get('name', 'Fenhollow Church'), keeper=OLD_CH.get('keeper', 'Father Aldric'),
                    altar=rel(alt), keeper_at=rel(pri), stand=rel(st), note=note)
        used = {alt, pri, st}
        for p in inn:
            if len(base['props']) >= 6: break
            if p in used or p[0] == door[0] or p[1] <= st[1] - 3 and False: continue
            trial = solve([q for q in inn], door, 0)
            # keep every item reachable after adding a pew
            cand = [q for q in it] + [tuple(x['at']) for x in base['props']] + [p]
            free = set(inn) - set(cand); seen = {door}; q_ = [door]
            while q_:
                c = q_.pop()
                for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nn = (c[0] + d[0], c[1] + d[1])
                    if nn in free and nn not in seen: seen.add(nn); q_.append(nn)
            if st in seen and all(any((z[0] + a, z[1] + c) in seen for a, c in ((1, 0), (-1, 0), (0, 1), (0, -1))) for z in cand):
                base['props'].append(dict(object='pew' if p[1] > alt[1] else 'candle_stand', at=rel(p)))
        church = base; continue
    need = {'bank': 3, 'smithy': 3, 'cook': 2}.get(role, 1)
    sol = solve(inn, door, need) if inn else None
    if role in ('home', 'kell', 'guard') or sol is None:
        if role not in ('home', 'kell', 'guard'): print('ROLE FAIL', role, b['art']); sys.exit(1)
    if role == 'bank':
        st, (k, c1, c2), _ = sol
        base.update(from_old('fenhollow_bank', keeper_at=rel(k), stand=rel(st), style='stone', roof='#5a6070', note=note))
        base['props'] = [dict(object='bank_chest', at=rel(c1)), dict(object='bank_chest', at=rel(c2))]
    elif role == 'smithy':
        st, (k, f1, a1), _ = sol
        base.update(from_old('fenhollow_swords', keeper_at=rel(k), stand=rel(st), note=note + '; the forge hall: fh_smithy is too small for keeper + furnace + anvil'))
        base['props'] = [dict(object='furnace', at=rel(f1)), dict(object='anvil', at=rel(a1))]
    elif role == 'cook':
        st, (k, o1), _ = sol
        base.update(from_old('fenhollow_cook', keeper_at=rel(k), stand=rel(st), note=note))
        base['props'] = [dict(object='oven', at=rel(o1))]
    elif role in ('general', 'player', 'helmets', 'archery'):
        st, (k,), _ = sol
        bid = {'general': 'fenhollow_general', 'player': 'fenhollow_player', 'helmets': 'fenhollow_helmets', 'archery': 'fenhollow_archery'}[role]
        base.update(from_old(bid, keeper_at=rel(k), stand=rel(st), note=note))
        if 'roof' in OLD.get(bid, {}): base['roof'] = OLD[bid]['roof']
    else:
        nm, kp = HOMES[hi % len(HOMES)]; hi += 1
        if role == 'kell': nm, kp = "Kell's Lodge", 'Kell'
        if role == 'guard': nm, kp = 'Guard Post', 'Sergeant Rook'
        bid = {'kell': 'fenhollow_kell_lodge', 'guard': 'fenhollow_guard_post'}.get(role, 'fenhollow_home_%d' % hi)
        base.update(id=bid, kind='house', shop='', name=nm, keeper=kp, keeper_sprite='villager', sign_sprite='sign_house', note=note)
        if role == 'kell':
            # Kell himself stands outside at the lodge door (the quest giver); the lodge is open and empty
            base.update(no_keeper=True, keeper_at=rel(door), stand=rel(door)); kell_b = base
        elif sol and role == 'home' and len(inn) >= 3:
            st, (k,), _ = sol; base.update(keeper_at=rel(k), stand=rel(st))
        else:
            base.update(no_keeper=True, keeper_at=rel(door), stand=rel(door))
        if role == 'guard': base['keeper_sprite'] = 'villager'
    out_b.append(base)
assert church and kell_b, 'church / Kell lodge missing'

# ---------------------------------------------------------------- objects and props
objs = {}
for b in out_b + [church]:
    for pr in b['props']: objs[tuple(pr['at'])] = pr['object']
def door_zone(x, y):
    for b in blds:
        dx, dy = b['door']
        if abs(x - dx) <= 1 and dy <= y <= dy + 3: return True
    return False
def free_tile(x, y, allow_path=False, on_bw=False, water=False):
    if not (1 <= x < GW - 1 and 1 <= y < GH - 1) or (x, y) in objs or (x, y) in BT: return False
    c = grid[y][x]
    if water: ok = c == '~'
    elif on_bw: ok = c == '='
    else: ok = c in ('g:' if allow_path else 'g')
    if not ok or door_zone(x, y): return False
    for v in list(GATE_TILES.values()) + list(GATES.values()):
        for p in v:
            if abs(x - p[0]) <= 2 and abs(y - p[1]) <= 2: return False
    for b in blds:
        if (x, y) in b['route']: return False
    return True
def addo(name, x, y, **kw):
    if free_tile(x, y, **kw): objs[(x, y)] = name; return True
    return False
# Kell at his lodge door, the spawn beside him
kdx, kdy = kell_b['door'][0]
KELL = None
for (ax, ay) in [(1, 1), (-1, 1), (1, 2), (-1, 2), (2, 1), (-2, 1)]:
    q = (kdx + ax, kdy + ay)
    if q not in BT and grid[q[1]][q[0]] in 'g:' and q not in objs:
        objs[q] = 'quest_giver'; KELL = q; break
assert KELL, 'no tile for Kell'
# village green: exchange board, workbench, training dummy (the old plaza kit)
GREEN = (int(37 * S), int(30 * S))
for nm in ['exchange_board', 'workbench', 'training_dummy']:
    done = False
    for r_ in range(3, 10):
        for dx, dy in ((1, -2), (-1, -2), (2, 1), (-2, 1), (1, 2), (-1, 2), (3, 0), (-3, 0)):
            if addo(nm, GREEN[0] + dx * r_ // 3, GREEN[1] + dy, allow_path=True): done = True; break
        if done: break
MARKET = [list(p) for p, v in objs.items() if v in ('exchange_board', 'workbench', 'training_dummy')]
# gatherables the old town had: reed beds, ash/oak trees; fishing spots in the pools
rn = random.Random(13)
bank_t = [(x, y) for y in range(2, GH - 2) for x in range(2, GW - 2) if grid[y][x] == 'g' and INNER_T[y, x] and any(grid[y + b][x + a] == '~' for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
rn.shuffle(bank_t)
nreed = sum(1 for p in bank_t[:40] if sum(1 for v in objs.values() if v == 'reed_bed') < 5 and addo('reed_bed', *p))
fs = 0
for y in range(4, GH - 4):
    for x in range(4, GW - 4):
        if fs < 4 and INNER_T[y, x] and grid[y][x] == '~' and sum(grid[y + b][x + a] == '~' for a in (-1, 0, 1) for b in (-1, 0, 1)) >= 6 and \
           any(grid[y + b][x + a] in '=' for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1))) and all(abs(x - p[0]) + abs(y - p[1]) > 8 for p, v in objs.items() if v == 'fishing_spot') \
           and addo('fishing_spot', x, y, water=True): fs += 1
dry_in = [(x, y) for y in range(2, GH - 2) for x in range(2, GW - 2) if grid[y][x] == 'g' and INNER_T[y, x]]
rn.shuffle(dry_in); nt = 0
for p in dry_in:
    if nt >= 6: break
    if mud_d[p[1] * 16 + 8, p[0] * 16 + 8] > 24 and all((p[0] + a, p[1] + b) not in objs for a in (-1, 0, 1) for b in (-1, 0, 1)) and addo('ash_tree' if nt < 5 else 'alder_tree', *p): nt += 1
# lots of props (designer set): reeds on the banks, fish traps / stilts / rowboats in the water, clutter on boardwalks and by paths
PROPS_W = ['fh_fish_trap', 'fh_stilts', 'fh_fish_trap', 'fh_rowboat']
PROPS_BANK = ['fh_reeds_a', 'fh_reeds_b', 'fh_reeds_c', 'fh_reeds_a', 'fh_reeds_c']
PROPS_PATH = ['fh_lantern_pole', 'fh_barrel', 'fh_crates', 'fh_drying_rack', 'fh_cart', 'fh_barrel', 'fh_drying_rack', 'fh_crates', 'fh_rope_coil']
PROPS_BW = ['fh_rope_coil', 'fh_barrel', 'fh_crates', 'fh_lantern_pole']
cnt = collections.Counter()
for k in range(5000):
    x, y = rn.randrange(2, GW - 2), rn.randrange(2, GH - 2); c = grid[y][x]
    near_w = any(grid[y + b][x + a] == '~' for a in (-1, 0, 1) for b in (-1, 0, 1))
    near_p = any(grid[y + b][x + a] in ':=' for a in (-2, -1, 0, 1, 2) for b in (-2, -1, 0, 1, 2))
    if any(objs.get((x + a, y + b)) for a in (-1, 0, 1) for b in (-1, 0, 1)) and rn.random() < .7: continue
    if c == '~' and rn.random() < .05 and any(grid[y + b][x + a] in 'g=' for a in (-2, 0, 2) for b in (-2, 0, 2)):
        nm = rn.choice(PROPS_W)
        if nm == 'fh_rowboat' and cnt[nm] >= 6: continue
        if addo(nm, x, y, water=True): cnt[nm] += 1
    elif c == 'g' and near_w and rn.random() < .5:
        nm = rn.choice(PROPS_BANK)
        if addo(nm, x, y): cnt[nm] += 1
    elif c == '=' and rn.random() < .04 and not any(grid[y + b][x + a] in ':' for a in (-1, 0, 1) for b in (-1, 0, 1)):
        # boardwalk clutter only on wide spots so the walk stays open
        if sum(grid[y + b][x + a] == '=' for a in (-1, 0, 1) for b in (-1, 0, 1)) >= 6:
            nm = rn.choice(PROPS_BW)
            if addo(nm, x, y, on_bw=True): cnt[nm] += 1
    elif c == 'g' and near_p and rn.random() < .2:
        nm = rn.choice(PROPS_PATH)
        if addo(nm, x, y): cnt[nm] += 1
    elif c == 'g' and rn.random() < .04:
        nm = rn.choice(['fh_reeds_c', 'fh_mud_puddle', 'fh_reeds_a'])
        if addo(nm, x, y): cnt[nm] += 1
# shop signs by the doors + the town sign by the S gate
SIGNS = {'fenhollow_swords': 'fh_sign_smith', 'fenhollow_cook': 'fh_sign_cook', 'fenhollow_general': 'fh_sign_store', 'fenhollow_kell_lodge': 'fh_sign_kell'}
nsign = 0
for b in out_b:
    s = SIGNS.get(b['id'])
    if not s: continue
    dx, dy = b['door'][0]
    for (ax, ay) in [(-1, 1), (1, 1), (-2, 1), (2, 1), (-1, 2), (1, 2)]:
        q = (dx + ax, dy + ay)
        if q not in objs and q not in BT and grid[q[1]][q[0]] in 'g:' and q != KELL and all(q not in bb['route'] for bb in blds):
            objs[q] = s; nsign += 1; break
sgx = GATE_LINE['south'][0][0]; sgy = GATE_LINE['south'][0][1]
tsign = any(addo('fh_town_sign', sgx + dx, sgy + dy) for dx, dy in ((-3, 3), (4, 3), (-4, 4), (5, 4), (-3, 5), (4, 5), (-5, 6), (6, 6)))
npost = 0
for (qx, qy), (a_, b_) in LANDINGS:
    for sx, sy in ((b_, a_), (-b_, -a_)):
        px_, py_ = qx + 2 * sx + a_, qy + 2 * sy + b_
        if 1 < px_ < GW - 1 and 1 < py_ < GH - 1 and grid[py_][px_] in 'g~' and (px_, py_) not in BT and addo('fh_stilts', px_, py_, water=grid[py_][px_] == '~'): npost += 1
    for k in range(3):
        rx_, ry_ = qx + rn.randint(-3, 3), qy + rn.randint(-3, 3)
        if 1 < rx_ < GW - 1 and 1 < ry_ < GH - 1 and grid[ry_][rx_] == 'g' and addo(rn.choice(PROPS_BANK), rx_, ry_): cnt['landing_reeds'] += 1
print('landing posts', npost)
print('props', dict(cnt), 'signs', nsign, 'town sign', tsign, 'reeds', nreed, 'fishing', fs, 'trees', nt)

# ---------------------------------------------------------------- reachability
inside_walk = {}
for b in out_b + [church]:
    rows = ART[b['art']]['plan'] if not b['flip'] else flip_plan(ART[b['art']]['plan'])
    for y, r in enumerate(rows):
        for x, c in enumerate(r):
            if c in 'oD': inside_walk[(b['at'][0] + x, b['at'][1] + y)] = True
for b in out_b + [church]:
    for key in ('keeper_at', 'altar'):
        if key in b and not b.get('no_keeper'): inside_walk.pop(tuple(b[key]), None)
    for pr in b['props']: inside_walk.pop(tuple(pr['at']), None)
NONBLOCK = {'fh_mud_puddle', 'fh_reeds_a', 'fh_reeds_b', 'fh_reeds_c', 'fh_rope_coil'}
def walk(x, y):
    if not (0 <= x < GW and 0 <= y < GH): return False
    o = objs.get((x, y))
    if o and o not in NONBLOCK: return False
    return grid[y][x] in 'g:=' and (x, y) not in BT or (x, y) in inside_walk
start = tuple(GATES['south'][1]); seen = {start}; q = [start]
while q:
    x, y = q.pop()
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        n2 = (x + dx, y + dy)
        if n2 not in seen and walk(*n2): seen.add(n2); q.append(n2)
fails = []
for side, g in GATES.items():
    if tuple(g[1]) not in seen: fails.append('gate ' + side)
for b in out_b + [church]:
    if tuple(b['door'][0]) not in seen: fails.append('door ' + b['id'])
    if not b.get('no_keeper') and tuple(b['stand']) not in seen: fails.append('stand ' + b['id'])
    for pr in b['props']:
        p = pr['at']
        if not any((p[0] + a, p[1] + c) in seen for a, c in ((1, 0), (-1, 0), (0, 1), (0, -1))): fails.append('prop %s %s' % (b['id'], pr['object']))
for p, v in objs.items():
    if v in ('quest_giver', 'exchange_board', 'workbench', 'training_dummy', 'reed_bed', 'ash_tree', 'alder_tree', 'fishing_spot') and \
       not any((p[0] + a, p[1] + c) in seen for a, c in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1))): fails.append('obj %s %s' % (v, p))
_cells = collections.Counter((b['at'][0] + x, b['at'][1] + y) for b in blds for y, r in enumerate(b['rows']) for x, c in enumerate(r) if c != '.')
overlap = [p for p, n in _cells.items() if n > 1]
road_fails = []
for b in blds:
    al = drawn(b['art'], b['flip']); x0, y0 = b['px']; h, w = al.shape
    if ((ndi.binary_dilation(pathpx & ~ndi.binary_dilation(SPUR_px if False else np.zeros_like(pathpx)), iterations=0) if False else (wallpx | waterpx))[y0:y0 + h, x0:x0 + w] & al).any():
        road_fails.append(b['art'] + str(b['at']))

# ---------------------------------------------------------------- ring QA: sealed with every gate shut, open through each gate; visual centreline walk
def flood(open_gate):
    shut = set()
    for gname, v in GATE_TILES.items():
        if gname != open_gate: shut |= {tuple(p) for p in v}
    def bl(p):
        x, y = p
        if not (0 <= x < GW and 0 <= y < GH): return False
        return p in shut or grid[y][x] in '#~' and grid[y][x] == '#' or (p in BT and p not in inside_walk)
    s = (CXt, CYt); sn = {s}; qq = [s]
    while qq:
        c = qq.pop()
        if not (0 <= c[0] < GW and 0 <= c[1] < GH): return True
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                nn = (c[0] + dx, c[1] + dy)
                if (dx or dy) and nn not in sn and not bl(nn):
                    if dx and dy and bl((c[0] + dx, c[1])) and bl((c[0], c[1] + dy)): continue
                    sn.add(nn); qq.append(nn)
    return False
SEALED = flood('none'); OPENS = sum(1 for gname in GATE_TILES if flood(gname))
# visual walk: one ray every 2 px of perimeter from the town centre; each ray must cross palisade / tower / gate
# alpha between 0.8 and 1.25 of the ring radius (the designer's straight gate runs and connectors stand off the
# ellipse), except the 4 gate passages
_gaps = []; _gate_hits = set(); _n = 0
per = 2 * math.pi * math.sqrt((RX ** 2 + RY ** 2) / 2) * T
NS = int(per / 2)
for k in range(NS):
    a = 2 * math.pi * k / NS; _n += 1
    hit = False; gate = None
    for s_ in np.arange(.8, 1.25, .004):
        vx, vy = CXt + RX * s_ * math.cos(a), CYt + RY * s_ * math.sin(a)
        px, py = int(vx * T), int(vy * T)
        if not (0 <= px < SW and 0 <= py < SH): break
        gt = [g_ for g_, v in GATE_TILES.items() if any(abs(int(vx) - x) <= 1 and abs(int(vy) - y) <= 1 for x, y in v)]
        if gt: gate = gt[0]; break
        if wallpx[py, px]: hit = True; break
    if gate: _gate_hits.add(gate); continue
    if not hit: _gaps.append((round(float(CXt + RX * math.cos(a)), 1), round(float(CYt + RY * math.sin(a)), 1)))
RING_QA = dict(samples=_n, gaps=[list(g_) for g_ in _gaps[:20]], gap_count=len(_gaps), gates=sorted(_gate_hits), sealed=not SEALED, opens=OPENS,
               note='0.3.13 palisade ring walk: a ray from the centre every 2 px of perimeter must cross wall art over the composited palisade/tower/gate alpha; tile flood sealed with the gates shut and open through each')
print('ring QA', RING_QA)

# ---------------------------------------------------------------- register props (sprites.json / objects.json)
SP = os.path.join(REPO, 'data/sprites.json'); OB = os.path.join(REPO, 'data/objects.json')
s_ = json.load(open(SP)); o_ = json.load(open(OB))
NAMES = {'reeds_a': 'Reeds', 'reeds_b': 'Reeds', 'reeds_c': 'Reeds', 'fish_trap': 'Fish trap', 'rope_coil': 'Rope', 'lantern_pole': 'Lantern',
         'barrel': 'Barrel', 'crates': 'Crates', 'drying_rack': 'Drying rack', 'rowboat': 'Rowboat', 'stilts': 'Stilts', 'sign_smith': 'Blacksmith sign',
         'sign_cook': 'Cookhouse sign', 'sign_store': 'Provisions sign', 'sign_kell': "Kell's Lodge", 'town_sign': 'Fenhollow', 'cart': 'Cart', 'mud_puddle': 'Mud'}
for f in sorted(x for x in os.listdir(os.path.join(DST, 'props')) if x.endswith('.png')):
    oid = f[:-4]; n = oid[3:]; im = Image.open(os.path.join(DST, 'props', f))
    s_['objects'][oid] = {'path': f'{RES}/props/{f}', 'frame_size': [im.width, im.height], 'frames': 1, 'anchor': 'bottom',
                          'note': '0.3.13 designer Fenhollow v1 prop (art_handoff/towns/fenhollow)'}
    o_['objects'][oid] = {'name': NAMES.get(n, n.replace('_', ' ').capitalize()), 'sprite': oid, 'blocks': oid not in NONBLOCK, 'type': 'prop'}
json.dump(s_, open(SP, 'w'), indent=1); json.dump(o_, open(OB, 'w'), indent=1)

# ---------------------------------------------------------------- write data
GROUND = {'g': 'marsh', ':': 'path', '~': 'water', '=': 'boardwalk', '#': 'palisade', 'G': 'gate_wood'}
GPASS = {(x, y) for v in GATE_TILES.values() for x, y in v if grid[y][x] in ':=g'}   # passages are gate tiles (safe zone, 'through a gate')
OBJ_CH = {}
chars = iter('ABCEFHIJKLMNOPQRSTUVWXYZabcdefhijklmnopqrstuvwxyz0123456789!$%&()*+,/;<>?@[]_{|}^')
STATIONS = {'pew', 'candle_stand', 'bank_chest', 'oven', 'furnace', 'anvil'}
OBJ_CH['quest_giver'] = 'K'
for o in sorted(set(objs.values()) - STATIONS - {'quest_giver'}):
    c = next(chars)
    while c in GROUND or c in 'KG': c = next(chars)
    OBJ_CH[o] = c
rows = []
for y in range(GH):
    r = ''
    for x in range(GW):
        o = objs.get((x, y))
        r += OBJ_CH[o] if o in OBJ_CH else ('G' if (x, y) in GPASS else grid[y][x])
    rows.append(r)
objects = {}
for o, ch in OBJ_CH.items():
    gs = [GROUND[grid[p[1]][p[0]]] for p, v in objs.items() if v == o]
    objects[ch] = {'object': o, 'ground': collections.Counter(gs).most_common(1)[0][0]}
_ta_p = os.path.join(REPO, 'data/town_art.json'); _ta = json.load(open(_ta_p))
_ta['buildings'] = {k: v for k, v in _ta.get('buildings', {}).items() if k not in ART}; _ta['buildings'].update(ART)
json.dump(_ta, open(_ta_p, 'w'), indent=1)
old = json.load(open(os.path.join(REPO, 'data/towns/fenhollow.json')))
spawn = None
for (ax, ay) in [(0, 1), (-1, 1), (1, 0), (-1, 0), (0, 2), (1, 1), (-2, 0), (2, 0), (0, -1)]:
    q = (KELL[0] + ax, KELL[1] + ay)
    if walk(*q) and q in seen and objs.get(q) is None: spawn = q; break
assert spawn, 'no spawn by Kell'
town = dict(id='fenhollow', name='Fenhollow', origin=ORIGIN, spawn=[ORIGIN[0] + spawn[0], ORIGIN[1] + spawn[1]],
            tiles=GROUND, objects=objects, roof='#9a8a5a', building_style='timber',
            specialists=old['specialists'], price_bias=old['price_bias'],
            tagline='Marsh timber town behind a wooden palisade: winding mud lanes, raised boardwalks over the creek and pools, watchtowers on the ring.',
            theme='fenhollow', walls='palisade', gates=GATES, gate_walls=GATE_LINE, gate_tiles=GATE_TILES, ring_qa=RING_QA,
            kell=dict(at=list(KELL), lodge='fenhollow_kell_lodge'),
            art=dict(market=MARKET, plaza_px=[GREEN[0] * T, GREEN[1] * T], ground_decal=f'{RES}/ground_decal.png', ysort=YSORT, fades=FADES),
            buildings=out_b, rows=rows,
            note="0.3.13 generated by tools/world/build_fenhollow_v1.py from the designer's Fenhollow v1 set (art_handoff/towns/fenhollow)")
json.dump(town, open(os.path.join(REPO, 'data/towns/fenhollow.json'), 'w'), indent=1)
_ck['towns']['fenhollow'] = church
json.dump(_ck, open(os.path.join(REPO, 'data/churches.json'), 'w'), indent=1)
NP = os.path.join(REPO, 'data/town_npcs.json'); npcs = json.load(open(NP))
def near_walk(x, y):
    for r_ in range(0, 10):
        for dx in range(-r_, r_ + 1):
            for dy in range(-r_, r_ + 1):
                p = (x + dx, y + dy)
                if p in seen and 0 <= p[0] < GW and 0 <= p[1] < GH and grid[p[1]][p[0]] in ':=' and p not in inside_walk: return [p[0], p[1]]
guards = []
for gname, v in GATE_TILES.items():          # two guards just inside every gate
    xs = [p[0] for p in v]; ys = [p[1] for p in v]
    if gname in ('north', 'south'):
        iy = max(ys) + 2 if gname == 'north' else min(ys) - 2
        for gx in (min(xs) - 1, max(xs) + 1): guards.append(dict(enemy='town_guard', patrol=[near_walk(gx, iy)], gate=gname))
    else:
        ix = max(xs) + 2 if gname == 'west' else min(xs) - 2
        for gy in (min(ys) - 1, max(ys) + 1): guards.append(dict(enemy='town_guard', patrol=[near_walk(ix, gy)], gate=gname))
for beat in [[(int(x * S), int(y * S)) for x, y in bt] for bt in [[(37, 30), (24, 27), (15, 26)], [(37, 30), (46, 31), (55, 26)], [(36, 12), (28, 13), (19, 17)], [(39, 41), (48, 44), (56, 41)]]]:
    guards.append(dict(enemy='town_guard', patrol=[near_walk(int(x), int(y)) for x, y in beat]))
npcs['towns']['fenhollow'] = dict(guards=guards, citizens=dict(enemy='citizen', count=6, area=[GREEN[0] - 8, GREEN[1] - 6, 17, 13]),
                                  note='0.3.13 two guards inside each of the 4 palisade gates + 4 lane patrols')
json.dump(npcs, open(NP, 'w'), indent=1)

# ---------------------------------------------------------------- debug composite
dbg = Image.new('RGBA', (SW, SH), (40, 60, 50, 255)); dbg.alpha_composite(Image.fromarray(dec))
items = [(it['pos'][1] + it['base'], 'y', it) for it in YSORT]
items += [(b['px'][1] + BM[b['art']]['px'][1], 'b', b) for b in blds] + [(y * T + T, 'p', (o, x, y)) for (x, y), o in objs.items()]
for _, kind, it in sorted(items, key=lambda t: t[0]):
    if kind == 'b':
        for l in BM[it['art']]['layers']:
            im = LB(l); im = im.transpose(Image.FLIP_LEFT_RIGHT) if it['flip'] else im
            dbg.alpha_composite(im, tuple(it['px']))
    elif kind == 'y':
        im = Image.open(os.path.join(DST, it['path'][len(RES) + 1:])).convert('RGBA'); dbg.alpha_composite(im, (it['pos'][0], max(0, it['pos'][1])))
    else:
        o, x, y = it; p = s_['objects'].get(o, {}).get('path', '')
        if p.startswith(RES):
            im = Image.open(os.path.join(DST, p[len(RES) + 1:])).convert('RGBA')
            dbg.alpha_composite(im, (int(x * T + 8 - im.width / 2), max(0, int(y * T + T - im.height))))
        else: ImageDraw.Draw(dbg).rectangle([x * T + 3, y * T + 3, x * T + 12, y * T + 12], fill=(220, 60, 60, 255) if o != 'quest_giver' else (255, 220, 0, 255))
for it in FADES: dbg.alpha_composite(Image.open(os.path.join(DST, it['path'][len(RES) + 1:])).convert('RGBA'), tuple(it['pos']))
ImageDraw.Draw(dbg).rectangle([spawn[0] * T + 4, spawn[1] * T + 4, spawn[0] * T + 11, spawn[1] * T + 11], outline=(0, 255, 255, 255))
os.makedirs(os.path.join(REPO, 'build'), exist_ok=True)
dbg.save(os.path.join(REPO, 'build/fenhollow_layout_check.png'))
open('/tmp/fh/grid.txt', 'w').write('\n'.join(rows))
print('buildings', len(blds), 'designs', len(set(b['art'] for b in blds)), 'objects', len(objs), 'tile overlaps', overlap, 'art over wall/water', road_fails,
      'reach fails', fails, 'spawn', town['spawn'], 'kell', [ORIGIN[0] + KELL[0], ORIGIN[1] + KELL[1]])
ok = not (overlap or fails or road_fails or RING_QA['gap_count'] or not RING_QA['sealed'] or OPENS != 4 or len(_gate_hits) != 4)
sys.exit(0 if ok else 1)
