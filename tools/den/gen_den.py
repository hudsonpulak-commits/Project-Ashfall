#!/usr/bin/env python3
"""0.4.2 Rat den layout generator (organic cave). Writes rows into data/underworld.json.
Chambers = noisy discs, tunnels = wobbly thick polylines, then cellular smoothing.
Legend: '#' wall, '.' floor, 'U' ladder up (exit), 'S' arrival, 'M' Rat Mother,
'R' rat camp, 'T' torch, props: b bones k skull n nest s straw d droppings g gnawed p puddle."""
import json, math, random, sys
W, H = 60, 44
rnd = random.Random(4242)
def vnoise(seed):
    g = {}
    def at(x, y):
        k = (x, y)
        if k not in g: g[k] = random.Random(hash((seed, x, y))).random()
        return g[k]
    def f(x, y, s=5.0):
        x /= s; y /= s; x0, y0 = math.floor(x), math.floor(y); fx, fy = x - x0, y - y0
        fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy)
        a = at(x0, y0) + (at(x0 + 1, y0) - at(x0, y0)) * fx
        b = at(x0, y0 + 1) + (at(x0 + 1, y0 + 1) - at(x0, y0 + 1)) * fx
        return a + (b - a) * fy
    return f
nz = vnoise(7)
chambers = {  # name: (cx, cy, r)
    "entry": (12, 34, 5.5), "mid": (28, 25, 6.5), "pool": (14, 13, 5.0),
    "mother": (45, 13, 8.0), "nook": (47, 33, 4.5)}
tunnels = [("entry", "mid", 2.0), ("mid", "pool", 1.7), ("mid", "mother", 2.2), ("mid", "nook", 1.6), ("pool", "mother", 1.4)]
g = [[1] * W for _ in range(H)]
for (cx, cy, r) in chambers.values():
    for y in range(H):
        for x in range(W):
            d = math.hypot(x - cx, (y - cy) * 1.15)
            if d < r * (0.78 + 0.45 * nz(x, y, 3.5)):
                g[y][x] = 0
for a, b, w in tunnels:
    ax, ay, _ = chambers[a]; bx, by, _ = chambers[b]
    n = int(math.hypot(bx - ax, by - ay) * 2)
    for i in range(n + 1):
        t = i / n
        px = ax + (bx - ax) * t + math.sin(t * math.pi * 2 + ax) * 2.2 * math.sin(t * math.pi)
        py = ay + (by - ay) * t + math.cos(t * math.pi * 2 + by) * 2.2 * math.sin(t * math.pi)
        ww = w * (0.8 + 0.5 * nz(px * 3, py * 3, 2.0))
        for y in range(int(py - 4), int(py + 5)):
            for x in range(int(px - 4), int(px + 5)):
                if 0 <= x < W and 0 <= y < H and math.hypot(x - px, y - py) <= ww:
                    g[y][x] = 0
def nbw(x, y):
    return sum(g[y + dy][x + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1) if (dx or dy))
for _ in range(2):  # smoothing
    g2 = [r[:] for r in g]
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            n = nbw(x, y)
            if g[y][x] == 1 and n <= 3: g2[y][x] = 0
            elif g[y][x] == 0 and n >= 6: g2[y][x] = 1
    g = g2
# clean: no wall cell that is 1-thick in both axes pattern (pillars of 1 cell ok if >= 2 wide)
changed = True
while changed:
    changed = False
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            if g[y][x] == 1:
                ns, ew = g[y - 1][x] + g[y + 1][x], g[y][x - 1] + g[y][x + 1]
                if ns == 0 or ew == 0:   # wall sliver: open it
                    g[y][x] = 0; changed = True
            else:
                # floor sliver 1 wide between walls -> keep (tunnels) unless diagonal pinch
                pass
    # diagonal-only wall contacts (checkerboard) -> open
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            if g[y][x] == 1 and g[y + 1][x + 1] == 1 and g[y][x + 1] == 0 and g[y + 1][x] == 0:
                g[y][x + 1] = 1; changed = True
            if g[y][x + 1] == 1 and g[y + 1][x] == 1 and g[y][x] == 0 and g[y + 1][x + 1] == 0:
                g[y][x] = 1; changed = True
# connectivity: flood from entry, wall off the rest
from collections import deque
ex, ey = int(chambers["entry"][0]), int(chambers["entry"][1])
assert g[ey][ex] == 0
seen = {(ex, ey)}; q = deque([(ex, ey)])
while q:
    x, y = q.popleft()
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nx, ny = x + dx, y + dy
        if g[ny][nx] == 0 and (nx, ny) not in seen:
            seen.add((nx, ny)); q.append((nx, ny))
for y in range(H):
    for x in range(W):
        if g[y][x] == 0 and (x, y) not in seen: g[y][x] = 1
for c in chambers.values():
    assert (int(c[0]), int(c[1])) in seen, c
rows = [["#" if v else "." for v in r] for r in g]
def free(x, y, need_wall_n=False):
    if rows[y][x] != ".": return False
    if need_wall_n and rows[y - 1][x] != "#": return False
    return True
def put(ch, x, y):
    assert rows[y][x] == ".", (ch, x, y); rows[y][x] = ch
# ladder: on the north wall of the entry chamber (floor cell whose N is wall)
cx, cy = int(chambers["entry"][0]), int(chambers["entry"][1])
lad = None
for y in range(cy, 0, -1):
    if rows[y - 1][cx] == "#": lad = (cx, y); break
put("U", *lad); put("S", lad[0], lad[1] + 1)
mx, my = int(chambers["mother"][0]), int(chambers["mother"][1]); put("M", mx, my)
for nm in ("mid", "nook", "pool"):
    put("R", int(chambers[nm][0]), int(chambers[nm][1]))
# torches on north walls near chamber centres
for nm in ("entry", "mid", "mother", "pool"):
    x0, y0 = int(chambers[nm][0]) + 2, int(chambers[nm][1])
    for y in range(y0, 0, -1):
        if rows[y - 1][x0] == "#":
            if rows[y][x0] == ".": rows[y][x0] = "T"
            break
props = {"mother": "nnnbbkgssmm", "mid": "bdgsp", "pool": "pppd", "nook": "nbkd", "entry": "dg"}
for nm, ps in props.items():
    cx, cy, r = chambers[nm]
    for ch in ps:
        for _ in range(60):
            a = rnd.random() * math.tau; d = rnd.uniform(1.5, r * 0.8)
            x, y = int(cx + math.cos(a) * d), int(cy + math.sin(a) * d)
            if free(x, y) and all(rows[y + dy][x + dx] in ".#" for dy in (-1, 0, 1) for dx in (-1, 0, 1)):
                rows[y][x] = ch; break
out = ["".join(r) for r in rows]
path = sys.argv[1] if len(sys.argv) > 1 else "data/underworld.json"
try: d = json.load(open(path))
except Exception: d = {}
d.setdefault("dens", {}).setdefault("rat_den", {})
d["dens"]["rat_den"]["rows"] = out
json.dump(d, open(path, "w"), indent=1)
print("\n".join(out)); print(len(seen), "floor cells")
