#!/usr/bin/env python3
"""0.3.10 region overview from tools/export_world_map.gd output:
terrain tinted by lore region, cliffs (dark) + stairs (light), roads, towns,
mines, and a reachability check (flood fill from Fenhollow; walls/water/cliffs/
blocking objects block, 4-way). Usage: render_region_map.py <dump dir> <out.png>"""
import json, os, sys
from collections import deque
from PIL import Image, ImageDraw, ImageFont
D = sys.argv[1]; OUT = sys.argv[2]
d = json.load(open(os.path.join(D, "world_dump.json"))); m = d["meta"]
ox, oy = m["origin"]; W, H = m["size"]
T = open(os.path.join(D, "world_tiles.bin"), "rb").read()
O = open(os.path.join(D, "world_objects.bin"), "rb").read()
R = open(os.path.join(D, "world_regions.bin"), "rb").read()
names = m["tile_names"]; cols = [tuple(int(c[i:i+2], 16) for i in (1, 3, 5)) for c in m["tile_colors"]]
tints = [tuple(int(c[i:i+2], 16) for i in (1, 3, 5)) for c in m["region_tints"]]
blockT = set(m["blocking_tiles"]); objb = m["object_blocks"]
CF, CL, CS = names.index("cliff_face"), names.index("cliff_lip"), names.index("cliff_stairs")
x0, y0, x1, y1 = m["land_extent"]; x0 -= 10; y0 -= 10; x1 += 10; y1 += 10
S = 2
img = Image.new("RGB", ((x1 - x0) * S, (y1 - y0) * S), (29, 74, 102))
px = img.load()
def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))
for y in range(y0, y1):
    for x in range(x0, x1):
        i = (y - oy) * W + (x - ox); t = T[i]
        if t == 255: continue
        c = cols[t]
        if t in (CF, CL): c = (40, 30, 26)
        elif t == CS: c = (230, 215, 170)
        elif names[t] in ("grass", "grass_lush", "grass_boreal", "grass_tropic", "dirt", "rocky", "marsh", "sand"):
            c = lerp(c, tints[R[i]], 0.35)
        for dy in range(S):
            for dx in range(S): px[(x - x0) * S + dx, (y - y0) * S + dy] = c
# reachability
def walk(x, y):
    if not (ox <= x < ox + W and oy <= y < oy + H): return False
    i = (y - oy) * W + (x - ox); t = T[i]
    return t != 255 and t not in blockT and not objb[O[i]]
start = None
fen = [t for t in d["towns"] if t.get("id") == "fenhollow"]
sx, sy = (fen[0]["center"] if fen and "center" in fen[0] else (0, 0))
for r in range(30):
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if start is None and walk(sx + dx, sy + dy): start = (sx + dx, sy + dy)
seen = bytearray(W * H); q = deque([start]); seen[(start[1] - oy) * W + start[0] - ox] = 1
while q:
    x, y = q.popleft()
    for ddx, ddy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nx, ny = x + ddx, y + ddy
        if walk(nx, ny):
            j = (ny - oy) * W + nx - ox
            if not seen[j]: seen[j] = 1; q.append((nx, ny))
walkable = unreached = 0; unreached_res = 0; big = 0
gather = {"tree", "rock", "patch", "mushroom", "reed"}
for y in range(oy, oy + H):
    for x in range(ox, ox + W):
        if walk(x, y):
            walkable += 1
            if not seen[(y - oy) * W + x - ox]:
                unreached += 1
                px_ = ((x - x0) * S, (y - y0) * S)
                if 0 <= px_[0] < img.width and 0 <= px_[1] < img.height: img.putpixel(px_, (255, 0, 255))
# objects next to unreached tiles only matter if they are gather nodes: count gather objects with no reached neighbour
for y in range(oy + 1, oy + H - 1):
    for x in range(ox + 1, ox + W - 1):
        oi = O[(y - oy) * W + x - ox]
        if oi and any(k in m["object_ids"][oi] for k in gather):
            if not any(seen[(y + b - oy) * W + x + a - ox] for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1))):
                unreached_res += 1
dr = ImageDraw.Draw(img)
try: f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22); fs = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
except Exception: f = fs = ImageFont.load_default()
for rd in d["roads"]:
    pts = rd.get("tiles", rd) if isinstance(rd, dict) else rd
for t in d["towns"]:
    c = t.get("center"); 
    if not c: continue
    X, Y = (c[0] - x0) * S, (c[1] - y0) * S
    dr.rectangle([X - 6, Y - 6, X + 6, Y + 6], fill=(248, 240, 216), outline=(40, 30, 20), width=2)
    dr.text((X + 10, Y - 12), t.get("name", t.get("id")), fill=(255, 255, 255), font=fs, stroke_width=3, stroke_fill=(0, 0, 0))
for mn in d["mines"]:
    X, Y = (mn["center"][0] - x0) * S, (mn["center"][1] - y0) * S
    dr.ellipse([X - 5, Y - 5, X + 5, Y + 5], outline=(255, 230, 80), width=2)
# region labels at the mean position of each region
acc = {}
for y in range(y0, y1, 4):
    for x in range(x0, x1, 4):
        i = (y - oy) * W + (x - ox)
        if T[i] != 255:
            a = acc.setdefault(R[i], [0, 0, 0]); a[0] += x; a[1] += y; a[2] += 1
for ri, a in acc.items():
    X, Y = (a[0] / a[2] - x0) * S, (a[1] / a[2] - y0) * S
    if m["region_ids"][ri] == "cinder": Y += 60
    dr.text((X - 80, Y), m["region_names"][ri].upper(), fill=tints[ri], font=f, stroke_width=4, stroke_fill=(0, 0, 0))
leg = ["AshFall 0.3.10 - lore regions (seed %d)" % m["seed"], "dark = cliffs (block), cream = ramps / stone stairs, yellow rings = mines",
       "reachability: %d walkable tiles, %d unreachable (magenta), %d gather nodes unreachable" % (walkable, unreached, unreached_res)]
for k, l in enumerate(leg): dr.text((12, 10 + k * 20), l, fill=(255, 255, 255), font=fs, stroke_width=3, stroke_fill=(0, 0, 0))
img.save(OUT)
print("REGION_MAP", OUT, img.size, "walkable", walkable, "unreached", unreached, "unreached_gather", unreached_res)
