#!/usr/bin/env python3
"""0.3.9 placeholder pixel art (swap freely; sheets listed in the Aseprite
manifest). Writes PNGs only when missing and registers them in
data/sprites.json + tools/art/aseprite_manifest.json. Re-runnable.

  autotile/fence_rural.png   18 pieces x 2 rows (row 1 = broken), 16x24
  autotile/wall_<fam>.png    18 wall-top cap pieces, 16x16 (city walls: never broken)
  autotile/moat_border.png   16 bank pieces + 4 bridge joins, 16x16
  transitions/<terrain>.png  256 blend frames (edges | corners<<4), 16x16
  actors/*_front.png / *_back.png   facing down / up (same frames as the side sheet)

Piece index (Autotile.PIECES): N=1 E=2 S=4 W=8 -> 0..15, 16 '/' diagonal, 17 '\\' diagonal."""
import json, os, random
from PIL import Image, ImageDraw
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SPR = os.path.join(ROOT, "data", "sprites.json")
MAN = os.path.join(ROOT, "tools", "art", "aseprite_manifest.json")
A = os.path.join(ROOT, "assets", "sprites")

def rgb(h, a=255): h = h.lstrip("#"); return tuple(int(h[i:i+2], 16) for i in (0, 2, 4)) + (a,)
def save(im, rel):
    p = os.path.join(A, rel)
    if not os.path.exists(p):
        os.makedirs(os.path.dirname(p), exist_ok=True); im.save(p, optimize=True)
    return "res://assets/sprites/" + rel
def h01(*a):
    x = 0
    for v in a: x = (x * 73856093 ^ (v + 0x9e37) * 19349663) & 0xffffffff
    return (x % 1000) / 1000.0

# ---------------------------------------------------------------- fence --
FD, FM, FL, FS = rgb("#5a3a1e"), rgb("#8a6038"), rgb("#a87a48"), rgb("#000000", 50)
def fence_piece(i, broken):
    im = Image.new("RGBA", (16, 24), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    n, e, s, w = i & 1, i & 2, i & 4, i & 8
    def rail_h(x0, x1):
        for y in (13, 17):
            d.line([(x0, y), (x1, y)], fill=FM); d.point((x0, y + 1), fill=FD)
    def rail_v(y0, y1):
        d.line([(7, y0), (7, y1)], fill=FM); d.line([(8, y0), (8, y1)], fill=FD)
    if i < 16:
        if e: rail_h(8, 15)
        if w: rail_h(0, 8)
        if n: rail_v(0, 12)
        if s: rail_v(18, 23)
    else:
        pts = [(0, 23), (15, 8)] if i == 16 else [(0, 8), (15, 23)]
        for dy in (0, 3):
            d.line([(pts[0][0], pts[0][1] - dy - 4), (pts[1][0], pts[1][1] - dy - 4)], fill=FM)
    top = 9
    if broken:
        top = 13
        # snapped rail + splinters
        if i < 16 and (e or w):
            x = 12 if e else 3
            d.line([(x, 12), (x + 1, 18)], fill=(0, 0, 0, 0))
            d.point((x - 1, 18), fill=FD)
        if i < 16 and (n or s) and not (e or w):
            d.line([(7, 3), (8, 6)], fill=(0, 0, 0, 0))
        d.point((10, 21), fill=FD); d.point((4, 22), fill=FL)
    d.ellipse([5, 20, 10, 23], fill=FS)
    d.rectangle([6, top, 9, 21], fill=FM); d.line([(6, top), (6, 21)], fill=FL); d.line([(9, top), (9, 21)], fill=FD)
    d.line([(6, top), (9, top)], fill=FL)
    if broken: d.point((9, top), fill=(0, 0, 0, 0)); d.point((8, top + 1), fill=FD)
    return im

def fence_sheet():
    im = Image.new("RGBA", (16 * 18, 48), (0, 0, 0, 0))
    for r in (0, 1):
        for i in range(18):
            im.paste(fence_piece(i, r == 1), (i * 16, r * 24))
    return im

# ---------------------------------------------------------------- walls --
def avg(path):
    im = Image.open(path).convert("RGBA").crop((0, 0, 16, 16))
    px = [c for c in im.getdata() if c[3] > 0]
    return tuple(sum(c[k] for c in px) // len(px) for k in range(3))
def shade(c, f): return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + (255,)

def wall_sheet(base):
    lt, dk, md = shade(base, 1.35), shade(base, 0.6), shade(base, 1.1)
    im = Image.new("RGBA", (16 * 18, 16), (0, 0, 0, 0))
    for i in range(18):
        t = Image.new("RGBA", (16, 16), (0, 0, 0, 0)); d = ImageDraw.Draw(t)
        segs = []
        if i < 16:
            if i & 1: segs.append([5, 0, 10, 8])
            if i & 4: segs.append([5, 7, 10, 15])
            if i & 2: segs.append([7, 5, 15, 10])
            if i & 8: segs.append([0, 5, 8, 10])
            for r in segs: d.rectangle(r, fill=md)
            d.rectangle([5, 5, 10, 10], fill=lt if i in (0, 1, 2, 4, 8) else md)
            for r in segs:   # crenel notches along the walk
                x0, y0, x1, y1 = r
                if x1 - x0 > y1 - y0:
                    for x in range(x0 + 1, x1, 4): d.point((x, y0), fill=dk)
                else:
                    for y in range(y0 + 1, y1, 4): d.point((x0, y), fill=dk)
            if i == 0: d.rectangle([4, 4, 11, 11], outline=dk)
        else:
            for k in range(-3, 3):
                if i == 16: d.line([(0, 15 + k), (15 + k, 0)], fill=md)
                else: d.line([(0, k), (15 - k, 15)], fill=md)
            for k in range(0, 16, 4):
                d.point((k, 15 - k) if i == 16 else (k, k), fill=lt)
        im.paste(t, (i * 16, 0))
    return im

# ---------------------------------------------------------------- moat --
WAT, BANK, BANKD, FOAM = rgb("#2a5f86"), rgb("#9c9a92"), rgb("#6c6a64"), rgb("#6aa6cc")
def moat_sheet():
    im = Image.new("RGBA", (16 * 20, 16), (0, 0, 0, 0))
    for i in range(16):
        t = Image.new("RGBA", (16, 16), (0, 0, 0, 0)); d = ImageDraw.Draw(t)
        # a bank on every side that does NOT connect (N1 E2 S4 W8)
        if not i & 1: d.rectangle([0, 0, 15, 2], fill=BANK); d.line([(0, 3), (15, 3)], fill=FOAM)
        if not i & 4: d.rectangle([0, 13, 15, 15], fill=BANK); d.line([(0, 12), (15, 12)], fill=FOAM)
        if not i & 2: d.rectangle([13, 0, 15, 15], fill=BANK); d.line([(12, 0), (12, 15)], fill=FOAM)
        if not i & 8: d.rectangle([0, 0, 2, 15], fill=BANK); d.line([(3, 0), (3, 15)], fill=FOAM)
        for x in range(0, 16, 4):
            for (xx, yy) in ((x, 0), (x, 15), (0, x), (15, x)):
                if t.getpixel((xx, yy))[3]: d.point((xx, yy), fill=BANKD)
        im.paste(t, (i * 16, 0))
    for k, (dx, dy) in enumerate(((0, -1), (1, 0), (0, 1), (-1, 0))):   # bridge join N E S W: stone pier
        t = Image.new("RGBA", (16, 16), (0, 0, 0, 0)); d = ImageDraw.Draw(t)
        if dy: y = 0 if dy < 0 else 12; d.rectangle([2, y, 4, y + 3], fill=BANK); d.rectangle([11, y, 13, y + 3], fill=BANK); d.line([(2, y + (3 if dy < 0 else 0)), (13, y + (3 if dy < 0 else 0))], fill=FOAM)
        else: x = 0 if dx < 0 else 12; d.rectangle([x, 2, x + 3, 4], fill=BANK); d.rectangle([x, 11, x + 3, 13], fill=BANK); d.line([(x + (3 if dx < 0 else 0), 2), (x + (3 if dx < 0 else 0), 13)], fill=FOAM)
        im.paste(t, ((16 + k) * 16, 0))
    return im

# ---------------------------------------------------------- transitions --
def trans_sheet(src_path, seed):
    base = Image.open(src_path).convert("RGBA").crop((0, 0, 16, 16)); bp = base.load()
    im = Image.new("RGBA", (256, 256), (0, 0, 0, 0)); px = im.load()
    depth = [3 + int(h01(seed, k) * 3) for k in range(16)]   # ragged edge per column/row
    for f in range(256):
        e, c = f & 15, f >> 4
        ox, oy = (f % 16) * 16, (f // 16) * 16
        for y in range(16):
            for x in range(16):
                on = (e & 1 and y < depth[x]) or (e & 4 and 15 - y < depth[15 - x]) or \
                     (e & 8 and x < depth[y]) or (e & 2 and 15 - x < depth[15 - y])
                r = 4 + (h01(seed, x, y) > 0.6)
                if not on and c:
                    on = (c & 1 and x * x + y * y < r * r) or (c & 2 and (15 - x) ** 2 + y * y < r * r) or \
                         (c & 4 and (15 - x) ** 2 + (15 - y) ** 2 < r * r) or (c & 8 and x * x + (15 - y) ** 2 < r * r)
                if on:
                    px[ox + x, oy + y] = bp[x, y]
    return im

# --------------------------------------------------------------- actors --
def skinish(c): return c[3] and c[0] > 150 and c[0] > c[1] > c[2] and c[0] - c[2] > 40
def dir_frames(src, fw, fh, gear_slot):
    im = Image.open(src).convert("RGBA"); W, H = im.size
    front = Image.new("RGBA", (W, H), (0, 0, 0, 0)); back = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sp, fp, bp = im.load(), front.load(), back.load()
    for f in range(W // fw):
        ox = f * fw; c = fw // 2
        for y in range(H):
            for x in range(fw):
                p = sp[ox + x, y]
                if gear_slot in ("weapon", "shield"):
                    fp[ox + x, y] = p
                    bp[ox + x, y] = shade(p, 0.7)[:3] + (p[3],) if p[3] else p
                    continue
                # front: the face side (right half, the art faces right) mirrored round the centre
                xr = x if x >= c else fw - 1 - x
                fp[ox + x, y] = sp[ox + min(fw - 1, xr), y]
                # back: the back side (left half) mirrored; skin on the head becomes hair
                xl = x if x < c else fw - 1 - x
                q = sp[ox + max(0, xl), y]
                if skinish(q) and y < H * 0.55: q = (88, 60, 38, 255)
                bp[ox + x, y] = q
    return front, back

def main():
    spr = json.load(open(SPR)); man = json.load(open(MAN))
    at = spr.setdefault("autotile", {})
    at["_doc"] = "0.3.9 autotile sheets: piece = N1|E2|S4|W8 (0..15), 16 '/' and 17 '\\' diagonals; 'broken_row' 1 = deteriorated variants (rural fences only, ~15% by tile hash)."
    at["fence_rural"] = {"path": save(fence_sheet(), "autotile/fence_rural.png"), "frame_size": [16, 24], "frames": 18, "rows": 2, "broken_row": 1, "anchor": "bottom"}
    cells = [{"file": "assets/sprites/autotile/fence_rural.png", "x": 0, "y": 0, "w": 288, "h": 48}]
    fams = {"stone_wall": "stone_wall", "palisade": "palisade", "basalt_wall": "basalt_wall", "sandstone_wall": "sandstone_wall", "capital_wall": "capital_wall"}
    wcells = []
    for fam, tile in fams.items():
        p = spr["tiles"][tile]["path"].replace("res://", "")
        at["wall_" + fam] = {"path": save(wall_sheet(avg(os.path.join(ROOT, p))), "autotile/wall_%s.png" % fam), "frame_size": [16, 16], "frames": 18}
        wcells.append({"file": "assets/sprites/autotile/wall_%s.png" % fam, "x": 0, "y": 16 * len(wcells), "w": 288, "h": 16})
    at["moat_border"] = {"path": save(moat_sheet(), "autotile/moat_border.png"), "frame_size": [16, 16], "frames": 20, "note": "0..15 banks by connection mask, 16..19 bridge joins N E S W"}
    wcells.append({"file": "assets/sprites/autotile/moat_border.png", "x": 0, "y": 16 * len(wcells), "w": 320, "h": 16})
    man["autotile_fence_16x24"] = {"cell_w": 288, "cell_h": 48, "cols": 1, "rows": 1, "cells": cells}
    man["autotile_tiles_16x16"] = {"cell_w": 320, "cell_h": 16, "cols": 1, "rows": len(wcells), "cells": wcells}
    tr = spr.setdefault("transitions", {})
    pri = {"marsh": 1, "grass": 2, "sand": 3, "ash": 3, "dirt": 4, "path": 5, "road_dirt": 5, "boardwalk": 6,
           "planks": 6, "floor": 6, "stone_floor": 6, "plaster": 6, "cobble": 7, "road_stone": 7, "cobble_dark": 8}
    tr["_rules"] = {"priority": pri, "doc": "0.3.9 a tile is overlaid by up to 2 higher-priority neighbouring floors; frame = edges(N1 E2 S4 W8) | corners(NW1 NE2 SE4 SW8)<<4 (corners only where both sides are not that floor). Water, walls and the moat never blend."}
    tcells = []
    for k, t in enumerate(pri):
        p = spr["tiles"][t]["path"].replace("res://", "")
        tr[t] = {"path": save(trans_sheet(os.path.join(ROOT, p), k + 11), "transitions/%s.png" % t), "frame_size": [16, 16], "frames": 256, "cols": 16}
        tcells.append({"file": "assets/sprites/transitions/%s.png" % t, "x": 0, "y": 256 * k, "w": 256, "h": 256})
    man["transitions_256x256"] = {"cell_w": 256, "cell_h": 256, "cols": 1, "rows": len(tcells), "cells": tcells}
    dcells = []
    for sid, d in spr["actors"].items():
        if sid.startswith("_"): continue
        rel = d["path"].replace("res://assets/sprites/", "")
        fw, fh = d["frame_size"]
        slot = sid.split("_")[1] if sid.startswith("gear_") else ""
        stem = rel[:-4]
        if not os.path.exists(os.path.join(A, stem + "_front.png")):
            f, b = dir_frames(os.path.join(A, rel), fw, fh, slot)
            save(f, stem + "_front.png"); save(b, stem + "_back.png")
        d["dir_paths"] = {"down": "res://assets/sprites/%s_front.png" % stem, "up": "res://assets/sprites/%s_back.png" % stem}
        W, H = Image.open(os.path.join(A, rel)).size
        for suf in ("_front", "_back"):
            dcells.append({"file": "assets/sprites/%s%s.png" % (stem, suf), "x": 0, "y": 0, "w": W, "h": H})
    man["actors_dirs_039"] = {"cell_w": 0, "cell_h": 0, "cols": 1, "rows": len(dcells), "note": "0.3.9 front (down) / back (up) sheets, same frames as the side sheet; one file per cell", "cells": dcells}
    spr["_doc_facing"] = "actors: the side sheet faces right ('flip' mirrors it for left); 'dir_paths' down/up are the front/back sheets with the same frames (0.3.9). Moving up shows the back, down the front."
    for o in ("fence", "fence_v", "road_fence"):
        spr["objects"][o]["autotile"] = "fence_rural"
    json.dump(spr, open(SPR, "w"), indent=1, ensure_ascii=False); json.dump(man, open(MAN, "w"), indent=1, ensure_ascii=False)
    print("ok", len(dcells), "dir sheets")

if __name__ == "__main__":
    main()
