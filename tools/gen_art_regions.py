#!/usr/bin/env python3
"""0.3.10 PLACEHOLDER art for the lore regions: recolours of existing sprites
(region grasses, rocky ground, cliffs, new trees, magic mushroom, dusk ore).
Every file written here is listed in docs/ART_TODO_0.3.10.md for the designer
to redraw, and registered in assets/sprites/placeholders.json (art_status.py).
Re-run safely: it only writes the 0.3.10 files.
"""
import os, json, hashlib, colorsys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = os.path.join(ROOT, "assets", "sprites")
OUT = []

def load(rel):
    return Image.open(os.path.join(S, rel)).convert("RGBA")

def save(im, rel):
    im.save(os.path.join(S, rel))
    OUT.append(rel)

def recolour(im, hue=None, sat=1.0, val=1.0, hue_shift=0.0, only=None):
    im = im.copy(); px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if only and not only(h, s, v):
                continue
            h = (hue if hue is not None else h + hue_shift) % 1.0
            s = min(1, s * sat); v = min(1, v * val)
            rr, gg, bb = colorsys.hsv_to_rgb(h, s, v)
            px[x, y] = (int(rr * 255), int(gg * 255), int(bb * 255), a)
    return im

green = lambda h, s, v: 0.17 < h < 0.48 and s > 0.15
# ---- region grasses (tile strip + transition sheet) ----
for name, kw in {"grass_lush": dict(hue_shift=0.015, sat=1.25, val=0.92),
                 "grass_boreal": dict(hue_shift=0.07, sat=0.6, val=0.85),
                 "grass_tropic": dict(hue_shift=-0.045, sat=1.3, val=1.08)}.items():
    save(recolour(load("tiles/grass.png"), **kw), f"tiles/{name}.png")
    save(recolour(load("transitions/grass.png"), **kw), f"transitions/{name}.png")
# rocky ground: grey dirt
save(recolour(load("tiles/dirt.png"), hue=0.08, sat=0.25, val=1.1), "tiles/rocky.png")
save(recolour(load("transitions/dirt.png"), hue=0.08, sat=0.25, val=1.1), "transitions/rocky.png")

# ---- cliffs (layered: lip on top, rock face below, shadow cast south) ----
rock = recolour(load("tiles/dirt.png"), hue=0.08, sat=0.22, val=1.3)   # light lip stone (rocky ground, brighter)
face = recolour(load("tiles/dirt.png"), hue=0.07, sat=0.35, val=0.8)  # rock face (darker rocky)
def cliff_face():
    out = Image.new("RGBA", (64, 16))
    for v in range(4):
        t = Image.new("RGBA", (16, 16))
        t.paste(face.crop((v * 16, 0, v * 16 + 16, 16)), (0, 0))
        px = t.load()
        for y in range(16):          # vertical striations + darker toward the foot
            for x in range(16):
                r, g, b, a = px[x, y]
                k = 1.0 - 0.03 * y - (0.25 if (x * 3 + v * 5 + (y // 5)) % 7 == 0 else 0) + (0.12 if (x * 3 + v * 5 + (y // 5)) % 7 == 1 else 0)
                px[x, y] = (int(r * k), int(g * k), int(b * k), 255)
        t.paste(rock.crop((v * 16, 0, v * 16 + 16, 4)), (0, 0))   # the top lip
        for x in range(16):
            px[x, 4] = (40, 34, 30, 255)                             # lip edge line
        out.paste(t, (v * 16, 0))
    return out
save(cliff_face(), "tiles/cliff_face.png")
lip = rock.copy(); px = lip.load()
for vx in range(64):
    for y in range(16):
        r, g, b, a = px[vx, y]
        x = vx % 16
        k = 0.85 if (x in (0, 15) or y in (0, 15)) else 1.0
        px[vx, y] = (int(r * k), int(g * k), int(b * k), 255)
save(lip, "tiles/cliff_lip.png")
sh = recolour(load("tiles/grass.png"), hue_shift=0.05, sat=0.7, val=0.55); px = sh.load()
for vx in range(64):
    for y in range(16):
        r, g, b, a = px[vx, y]
        k = 0.7 + 0.3 * (y / 15)       # darkest right under the face
        px[vx, y] = (int(r * k), int(g * k), int(b * k), 255)
save(sh, "tiles/cliff_shadow.png")
st = rock.copy(); px = st.load()
for vx in range(64):
    for y in range(16):
        if y % 4 == 3:
            r, g, b, a = px[vx, y]
            px[vx, y] = (int(r * 0.55), int(g * 0.55), int(b * 0.55), 255)   # step risers
save(st, "tiles/cliff_stairs.png")

# ---- trees ----
save(recolour(load("objects/tree_ash.png"), hue_shift=0.12, sat=0.9, val=0.75, only=green), "objects/tree_pine.png")
save(recolour(load("objects/burnt_tree.png"), hue=0.08, sat=0.35, val=1.9), "objects/tree_dead.png")
save(recolour(load("objects/tree_alder.png"), hue_shift=0.1, sat=0.7, val=0.7, only=green), "objects/tree_spruce.png")
mah = recolour(load("objects/tree_blackthorn.png"), hue=0.30, sat=1.2, val=1.15, only=lambda h, s, v: v > 0.35 and not (0.02 < h < 0.12))
save(recolour(mah, hue=0.02, sat=1.3, val=0.9, only=lambda h, s, v: 0.02 < h < 0.12), "objects/tree_mahogany.png")
# ---- magic mushroom (cyan glow), dusk ore ----
save(recolour(load("objects/fenroot_patch.png"), hue=0.5, sat=1.4, val=1.35), "objects/magic_mushroom.png")
save(recolour(load("items/fenroot.png"), hue=0.5, sat=1.4, val=1.35), "items/magic_mushroom.png")
save(recolour(load("objects/rock_iron.png"), hue=0.75, sat=1.2, val=0.9, only=lambda h, s, v: s > 0.2), "objects/rock_dusk.png")
save(recolour(load("items/iron_ore.png"), hue=0.75, sat=1.3, val=0.85, only=lambda h, s, v: s > 0.15), "items/dusk_ore.png")
save(recolour(load("items/steel_bar.png"), hue=0.74, sat=2.0, val=0.8), "items/dusk_steel_bar.png")
save(recolour(load("items/alder_log.png"), hue_shift=0.03, sat=0.8, val=0.85), "items/spruce_log.png")
save(recolour(load("items/blackthorn_log.png"), hue=0.01, sat=1.3, val=0.9), "items/mahogany_log.png")

man_p = os.path.join(S, "placeholders.json")
man = json.load(open(man_p))
for rel in OUT:
    man[rel] = hashlib.sha256(open(os.path.join(S, rel), "rb").read()).hexdigest()
json.dump(man, open(man_p, "w"), indent=1, sort_keys=True)
print("\n".join(OUT))
