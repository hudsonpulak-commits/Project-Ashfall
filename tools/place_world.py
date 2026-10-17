#!/usr/bin/env python3
"""0.3.1 helper: propose mine clusters and creature camps from the real world
dump (tools/export_world_map.gd) and the distance bands in data/enemy_bands.json.
It only PRINTS JSON proposals; data/mines.json and data/enemies.json "camps"
are the source of truth (hand-editable). Deterministic.

    python3 tools/place_world.py [build/map]
"""
import json, math, os, sys
OUT = sys.argv[1] if len(sys.argv) > 1 else "build/map"
d = json.load(open(os.path.join(OUT, "world_dump.json")))
meta = d["meta"]; ox, oy = meta["origin"]; W, H = meta["size"]
tiles = open(os.path.join(OUT, "world_tiles.bin"), "rb").read()
names = meta["tile_names"]
WATER = names.index("water"); DIRT = names.index("dirt")
towns = d["towns"]
roads = set()
for r in d["roads"]:
    for x, y in r["tiles"]:
        roads.add((x, y))
pk = [z["rect"] for z in d["pk_zones"]]

def t(x, y):
    i = (y - oy) * W + (x - ox)
    if x < ox or y < oy or x >= ox + W or y >= oy + H: return 255
    return tiles[i]
def in_pk(x, y, m=0):
    return any(r[0] - m <= x < r[0] + r[2] + m and r[1] - m <= y < r[1] + r[3] + m for r in pk)
def edge(x, y, town=None):
    best = 1e9
    for tw in towns:
        if town and tw["id"] != town: continue
        rx, ry, rw, rh = tw["rect"]
        dx = max(rx - x, 0, x - (rx + rw - 1)); dy = max(ry - y, 0, y - (ry + rh - 1))
        best = min(best, math.hypot(dx, dy))
    return best
def land_frac(x, y, r):
    n = l = dd = 0
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy > r * r: continue
            n += 1; c = t(x + dx, y + dy)
            if c not in (WATER, 255): l += 1
            if c == DIRT: dd += 1
    return l / n, dd / n
def near_road(x, y, r):
    return any((x + dx, y + dy) in roads for dy in range(-r, r + 1) for dx in range(-r, r + 1))

taken = []   # (x, y, radius)
def free(x, y, r):
    return all(math.hypot(x - a, y - b) >= r + rr for a, b, rr in taken)

def pick(lo, hi, town=None, radius=6, need_land=0.92, road_gap=3, pk_mode="no", spacing=8, prefer=None, avoid_dirs=None, n=1, step=3):
    cands = []
    for y in range(oy, oy + H, step):
        for x in range(ox, ox + W, step):
            ip = in_pk(x, y)
            if pk_mode == "no" and in_pk(x, y, radius + 4): continue
            if pk_mode == "only" and not in_pk(x, y, -(radius + 8)): continue
            e = edge(x, y, town) if pk_mode != "only" else 0
            if pk_mode != "only":
                if not (lo <= e <= hi): continue
                if town and edge(x, y) < e - 0.01: continue        # must be closest to this town
            if t(x, y) in (WATER, 255): continue
            lf, df = land_frac(x, y, radius)
            if lf < need_land: continue
            if near_road(x, y, radius + road_gap): continue
            if not free(x, y, radius + spacing): continue
            score = -abs(e - (prefer if prefer is not None else (lo + hi) / 2)) + df * 6 + lf * 3
            if avoid_dirs and town:
                tc = [tw for tw in towns if tw["id"] == town][0]["center"]
                if any((y - tc[1]) * s < -abs(x - tc[0]) * 0.3 for s in avoid_dirs): score -= 50
            cands.append((score, x, y, e))
    cands.sort(reverse=True)
    out = []
    for s, x, y, e in cands:
        if len(out) >= n: break
        if not free(x, y, radius + spacing): continue
        taken.append((x, y, radius)); out.append((x, y, round(e, 1)))
    return out

TOWNS = [tw["id"] for tw in towns]
NICE = {"fenhollow": "Fenhollow", "cinderholt": "Cinderholt", "saltmere": "Saltmere"}
mines = []
for tw in TOWNS:
    av = [1] if tw == "cinderholt" else None    # Cinderholt: keep its starter mine south of town (Scorch lies north)
    for (x, y, e) in pick(15, 30, tw, radius=6, prefer=22, avoid_dirs=av):
        mines.append({"id": f"{tw}_pits", "name": f"{NICE[tw]} Pits", "tier": "copper_tin", "town": tw, "center": [x, y], "radius": 6,
                      "density": 0.32, "ores": {"copper_rock": 0.55, "tin_rock": 0.45}, "_edge": e})
for tw in TOWNS:
    k = 2 if tw == "cinderholt" else 1
    for i, (x, y, e) in enumerate(pick(50, 90, tw, radius=6, prefer=68, n=k, spacing=20)):
        mines.append({"id": f"{tw}_iron{'' if i == 0 else i + 1}", "name": f"{NICE[tw]} Iron Cut{'' if i == 0 else ' East'}", "tier": "iron", "town": tw,
                      "center": [x, y], "radius": 6, "density": 0.30, "ores": {"iron_rock": 0.85, "tin_rock": 0.15}, "_edge": e})
for i, (x, y, e) in enumerate(pick(100, 400, None, radius=6, prefer=115, n=3, spacing=60)):
    mines.append({"id": f"coal_{i + 1}", "name": f"Coal Seam {i + 1}", "tier": "coal", "center": [x, y], "radius": 6, "density": 0.30,
                  "ores": {"coal_rock": 0.75, "iron_rock": 0.25}, "_edge": e})
for i, (x, y, e) in enumerate(pick(0, 0, None, radius=7, pk_mode="only", n=2, spacing=40)):
    mines.append({"id": f"scorch_{i + 1}", "name": f"Scorch Deep Mine {i + 1}", "tier": "scorch", "center": [x, y], "radius": 7, "density": 0.45,
                  "ores": {"coal_rock": 0.5, "iron_rock": 0.5}, "_edge": e})

camps = []
def camp(kind, lo, hi, town, n, count, spread, radius=4, pk_mode="no", spacing=10, prefer=None, road_gap=2):
    for (x, y, e) in pick(lo, hi, town, radius=radius, need_land=0.85, road_gap=road_gap, pk_mode=pk_mode, spacing=spacing, prefer=prefer, n=n, step=2):
        camps.append({"enemy": kind, "at": [x, y], "count": count, "spread": spread, "_edge": e})
for tw in TOWNS:
    camp("chicken", 5, 16, tw, 2, 4, 2, radius=3, spacing=6, prefer=9, road_gap=1)
for tw in TOWNS:
    camp("giant_rat", 16, 45, tw, 2, 4, 3, prefer=32)
for tw in TOWNS:
    camp("wolf", 42, 80, tw, 2, 3, 2, prefer=60, road_gap=4)
camp("goblin", 75, 400, None, 6, 4, 3, prefer=95, spacing=40)
camp("wolf", 0, 0, None, 1, 4, 2, pk_mode="only", spacing=20)
camp("cinder_brute", 0, 0, None, 3, 3, 3, pk_mode="only", spacing=25)
print(json.dumps({"mines": mines, "camps": camps}, indent=1))
