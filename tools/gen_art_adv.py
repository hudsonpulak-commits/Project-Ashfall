#!/usr/bin/env python3
"""0.3.1 placeholder art for the adventurer track (run from the project root):
 - actors/gear/<slot>_<tier>.png: visible-gear overlays (4-frame strips, 16x24,
   same layout as actors/npc.png) for helmets, body armour, leg armour,
   shields (generic + buckler / kite / heater / tower) and weapons (sword /
   dagger / mace / warhammer / battleaxe / bow) per
   metal tier (1 bronze, 2 iron, 3 steel, 4 dusk).
 - ui/skull.png (8x8): the PK skull drawn over skulled actors and in the HUD.
 - ui/pk_zone.png (16x16): the HUD "PK zone" badge.
Like tools/gen_art.py it never overwrites a PNG the owner has replaced by hand
(sha256 manifest in assets/sprites/placeholders.json). Swap any of them for
hand-drawn art of the same size; data/sprites.json maps the ids."""
import os, sys, json, hashlib
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPR = os.path.join(ROOT, "assets", "sprites")
MANIFEST = os.path.join(SPR, "placeholders.json")
FORCE = "--force" in sys.argv
man = json.load(open(MANIFEST)) if os.path.exists(MANIFEST) else {}

def sha(p): return hashlib.sha256(open(p, "rb").read()).hexdigest()

def out(rel, im):
    path = os.path.join(SPR, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path) and not FORCE and man.get(rel) not in (None, sha(path)) :
        print("  keep (hand-made art):", rel); return
    if os.path.exists(path) and not FORCE and man.get(rel) is None:
        print("  keep (unknown art):", rel); return
    im.save(path); man[rel] = sha(path)

def hexc(h, a=255):
    h = h.lstrip("#"); return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)

METALS = {1: ("#b08a3c", "#d8b060", "#6a4a1a"), 2: ("#8a8e96", "#c8ccd4", "#55585e"),
          3: ("#6a7a8a", "#a8b8c8", "#3a4450"), 4: ("#5a4a7a", "#9a86c8", "#2e2440")}
WOOD = ("#a8784a", "#c89a6a", "#6a4a2a")
GEM = "#c84a3a"

def strip4(draw):
    s = Image.new("RGBA", (64, 24), (0, 0, 0, 0))
    for f in range(4):
        im = Image.new("RGBA", (16, 24), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
        draw(d, f); s.paste(im, (f * 16, 0))
    return s

# frame geometry of tools/gen_art.py person(): legs x5-6 (far, lifts on f1) and
# x9-10 (near, lifts on f3) y17-21; torso x4-11 y10-17; head x5-10 y4-9 (hair
# y3-4 + back x4-5); near arm x12 y11-15 (+1 f1, -1 f3); far arm x3 y11-14.
def head(t):
    m, hi, lo = METALS[t]
    def f(d, fr):
        d.rectangle([4, 2, 10, 4], fill=hexc(m)); d.rectangle([4, 4, 5, 7], fill=hexc(m))   # cap + back guard
        d.line([(5, 2), (9, 2)], fill=hexc(hi)); d.line([(4, 5), (10, 5)], fill=hexc(lo))  # rim
        d.point([(6, 5), (9, 5)], fill=hexc(m))
        if t >= 2: d.point([(11, 4)], fill=hexc(lo))                                       # brow peak
        if t >= 3: d.line([(4, 1), (9, 1)], fill=hexc(lo))                                 # taller crown
        if t == 4: d.line([(6, 0), (8, 0)], fill=hexc(GEM)); d.point([(7, 1)], fill=hexc(GEM))
    return f

def body(t):
    m, hi, lo = METALS[t]
    def f(d, fr):
        d.rectangle([4, 10, 11, 16], fill=hexc(m))
        d.line([(5, 11), (10, 11)], fill=hexc(hi)); d.line([(4, 15), (11, 15)], fill=hexc(lo))  # belt
        d.point([(7, 13), (8, 13)], fill=hexc(lo))
        if t >= 2: d.rectangle([3, 10, 4, 11], fill=hexc(hi)); d.rectangle([11, 10, 12, 11], fill=hexc(hi))  # pauldrons
        if t == 4: d.point([(8, 12)], fill=hexc(GEM))
    return f

def legs(t):
    m, hi, lo = METALS[t]
    def f(d, fr):
        back = 1 if fr == 1 else 0; front = 1 if fr == 3 else 0
        d.rectangle([5, 17, 6, 20 - back], fill=hexc(lo)); d.rectangle([9, 17, 10, 20 - front], fill=hexc(m))
        d.point([(9, 18 - front)], fill=hexc(hi))
        if t >= 3: d.point([(5, 18 - back), (10, 18 - front)], fill=hexc(hi))
    return f

def shield(t):
    m, hi, lo = METALS[t]
    def f(d, fr):
        if t == 1:
            w, wh, wl = WOOD
            d.ellipse([0, 10, 5, 16], fill=hexc(w)); d.point([(2, 13), (3, 13)], fill=hexc(m)); d.point([(1, 11)], fill=hexc(wh))
        elif t in (2, 3):
            d.polygon([(0, 10), (5, 10), (5, 14), (2, 17), (0, 14)], fill=hexc(m)); d.line([(2, 11), (2, 15)], fill=hexc(lo)); d.point([(1, 11)], fill=hexc(hi))
        else:
            d.rectangle([0, 9, 4, 17], fill=hexc(m)); d.rectangle([0, 9, 4, 17], outline=hexc(hi)); d.line([(2, 11), (2, 15)], fill=hexc(GEM))
    return f

def weapon(t, kind):
    m, hi, lo = METALS[t]
    def f(d, fr):
        sw = {1: 1, 3: -1}.get(fr, 0)
        hy = 14 + sw                                           # the near hand
        grip = hexc("#5a3b22")
        if kind == "sword":
            d.line([(13, hy - 9), (13, hy - 2)], fill=hexc(m)); d.line([(14, hy - 8), (14, hy - 2)], fill=hexc(hi))
            d.line([(12, hy - 1), (15, hy - 1)], fill=hexc(lo)); d.point([(13, hy)], fill=grip)
        elif kind == "dagger":
            d.line([(13, hy - 5), (13, hy - 2)], fill=hexc(hi)); d.line([(12, hy - 1), (14, hy - 1)], fill=hexc(lo)); d.point([(13, hy)], fill=grip)
        elif kind == "mace":
            d.line([(13, hy - 6), (13, hy + 1)], fill=grip); d.rectangle([12, hy - 9, 14, hy - 6], fill=hexc(m)); d.point([(13, hy - 9), (15, hy - 7)], fill=hexc(hi))
        elif kind == "warhammer":
            d.line([(13, hy - 7), (13, hy + 1)], fill=grip); d.rectangle([11, hy - 9, 15, hy - 7], fill=hexc(m)); d.line([(11, hy - 9), (15, hy - 9)], fill=hexc(hi))
        elif kind == "battleaxe":
            d.line([(13, hy - 9), (13, hy + 1)], fill=grip); d.polygon([(14, hy - 9), (15, hy - 10), (15, hy - 5), (14, hy - 6)], fill=hexc(m)); d.point([(15, hy - 8)], fill=hexc(hi))
        if t == 4: d.point([(13, hy - 1)], fill=hexc(GEM))
    return f

WOODS = {1: ("#c8a070", "#e0c090", "#7a5a3a"), 2: ("#a8784a", "#c89a6a", "#6a4a2a"),
         3: ("#4a3a3a", "#7a6060", "#2a2020"), 4: ("#3a2e4a", "#6a5a88", "#1e1828")}

def shield_kind(t, kind):
    """Shield silhouettes on the far arm (x0-5): buckler (small round), kite,
    heater (short, round bottom) and tower (tall)."""
    m, hi, lo = METALS[t]
    def f(d, fr):
        if kind == "buckler":
            w, wh, wl = WOOD if t == 1 else (m, hi, lo)
            d.ellipse([0, 11, 5, 16], fill=hexc(w), outline=hexc(wl)); d.rectangle([2, 13, 3, 14], fill=hexc(METALS[t][1]))
        elif kind == "kite":
            d.polygon([(0, 10), (5, 10), (5, 14), (2, 18), (0, 14)], fill=hexc(m)); d.line([(2, 11), (2, 16)], fill=hexc(lo)); d.point([(1, 11)], fill=hexc(hi))
        elif kind == "heater":
            d.rectangle([0, 10, 5, 13], fill=hexc(m)); d.polygon([(0, 13), (5, 13), (4, 15), (2, 16), (1, 15)], fill=hexc(m))
            d.line([(0, 10), (5, 10)], fill=hexc(hi)); d.line([(1, 12), (4, 12)], fill=hexc(lo))
        elif kind == "tower":
            d.rectangle([0, 8, 5, 18], fill=hexc(m)); d.rectangle([0, 8, 5, 18], outline=hexc(hi)); d.line([(2, 10), (2, 16)], fill=hexc(lo))
        if t == 4: d.point([(2, 13)], fill=hexc(GEM))
    return f

def bow(t):
    """A bow held upright in the near hand (x13-15), string toward the body."""
    w, wh, wl = WOODS[t]
    def f(d, fr):
        sw = {1: 1, 3: -1}.get(fr, 0)
        hy = 14 + sw
        d.line([(14, hy - 9), (15, hy - 7)], fill=hexc(w)); d.line([(15, hy - 6), (15, hy - 1)], fill=hexc(w))
        d.line([(15, hy), (14, hy + 2)], fill=hexc(w)); d.point([(15, hy - 4)], fill=hexc(wl))
        d.line([(13, hy - 8), (13, hy + 1)], fill=hexc("#e8e0c8"))       # string
        if t >= 3: d.point([(14, hy - 9), (14, hy + 2)], fill=hexc(wh))
    return f

sprites = {}
def gear(sid, rel, fn):
    out(rel, strip4(fn)); sprites[sid] = {"path": "res://assets/sprites/" + rel, "frame_size": [16, 24], "frames": 4, "fps": 5, "anchor": "bottom", "flip": True}

for t in (1, 2, 3, 4):
    gear(f"gear_head_{t}", f"actors/gear/head_{t}.png", head(t))
    gear(f"gear_body_{t}", f"actors/gear/body_{t}.png", body(t))
    gear(f"gear_legs_{t}", f"actors/gear/legs_{t}.png", legs(t))
    gear(f"gear_shield_{t}", f"actors/gear/shield_{t}.png", shield(t))
    gear(f"gear_weapon_{t}", f"actors/gear/weapon_sword_{t}.png", weapon(t, "sword"))
    for k in ("dagger", "mace", "warhammer", "battleaxe"):
        gear(f"gear_weapon_{k}_{t}", f"actors/gear/weapon_{k}_{t}.png", weapon(t, k))
    gear(f"gear_weapon_bow_{t}", f"actors/gear/weapon_bow_{t}.png", bow(t))
    for k in ("buckler", "kite", "heater", "tower"):
        gear(f"gear_shield_{k}_{t}", f"actors/gear/shield_{k}_{t}.png", shield_kind(t, k))

# skull (8x8) and the PK-zone badge (16x16)
im = Image.new("RGBA", (8, 8), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
bone, dark = hexc("#f0ece0"), hexc("#1a1414")
d.rectangle([1, 0, 6, 4], fill=bone); d.rectangle([0, 1, 7, 3], fill=bone); d.rectangle([2, 5, 5, 6], fill=bone)
d.point([(2, 2), (5, 2)], fill=dark); d.point([(3, 6), (4, 7)], fill=hexc("#a8a090")); d.point([(3, 4), (4, 4)], fill=hexc("#c8c0b0"))
out("ui/skull.png", im)
im = Image.new("RGBA", (16, 16), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
d.ellipse([0, 0, 15, 15], fill=hexc("#2a1410"), outline=hexc("#e8702a"))
sk = Image.open(os.path.join(SPR, "ui/skull.png")).resize((8, 8)); im.paste(sk, (4, 4), sk)
d.point([(3, 12), (12, 12), (8, 13)], fill=hexc("#ffb040"))
out("ui/pk_zone.png", im)
ui = {"skull": {"path": "res://assets/sprites/ui/skull.png"}, "pk_zone": {"path": "res://assets/sprites/ui/pk_zone.png"}}

json.dump(man, open(MANIFEST, "w"), indent=1, sort_keys=True)
if "--print-sprites" in sys.argv:
    print(json.dumps({"actors": sprites, "ui": ui}, indent=1))
else:
    json.dump({"actors": sprites, "ui": ui}, open("/tmp/adv_sprites.json", "w"))
print("0.3.1 adventurer gear + PK art generated:", len(sprites), "gear strips")
