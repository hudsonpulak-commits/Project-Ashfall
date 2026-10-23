"""0.3.16 Millbrook from the sprite bot's villages/v1 set (art_handoff/towns/villages/v1, READ-ONLY: copied, never written).
Designer geometry = src/preview_millbrook.py (84x60 tiles, seed 11): millpond + brook, meadow, 5 wheat fields, cow pasture,
loose 45deg dirt roads, buildings at layout/layout.json (snapped to the tile grid), a spur to every door.
Writes assets/sprites/towns/villages/millbrook/*, data/towns/millbrook.json, data/town_art.json (mb_* plans), registers props.
Gameplay kept: fields = village farms (game fences + wheat), pasture = cows, well/quern/hearth, cottages that talk."""
import json, math, os, random, shutil, sys, collections
from collections import deque
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SRC = '/workspace/art_handoff/towns/villages/v1'
DST = os.path.join(REPO, 'assets/sprites/towns/villages/millbrook')
RES = 'res://assets/sprites/towns/villages/millbrook'
T = 16; GW, GH = 84, 60; SW, SH = GW * T, GH * T
ORIGIN = [143, -146]      # world tile of the village's top-left (land between the north lake and the Cinder road)

for sub in ('tiles', 'buildings', 'props', 'npcs'):
    os.makedirs(os.path.join(DST, sub), exist_ok=True)
    for f in sorted(os.listdir(os.path.join(SRC, sub))):
        if f.endswith('.png') and 'closeup' not in f: shutil.copyfile(os.path.join(SRC, sub, f), os.path.join(DST, sub, f))
shutil.copyfile(os.path.join(SRC, 'manifest.json'), os.path.join(DST, 'manifest_designer.json'))
shutil.copyfile(os.path.join(SRC, 'README.md'), os.path.join(DST, 'README_designer.md'))
M = json.load(open(os.path.join(SRC, 'manifest.json'))); BM = {b['name']: b for b in M['buildings']}
def L(sub, n): return Image.open(os.path.join(DST, sub, n if n.endswith('.png') else n + '.png')).convert('RGBA')
sys.path.insert(0, os.path.join(SRC, 'src'))
import diagtiles as dg

def plan_of_v2(b):
    E = b['footprint_origin_px'][1]; W, H = b['tiles']; d = tuple(b['door_tile']); H = d[1] + 1
    def inr(r, cx, cy): return r[0] <= cx < r[0] + r[2] and r[1] <= cy < r[1] + r[3]
    rows = []
    for y in range(H):
        r = ''
        for x in range(W):
            cx, cy = x * T + 8, E + y * T + 8
            if (x, y) == d: r += 'D'
            elif 0 < x < W - 1 and 0 < y < H - 1 and (inr(b['clear_area_px'], cx, cy) or inr(b['door_lane_px'], cx, cy)): r += 'o'
            else: r += '#'
        rows.append(r)
    return rows
ART = {}
for b in M['buildings']:
    lay = b['layers']; P = lambda l: f"{RES}/buildings/{l if l.endswith('.png') else l + '.png'}"
    ART[b['name']] = dict(tiles=[b['tiles'][0], b['door_tile'][1] + 1], px=b['px'], origin_y=b['footprint_origin_px'][1], inset_x=0, door_tile=b['door_tile'],
                          storeys=b.get('storeys', 1), floor=P(lay[0]), walls=P(lay[1]), fade=[P(l) for l in b['fade_group']],
                          night=(P(b['night_layer']) if b.get('night_layer') else ''), plan=plan_of_v2(b), note='0.3.16 Millbrook v1 (villages/v1)')
def flip_plan(rows): return [r[::-1] for r in rows]

# ---------------------------------------------------------------- designer terrain (preview_millbrook.py, same seed)
nr = np.random.RandomState(11); rnd = random.Random(11)
VY, VX = np.mgrid[:GH + 1, :GW + 1].astype(float)
nz = ndi.gaussian_filter(nr.rand(GH + 1, GW + 1), 2.5); nz = (nz - nz.min()) / (nz.max() - nz.min())
pond = (((VX - 66) / 7.5) ** 2 + ((VY - 11) / 4.6) ** 2) * (1 + .25 * (nz - .5)) <= 1
# 0.3.16 the brook rises inside the village (no water running off the rect edge into world grass)
brook = dg.line_mask(VY.shape, [(66, 8), (68, 4.5), (66.5, 3.2)], 1.0)
WAT = pond | brook; LV = ~WAT
MEAD = (nz > .62) & LV
FIELDS = [(3, 4, 16, 9, 'ripe'), (3, 15, 8, 8, 'young'), (12, 15, 8, 8, 'harvested'), (68, 38, 13, 9, 'ripe'), (68, 49, 13, 8, 'sprout')]
PAST = (32, 44, 20, 12)
MAIN = [[(-1, 30), (10, 30), (16, 27), (26, 27), (31, 31), (42, 31), (47, 27), (58, 27), (63, 32), (85, 32)],
        [(42, 31), (42, 38), (39, 41), (39, 43)], [(58, 27), (58, 20), (54, 16), (54, 12)], [(16, 27), (16, 24), (11, 24)],
        [(63, 32), (66, 35), (66, 37)], [(26, 27), (26, 19), (31, 14), (44, 14)], [(31, 31), (28, 34), (28, 47), (24, 51), (14, 51)]]
RV = np.zeros_like(LV)
for i, p in enumerate(MAIN): RV |= dg.line_mask(VY.shape, p, 1.15 if i == 0 else .85)
RV |= ((VX - 36) / 3.4) ** 2 + ((VY - 29) / 2.4) ** 2 <= 1
RV &= LV
FT = np.zeros((GH, GW), bool)
for (x0, y0, w, h, s) in FIELDS + [PAST + ('pasture',)]: FT[y0:y0 + h, x0:x0 + w] = True
TILL = np.zeros_like(LV)
for (x0, y0, w, h, s) in FIELDS: TILL[y0 + 1:y0 + h, x0 + 1:x0 + w] = True
fr = dg.frames_of
bits = np.vectorize(lambda f: bin(int(f)).count('1'))
CNT_L = bits(fr(LV)); CNT_R = bits(fr(RV))

# ---------------------------------------------------------------- tile grid
grid = [['g'] * GW for _ in range(GH)]
for y in range(GH):
    for x in range(GW):
        if CNT_L[y, x] < 3: grid[y][x] = '~'
        elif CNT_R[y, x] >= 3: grid[y][x] = ':'
FIELD_T = set(); FIELD_M = set()
for (x0, y0, w, h, s) in FIELDS + [PAST + ('pasture',)]:
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            FIELD_T.add((x, y))
            if grid[y][x] == ':': grid[y][x] = 'g'      # fields win over the designer's road ends (gate stubs re-added below)
    for y in range(y0 - 1, y0 + h + 1):
        for x in range(x0 - 1, x0 + w + 1): FIELD_M.add((x, y))

# ---------------------------------------------------------------- buildings at the designer layout, snapped to tiles
LAYOUT = json.load(open(os.path.join(SRC, 'layout', 'layout.json')))['buildings']
blds = []; BT = {}; tile_used = np.zeros((GH, GW), bool)
for y in range(GH):
    for x in range(GW): tile_used[y, x] = grid[y][x] in '~' or (x, y) in FIELD_M
def try_at(n, ox, oy):
    rows = ART[n]['plan']
    for ly, r in enumerate(rows):
        for lx, c in enumerate(r):
            q = (ox + lx, oy + ly)
            if not (1 <= q[0] < GW - 1 and 1 <= q[1] < GH - 2): return False
            if tile_used[q[1], q[0]] or grid[q[1]][q[0]] != 'g' or q in BT: return False
    d = ART[n]['door_tile']; fx, fy = ox + d[0], oy + d[1] + 1
    if fy >= GH - 1 or (fx, fy) in BT or grid[fy][fx] == '~' or (fx, fy) in FIELD_M: return False
    return True
ROLE = {'mb_inn': 'inn', 'mb_mill': 'mill', 'mb_rat_barn': 'rat_barn', 'mb_granary': 'granary', 'mb_cowshed': 'cowshed',
        'mb_farmhouse_a': 'farmhouse', 'mb_farmhouse_b': 'farmhouse', 'ch_ruin_chapel': 'chapel'}
moved = []
for lb in LAYOUT:
    n = lb['name']; ox0, oy0 = int(round(lb['x'] / T)), int(round(lb['y'] / T)); done = False
    for r_ in range(0, 4):
        for dx in range(-r_, r_ + 1):
            for dy in range(-r_, r_ + 1):
                if max(abs(dx), abs(dy)) != r_ or done: continue
                if try_at(n, ox0 + dx, oy0 + dy):
                    ox, oy = ox0 + dx, oy0 + dy; done = True
        if done: break
    if not done: print('NO ROOM', n); sys.exit(1)
    if (ox, oy) != (ox0, oy0): moved.append((n, ox - ox0, oy - oy0))
    rows = ART[n]['plan']; d = ART[n]['door_tile']
    for ly, r in enumerate(rows):
        for lx, c in enumerate(r): BT[(ox + lx, oy + ly)] = n; tile_used[oy + ly, ox + lx] = True
    blds.append(dict(art=n, at=[ox, oy], rows=rows, door=[ox + d[0], oy + d[1]], role=ROLE.get(n, 'home'), px=[ox * T, oy * T]))
print('snapped buildings moved', moved)

# door spurs: BFS from the tile below the door to the road network
def spur_route(fx, fy):
    prev = {(fx, fy): None}; dq = deque([(fx, fy)])
    while dq:
        c = dq.popleft()
        if grid[c[1]][c[0]] == ':':
            r = []; k = c
            while k: r.append(k); k = prev[k]
            return r[::-1]
        for dx, dy in ((0, 1), (1, 0), (-1, 0), (0, -1)):
            q = (c[0] + dx, c[1] + dy)
            if 0 < q[0] < GW - 1 and 0 < q[1] < GH - 1 and q not in prev and q not in BT and grid[q[1]][q[0]] in 'g:' and q not in FIELD_T:
                prev[q] = c; dq.append(q)
    return None
SPUR = np.zeros_like(LV)
for b in blds:
    dx_, dy_ = b['door']; route = spur_route(dx_, dy_ + 1)
    if route is None: print('NO SPUR', b['art']); sys.exit(1)
    b['route'] = route
    pts = [(dx_ + .5, dy_ + .4), (dx_ + .5, dy_ + 1.5)] + [(c[0] + .5, c[1] + .5) for c in route[1:]]
    SPUR |= dg.line_mask(VY.shape, pts, .62)
    for q in route:
        if grid[q[1]][q[0]] == 'g': grid[q[1]][q[0]] = ':'
# farm / pasture gates: the rim tile (not a corner) nearest a road tile; a short track joins it
FARMS = []
def nearest_gate(x0, y0, w, h):
    rim = [(x, y0) for x in range(x0 + 1, x0 + w - 1)] + [(x, y0 + h - 1) for x in range(x0 + 1, x0 + w - 1)] + \
          [(x0, y) for y in range(y0 + 1, y0 + h - 1)] + [(x0 + w - 1, y) for y in range(y0 + 1, y0 + h - 1)]
    best = None
    for (gx, gy) in rim:
        out = (gx, gy - 1) if gy == y0 else (gx, gy + 1) if gy == y0 + h - 1 else (gx - 1, gy) if gx == x0 else (gx + 1, gy)
        if not (0 < out[0] < GW - 1 and 0 < out[1] < GH - 1) or out in BT or out in FIELD_T or grid[out[1]][out[0]] == '~': continue
        r = spur_route(*out)
        if r and (best is None or len(r) < len(best[2])): best = ((gx, gy), out, r)
    return best
for i, f in enumerate(FIELDS + [PAST + ('pasture',)]):
    x0, y0, w, h, s = f; g = nearest_gate(x0, y0, w, h)
    if g is None: print('NO GATE', f); sys.exit(1)
    (gx, gy), out, r = g
    SPUR |= dg.line_mask(VY.shape, [(gx + .5, gy + .5), (out[0] + .5, out[1] + .5)] + [(c[0] + .5, c[1] + .5) for c in r[1:]], .7)
    for q in r:
        if grid[q[1]][q[0]] == 'g': grid[q[1]][q[0]] = ':'
    FARMS.append(dict(rect=[x0, y0, w, h], gate=[gx, gy], stage=s, route=r))
RVA = (RV | SPUR) & LV
for _ in range(4):
    F = fr(RVA); bad = (F == 5) | (F == 10)
    if not bad.any(): break
    for y, x in zip(*np.nonzero(bad)): RVA[y:y + 2, x:x + 2] = True
RVA &= LV

# ---------------------------------------------------------------- ground decal: water, bank, meadow, tilled, brighter worn road, fade edge
def strip(n): return np.array(L('tiles', n))
landT = fr(LV) == 15
WD, WS = strip('vl_water_deep_4f'), strip('vl_water_shallow_4f'); dT = ndi.distance_transform_edt(~landT)
base = np.zeros((SH, SW, 4), np.uint8)
for y in range(GH):
    for x in range(GW): base[y * 16:y * 16 + 16, x * 16:x * 16 + 16] = (WD if dT[y, x] > 2.5 else WS)[:, (x + y) % 4 * 16:(x + y) % 4 * 16 + 16]
img = Image.fromarray(base)
# grass fill under everything dry so the decal is opaque where the bank says land (the world grass only shows at the faded rim)
gf = strip('vl_grass_fill')[:16, :16]
for n, V in [('vl_diag_bank', LV), ('vl_diag_meadow', MEAD & LV), ('vl_diag_tilled', TILL & LV), ('vl_diag_road', RVA)]:
    F = fr(V); A = strip(n).copy()
    if n == 'vl_diag_road':      # Hudson's rule: brighter, worn roads (lift + warm the dirt, keep the pixel texture)
        a = A[..., :3].astype(float); a = a * 1.16 + np.array([10, 7, 2]); A[..., :3] = np.clip(a, 0, 255).astype(np.uint8)
    lay = np.zeros((SH, SW, 4), np.uint8)
    for y, x in zip(*np.nonzero(F)): lay[y * 16:y * 16 + 16, x * 16:x * 16 + 16] = A[:, F[y, x] * 16:F[y, x] * 16 + 16]
    img.alpha_composite(Image.fromarray(lay))
dec = np.array(img)
_rp = np.random.RandomState(17)
ex = np.minimum(np.arange(SW), SW - 1 - np.arange(SW))[None, :] / T
ey = np.minimum(np.arange(SH), SH - 1 - np.arange(SH))[:, None] / T
_ed = np.minimum(ex, ey)
_c1 = ndi.gaussian_filter(_rp.rand(SH, SW), 7.0); _c1 = (_c1 - _c1.min()) / (_c1.max() - _c1.min()); _c2 = _rp.rand(SH, SW)
_keep = _ed > (.6 + 3.2 * _c1 + .9 * (_c2 - .5))
dec[..., 3] = np.where(_keep, dec[..., 3], 0).astype(np.uint8)
Image.fromarray(dec).save(os.path.join(DST, 'ground_decal.png'))

# ---------------------------------------------------------------- objects
objs = {}
def door_zone(x, y):
    return any(abs(x - b['door'][0]) <= 1 and b['door'][1] <= y <= b['door'][1] + 2 for b in blds)
ROUTES = {q for b in blds for q in b['route']} | {q for f in FARMS for q in f['route']}
def free(x, y, path=False):
    if not (1 <= x < GW - 1 and 1 <= y < GH - 1) or (x, y) in objs or (x, y) in BT or (x, y) in FIELD_M or door_zone(x, y): return False
    if (x, y) in ROUTES and not path: return False
    if x <= 2 and 27 <= y <= 33: return False   # the west gate mouth
    return grid[y][x] in ('g:' if path else 'g')
def addo(n, x, y, path=False):
    if free(x, y, path): objs[(x, y)] = n; return True
    return False
GREEN = (36, 29)
def near(n, cx, cy, path=True, rmax=9):
    for r_ in range(1, rmax):
        for dx in range(-r_, r_ + 1):
            for dy in range(-r_, r_ + 1):
                if max(abs(dx), abs(dy)) == r_ and addo(n, cx + dx, cy + dy, path): return (cx + dx, cy + dy)
    print('no room for', n); sys.exit(1)
WELL = near('vl_well_station', 39, 26, path=False)
QUERN = near('quern', 33, 26, path=False)
HEARTH = near('hearth', 30, 25, path=False)
BYB = {b['art']: b for b in blds}
rb = BYB['mb_rat_barn']; inn = BYB['mb_inn']
def beside(b, cand, n, path=False):
    dx, dy = b['door']
    for ax, ay in cand:
        if addo(n, dx + ax, dy + ay, path): return (dx + ax, dy + ay)
    return None
beside(rb, [(-4, 1), (-5, 1), (-4, 2), (4, 1)], 'mb_bounty_board')
beside(rb, [(2, 0), (2, 1), (3, 1)], 'mb_sign_rats')
beside(rb, [(-3, 2), (3, 3), (-2, 4), (4, 4)], 'vl_sack_gnawed'); beside(rb, [(3, 2), (-3, 4), (5, 3)], 'vl_rat_bones')
beside(inn, [(2, 0), (2, 1), (-2, 1)], 'mb_sign_inn')
mill = BYB['mb_mill']
beside(mill, [(3, 1), (-3, 1), (3, 2)], 'vl_millstone'); beside(mill, [(-2, 1), (2, 2), (-3, 2)], 'vl_sack')
# pasture props stay outside the fenced rect (cows wander inside); field dressing at the field rims (outside)
cnt = collections.Counter(); rn = random.Random(23)
SCAT = [('vl_tree_oak', 16), ('vl_tree_oak_b', 10), ('vl_tree_autumn', 6), ('vl_bush', 20), ('vl_bush_flowers', 10), ('vl_barrel', 8), ('vl_crates', 5),
        ('vl_cart', 2), ('vl_lamp', 8), ('vl_haystack', 5), ('vl_hay_bale', 5), ('vl_trough', 2), ('vl_scarecrow', 3), ('vl_wheat_sheaf', 6)]
road_d = ndi.distance_transform_edt(np.array([[grid[y][x] != ':' for x in range(GW)] for y in range(GH)]))
for n, k in SCAT:
    tries = 0
    while cnt[n] < k and tries < 4000:
        tries += 1; x, y = rn.randrange(2, GW - 2), rn.randrange(2, GH - 2)
        if any(objs.get((x + a, y + b_)) for a in (-1, 0, 1) for b_ in (-1, 0, 1)): continue
        if any((x + a, y + b_) in BT for a in (-1, 0, 1) for b_ in (-1, 0, 2)): continue
        rd = road_d[y, x]
        if n.startswith('vl_tree') and (rd < 4 or 22 < x < 62 and 10 < y < 44): continue
        if n in ('vl_barrel', 'vl_crates', 'vl_lamp', 'vl_cart') and not (1.5 <= rd <= 2.5): continue
        if n in ('vl_haystack', 'vl_hay_bale', 'vl_trough', 'vl_scarecrow', 'vl_wheat_sheaf') and not any((x + a, y + b_) in FIELD_M and (x + a, y + b_) not in FIELD_T for a in (-1, 0, 1) for b_ in (-1, 0, 1)) and min(abs(x - fx) for fx in (1,)) >= 0 and \
           not any(abs(x - (f['rect'][0] + f['rect'][2] // 2)) < f['rect'][2] // 2 + 3 and abs(y - (f['rect'][1] + f['rect'][3] // 2)) < f['rect'][3] // 2 + 3 for f in FARMS): continue
        if addo(n, x, y): cnt[n] += 1
# the old ruined chapel: graves + rubble about it
ch = BYB['ch_ruin_chapel']
for n, k in (('vl_grave_a', 4), ('vl_grave_b', 4), ('vl_cross_broken', 2), ('vl_rubble', 3)):
    t_ = 0
    while cnt[n] < k and t_ < 400:
        t_ += 1; x, y = ch['door'][0] + rn.randint(-7, 4), ch['door'][1] + rn.randint(-8, 5)
        if addo(n, x, y): cnt[n] += 1
print('props', dict(cnt))

# ---------------------------------------------------------------- reachability (from the green, through doors, to every gate)
inside_walk = set()
for b in blds:
    for y, r in enumerate(b['rows']):
        for x, c in enumerate(r):
            if c in 'oD': inside_walk.add((b['at'][0] + x, b['at'][1] + y))
NONBLOCK = {'vl_rat_bones', 'vl_sack_gnawed', 'vl_wheat_sheaf', 'vl_bush_flowers'}
fence_t = set()
for f in FARMS:
    x0, y0, w, h = f['rect']
    for x in range(x0, x0 + w):
        fence_t |= {(x, y0), (x, y0 + h - 1)}
    for y in range(y0, y0 + h): fence_t |= {(x0, y), (x0 + w - 1, y)}
    fence_t.discard(tuple(f['gate']))
def walk(x, y):
    if not (0 <= x < GW and 0 <= y < GH): return False
    o = objs.get((x, y))
    if o and o not in NONBLOCK: return False
    if (x, y) in fence_t: return False
    return grid[y][x] in 'g:' and (x, y) not in BT or (x, y) in inside_walk
GATE = (0, 30)
for y in range(28, 33):
    if grid[y][0] == ':': GATE = (0, y); break
start = GATE; seen = {start}; q = [start]
while q:
    x, y = q.pop()
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        n2 = (x + dx, y + dy)
        if n2 not in seen and walk(*n2): seen.add(n2); q.append(n2)
fails = []
for b in blds:
    if tuple(b['door']) not in seen: fails.append('door ' + b['art'])
for f in FARMS:
    if tuple(f['gate']) not in seen: fails.append('gate %s' % f['rect'])
if (GW - 1, 32) not in seen and not any((GW - 1, y) in seen for y in range(29, 35)): fails.append('east road end')
print('reach fails', fails)

# ---------------------------------------------------------------- building entries
def interior(b):
    ox, oy = b['at']
    return sorted([(ox + x, oy + y) for y, r in enumerate(b['rows']) for x, c in enumerate(r) if c == 'o'], key=lambda p: (p[1], p[0]))
def sign_tile(b):
    dx, dy = b['door']
    for sx in (dx + 1, dx - 1):
        lx = sx - b['at'][0]
        if 0 <= lx < len(b['rows'][0]) and b['rows'][dy - b['at'][1]][lx] == '#': return [sx, dy]
    return [dx, dy]
NAMES = {'inn': ("The Millwheel Inn", 'Hob Miller'), 'mill': ("Millbrook windmill", 'Wenna Thresh'), 'rat_barn': ("The rat barn", 'Old Corin'),
         'granary': ('Granary', 'Dora Sheaf'), 'cowshed': ('Cowshed', 'Abel Byre'), 'chapel': ('Ruined chapel', '')}
HOMES = [("Miller's cottage", 'Tom Miller'), ("Thresh's cottage", 'Bet Thresh'), ("Corin's cottage", 'Ada Corin'), ("Furrow House", 'Ned Furrow'),
         ("The Sheaves' house", 'Molly Sheaf'), ("Brookside", 'Ivo Brook'), ("Hayloft Cottage", 'Pell Hay'), ("The Barleys' house", 'Rose Barley'),
         ("Millpond End", 'Sam Ponder'), ("Wheatear House", 'Lise Ear'), ("Upper Farm", 'Jory Field'), ("Lower Farm", 'Mags Field')]
out_b = []; hi = 0
for i, b in enumerate(blds):
    inn_t = interior(b); door = tuple(b['door']); ad = (door[0], door[1] - 1)
    role = b['role']
    if role in NAMES: nm, kp = NAMES[role]
    else: nm, kp = HOMES[hi % len(HOMES)]; hi += 1
    e = dict(id='millbrook_%s' % (b['art'][3:] if b['art'].startswith('mb_') else b['art']), kind='house', shop='', name=nm, keeper=kp or 'Villager',
             keeper_sprite='villager', sign_sprite='sign_house', roof='#a0784a', art=b['art'], flip=False, at=b['at'], door=[list(door)], sign=sign_tile(b), props=[], counter=[],
             note='0.3.16 Millbrook v1 (designer %s)' % b['art'])
    cand = [p for p in inn_t if p != ad and abs(p[0] - door[0]) + abs(p[1] - door[1]) >= 2]
    if kp and ad in inn_t and cand:
        k = min(cand, key=lambda p: (p[1], abs(p[0] - door[0])))
        e.update(keeper_at=list(k), stand=list(ad))
    else:
        e.update(no_keeper=True, keeper_at=list(door), stand=list(door))
    out_b.append(e)
assert sum(1 for e in out_b if not e.get('no_keeper')) >= 2

# ---------------------------------------------------------------- mill sails (animated, fade with the mill roof)
rf = np.array(L('buildings', 'mb_mill_roof'))[..., 3] > 0; dtm = ndi.distance_transform_edt(rf); hy, hx = np.unravel_index(np.argmax(dtm), dtm.shape)
SZ = 88
mill_tiles = [[mill['at'][0] + x, mill['at'][1] + y] for y, r in enumerate(mill['rows']) for x, c in enumerate(r)]
FADES = [dict(path=f'{RES}/props/mb_mill_sails_4f.png', pos=[int(mill['px'][0] + hx - SZ // 2), int(mill['px'][1] + hy - SZ // 2)], tiles=mill_tiles, frames=4, fps=4)]

# ---------------------------------------------------------------- register props + giver NPC sprites
SP = os.path.join(REPO, 'data/sprites.json'); OB = os.path.join(REPO, 'data/objects.json')
s_ = json.load(open(SP)); o_ = json.load(open(OB))
PN = {'bounty_board': 'Bounty board', 'sign_rats': 'Rat-catcher wanted', 'sign_inn': 'The Millwheel Inn', 'sack_gnawed': 'Gnawed sack', 'rat_bones': 'Rat bones',
      'tree_oak': 'Oak tree', 'tree_oak_b': 'Oak tree', 'tree_autumn': 'Autumn tree', 'bush_flowers': 'Flowering bush', 'lamp': 'Lamp post', 'grave_a': 'Grave', 'grave_b': 'Grave',
      'cross_broken': 'Broken cross'}
for f in sorted(x for x in os.listdir(os.path.join(DST, 'props')) if x.endswith('.png')):
    oid = f[:-4]
    if oid == 'mb_mill_sails_4f': continue
    im = Image.open(os.path.join(DST, 'props', f)); n = oid[3:]
    s_['objects'][oid] = {'path': f'{RES}/props/{f}', 'frame_size': [im.width, im.height], 'frames': 1, 'anchor': 'bottom', 'note': '0.3.16 Millbrook v1 prop (villages/v1)'}
    o_['objects'][oid] = {'name': PN.get(n, n.replace('_', ' ').capitalize()), 'sprite': oid, 'blocks': oid not in NONBLOCK, 'type': 'prop'}
# the village well keeps the game's well object (tests: well/quern/hearth) but wears the designer's well art
s_['objects']['vl_well_station'] = dict(s_['objects']['vl_well'], note='0.3.16 Millbrook well (designer art)')
o_['objects']['vl_well_station'] = dict(o_['objects'].get('well', {'name': 'Well', 'blocks': True, 'type': 'prop'}), sprite='vl_well_station', alias_of='well')
for nid, act in (('odric_hunter', 'quest_giver_hunter'), ('quartermaster_hale', 'quest_giver_quartermaster')):
    im = Image.open(os.path.join(DST, 'npcs', nid + '.png'))
    s_['actors'][nid] = {'path': f'{RES}/npcs/{nid}.png', 'frame_size': [16, 24], 'frames': im.width // 16, 'fps': 2, 'anchor': 'bottom', 'flip': True,
                         'dir_paths': {'down': f'{RES}/npcs/{nid}_front.png', 'up': f'{RES}/npcs/{nid}_back.png'}, 'note': '0.3.16 sprite bot villages/v1 giver NPC'}
    o_['objects'][act]['actor_sprite'] = nid
json.dump(s_, open(SP, 'w'), indent=1); json.dump(o_, open(OB, 'w'), indent=1)

# ---------------------------------------------------------------- write data
GROUND = {'.': None, ':': 'road_dirt', '~': 'water'}
OBJ_CH = {}; chars = iter('ABCEFHIJKLMNOPQRSTUVWXYZabcdefhijklmnopqrstuvwxyz0123456789!$%&()*+,/;<>?@[]_{|}^')
for o in sorted(set(objs.values())):
    c = next(chars)
    while c in ':~.#': c = next(chars)
    OBJ_CH[o] = c
rows = []
for y in range(GH):
    r = ''
    for x in range(GW):
        o = objs.get((x, y))
        r += OBJ_CH[o] if o else ('.' if grid[y][x] == 'g' else grid[y][x])
    rows.append(r)
objects = {ch: {'object': ('well' if o == 'vl_well_station' else o), 'ground': ('road_dirt' if grid[p[1]][p[0]] == ':' else 'grass')} for o, ch in OBJ_CH.items() for p in [next(pp for pp, vv in objs.items() if vv == o)]}
# well: the logic object stays "well"; its sprite is swapped per tile via objects.json alias? keep it simple: use the game well id
_ta_p = os.path.join(REPO, 'data/town_art.json'); _ta = json.load(open(_ta_p))
_ta['buildings'] = {k: v for k, v in _ta.get('buildings', {}).items() if k not in ART}; _ta['buildings'].update(ART)
json.dump(_ta, open(_ta_p, 'w'), indent=1)
old = json.load(open(os.path.join(REPO, 'data/towns/millbrook.json')))
spawn = next(q for q in [(GREEN[0] + a, GREEN[1] + b) for a in range(-3, 4) for b in range(-2, 3)] if q in seen and q not in objs)
farms = []; past = []
for i, f in enumerate(FARMS):
    if f['stage'] == 'pasture':
        past.append(dict(id='millbrook_pasture', rect=f['rect'], enemy='cow', count=6, gate=f['gate']))
    else:
        farms.append(dict(id='millbrook_wheat' if i == 0 else 'millbrook_wheat_%d' % (i + 1), rect=f['rect'], crop='wheat', ground='dirt', gate=f['gate']))
town = dict(id='millbrook', name='Millbrook', kind='village', between=old.get('between', []), tagline='Wheat, a windmill and a millpond on the Cinder road; something is breeding under the rat barn.',
            origin=ORIGIN, spawn=[ORIGIN[0] + spawn[0], ORIGIN[1] + spawn[1]], tiles={k: v for k, v in GROUND.items() if v}, objects=objects, roof='#a0784a',
            gate=list(GATE), buildings=out_b, farms=farms, pastures=past, citizens=dict(area=[GREEN[0] - 8, GREEN[1] - 4, 17, 9], count=5),
            art=dict(ground_decal=f'{RES}/ground_decal.png', ysort=[], fades=FADES, rat_barn_door=rb['door'], green=list(GREEN)),
            rows=rows, note="0.3.16 generated by tools/world/build_millbrook_v1.py from the sprite bot's villages/v1 set")
json.dump(town, open(os.path.join(REPO, 'data/towns/millbrook.json'), 'w'), indent=1)

# ---------------------------------------------------------------- debug composite
dbg = Image.new('RGBA', (SW, SH), (60, 90, 50, 255)); dbg.alpha_composite(Image.fromarray(dec))
items = [(b['px'][1] + BM[b['art']]['px'][1], 'b', b) for b in blds] + [(y * T + T, 'p', (o, x, y)) for (x, y), o in objs.items()]
for f in FARMS:
    x0, y0, w, h = f['rect']; ImageDraw.Draw(dbg).rectangle([x0 * T, y0 * T, (x0 + w) * T - 1, (y0 + h) * T - 1], outline=(140, 100, 50, 255))
    gx, gy = f['gate']; ImageDraw.Draw(dbg).rectangle([gx * T, gy * T, gx * T + 15, gy * T + 15], outline=(255, 255, 0, 255))
for _, kind, it in sorted(items, key=lambda t: t[0]):
    if kind == 'b':
        for l in BM[it['art']]['layers']: dbg.alpha_composite(L('buildings', l), tuple(it['px']))
    else:
        o, x, y = it; p = s_['objects'].get(o, {}).get('path', '')
        if p.startswith(RES):
            im = Image.open(os.path.join(DST, p[len(RES) + 1:])).convert('RGBA'); dbg.alpha_composite(im, (int(x * T + 8 - im.width / 2), max(0, int(y * T + T - im.height))))
        else: ImageDraw.Draw(dbg).rectangle([x * T + 3, y * T + 3, x * T + 12, y * T + 12], fill=(220, 60, 60, 255))
sl = L('props', 'mb_mill_sails_4f').crop((0, 0, SZ, SZ)); dbg.alpha_composite(sl, tuple(FADES[0]['pos']))
dbg.save(os.path.join(REPO, 'build/millbrook_layout_check.png'))
open('/tmp/mb/grid.txt', 'w').write('\n'.join(rows))
print('buildings', len(blds), 'objects', len(objs), 'farms', len(farms), 'pastures', len(past), 'gate', GATE, 'spawn', town['spawn'], 'rat barn door', rb['door'])
sys.exit(1 if fails else 0)
