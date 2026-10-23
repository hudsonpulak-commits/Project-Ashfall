"""0.3.14 Cinderholt redesign + the Northern Guard camp, built from the designer's Cinderholt v1 set
(art_handoff/towns/cinderholt, read-only; copied to assets/sprites/towns/cinderholt) and the repo's Cinder
cliff variant (assets/sprites/cliffs/cinder) for the ridge.

Geometry follows the designer's preview.py (ring 28x22, same wobble, gates, towers every 36 deg, loose cobble
roads, ash drifts) with one change: the camp sits NORTH of town on the plateau above the cinder ridge
(docs/specs/Lore_2026-10-21.md "Camp just north of Cinderholt"), reached by the cliff stairs above the N gate.
Ridge = one straight 2-tile cliff face (16x32 faces) across the whole rect, so there are no diagonal gaps.
Every building is walk-in (1-tile invisible collision rim, roof fade, 0.3.13 walls-behind-player).

Writes assets/sprites/towns/cinderholt/..., data/town_art.json (merged), data/towns/cinderholt.json,
data/churches.json, data/town_npcs.json, data/sprites.json + data/objects.json (ch_/ng_ props),
build/cinderholt_layout_check.png. Exits 1 on overlap, unreachable door/stand/prop/gate, a ring gap or leak
(town basalt ring and camp palisade)."""
import json, math, os, random, shutil, sys, collections, itertools
from collections import deque
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SRC = '/workspace/art_handoff/towns/cinderholt'
DST = os.path.join(REPO, 'assets/sprites/towns/cinderholt')
RES = 'res://assets/sprites/towns/cinderholt'
CLIFF = os.path.join(REPO, 'assets/sprites/cliffs/cinder')
T = 16
GW, GH = 84, 90
SW, SH = GW * T, GH * T
CXt, CYt, RX, RY = 42, 62, 28, 22
OLD_CENTER = (330, -200)
ORIGIN = [OLD_CENTER[0] - CXt, OLD_CENTER[1] - CYt]
RF = 34                       # ridge face rows RF, RF+1 (blocked); lip RF-1; shadow RF+2
STAIRS = set(range(CXt - 2, CXt + 2))
KX, KY, KA, KB, KC = 42, 17, 14, 10, 19
os.makedirs('/tmp/ch', exist_ok=True)

# ---------------------------------------------------------------- copy art (never write into art_handoff)
for sub in ('tiles', 'buildings', 'props'):
    os.makedirs(os.path.join(DST, sub), exist_ok=True)
    for f in sorted(os.listdir(os.path.join(SRC, sub))):
        if f.endswith('.png'): shutil.copyfile(os.path.join(SRC, sub, f), os.path.join(DST, sub, f))
shutil.copyfile(os.path.join(SRC, 'manifest.json'), os.path.join(DST, 'manifest_designer.json'))
shutil.copyfile(os.path.join(SRC, 'README.md'), os.path.join(DST, 'README_designer.md'))
# roads a shade or two brighter than the buildings (adjusted on the repo copy only)
def _lum(a): m = a[..., 3] > 0; return float((a[..., :3][m] @ [.299, .587, .114]).mean())
_bl = np.mean([_lum(np.array(Image.open(os.path.join(DST, 'buildings', f)).convert('RGBA')).astype(float))
               for f in os.listdir(os.path.join(DST, 'buildings')) if f.endswith(('_walls.png', '_roof.png'))])
BRIGHT = {}
for n, ratio in (('ch_diag_cobble_road', 1.42), ('ch_cobble_fill', 1.42), ('ch_diag_ash_drift', 1.36), ('ch_ash_fill', 1.36), ('ng_diag_yard_dirt', 1.32), ('ng_yard_fill', 1.32)):
    p = os.path.join(DST, 'tiles', n + '.png')
    if not os.path.exists(p): continue
    a = np.array(Image.open(p).convert('RGBA')).astype(float); l0 = _lum(a); k = max(1.0, _bl * ratio / l0)
    a[..., :3] = np.clip(a[..., :3] * k, 0, 255); Image.fromarray(a.astype(np.uint8)).save(p); BRIGHT[n] = [round(l0, 1), round(l0 * k, 1)]
print('building lum %.1f; roads lum before/after' % _bl, BRIGHT)
M = json.load(open(os.path.join(SRC, 'manifest.json')))
ALLB = M['buildings'] + M['camp']['buildings']
BM = {b['name']: b for b in ALLB}; GM = M['wall']['gates']
_LC = {}
def L(sub, n):
    n = n if n.endswith('.png') else n + '.png'
    if (sub, n) not in _LC: _LC[(sub, n)] = Image.open(os.path.join(CLIFF if sub == 'cliff' else os.path.join(DST, sub), n)).convert('RGBA')
    return _LC[(sub, n)]
sys.path.insert(0, os.path.join(SRC, 'src'))
import diagtiles as dg

# ---------------------------------------------------------------- per-design plans: walk-in floor + invisible rim
def plan_of(b):
    n = b['name']; E = b['footprint_origin_px'][1]; W, H = b['tiles']; d = tuple(b['door_tile']); H = d[1] + 1
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
ART = {}
for b in ALLB:
    ART[b['name']] = dict(tiles=[b['tiles'][0], b['door_tile'][1] + 1], px=b['px'], origin_y=b['footprint_origin_px'][1] - T, inset_x=T, door_tile=b['door_tile'], storeys=b['storeys'],
                          floor=f"{RES}/buildings/{b['layers'][0]}", walls=f"{RES}/buildings/{b['layers'][1]}",
                          fade=[f"{RES}/buildings/{l}" for l in b['fade_group']],
                          plan=plan_of(b), note='0.3.14 Cinderholt v1: plan has a 1-tile invisible collision rim (top/left/right)')
def flip_plan(rows): return [r[::-1] for r in rows]
def LB(l): return L('buildings', l)

# ---------------------------------------------------------------- terrain (designer preview.py geometry, seed 21)
rnd = random.Random(21); nr = np.random.RandomState(21)
VY, VX = np.mgrid[:GH + 1, :GW + 1].astype(float)
ang = np.degrees(np.arctan2((VY - CYt) / RY, (VX - CXt) / RX)) % 360
wob = 1 + .03 * np.sin(np.radians(ang) * 5 + 2) + .015 * np.sin(np.radians(ang) * 11)
def ell(rx, ry): return np.hypot((VX - CXt) / rx, (VY - CYt) / ry) / wob <= 1
def octo(d): return (np.abs(VX - KX) <= KA + d) & (np.abs(VY - KY) <= KB + d) & (np.abs(VX - KX) + np.abs(VY - KY) <= KC + d * 1.41)
CR = np.array([[0, 1, 0], [1, 1, 1], [0, 1, 0]], bool)
def desaddle(V):
    for _ in range(6):
        F = dg.frames_of(V); bad = (F == 5) | (F == 10)
        if not bad.any(): break
        for y, x in zip(*np.nonzero(bad)): V[y:y + 2, x:x + 2] = True
    return V
def jline(pts, hw, j=.35, seed=0):
    r = random.Random(seed); out = [pts[0]]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(1, int(math.hypot(x1 - x0, y1 - y0) / 4))
        for i in range(1, n + 1):
            f = i / n; out.append((x0 + (x1 - x0) * f + (r.uniform(-j, j) if i < n else 0), y0 + (y1 - y0) * f + (r.uniform(-j, j) if i < n else 0)))
    return dg.line_mask(VY.shape, out, hw)
inside = ell(RX - 1, RY - 1)
WV = ell(RX + 1, RY + 1) & ~ell(RX - 1, RY - 1); GATE = []
GATE_TILES = {}; GATE_LINE = {}; ROOF_TILES = {}; SIDE = {270: 'north', 90: 'south', 0: 'east', 180: 'west', 'camp': 'camp'}
for g, view in [(270, 'back'), (90, 'front'), (0, 'side'), (180, 'side')]:
    side = SIDE[g]
    if view == 'side':
        c = int(round(CXt + math.cos(math.radians(g)) * RX)); c = c - 1 if g == 0 else c; cy = CYt
        WV[cy - 6:cy + 7, c - 3:c + 5] = False; WV[cy - 6:cy + 7, c:c + 2] = True; WV[cy - 1:cy + 2, c - 1:c + 3] = False
        GATE.append(('ch_gate_side', int((c + .5) * 16) - 24, cy * 16 - 57, g, cy))
        GATE_TILES[side] = [[x, y] for x in (c - 1, c, c + 1) for y in (cy - 1, cy)]
        GATE_LINE[side] = [[c, cy - 1], [c, cy]]
        ROOF_TILES[side] = [[x, y] for x in range(c - 1, c + 2) for y in (cy - 1, cy)]
    else:
        r = int(round(CYt + math.sin(math.radians(g)) * RY)); r = r - 1 if g == 90 else r; cx = CXt
        WV[r - 3:r + 5, cx - 6:cx + 7] = False; WV[r:r + 2, cx - 6:cx + 7] = True; WV[r - 1:r + 3, cx - 1:cx + 2] = False
        GATE.append((f'ch_gate_{view}', cx * 16 - 32, int((r + .5) * 16) - 16, g, r))
        GATE_TILES[side] = [[x, y] for x in (cx - 1, cx) for y in (r - 1, r, r + 1)]
        GATE_LINE[side] = [[cx - 1, r], [cx, r]]
        ROOF_TILES[side] = [[x, y] for x in (cx - 1, cx) for y in range(r - 1, r + 3)]
# camp palisade octagon, W side gate
PV = octo(.5) & ~octo(-1.0)
c = KX - KA; cy = KY
PV[cy - 1:cy + 2, c - 1:c + 3] = False
GATE.append(('ng_gate_side', int((c + .5) * 16) - 24, cy * 16 - 57, 'camp', cy))
GATE_TILES['camp'] = [[x, y] for x in (c - 1, c, c + 1) for y in (cy - 1, cy)]
GATE_LINE['camp'] = [[c, cy - 1], [c, cy]]; ROOF_TILES['camp'] = [[x, y] for x in range(c - 1, c + 2) for y in (cy - 1, cy)]
campin = octo(-1.5)
G = {g: (x0, y0) for n, x0, y0, g, _ in GATE}
gw = ((G[180][0] - 8) / 16, (G[180][1] + 57) / 16); ge = ((G[0][0] + 56) / 16, (G[0][1] + 57) / 16)
gn = ((G[270][0] + 32) / 16, G[270][1] / 16); gs = ((G[90][0] + 32) / 16, (G[90][1] + 72) / 16)
cgw = ((G['camp'][0] - 8) / 16, (G['camp'][1] + 57) / 16); cge = ((G['camp'][0] + 56) / 16, (G['camp'][1] + 57) / 16)
# ---- roads: loose cobble in town (ring lane, plaza, gate roads, spokes), on over the ridge stairs ----
RV = ell(.62 * RX + .9, .62 * RY + .9) & ~ell(.62 * RX - .9, .62 * RY - .9) | ell(.2 * RX, .2 * RY)
for i, p in enumerate([[gs, (CXt, GH + 1)], [gn, (CXt, RF - 2.5)], [gw, (-1, gw[1])], [ge, (GW + 1, ge[1])],
                       [(CXt, CYt), gs], [(CXt, CYt), gn], [(CXt, CYt), gw], [(CXt, CYt), ge]]):
    RV |= jline(p, 1.05, j=(0 if i == 1 else .35), seed=i)
for a0 in (45, 135, 225, 315):
    RV |= jline([(CXt + RX * .2 * math.cos(math.radians(a0)), CYt + RY * .2 * math.sin(math.radians(a0))), (CXt + RX * .63 * math.cos(math.radians(a0)), CYt + RY * .63 * math.sin(math.radians(a0)))], .8, seed=a0)
for n, x0, y0, g, _ in GATE[:4]:
    if 'side' in n: RV |= dg.line_mask(VY.shape, [((x0 - 8) / 16, (y0 + 57) / 16), ((x0 + 56) / 16, (y0 + 57) / 16)], 1.0)
    else: RV |= dg.line_mask(VY.shape, [((x0 + 32) / 16, y0 / 16), ((x0 + 32) / 16, (y0 + 72) / 16)], .9)
RV &= ~((VY < RF + 2.2) & ~((VX >= min(STAIRS)) & (VX <= max(STAIRS) + 1) & (VY > RF - 2.6)))
# ---- camp + plateau dirt roads (stairs top -> round the camp's SW corner -> W gate; on to the N edge) ----
SW_C = (KX - KA - 5, KY + 8)
YV = jline([(CXt, RF - 1.0), (CXt - 2, RF - 3), (KX - 9, KY + KB + 3), SW_C, (cgw[0] - 1.5, cgw[1] + 2), cgw], .95, seed=40)
YV |= jline([cgw, cge, (KX - 4, KY), (KX + 6, KY)], .9, seed=41) | jline([(KX - 4, KY), (KX - 4, KY - 5)], .8, seed=42) | jline([(KX - 2, KY), (KX + 1, KY + 5)], .8, seed=43)
YV |= jline([(cgw[0] - 1.5, cgw[1]), (cgw[0] - 4, KY - 6), (11, 6), (11, -1)], .95, seed=44)
YV &= ~RV & ~(VY > RF - 1.2) | (YV & (VY <= RF - 0.6) & (np.abs(VX - CXt) < 2.5))
YARD = ((VX - (KX + 6)) / 5.2) ** 2 + ((VY - (KY + 5.5)) / 3.2) ** 2 <= 1
WV &= ~RV; PV &= ~YV
for n, x0, y0, g, c_ in GATE[:4]:
    if 'side' in n: cc = (x0 + 24) // 16; WV[c_ - 6:c_ - 1, cc:cc + 2] = True; WV[c_ + 2:c_ + 7, cc:cc + 2] = True
WV = desaddle(WV); PV = desaddle(PV)
fr = lambda V: dg.frames_of(V)
bits = np.vectorize(lambda f: bin(int(f)).count('1'))
CNT_W = bits(fr(WV)); CNT_P = bits(fr(PV))
nz = ndi.gaussian_filter(nr.rand(GH + 1, GW + 1), 2.6); nz = (nz - nz.min()) / (nz.max() - nz.min())
ASH = (nz > .7) & ~ell(RX - 1.5, RY - 1.5) & ~octo(0) | (nz > .84)

# ---------------------------------------------------------------- wall rows, towers, gates, watchtower
YSORT = []; FADES = []
os.makedirs(os.path.join(DST, 'rows'), exist_ok=True)
for f_ in os.listdir(os.path.join(DST, 'rows')): os.remove(os.path.join(DST, 'rows', f_))
wallpx = np.zeros((SH + 40, SW), bool)
def wall_rows(V, sheet, tag, gates):
    A = L('tiles', sheet); F = dg.frames_of(V)
    for n, x0, y0, g, _ in gates:
        w_, h_ = GM[n]['size_px']
        for y in range(GH):
            for x in range(GW):
                if x * 16 >= x0 and x * 16 + 16 <= x0 + w_ and y * 16 >= y0 and y * 16 + 16 <= y0 + h_ - 8: F[y, x] = 0
    for y in range(GH):
        if not F[y].any(): continue
        xs_ = np.nonzero(F[y])[0]; runs = []; s0 = xs_[0]; pv = xs_[0]
        for x in list(xs_[1:]) + [None]:
            if x is None or x != pv + 1: runs.append((s0, pv + 1)); s0 = x
            if x is not None: pv = x
        for k, (xa, xb) in enumerate(runs):
            row = Image.new('RGBA', ((xb - xa) * T, 30))
            for x in range(xa, xb): row.alpha_composite(A.crop((F[y, x] * 16, 0, F[y, x] * 16 + 16, 30)), ((x - xa) * T, 0))
            nm = f'{tag}_row_{y:02d}_{k}.png'; row.save(os.path.join(DST, 'rows', nm))
            YSORT.append(dict(path=f'{RES}/rows/{nm}', pos=[int(xa * T), int(y * T)], base=T))
            wallpx[y * T:y * T + 30, xa * T:xb * T] |= np.array(row)[..., 3] > 0
    return F
WF = wall_rows(WV, 'ch_diag_basalt_wall', 'wall', GATE[:4]); PF = wall_rows(PV, 'ng_diag_palisade', 'pal', GATE[4:])
wallpx = wallpx[:SH]
TOW = []; TOW_T = []
wy_, wx_ = np.nonzero(WF == 15)
for a_ in range(18, 360, 36):
    if min(abs(((a_ - g + 180) % 360) - 180) for g in (0, 90, 180, 270)) < 14: continue
    x = CXt + RX * math.cos(math.radians(a_)); y = CYt + RY * math.sin(math.radians(a_)); i = np.argmin((wx_ - x) ** 2 + (wy_ - y) ** 2)
    TOW.append((int(wx_[i] * 16 + 8 - 24), int(wy_[i] * 16 + 18 - 64))); TOW_T.append((int(wx_[i]), int(wy_[i])))
for x, y in TOW:
    YSORT.append(dict(path=f'{RES}/tiles/ch_wall_tower.png', pos=[x, y], base=64))
    wallpx[max(0, y):y + 64, x:x + 48] |= np.array(L('tiles', 'ch_wall_tower'))[max(0, -y):, :, 3] > 0
WT = (int((KX + 7) * 16 - 24), int((KY - 8) * 16 + 16 - 88)); WT_T = [(KX + 6, KY - 8), (KX + 7, KY - 8)]
YSORT.append(dict(path=f'{RES}/tiles/ng_watchtower.png', pos=list(WT), base=88))
for n, x0, y0, g, _ in GATE:
    w_, h_ = GM[n]['size_px']
    YSORT.append(dict(path=f'{RES}/tiles/{n}_walls.png', pos=[x0, y0], base=h_))
    FADES.append(dict(path=f'{RES}/tiles/{n}_roof.png', pos=[x0, y0], tiles=ROOF_TILES[SIDE[g]]))
    wallpx[y0:y0 + h_, x0:x0 + w_] |= np.array(L('tiles', n + '_walls'))[..., 3] > 0
TWPX = wallpx.copy()   # ring art (for ring QA); watchtower is interior

wall_t = (CNT_W >= 2) | (CNT_P >= 2)
GSET = {tuple(p) for v in GATE_TILES.values() for p in v}
for n, x0, y0, g, c_ in GATE:
    w_, h_ = GM[n]['size_px']
    for ty in range(max(0, (y0 + 8) // T), (y0 + h_) // T):
        for tx in range(x0 // T, (x0 + w_ + T - 1) // T):
            if (tx, ty) not in GSET and 0 <= ty < GH and 0 <= tx < GW:
                if 'side' in n or abs(ty - c_) <= 1: wall_t[ty, tx] = True
for p in GSET: wall_t[p[1], p[0]] = False
for (tx, ty) in TOW_T + WT_T: wall_t[ty, tx] = True
CLIFF_T = np.zeros((GH, GW), bool)
for x in range(GW):
    if x not in STAIRS: CLIFF_T[RF, x] = CLIFF_T[RF + 1, x] = True
blk = lambda x, y: wall_t[y, x] or CLIFF_T[y, x]
DIAG_FIX = 0
for _ in range(3):
    for y in range(GH - 1):
        for x in range(GW - 1):
            for (p1, p2, o1, o2) in (((x, y), (x + 1, y + 1), (x + 1, y), (x, y + 1)), ((x + 1, y), (x, y + 1), (x, y), (x + 1, y + 1))):
                if blk(*p1) and blk(*p2) and not blk(*o1) and not blk(*o2):
                    cand = [o for o in (o1, o2) if o not in GSET and not (RF - 1 <= o[1] <= RF + 2 and o[0] in STAIRS)]
                    if not cand: continue
                    o = max(cand, key=lambda q: (max(CNT_W[q[1], q[0]], CNT_P[q[1], q[0]]), -abs(q[0] - CXt) - abs(q[1] - CYt)))
                    wall_t[o[1], o[0]] = True; DIAG_FIX += 1

# ---------------------------------------------------------------- tile grid
grid = [['g'] * GW for _ in range(GH)]
CNT_R = bits(fr(RV)); CNT_Y = bits(fr(YV))
for y in range(GH):
    for x in range(GW):
        if CLIFF_T[y, x]: grid[y][x] = '^'
        elif wall_t[y, x]: grid[y][x] = '#'
        elif CNT_R[y, x] >= 3: grid[y][x] = ':'
        elif CNT_Y[y, x] >= 3: grid[y][x] = '='
for p in GSET: grid[p[1]][p[0]] = '=' if p in {tuple(q) for q in GATE_TILES['camp']} else ':'
for x in STAIRS:
    for y in (RF, RF + 1): grid[y][x] = ':'
GATES = dict(north=[[10, 0], [11, 0], [12, 0]], south=[[CXt - 1, GH - 1], [CXt, GH - 1], [CXt + 1, GH - 1]],
             west=[[0, int(gw[1]) - 1], [0, int(gw[1])], [0, int(gw[1]) + 1]], east=[[GW - 1, int(ge[1]) - 1], [GW - 1, int(ge[1])], [GW - 1, int(ge[1]) + 1]])
for v in GATES.values():
    for (x, y) in v:
        if grid[y][x] == 'g': grid[y][x] = ':' if y > RF else '='
INNER_T = (inside[:-1, :-1] & inside[1:, 1:] & inside[:-1, 1:] & inside[1:, :-1])
CAMP_T = (campin[:-1, :-1] & campin[1:, 1:] & campin[:-1, 1:] & campin[1:, :-1])
ZONE_PX = dict(town=np.kron(ell(RX - 1.6, RY - 1.6)[:-1, :-1], np.ones((16, 16), bool)).astype(bool),
               camp=np.kron(campin[:-1, :-1], np.ones((16, 16), bool)).astype(bool))
ZONE_T = dict(town=INNER_T, camp=CAMP_T); ZONE_RC = dict(town=':', camp='=')

# ---------------------------------------------------------------- ground render
def strip(n): return np.array(L('tiles', n))
def layer(V, sheet, skip=None):
    F = dg.frames_of(V); A = strip(sheet); lay = np.zeros((SH, SW, 4), np.uint8)
    for y in range(GH):
        for x in range(GW):
            if F[y, x] and (skip is None or not skip[y, x]): lay[y * 16:y * 16 + 16, x * 16:x * 16 + 16] = A[:, F[y, x] * 16:F[y, x] * 16 + 16]
    return lay
def render_ground(R, Y_):
    fa, fb = strip('ch_scorched_fill_a'), strip('ch_scorched_fill_b'); base = np.zeros((SH, SW, 4), np.uint8); r_ = random.Random(3)
    for y in range(GH):
        for x in range(GW): base[y * 16:y * 16 + 16, x * 16:x * 16 + 16] = fb if r_.random() < .06 else fa
    img = Image.fromarray(base); px = {}
    for nm, V, sh in (('ash', ASH, 'ch_diag_ash_drift'), ('yard', YARD, 'ng_diag_yard_dirt'), ('yroad', Y_, 'ng_diag_yard_dirt'), ('road', R, 'ch_diag_cobble_road')):
        lay = layer(V, sh); img.alpha_composite(Image.fromarray(lay)); px[nm] = lay[..., 3] > 0
    # cinder ridge: lip row, 16x32 faces (stairs in the gap), shadow below
    top = L('cliff', 'cliff_top'); faces = [L('cliff', f'cliff_face_s_{k}') for k in 'abcd']; st = L('cliff', 'cliff_stairs'); sh_ = L('cliff', 'cliff_shadow'); rim = L('cliff', 'cliff_rim_n')
    r2 = random.Random(9)
    for x in range(GW):
        if x not in STAIRS:
            img.alpha_composite(top, (x * T, (RF - 1) * T)); img.alpha_composite(faces[r2.randrange(4)], (x * T, RF * T)); img.alpha_composite(faces[r2.randrange(4)].crop((0, 16, 16, 32)), (x * T, (RF + 1) * T))
            img.alpha_composite(sh_, (x * T, (RF + 2) * T))
        else:
            img.alpha_composite(st, (x * T, RF * T))
    for n, x0, y0, g, _ in GATE: img.alpha_composite(L('tiles', n + '_floor'), (x0, y0))
    return img, px
img0, gpx = render_ground(RV, YV)
roadpx = gpx['road'] | gpx['yroad']; yardpx = gpx['yard']
cliffpx = np.zeros((SH, SW), bool); cliffpx[(RF - 1) * T:(RF + 2) * T] = True
for x in STAIRS: cliffpx[(RF - 1) * T:(RF + 2) * T, x * T:x * T + T] = False

# ---------------------------------------------------------------- building placement (tile-snapped)
occ = ndi.binary_dilation(roadpx | wallpx | cliffpx, iterations=2) | yardpx
for n, x0, y0, g, _ in GATE: w_, h_ = GM[n]['size_px']; occ[max(0, y0 - 4):y0 + h_ + 4, max(0, x0 - 20):x0 + w_ + 20] = True
for x, y in TOW: occ[max(0, y):y + 64, max(0, x):x + 48] = True
occ[WT[1]:WT[1] + 88, WT[0]:WT[0] + 48] = True
tile_used = np.array([[grid[y][x] in '#^' for x in range(GW)] for y in range(GH)])
reserved = set(); blds = []
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
def spur_route(fx, fy, rc):
    if not (0 <= fx < GW and 0 <= fy < GH): return None
    prev = {(fx, fy): None}; dq = deque([(fx, fy)])
    while dq:
        c = dq.popleft()
        if grid[c[1]][c[0]] == rc:
            r = []; k = c
            while k: r.append(k); k = prev[k]
            return r[::-1]
        for dx, dy in ((0, 1), (1, 0), (-1, 0), (0, -1)):
            q = (c[0] + dx, c[1] + dy)
            if 0 <= q[0] < GW and 0 <= q[1] < GH and q not in prev and not tile_used[q[1], q[0]] and grid[q[1]][q[0]] in 'g' + rc:
                prev[q] = c; dq.append(q)
    return None
def place(n, tx, ty, flip=False, role=None, reach=80, quiet=False, zone='town'):
    al = drawn(n, flip); h, w = al.shape; E = BM[n]['footprint_origin_px'][1]; rc = ZONE_RC[zone]
    rows, tiles = plan_tiles(n, flip); dl = door_local(rows); PWt, PHt = len(rows[0]), len(rows)
    for r in range(0, reach, 2):
        nst = max(1, int(2 * math.pi * r / 8))
        for k in range(nst):
            t = 360.0 * k / nst
            px = tx * T + r * math.cos(math.radians(t)) - w / 2; py = ty * T + r * math.sin(math.radians(t)) - h / 2
            ox, oy = int(round(px / T)) - 1, int(round((py + E) / T)) - 1
            x0, y0 = (ox + 1) * T, (oy + 1) * T - E
            if ox < 1 or oy < 1 or ox + PWt > GW - 1 or oy + PHt > GH - 4 or y0 < 0 or x0 + w > SW: continue
            if (occ[y0:y0 + h, x0:x0 + w] & al).any(): continue
            if not ZONE_PX[zone][y0:y0 + h, x0:x0 + w][al].all(): continue
            bad = False
            for (lx, ly) in tiles:
                q = (ox + lx, oy + ly)
                if tile_used[q[1], q[0]] or q in reserved or grid[q[1]][q[0]] != 'g' or not ZONE_T[zone][q[1], q[0]]: bad = True; break
            if bad: continue
            dx_, dy_ = ox + dl[0], oy + dl[1]
            front = [(dx_, dy_ + k) for k in (1, 2, 3)]
            if tile_used[front[0][1], front[0][0]] or grid[front[0][1]][front[0][0]] not in 'g' + rc or grid[front[1][1]][front[1][0]] not in 'g' + rc or (role == 'church' and grid[front[2][1]][front[2][0]] not in 'g' + rc): continue
            for (lx, ly) in tiles: tile_used[oy + ly, ox + lx] = True
            route = spur_route(dx_, dy_ + 1, rc)
            if route is None:
                for (lx, ly) in tiles: tile_used[oy + ly, ox + lx] = False
                continue
            occ[y0:y0 + h, x0:x0 + w] |= ndi.binary_dilation(al, iterations=3)
            for (lx, ly) in tiles: reserved.add((ox + lx, oy + ly))
            for q in route: reserved.add(q)
            d = dict(art=n, flip=flip, at=[ox, oy], role=role, px=[x0, y0], rows=rows, door=[dx_, dy_], route=route, zone=zone)
            blds.append(d); return d
    if not quiet: print('no room for', n, role)
    return None
CIVIC = [('ch_smithy', (26, 70), 'smithy', False, 'town'), ('ch_church', (42, 50), 'church', False, 'town'), ('ch_bank', (53, 55), 'bank', False, 'town'), ('ch_general_store', (31, 55), 'general', False, 'town'),
         ('ch_cookhouse', (57, 70), 'cook', False, 'town'), ('ch_player_shop', (36, 77), 'player', False, 'town'),
         ('ch_guard_post', (49, 78), 'guard', False, 'town'), ('ch_house_12', (23, 61), 'body', False, 'town'), ('ch_house_04', (61, 61), 'shields', False, 'town'),
         ('ng_command_tent', (38, 11), 'command', False, 'camp'), ('ng_barracks_hut', (50, 12), 'barracks', False, 'camp'),
         ('ng_tent_03', (33, 15), 'tent', False, 'camp'), ('ng_tent_04', (53, 21), 'tent', False, 'camp'), ('ng_tent_01', (35, 22), 'tent', False, 'camp'), ('ng_tent_02', (44, 25), 'tent', False, 'camp'),
         ('ng_tent_01', (47, 8), 'tent', True, 'camp'), ('ng_tent_03', (31, 19), 'tent', True, 'camp')]
left = []
for n, p, role, flip, zone in CIVIC:
    if not place(n, *p, flip=flip, role=role, reach=400 if role != 'tent' else 260, zone=zone):
        if role != 'tent' or not flip: left.append((n, role))
HOUSES = [h for h in M['houses']]
rr = random.Random(7)
road_d = ndi.distance_transform_edt(~roadpx)
cands = [(x, y) for y in range(RF + 6, GH - 6, 2) for x in range(6, GW - 6, 2) if INNER_T[y, x]]
rr.shuffle(cands); cands.sort(key=lambda c: road_d[c[1] * 16, c[0] * 16])
use = collections.Counter(); nh = 0
for rnd_pass in range(3):
    for n in HOUSES:
        if rnd_pass and use[n] >= rnd_pass + 1: continue
        for c in cands:
            if place(n, c[0], c[1], flip=(use[n] % 2 == 1), role='home', reach=48, quiet=True):
                use[n] += 1; nh += 1; break
        else:
            if not rnd_pass and use[n] == 0: left.append((n, 'home'))
print('houses', nh, 'designs used', len(set(b['art'] for b in blds)), 'not placed', left)

# ---------------------------------------------------------------- doorway spurs
SPm = np.zeros_like(RV); SPc = np.zeros_like(RV)
for b in blds:
    route = b['route']; dx_, dy_ = b['door']
    pts = [(dx_ + .5, dy_ + .3), (dx_ + .5, dy_ + 1.5)] + [(c[0] + .5 + rnd.uniform(-.2, .2), c[1] + .5 + rnd.uniform(-.2, .2)) for c in route[1:-1]] + [(route[-1][0] + .5, route[-1][1] + .5)]
    (SPc if b['zone'] == 'camp' else SPm).__ior__(dg.line_mask(VY.shape, pts, .62))
    for q in route:
        if grid[q[1]][q[0]] == 'g': grid[q[1]][q[0]] = ZONE_RC[b['zone']]
BT = set()
for b in blds:
    for y, r in enumerate(b['rows']):
        for x, c in enumerate(r):
            if c != '.': BT.add((b['at'][0] + x, b['at'][1] + y))
U = RV | (SPm & ~WV); UY = YV | (SPc & ~PV)
for V in (U, UY):
    for _ in range(4):
        F = dg.frames_of(V); bad = (F == 5) | (F == 10)
        if not bad.any(): break
        for y, x in zip(*np.nonzero(bad)): V[y:y + 2, x:x + 2] = True
U &= ~((VY < RF + 2.2) & ~((VX >= min(STAIRS)) & (VX <= max(STAIRS) + 1) & (VY > RF - 2.6)))
img, gpx = render_ground(U, UY)
roadpx = gpx['road'] | gpx['yroad']
dec = np.array(img)
ex = np.minimum(np.arange(SW), SW - 1 - np.arange(SW))[None, :] / (2 * T)
ey = np.minimum(np.arange(SH), SH - 1 - np.arange(SH))[:, None] / (2 * T)
fx = np.clip(np.minimum(ex, ey), 0, 1)
dec[..., 3] = (dec[..., 3] * (.2 + .8 * fx)).astype(np.uint8)
Image.fromarray(dec).save(os.path.join(DST, 'ground_decal.png'))
CNT_U = bits(fr(U)); CNT_UY = bits(fr(UY))
for y in range(GH):
    for x in range(GW):
        if grid[y][x] == 'g' and (x, y) not in BT:
            if CNT_U[y, x] >= 3: grid[y][x] = ':'
            elif CNT_UY[y, x] >= 3: grid[y][x] = '='

# ---------------------------------------------------------------- roles -> buildings
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
_oldp = '/tmp/ch/cinderholt_old.json'
if not os.path.exists(_oldp): shutil.copyfile(os.path.join(REPO, 'data/towns/cinderholt.json'), _oldp)
OLD = {b['id']: b for b in json.load(open(_oldp))['buildings']}
_ck = json.load(open(os.path.join(REPO, 'data/churches.json'))); OLD_CH = _ck['towns'].get('cinderholt', {})
KEEP_OLD = ('id', 'kind', 'shop', 'name', 'keeper', 'keeper_sprite', 'sign_sprite', 'greet', 'roof', 'style')
def from_old(bid, **kw):
    o = OLD.get(bid, {}); d = {k: o[k] for k in KEEP_OLD if k in o}; d['id'] = bid; d.update(kw); return d
HOMES = [("The Coalbys' house", 'Mara Coalby'), ("Ember Row", 'Tor Ashby'), ("Slag House", 'Wynn Slagg'), ("The Flints' house", 'Bera Flint'),
         ("Bellows Cottage", 'Ott Bellow'), ("Cinder End", 'Ilsa Cind'), ("The Hammers' house", 'Dag Hammer'), ("Soot Lane house", 'Petra Soot'),
         ("Kiln House", 'Arno Kiln'), ("The Tongs' house", 'Rhea Tong'), ("Basalt Cottage", 'Gil Stone'), ("Quench House", 'Fen Quench'),
         ("The Ores' house", 'Hal Ore'), ("Smelter's Rest", 'Kara Smelt'), ("Ironside", 'Bram Iron'), ("Ash Hollow", 'Una Ash'),
         ("The Rivets' house", 'Cole Rivet'), ("Forge View", 'Saba Forge'), ("Clinker House", 'Jory Clink'), ("Pitside", 'Lena Pitt')]
CAMP_NAMES = {'command': ('Command Tent', 'Marshal Brannoc'), 'barracks': ('Northern Guard Barracks', 'Sergeant Hale')}
out_b = []; church = None; hi = 0; ti = 0
for b in blds:
    role = b['role']; inn = interior(b); door = tuple(b['door'])
    base = dict(art=b['art'], flip=b['flip'], at=b['at'], door=[list(door)], sign=sign_tile(b), props=[], counter=[], style='basalt', roof='#3a3e4c')
    note = '0.3.14 Cinderholt v1 (designer %s%s)' % (b['art'], ', flipped' if b['flip'] else '')
    if role == 'church':
        st, it, _ = solve(inn, door, 2)
        alt, pri = it
        base.update(id='cinderholt_church', kind='church', name=OLD_CH.get('name', 'Cinderholt Chapel'), keeper=OLD_CH.get('keeper', 'Brother Varr'),
                    altar=rel(alt), keeper_at=rel(pri), stand=rel(st), style='stone', note=note)
        for p in inn:
            if len(base['props']) >= 6: break
            if p in (alt, pri, st) or p[0] == door[0]: continue
            cand = list(it) + [tuple(x['at']) for x in base['props']] + [p]
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
    if role not in ('home', 'guard', 'tent', 'barracks', 'command') and sol is None: print('ROLE FAIL', role, b['art']); sys.exit(1)
    if role == 'bank':
        st, (k, c1, c2), _ = sol
        base.update(from_old('cinderholt_bank', keeper_at=rel(k), stand=rel(st), note=note))
        base['props'] = [dict(object='bank_chest', at=rel(c1)), dict(object='bank_chest', at=rel(c2))]
    elif role == 'smithy':
        st, (k, f1, a1), _ = sol
        base.update(from_old('cinderholt_axes', keeper_at=rel(k), stand=rel(st), note=note + '; the forge (furnace + anvil)'))
        base['props'] = [dict(object='furnace', at=rel(f1)), dict(object='anvil', at=rel(a1))]
    elif role == 'cook':
        st, (k, o1), _ = sol
        base.update(from_old('cinderholt_cook', keeper_at=rel(k), stand=rel(st), note=note))
        base['props'] = [dict(object='oven', at=rel(o1))]
    elif role in ('general', 'player', 'body', 'shields'):
        st, (k,), _ = sol
        base.update(from_old('cinderholt_' + role, keeper_at=rel(k), stand=rel(st), note=note))
    else:
        if role == 'home':
            nm, kp = HOMES[hi % len(HOMES)]; hi += 1; bid = 'cinderholt_home_%d' % hi
        elif role == 'guard': nm, kp, bid = 'Guard Post', 'Captain Orla Vane', 'cinderholt_guard_post'
        elif role == 'tent': ti += 1; nm, kp, bid = 'Northern Guard tent', 'Northern Guard', 'cinderholt_ng_tent_%d' % ti
        else: nm, kp = CAMP_NAMES[role]; bid = 'cinderholt_ng_' + role
        base.update(id=bid, kind='house', shop='', name=nm, keeper=kp, keeper_sprite='town_guard' if b['zone'] == 'camp' or role == 'guard' else 'villager', sign_sprite='sign_house', note=note)
        if b['zone'] == 'camp': base.update(style='canvas', roof='#6a5a44', camp='northern_guard')
        if sol and role in ('home', 'command', 'barracks', 'guard') and len(inn) >= 3:
            st, (k,), _ = sol; base.update(keeper_at=rel(k), stand=rel(st))
        else:
            base.update(no_keeper=True, keeper_at=rel(door), stand=rel(door))
    out_b.append(base)
assert church, 'church missing'

# ---------------------------------------------------------------- objects and props
objs = {}
for b in out_b + [church]:
    for pr in b['props']: objs[tuple(pr['at'])] = pr['object']
def door_zone(x, y):
    for b in blds:
        dx, dy = b['door']
        if abs(x - dx) <= 1 and dy <= y <= dy + 3: return True
    return False
ROUTES = set(q for b in blds for q in b['route'])
def free_tile(x, y, allow_path=False, ground='g'):
    if not (1 <= x < GW - 1 and 1 <= y < GH - 1) or (x, y) in objs or (x, y) in BT: return False
    c = grid[y][x]
    if not (c == ground or allow_path and c in ':='): return False
    if door_zone(x, y) or (x, y) in ROUTES: return False
    if RF - 2 <= y <= RF + 2 and abs(x - CXt) <= 3: return False
    for v in list(GATE_TILES.values()) + list(GATES.values()):
        for p in v:
            if abs(x - p[0]) <= 2 and abs(y - p[1]) <= 2: return False
    return True
def addo(name, x, y, **kw):
    if free_tile(x, y, **kw): objs[(x, y)] = name; return True
    return False
def near_ring(x, y, pred, r0=1, r1=8):
    for r_ in range(r0, r1):
        for dx in range(-r_, r_ + 1):
            for dy in range(-r_, r_ + 1):
                if max(abs(dx), abs(dy)) == r_ and pred(x + dx, y + dy): return (x + dx, y + dy)
    return None
ROAD_T = np.array([[grid[y][x] in ':=' for x in range(GW)] for y in range(GH)])
near_road = ndi.binary_dilation(ROAD_T, iterations=2)
cnt = collections.Counter(); rn = random.Random(13)
# plaza kit: exchange board + workbench by the well; the training dummy in the camp yard
PLAZA = (CXt, CYt)
for nm in ['ch_ash_well', 'exchange_board', 'workbench']:
    q = near_ring(PLAZA[0], PLAZA[1] - 1, lambda x, y: free_tile(x, y) and all((x + a, y + b_) not in objs for a in (-1, 0, 1) for b_ in (-1, 0, 1)), 2, 12)
    if q: objs[q] = nm
MARKET = [list(p) for p, v in objs.items() if v in ('exchange_board', 'workbench')]
yard_t = [(x, y) for y in range(GH) for x in range(GW) if YARD[y, x] and YARD[y + 1, x + 1] and grid[y][x] == 'g']
rn.shuffle(yard_t)
for nm in ['training_dummy'] + ['ng_training_dummy'] * 4 + ['ng_archery_target'] * 3:
    for p in yard_t:
        if all((p[0] + a, p[1] + b_) not in objs for a in (-1, 0, 1) for b_ in (-1, 0, 1)) and addo(nm, *p): cnt[nm] += 1; break
# forge district round the smithy: anvils, quench barrels, coal heaps and carts, braziers
smb = [b for b in blds if b['role'] == 'smithy'][0]
sx0, sy0 = smb['at']; sw_, sh_ = len(smb['rows'][0]), len(smb['rows'])
forge = [(x, y) for y in range(sy0 - 2, sy0 + sh_ + 5) for x in range(sx0 - 4, sx0 + sw_ + 4) if 0 <= x < GW and 0 <= y < GH]
rn.shuffle(forge)
for nm in ['ch_anvil', 'ch_quench_barrel', 'ch_coal_heap', 'ch_coal_cart', 'ch_anvil', 'ch_brazier', 'ch_coal_heap', 'ch_quench_barrel', 'ch_brazier', 'ch_crates']:
    for p in forge:
        if addo(nm, *p): cnt[nm] += 1; forge.remove(p); break
# braziers outside every gate
for n, x0, y0, g, c_ in GATE:
    gt = GATE_TILES[SIDE[g]]; xs = [p[0] for p in gt]; ys = [p[1] for p in gt]
    cands_ = [(min(xs) - 2, max(ys) + 2), (max(xs) + 2, max(ys) + 2)] if g == 90 else [(min(xs) - 2, min(ys) - 2), (max(xs) + 2, min(ys) - 2)] if g == 270 else \
             [(min(xs) - 1, min(ys) - 3), (min(xs) - 1, max(ys) + 3)] if g in (180, 'camp') else [(max(xs) + 1, min(ys) - 3), (max(xs) + 1, max(ys) + 3)]
    for p in cands_:
        q = near_ring(p[0], p[1], lambda x, y: free_tile(x, y) and not wall_t[y, x], 0, 3)
        if q: objs[q] = 'ch_brazier'; cnt['ch_brazier'] += 1
# lamp posts / tall braziers along the town roads, torches (tall braziers) in the camp
lamps = []
edge = [(x, y) for y in range(GH) for x in range(GW) if grid[y][x] == 'g' and near_road[y, x] and (INNER_T[y, x] or CAMP_T[y, x])]
rn.shuffle(edge)
for p in edge:
    if any(abs(p[0] - a) + abs(p[1] - b_) < 7 for a, b_ in lamps): continue
    nm = 'ch_brazier_tall' if CAMP_T[p[1], p[0]] or rn.random() < .4 else 'ch_lamp_post'
    if addo(nm, *p): lamps.append(p); cnt[nm] += 1
    if len(lamps) >= 34: break
# camp: central campfire, cookpot, supply wagons + crates, bedrolls, racks, banners
cf = near_ring(KX - 1, KY + 2, lambda x, y: free_tile(x, y) and CAMP_T[y, x] and all((x + a, y + b_) not in objs for a in (-1, 0, 1) for b_ in (-1, 0, 1)), 0, 6)
if cf: objs[cf] = 'ng_campfire'; cnt['ng_campfire'] += 1
camp_g = [(x, y) for y in range(GH) for x in range(GW) if CAMP_T[y, x] and grid[y][x] == 'g' and not YARD[y, x]]
rn.shuffle(camp_g)
if cf: camp_g.sort(key=lambda p: abs(p[0] - cf[0]) + abs(p[1] - cf[1]))
for nm in ['ng_cookpot', 'ng_bedroll', 'ng_bedroll', 'ng_bedroll']:
    for p in camp_g[:40]:
        if addo(nm, *p): cnt[nm] += 1; break
rn.shuffle(camp_g)
for nm in ['ch_cart', 'ng_supply_crates', 'ch_cart', 'ng_supply_crates', 'ng_supply_crates', 'ch_barrel', 'ch_crates', 'ch_barrel', 'ng_weapon_rack', 'ng_spear_rack', 'ng_armor_stand',
           'ng_shield_rack', 'ng_weapon_rack', 'ng_armor_stand', 'ng_spear_rack', 'ng_campfire', 'ng_bedroll', 'ng_bedroll']:
    for p in camp_g:
        if all((p[0] + a, p[1] + b_) not in objs for a in (-1, 0, 1) for b_ in (-1, 0, 1)) and addo(nm, *p): cnt[nm] += 1; break
cmd = [b for b in blds if b['role'] == 'command']
if cmd:
    dx, dy = cmd[0]['door']
    for p in [(dx - 2, dy + 1), (dx + 2, dy + 1), (dx - 3, dy + 1), (dx + 3, dy + 1)]:
        if cnt['ng_banner_north'] < 2 and addo('ng_banner_north', *p): cnt['ng_banner_north'] += 1
cgt = GATE_TILES['camp']; cgx_ = max(p[0] for p in cgt) + 2
for p in [(cgx_, KY - 3), (cgx_, KY + 2), (cgx_ + 1, KY - 3), (cgx_ + 1, KY + 2)]:
    if cnt['ng_banner_north'] < 4 and addo('ng_banner_north', *p): cnt['ng_banner_north'] += 1
# shop signs + town sign by the S gate
SIGNS = {'cinderholt_axes': 'ch_sign_smith', 'cinderholt_cook': 'ch_sign_cook', 'cinderholt_general': 'ch_sign_store', 'cinderholt_bank': 'ch_sign_bank', 'cinderholt_church': 'ch_sign_church'}
nsign = 0
for b in out_b + [church]:
    s = SIGNS.get(b['id'])
    if not s: continue
    dx, dy = b['door'][0]
    for (ax, ay) in [(-1, 1), (1, 1), (-2, 1), (2, 1), (-1, 2), (1, 2)]:
        q = (dx + ax, dy + ay)
        if q not in objs and q not in BT and grid[q[1]][q[0]] in 'g' and q not in ROUTES:
            objs[q] = s; nsign += 1; break
sgx, sgy = GATE_LINE['south'][0]
tsign = any(addo('ch_town_sign', sgx + dx, sgy + dy) for dx, dy in ((-3, 3), (4, 3), (-4, 4), (5, 4), (-3, 5), (4, 5), (-5, 6), (6, 6)))
# town clutter, wilds outside the ring, the ridge top
TOWN_C = ['ch_ash_pile_a', 'ch_ash_pile_c', 'ch_barrel', 'ch_crates', 'ch_cart', 'ch_rubble', 'ch_charred_stump', 'ch_ash_pile_b', 'ch_coal_cart', 'ch_coal_heap', 'ch_brazier', 'ch_dead_tree_a']
WILD = ['ch_dead_tree_a', 'ch_dead_tree_b', 'ch_charred_stump', 'ch_ember_vent', 'ch_ash_pile_a', 'ch_ash_pile_b', 'ch_rubble', 'ch_ash_pile_c', 'ch_ember_vent']
for k in range(6000):
    x, y = rn.randrange(2, GW - 2), rn.randrange(2, GH - 2)
    if any(objs.get((x + a, y + b_)) for a in (-1, 0, 1) for b_ in (-1, 0, 1)) and rn.random() < .8: continue
    if INNER_T[y, x]:
        if rn.random() < .12 and addo(rn.choice(TOWN_C), x, y): cnt['town'] += 1
    elif CAMP_T[y, x]: continue
    elif rn.random() < .05 and not ndi.binary_dilation(wall_t, iterations=2)[y, x] and addo(rn.choice(WILD), x, y): cnt['wild'] += 1
for x in range(2, GW - 2, 3):
    if abs(x - CXt) > 3 and rn.random() < .45: addo(rn.choice(['ch_dead_tree_a', 'ch_charred_stump', 'ch_dead_tree_b', 'ch_rubble']), x, RF - 2 - rn.randrange(2))
for nm in ('embers', 'embers'):
    for p in edge[::7]:
        if INNER_T[p[1], p[0]] and addo(nm, *p): break
print('props', dict(cnt), 'signs', nsign, 'town sign', tsign, 'objects', len(objs))

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
NONBLOCK = {'ch_ash_pile_a', 'ch_ash_pile_b', 'ch_ash_pile_c', 'ch_ember_vent', 'ng_bedroll', 'ch_rubble', 'embers'}
def walk(x, y):
    if not (0 <= x < GW and 0 <= y < GH): return False
    o = objs.get((x, y))
    if o and o not in NONBLOCK: return False
    return grid[y][x] in 'g:=' and (x, y) not in BT or (x, y) in inside_walk
start = (GATES['south'][1][0], GATES['south'][1][1]); seen = {start}; q = [start]
while q:
    x, y = q.pop()
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        n2 = (x + dx, y + dy)
        if n2 not in seen and walk(*n2): seen.add(n2); q.append(n2)
fails = []
for side, g in GATES.items():
    if tuple(g[1]) not in seen: fails.append('edge ' + side)
for side, v in GATE_TILES.items():
    if not any(tuple(p) in seen for p in v): fails.append('gate ' + side)
for b in out_b + [church]:
    if tuple(b['door'][0]) not in seen: fails.append('door ' + b['id'])
    if not b.get('no_keeper') and tuple(b['stand']) not in seen: fails.append('stand ' + b['id'])
    for pr in b['props']:
        p = pr['at']
        if not any((p[0] + a, p[1] + c) in seen for a, c in ((1, 0), (-1, 0), (0, 1), (0, -1))): fails.append('prop %s %s' % (b['id'], pr['object']))
for p, v in objs.items():
    if v in ('exchange_board', 'workbench', 'training_dummy') and not any((p[0] + a, p[1] + c) in seen for a, c in ((1, 0), (-1, 0), (0, 1), (0, -1))): fails.append('obj %s %s' % (v, p))
_cells = collections.Counter((b['at'][0] + x, b['at'][1] + y) for b in blds for y, r in enumerate(b['rows']) for x, c in enumerate(r) if c != '.')
overlap = [p for p, n in _cells.items() if n > 1]
road_fails = []
for b in blds:
    al = drawn(b['art'], b['flip']); x0, y0 = b['px']; h, w = al.shape
    if ((wallpx | cliffpx)[y0:y0 + h, x0:x0 + w] & al).any(): road_fails.append(b['art'] + str(b['at']))
# no diagonal slip-throughs anywhere (walls, towers, cliff)
def isblk(x, y): return grid[y][x] in '#^'
diag_gaps = []
for y in range(GH - 1):
    for x in range(GW - 1):
        a, b_, c_, d_ = isblk(x, y), isblk(x + 1, y), isblk(x, y + 1), isblk(x + 1, y + 1)
        if (a and d_ and not b_ and not c_) or (b_ and c_ and not a and not d_): diag_gaps.append((x, y))

# ---------------------------------------------------------------- ring QA (town basalt ring + camp palisade)
def flood(gset, open_gate, start_, inside_mask):
    shut = set()
    for gname in gset:
        if gname != open_gate: shut |= {tuple(p) for p in GATE_TILES[gname]}
    def bl(p):
        x, y = p
        if not (0 <= x < GW and 0 <= y < GH): return False
        return p in shut or grid[y][x] in '#^' or (p in BT and p not in inside_walk)
    sn = {start_}; qq = [start_]
    while qq:
        c = qq.pop()
        if not inside_mask[min(GH - 1, max(0, c[1])), min(GW - 1, max(0, c[0]))] or not (0 <= c[0] < GW and 0 <= c[1] < GH): return True
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                nn = (c[0] + dx, c[1] + dy)
                if (dx or dy) and nn not in sn and not bl(nn):
                    if dx and dy and bl((c[0] + dx, c[1])) and bl((c[0], c[1] + dy)): continue
                    sn.add(nn); qq.append(nn)
    return False
TOWN_BOX = (ell(RX + 3, RY + 3)[:-1, :-1]); CAMP_BOX = octo(2.5)[:-1, :-1]
TG = ['north', 'south', 'east', 'west']
T_LEAK = flood(TG, 'none', (CXt, CYt), TOWN_BOX); T_OPENS = sum(1 for gname in TG if flood(TG, gname, (CXt, CYt), TOWN_BOX))
C_LEAK = flood(['camp'], 'none', (KX, KY), CAMP_BOX); C_OPENS = sum(1 for gname in ['camp'] if flood(['camp'], gname, (KX, KY), CAMP_BOX))
def ray_walk(cx, cy, boundary, gate_names, smin, smax, step=.02):
    gaps = []; hits = set(); n = 0
    per = 0
    for k in range(3600):
        a = 2 * math.pi * k / 3600; s = 0
        while boundary(cx + s * math.cos(a), cy + s * math.sin(a)): s += .05
        per = max(per, s)
    NS = int(2 * math.pi * per * T / 2)
    for k in range(NS):
        a = 2 * math.pi * k / NS; n += 1; s = 0
        while boundary(cx + s * math.cos(a), cy + s * math.sin(a)): s += .05
        hit = False; gate = None
        for s_ in np.arange(s - smin, s + smax, step):
            vx, vy = cx + s_ * math.cos(a), cy + s_ * math.sin(a); px, py = int(vx * T), int(vy * T)
            if not (0 <= px < SW and 0 <= py < SH): break
            gt = [g_ for g_ in gate_names if any(abs(int(vx) - x) <= 1 and abs(int(vy) - y) <= 1 for x, y in GATE_TILES[g_])]
            if gt: gate = gt[0]; break
            if TWPX[py, px]: hit = True; break
        if gate: hits.add(gate); continue
        if not hit: gaps.append((round(float(cx + s * math.cos(a)), 1), round(float(cy + s * math.sin(a)), 1)))
    return n, gaps, hits
def ell_b(x, y):
    a_ = math.degrees(math.atan2((y - CYt) / RY, (x - CXt) / RX)) % 360; w = 1 + .03 * math.sin(math.radians(a_) * 5 + 2) + .015 * math.sin(math.radians(a_) * 11)
    return math.hypot((x - CXt) / RX, (y - CYt) / RY) / w <= 1
def oct_b(x, y): return abs(x - KX) <= KA and abs(y - KY) <= KB and abs(x - KX) + abs(y - KY) <= KC
tn, tg, th = ray_walk(CXt, CYt, ell_b, TG, 4.5, 2.5)
cn, cg, chh = ray_walk(KX, KY, oct_b, ['camp'], 2.0, 2.0)
RING_QA = dict(samples=tn, gaps=[list(g_) for g_ in tg[:20]], gap_count=len(tg), gates=sorted(th), sealed=not T_LEAK, opens=T_OPENS,
               camp=dict(samples=cn, gaps=[list(g_) for g_ in cg[:20]], gap_count=len(cg), gates=sorted(chh), sealed=not C_LEAK, opens=C_OPENS),
               diag_gaps=len(diag_gaps), diag_fixed=DIAG_FIX,
               note='0.3.14 wall-ring walk: a ray from the centre every 2 px of perimeter must cross basalt wall/tower/gate art (camp: palisade/gate) near the ring; tile flood sealed with the gates shut and open through each; no diagonal corner gaps between blocking tiles (walls, towers, cliff)')
print('ring QA', json.dumps(RING_QA)[:900])

# ---------------------------------------------------------------- register props (sprites.json / objects.json)
SP = os.path.join(REPO, 'data/sprites.json'); OB = os.path.join(REPO, 'data/objects.json')
s_ = json.load(open(SP)); o_ = json.load(open(OB))
NAMES = {'sign_smith': 'Blacksmith sign', 'sign_cook': 'Cookhouse sign', 'sign_store': 'Supply sign', 'sign_bank': 'Bank sign', 'sign_church': 'Chapel sign', 'town_sign': 'Cinderholt',
         'ash_well': 'Ash well', 'banner_north': 'Northern Guard banner', 'brazier_tall': 'Brazier', 'lamp_post': 'Lamp post', 'coal_cart': 'Coal cart', 'quench_barrel': 'Quench barrel'}
for f in sorted(x for x in os.listdir(os.path.join(DST, 'props')) if x.endswith('.png')):
    oid = f[:-4]; n = oid[3:]; im = Image.open(os.path.join(DST, 'props', f))
    s_['objects'][oid] = {'path': f'{RES}/props/{f}', 'frame_size': [im.width, im.height], 'frames': 1, 'anchor': 'bottom',
                          'note': '0.3.14 designer Cinderholt v1 prop (art_handoff/towns/cinderholt)'}
    o_['objects'][oid] = {'name': NAMES.get(n, n.replace('_', ' ').capitalize()), 'sprite': oid, 'blocks': oid not in NONBLOCK, 'type': 'prop'}
json.dump(s_, open(SP, 'w'), indent=1); json.dump(o_, open(OB, 'w'), indent=1)

# ---------------------------------------------------------------- write data
CAMPWALL = {(x, y) for y in range(GH) for x in range(GW) if grid[y][x] == '#' and (CNT_P[y, x] >= 2 or y < RF)}
GROUND = {'g': 'dirt', ':': 'cobble', '=': 'road_dirt', '#': 'basalt_wall', 'P': 'palisade', '^': 'art_wall', 'G': 'gate_basalt', 'Q': 'gate_wood'}
CGS = {tuple(p) for p in GATE_TILES['camp']}
GPASS = {(x, y) for v in GATE_TILES.values() for x, y in v if grid[y][x] in ':=g'}
OBJ_CH = {}
chars = iter('ABCEFHIJKLMNORSTUVWXYZabcdefhijklmnopqrstuvwxyz0123456789!$%&()*+,/;<>?@[]_{|}~')
STATIONS = {'pew', 'candle_stand', 'bank_chest', 'oven', 'furnace', 'anvil'}
for o in sorted(set(objs.values()) - STATIONS):
    c = next(chars)
    while c in GROUND or c in 'KDo': c = next(chars)
    OBJ_CH[o] = c
rows = []
for y in range(GH):
    r = ''
    for x in range(GW):
        o = objs.get((x, y))
        if o in OBJ_CH: r += OBJ_CH[o]
        elif (x, y) in GPASS: r += 'Q' if (x, y) in CGS else 'G'
        elif (x, y) in CAMPWALL: r += 'P'
        else: r += grid[y][x]
    rows.append(r)
objects = {}
for o, ch in OBJ_CH.items():
    gs = [GROUND[grid[p[1]][p[0]]] for p, v in objs.items() if v == o]
    objects[ch] = {'object': o, 'ground': collections.Counter(gs).most_common(1)[0][0]}
_ta_p = os.path.join(REPO, 'data/town_art.json'); _ta = json.load(open(_ta_p))
_ta['buildings'] = {k: v for k, v in _ta.get('buildings', {}).items() if k not in ART}; _ta['buildings'].update(ART)
json.dump(_ta, open(_ta_p, 'w'), indent=1)
old = json.load(open(_oldp))
spawn = near_ring(PLAZA[0], PLAZA[1] + 1, lambda x, y: 0 <= x < GW and 0 <= y < GH and (x, y) in seen and objs.get((x, y)) is None and grid[y][x] in ':' and (x, y) not in inside_walk, 0, 8)
assert spawn, 'no spawn'
town = dict(id='cinderholt', name='Cinderholt', origin=ORIGIN, spawn=[ORIGIN[0] + spawn[0], ORIGIN[1] + spawn[1]],
            tiles=GROUND, objects=objects, roof='#3a3e4c', building_style='basalt',
            specialists=old['specialists'], price_bias=old['price_bias'],
            tagline='Basalt forge city behind a towered ring wall: loose ash-and-cobble lanes, a smoking forge district, and the Northern Guard camp on the ridge above the north gate.',
            theme='cinderholt', walls='basalt', gates=GATES, gate_walls={k: v for k, v in GATE_LINE.items() if k != 'camp'},
            gate_tiles={k: v for k, v in GATE_TILES.items() if k != 'camp'}, ring_qa=RING_QA,
            camp=dict(id='northern_guard', name='Northern Guard camp', center=[KX, KY], gate_tiles=GATE_TILES['camp'], gate_wall=GATE_LINE['camp'],
                      ridge=dict(face_rows=[RF, RF + 1], stairs=sorted(STAIRS))),
            art=dict(market=MARKET, plaza_px=[PLAZA[0] * T, PLAZA[1] * T], ground_decal=f'{RES}/ground_decal.png', ysort=YSORT, fades=FADES),
            buildings=out_b, rows=rows,
            note="0.3.14 generated by tools/world/build_cinderholt_v1.py from the designer's Cinderholt v1 set (art_handoff/towns/cinderholt); camp north per the lore")
json.dump(town, open(os.path.join(REPO, 'data/towns/cinderholt.json'), 'w'), indent=1)
_ck['towns']['cinderholt'] = church
json.dump(_ck, open(os.path.join(REPO, 'data/churches.json'), 'w'), indent=1)
NP = os.path.join(REPO, 'data/town_npcs.json'); npcs = json.load(open(NP))
def near_walk(x, y, chars_=':='):
    for r_ in range(0, 10):
        for dx in range(-r_, r_ + 1):
            for dy in range(-r_, r_ + 1):
                p = (x + dx, y + dy)
                if p in seen and 0 <= p[0] < GW and 0 <= p[1] < GH and grid[p[1]][p[0]] in chars_ and p not in inside_walk and objs.get(p) is None: return [p[0], p[1]]
guards = []
for gname in TG:
    v = GATE_TILES[gname]; xs = [p[0] for p in v]; ys = [p[1] for p in v]
    if gname in ('north', 'south'):
        iy = max(ys) + 2 if gname == 'north' else min(ys) - 2
        for gx in (min(xs) - 1, max(xs) + 1): guards.append(dict(enemy='town_guard', patrol=[near_walk(gx, iy)], gate=gname))
    else:
        ix = max(xs) + 2 if gname == 'west' else min(xs) - 2
        for gy in (min(ys) - 1, max(ys) + 1): guards.append(dict(enemy='town_guard', patrol=[near_walk(ix, gy)], gate=gname))
for beat in [[(42, 62), (31, 58), (24, 66)], [(42, 62), (53, 58), (60, 66)], [(42, 48), (34, 52), (50, 52)], [(42, 75), (33, 72), (51, 72)]]:
    guards.append(dict(enemy='town_guard', patrol=[near_walk(int(x), int(y)) for x, y in beat]))
v = GATE_TILES['camp']; ix = max(p[0] for p in v) + 2
for gy in (KY - 2, KY + 1): guards.append(dict(enemy='northern_guard', patrol=[near_walk(ix, gy)], camp='northern_guard'))
guards.append(dict(enemy='northern_guard', patrol=[near_walk(KX - 9, KY + KB + 3), near_walk(CXt, RF - 2)], camp='northern_guard'))
guards.append(dict(enemy='northern_guard', patrol=[near_walk(KX, KY), near_walk(KX + 8, KY - 4), near_walk(KX - 6, KY + 5)], camp='northern_guard'))
if cmd:
    dx, dy = cmd[0]['door']
    for ax in (-2, 2): guards.append(dict(enemy='northern_soldier', patrol=[near_walk(dx + ax, dy + 2, ':=g')], camp='northern_guard'))
for p in [(KX + 3, KY + 5), (KX + 9, KY + 6), (KX + 6, KY + 3)]:
    guards.append(dict(enemy='northern_soldier', patrol=[near_walk(p[0], p[1], ':=g')], camp='northern_guard'))
guards = [g_ for g_ in guards if all(g_['patrol'])]
npcs['towns']['cinderholt'] = dict(guards=guards, citizens=dict(enemy='citizen', count=6, area=[PLAZA[0] - 8, PLAZA[1] - 6, 17, 13]),
                                   note='0.3.14 two guards inside each of the 4 basalt gates + 4 lane patrols; Northern Guard camp: guards (lv 30) at the camp gate / stair road / camp, soldiers (lv 35) at the command tent and training yard')
json.dump(npcs, open(NP, 'w'), indent=1)

# ---------------------------------------------------------------- debug composite
dbg = Image.new('RGBA', (SW, SH), (40, 30, 28, 255)); dbg.alpha_composite(Image.fromarray(dec))
items = [(it['pos'][1] + it['base'], 'y', it) for it in YSORT]
items += [(b['px'][1] + BM[b['art']]['px'][1], 'b', b) for b in blds] + [(y * T + T, 'p', (o, x, y)) for (x, y), o in objs.items()]
for _, kind, it in sorted(items, key=lambda t: t[0]):
    if kind == 'b':
        for l in BM[it['art']]['layers']:
            im = LB(l); im = im.transpose(Image.FLIP_LEFT_RIGHT) if it['flip'] else im
            dbg.alpha_composite(im, tuple(it['px']))
    elif kind == 'y':
        im = Image.open(os.path.join(DST, it['path'][len(RES) + 1:])).convert('RGBA'); dbg.alpha_composite(im.crop((0, max(0, -it['pos'][1]), im.width, im.height)), (it['pos'][0], max(0, it['pos'][1])))
    else:
        o, x, y = it; p = s_['objects'].get(o, {}).get('path', '')
        if p.startswith(RES):
            im = Image.open(os.path.join(DST, p[len(RES) + 1:])).convert('RGBA')
            dbg.alpha_composite(im, (int(x * T + 8 - im.width / 2), max(0, int(y * T + T - im.height))))
        else: ImageDraw.Draw(dbg).rectangle([x * T + 3, y * T + 3, x * T + 12, y * T + 12], fill=(220, 60, 60, 255))
for it in FADES: dbg.alpha_composite(Image.open(os.path.join(DST, it['path'][len(RES) + 1:])).convert('RGBA'), tuple(it['pos']))
ImageDraw.Draw(dbg).rectangle([spawn[0] * T + 4, spawn[1] * T + 4, spawn[0] * T + 11, spawn[1] * T + 11], outline=(0, 255, 255, 255))
for g_ in guards:
    x, y = g_['patrol'][0]; ImageDraw.Draw(dbg).rectangle([x * T + 4, y * T + 2, x * T + 11, y * T + 14], fill=(60, 120, 255, 255) if g_['enemy'] == 'town_guard' else (255, 160, 40, 255))
os.makedirs(os.path.join(REPO, 'build'), exist_ok=True)
dbg.save(os.path.join(REPO, 'build/cinderholt_layout_check.png'))
open('/tmp/ch/grid.txt', 'w').write('\n'.join(rows))
need = set(M['civic'] + [b['name'] for b in M['camp']['buildings']] + M['houses']); missing = sorted(need - set(b['art'] for b in blds))
print('buildings', len(blds), 'designs', len(set(b['art'] for b in blds)), 'missing designs', missing, 'objects', len(objs), 'tile overlaps', overlap, 'art over wall/cliff', road_fails,
      'reach fails', fails, 'diag gaps', diag_gaps[:10], 'spawn', town['spawn'], 'guards', len(guards))
ok = not (overlap or fails or road_fails or diag_gaps or RING_QA['gap_count'] or not RING_QA['sealed'] or T_OPENS != 4 or len(th) != 4
          or RING_QA['camp']['gap_count'] or not RING_QA['camp']['sealed'] or C_OPENS != 1 or len(chh) != 1)
sys.exit(0 if ok else 1)
