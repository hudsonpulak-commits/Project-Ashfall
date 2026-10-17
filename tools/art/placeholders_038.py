#!/usr/bin/env python3
"""0.3.8 placeholder pixel art (swap freely: draw over the PNGs, or edit the
sheets listed in tools/art/aseprite_manifest.json and run import_sheets.py).
Writes PNGs only when missing (never overwrites Hudson's art) and registers
them in data/sprites.json + the Aseprite manifest. Re-runnable."""
import json, os, random
from PIL import Image, ImageDraw
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
S = os.path.join(ROOT, "assets", "sprites")

def rgb(h): h = h.lstrip("#"); return tuple(int(h[i:i+2], 16) for i in (0, 2, 4)) + (255,)

def noise_tile(base, dots, seed, n=40):
    r = random.Random(seed); im = Image.new("RGBA", (16, 16), rgb(base)); px = im.load()
    for _ in range(n):
        px[r.randrange(16), r.randrange(16)] = rgb(r.choice(dots))
    return im

def brick(base, mortar, seed, h=4, w=8):
    im = Image.new("RGBA", (16, 16), rgb(base)); d = ImageDraw.Draw(im)
    for y in range(0, 16, h):
        d.line([(0, y), (15, y)], fill=rgb(mortar))
        off = (y // h % 2) * (w // 2)
        for x in range(off, 16, w):
            d.line([(x, y), (x, y + h - 1)], fill=rgb(mortar))
    return im

def tiles():
    out = {}
    im = noise_tile("#8f8c84", ["#6f6c66", "#a6a39a"], 1, 30); d = ImageDraw.Draw(im)
    for y in (0, 5, 10, 15): d.line([(0, y), (15, y)], fill=rgb("#6a675f"))
    for i, y in enumerate((0, 5, 10)):
        for x in ((3, 11) if i % 2 == 0 else (7, 15)): d.line([(x, y), (x, y + 5)], fill=rgb("#6a675f"))
    out["road_stone"] = (im, "#8f8c84")
    out["road_dirt"] = (noise_tile("#9a7a4c", ["#7d6038", "#b08f5c", "#6e5532"], 2, 50), "#9a7a4c")
    m = noise_tile("#2a5f86", ["#3a77a3", "#22506f"], 3, 30); d = ImageDraw.Draw(m)
    d.line([(2, 5), (6, 5)], fill=rgb("#6aa6cc")); d.line([(9, 11), (13, 11)], fill=rgb("#6aa6cc"))
    out["moat"] = (m, "#2a5f86")
    e = brick("#9c9a92", "#6c6a64", 4, 4, 4); d = ImageDraw.Draw(e); d.rectangle([0, 12, 15, 15], fill=rgb("#2a5f86"))
    out["moat_edge"] = (e, "#9c9a92")
    out["capital_wall"] = (brick("#c9c2b0", "#8d8676", 5), "#c9c2b0")
    f = brick("#bdb5a2", "#857e6e", 6); d = ImageDraw.Draw(f); d.rectangle([0, 13, 15, 15], fill=rgb("#7a7364"))
    out["capital_front"] = (f, "#bdb5a2")
    g = Image.new("RGBA", (16, 16), rgb("#8f8c84")); d = ImageDraw.Draw(g)
    d.rectangle([0, 0, 1, 15], fill=rgb("#c9c2b0")); d.rectangle([14, 0, 15, 15], fill=rgb("#c9c2b0"))
    for x in range(3, 13, 3): d.line([(x, 0), (x, 15)], fill=rgb("#5a4a32"))
    out["gate_capital"] = (g, "#8f8c84")
    out["capital_bldg_wall"] = (brick("#e2dccb", "#a9a290", 7), "#e2dccb")
    f2 = brick("#d6cfbb", "#9d9684", 8); d = ImageDraw.Draw(f2); d.rectangle([5, 4, 10, 9], fill=rgb("#4a6a8a")); d.rectangle([5, 4, 10, 9], outline=rgb("#6e5532"))
    out["capital_bldg_front"] = (f2, "#d6cfbb")
    out["house_wall"] = (brick("#b88a5a", "#7a5a38", 9, 4, 16), "#b88a5a")
    f3 = brick("#a87a4c", "#6e5030", 10, 4, 16); d = ImageDraw.Draw(f3); d.rectangle([4, 3, 11, 9], fill=rgb("#f0d890")); d.line([(7, 3), (7, 9)], fill=rgb("#6e5030")); d.line([(4, 6), (11, 6)], fill=rgb("#6e5030"))
    out["house_front"] = (f3, "#a87a4c")
    return out

def objects():
    out = {}
    im = Image.new("RGBA", (16, 24), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    for x in (1, 13): d.rectangle([x, 10, x + 2, 23], fill=rgb("#7a5a38"))
    for y in (13, 18): d.rectangle([0, y, 15, y + 1], fill=rgb("#9a7448"))
    out["road_fence"] = im
    im = Image.new("RGBA", (16, 24), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.ellipse([1, 13, 14, 23], fill=rgb("#7c7c78")); d.ellipse([3, 14, 9, 18], fill=rgb("#9a9a94")); d.line([(4, 21), (12, 21)], fill=rgb("#5c5c58"))
    out["boulder"] = im
    im = Image.new("RGBA", (16, 24), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.ellipse([0, 10, 15, 23], fill=rgb("#3f7a32")); d.ellipse([3, 11, 10, 17], fill=rgb("#5a9a44")); d.point([(5, 19), (11, 15)], fill=rgb("#c04040"))
    out["bush"] = im
    im = Image.new("RGBA", (16, 24), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.rectangle([0, 16, 13, 21], fill=rgb("#6e5030")); d.ellipse([11, 16, 15, 21], fill=rgb("#c9a46a")); d.point([(13, 18)], fill=rgb("#7a5a38"))
    d.line([(1, 17), (10, 17)], fill=rgb("#8a6a44")); d.point([(4, 15), (5, 15)], fill=rgb("#4f8a3a"))
    out["old_log"] = im
    return out

def slime():
    im = Image.new("RGBA", (32, 16), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    for f, top in ((0, 6), (16, 8)):
        d.ellipse([f + 2, top, f + 13, 15], fill=rgb("#5cc04a")); d.ellipse([f + 4, top + 1, f + 8, top + 4], fill=rgb("#a8f090"))
        d.point([(f + 6, top + 4), (f + 10, top + 4)], fill=rgb("#1a2a18"))
    return im

def main():
    sp_path = os.path.join(ROOT, "data", "sprites.json"); sp = json.load(open(sp_path))
    man_path = os.path.join(ROOT, "tools", "art", "aseprite_manifest.json"); man = json.load(open(man_path))
    order = max(int(v.get("_order", 0)) for v in sp["tiles"].values())
    cells_t, cells_o = [], []
    for name, (im, mm) in tiles().items():
        f = os.path.join(S, "tiles", name + ".png")
        if not os.path.exists(f): im.save(f)
        if name not in sp["tiles"]:
            order += 1
            sp["tiles"][name] = {"path": "res://assets/sprites/tiles/%s.png" % name, "frame_size": [16, 16], "minimap_color": mm, "_order": order, "note": "0.3.8 placeholder"}
        cells_t.append(name)
    for name, im in objects().items():
        f = os.path.join(S, "objects", name + ".png")
        if not os.path.exists(f): im.save(f)
        sp["objects"].setdefault(name, {"path": "res://assets/sprites/objects/%s.png" % name, "frame_size": [16, 24], "frames": 1, "anchor": "bottom", "note": "0.3.8 placeholder road decoration"})
        cells_o.append(name)
    f = os.path.join(S, "actors", "slime.png")
    if not os.path.exists(f): slime().save(f)
    sp["actors"].setdefault("slime", {"path": "res://assets/sprites/actors/slime.png", "frame_size": [16, 16], "frames": 2, "fps": 3, "anchor": "bottom", "flip": True, "note": "0.3.8 placeholder"})
    json.dump(sp, open(sp_path, "w"), indent=1)
    def sheet(cells, folder, w, h):
        return {"cell_w": w, "cell_h": h, "cols": len(cells), "rows": 1, "note": "0.3.8 placeholders",
                "cells": [{"file": "assets/sprites/%s/%s.png" % (folder, n), "x": i * w, "y": 0, "w": w, "h": h} for i, n in enumerate(cells)]}
    man["tiles_038_16x16"] = sheet(cells_t, "tiles", 16, 16)
    man["objects_038_16x24"] = sheet(cells_o, "objects", 16, 24)
    a = man["actors_32x16"]
    if not any(c["file"].endswith("/slime.png") for c in a["cells"]):
        a["cells"].append({"file": "assets/sprites/actors/slime.png", "x": a["cols"] * 32, "y": 0, "w": 32, "h": 16}); a["cols"] += 1
    json.dump(man, open(man_path, "w"), indent=1)
    print("tiles", cells_t, "objects", cells_o, "slime")

main()
