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
SRC = '/workspace/art_handoff/towns/highfen'
DST = os.path.join(REPO, 'assets/sprites/towns/highfen')
RES = 'res://assets/sprites/towns/highfen'
T = 16
N = 72                     # town is N x N tiles
SW = SH = N * T
CX, CY = SW // 2, SH // 2  # ring centre (px)
R = 17 * T                 # ring inner radius

# ---------------------------------------------------------------- copy art
for sub in ('buildings', 'props', 'walls'):
    os.makedirs(os.path.join(DST, sub), exist_ok=True)
    for f in sorted(os.listdir(os.path.join(SRC, sub))):
        if f.endswith('.png'):
            shutil.copyfile(os.path.join(SRC, sub, f), os.path.join(DST, sub, f))
shutil.copyfile(os.path.join(SRC, 'manifest.json'), os.path.join(DST, 'manifest.json'))
shutil.copyfile(os.path.join(SRC, 'README.md'), os.path.join(DST, 'README_designer.md'))
M = json.load(open(os.path.join(SRC, 'manifest.json')))
BM = {b['name']: b for b in M['buildings']}
L = lambda sub, n: Image.open(os.path.join(SRC, sub, n if n.endswith('.png') else n + '.png')).convert('RGBA')

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
ART = {}
for b in M['buildings']:
    lay = b['layers']; fade = b['fade_group']
    ART[b['name']] = dict(tiles=b['tiles'], px=b['px'], origin_y=b['footprint_origin_px'][1], door_tile=b['door_tile'], storeys=b['storeys'],
                          floor=f"{RES}/buildings/{lay[0]}", walls=f"{RES}/buildings/{lay[1]}",
                          fade=[f"{RES}/buildings/{l}" for l in fade], plan=plan_of(b))
segs = {k: dict(path=f"{RES}/walls/{k}.png", offset=v['offset_from_ring_px'], size=v['size']) for k, v in M['wall_segments'].items()}
PROPS = {p[0]: p[1] for p in M['props']}

def flip_plan(rows): return [r[::-1] for r in rows]

# ---------------------------------------------------------------- roads (pixel masks)
Y, X = np.mgrid[:SH, :SW]
def roadmask(pts, w):
    m = np.zeros((SH, SW), bool)
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        for t in np.linspace(0, 1, 12):
            px, py = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t; r = w / 2
            ys, ye, xs, xe = max(0, int(py - r - 1)), min(SH, int(py + r + 2)), max(0, int(px - r - 1)), min(SW, int(px + r + 2))
            if ys >= ye or xs >= xe: continue
            m[ys:ye, xs:xe] |= (X[ys:ye, xs:xe] - px) ** 2 + (Y[ys:ye, xs:xe] - py) ** 2 <= r * r
    return m
ell = lambda cx, cy, rx, ry, a0=0, a1=360, st=4: [(cx + rx * math.cos(math.radians(t)), cy + ry * math.sin(math.radians(t))) for t in range(a0, a1 + 1, st)]
def until(gen, ok):
    out = []
    for p in gen:
        out.append(p)
        if not ok(p): break
    return out
inb = lambda p: -8 <= p[0] <= SW + 8 and -8 <= p[1] <= SH + 8
PLAZA = (CX, CY + R - 50, 60, 27)
LANES = dict(
    gate_road=until(((CX + 18 * math.sin(t / 5), CY + R - 30 + t * 4) for t in range(400)), inb),
    palace_loop=ell(CX, CY - 14, 116, 128),
    outer_ring=ell(CX, CY + 8, R + 46, R + 42),
    north_track=until(((CX - 30 + 40 * math.sin(t / 9), CY + 8 - R - 42 - t * 4) for t in range(400)), inb),
    west_track=until(((CX - R - 40 - t * 4, CY + 60 + 30 * math.sin(t / 8)) for t in range(400)), inb),
    east_track=until(((CX + R + 40 + t * 4, CY - 40 + 26 * math.sin(t / 7)) for t in range(400)), inb),
    market_spoke=[(CX + 10 * math.sin(t / 4), CY + 112 + t * 4) for t in range(0, 22)],
)
W_ = dict(gate_road=18, palace_loop=16, outer_ring=16, north_track=13, west_track=13, east_track=13, market_spoke=13)
road = np.zeros((SH, SW), bool)
for k, p in LANES.items(): road |= roadmask(p, W_[k])
plaza = ((X - PLAZA[0]) / PLAZA[2]) ** 2 + ((Y - PLAZA[1]) / PLAZA[3]) ** 2 <= 1
road |= plaza

# ---------------------------------------------------------------- city wall ring (tile collision from its alpha)
ring = L('walls', 'city_wall_ring_full'); rc = M['ring_center_px']; rox, roy = CX - rc, CY - rc
ringA = np.zeros((SH, SW), bool); ra = np.array(ring)[..., 3] > 0
ringA[roy:roy + ra.shape[0], rox:rox + ra.shape[1]] = ra[:SH - roy, :SW - rox]
cov = ringA.reshape(N, T, N, T).mean(axis=(1, 3))
wall_t = cov > 0.15
# the gate: the open columns in the ring under the centre line (south)
gate_cols = [tx for tx in range(N) if abs(tx * T + 8 - CX) < 40 and not wall_t[(CY + R) // T:(CY + R + 40) // T, tx].any()]
print('ring gate columns', gate_cols)

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
            if inside and dd.max() > R - 4: why['ring'] = why.get('ring', 0) + 1; continue
            if not inside and dd.min() < R + 34: continue
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

# inside the walls (designer's scene, roles mapped onto the game's Highfen buildings)
place('palace', CX, CY - 14, True, role='palace')
place('guild_knights', CX + 190, CY - 12, True, role='guild')
place('church', CX - 150, CY + 4, True, role='church')
place('house_tower_corner', CX + 120, CY - 84, True, role='bank')
place('shop_general', CX - 120, CY - 116, True, role='general')
place('shop_tavern', CX - 112, CY + 128, True, role='cook')
place('shop_smith', CX + 104, CY + 140, True, role='player_shop')
place('house_twin_gable', CX + 168, CY + 74, True, role='player_house', flip=True)
place('shop_baker', CX + 30, CY + 150, True, role='baker')
place('house_crooked', CX - 40, CY - 168, True, role='home')
place('house_stepped', CX + 60, CY - 176, True, role='home', flip=True)
place('house_narrow_tall', CX - 200, CY - 60, True, role='home')
for i, n in enumerate(['house_lshape', 'house_cottage_round', 'house_twin_gable', 'house_stepped', 'house_longhouse', 'house_tower_corner',
                       'house_narrow_tall', 'shop_baker', 'house_crooked', 'house_lshape', 'house_cottage_round', 'house_longhouse']):
    an = i * 30 + 7; pfx, pfy = CX + 196 * math.cos(math.radians(an)), CY + 186 * math.sin(math.radians(an))
    cand = sorted([(x, y) for x in range(CX - R, CX + R, 8) for y in range(CY - R, CY + R, 8) if 150 < math.hypot(x - CX, y - CY) < R - 20],
                  key=lambda c: math.hypot(c[0] - pfx, c[1] - pfy))
    for (x, y) in cand:
        if place(n, x, y, True, flip=i % 2 == 0, role='home', reach=1, quiet=True): break
import collections; _c = collections.Counter()
for w in QW: _c.update(w)
print('ring-house rejections', dict(_c))
OUT = ['house_twin_gable', 'house_longhouse', 'house_lshape', 'shop_general', 'house_cottage_round', 'house_stepped', 'house_cottage_round', 'house_lshape',
       'house_twin_gable', 'house_tower_corner', 'house_longhouse', 'house_stepped', 'house_crooked', 'house_narrow_tall', 'house_lshape', 'house_cottage_round',
       'house_twin_gable', 'house_longhouse', 'house_tower_corner', 'house_narrow_tall', 'shop_smith', 'house_crooked', 'shop_baker', 'house_cottage_round']
for i, n in enumerate(OUT):
    ang = (200 + i * (340 / len(OUT))) % 360
    if 75 < ang < 105: ang += 30
    rr = R + 74 + (i % 3) * 34
    place(n, CX + rr * math.cos(math.radians(ang)), CY + rr * math.sin(math.radians(ang)), False, flip=i >= 8, role='home', reach=90)

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
    if grid[y][x] not in '.d' or (x, y) in objs: return False
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
    ox, oy = b['at']
    return [(ox + x, oy + y) for y, r in enumerate(b['rows']) for x, c in enumerate(r) if c == 'o']
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
                base['props'].append(dict(object='hf_banner_pole', at=rel(p)))
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
        if top: base['props'].append(dict(object='oven', at=rel(top[0])))
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
            disp.append([x, y]); objs[(x, y)] = 'display_stand'
        base['displays'] = disp
        print('player shop displays', len(disp))
    if base.pop('_yard', False):
        ox, oy = base['at']; W, H = ART[base['art']]['tiles']
        stations = ['hearth', 'furnace', 'anvil', 'workbench', 'quern', 'bank_chest', 'oven']
        # yard: the row(s) behind the house (north), fenced by the house's own back wall and the yard edge
        cells = sorted([(x, y) for x in range(ox - 4, ox + W + 4) for y in range(oy - 4, oy + H)
                        if not (ox - 1 <= x <= ox + W and oy - 1 <= y <= oy + H)],
                       key=lambda c: (abs(c[0] - (ox + W / 2)) + abs(c[1] - oy) * 0.8))
        put = 0
        for (x, y) in cells:
            if put == len(stations): break
            if free_tile(x, y) and not wall_t[y, x]:
                base['props'].append(dict(object=stations[put], at=[x, y])); objs[(x, y)] = stations[put]; put += 1
        print('player house stations', put, 'of', len(stations))

# ---------------------------------------------------------------- market + props
MARKET = []
def addo(name, x, y, allow_road=False):
    if free_tile(x, y, allow_road):
        objs[(x, y)] = name; return True
    return False
px2t = lambda x, y: (int(x // T), int(y // T))
# stalls in a curved row across the plaza, the well, the statue, the exchange board
for i, s in enumerate(['stall_fruit', 'stall_cloth', 'stall_fish', 'stall_fruit']):
    tx, ty = px2t(PLAZA[0] - 60 + i * 38, PLAZA[1] - 10 + (i % 2) * 6)
    if addo('hf_' + s, tx, ty, True): MARKET.append((tx, ty))
for nm, dx, dy in [('hf_well', -6, 22), ('exchange_board', 40, 18), ('hf_statue_knight', 70, -26), ('hf_lamp_post', -76, -24), ('hf_lamp_post', 74, 8),
                   ('hf_cart', -96, 4), ('hf_crate_stack', 90, -12), ('hf_barrel', -84, 18)]:
    tx, ty = px2t(PLAZA[0] + dx, PLAZA[1] + dy)
    for (ax, ay) in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1)]:
        if addo(nm, tx + ax, ty + ay, True): MARKET.append((tx + ax, ty + ay)); break
side = ['hf_lamp_post', 'hf_barrel', 'hf_crate', 'hf_crate_broken', 'hf_debris', 'hf_bush_a', 'hf_bush_flowers', 'hf_flowerbed_small', 'hf_crate_stack',
        'hf_sign_post_road', 'hf_debris_b', 'hf_barrel', 'hf_fence_straight', 'hf_banner_pole']
for k, p in LANES.items():
    for i in range(2, len(p) - 2, 3):
        (x0, y0), (x1, y1) = p[i - 1], p[i + 1]; dx, dy = x1 - x0, y1 - y0; l = math.hypot(dx, dy) or 1; nx, ny = -dy / l, dx / l
        s = rnd.choice((-1, 1)); off = W_[k] / 2 + 10
        tx, ty = px2t(p[i][0] + s * nx * off, p[i][1] + s * ny * off)
        if rnd.random() < .6: addo(rnd.choice(side), tx, ty)
# trees + bushes outside the wall, gardens inside
trees = ['hf_tree_oak_a', 'hf_tree_oak_b', 'hf_tree_pine', 'hf_tree_autumn', 'hf_bush_a', 'hf_bush_b', 'hf_bush_flowers', 'hf_tree_oak_a', 'hf_tree_pine']
for k in range(900):
    x, y = rnd.randrange(1, N - 1), rnd.randrange(1, N - 1); d = math.hypot(x * T + 8 - CX, y * T + 8 - CY)
    if d < R + 40 or (d < R + 150 and rnd.random() < .7): continue
    if rnd.random() < .35: addo(rnd.choice(trees), x, y)
for k in range(400):
    x, y = rnd.randrange(1, N - 1), rnd.randrange(1, N - 1)
    if math.hypot(x * T + 8 - CX, y * T + 8 - CY) < R - 24 and rnd.random() < .25:
        addo(rnd.choice(['hf_bush_a', 'hf_bush_flowers', 'hf_flowerbed_small', 'hf_bush_b', 'hf_debris', 'hf_barrel', 'hf_crate']), x, y)

# ---------------------------------------------------------------- ground decal: roads, plaza, puddles, mud
decal = road_tex(road, 3)
dimg = Image.fromarray(decal)
for k in range(140):
    x, y = rnd.randrange(16, SW - 32), rnd.randrange(16, SH - 16)
    nm = rnd.choice(['puddle', 'mud_patch'])
    im = L('props', nm)
    on_road = road[y:y + im.height, x:x + im.width].mean() > .6
    if on_road or rnd.random() < .25:
        tx, ty = px2t(x + im.width / 2, y + im.height / 2)
        if 0 <= tx < N and 0 <= ty < N and grid[ty][tx] in '.d':
            dimg.alpha_composite(im, (x, y))
dimg.save(os.path.join(DST, 'ground_decal.png'))

# ---------------------------------------------------------------- reachability (4-connected, objects block)
def walk(x, y):
    if not (0 <= x < N and 0 <= y < N): return False
    if (x, y) in objs: return False
    c = grid[y][x]
    return c in '.d'
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
chars = iter('ABCEFGHIJKLMNOPQRSTUVXYZabcefhijklmnpqrstuvwxyz0123456789!$%&()*+,/;<>?@[]_{|}')
for o in sorted(set(objs.values()) - {'display_stand', 'hearth', 'furnace', 'anvil', 'workbench', 'quern', 'bank_chest', 'oven'}):
    OBJ_CH[o] = next(chars)
rows = []
for y in range(N):
    r = ''
    for x in range(N):
        c = grid[y][x]
        o = objs.get((x, y))
        if o in OBJ_CH: r += OBJ_CH[o]
        elif c == 'W': r += '#'
        elif c == 'B': r += 'g'
        elif c == 'd': r += 'd'
        else: r += 'g'
    rows.append(r)
ground_of = lambda x, y: 'dirt' if grid[y][x] == 'd' else 'grass'
objects = {}
for o, ch in OBJ_CH.items():
    xs = [p for p, v in objs.items() if v == o]
    objects[ch] = {'object': o, 'ground': 'grass'}
town_art = dict(note='0.3.11 per-design tile plans for the layered town buildings (tools/world/build_highfen_v2.py). plan: # wall, o floor, D door, . outside',
                buildings=ART, ring=dict(segments=segs, center_px=rc))
json.dump(town_art, open(os.path.join(REPO, 'data/town_art.json'), 'w'), indent=1)
old = json.load(open(os.path.join(REPO, 'data/towns/highfen.json')))
spawn = [PLAZA[0] // T, PLAZA[1] // T + 3]
while not walk(*spawn) or tuple(spawn) not in seen: spawn[1] += 1
town = dict(id='highfen', name='Highfen', kind='capital', origin=old['origin'], spawn=[old['origin'][0] + spawn[0], old['origin'][1] + spawn[1]],
            tiles={'g': 'grass', 'd': 'dirt', '#': 'city_ring'}, objects=objects, roof='#b8a888', building_style='capital',
            specialists=old['specialists'], price_bias=old['price_bias'],
            tagline='The walled capital at the heart of the realm: a round city of soot-dark stone, the palace at its centre, the Guild of Knights, a market by the gate and houses ringing the wall.',
            theme='highfen', gates=gates,
            gate_walls=dict(south=[[x, max(y for y in range(N) if wall_t[y, gate_cols[0] - 1])] for x in gate_cols]),
            art=dict(ground_decal=f'{RES}/ground_decal.png', ring_origin_px=[rox, roy], market=[list(p) for p in MARKET], plaza_px=list(PLAZA[:2])),
            buildings=out_b, rows=rows,
            note="0.3.11 generated by tools/world/build_highfen_v2.py from the designer's Highfen set (art_handoff/towns/highfen, copied to assets/sprites/towns/highfen)")
json.dump(town, open(os.path.join(REPO, 'data/towns/highfen.json'), 'w'), indent=1)
# debug image
os.makedirs(os.path.join(REPO, 'build'), exist_ok=True)
dbg = Image.new('RGBA', (SW, SH), (60, 80, 50, 255)); dbg.alpha_composite(dimg)
items = [(b['px'][1] + BM[b['art']]['px'][1], 'b', b) for b in blds] + [(y * T + T, 'p', (o, x, y)) for (x, y), o in objs.items()]
seg_items = [(roy + v['offset'][1] + v['size'][1], 's', (k, v)) for k, v in segs.items()]
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
