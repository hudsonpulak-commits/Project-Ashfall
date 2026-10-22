"""0.3.13 Saltmere v3 = the 0.3.12 v2 town plus the designer's v3 add-on (art_handoff/towns/saltmere/v3):
quay end/corner/inner tiles and pier tips, 14 dock props, the town sign, the harbour entrance over the north road,
Elijah's tomb, the large smithy (the smith leaves the warehouse), 40x20 rowboats, the v3 galleon and sloop.

0.3.12 Saltmere redesign: an open harbour town (no walls, no fort) built from the designer's
Saltmere v2 set (art_handoff/towns/saltmere, read-only: tiles_v2, buildings_v2, props_v2, manifest_v2;
plus docks/ and ships/ which manifest_v2 references, and v1 dock clutter props because v2 has none).

The town sits on the real east coast: origin [280,136], 80x48. A harbour basin with a quay and three
piers opens to the ocean through a winding channel (>= 4 tiles wide); the lighthouse stands on the spit.
The dry ring stays at the old centre (dry_center) so the coast outside is unchanged; cliff_clear=1 keeps
the sea cliffs just south of the town.

Writes:
  assets/sprites/towns/saltmere/{tiles,buildings,props,props_v1,docks,ships}/  (copies)
  assets/sprites/towns/saltmere/ground_decal.png
  data/town_art.json (merged), data/towns/saltmere.json, data/churches.json (saltmere),
  data/town_npcs.json (saltmere), data/sprites.json + data/objects.json (sm_* / sm1_* props)
  build/saltmere_layout_check.png
Exits 1 on any building/road overlap, unreachable door/stand/gate, ship on land, or if the dock water
does not flood out to the open sea through a channel at least 4 tiles wide.
"""
import json, math, os, random, shutil, sys, collections
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SRC = '/workspace/art_handoff/towns/saltmere'
DST = os.path.join(REPO, 'assets/sprites/towns/saltmere')
RES = 'res://assets/sprites/towns/saltmere'
T = 16
GW, GH = 80, 48
SW, SH = GW * T, GH * T
ORIGIN = [280, 136]
OLD_CENTER = [300, 170]
ELIJAH_TOMB = [272, 160]

# ---------------------------------------------------------------- copy art
V1_PROPS = ['barrel', 'barrel_stack', 'crate', 'crate_stack', 'crate_broken', 'net_hanging', 'rope_coil', 'anchor', 'fish_rack', 'lamp_post', 'bench']
COPY = [('tiles_v2', 'tiles', None), ('buildings_v2', 'buildings', None), ('props_v2', 'props', None),
        ('docks', 'docks', None), ('ships', 'ships', None), ('props', 'props_v1', set(V1_PROPS))]
for sub, dsub, only in COPY:
    os.makedirs(os.path.join(DST, dsub), exist_ok=True)
    for f in sorted(os.listdir(os.path.join(SRC, sub))):
        if f.endswith('.png') and (only is None or f[:-4] in only):
            shutil.copyfile(os.path.join(SRC, sub, f), os.path.join(DST, dsub, f))
V3 = os.path.join(SRC, 'v3')
for sub in ('buildings', 'props', 'ships', 'tiles'):
    for f in sorted(os.listdir(os.path.join(V3, sub))):
        if not f.endswith('.png'): continue
        d_ = os.path.join(DST, 'props_v3' if sub == 'props' else sub); os.makedirs(d_, exist_ok=True)
        shutil.copyfile(os.path.join(V3, sub, f), os.path.join(d_, f))
shutil.copyfile(os.path.join(V3, 'manifest_v3.json'), os.path.join(DST, 'manifest_v3.json'))
M3 = json.load(open(os.path.join(V3, 'manifest_v3.json')))
shutil.copyfile(os.path.join(SRC, 'manifest_v2.json'), os.path.join(DST, 'manifest_v2.json'))
shutil.copyfile(os.path.join(SRC, 'README.md'), os.path.join(DST, 'README_designer.md'))
M = json.load(open(os.path.join(SRC, 'manifest_v2.json')))
M['buildings'] += [b for b in M3['buildings'] if b['name'] != 'v3_harbour_entrance']
BM = {b['name']: b for b in M['buildings']}
HE = next(b for b in M3['buildings'] if b['name'] == 'v3_harbour_entrance')
_LC = {}
def L(sub, n):
    n = n if n.endswith('.png') else n + '.png'
    if (sub, n) not in _LC: _LC[(sub, n)] = Image.open(os.path.join(DST, sub, n)).convert('RGBA')
    return _LC[(sub, n)]
sys.path.insert(0, os.path.join(SRC, 'src'))
import diagtiles as dg

# ---------------------------------------------------------------- per-design tile plans (same rule as Highfen v3)
def plan_of(b):
    n = b['name']; E = b['footprint_origin_px'][1]; W, H = b['tiles']; d = tuple(b['door_tile'])
    f = np.array(L('buildings', n + '_floor'))[..., 3] > 0
    S = set()
    for y in range(H):
        for x in range(W):
            if f[E + y * T:E + y * T + T, x * T:x * T + T].sum() >= 24: S.add((x, y))
    S.add(d)
    inn = {t for t in S if t != d and t[1] < H - 1 and all((t[0] + a, t[1] + c) in S for a, c in ((1, 0), (-1, 0), (0, 1), (0, -1)))}
    return [''.join('D' if (x, y) == d else 'o' if (x, y) in inn else '#' if (x, y) in S else '.' for x in range(W)) for y in range(H)]
ART = {}
for b in M['buildings']:
    if b['name'] == 'v2_fort': continue          # Saltmere has no fort (Hudson)
    lay = b['layers']
    ART[b['name']] = dict(tiles=b['tiles'], px=b['px'], origin_y=b['footprint_origin_px'][1], door_tile=b['door_tile'], storeys=b['storeys'],
                          floor=f"{RES}/buildings/{lay[0]}", walls=f"{RES}/buildings/{lay[1]}",
                          fade=[f"{RES}/buildings/{l}" for l in b['fade_group']], plan=plan_of(b))
def flip_plan(rows): return [r[::-1] for r in rows]

# ---------------------------------------------------------------- terrain on the vertex grid
site = json.load(open(os.path.join(REPO, 'tools/world/saltmere_site.json')))
SO = site['origin']; SR = site['rows']
def world_ocean(x, y):
    sx, sy = x + ORIGIN[0] - SO[0], y + ORIGIN[1] - SO[1]
    sy = min(max(sy, 0), len(SR) - 1); sx = min(max(sx, 0), len(SR[0]) - 1)
    return SR[sy][sx] == '~'
VY, VX = np.mgrid[:GH + 1, :GW + 1].astype(float)
nr = np.random.RandomState(31)
nz = ndi.gaussian_filter(nr.rand(GH + 1, GW + 1), 3); nz = (nz - nz.min()) / (nz.max() - nz.min())
OCEAN_V = np.array([[world_ocean(min(x, GW - 1), min(y, GH - 1)) for x in range(GW + 1)] for y in range(GH + 1)])
SEA = (VX >= 72 + 1.2 * np.sin(VY / 5.0) + (nz - .5) * 1.5) | OCEAN_V
qx0, qx1, qy = 18, 56, 31
yb = 40.6
basin = (VY > qy) & (VY < yb) & ((((VX - 37) / 22.5) ** 4 + ((VY - 35.8) / 5.2) ** 4) <= 1)
basin |= (VY > qy) & (VY <= 36) & (VX >= qx0) & (VX <= qx1)
CH_PTS = [(56, 35.5), (61, 37.4), (65.5, 35.6), (69.5, 37.2), (75, 36.2), (GW + 1, 36.4)]
chan = dg.line_mask(VY.shape, CH_PTS, 2.55)
LV = ~(SEA | basin | chan)
LV[:qy + 1, qx0:qx1 + 1] = True                       # quay line: land filled to vertex row qy across the dock span
LV[qy + 1:qy + 3, qx0:qx1 + 1] = False
landT = LV[:-1, :-1] & LV[:-1, 1:] | LV[1:, 1:] & LV[1:, :-1] | LV[:-1, :-1] & LV[1:, 1:] | LV[:-1, 1:] & LV[1:, :-1]
CNT_L = LV[:-1, :-1].astype(int) + LV[:-1, 1:] + LV[1:, 1:] + LV[1:, :-1]
dock = np.zeros((GH, GW), bool); dock[qy:qy + 2, qx0:qx1] = True
PIERS = (23, 35, 47)
for px_ in PIERS: dock[qy + 2:qy + 7, px_:px_ + 2] = True
dw = ndi.distance_transform_edt(LV)
GV = LV & (dw > 3.2 + 2.2 * nz) & ~((nz > .74) & (VY < 26))          # sand belt on every shore, sand clearings inland

# ---------------------------------------------------------------- roads (tile-based winding streets, 45-degree corner autotiles)
st = qy - 2
PLAZA_C = (33, 15.5); PRX, PRY = 5.6, 3.7
LINES_C = [([(-1, 15), (4, 15.2), (9, 16.4), (16, 14.6), (23, 16.2), (28, 15.5)], 1.15),           # main street from the west gate
           ([(44, -1), (44, 3), (45.5, 6), (41.5, 10), (37.5, 13)], 1.1),                          # north road
           ([(5, st + .5), (12, st), (20, st + .8), (28, st), (36, st + .8), (44, st), (52, st + .8), (59, st), (64, st - 1.2)], 1.1),  # harbour street
           ([(33.5, 18.5), (35, 22), (33.5, 25.5), (34.5, st)], 1.0),                              # plaza -> harbour
           ([(12, 15.5), (10.5, 20), (13, 24.5), (11.5, st)], 1.0),                                # west cross street
           ([(38.5, 16.5), (45, 18.5), (52, 17.5), (58.5, 20), (57.5, 24.5), (59.5, st)], 1.0)]    # east cross street
CV = np.zeros(VY.shape, bool)
for pts, hw in LINES_C: CV |= dg.line_mask(VY.shape, pts, hw)
CV |= ((VX - PLAZA_C[0]) / PRX) ** 2 + ((VY - PLAZA_C[1]) / PRY) ** 2 <= 1
APR = (VY >= st - .6) & (VY <= qy) & (VX >= qx0) & (VX <= qx1)
CV |= APR
CV &= LV
LINES_S = [([(16, 14.6), (14.5, 9), (17, 4.5), (15, 0.5)], .95), ([(25, 15.8), (26.5, 9.5), (24.5, 3)], .9),
           ([(52, 17.5), (55.5, 12), (61, 7.5), (65, 3)], .95), ([(6, 15.5), (4.5, 21), (6.5, st + .5)], .95),
           ([(5, st + .5), (7, 35), (10, 40), (13.5, 43.5), (24, 44), (36, 43.2), (48, 44.2), (58, 42.8), (63.5, 43.2)], .95),   # round the bay to the lighthouse
           ([(64, st - 1.2), (67, 26), (66, 18), (68.5, 11)], .9)]                                   # east coast lane
SPV = np.zeros(VY.shape, bool)
for pts, hw in LINES_S: SPV |= dg.line_mask(VY.shape, pts, hw)
SPV &= LV & ~CV
CF, SF, LF, GF = dg.frames_of(CV), dg.frames_of(SPV), dg.frames_of(LV), dg.frames_of(GV)
bits = np.vectorize(lambda f: bin(int(f)).count('1'))
CNT_C, CNT_S = bits(CF), bits(SF)
GATES = dict(west=[[0, 14], [0, 15], [0, 16]], north=[[43, 0], [44, 0], [45, 0]])

# ---------------------------------------------------------------- channel flood check: dock water reaches the open sea, >= 4 tiles wide
waterT = (CNT_L < 3) & ~dock
lab, nl = ndi.label(waterT)
dock_water = {lab[y + c, x + a] for y, x in zip(*np.nonzero(dock)) for a, c in ((0, 1), (1, 0), (-1, 0), (0, -1))
              if 0 <= y + c < GH and 0 <= x + a < GW and lab[y + c, x + a]}
sea_lab = {lab[y, GW - 1] for y in range(GH) if lab[y, GW - 1]}
CHANNEL_OK = bool(dock_water & sea_lab)
chan_w = 99
for x in range(52, 76):                                   # narrowest water run across the channel, column by column
    col = waterT[30:47, x]; best = 0; run = 0
    for v in col:
        run = run + 1 if v else 0; best = max(best, run)
    chan_w = min(chan_w, best)
print('channel to the sea', CHANNEL_OK, 'narrowest', chan_w, 'tiles')

# ---------------------------------------------------------------- ground decal
ST = {n: np.array(L('tiles', n)) for n in ['v2_diag_sand_shore', 'v2_diag_grass', 'v2_diag_sand_path', 'v2_diag_cobble']}
DK = np.array(L('docks', 'dock_planks_autotile')); JN = L('tiles', 'v2_dock_join')
img = Image.new('RGBA', (SW, SH)); cover = {}
for n, F in [('v2_diag_sand_shore', LF), ('v2_diag_grass', GF), ('v2_diag_sand_path', SF), ('v2_diag_cobble', CF)]:
    lay = np.zeros((SH, SW, 4), np.uint8)
    for y in range(GH):
        for x in range(GW):
            if F[y, x]: lay[y * T:y * T + T, x * T:x * T + T] = ST[n][:, F[y, x] * T:F[y, x] * T + T]
    for y, x in zip(*np.nonzero(dock)): lay[y * T:y * T + T, x * T:x * T + T] = 0
    cover[n] = lay[..., 3] > 0; img.alpha_composite(Image.fromarray(lay))
landpx = cover['v2_diag_sand_shore']
road = cover['v2_diag_cobble'] | cover['v2_diag_sand_path']
def nb(m, y, x):
    g = lambda yy, xx: 0 <= yy < GH and 0 <= xx < GW and m[yy, xx]
    return (1 if g(y - 1, x) else 0) | (2 if g(y, x + 1) else 0) | (4 if g(y + 1, x) else 0) | (8 if g(y, x - 1) else 0)
dockpx = np.zeros((SH, SW), bool)
QUAY3 = collections.Counter()
def quay_v3(x, y, onland):
    # 0.3.13 v3 quay pieces: exposed quay ends/corners, knee braces where a pier leaves the quay, ladder tips on the piers
    if qy <= y < qy + 2:
        if x == qx0: return 'v3_quay_corner_nw' if onland else 'v3_quay_corner_sw' if y == qy + 1 else 'v3_quay_end_w'
        if x == qx1 - 1: return 'v3_quay_corner_ne' if onland else 'v3_quay_corner_se' if y == qy + 1 else 'v3_quay_end_e'
        if y == qy + 1 and any(x == p_ + 2 for p_ in PIERS): return 'v3_quay_inner_sw'
        if y == qy + 1 and any(x == p_ - 1 for p_ in PIERS): return 'v3_quay_inner_se'
    if y == qy + 6 and any(x in (p_, p_ + 1) for p_ in PIERS): return 'v3_pier_end_s'
    return None
for y in range(GH):
    for x in range(GW):
        if dock[y, x]:
            m = nb(dock, y, x); onland = y > 0 and CNT_L[y - 1, x] == 4
            if onland: m |= 1
            fr = Image.fromarray(DK[:, m * T:m * T + T])
            v3 = quay_v3(x, y, onland)
            if v3: fr = L('tiles', v3); QUAY3[v3] += 1
            img.alpha_composite(fr, (x * T, y * T))
            dockpx[y * T:y * T + 20, x * T:x * T + T] |= np.array(fr)[:min(20, SH - y * T), :, 3] > 0
            if onland:
                timber = cover['v2_diag_sand_path'][y * T - 4, x * T + 8] and not cover['v2_diag_cobble'][y * T - 4, x * T + 8]
                jl = not (dock[y, x - 1] and CNT_L[y - 1, x - 1] == 4); jr = not (x + 1 < GW and dock[y, x + 1] and CNT_L[y - 1, x + 1] == 4)
                k = (3 if timber else 0) + (1 if jl else 2 if jr else 0)
                img.alpha_composite(JN.crop((k * T, 0, k * T + T, T)), (x * T, y * T))
waterpx = ~landpx & ~dockpx
# land fades over its last 2 tiles at the W, N and S edges into the world terrain (the east edge is sea)
dec = np.array(img)
fx = np.clip(np.minimum.reduce([np.arange(SW)[None, :] / (2 * T) + 0 * np.arange(SH)[:, None],
                                np.arange(SH)[:, None] / (2 * T) + 0 * np.arange(SW)[None, :],
                                (SH - 1 - np.arange(SH))[:, None] / (2 * T) + 0 * np.arange(SW)[None, :]]), 0, 1)
dec[..., 3] = (dec[..., 3] * (.25 + .75 * fx)).astype(np.uint8)
Image.fromarray(dec).save(os.path.join(DST, 'ground_decal.png'))

# ---------------------------------------------------------------- tile grid
grid = [['s'] * GW for _ in range(GH)]
for y in range(GH):
    for x in range(GW):
        if dock[y, x]: grid[y][x] = '='
        elif CNT_L[y, x] < 3: grid[y][x] = '~'
        elif CNT_C[y, x] >= 3: grid[y][x] = ':'
        elif CNT_S[y, x] >= 3: grid[y][x] = '-'
        elif GF[y, x] == 15: grid[y][x] = 'g'
for g in GATES.values():
    for (x, y) in g: grid[y][x] = ':'
for x in range(qx0, qx1):                                   # the quay edge row above the planks is walkable cobble
    if grid[qy - 1][x] == '~': grid[qy - 1][x] = ':'

# ---------------------------------------------------------------- building placement (tile-snapped)
occ_r = ndi.binary_dilation(road | dockpx, iterations=2)
occ_w = ndi.binary_dilation(waterpx, iterations=2)
tile_used = np.array([[grid[y][x] in '~=' for x in range(GW)] for y in range(GH)])
blds = []
def drawn(n, flip):
    b = BM[n]; im = Image.new('RGBA', tuple(b['px']))
    for l in b['layers']: im.alpha_composite(L('buildings', l))
    if flip: im = im.transpose(Image.FLIP_LEFT_RIGHT)
    return np.array(im)[..., 3] > 0
def plan_tiles(n, flip):
    rows = ART[n]['plan']; rows = flip_plan(rows) if flip else rows
    return rows, [(x, y) for y, r in enumerate(rows) for x, c in enumerate(r) if c != '.']
def door_local(rows):
    for y, r in enumerate(rows):
        if 'D' in r: return (r.index('D'), y)
def place(n, tx, ty, flip=False, role=None, reach=60, spit=False, quiet=False):
    al = drawn(n, flip); h, w = al.shape; E = ART[n]['origin_y']; W, H = ART[n]['tiles']
    rows, tiles = plan_tiles(n, flip); dl = door_local(rows)
    for r in range(0, reach, 2):
        for t in range(0, 360, 15 if r else 360):
            px = tx * T + r * math.cos(math.radians(t)) - w / 2; py = ty * T + r * math.sin(math.radians(t)) - h / 2
            ox, oy = int(round(px / T)), int(round((py + E) / T))
            x0, y0 = ox * T, oy * T - E
            if ox < 2 or oy < 1 or ox + W > GW - 1 or oy + H > GH - 2 or y0 < 0 or x0 + w > SW: continue
            if (occ_r[y0:y0 + h, x0:x0 + w] & al).any(): continue
            if not spit and (occ_w[y0:y0 + h, x0:x0 + w] & al).any(): continue
            bad = False
            for (lx, ly) in tiles:
                for ax in (-1, 0, 1):
                    for ay in (-1, 0, 1):
                        q = (ox + lx + ax, oy + ly + ay)
                        if not (0 <= q[0] < GW and 0 <= q[1] < GH) or tile_used[q[1], q[0]]: bad = True
                if grid[oy + ly][ox + lx] not in 'sg': bad = True
            fx_, fy_ = ox + dl[0], oy + dl[1] + 1
            if fy_ + 1 >= GH or tile_used[fy_, fx_] or tile_used[fy_ + 1, fx_] or grid[fy_][fx_] in '~=': bad = True
            if bad: continue
            occ_r[y0:y0 + h, x0:x0 + w] |= ndi.binary_dilation(al, iterations=2)
            for (lx, ly) in tiles: tile_used[oy + ly, ox + lx] = True
            d = dict(art=n, flip=flip, at=[ox, oy], role=role, px=[x0, y0], rows=rows, door=[ox + dl[0], oy + dl[1]])
            blds.append(d); return d
    if not quiet: print('no room for', n, role)
    return None

place('v2_church', 33, 8.5, role='church')
place('v2_governor', 54, 9, role='bank')
place('v2_tavern', 37, 23.5, role='cook')
place('v2_warehouse_b', 19, 23, role='general')
place('v2_harbourmaster', 28, 23, role='harbourmaster')
place('v3_smithy_large', 51, 23.5, role='smithy', reach=120)   # 0.3.13 the smith moves into the designer's large v3 smithy
place('v2_rum_house', 64, 24, role='rum')
place('v2_warehouse_a', 7, 21.5, role='warehouse', reach=160)   # 0.3.13 the warehouse is a warehouse again (Salt Warehouse)
place('v3_elijah_tomb', 6, 6, role='tomb', reach=160)
place('v2_house_10', 46, 12, role='legs')
place('v2_house_23', 19, 9, role='player_house')
place('v2_lighthouse', 66, 42, role='lighthouse', spit=True, reach=80)
# white houses with blue roofs first (designer houses with a blue roof), the rest after
def roof_blue(n):
    a = np.array(L('buildings', n + '_roof')).reshape(-1, 4); a = a[a[:, 3] > 0][:, :3].astype(int)
    return len(a) and ((a[:, 2] > a[:, 0] + 12).mean() > .4)
HOUSES = [h for h in M['houses'] if h not in ('v2_house_10', 'v2_house_23')]
HOUSES = sorted(HOUSES, key=lambda h: (not roof_blue(h), h))
NBLUE = sum(1 for h in HOUSES if roof_blue(h))
rr = random.Random(7)
cands = [(x, y) for y in range(3, 46) for x in range(4, 70) if CNT_L[min(y, GH - 1), min(x, GW - 1)] == 4]
rr.shuffle(cands)
roadd = ndi.distance_transform_edt(~road)
cands.sort(key=lambda c: roadd[min(SH - 1, c[1] * T + 8), min(SW - 1, c[0] * T)])
use = collections.Counter(); nh = 0; pi = 0
for c in cands:
    if nh >= 26: break
    for k in range(6):
        n = HOUSES[(pi + k) % NBLUE]
        if use[n] >= (3 if roof_blue(n) else 0): continue      # Hudson: white houses with blue roofs
        if place(n, c[0], c[1], flip=use[n] % 2 == 1, role='home', reach=6, quiet=True):
            use[n] += 1; nh += 1; pi += k + 1; break
print('houses', nh, 'blue-roof designs', sum(1 for h in HOUSES if roof_blue(h)))

# ---------------------------------------------------------------- objects
objs = {}
def free_tile(x, y, allow_road=False, on_dock=False):
    if not (1 <= x < GW - 1 and 1 <= y < GH - 1) or (x, y) in objs or tile_used[y, x] and not on_dock: return False
    c = grid[y][x]
    if on_dock: ok = c == '='
    else: ok = c in ('sg:-' if allow_road else 'sg')
    if not ok: return False
    for b in blds:
        dx, dy = b['door']
        if abs(x - dx) <= 1 and dy <= y <= dy + 2: return False
    for g in GATES.values():
        for p in g:
            if abs(x - p[0]) <= 2 and abs(y - p[1]) <= 2: return False
    return True
def interior(b):
    ox, oy = b['at']
    allo = {(ox + x, oy + y) for y, r in enumerate(b['rows']) for x, c in enumerate(r) if c == 'o'}
    d0 = tuple(b['door']); seen_ = set(); st_ = [d0]
    while st_:
        p = st_.pop()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (p[0] + dx, p[1] + dy)
            if q in allo and q not in seen_: seen_.add(q); st_.append(q)
    return [p for p in sorted(allo, key=lambda p: (p[1], p[0])) if p in seen_]
def rel(p): return [int(p[0]), int(p[1])]
def sign_tile(b):
    dx, dy = b['door']
    for sx in (dx + 1, dx - 1):
        lx = sx - b['at'][0]
        if 0 <= lx < len(b['rows'][0]) and b['rows'][dy - b['at'][1]][lx] == '#': return [sx, dy]
    return [dx, dy]
HOMES = [("The Brines' cottage", 'Wenna Brine'), ("Coral's house", 'Coral Penhale'), ("Netmaker's house", 'Jory Tregar'), ("The Kellows' house", 'Tamsin Kellow'),
         ("Old Skip's", 'Skip Nancarrow'), ("Gull Cottage", 'Morwen Gull'), ("Pascoe's house", 'Davey Pascoe'), ("The Treloars' house", 'Loveday Treloar'),
         ("Polglaze's house", 'Kerra Polglaze'), ("The Rowes' house", 'Zennor Rowe'), ("Trevail's house", 'Pedrek Trevail'), ("Bosanko's house", 'Elowen Bosanko'),
         ("The Jagos' house", 'Ruan Jago'), ("Chegwidden's house", 'Lowdy Chegwidden'), ("Pengelly's house", 'Talan Pengelly'), ("Saltcote", 'Demelza Hocking'),
         ("The Carnes' house", 'Senara Carne'), ("Penrose's house", 'Bryok Penrose'), ("Tregenza's house", 'Jenna Tregenza'), ("Quay Cottage", 'Ned Trewin'),
         ("The Rosewarnes' house", 'Hedra Rosewarne'), ("Angove's house", 'Cador Angove'), ("Shell House", 'Ia Penhaligon'), ("Tremayne's house", 'Gwen Tremayne'),
         ("The Vosses' house", 'Mawgan Vosper'), ("Lanyon's house", 'Piran Lanyon'), ("Driftwood House", 'Tressa Nance'), ("Keverne's house", 'Austol Keverne')]
OLD = {b['id']: b for b in json.load(open(os.path.join(REPO, 'data/towns/saltmere.json'))).get('buildings', [])}
_ck = json.load(open(os.path.join(REPO, 'data/churches.json')))
OLD_CH = _ck['towns'].get('saltmere', {})
KEEP_OLD = ('id', 'kind', 'shop', 'name', 'keeper', 'keeper_sprite', 'sign_sprite', 'greet', 'roof')
def from_old(bid, **kw):
    o = OLD.get(bid, {}); d = {k: o[k] for k in KEEP_OLD if k in o}; d['id'] = bid; d.update(kw); return d
out_b = []; church = None; hi = 0
for b in blds:
    role = b['role']; inn = interior(b); door = b['door']; ad = (door[0], door[1] - 1)
    base = dict(art=b['art'], flip=b['flip'], at=b['at'], door=[door], sign=sign_tile(b), props=[], counter=[], style='plaster', roof='#2a6a9a')
    def keep():
        c = [p for p in sorted(inn, key=lambda p: (p[1], abs(p[0] - door[0]))) if p != ad]
        return c[0] if c else ad
    if role == 'church':
        alt = min(inn, key=lambda p: (p[1], abs(p[0] - door[0])))
        stn = (alt[0], alt[1] + 1)
        pri = next((p for p in inn if p[1] == alt[1] and p != alt), None) or next(p for p in inn if p not in (alt, stn, ad))
        base.update(id='saltmere_church', kind='church', name=OLD_CH.get('name', 'Saltmere Chapel'), keeper=OLD_CH.get('keeper', 'Sister Mare'),
                    altar=rel(alt), keeper_at=rel(pri), stand=rel(stn), style='stone', roof='#2a6a9a', note='0.3.12 the chapel (designer v2_church)')
        used = {alt, stn, pri, ad}
        for p in inn:
            if p not in used and p[1] > stn[1] and p[0] != door[0] and len(base['props']) < 6:
                base['props'].append(dict(object='pew', at=rel(p))); used.add(p)
        church = base; continue
    if role == 'bank':
        k = keep(); stn = (k[0], k[1] + 1) if (k[0], k[1] + 1) in inn and (k[0], k[1] + 1) != ad else ad
        base.update(from_old('saltmere_bank', keeper_at=rel(k), stand=rel(stn), style='stone', note="0.3.12 the bank keeps the old governor's house (designer v2_governor)"))
        for p in sorted([p for p in inn if p not in (k, stn, ad) and p[1] == k[1]], key=lambda p: -abs(p[0] - door[0]))[:2]:
            base['props'].append(dict(object='bank_chest', at=rel(p)))
    elif role == 'general':
        k = keep(); stn = (k[0], k[1] + 1) if (k[0], k[1] + 1) in inn and (k[0], k[1] + 1) != ad else ad
        base.update(from_old('saltmere_general', keeper_at=rel(k), stand=rel(stn), note='0.3.12 the chandlery (designer v2_warehouse_b)'))
    elif role == 'legs':
        k = keep()
        base.update(from_old('saltmere_legs', name='Saltmere Outfitter', keeper='Ewan Tackle', keeper_at=rel(k), stand=rel(ad if ad != k else door)))
    elif role == 'cook':
        k = keep(); stn = (k[0], k[1] + 1) if (k[0], k[1] + 1) in inn and (k[0], k[1] + 1) != ad else ad
        base.update(from_old('saltmere_cook', keeper_at=rel(k), stand=rel(stn), note='0.3.12 the harbour cookhouse (designer v2_tavern)'))
        top = sorted([p for p in inn if p[1] == k[1] and p != k], key=lambda p: -abs(p[0] - door[0]))
        if top: base['props'].append(dict(object='oven', at=rel(top[0])))
    elif role == 'smithy':
        def _inb(b_, x_, y_):   # 0.3.13 stations only where all 8 neighbours are building tiles (no reach-in through a diagonal)
            lx_, ly_ = x_ - b_['at'][0], y_ - b_['at'][1]
            return 0 <= ly_ < len(b_['rows']) and 0 <= lx_ < len(b_['rows'][0]) and b_['rows'][ly_][lx_] != '.'
        k = keep()
        base.update(from_old('saltmere_maces', keeper_at=rel(k), stand=rel(ad if ad != k else door), style='stone', roof='#5a6070',
                             note='0.3.13 the harbour forge (designer v3_smithy_large); furnace + anvil under the roof'))
        sp = sorted([p for p in inn if p not in (k, ad, tuple(door)) and abs(p[0] - door[0]) >= 2 and all(_inb(b, p[0] + a_, p[1] + c_) for a_ in (-1, 0, 1) for c_ in (-1, 0, 1))], key=lambda p: (p[1], -abs(p[0] - door[0])))
        base['props'] = [dict(object=o, at=rel(p)) for o, p in zip(['furnace', 'anvil'], sp[:2])]
    elif role == 'player_house':
        k = keep()
        base.update(from_old('saltmere_player', keeper_at=rel(k), stand=rel(ad if ad != k else door), note='0.3.12 the townhouse (designer v2_house_23)'))
    elif role == 'harbourmaster':
        k = keep()
        base.update(id='saltmere_harbourmaster', kind='hall', shop='', name='Harbourmaster', keeper='Jago Pellow', keeper_sprite='keeper_general', sign_sprite='sign_general',
                    keeper_at=rel(k), stand=rel(ad if ad != k else door),
                    greet=["Tides, berths and manifests. Mind the ropes on the quay.", "The channel's deep enough for a galleon at any tide. Mostly.",
                           "Keep clear of the black ship. Nobody signs her in."])
    elif role == 'tomb':
        base.update(id='saltmere_elijah_tomb', kind='house', shop='', name="Elijah's Tomb", keeper='', keeper_sprite='villager', sign_sprite='sign_house',
                    no_keeper=True, keeper_at=rel(door), stand=rel(door), style='stone', roof='#6a6a72',
                    note="0.3.13 Elijah's tomb (designer v3_elijah_tomb), walk-in, no keeper")
    elif role in ('rum', 'warehouse', 'lighthouse', 'home'):
        nm, kp = HOMES[hi % len(HOMES)]; hi += 1
        if role == 'rum': nm, kp = 'The Rum House', 'Bess Cardew'
        if role == 'warehouse': nm, kp = 'Salt Warehouse', 'Tobias Venn'   # 0.3.13 now in v2_warehouse_a
        if role == 'lighthouse': nm, kp = 'Saltmere Light', 'Old Wick'
        base.update(id='saltmere_' + ({'home': 'home_%d' % hi}.get(role, role)), kind='house', shop='', name=nm, keeper=kp, keeper_sprite='villager', sign_sprite='sign_house')
        cand = [p for p in inn if p != ad]
        if cand and len(inn) >= 2:
            k = cand[-1]; base.update(keeper_at=rel(k), stand=rel(ad if ad != k else door))
        else:
            base.update(no_keeper=True, keeper_at=rel(door), stand=rel(door))
        if not inn:
            base['closed'] = True; base.update(stand=[door[0], door[1] + 1], keeper_at=[door[0], door[1] + 1])
    out_b.append(base)
for b in out_b + [church]:
    for pr in b['props']: objs[tuple(pr['at'])] = pr['object']

# ---------------------------------------------------------------- props: market, docks, palms
MARKET = []
def addo(name, x, y, allow_road=False, on_dock=False):
    if free_tile(x, y, allow_road, on_dock): objs[(x, y)] = name; return True
    return False
pcx, pcy = int(PLAZA_C[0]), int(PLAZA_C[1])
for (ax, ay) in [(0, 0), (1, 0), (0, 1)]:
    if addo('sm_well', pcx + ax, pcy + ay, True): MARKET.append((pcx + ax, pcy + ay)); break
for i, s in enumerate(M['stalls']):
    a_ = 200 + i * 360 / len(M['stalls'])
    tx, ty = int(round(PLAZA_C[0] + (PRX - 1.2) * math.cos(math.radians(a_)))), int(round(PLAZA_C[1] + (PRY - 1) * math.sin(math.radians(a_))))
    for (ax, ay) in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)]:
        if addo('sm_' + s[3:], tx + ax, ty + ay, True): MARKET.append((tx + ax, ty + ay)); break
for nm in ['exchange_board', 'workbench', 'training_dummy']:
    for r_ in range(3, 9):
        if any(addo(nm, pcx + r_ * dx, pcy + dy, True) for dx, dy in ((1, 2), (-1, 2), (1, -2), (-1, -2), (1, 0), (-1, 0))): break
# docks: nets and crates (v1 clutter), mooring posts along the quay edge
DCL = ['sm3_' + n[3:] for n in M3['dock_clutter']]        # 0.3.13 the designer's 14 v3 dock props
ndk = 0
for x in range(qx0 + 1, qx1 - 1, 2):
    if x in PIERS or x - 1 in PIERS or x + 1 in PIERS or x + 2 in PIERS: continue
    if addo(DCL[ndk % len(DCL)], x, qy + 1, on_dock=True): ndk += 1
for p_ in PIERS:                                             # a few on the pier fingers, outer column only (inner one stays a walkway)
    for yy in (qy + 3, qy + 5):
        if addo(DCL[ndk % len(DCL)], p_ + 1, yy, on_dock=True): ndk += 1
# the town sign by the west road into town
for (x, y) in [(3, 13), (3, 17), (4, 13), (4, 17), (2, 12), (5, 12)]:
    if addo('sm3_town_sign', x, y): break
for x in range(qx0 + 2, qx1 - 1, 4):
    if addo('sm_mooring_post', x, qy - 1, True): pass
dock_objs = ndk
# fishing spots in the basin and the sea (the old harbour had them)
fs = 0
for (x, y) in [(28, 35), (41, 35), (52, 35), (75, 20), (76, 30), (74, 8)]:
    if 0 <= x < GW and grid[y][x] == '~' and (x, y) not in objs: objs[(x, y)] = 'fishing_spot'; fs += 1
rnd = random.Random(11)
SANDY = ['sm_palm_tall', 'sm_palm_lean', 'sm_palm_short', 'sm_palm_cluster', 'sm_agave']
GRASSY = ['sm_banana', 'sm_fern', 'sm_hibiscus', 'sm_palm_short', 'sm_flowerbed', 'sm_palm_tall', 'sm_agave']
for k in range(3000):
    x, y = rnd.randrange(2, GW - 1), rnd.randrange(2, GH - 1)
    if roadd[y * T + 8, x * T + 8] < 10: continue
    c = grid[y][x]
    if c == 's' and rnd.random() < .16: addo(rnd.choice(SANDY), x, y)
    elif c == 'g' and rnd.random() < .12: addo(rnd.choice(GRASSY), x, y)
for k in range(400):
    x, y = rnd.randrange(2, GW - 1), rnd.randrange(2, GH - 1)
    if grid[y][x] in 'sg' and 10 <= roadd[y * T + 8, x * T + 8] < 20 and rnd.random() < .3:
        addo(rnd.choice(['sm1_lamp_post', 'sm_crate_pile', 'sm_barrels', 'sm_cart', 'sm1_bench', 'sm1_lamp_post']), x, y)

# ---------------------------------------------------------------- ships (y-sorted decor on the water)
ships = []
clear = ndi.binary_dilation(landpx | dockpx, iterations=10)
def put_ship(n, tries, hull=1.0):
    im = L('ships', n); al = np.array(im)[..., 3] > 0; h, w = al.shape
    al = al.copy(); al[:int(h * (1 - hull))] = False          # only the hull must sit on water (masts may stand over the quay)
    for x, y in tries:
        if x < 0 or y < 0 or x + w > SW or y + h > SH: continue
        if not (clear[y:y + h, x:x + w] & al).any():
            ships.append((n, x, y)); clear[y:y + h, x:x + w] |= ndi.binary_dilation(al, iterations=6); return True
    return False
SHIP_TRIES_BASIN = [(x, y) for y in range(40 * T - 40, (qy + 1) * T - 160, -4) for x in range(qx0 * T, 60 * T, 4)]
SHIP_TRIES_SEA = [(x, y) for y in range(20, SH - 60, 8) for x in range(SW - 80, 62 * T, -8)]
def tries_for(n, base):
    w_, h_ = L('ships', n).size
    return [(x, y) for x, y in base if x + w_ <= SW and y + h_ <= SH]
put_ship('v3_ship_galleon', tries_for('v3_ship_galleon', SHIP_TRIES_BASIN + SHIP_TRIES_SEA), hull=.4)
put_ship('v3_ship_sloop', tries_for('v3_ship_sloop', SHIP_TRIES_SEA), hull=.5)
put_ship('v3_ship_sloop', tries_for('v3_ship_sloop', SHIP_TRIES_BASIN + SHIP_TRIES_SEA), hull=.5)
for i in (1, 2, 3):
    put_ship(f'v3_rowboat_{i}', [(x, y) for y in range((qy + 2) * T + 4, 40 * T, 4) for x in range(qx0 * T + 8 + i * 100, qx1 * T, 6)])
def hull_mask(n):   # the waterline part of each ship (galleon masts may stand over the quay, as in 0.3.12)
    al = np.array(L('ships', n))[..., 3] > 0; h = al.shape[0]; hf = .4 if 'galleon' in n else .5 if 'sloop' in n else 1.0
    al = al.copy(); al[:int(h * (1 - hf))] = False; return al
ship_fail = [n for n, x, y in ships if ((landpx | dockpx)[y:y + L('ships', n).height, x:x + L('ships', n).width] & hull_mask(n)).any()]
YSORT = [dict(path=f'{RES}/ships/{n}.png', pos=[x, y], base=L('ships', n).height) for n, x, y in ships]

NB3 = {'gulls', 'oars', 'fish_basket', 'rope_spool', 'bollard_rope', 'buoys', 'sacks', 'net_pile', 'fish_crate', 'lobster_pots'}   # small dock clutter does not block the quay
# ---------------------------------------------------------------- 0.3.13 harbour entrance over the north road (passage = gate tiles 43..45)
HE_X0 = 42 * T + 8 - HE['passage_px'][0] + 8            # passage x16..64 centred on the 3 road tiles 43..45
HE_X0 = 43 * T - HE['passage_px'][0]
HE_ROW = 4                                                 # base line on the bottom of tile row 4
HE_Y0 = (HE_ROW + 1) * T - HE['px'][1]
HE_PILLARS = []
for ty in (HE_ROW - 1, HE_ROW):
    for tx in (42, 46):
        HE_PILLARS.append((tx, ty)); objs.pop((tx, ty), None)
HE_PASS = [[x, y] for x in (43, 44, 45) for y in range(max(0, HE_Y0 // T), HE_ROW + 1)]
print('harbour entrance', HE_X0, HE_Y0, 'pillars', HE_PILLARS, 'passage', [grid[y][x] for x, y in HE_PASS])
for (tx, ty) in HE_PILLARS: grid[ty][tx] = 'P'

# ---------------------------------------------------------------- reachability
inside_walk = {}
BTILES = set((b['at'][0] + x, b['at'][1] + y) for b in blds for y, r in enumerate(b['rows']) for x, c in enumerate(r) if c != '.')
for b in out_b + [church]:
    rows = ART[b['art']]['plan'] if not b['flip'] else flip_plan(ART[b['art']]['plan'])
    for y, r in enumerate(rows):
        for x, c in enumerate(r):
            if c in 'oD' and not (c == 'D' and b.get('closed')): inside_walk[(b['at'][0] + x, b['at'][1] + y)] = True
for b in out_b + [church]:
    for key in ('keeper_at', 'altar'):
        if key in b and not b.get('no_keeper'): inside_walk.pop(tuple(b[key]), None)
    for pr in b['props']: inside_walk.pop(tuple(pr['at']), None)
def walk(x, y):
    if not (0 <= x < GW and 0 <= y < GH) or (x, y) in objs and objs[(x, y)][4:] not in NB3: return False
    return grid[y][x] == '=' or grid[y][x] in 'sg:-' and (x, y) not in BTILES or (x, y) in inside_walk
start = tuple(GATES['west'][1]); seen = {start}; q = [start]
while q:
    x, y = q.pop()
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        n2 = (x + dx, y + dy)
        if n2 not in seen and walk(*n2): seen.add(n2); q.append(n2)
fails = []
for side, g in GATES.items():
    if tuple(g[1]) not in seen: fails.append('gate ' + side)
for b in out_b + [church]:
    if not b.get('closed') and tuple(b['door'][0]) not in seen: fails.append('door ' + b['id'])
    if not b.get('no_keeper') and not b.get('closed') and tuple(b['stand']) not in seen: fails.append('stand ' + b['id'])
    for pr in b['props']:
        p = pr['at']
        if not any((p[0] + a, p[1] + c) in seen for a, c in ((1, 0), (-1, 0), (0, 1), (0, -1))): fails.append('prop %s %s' % (b['id'], pr['object']))
for px_ in PIERS:
    if (px_, qy + 6) not in seen: fails.append('pier %d' % px_)
road_fails = []; overlap = []
for b in blds:
    al = drawn(b['art'], b['flip']); x0, y0 = b['px']; h, w = al.shape
    if (road[y0:y0 + h, x0:x0 + w] & al[:SH - y0, :SW - x0]).any(): road_fails.append(b['art'] + str(b['at']))
_cells = collections.Counter((b['at'][0] + x, b['at'][1] + y) for b in blds for y, r in enumerate(b['rows']) for x, c in enumerate(r) if c != '.')
overlap = [p for p, n in _cells.items() if n > 1]

# ---------------------------------------------------------------- register props (sprites.json / objects.json)
SP = os.path.join(REPO, 'data/sprites.json'); OB = os.path.join(REPO, 'data/objects.json')
s_ = json.load(open(SP)); o_ = json.load(open(OB))
NONBLOCK = {'flowerbed', 'fern'}
NAMES = {'palm_tall': 'Palm', 'palm_lean': 'Palm', 'palm_short': 'Palm', 'palm_cluster': 'Palms', 'crate_pile': 'Crates', 'banana': 'Banana plant',
         'well': 'Well', 'barrels': 'Barrels', 'net_hanging': 'Fishing nets', 'fish_rack': 'Fish drying rack', 'rope_coil': 'Rope', 'crate_stack': 'Crates',
         'barrel_stack': 'Barrels', 'mooring_post': 'Mooring post', 'lamp_post': 'Lamp post'}
def reg(oid, rel_path, nm, blocks=True):
    im = Image.open(os.path.join(DST, rel_path))
    s_['objects'][oid] = {'path': f'{RES}/{rel_path}', 'frame_size': [im.width, im.height], 'frames': 1, 'anchor': 'bottom',
                          'note': '0.3.12/0.3.13 designer Saltmere prop (art_handoff/towns/saltmere)'}
    o_['objects'][oid] = {'name': nm, 'sprite': oid, 'blocks': blocks, 'type': 'prop'}
for f in sorted(x for x in os.listdir(os.path.join(DST, 'props')) if x.endswith('.png')):
    n = f[3:-4]
    reg('sm_' + n, 'props/' + f, 'Market stall' if n.startswith('stall') else NAMES.get(n, n.replace('_', ' ').capitalize()), n not in NONBLOCK)
for f in sorted(x for x in os.listdir(os.path.join(DST, 'props_v1')) if x.endswith('.png')):
    n = f[:-4]; reg('sm1_' + n, 'props_v1/' + f, NAMES.get(n, n.replace('_', ' ').capitalize()))
reg('sm_mooring_post', 'docks/mooring_post.png', 'Mooring post')
for f in sorted(x for x in os.listdir(os.path.join(DST, 'props_v3')) if x.endswith('.png')):
    n = f[3:-4]; reg('sm3_' + n, 'props_v3/' + f, {'town_sign': 'Saltmere', 'gulls': 'Gulls', 'cargo_hoist': 'Cargo hoist'}.get(n, n.replace('_', ' ').capitalize()), n not in NB3)
json.dump(s_, open(SP, 'w'), indent=1); json.dump(o_, open(OB, 'w'), indent=1)

# ---------------------------------------------------------------- write data
GROUND = {'s': 'sand', 'g': 'grass_tropic', ':': 'cobble', '-': 'path', '~': 'water', '=': 'planks', 'P': 'art_wall'}
OBJ_CH = {}
chars = iter('ABCEFHIJKLMNOQRSTUVWXYZabcdefhijklmnopqrtuvwxyz0123456789!$%&()*+,/;<>?@[]_{|}^')
STATIONS = {'pew', 'bank_chest', 'oven', 'furnace', 'anvil'}
for o in sorted(set(objs.values()) - STATIONS): OBJ_CH[o] = next(chars)
rows = []
for y in range(GH):
    r = ''
    for x in range(GW):
        o = objs.get((x, y))
        r += OBJ_CH[o] if o in OBJ_CH else grid[y][x]
    rows.append(r)
objects = {}
for o, ch in OBJ_CH.items():
    gs = [GROUND[grid[p[1]][p[0]]] for p, v in objs.items() if v == o]
    objects[ch] = {'object': o, 'ground': collections.Counter(gs).most_common(1)[0][0]}
_ta_p = os.path.join(REPO, 'data/town_art.json')
_ta = json.load(open(_ta_p)) if os.path.exists(_ta_p) else dict(buildings={})
_ta['buildings'] = {k: v for k, v in _ta.get('buildings', {}).items() if k not in ART}; _ta['buildings'].update(ART)
json.dump(_ta, open(_ta_p, 'w'), indent=1)
old = json.load(open(os.path.join(REPO, 'data/towns/saltmere.json')))
spawn = [int(PLAZA_C[0]), int(PLAZA_C[1]) + 2]
while not walk(*spawn) or tuple(spawn) not in seen: spawn[0] += 1
town = dict(id='saltmere', name='Saltmere', origin=ORIGIN, spawn=[ORIGIN[0] + spawn[0], ORIGIN[1] + spawn[1]],
            tiles=GROUND, objects=objects, roof='#2a6a9a', building_style='plaster',
            specialists=old['specialists'], price_bias=old['price_bias'],
            tagline='Open harbour town of white houses and blue roofs: a quay and three piers on a sheltered basin, a channel to the sea and a lighthouse on the spit.',
            theme='saltmere', walls='none', gates=GATES, dry_center=OLD_CENTER, cliff_clear=1,
            harbour=dict(quay=[qx0, qy, qx1 - qx0, 2], piers=[[p, qy + 2, 2, 5] for p in PIERS], channel=[list(p) for p in CH_PTS[:-1]],
                         channel_min_width=int(chan_w), open_to_sea=CHANNEL_OK),
            art=dict(market=[list(p) for p in MARKET], plaza_px=[int(PLAZA_C[0] * T), int(PLAZA_C[1] * T)], ground_decal=f'{RES}/ground_decal.png',
                     ysort=YSORT + [dict(path=f'{RES}/buildings/v3_harbour_entrance_floor.png', pos=[HE_X0, HE_Y0], base=HE['px'][1]),
                                    dict(path=f'{RES}/buildings/v3_harbour_entrance_walls.png', pos=[HE_X0, HE_Y0], base=HE['px'][1])],
                     fades=[dict(path=f'{RES}/buildings/v3_harbour_entrance_roof.png', pos=[HE_X0, HE_Y0], tiles=HE_PASS)]),
            harbour_entrance=dict(at=[HE_X0, HE_Y0], passage=HE_PASS, pillars=[list(p) for p in HE_PILLARS], note='0.3.13 designer v3_harbour_entrance over the north road'),
            buildings=out_b, rows=rows,
            note="0.3.13 generated by tools/world/build_saltmere_v3.py from the designer's Saltmere v2 set + v3 add-on; no walls, no fort (Hudson)")
json.dump(town, open(os.path.join(REPO, 'data/towns/saltmere.json'), 'w'), indent=1)
_ck['towns']['saltmere'] = church
json.dump(_ck, open(os.path.join(REPO, 'data/churches.json'), 'w'), indent=1)
NP = os.path.join(REPO, 'data/town_npcs.json'); npcs = json.load(open(NP))
def near_walk(x, y):
    for r_ in range(0, 8):
        for dx in range(-r_, r_ + 1):
            for dy in range(-r_, r_ + 1):
                if (x + dx, y + dy) in seen and grid[y + dy][x + dx] in ':-=sg': return [x + dx, y + dy]
BEATS = [[(4, 15), (20, 15.5), (30, 15)], [(44, 2), (42, 10), (36, 13)], [(8, 29), (24, 29), (40, 29)], [(40, 29), (56, 29), (63, 27)],
         [(24, 31), (24, 37)], [(36, 31), (36, 37)], [(48, 31), (48, 37)], [(12, 18), (11, 27)], [(39, 16), (52, 17.5), (58, 25)], [(8, 36), (24, 43), (48, 43), (62, 43)]]
guards = [dict(enemy='town_guard', patrol=[near_walk(int(x), int(y)) for x, y in b]) for b in BEATS]
npcs['towns']['saltmere'] = dict(guards=guards,
                                 citizens=dict(enemy='citizen', count=5, area=[int(PLAZA_C[0] - 7), int(PLAZA_C[1] - 4), 15, 15]),
                                 note='0.3.12 Saltmere has no walls or gates to guard: all 10 guards (2 patrols + the 8 former gate guards) walk town beats')
json.dump(npcs, open(NP, 'w'), indent=1)

# ---------------------------------------------------------------- debug composite
dbg = Image.new('RGBA', (SW, SH), (40, 75, 92, 255)); dbg.alpha_composite(Image.fromarray(dec))
items = [(b['px'][1] + BM[b['art']]['px'][1], 'b', b) for b in blds] + [(y * T + T, 'p', (o, x, y)) for (x, y), o in objs.items()] + \
        [(y + L('ships', n).height, 's', (n, x, y)) for n, x, y in ships]
for _, kind, it in sorted(items, key=lambda t: t[0]):
    if kind == 'b':
        for l in BM[it['art']]['layers']:
            im = L('buildings', l); im = im.transpose(Image.FLIP_LEFT_RIGHT) if it['flip'] else im
            dbg.alpha_composite(im, tuple(it['px']))
    elif kind == 's': dbg.alpha_composite(L('ships', it[0]), (it[1], it[2]))
    else:
        o, x, y = it; p = s_['objects'].get(o, {}).get('path', '')
        if p.startswith(RES):
            im = Image.open(os.path.join(DST, p[len(RES) + 1:])).convert('RGBA')
            dbg.alpha_composite(im, (int(x * T + 8 - im.width / 2), max(0, int(y * T + T - im.height))))
        else: ImageDraw.Draw(dbg).rectangle([x * T + 3, y * T + 3, x * T + 12, y * T + 12], fill=(220, 60, 60, 255))
os.makedirs(os.path.join(REPO, 'build'), exist_ok=True)
dbg.save(os.path.join(REPO, 'build/saltmere_layout_check.png'))
open('/tmp/sm/grid.txt', 'w').write('\n'.join(rows))
print('quay v3', dict(QUAY3)); print('buildings', len(blds), 'objects', len(objs), 'dock clutter', dock_objs, 'fishing', fs, 'road overlaps', road_fails, 'tile overlaps', overlap,
      'reach fails', fails, 'ship fails', ship_fail, 'ships', [s[0] for s in ships], 'channel', CHANNEL_OK, chan_w)
sys.exit(1 if road_fails or overlap or fails or ship_fail or not CHANNEL_OK or chan_w < 4 else 0)
