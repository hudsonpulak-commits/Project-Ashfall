"""0.3.11 Highfen redesign: circular walled capital built from the designer's
layered art set (art_handoff/towns/highfen, read-only; copied into the repo).

Writes:
  assets/sprites/towns/highfen/{buildings,props,walls}/   (copies)
  assets/sprites/towns/highfen/ground_decal.png           (curved cobble roads + plaza, puddles, mud)
  data/town_art.json                                      (per-design tile plans + layer lists)
  data/towns/highfen.json                                 (rows, buildings, props, gates)
  build/highfen_layout_check.png                          (debug)
Exits 1 if any building pixel (all layers, full drawn height) overlaps a road pixel,
or if a door / gate is unreachable.
"""
import json, math, os, random, shutil, sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SRC = '/workspace/art_handoff/towns/highfen/v5'   # 0.3.14 sprite bot's resized set (min 5x5, walk-in, *_night layers); read-only
DST = os.path.join(REPO, 'assets/sprites/towns/highfen')
RES = 'res://assets/sprites/towns/highfen'
T = 16
N = 92  # 0.3.14 v5 art is ~1.4x the area: city grown 72 -> 92, recentred on the 0.3.13 centre
#                   # town is N x N tiles
SW = SH = N * T
CX, CY = SW // 2, SH // 2  # ring centre (px)
R = 28 * T                 # 0.3.11b city wall mean radius (px); oval: RX/RY below
RX, RY = 30.0, 28.0          # wall radii in tiles (oval, wider than tall)

# ---------------------------------------------------------------- copy art
for sub in ('buildings', 'props', 'walls'):
    os.makedirs(os.path.join(DST, sub), exist_ok=True)
    for f in sorted(os.listdir(os.path.join(SRC, sub))):
        if f.endswith('.png'):
            shutil.copyfile(os.path.join(SRC, sub, f), os.path.join(DST, sub, f))
shutil.copyfile(os.path.join(SRC, 'manifest.json'), os.path.join(DST, 'manifest.json'))
shutil.copyfile(os.path.join(os.path.dirname(SRC), 'README.md'), os.path.join(DST, 'README_designer.md'))
# 0.3.11 v3.1: the designer's v3 buildings + v3.1 wall/gate tiles + v3 props
for sub, dsub in (('buildings_v3', 'buildings'), ('tiles_v31', 'v31'), ('props_v3', 'props_v3')):
    os.makedirs(os.path.join(DST, dsub), exist_ok=True)
    for f in sorted(os.listdir(os.path.join(SRC, sub))):
        if f.endswith('.png'): shutil.copyfile(os.path.join(SRC, sub, f), os.path.join(DST, dsub, f))
shutil.copyfile(os.path.join(SRC, 'tiles_v3', 'v3_wall_tower_round.png'), os.path.join(DST, 'v31', 'v3_wall_tower_round.png'))
shutil.copyfile(os.path.join(SRC, 'manifest_v3.json'), os.path.join(DST, 'manifest_v3.json'))
# 0.3.13 v4: guild, cookhouse, player shop, smithy, general store + lamps/statue/banners/trees (read-only source, copied in)
for sub, dsub in (('v4/buildings', 'buildings'), ('v4/props', 'props_v4')):
    os.makedirs(os.path.join(DST, dsub), exist_ok=True)
    for f in sorted(os.listdir(os.path.join(SRC, sub))):
        if f.endswith('.png'): shutil.copyfile(os.path.join(SRC, sub, f), os.path.join(DST, dsub, f))
shutil.copyfile(os.path.join(SRC, 'v4', 'manifest_v4.json'), os.path.join(DST, 'manifest_v4.json'))
M4 = json.load(open(os.path.join(SRC, 'v4', 'manifest_v4.json')))
M = json.load(open(os.path.join(SRC, 'manifest.json')))
M['buildings'] = M['buildings'] + json.load(open(os.path.join(SRC, 'manifest_v3.json')))['buildings'] + M4['buildings']
BM = {b['name']: b for b in M['buildings']}
def L(sub, n):
    n = n if n.endswith('.png') else n + '.png'; p = os.path.join(SRC, sub, n)
    if sub == 'buildings' and not os.path.exists(p): p = os.path.join(SRC, 'buildings_v3', n)
    if sub == 'props' and not os.path.exists(p): p = os.path.join(SRC, 'props_v3', n)
    if not os.path.exists(p): p = os.path.join(SRC, 'v4', sub, n)
    return Image.open(p).convert('RGBA')

# ---------------------------------------------------------------- designer palette + road texture (copied from src/gen_highfen.py)
def hx(s): return np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)] + [255], np.uint8)
P = dict(ol='120c10', st0='241c20', st1='3a3134', st2='5a4f4f', st3='857a74', w0='2a1b14', w1='47301f', g1='203a26', g2='2f5530', b1='1d3445', b2='2e5064')
C = {k: hx(v) for k, v in P.items()}
BAY = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.
def ramp_px(r, y, x, t):
    n = len(r) - 1; v = t * n + (BAY[y % 4, x % 4] - .5) * .9; return C[r[int(min(n, max(0, round(v))))]]
def grade(a):
    f = a[..., :3].astype(float); l = (f * [.3, .59, .11]).sum(-1, keepdims=True)
    f = (f * .64 + l * .36) * .92 + np.array([2, 0, 4]); a = a.copy(); a[..., :3] = np.clip(f, 0, 255).astype(np.uint8); return a
def road_tex(mask, seed=0):
    rnd = np.random.RandomState(seed); a = np.zeros(mask.shape + (4,), np.uint8)
    dist = ndi.distance_transform_edt(np.pad(mask, 1))[1:-1, 1:-1]
    st = rnd.rand(*mask.shape); jit = ndi.gaussian_filter(rnd.rand(*mask.shape), 2)
    puddle = (ndi.gaussian_filter(rnd.rand(*mask.shape), 3) > .565) & (dist > 3)
    for y, x in zip(*np.nonzero(mask)):
        j = int(jit[y, x] * 6)
        cell = ((x + j) // 5 + ((y + j // 2) // 4) % 2 * 2) % 3 == 0 or (y + j // 3) % 4 == 0
        t = .5 - (.3 if cell else 0) + (.18 if st[y, x] > .9 else 0) - (.2 if st[y, x] < .12 else 0)
        c = ramp_px(['st0', 'st1', 'st2', 'st3'], y, x, t)
        if dist[y, x] < 2 + 1.5 * jit[y, x]: c = C['w0'] if st[y, x] < .45 else C['w1'] if st[y, x] < .8 else C['g1']
        if st[y, x] > .985: c = C['g2']
        if st[y, x] < .01: c = C['ol']
        if puddle[y, x]: c = C['b1'] if st[y, x] > .25 else C['b2']
        a[y, x] = c
    return grade(a)

# ---------------------------------------------------------------- per-design tile plans
def plan_of(b):
    """Tile plan from the floor layer: '#' wall (blocking), 'o' walkable floor, 'D' door, '.' not part of the building.
    A tile is part of the building if the floor layer covers >= 24 of its 256 px; the shape's rim is wall."""
    n = b['name']; E = b['footprint_origin_px'][1]; W, H = b['tiles']; d = tuple(b['door_tile'])
    f = np.array(L('buildings', n + '_floor'))[..., 3] > 0
    S = set()
    for y in range(H):
        for x in range(W):
            if f[E + y * T:E + y * T + T, x * T:x * T + T].sum() >= 24:
                S.add((x, y))
    S.add(d)
    inn = {t for t in S if t != d and t[1] < H - 1 and all((t[0] + a, t[1] + c) in S for a, c in ((1, 0), (-1, 0), (0, 1), (0, -1)))}
    rows = [''.join('D' if (x, y) == d else 'o' if (x, y) in inn else '#' if (x, y) in S else '.' for x in range(W)) for y in range(H)]
    return rows
def plan_of_v2(b):
    # 0.3.14 v5 art: walls on the footprint edge; walkable = designer clear area + door lane + door
    E = b['footprint_origin_px'][1]; W, H = b['tiles']; d = tuple(b['door_tile']); H = d[1] + 1
    def inr(r, cx, cy): return r[0] <= cx < r[0] + r[2] and r[1] <= cy < r[1] + r[3]
    return [''.join('D' if (x, y) == d else 'o' if 0 < x < W - 1 and 0 < y < H - 1 and (inr(b['clear_area_px'], x * T + 8, E + y * T + 8) or inr(b['door_lane_px'], x * T + 8, E + y * T + 8)) else '#'
                    for x in range(W)) for y in range(H)]
ART = {}
for b in M['buildings']:
    lay = b['layers']; fade = b['fade_group']
    ART[b['name']] = dict(tiles=[b['tiles'][0], b['door_tile'][1] + 1] if 'clear_area_px' in b else b['tiles'], px=b['px'], origin_y=b['footprint_origin_px'][1], door_tile=b['door_tile'], storeys=b['storeys'],
                          floor=f"{RES}/buildings/{lay[0]}", walls=f"{RES}/buildings/{lay[1]}",
                          fade=[f"{RES}/buildings/{l}" for l in fade], night=(f"{RES}/buildings/{b['night_layer']}" if b.get('night_layer') else ''),
                          plan=plan_of_v2(b) if 'clear_area_px' in b else plan_of(b))
segs = {k: dict(path=f"{RES}/walls/{k}.png", offset=v['offset_from_ring_px'], size=v['size']) for k, v in M['wall_segments'].items()}
PROPS = {p[0]: p[1] for p in M['props']}

def flip_plan(rows): return [r[::-1] for r in rows]

# ---------------------------------------------------------------- 0.3.11 v3.1 geometry (designer's tiles_v31 method, src/preview_v31.py):
# ring wall + ring roads sampled on the (N+1)x(N+1) VERTEX grid; 45-degree corner autotiles (NW1|NE2|SE4|SW8)
sys.path.insert(0, os.path.join(SRC, 'src'))
import diagtiles as dg
M3 = json.load(open(os.path.join(SRC, 'manifest_v3.json'))); GM = M3['v31']['gates']
CXt, CYt = N // 2, N // 2
RX, RY = 38, 32
R = RY * T
Y, X = np.mgrid[:SH, :SW]
VY, VX = np.mgrid[:N + 1, :N + 1].astype(float)
_ang = np.degrees(np.arctan2((VY - CYt) / RY, (VX - CXt) / RX)) % 360
_wob = 1 + .03 * np.sin(np.radians(_ang) * 5 + 1) + .015 * np.sin(np.radians(_ang) * 11)
def vell(rx, ry): return np.hypot((VX - CXt) / rx, (VY - CYt) / ry) / _wob <= 1
# 0.3.11 v3.1b one continuous OCTAGONAL ring (straights + true 45-degree runs only, so the corner autotile
# never steps or saddles): |dx| <= RX, |dy| <= RY, |dx|+|dy| <= S on the vertex grid; 2 tiles thick
S_OCT = 40
_dX, _dY = np.abs(VX - CXt), np.abs(VY - CYt)
def voct(k, kd): return (_dX <= RX + k) & (_dY <= RY + k) & (_dX + _dY <= S_OCT + kd)
WV = voct(1, 2) & ~voct(-1, -1)
def vring(s, hw, sy=None): sy = sy or s; return vell(s * RX + hw, sy * RY + hw) & ~vell(s * RX - hw, sy * RY - hw)
PR = .24                                         # plaza radius (fraction of RX/RY)
RV = vring(.66, .95, .75)   # 0.3.13 v4: outer ring road dropped
RV |= vell(PR * RX * 1.15, PR * RY)
LANES = {}
for nm_, a0, hw in [('east_track', 0, 1.05), ('gate_road', 90, 1.05), ('west_track', 180, 1.05), ('north_track', 270, 1.05),
                    ('s1', 30, .8), ('s2', 150, .8), ('s3', 210, .8), ('s4', 330, .8)]:   # v4: 60/120 deg spokes dropped
    r0 = PR if hw < 1 else (.75 if a0 == 270 else 0); r1 = .68 if hw < 1 else 1.6
    p = [(CXt + RX * r * math.cos(math.radians(a0)), CYt + RY * r * math.sin(math.radians(a0))) for r in (r0, r1)]
    RV |= dg.line_mask(VY.shape, p, hw)
    LANES[nm_] = [(T * (p[0][0] + (p[1][0] - p[0][0]) * t / 80), T * (p[0][1] + (p[1][1] - p[0][1]) * t / 80)) for t in range(81)]
# gates: straight wall runs (>= 5 tiles each side) + the passage cut; N back, S front, E/W side profile
JOINS = []; GATE = []; GATE_LINE = {}; GATE_TILES = {}; ROOF_TILES = {}
for g, view, side in [(270, 'back', 'north'), (90, 'front', 'south'), (0, 'side', 'east'), (180, 'side', 'west')]:
    if view == 'side':
        c = CXt + RX if g == 0 else CXt - RX - 1; cy = CYt          # the 2 vertex columns of the straight run: c, c+1
        WV[cy - 1:cy + 2, c - 1:c + 3] = False
        GATE.append(('v31_gate_side', int((c + .5) * T) - 24, cy * T - 57, g))
        GATE_TILES[side] = [[x, y] for x in (c - 1, c, c + 1) for y in (cy - 1, cy)]
        GATE_LINE[side] = [[c, cy - 1], [c, cy]]
        ROOF_TILES[side] = [[x, y] for x in range(c - 2, c + 3) for y in (cy - 1, cy)]
    else:
        r = CYt - RY - 1 if g == 270 else CYt + RY; cx = CXt     # the 2 vertex rows of the straight run: r, r+1
        WV[r - 1:r + 3, cx - 1:cx + 2] = False
        GATE.append((f'v31_gate_{view}', cx * T - 32, int((r + .5) * T) - 16, g))
        GATE_TILES[side] = [[x, y] for x in (cx - 1, cx) for y in (r - 1, r, r + 1)]
        GATE_LINE[side] = [[cx - 1, r], [cx, r]]
        ROOF_TILES[side] = [[x, y] for x in (cx - 1, cx) for y in range(r - 2, r + 4)]
        JOINS.append(('v31_wall_gate_join_w', (cx - 2) * T, r * T)); JOINS.append(('v31_wall_gate_join_e', (cx + 1) * T, r * T))
RV &= ~WV
for n_, x0, y0, g in GATE:   # the road continues through every passage
    if 'side' in n_: RV |= dg.line_mask(VY.shape, [((x0 - 8) / T, (y0 + 57) / T), ((x0 + 56) / T, (y0 + 57) / T)], 1.0)
    else: RV |= dg.line_mask(VY.shape, [((x0 + 32) / T, y0 / T), ((x0 + 32) / T, (y0 + 72) / T)], .9)
WV &= ~RV
RF = dg.frames_of(RV); WF = dg.frames_of(WV)
bits = lambda f: bin(int(f)).count('1')
CNT_R = np.vectorize(bits)(RF); CNT_W = np.vectorize(bits)(WF)
# road decal (cobble autotile + v3 cobble fills) and the wall rows (16x28 frames, 12 px face hangs into the row below)
_rr = random.Random(int(os.environ.get('HF_ROAD_SEED', 23)))
L31 = lambda n: Image.open(os.path.join(DST, 'v31', n + '.png')).convert('RGBA')
# 0.3.11 v3.1b the plaza / road cobble (and the gate passage floors) lifted with the ground textures
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ground_grade import grade_file
grade_file(os.path.join(SRC, 'tiles_v31', 'v31_diag_cobble.png'), os.path.join(DST, 'v31', 'v31_diag_cobble.png'))
for _g in ('back', 'front', 'side'):
    grade_file(os.path.join(SRC, 'tiles_v31', f'v31_gate_{_g}_floor.png'), os.path.join(DST, 'v31', f'v31_gate_{_g}_floor.png'))
for _n in ('plain', 'worn', 'cracked', 'mossy', 'puddle'):
    grade_file(os.path.join(SRC, 'tiles_v3', f'v3_cobble_{_n}.png'), os.path.join(DST, 'v31', f'v3_cobble_{_n}.png'))
CB = np.array(L31('v31_diag_cobble'))
fills = [np.array(L31(f'v3_cobble_{n}')) for n in ['plain', 'plain', 'plain', 'worn', 'cracked', 'mossy', 'puddle']]
dec = np.zeros((SH, SW, 4), np.uint8)
for y in range(N):
    for x in range(N):
        if RF[y, x] == 15: dec[y * T:y * T + T, x * T:x * T + T] = fills[_rr.randrange(7)]
        elif RF[y, x]: dec[y * T:y * T + T, x * T:x * T + T] = CB[:, RF[y, x] * T:RF[y, x] * T + T]
road = dec[..., 3] > 0
decal = Image.fromarray(dec)
for n_, x0, y0, g in GATE: decal.alpha_composite(L31(n_ + '_floor'), (x0, y0))
WA = L31('v31_diag_wall_dark'); wallpx = np.zeros((SH + 28, SW), bool); YSORT = []; FADES = []
os.makedirs(os.path.join(DST, 'v31', 'rows'), exist_ok=True)
for f_ in os.listdir(os.path.join(DST, 'v31', 'rows')): os.remove(os.path.join(DST, 'v31', 'rows', f_))
for y in range(N):
    if not WF[y].any(): continue
    xs_ = np.nonzero(WF[y])[0]; xa, xb = int(xs_.min()), int(xs_.max()) + 1
    row = Image.new('RGBA', ((xb - xa) * T, 28))
    for x in range(xa, xb):
        if WF[y, x]: row.alpha_composite(WA.crop((WF[y, x] * T, 0, WF[y, x] * T + T, 28)), ((x - xa) * T, 0))
    row.save(os.path.join(DST, 'v31', 'rows', f'wall_row_{y:02d}.png'))
    YSORT.append(dict(path=f'{RES}/v31/rows/wall_row_{y:02d}.png', pos=[xa * T, y * T], base=T))
    wallpx[y * T:y * T + 28, xa * T:xb * T] |= np.array(row)[..., 3] > 0
wallpx = wallpx[:SH]
for n_, x0, y0, g in GATE:
    h = GM[n_]['size_px'][1]
    YSORT.append(dict(path=f'{RES}/v31/{n_}_walls.png', pos=[x0, y0], base=h))
    side = {270: 'north', 90: 'south', 0: 'east', 180: 'west'}[g]
    FADES.append(dict(path=f'{RES}/v31/{n_}_roof.png', pos=[x0, y0], tiles=ROOF_TILES[side]))
    wallpx[max(0, y0):y0 + h, x0:x0 + GM[n_]['size_px'][0]] |= np.array(L31(n_ + '_walls'))[:SH - max(0, y0), :, 3] > 0
decal.save(os.path.join(DST, 'ground_decal.png'))
# 0.3.11 v3.1b towers: a round tower on each of the 8 octagon turns (objects), and the designer's
# diagonal tower fits (v31_wall_tower_fit_diag_ne/nw) at the middle of the 4 diagonal runs, snapped
# to the pixel offset where the fit's wall stubs best match the wall rows (so the run stays unbroken)
wp = lambda a_, r=1.0: ((CXt + RX * r * math.cos(math.radians(a_))) * T, (CYt + RY * r * math.sin(math.radians(a_))) * T)
TOWER_T = []
_tc = S_OCT - RY, S_OCT - RX
for sx in (-1, 1):
    for sy in (-1, 1):
        for (vx, vy) in ((_tc[0], RY + .5), (RX + .5, _tc[1])):
            x, y = (CXt + sx * vx) * T, (CYt + sy * vy) * T
            TOWER_T.append((int(x // T), int((y + 8) // T)))
for (tx, ty) in TOWER_T:
    x, y = tx * T + 8, ty * T + 16
    wallpx[max(0, y - 64):y, x - 24:x + 24] |= np.array(L31('v3_wall_tower_round'))[64 - (y - max(0, y - 64)):, :, 3] > 0
FITS = []
_wall0 = wallpx.copy()
for sx in (-1, 1):
    for sy in (-1, 1):
        m = (S_OCT + .5) / 2; cx, cy = (CXt + sx * m) * T, (CYt + sy * m) * T
        best = None
        for nm_ in ('v31_wall_tower_fit_diag_ne', 'v31_wall_tower_fit_diag_nw'):
            al = np.array(L31(nm_))[..., 3] > 0; h, w = al.shape
            for oy in range(-24, 25):
                for ox in range(-24, 25):
                    x0, y0 = int(cx - w / 2 + ox), int(cy - h / 2 + oy)
                    win = _wall0[y0:y0 + h, x0:x0 + w]
                    sc_ = (win & al).sum() - 2 * (al & ~win).sum()
                    if best is None or sc_ > best[0]: best = (sc_, nm_, x0, y0)
        _, nm_, x0, y0 = best
        FITS.append((nm_, x0, y0))
        YSORT.append(dict(path=f'{RES}/v31/{nm_}.png', pos=[x0, y0], base=70))
        wallpx[y0:y0 + 92, x0:x0 + 80] |= np.array(L31(nm_))[..., 3] > 0
for (nm_, x0, y0) in JOINS:
    YSORT.append(dict(path=f'{RES}/v31/{nm_}.png', pos=[x0, y0], base=T))
    wallpx[y0:y0 + 28, x0:x0 + 16] |= np.array(L31(nm_))[..., 3] > 0
print('tower fits', FITS)
# tiles: wall = >= 2 wall corners, road = >= 3 cobble corners; gates = the passage tiles
wall_t = CNT_W >= 2
for (nm_, x0, y0) in FITS:      # the fit's round tower body blocks
    for ty in range((y0 + 40) // T, (y0 + 72) // T):
        for tx in range((x0 + 20) // T, (x0 + 60) // T + 1): wall_t[ty, tx] = True
for (tx, ty) in TOWER_T: wall_t[ty, tx] = False
roadT = np.where(CNT_R >= 3, 2, 0).astype(np.uint8)
GATES_RING = GATE_LINE   # the passage tiles on the wall line (gate torches either side)
for v in GATE_TILES.values():
    for (x, y) in v: wall_t[y, x] = False; roadT[y, x] = 2
# 0.3.11 v3.1b the cliff diagonal rule: where two wall tiles touch only at a corner, the open corner cell
# with more wall in it (ties: the inner one) becomes wall too - no diagonal slip-throughs
_gate_set = {tuple(p) for v in GATE_TILES.values() for p in v}
_tow = set(TOWER_T)
blk = lambda x, y: wall_t[y, x] or (x, y) in _tow
for _ in range(3):
    for y in range(N - 1):
        for x in range(N - 1):
            a, b, c, d = blk(x, y), blk(x + 1, y), blk(x, y + 1), blk(x + 1, y + 1)
            for (p1, p2, o1, o2) in (((x, y), (x + 1, y + 1), (x + 1, y), (x, y + 1)), ((x + 1, y), (x, y + 1), (x, y), (x + 1, y + 1))):
                if blk(*p1) and blk(*p2) and not blk(*o1) and not blk(*o2):
                    cand = [o for o in (o1, o2) if o not in _gate_set]
                    if not cand: continue
                    o = max(cand, key=lambda q: (CNT_W[q[1], q[0]], -abs(q[0] - CXt) - abs(q[1] - CYt)))
                    wall_t[o[1], o[0]] = True
inner = vell(RX - 1, RY - 1)[:-1, :-1] & vell(RX - 1, RY - 1)[1:, 1:]
print('wall tiles', int(wall_t.sum()), 'gates', {k: len(v) for k, v in GATES_RING.items()})
INNER_PX = np.kron(vell(RX - 1.6, RY - 1.6)[:-1, :-1] & vell(RX - 1.6, RY - 1.6)[1:, 1:], np.ones((T, T), bool))
OUTER_KEEP = np.kron(voct(3, 4)[:-1, :-1], np.ones((T, T), bool))
ringA = wallpx
PLAZA = (CXt * T, CYt * T, int(PR * RX * 1.15 * T), int(PR * RY * T))
plaza = ((X - PLAZA[0]) / PLAZA[2]) ** 2 + ((Y - PLAZA[1]) / PLAZA[3]) ** 2 <= 1
W_ = {}

# ---------------------------------------------------------------- building placement (tile-snapped)
occ = ndi.binary_dilation(road | ringA, iterations=2)       # px: no building pixel here
tile_used = np.zeros((N, N), bool)                           # building tiles + margins
tile_used |= wall_t
blds = []
QW = []                                                    # dicts
def drawn(n, flip):
    b = BM[n]; im = Image.new('RGBA', tuple(b['px']))
    for l in b['layers']: im.alpha_composite(L('buildings', l))
    if flip: im = im.transpose(Image.FLIP_LEFT_RIGHT)
    return np.array(im)[..., 3] > 0
def plan_tiles(n, flip):
    rows = ART[n]['plan']; rows = flip_plan(rows) if flip else rows
    return rows, [(x, y) for y, r in enumerate(rows) for x, c in enumerate(r) if c != '.']
def door_local(n, flip):
    rows, _ = plan_tiles(n, flip)
    for y, r in enumerate(rows):
        if 'D' in r: return (r.index('D'), y)
def place(n, tx, ty, inside, flip=False, role=None, reach=320, extra=None, quiet=False):
    al = drawn(n, flip); h, w = al.shape; E = ART[n]['origin_y']; W, H = ART[n]['tiles']
    rows, tiles = plan_tiles(n, flip); dl = door_local(n, flip)
    why = {}
    for r in range(0, reach, 3):
        for t in range(0, 360, 12 if r else 360):
            px = tx + r * math.cos(math.radians(t)) - w / 2; py = ty + r * math.sin(math.radians(t)) - h / 2
            ox, oy = int(round(px / T)), int(round((py + E) / T))     # footprint origin tile
            x0, y0 = ox * T, oy * T - E
            if ox < 1 or oy < 1 or ox + W > N - 1 or oy + H > N - 2 or y0 < 0 or x0 + w > SW: continue
            ys, xs = np.nonzero(al); dd = np.hypot(xs + x0 - CX, ys + y0 - CY)
            if inside and not INNER_PX[ys + y0, xs + x0].all(): why['ring'] = why.get('ring', 0) + 1; continue
            if not inside and OUTER_KEEP[ys + y0, xs + x0].any(): continue
            if (occ[y0:y0 + h, x0:x0 + w] & al).any(): why['occ'] = why.get('occ', 0) + 1; continue
            # tiles: footprint + 1 margin all round free; the tile in front of the door free
            bad = False
            for (lx, ly) in tiles:
                for ax in (-1, 0, 1):
                    for ay in (-1, 0, 1):
                        q = (ox + lx + ax, oy + ly + ay)
                        if not (0 <= q[0] < N and 0 <= q[1] < N) or tile_used[q[1], q[0]]: bad = True
            fx, fy = ox + dl[0], oy + dl[1] + 1
            if fy >= N or tile_used[fy, fx] or tile_used[min(N - 1, fy + 1), fx]: bad = True
            if extra and not extra(ox, oy): bad = True
            if bad: why['tiles'] = why.get('tiles', 0) + 1; continue
            occ[y0:y0 + h, x0:x0 + w] |= ndi.binary_dilation(al, iterations=2)
            for (lx, ly) in tiles: tile_used[oy + ly, ox + lx] = True
            d = dict(art=n, flip=flip, at=[ox, oy], role=role, px=[x0, y0], rows=rows, door=[ox + dl[0], oy + dl[1]])
            blds.append(d); return d
    if not quiet: print('no room for', n, role, why)
    else: QW.append(why)
    return None

# 0.3.11 v3.1 layout (designer preview_v31 + Hudson's reference): palace (keep) north of the fountain plaza,
# church (temple) west, guild east, market stalls on the plaza's south side, dense houses between the rings
CX, CY = CXt * T, CYt * T
pr = PR * RY * T
place('v3_keep', CX, CY - pr - 95, True, role='palace')
def place_any(n, spots, role, reach=48):
    for i, (a_, r_) in enumerate(spots):
        if place(n, *wp(a_, r_), True, role=role, reach=reach, quiet=True): return
    for a_ in range(0, 360, 30):     # last resort: wide search from the outer band
        if place(n, *wp(a_, .75), True, role=role, reach=200, quiet=True): return
    for a_ in range(0, 360, 15):     # 0.3.14 v5 art is bigger: outside the wall, by the ring road
        if place(n, *wp(a_, 1.14), False, role=role, reach=120, quiet=a_ < 345): print('outside the wall:', n, role); return
# 0.3.13 v4 layout (designer preview_v4): v3.1 civic core round the plaza; the larger v4 buildings take the room
# freed by the dropped outer ring road (guild, general store, smithy in the outer band; player shop + cookhouse mid-ring)
RING = lambda a0, r0: [(a0, r0)] + [((a0 + d) % 360, r_) for d in (8, -8, 16, -16, 24, -24, 36, -36, 50, -50, 70, -70, 90, -90) for r_ in (r0, r0 + .05, r0 - .05)]
place_any('v3_temple', RING(232, .56), 'church', reach=60)
place_any('v3_town_hall', RING(308, .56), 'townhall', reach=60)
place_any('v4_guild', RING(20, .42), 'guild', reach=60)
for n_, a_, r_, role_ in [('v3_bank', 345, .50, 'bank'), ('shop_tavern', 135, .74, 'cook'), ('v4_general_store', 100, .74, 'general'),
                          ('v4_player_shop', 165, .74, 'player_shop'), ('v3_player_house', 75, .50, 'player_house'),
                          ('v4_cookhouse', 195, .50, 'baker'), ('v4_smithy', 20, .8, 'smithy')]:
    place_any(n_, RING(a_, r_), role_, reach=150)
POOL = M3['houses'] + ['v3_house_narrow_tall', 'v3_house_longhouse']
use = {}; pi = 0; fill = 0
cands = [(r_, a_) for r_ in (.3, .36, .42, .47, .52, .58, .78, .82) for a_ in range(0, 360, 3)]
random.Random(12).shuffle(cands); cands.sort(key=lambda c: c[0])
for r_, a_ in cands:
    for _ in range(4):
        n = POOL[pi % len(POOL)]; pi += 1
        if use.get(n, 0) >= 3: continue
        if place(n, *wp(a_, r_), True, flip=use.get(n, 0) % 2 == 1, role='home', reach=24, quiet=True):
            use[n] = use.get(n, 0) + 1; fill += 1; break
print('inside houses', fill)
import collections; _c = collections.Counter()
for w in QW: _c.update(w)
print('ring-house rejections', dict(_c))
# lore: the civilian houses circle the city OUTSIDE the wall
nout = 0
for i in range(48):
    ang = i * 7.5 + 3; n = POOL[(i * 7) % len(POOL)]
    for rr in (1.16, 1.24, 1.32):
        if place(n, *wp(ang, rr), False, flip=(i // len(POOL)) % 2 == 1, role='home', reach=20, quiet=True):
            nout += 1; break
print('outside houses', nout, 'designs used', len(set(b['art'] for b in blds)))

# ---------------------------------------------------------------- tile grid
grid = [['.'] * N for _ in range(N)]     # '.' grass
rnd = random.Random(11)
dn = ndi.gaussian_filter(np.random.RandomState(2).rand(N, N), 1.4) > .62
for y in range(N):
    for x in range(N):
        if dn[y, x] and math.hypot(x * T + 8 - CX, y * T + 8 - CY) < R + 160: grid[y][x] = 'd'
for y in range(N):
    for x in range(N):
        if wall_t[y, x]: grid[y][x] = 'W'
        elif roadT[y, x]: grid[y][x] = 'r' if roadT[y, x] == 1 else 'c'
for b in blds:
    ox, oy = b['at']
    for ly, r in enumerate(b['rows']):
        for lx, c in enumerate(r):
            if c != '.': grid[oy + ly][ox + lx] = 'B'
# road-covered tiles: no dirt patches (the decal covers them anyway)
rcov = road.reshape(N, T, N, T).mean(axis=(1, 3))
for y in range(N):
    for x in range(N):
        if rcov[y, x] > 0.3 and grid[y][x] == 'd': grid[y][x] = '.'

# ---------------------------------------------------------------- gates (town entrances where the lanes reach the edge)
def edge_gate(track, side):
    pts = LANES[track]
    for (x, y) in pts:
        if side == 'north' and y <= 8: return [[int(x // T) + d, 0] for d in (-1, 0, 1)]
        if side == 'south' and y >= SH - 8: return [[int(x // T) + d, N - 1] for d in (-1, 0, 1)]
        if side == 'west' and x <= 8: return [[0, int(y // T) + d] for d in (-1, 0, 1)]
        if side == 'east' and x >= SW - 8: return [[N - 1, int(y // T) + d] for d in (-1, 0, 1)]
gates = dict(north=edge_gate('north_track', 'north'), south=edge_gate('gate_road', 'south'),
             west=edge_gate('west_track', 'west'), east=edge_gate('east_track', 'east'))

objs = {}                 # (x,y) -> object id
def free_tile(x, y, allow_road=False, margin_doors=True):
    if not (1 <= x < N - 1 and 1 <= y < N - 1): return False
    if any(objs.get((x + a, y + c)) == 'display_stand' for a, c in ((1, 0), (-1, 0), (0, 1), (0, -1))): return False
    if grid[y][x] not in ('.drc' if allow_road else '.d') or (x, y) in objs: return False
    if not allow_road and rcov[y, x] > 0.05: return False
    for b in blds:
        dx, dy = b['door']
        if margin_doors and abs(x - dx) <= 1 and dy <= y <= dy + 2: return False
    for side in gates.values():
        for g in side:
            if abs(x - g[0]) <= 2 and abs(y - g[1]) <= 2: return False
    return True

# ---------------------------------------------------------------- building roles -> game buildings
def interior(b):
    """floor tiles connected to the door (designs like the keep have closed tower rooms)"""
    ox, oy = b['at']
    allo = {(ox + x, oy + y) for y, r in enumerate(b['rows']) for x, c in enumerate(r) if c == 'o'}
    d0 = tuple(b['door']); seen_ = set(); st_ = [d0]
    while st_:
        p = st_.pop()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (p[0] + dx, p[1] + dy)
            if q in allo and q not in seen_: seen_.add(q); st_.append(q)
    return [p for p in sorted(allo, key=lambda p: (p[1], p[0])) if p in seen_]
def rel(p): return [p[0], p[1]]
def above_door(b): return (b['door'][0], b['door'][1] - 1)
def pick(cands, avoid):
    for c in cands:
        if c not in avoid: return c
    return None
NAMES_HOME = [("Cobb's house", 'Tamsin Cobb'), ("The Wrights' house", 'Edric Wright'), ("Old Nell's", 'Nell Ashby'), ("Fletcher's house", 'Osric Fletcher'),
              ("The Moores' house", 'Bryn Moore'), ("Hale's house", 'Agnes Hale'), ("Thatcher's house", 'Wat Thatcher'), ("The Pikes' house", 'Hedda Pike'),
              ("Marsh's house", 'Colm Marsh'), ("Reed's house", 'Ida Reed'), ("The Crofts' house", 'Lew Croft'), ("Brewer's house", 'Mabel Brewer'),
              ("Sexton's house", 'Odo Sexton'), ("The Lanes' house", 'Rosa Lane'), ("Tanner's house", 'Giles Tanner'), ("Webb's house", 'Elsie Webb'),
              ("The Coopers' house", 'Hugh Cooper'), ("Mason's house", 'Wynn Mason'), ("Baxter's house", 'Ada Baxter'), ("Chandler's house", 'Ned Chandler'),
              ("The Ashes' house", 'Pell Ash'), ("Dyer's house", 'Joan Dyer'), ("Carter's house", 'Royce Carter'), ("Shepherd's house", 'Lark Shepherd'),
              ("Miller's house", 'Una Miller'), ("The Holts' house", 'Abel Holt'), ("Weaver's house", 'Kit Weaver'), ("Gage's house", 'Mott Gage'),
              ("Fenwick's house", 'Dora Fenwick'), ("Ewer's house", 'Silas Ewer'), ("Lowe's house", 'Merry Lowe'), ("Rook's house", 'Jory Rook')]
out_b = []
hi = 0
def sign_tile(b):
    dx, dy = b['door']
    for sx in (dx + 1, dx - 1):
        lx = sx - b['at'][0]
        if 0 <= lx < len(b['rows'][0]) and b['rows'][dy - b['at'][1]][lx] == '#': return [sx, dy]
    return [dx, dy]
for b in blds:
    role = b['role']; inn = interior(b); ad = above_door(b); door = b['door']
    base = dict(art=b['art'], flip=b['flip'], at=b['at'], door=[door], sign=sign_tile(b), props=[], counter=[])
    if role == 'palace':
        k = pick(sorted(inn, key=lambda p: (p[1], abs(p[0] - door[0]))), [ad])
        base.update(id='highfen_palace', kind='hall', shop='', name='Highfen Palace', keeper='Lord Chamberlain Oswin', keeper_sprite='keeper_general',
                    sign_sprite='sign_bank', roof='#6c6a7a', keeper_at=rel(k), stand=rel((k[0], k[1] + 1)),
                    greet=["The King's throne room. Mind the carpet, it is older than you.", "His Majesty hears petitions on feast days. Today is not a feast day.",
                           "The Knights keep the roads; the palace keeps the Knights. That is the order of things."],
                    note='0.3.11 the palace and throne room at the heart of Highfen (designer art palace)')
        for p in sorted(inn, key=lambda p: (p[1], p[0])):
            if p[1] == k[1] and abs(p[0] - k[0]) == 2 and len(base['props']) < 2:
                base['props'].append(dict(object='hf4_banner_red', at=rel(p)))
    elif role == 'guild':
        k = pick(sorted(inn, key=lambda p: (p[1], abs(p[0] - door[0]))), [ad])
        base.update(id='highfen_guild', kind='hall', shop='', name='Guild of Knights', keeper='Knight-Commander Brannoc', keeper_sprite='keeper_general',
                    sign_sprite='sign_general', roof='#5a5f6a', keeper_at=rel(k), stand=rel((k[0], k[1] + 1)),
                    greet=["The Guild of Knights. We keep the roads between the cities.", "Prove your steel in the wilds and the Guild will remember your name.",
                           "Wipe your boots. This floor has seen better knights than you, and muddier."],
                    note="0.3.11 the Guild of Knights; the id contains 'guild' so the guild music slot plays inside")
        top = [p for p in inn if p[1] == k[1] and p != k]
        for p in sorted(top, key=lambda p: -abs(p[0] - k[0]))[:2]:
            base['props'].append(dict(object='weapon_rack', at=rel(p)))
    elif role == 'townhall':
        k = pick(sorted(inn, key=lambda p: (p[1], abs(p[0] - door[0]))), [ad])
        base.update(id='highfen_townhall', kind='hall', shop='', name='Highfen Town Hall', keeper='Reeve Margery Holt', keeper_sprite='keeper_general',
                    sign_sprite='sign_general', roof='#6a5a4a', keeper_at=rel(k), stand=rel((k[0], k[1] + 1)),
                    greet=["Deeds, tithes and petitions. Take a number; there are no numbers.", "The Reeve keeps the city's ledgers. All of them. Mostly."],
                    note='0.3.11 v3.1 the town hall (designer v3_town_hall)')
    elif role == 'church':
        alt = min(inn, key=lambda p: p[1])
        st = (alt[0], alt[1] + 1)
        pri = pick(sorted([p for p in inn if p[1] == st[1] + 1 and p[0] != st[0]], key=lambda p: p[0]), [])
        base.update(id='highfen_church', kind='church', name='Highfen Cathedral', keeper='Father Aldric', altar=rel(alt), keeper_at=rel(pri), stand=rel(st),
                    note='0.3.11 Highfen gets a church (designer church art)')
    elif role == 'bank':
        k = pick(sorted(inn, key=lambda p: (p[1], abs(p[0] - door[0]))), [ad])
        st = (k[0], k[1] + 1) if (k[0], k[1] + 1) in inn else ad
        others = [p for p in inn if p not in (k, st, ad)]
        base.update(id='highfen_bank', kind='bank', shop='', name='Highfen Treasury', keeper='Aldous Crane', keeper_sprite='keeper_general', sign_sprite='sign_bank',
                    roof='#8a8f9a', keeper_at=rel(k), stand=rel(st))
        for p in others[:1]: base['props'].append(dict(object='bank_chest', at=rel(p)))
    elif role == 'general':
        k = pick(sorted(inn, key=lambda p: abs(p[0] - door[0]) == 0), [ad]) or inn[0]
        base.update(id='highfen_general', kind='shop', shop='general', name='Highfen Emporium', keeper='Perrin Vale', roof='#b8a888',
                    keeper_at=rel(k), stand=rel(ad if ad != k else inn[0]))
    elif role == 'cook':
        k = pick(sorted(inn, key=lambda p: (p[1], -abs(p[0] - door[0]))), [ad])
        st = (k[0], k[1] + 1) if (k[0], k[1] + 1) in inn and (k[0], k[1] + 1) != ad else ad
        base.update(id='highfen_cook', kind='cookhouse', shop='cook', name='The Gilded Spoon', keeper='Maud Fairweather', roof='#b8a888', keeper_at=rel(k), stand=rel(st))
        top = sorted([p for p in inn if p[1] == k[1] and p != k], key=lambda p: -abs(p[0] - door[0]))
        if top and len(inn) > 2: base['props'].append(dict(object='oven', at=rel(top[0])))
    elif role == 'player_shop':
        k = pick(sorted(inn, key=lambda p: abs(p[0] - door[0]) == 0), [ad]) or inn[0]
        base.update(id='highfen_player', kind='player', shop='player', name='For sale', keeper_at=rel(k), stand=rel(ad if ad != k else inn[0]), roof='#b8a888',
                    note="0.3.8 the realm's ONLY player shop; 0.3.11 its 8 display stands line the market plaza in front of it")
        base['_displays'] = True
    elif role == 'player_house':
        k = pick(sorted(inn, key=lambda p: abs(p[0] - door[0]) == 0), [ad]) or inn[0]
        base.update(id='highfen_house', kind='player_house', shop='', name='Townhouse (for sale)', keeper='Estate clerk', keeper_sprite='keeper_general',
                    sign_sprite='sign_house', roof='#8a5a3a', keeper_at=rel(k), stand=rel(ad if ad != k else inn[0]),
                    note='0.3.8 player house; 0.3.11 a walk-in townhouse with a walled work yard behind it (stations + bank chest work for the owner only)')
        base['_yard'] = True
    elif role == 'smithy':   # 0.3.13 a working forge: furnace + anvil under the roof (stations only where all 8 neighbours are building tiles)
        def _inb(b_, x_, y_):
            lx_, ly_ = x_ - b_['at'][0], y_ - b_['at'][1]
            return 0 <= ly_ < len(b_['rows']) and 0 <= lx_ < len(b_['rows'][0]) and b_['rows'][ly_][lx_] != '.'
        cand = [p for p in inn if p != ad]; k = cand[-1] if cand else door
        base.update(id='highfen_smithy', kind='smithy', shop='', name='Highfen Forge', keeper='Bram Ironside', keeper_sprite='villager',
                    roof='#8a7050', keeper_at=rel(k), stand=rel(ad if ad != k else door), note='0.3.13 Highfen v4 forge (designer v4_smithy): furnace + anvil, smithing role')
        base['sign_sprite'] = 'sign_smithy'
        sp = sorted([p for p in inn if p not in (k, ad, tuple(door)) and all(_inb(b, p[0] + a_, p[1] + c_) for a_ in (-1, 0, 1) for c_ in (-1, 0, 1))], key=lambda p: (p[1], -abs(p[0] - door[0])))
        if len(sp) < 2:
            sp = sorted([p for p in inn if p not in (k, ad, tuple(door))], key=lambda p: (p[1], -abs(p[0] - door[0])))
        print('highfen forge stations', sp[:2])
        base['props'] = [dict(object=o, at=rel(p)) for o, p in zip(['furnace', 'anvil'], sp[:2])]
    elif role in ('baker', 'home'):
        nm, kp = NAMES_HOME[hi % len(NAMES_HOME)]; hi += 1
        if role == 'baker': nm, kp = ("Hob's bakery", 'Hob Larder')
        base.update(id='highfen_home_%d' % hi, kind='house', shop='', name=nm, keeper=kp, keeper_sprite='villager', sign_sprite='sign_house', roof='#8a7050')
        cand = [p for p in inn if p != ad]
        if cand and len(inn) >= 2:
            k = cand[-1]; base.update(keeper_at=rel(k), stand=rel(ad if ad != k else door))
        else:
            base.update(no_keeper=True, keeper_at=rel(door), stand=rel(door))
        if not inn:
            base['closed'] = True
            base.update(stand=[door[0], door[1] + 1], keeper_at=[door[0], door[1] + 1])
    out_b.append(base)

# ---------------------------------------------------------------- player-shop displays on the plaza; player-house yard
for base in out_b:
    if base.pop('_displays', False):
        cands = []
        for y in range(N):
            for x in range(N):
                cx, cy = x * T + 8, y * T + 8
                if ((cx - PLAZA[0]) / (PLAZA[2] + 26)) ** 2 + ((cy - PLAZA[1]) / (PLAZA[3] + 22)) ** 2 <= 1 and not plaza[cy, cx] and free_tile(x, y, True):
                    cands.append((math.hypot(cx - (base['door'][0][0] * T + 8), cy - (base['door'][0][1] * T + 8)), x, y))
        cands.sort(); disp = []
        for _, x, y in cands:
            if len(disp) == 8: break
            if (x, y) in objs: continue
            if sum(1 for a, c in ((1, 0), (-1, 0), (0, 1), (0, -1)) if grid[y + c][x + a] in '.drc' and (x + a, y + c) not in objs) < 3: continue
            disp.append([x, y]); objs[(x, y)] = 'display_stand'
        base['displays'] = disp
        print('player shop displays', len(disp))
    if base.pop('_yard', False):
        ox, oy = base['at']; W, H = ART[base['art']]['tiles']
        stations = ['hearth', 'furnace', 'anvil', 'workbench', 'quern', 'bank_chest', 'oven']
        # yard: the row(s) behind the house (north), fenced by the house's own back wall and the yard edge
        cells = sorted([(x, y) for x in range(ox - 6, ox + W + 6) for y in range(oy - 6, oy + H)
                        if not (ox - 1 <= x <= ox + W and oy - 1 <= y <= oy + H)],
                       key=lambda c: (abs(c[0] - (ox + W / 2)) + abs(c[1] - oy) * 0.8))
        put = 0
        for (x, y) in cells:
            if put == len(stations): break
            if free_tile(x, y) and not wall_t[y, x] and (x + y) % 2 == 0:   # 0.3.13 checkerboard: no station boxed in by others
                base['props'].append(dict(object=stations[put], at=[x, y])); objs[(x, y)] = stations[put]; put += 1
        print('player house stations', put, 'of', len(stations))

# ---------------------------------------------------------------- market + props (v3.1 designer props)
MARKET = []
def addo(name, x, y, allow_road=False):
    if free_tile(x, y, allow_road):
        objs[(x, y)] = name; return True
    return False
px2t = lambda x, y: (int(x // T), int(y // T))
# the animated fountain at the plaza centre
for (ax, ay) in [(0, 0), (-1, 0), (0, 1), (-1, 1)]:
    if addo('hf_fountain', CXt + ax, CYt + ay, True): MARKET.append((CXt + ax, CYt + ay)); break
cols = ['purple', 'red', 'green', 'blue', 'orange']
for i in range(10):   # stalls in an arc along the plaza's south side
    a_ = 25 + i * 14; tx, ty = px2t(CX + pr * 1.25 * math.cos(math.radians(a_)), CY + pr * .95 * math.sin(math.radians(a_)) + 8)
    for (ax, ay) in [(0, 0), (0, 1), (1, 0), (-1, 0)]:
        if addo('hf_v3_stall_' + cols[i % 5], tx + ax, ty + ay, True): MARKET.append((tx + ax, ty + ay)); break
for nm, dx, dy in [('hf_v3_crate_pile', -70, 30), ('hf_v3_barrels', 60, 30), ('hf_v3_cart', -90, 0), ('hf_v3_bench', 36, -34), ('hf_v3_bench', -52, -34),
                   ('exchange_board', 70, -20), ('hf_v3_well_round', -80, -30), ('hf4_statue_knight', 96, 8)]:
    tx, ty = px2t(CX + dx, CY + dy)
    for (ax, ay) in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1)]:
        if addo(nm, tx + ax, ty + ay, True): MARKET.append((tx + ax, ty + ay)); break
# gardens, trees, crates, carts between the houses; trees outside the wall
FILL_IN = ['hf4_tree_oak', 'hf4_tree_elm', 'hf4_tree_birch', 'hf4_tree_young', 'hf_v3_hedge', 'hf_v3_garden_bed', 'hf_v3_veg_patch', 'hf_v3_well_round', 'hf_v3_cart', 'hf_v3_crate_pile',
           'hf_v3_barrels', 'hf_bush_a', 'hf_bush_flowers', 'hf_crate_broken', 'hf_barrel', 'hf4_tree_pine']
FILL_OUT = ['hf4_tree_oak', 'hf4_tree_elm', 'hf4_tree_pine', 'hf4_tree_birch', 'hf4_tree_dead', 'hf_bush_a', 'hf_v3_veg_patch', 'hf_v3_hedge', 'hf_v3_cart', 'hf_v3_crate_pile']
for k in range(2600):
    x, y = rnd.randrange(1, N - 1), rnd.randrange(1, N - 1)
    if inner[y, x]:
        if rnd.random() < .22 and not roadT[y, x]: addo(rnd.choice(FILL_IN), x, y)
    elif not OUTER_KEEP[y * T + 8, x * T + 8] and rnd.random() < .12: addo(rnd.choice(FILL_OUT), x, y)
# 0.3.13 v4: banners flank the civic doors, lamp posts on the road verge (never on the road)
BANNER = {'palace': 'hf4_banner_gold', 'guild': 'hf4_banner_red', 'townhall': 'hf4_banner_blue', 'church': 'hf4_banner_gold', 'bank': 'hf4_banner_blue'}
for b in blds:
    if b['role'] in BANNER:
        dx_, dy_ = b['door']
        for sx in (dx_ - 2, dx_ + 2, dx_ - 3, dx_ + 3):
            addo(BANNER[b['role']], sx, dy_ + 1)
_rb = roadT.astype(bool)
VERGE = ndi.binary_dilation(_rb, iterations=2) & ~ndi.binary_dilation(_rb, iterations=1)
_lamps = 0
for y in range(2, N - 2, 1):
    for x in range(2, N - 2, 1):
        if VERGE[y, x] and inner[y, x] and (x * 7 + y * 13) % 9 == 0 and addo('hf4_lamp_post_double' if (x + y) % 3 == 0 else 'hf4_lamp_post', x, y): _lamps += 1
print('v4 lamps', _lamps)
# 0.3.13 v4: a wall banner hung on the inner face of the city wall either side of every gate
_wb = 0
for side, line in GATE_LINE.items():
    xs = [p_[0] for p_ in line]; ys = [p_[1] for p_ in line]
    if side in ('north', 'south'):
        inw = 1 if side == 'north' else -1; y_ = ys[0]
        for x_, d_ in ((min(xs), -1), (max(xs), 1)):
            for k_ in (2, 3, 4):
                if any(addo('hf4_banner_wall', x_ + d_ * k_, y_ + inw * j_) for j_ in (1, 2)): _wb += 1; break
    else:
        inw = 1 if side == 'west' else -1; x_ = xs[0]
        for y_, d_ in ((min(ys), -1), (max(ys), 1)):
            for k_ in (2, 3, 4):
                if any(addo('hf4_banner_wall', x_ + inw * j_, y_ + d_ * k_) for j_ in (1, 2)): _wb += 1; break
print('v4 wall banners', _wb)
# round towers on the wall
for (tx, ty) in TOWER_T: objs[(tx, ty)] = 'hf_wall_tower'
print('wall towers', len(TOWER_T))

# 0.3.13: keep every building prop (yard stations) open - drop fill props that box one in
_STA = {'display_stand', 'hearth', 'furnace', 'anvil', 'workbench', 'quern', 'bank_chest', 'oven'}
for b in out_b:
    for pr_ in b.get('props', []):
        x_, y_ = pr_['at']
        for a_, c_ in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q_ = (x_ + a_, y_ + c_)
            if q_ in objs and objs[q_] not in _STA and objs[q_] != 'hf_wall_tower' and q_ not in MARKET: print('unbox', b.get('id'), q_, objs.pop(q_))
# ---------------------------------------------------------------- reachability (4-connected, objects block)
def walk(x, y):
    if not (0 <= x < N and 0 <= y < N): return False
    if (x, y) in objs: return False
    c = grid[y][x]
    return c in '.drc'
blocked_obj = set(objs)
inside_walk = {}
for b in out_b:
    for y, r in enumerate(ART[b['art']]['plan'] if not b['flip'] else flip_plan(ART[b['art']]['plan'])):
        for x, c in enumerate(r):
            p = (b['at'][0] + x, b['at'][1] + y)
            if c in 'oD' and not (c == 'D' and b.get('closed')): inside_walk[p] = True
for b in out_b:
    for key in ('keeper_at', 'altar'):
        if key in b and not b.get('no_keeper'): inside_walk.pop(tuple(b[key]), None)
    for pr in b['props']: inside_walk.pop(tuple(pr['at']), None)
def walkable(x, y): return walk(x, y) or (x, y) in inside_walk
start = tuple(gates['south'][1])
seen = {start}; q = [start]
while q:
    x, y = q.pop()
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        n2 = (x + dx, y + dy)
        if n2 not in seen and walkable(*n2): seen.add(n2); q.append(n2)
fails = []
for side, g in gates.items():
    if tuple(g[1]) not in seen: fails.append('gate ' + side)
for b in out_b:
    if not b.get('closed') and tuple(b['door'][0]) not in seen: fails.append('door ' + b['id'])
    if not b.get('no_keeper') and not b.get('closed') and tuple(b['stand']) not in seen: fails.append('stand ' + b['id'])
for b in out_b:
    for d in b.get('displays', []):
        if not any((d[0] + a, d[1] + c) in seen for a, c in ((1, 0), (-1, 0), (0, 1), (0, -1))): fails.append('display %s' % d)
    for pr in b['props']:
        p = pr['at']
        if not any((p[0] + a, p[1] + c) in seen for a, c in ((1, 0), (-1, 0), (0, 1), (0, -1))): fails.append('prop %s %s' % (b['id'], pr))
road_fails = [b['art'] + str(b['at']) for b in blds if (road[b['px'][1]:b['px'][1] + drawn(b['art'], b['flip']).shape[0], b['px'][0]:b['px'][0] + drawn(b['art'], b['flip']).shape[1]] & drawn(b['art'], b['flip'])[:SH - b['px'][1], :SW - b['px'][0]]).any()]

# ---------------------------------------------------------------- write data
OBJ_CH = {}
chars = iter('ABCEFHIJKLMNOPQRSTUVXYZabefhijklmnpqstuvwxyz0123456789!$%&()*+,/;<>?@[]_{|}')
for o in sorted(set(objs.values()) - {'display_stand', 'hearth', 'furnace', 'anvil', 'workbench', 'quern', 'bank_chest', 'oven'}):
    OBJ_CH[o] = next(chars)
GATE_SET = {tuple(p) for v in GATES_RING.values() for p in v}
for p in GATE_SET: grid[p[1]][p[0]] = 'c'
rows = []
for y in range(N):
    r = ''
    for x in range(N):
        c = grid[y][x]
        o = objs.get((x, y))
        if o in OBJ_CH: r += OBJ_CH[o]
        elif c == 'W': r += '#'
        elif c == 'r': r += '='
        elif c == 'c': r += ':'
        elif (x, y) in GATE_SET: r += 'G'
        elif c == 'B': r += 'g'
        elif c == 'd': r += 'd'
        else: r += 'g'
    rows.append(r)
ground_of = lambda x, y: 'dirt' if grid[y][x] == 'd' else 'grass'
objects = {}
for o, ch in OBJ_CH.items():
    xs = [p for p, v in objs.items() if v == o]
    objects[ch] = {'object': o, 'ground': 'capital_wall' if o == 'hf_wall_tower' else ('cobble' if xs and all(roadT[p[1], p[0]] for p in xs) else 'grass')}
town_art = dict(note='0.3.11 per-design tile plans for the layered town buildings (tools/world/build_highfen_v4.py). plan: # wall, o floor, D door, . outside',
                buildings=ART)
# 0.3.11 v3.1b ring QA (visual): walk the octagon centreline (L1 = S+.5, 2 px steps) over the composited
# wall art alpha (rows + gatehouses + joins + fits + towers); every sample must hit wall pixels except
# inside the 4 gate passages
_ring_px = wallpx.copy()
_cl = []
_m = S_OCT + .5
_pts = [(RX + .5, -(_m - RX - .5)), (RX + .5, _m - RX - .5), (_m - RY - .5, RY + .5), (-(_m - RY - .5), RY + .5),
        (-RX - .5, _m - RX - .5), (-RX - .5, -(_m - RX - .5)), (-(_m - RY - .5), -RY - .5), (_m - RY - .5, -RY - .5)]
_gaps = []; _gate_hits = set(); _n = 0
for i in range(8):
    (ax, ay), (bx, by) = _pts[i], _pts[(i + 1) % 8]
    _L = int(math.hypot(bx - ax, by - ay) * T / 2) + 1
    for k in range(_L):
        vx = CXt + ax + (bx - ax) * k / _L; vy = CYt + ay + (by - ay) * k / _L
        px, py = int(vx * T), int(vy * T) + 4     # +4: the wall top sits just above the vertex line
        _n += 1
        gt = [g for g, v in GATE_TILES.items() if any(abs(vx - (x + .5)) <= 1.6 and abs(vy - (y + .5)) <= 1.6 for x, y in v)]
        if gt: _gate_hits.add(gt[0]); continue
        if not _ring_px[max(0, py - 6):py + 6, px - 2:px + 3].any(): _gaps.append((round(vx, 1), round(vy, 1)))
RING_QA = dict(samples=_n, gaps=_gaps[:20], gap_count=len(_gaps), gates=sorted(_gate_hits))
print('ring QA', RING_QA)
assert not _gaps and len(_gate_hits) == 4, RING_QA
SP = os.path.join(REPO, 'data/sprites.json'); OB = os.path.join(REPO, 'data/objects.json')
s_ = json.load(open(SP)); o_ = json.load(open(OB))
V4N = {'lamp_post': 'Lamp post', 'lamp_post_double': 'Lamp post', 'statue_knight': 'Statue of a knight', 'banner_red': 'Banner', 'banner_blue': 'Banner',
       'banner_gold': 'Banner', 'banner_wall': 'Banner', 'tree_dead': 'Dead tree'}
for f in sorted(x for x in os.listdir(os.path.join(DST, 'props_v4')) if x.endswith('.png')):
    n = f[3:-4]; oid = 'hf4_' + n; im = Image.open(os.path.join(DST, 'props_v4', f))
    s_['objects'][oid] = {'path': f'{RES}/props_v4/{f}', 'frame_size': [im.width, im.height], 'frames': 1, 'anchor': 'bottom',
                          'note': '0.3.13 designer Highfen v4 prop (art_handoff/towns/highfen/v4)'}
    o_['objects'][oid] = {'name': V4N.get(n, 'Tree' if n.startswith('tree') else n.replace('_', ' ').capitalize()), 'sprite': oid, 'blocks': True, 'type': 'prop'}
json.dump(s_, open(SP, 'w'), indent=1); json.dump(o_, open(OB, 'w'), indent=1)
_ta_p = os.path.join(REPO, 'data/town_art.json')   # 0.3.12 merge: other towns (Saltmere v2) share this file
_ta = json.load(open(_ta_p)) if os.path.exists(_ta_p) else dict(buildings={})
_ta['buildings'] = {k: v for k, v in _ta.get('buildings', {}).items() if k not in ART}; _ta['buildings'].update(ART)
_ta['note'] = town_art['note']
json.dump(_ta, open(_ta_p, 'w'), indent=1)
old = json.load(open(os.path.join(REPO, 'data/towns/highfen.json')))
HF_ORIGIN = [144 - (N - 72) // 2, -46 - (N - 72) // 2]   # 0.3.13 origin, same centre
spawn = [PLAZA[0] // T, PLAZA[1] // T + 3]
while not walk(*spawn) or tuple(spawn) not in seen: spawn[1] += 1
town = dict(id='highfen', name='Highfen', kind='capital', origin=HF_ORIGIN, spawn=[HF_ORIGIN[0] + spawn[0], HF_ORIGIN[1] + spawn[1]],
            tiles={'g': 'grass', 'd': 'dirt', '#': 'capital_wall', '=': 'road_stone', ':': 'cobble', 'G': 'gate_capital'}, objects=objects, roof='#b8a888', building_style='capital',
            specialists=old['specialists'], price_bias=old['price_bias'],
            tagline='The walled capital at the heart of the realm: a round city of soot-dark stone, the palace at its centre, the Guild of Knights, a market by the gate and houses ringing the wall.',
            theme='highfen', gates=gates,
            gate_walls=GATES_RING,
            gate_tiles=GATE_TILES, ring_qa=RING_QA,
            art=dict(market=[list(p) for p in MARKET], plaza_px=list(PLAZA[:2]), ground_decal=f'{RES}/ground_decal.png', ysort=YSORT, fades=FADES),
            buildings=out_b, rows=rows,
            note="0.3.11 generated by tools/world/build_highfen_v4.py from the designer's Highfen set (art_handoff/towns/highfen, copied to assets/sprites/towns/highfen)")
json.dump(town, open(os.path.join(REPO, 'data/towns/highfen.json'), 'w'), indent=1)
# debug image
os.makedirs(os.path.join(REPO, 'build'), exist_ok=True)
dbg = Image.new('RGBA', (SW, SH), (60, 80, 50, 255))
from PIL import ImageDraw as _ID
_dd = _ID.Draw(dbg)
for y in range(N):
    for x in range(N):
        col = {'r': (150, 140, 120, 255), 'c': (175, 170, 160, 255), 'W': (70, 64, 70, 255)}.get(grid[y][x])
        if (x, y) in GATE_SET: col = (200, 160, 60, 255)
        if col: _dd.rectangle([x * T, y * T, x * T + T - 1, y * T + T - 1], fill=col)
items = [(b['px'][1] + BM[b['art']]['px'][1], 'b', b) for b in blds] + [(y * T + T, 'p', (o, x, y)) for (x, y), o in objs.items()]
seg_items = []
for base, kind, it in sorted(items + seg_items, key=lambda t: t[0]):
    if kind == 's':
        dbg.alpha_composite(L('walls', it[0]), (rox + it[1]['offset'][0], roy + it[1]['offset'][1]))
    elif kind == 'b':
        for l in BM[it['art']]['layers']:
            im = L('buildings', l); im = im.transpose(Image.FLIP_LEFT_RIGHT) if it['flip'] else im
            dbg.alpha_composite(im, tuple(it['px']))
    else:
        o, x, y = it
        nm = o[3:] if o.startswith('hf_') else None
        if nm and os.path.exists(os.path.join(SRC, 'props', nm + '.png')):
            im = L('props', nm); dbg.alpha_composite(im, (int(x * T + 8 - im.width / 2), int(y * T + T - im.height)))
        else:
            from PIL import ImageDraw; ImageDraw.Draw(dbg).rectangle([x * T + 3, y * T + 3, x * T + 12, y * T + 12], fill=(220, 60, 60, 255))
dbg.save(os.path.join(REPO, 'build/highfen_layout_check.png'))
print('buildings', len(blds), 'objects', len(objs), 'road overlaps', road_fails, 'reach fails', fails)
sys.exit(1 if road_fails or fails else 0)
