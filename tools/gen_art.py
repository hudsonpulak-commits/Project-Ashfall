#!/usr/bin/env python3
"""Generates Ashfen's original placeholder pixel art.

Everything here is drawn procedurally from simple shapes and a hand-picked
palette, so it is 100% original and safe to ship. Artists can replace any PNG
in assets/ with a hand-made version of the same size; the game only cares
about file names (see data/*.json "sprite"/"icon" fields).

Usage: python3 tools/gen_art.py   (from the project root)
"""
import os as _o, sys as _s; _s.path.insert(0, _o.path.join(_o.path.dirname(_o.path.abspath(__file__)), "art")); import art_guard  # noqa: E402,F401  0.3.9.2: never overwrite hand-drawn art
import os, random
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
import sys, json, hashlib
SPR = os.path.join(ROOT, "assets", "sprites")
MANIFEST = os.path.join(SPR, "placeholders.json")
FORCE = "--force" in sys.argv
_manifest = json.load(open(MANIFEST)) if os.path.exists(MANIFEST) else {}
_written = []

def _sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()

def out(category, name, im):
    """Save a placeholder PNG unless the owner has replaced it with real art."""
    rel = f"{category}/{name}.png"
    path = os.path.join(SPR, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path) and not FORCE:
        known = _manifest.get(rel)
        if known is None or _sha(path) != known:
            print(f"  keep (hand-made art): {rel}")
            return
    im.save(path)
    _manifest[rel] = _sha(path)
    _written.append(rel)

def strip(frames):
    """Horizontal animation/variant strip, left to right."""
    w, h = frames[0].size
    s = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        s.paste(f, (i * w, 0))
    return s

def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)

def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + (c[3],)

T = 16  # source pixels per tile; the game scales x3

# ---------------------------------------------------------------- tiles ----
# Row order must match WorldGen.TileType in src/world/world_gen.gd
TILE_BASE = [
    ("grass", "#4a7a3a"),
    ("path",  "#9a7c4c"),
    ("water", "#2e6a8c"),
    ("sand",  "#cdb878"),
    ("dirt",  "#6e5236"),
    ("cobble","#80827a"),
    ("planks","#8a6438"),
    ("marsh", "#3e5e3a"),
]
VARIANTS = 4

def tile(kind, base, v):
    rnd = random.Random(hash((kind, v)) & 0xffffffff)
    rnd.seed(f"{kind}-{v}")
    im = Image.new("RGBA", (T, T), hexc(base))
    px = im.load()
    b = hexc(base)
    for y in range(T):
        for x in range(T):
            r = rnd.random()
            if r < 0.18: px[x, y] = shade(b, 0.9)
            elif r < 0.26: px[x, y] = shade(b, 1.08)
    d = ImageDraw.Draw(im)
    if kind == "grass":
        for _ in range(3 + v):
            x, y = rnd.randrange(1, 15), rnd.randrange(2, 15)
            d.point([(x, y), (x, y - 1)], fill=shade(b, 1.25))
            d.point([(x + 1, y)], fill=shade(b, 0.8))
        if v == 3:
            x, y = rnd.randrange(3, 13), rnd.randrange(3, 13)
            d.point([(x, y)], fill=hexc("#e8d870"))
            d.point([(x + 4, y + 2)], fill=hexc("#d88aa0"))
    elif kind == "marsh":
        for _ in range(4):
            x, y = rnd.randrange(1, 15), rnd.randrange(3, 15)
            d.line([(x, y), (x, y - 3)], fill=hexc("#6f8a46"))
        if v % 2 == 0:
            x, y = rnd.randrange(2, 11), rnd.randrange(4, 12)
            d.ellipse([x, y, x + 4, y + 2], fill=hexc("#35596a"))
    elif kind == "water":
        for i in range(2):
            x, y = rnd.randrange(0, 11), rnd.randrange(2, 14)
            d.line([(x, y), (x + 3, y)], fill=shade(b, 1.35))
            d.line([(x + 1, y + 1), (x + 4, y + 1)], fill=shade(b, 0.85))
    elif kind == "path":
        for _ in range(3):
            x, y = rnd.randrange(1, 14), rnd.randrange(1, 14)
            d.point([(x, y), (x + 1, y)], fill=hexc("#b49a68"))
            d.point([(x, y + 1)], fill=hexc("#6e5532"))
    elif kind == "sand":
        for _ in range(4):
            x, y = rnd.randrange(0, 16), rnd.randrange(0, 16)
            d.point([(x, y)], fill=hexc("#e3d39a"))
    elif kind == "dirt":
        for _ in range(3):
            x, y = rnd.randrange(1, 14), rnd.randrange(1, 14)
            d.rectangle([x, y, x + 1, y], fill=hexc("#54402a"))
    elif kind == "cobble":
        im.paste(hexc("#5b5d56"), (0, 0, T, T))
        for (x0, y0, x1, y1) in [(0,0,7,6),(8,0,15,6),(0,8,4,15),(5,8,11,15),(12,8,15,15)]:
            c = shade(hexc("#868a80"), 0.92 + 0.06 * ((x0 + v) % 3))
            d.rectangle([x0, y0, x1 - 1, y1 - 1], fill=c)
            d.line([(x0, y0), (x1 - 1, y0)], fill=shade(c, 1.15))
    elif kind == "planks":
        for row in range(4):
            y0 = row * 4
            d.line([(0, y0 + 3), (15, y0 + 3)], fill=hexc("#5e4225"))
            off = (row * 5 + v * 3) % 16
            d.line([(off, y0), (off, y0 + 2)], fill=hexc("#5e4225"))
    return im

for kind, base in TILE_BASE:
    out("tiles", kind, strip([tile(kind, base, v) for v in range(VARIANTS)]))

# ------------------------------------------------------------ entities ----
# 16 wide x 24 tall; bottom 16px sit on the tile, top 8px overhang.
def canvas(h=24):
    return Image.new("RGBA", (16, h), (0, 0, 0, 0))

def shadow(d, y=21):
    d.ellipse([3, y, 12, y + 2], fill=(0, 0, 0, 70))

def tree(name, trunk, leaf, leaf_dark, shape="round"):
    im = canvas(); d = ImageDraw.Draw(im)
    shadow(d)
    d.rectangle([7, 14, 8, 21], fill=hexc(trunk))
    d.point([(6, 21), (9, 21)], fill=hexc(trunk))
    if shape == "round":
        d.ellipse([1, 1, 14, 15], fill=hexc(leaf_dark))
        d.ellipse([2, 1, 13, 12], fill=hexc(leaf))
        d.point([(5, 4), (6, 3), (9, 6), (4, 8)], fill=shade(hexc(leaf), 1.25))
    elif shape == "tall":
        d.polygon([(8, 0), (14, 15), (1, 15)], fill=hexc(leaf_dark))
        d.polygon([(8, 1), (12, 11), (3, 11)], fill=hexc(leaf))
        d.point([(7, 4), (6, 7), (9, 8)], fill=shade(hexc(leaf), 1.25))
    elif shape == "thorn":
        d.ellipse([1, 2, 14, 15], fill=hexc(leaf_dark))
        for (x, y) in [(3, 4), (11, 5), (6, 2), (9, 11), (4, 11), (12, 9)]:
            d.point([(x, y), (x + 1, y - 1)], fill=hexc(leaf))
        d.point([(7, 7), (8, 6)], fill=hexc("#b03a3a"))
    out("objects", name, im)

tree("tree_ash", "#5a3b22", "#5f9a46", "#3c6a30", "round")
tree("tree_alder", "#4a3324", "#3f8a5a", "#2a5e3e", "tall")
tree("tree_blackthorn", "#2e2420", "#4b5a3a", "#262f20", "thorn")

im = canvas(); d = ImageDraw.Draw(im); shadow(d)
d.ellipse([4, 15, 11, 21], fill=hexc("#5a3b22")); d.ellipse([5, 15, 10, 18], fill=hexc("#c9a46a"))
d.point([(7, 16), (8, 17)], fill=hexc("#8a6a40"))
out("objects", "stump", im)

def rock(name, ore):
    im = canvas(); d = ImageDraw.Draw(im); shadow(d)
    d.polygon([(2, 21), (1, 15), (5, 10), (11, 9), (15, 14), (14, 21)], fill=hexc("#6e7078"))
    d.polygon([(3, 15), (6, 11), (11, 10), (13, 14), (9, 15)], fill=hexc("#8d9098"))
    if ore:
        for (x, y) in [(5, 13), (9, 12), (11, 16), (6, 18), (3, 17)]:
            d.rectangle([x, y, x + 1, y + 1], fill=hexc(ore))
    out("objects", name, im)

rock("rock_copper", "#c8783c")
rock("rock_tin", "#d0d4d8")
rock("rock_iron", "#9a5a48")
rock("rock_coal", "#1e1e22")
rock("rock_empty", None)

# fishing spot: 2 frames of ripples (transparent, sits on water)
_fr = []
for f in range(2):
    im = canvas(); d = ImageDraw.Draw(im)
    r = 3 + f * 2
    d.ellipse([8 - r, 16 - r // 2, 8 + r, 16 + r // 2], outline=(220, 240, 255, 200))
    d.point([(5 + f, 13), (11 - f, 19)], fill=(255, 255, 255, 230))
    _fr.append(im)
out("objects", "fishing_spot", strip(_fr))

im = canvas(); d = ImageDraw.Draw(im); shadow(d)
d.rectangle([7, 9, 8, 21], fill=hexc("#7a5a30"))
d.rectangle([4, 10, 11, 17], fill=hexc("#c8a868"))
d.rectangle([3, 11, 12, 12], fill=hexc("#b89858"))
d.ellipse([5, 3, 10, 9], fill=hexc("#d8c08a"))
d.line([(5, 14), (10, 14)], fill=hexc("#8a6a3a"))
out("objects", "dummy", im)

im = canvas(); d = ImageDraw.Draw(im); shadow(d)
d.rectangle([2, 12, 13, 21], fill=hexc("#7a4e24"))
d.rectangle([2, 10, 13, 13], fill=hexc("#94622e"))
d.line([(2, 14), (13, 14)], fill=hexc("#3a2612"))
d.rectangle([2, 10, 2, 21], fill=hexc("#c8a040")); d.rectangle([13, 10, 13, 21], fill=hexc("#c8a040"))
d.rectangle([7, 14, 8, 16], fill=hexc("#f0d070"))
out("objects", "bank_chest", im)

im = canvas(); d = ImageDraw.Draw(im); shadow(d)
d.rectangle([2, 12, 13, 21], fill=hexc("#7d7a72"))
d.rectangle([3, 13, 12, 20], fill=hexc("#5f5c55"))
d.rectangle([5, 16, 10, 20], fill=hexc("#2a1a10"))
for (x, y, c) in [(6, 18, "#f0a030"), (8, 17, "#ffd060"), (7, 19, "#e0602a"), (9, 19, "#f0a030")]:
    d.point([(x, y)], fill=hexc(c))
d.rectangle([4, 10, 11, 12], fill=hexc("#3c3a36"))
out("objects", "hearth", im)

im = canvas(); d = ImageDraw.Draw(im); shadow(d)
d.polygon([(2, 21), (3, 8), (12, 8), (13, 21)], fill=hexc("#6a4a3a"))
d.rectangle([6, 2, 9, 8], fill=hexc("#4e3a30"))
d.rectangle([5, 14, 10, 20], fill=hexc("#1a0e08"))
d.rectangle([6, 16, 9, 20], fill=hexc("#e8702a")); d.rectangle([7, 17, 8, 20], fill=hexc("#ffd070"))
for y in range(9, 21, 3):
    d.line([(3, y), (12, y)], fill=hexc("#57392c"))
out("objects", "furnace", im)

im = canvas(); d = ImageDraw.Draw(im); shadow(d)
d.rectangle([3, 11, 4, 21], fill=hexc("#5a3b22")); d.rectangle([11, 11, 12, 21], fill=hexc("#5a3b22"))
d.rectangle([1, 4, 14, 13], fill=hexc("#8a6438")); d.rectangle([2, 5, 13, 12], fill=hexc("#e8dcb4"))
for y in (6, 8, 10):
    d.line([(3, y), (8, y)], fill=hexc("#4a4a4a")); d.line([(10, y), (12, y)], fill=hexc("#2a8a3a" if y != 8 else "#a83a3a"))
out("objects", "exchange_board", im)

# actors: body colours are swapped at runtime via modulate for AI players
def person(name, tunic, hair, legs="#3a3a48"):
    # 0.2.5: 4-frame walk cycle [stand, back leg lifted, stand, front leg lifted].
    # The 0.2.3 2-frame cycle swapped which arm/leg was low, which on a
    # front-facing figure is a mirror image: walking looked like the avatar
    # flipping left/right. Now the head is a 3/4 view facing RIGHT (eyes and
    # nose to the right, hair tuft at the back), the upper body never changes
    # and only one leg lifts at a time, so no frame mirrors another and
    # flip_h alone says which way the actor faces.
    frames = []
    skin = hexc("#e2b896")
    for f in range(4):
        im = canvas(); d = ImageDraw.Draw(im); shadow(d)
        back_up = 1 if f == 1 else 0     # far leg (left) lifts
        front_up = 1 if f == 3 else 0    # near leg (right) lifts
        d.rectangle([5, 17, 6, 21 - back_up], fill=shade(hexc(legs), 0.8))
        d.rectangle([9, 17, 10, 21 - front_up], fill=hexc(legs))
        d.rectangle([4, 10, 11, 17], fill=hexc(tunic))
        d.line([(4, 15), (11, 15)], fill=shade(hexc(tunic), 0.7))
        d.rectangle([3, 11, 3, 14], fill=shade(skin, 0.85))          # far arm, tucked
        swing = {1: 1, 3: -1}.get(f, 0)                               # near arm swings with the stride
        d.rectangle([12, 11, 12, 15 + swing], fill=skin)
        d.rectangle([5, 4, 10, 9], fill=skin)
        d.point([(11, 7)], fill=skin)                                 # nose (faces right)
        d.rectangle([5, 3, 10, 4], fill=hexc(hair)); d.rectangle([4, 4, 5, 7], fill=hexc(hair))  # hair falls at the back
        d.point([(8, 6), (10, 6)], fill=hexc("#22201c"))
        frames.append(im)
    out("actors", name, strip(frames))

person("player", "#2c5c9a", "#6b3f22")
person("npc", "#ffffff", "#40403c", legs="#4a4a44")  # tinted per AI persona

# tap marker
im = Image.new("RGBA", (16, 16), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
d.line([(3, 3), (12, 12)], fill=hexc("#ffd84a"), width=2); d.line([(12, 3), (3, 12)], fill=hexc("#ffd84a"), width=2)
out("ui", "tap_marker", im)

# ---------------------------------------------------------------- icons ----
def icon(name, fn):
    im = Image.new("RGBA", (16, 16), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    fn(d)
    out("items", name, im)

def log_icon(bark, core):
    def f(d):
        d.polygon([(2, 10), (11, 3), (14, 6), (5, 13)], fill=hexc(bark))
        d.ellipse([11, 2, 15, 7], fill=hexc(core)); d.point([(13, 4)], fill=shade(hexc(core), 0.7))
        d.line([(5, 9), (9, 6)], fill=shade(hexc(bark), 0.7))
    return f

def ore_icon(fleck, base="#6e7078"):
    def f(d):
        d.polygon([(2, 12), (3, 6), (8, 3), (13, 5), (14, 11), (9, 14)], fill=hexc(base))
        for (x, y) in [(5, 7), (9, 5), (10, 10), (6, 11)]:
            d.rectangle([x, y, x + 1, y + 1], fill=hexc(fleck))
    return f

def bar_icon(c):
    def f(d):
        d.polygon([(2, 11), (5, 6), (14, 6), (11, 11)], fill=hexc(c))
        d.polygon([(2, 11), (11, 11), (11, 13), (2, 13)], fill=shade(hexc(c), 0.7))
        d.line([(6, 7), (12, 7)], fill=shade(hexc(c), 1.3))
    return f

def fish_icon(c, cooked=False, burnt=False):
    def f(d):
        body = hexc("#2a2420") if burnt else (shade(hexc(c), 0.75) if cooked else hexc(c))
        d.ellipse([2, 5, 12, 11], fill=body)
        d.polygon([(11, 8), (15, 4), (15, 12)], fill=body)
        d.point([(4, 7)], fill=hexc("#101010"))
        if cooked and not burnt:
            d.line([(5, 9), (9, 7)], fill=hexc("#4a2a14"))
    return f

def tool_icon(head, kind):
    def f(d):
        d.line([(3, 14), (11, 4)], fill=hexc("#7a5a30"), width=2)
        if kind == "hatchet":
            d.polygon([(9, 2), (14, 3), (13, 8), (10, 6)], fill=hexc(head))
        elif kind == "pick":
            d.line([(6, 3), (14, 7)], fill=hexc(head), width=2)
        elif kind == "sword":
            d.line([(4, 12), (13, 3)], fill=hexc(head), width=2)
            d.line([(3, 9), (7, 13)], fill=hexc("#7a5a30"), width=2)
        elif kind == "rod":
            d.line([(11, 4), (14, 13)], fill=hexc("#d8d8d8"))
    return f

icon("marks", lambda d: (d.ellipse([3, 5, 12, 13], fill=hexc("#b88a2a")), d.ellipse([3, 3, 12, 11], fill=hexc("#e8c050")), d.ellipse([5, 5, 10, 9], outline=hexc("#b88a2a"))))
icon("ash_log", log_icon("#6b4a2c", "#d8b680"))
icon("alder_log", log_icon("#5a3a2a", "#c89a6a"))
icon("blackthorn_log", log_icon("#2e2420", "#8a6a50"))
icon("copper_ore", ore_icon("#d0803c"))
icon("tin_ore", ore_icon("#c4c8cc"))
icon("iron_ore", ore_icon("#a86a54"))
icon("coal", ore_icon("#202024", base="#3a3a40"))
icon("bronze_bar", bar_icon("#b08a3c"))
icon("iron_bar", bar_icon("#8a8e96"))
icon("steel_bar", bar_icon("#6a7a8a"))
icon("raw_carp", fish_icon("#8aa070"))
icon("cooked_carp", fish_icon("#c8a060", cooked=True))
icon("raw_eel", fish_icon("#5a6a5a"))
icon("cooked_eel", fish_icon("#a87a50", cooked=True))
icon("charred_fish", fish_icon("#000000", burnt=True))
icon("bronze_hatchet", tool_icon("#b08a3c", "hatchet"))
icon("bronze_pick", tool_icon("#b08a3c", "pick"))
icon("iron_hatchet", tool_icon("#8a8e96", "hatchet"))
icon("iron_pick", tool_icon("#8a8e96", "pick"))
icon("iron_sword", tool_icon("#8a8e96", "sword"))
icon("reed_rod", tool_icon("#ffffff", "rod"))
icon("plank", lambda d: (d.rectangle([2, 6, 14, 10], fill=hexc("#a8784a")), d.line([(2, 8), (14, 8)], fill=hexc("#7a5430"))))
icon("fenroot", lambda d: (d.line([(8, 14), (8, 6)], fill=hexc("#6a8a3a")), d.ellipse([4, 2, 8, 7], fill=hexc("#7aa84a")), d.ellipse([8, 3, 12, 8], fill=hexc("#5a8a3a")), d.line([(8, 14), (5, 15)], fill=hexc("#8a6a4a"))))
icon("reed_fibre", lambda d: [d.line([(4 + i * 2, 14), (6 + i * 2, 2)], fill=hexc("#c8b86a")) for i in range(4)])
icon("marsh_tonic", lambda d: (d.rectangle([6, 2, 9, 4], fill=hexc("#8a6a4a")), d.ellipse([3, 4, 12, 14], fill=hexc("#cfe8e8")), d.ellipse([4, 7, 11, 13], fill=hexc("#5aa86a"))))
icon("unknown", lambda d: d.rectangle([3, 3, 12, 12], outline=hexc("#c8b07a")))
# magenta "missing" sprite: shown in-game whenever a mapped PNG doesn't exist
_m = Image.new("RGBA", (16, 16), hexc("#ff00ff"))
ImageDraw.Draw(_m).rectangle([0, 0, 7, 7], fill=hexc("#000000")); ImageDraw.Draw(_m).rectangle([8, 8, 15, 15], fill=hexc("#000000"))
out("ui", "missing", _m)

# ------------------------------------------------------------- app icon ----
def app_icon(size, bg=True, fg=True):
    im = Image.new("RGBA", (64, 64), hexc("#1d2a1a") if bg else (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if bg:
        d.rectangle([0, 40, 63, 63], fill=hexc("#2e5a6c"))
        d.line([(6, 48), (20, 48)], fill=hexc("#5a8aa0")); d.line([(36, 55), (54, 55)], fill=hexc("#5a8aa0"))
    if fg:
        # stylised ash tree over the fen
        d.rectangle([30, 26, 33, 46], fill=hexc("#5a3b22"))
        d.ellipse([16, 8, 47, 34], fill=hexc("#3c6a30")); d.ellipse([19, 9, 44, 28], fill=hexc("#5f9a46"))
        d.point([(26, 14), (35, 18), (30, 12)], fill=hexc("#9ad070"))
        d.ellipse([24, 44, 40, 48], fill=(0, 0, 0, 80))
    # integer scaling only (pixel-perfect); pad to the target size if needed
    k = size // 64
    big = im.resize((64 * k, 64 * k), Image.NEAREST)
    if 64 * k == size:
        return big
    canvas_ = Image.new("RGBA", (size, size), hexc("#1d2a1a") if bg else (0, 0, 0, 0))
    off = (size - 64 * k) // 2
    canvas_.paste(big, (off, off))
    return canvas_

os.makedirs(os.path.join(SPR, "app"), exist_ok=True)
out("app", "icon_64", app_icon(64))   # source pixel art; scaled copies below are derived
app_icon(256).save(os.path.join(ROOT, "icon.png"))
app_icon(192).save(os.path.join(ROOT, "assets", "app_icon_main_192.png"))
app_icon(432, bg=False).save(os.path.join(ROOT, "assets", "app_icon_fg_432.png"))
app_icon(432, fg=False).save(os.path.join(ROOT, "assets", "app_icon_bg_432.png"))


# ---- extra M1 nodes (appended) ----
im = canvas(); d = ImageDraw.Draw(im)
for i, x in enumerate([3, 6, 9, 12]):
    d.line([(x, 21), (x + (i % 2), 9 + (i * 3) % 5)], fill=hexc("#b8a85a"))
    d.rectangle([x + (i % 2), 8 + (i * 3) % 5, x + (i % 2), 10 + (i * 3) % 5], fill=hexc("#6a4a2a"))
out("objects", "reed_bed", im)

im = canvas(); d = ImageDraw.Draw(im)
for (x, y) in [(4, 16), (9, 14), (11, 18)]:
    d.line([(x + 1, y + 4), (x + 1, y)], fill=hexc("#4a6a2a"))
    d.ellipse([x - 1, y - 3, x + 3, y + 1], fill=hexc("#7aa84a"))
d.point([(5, 12), (10, 10)], fill=hexc("#e0e070"))
out("objects", "fenroot_patch", im)

im = canvas(); d = ImageDraw.Draw(im); shadow(d)
d.rectangle([1, 12, 14, 14], fill=hexc("#a8784a")); d.line([(1, 12), (14, 12)], fill=hexc("#c89868"))
d.rectangle([2, 15, 3, 21], fill=hexc("#6a4a2a")); d.rectangle([12, 15, 13, 21], fill=hexc("#6a4a2a"))
d.line([(5, 11), (10, 11)], fill=hexc("#8a8e96")); d.rectangle([9, 10, 10, 11], fill=hexc("#5a3b22"))
out("objects", "workbench", im)
json.dump(_manifest, open(MANIFEST, "w"), indent=1, sort_keys=True)
print(f"wrote {len(_written)} placeholder PNGs; manifest: {MANIFEST}")

# ---- M2 additions ----
im = canvas(); d = ImageDraw.Draw(im); shadow(d)
d.rectangle([5, 16, 10, 21], fill=hexc("#5a3b22"))                     # stump base
d.rectangle([2, 12, 13, 15], fill=hexc("#5c5f66"))                     # anvil body
d.polygon([(13, 12), (15, 13), (13, 14)], fill=hexc("#5c5f66"))         # horn
d.line([(2, 12), (13, 12)], fill=hexc("#9a9ea6"))
d.rectangle([5, 15, 10, 16], fill=hexc("#45474d"))
d.point([(7, 10), (9, 9), (6, 9)], fill=hexc("#ffb040"))                # sparks
out("objects", "anvil", im)

# (0.3.0: the market-stall art was replaced by walk-in buildings, see the end of this file)

json.dump(_manifest, open(MANIFEST, "w"), indent=1, sort_keys=True)
print("M2 art generated")

# ---- M2 world update: gear lines (3 metal tiers) + specialist shop stalls ----
# 0.2.3: 1 bronze, 2 iron, 3 steel, 4 dusksteel (dusk details keyed on t == 4)
METALS = {1: ("#b08a3c", "#d8b060", "#6a4a1a"), 2: ("#8a8e96", "#c8ccd4", "#55585e"), 3: ("#6a7a8a", "#a8b8c8", "#3a4450"), 4: ("#5a4a7a", "#9a86c8", "#2e2440")}
WOOD = {1: ("#a8784a", "#c89a6a"), 2: ("#8a5a3a", "#b07a50"), 3: ("#3a2a24", "#6a4a3a")}

def helm(t):
    m, hi, lo = METALS[t]
    def f(d):
        d.chord([3, 3, 13, 15], 180, 360, fill=hexc(m)); d.rectangle([3, 9, 13, 11], fill=hexc(m))
        d.line([(4, 5), (8, 3)], fill=hexc(hi)); d.rectangle([3, 11, 13, 12], fill=hexc(lo))
        if t >= 2: d.rectangle([7, 9, 9, 13], fill=hexc(lo))
        if t == 4: d.line([(8, 1), (8, 3)], fill=hexc("#c84a3a"), width=2)
    return f

def body(t):
    m, hi, lo = METALS[t]
    def f(d):
        d.polygon([(4, 3), (12, 3), (14, 6), (12, 7), (12, 14), (4, 14), (4, 7), (2, 6)], fill=hexc(m))
        d.line([(6, 4), (10, 4)], fill=hexc(lo), width=1); d.line([(5, 8), (11, 8)], fill=hexc(hi))
        for y in (10, 12): d.line([(5, y), (11, y)], fill=hexc(lo))
        if t == 4: d.point([(8, 6)], fill=hexc("#c84a3a"))
    return f

def legs(t):
    m, hi, lo = METALS[t]
    def f(d):
        d.rectangle([4, 2, 12, 5], fill=hexc(lo)); d.rectangle([4, 5, 7, 14], fill=hexc(m)); d.rectangle([9, 5, 12, 14], fill=hexc(m))
        d.line([(5, 6), (5, 13)], fill=hexc(hi)); d.line([(10, 6), (10, 13)], fill=hexc(hi))
        if t >= 2: d.rectangle([4, 9, 7, 10], fill=hexc(lo)); d.rectangle([9, 9, 12, 10], fill=hexc(lo))
    return f

def shield(t):
    m, hi, lo = METALS[t]
    def f(d):
        if t == 1:
            w, wh = WOOD[1]
            d.ellipse([2, 2, 14, 14], fill=hexc(w)); d.ellipse([6, 6, 10, 10], fill=hexc(m)); d.line([(4, 5), (6, 3)], fill=hexc(wh))
        elif t in (2, 3):
            d.polygon([(3, 2), (13, 2), (13, 8), (8, 15), (3, 8)], fill=hexc(m)); d.line([(8, 3), (8, 13)], fill=hexc(lo)); d.line([(4, 6), (12, 6)], fill=hexc(lo))
        else:
            d.rectangle([3, 1, 13, 14], fill=hexc(m)); d.rectangle([3, 1, 13, 14], outline=hexc(hi)); d.line([(8, 3), (8, 12)], fill=hexc("#c84a3a"), width=2)
    return f

def sword(t):
    m, hi, lo = METALS[t]
    def f(d):
        d.line([(4, 12), (13, 3)], fill=hexc(m), width=2); d.line([(5, 11), (13, 3)], fill=hexc(hi))
        d.line([(3, 9), (7, 13)], fill=hexc("#7a5a30"), width=2); d.point([(2, 14)], fill=hexc(lo))
    return f

def axe(t):
    m, hi, lo = METALS[t]
    def f(d):
        d.line([(3, 14), (11, 3)], fill=hexc("#6a4a28"), width=2)
        d.polygon([(8, 2), (14, 1), (15, 8), (11, 7)], fill=hexc(m)); d.polygon([(8, 2), (4, 1), (4, 6), (7, 6)], fill=hexc(m))
        d.line([(14, 2), (15, 7)], fill=hexc(hi))
    return f

def mace(t):
    m, hi, lo = METALS[t]
    def f(d):
        d.line([(3, 14), (9, 7)], fill=hexc("#6a4a28"), width=2)
        d.ellipse([8, 2, 14, 8], fill=hexc(m)); d.point([(10, 3)], fill=hexc(hi))
        for p in [(11, 1), (15, 5), (7, 5), (11, 9)]: d.point([p], fill=hexc(lo))
    return f

def dagger(t):
    # 0.2.4: short stabbing blade, small cross-guard, wrapped grip
    m, hi, lo = METALS[t]
    def f(d):
        d.line([(7, 9), (12, 4)], fill=hexc(m), width=2); d.line([(8, 8), (12, 4)], fill=hexc(hi))
        d.point([(13, 3)], fill=hexc(hi))
        d.line([(5, 8), (8, 11)], fill=hexc(lo), width=1)
        d.line([(4, 12), (6, 10)], fill=hexc("#7a5a30"), width=2); d.point([(3, 13)], fill=hexc(lo))
        if t == 4: d.point([(6, 9)], fill=hexc("#c84a3a"))
    return f

def warhammer(t):
    # 0.2.4: long haft, heavy square head with a back spike (crush)
    m, hi, lo = METALS[t]
    def f(d):
        d.line([(2, 15), (10, 6)], fill=hexc("#6a4a28"), width=2)
        d.polygon([(7, 1), (12, 1), (15, 4), (15, 7), (10, 7), (7, 4)], fill=hexc(m))
        d.line([(8, 1), (12, 1)], fill=hexc(hi)); d.line([(15, 4), (15, 7)], fill=hexc(lo))
        d.polygon([(7, 4), (4, 5), (7, 6)], fill=hexc(lo))
        if t == 4: d.point([(11, 4)], fill=hexc("#c84a3a"))
    return f

def bow(t):
    w, wh = WOOD[t]
    def f(d):
        d.arc([2, 1, 14, 15], 260, 100, fill=hexc(w), width=2)
        d.line([(9, 1), (9, 15)], fill=hexc("#e8e0c8"))
        d.point([(13, 8)], fill=hexc(wh))
    return f

def arrows(t):
    m, hi, lo = METALS[t]
    def f(d):
        for i in range(3):
            d.line([(3 + i * 2, 14), (11 + i * 2, 3)], fill=hexc("#a8784a"))
            d.point([(11 + i * 2, 3)], fill=hexc(m)); d.point([(3 + i * 2, 14)], fill=hexc("#e8e0c8"))
    return f

GEAR = {"helmets": (helm, ["bronze_cap", "iron_helm", "steel_helm", "dusk_helm"]), "body": (body, ["bronze_scale_vest", "iron_hauberk", "steel_brigandine", "dusk_cuirass"]),
        "legs": (legs, ["bronze_greaves", "iron_legguards", "steel_legplates", "dusk_tassets"]), "shields": (shield, ["alder_buckler", "iron_kite_shield", "steel_heater_shield", "dusk_tower_shield"]),
        "swords": (sword, ["bronze_sword", "iron_sword", "steel_sword", "dusk_sword"]), "axes": (axe, ["bronze_battleaxe", "iron_battleaxe", "steel_battleaxe", "dusk_battleaxe"]),
        "maces": (mace, ["bronze_mace", "iron_mace", "steel_mace", "dusk_mace"]), "archery": (bow, ["ash_shortbow", "alder_longbow", "blackthorn_warbow"])}
for line, (fn, ids) in GEAR.items():
    for t, i in enumerate(ids, 1):
        icon(i, fn(t))
for t, mtl in enumerate(["bronze", "iron", "steel", "dusk"], 1):
    icon(f"{mtl}_dagger", dagger(t))
    icon(f"{mtl}_warhammer", warhammer(t))
icon("bronze_arrows", arrows(1))
icon("iron_arrows", arrows(2))
icon("steel_arrows", arrows(3))

AWNING = {"helmets": "#3a6ac8", "body": "#8a8e96", "legs": "#4a8a5a", "shields": "#c8a03a", "swords": "#c84a3a", "axes": "#a85a2a", "maces": "#6a4a8a", "archery": "#3a8a3a"}
json.dump(_manifest, open(MANIFEST, "w"), indent=1, sort_keys=True)
print("M2 gear + shop art generated")

# ---- M2 enemies + combat drops ----
frames = []
for f in range(2):   # giant rat: a big brown rodent, 16x16, 2-frame scurry
    im = Image.new("RGBA", (16, 16), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.ellipse([1, 13, 14, 15], fill=(0, 0, 0, 70))
    d.ellipse([2, 6, 12, 14], fill=hexc("#6a5242"))
    d.ellipse([3, 7, 9, 10], fill=hexc("#8a705a"))
    d.ellipse([9, 6, 15, 12], fill=hexc("#7a604e"))
    d.point([(13, 8)], fill=hexc("#e84030")); d.point([(15, 10)], fill=hexc("#e8a0a0"))
    d.point([(10, 5), (11, 5)], fill=hexc("#c88a80"))
    d.line([(2, 11), (0, 8 + f), (1, 5 + 2 * f)], fill=hexc("#d89a8a"))
    d.point([(4, 14 - f), (7, 14), (10, 13 + f), (12, 14 - f)], fill=hexc("#3a2a1e"))
    frames.append(im)
out("actors", "giant_rat", strip(frames))

frames = []
for f in range(2):   # goblin: short green humanoid with a crude club, 16x24
    im = canvas(); d = ImageDraw.Draw(im); shadow(d)
    lo = f
    d.rectangle([5, 18, 6, 21 - lo], fill=hexc("#3a3020")); d.rectangle([9, 18, 10, 20 + lo], fill=hexc("#3a3020"))
    d.rectangle([4, 12, 11, 18], fill=hexc("#7a5a30")); d.line([(4, 16), (11, 16)], fill=hexc("#4a3418"))
    d.rectangle([3, 13, 3, 16 + lo], fill=hexc("#6a9a3a")); d.rectangle([12, 12, 12, 16 - lo], fill=hexc("#6a9a3a"))
    d.line([(13, 8 + lo), (13, 15 - lo)], fill=hexc("#8a6438"), width=2)          # club
    d.rectangle([4, 6, 11, 11], fill=hexc("#6a9a3a"))
    d.point([(2, 7), (3, 8), (13, 7), (12, 8)], fill=hexc("#6a9a3a"))           # ears
    d.point([(6, 8), (9, 8)], fill=hexc("#f0d020")); d.line([(6, 10), (9, 10)], fill=hexc("#2a3a1a"))
    frames.append(im)
out("actors", "goblin", strip(frames))

icon("bones", lambda d: (d.line([(3, 12), (12, 3)], fill=hexc("#e8e0c8"), width=2), d.line([(3, 3), (12, 12)], fill=hexc("#d8d0b8"), width=2),
                         d.point([(2, 11), (3, 13), (11, 2), (13, 3), (2, 3), (3, 2), (12, 13), (13, 11)], fill=hexc("#f8f0e0"))))
icon("raw_rat_meat", lambda d: (d.ellipse([3, 4, 13, 12], fill=hexc("#c85a5a")), d.ellipse([5, 6, 9, 9], fill=hexc("#e88a80")),
                                d.line([(11, 11), (14, 14)], fill=hexc("#e8e0c8"), width=2)))
icon("cooked_rat_meat", lambda d: (d.ellipse([3, 4, 13, 12], fill=hexc("#8a5a30")), d.ellipse([5, 6, 9, 9], fill=hexc("#b07a48")),
                                   d.line([(11, 11), (14, 14)], fill=hexc("#e8e0c8"), width=2)))
icon("burnt_meat", lambda d: (d.ellipse([3, 4, 13, 12], fill=hexc("#2a201a")), d.point([(6, 7), (9, 9)], fill=hexc("#4a3a2a")),
                              d.line([(11, 11), (14, 14)], fill=hexc("#a8a090"), width=2)))
json.dump(_manifest, open(MANIFEST, "w"), indent=1, sort_keys=True)
print("M2 enemy art generated")

# ---- M2 prayer buff icons (HUD countdown + Prayer panel), 16x16 ----
def prayer_icon(name, draw_fn, ring):
    im = Image.new("RGBA", (16, 16), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.ellipse([0, 0, 15, 15], fill=hexc("#2a2438"), outline=hexc(ring))
    draw_fn(d)
    out("ui", name, im)

prayer_icon("prayer_def", lambda d: (d.polygon([(4, 4), (11, 4), (11, 8), (7, 12), (4, 8)], fill=hexc("#8ab0e0")),
                                     d.line([(7, 5), (7, 10)], fill=hexc("#e8f0ff"))), "#8ab0e0")
prayer_icon("prayer_dmg", lambda d: (d.polygon([(8, 2), (11, 7), (10, 12), (6, 12), (5, 7)], fill=hexc("#e8702a")),
                                     d.polygon([(8, 6), (9, 9), (8, 11), (7, 9)], fill=hexc("#ffd070"))), "#e8702a")
prayer_icon("prayer_acc", lambda d: (d.ellipse([3, 5, 12, 10], fill=hexc("#e8e0c8")), d.ellipse([6, 5, 9, 10], fill=hexc("#3a8a5a")),
                                     d.point([(7, 7)], fill=hexc("#101010"))), "#3a8a5a")
prayer_icon("prayer_gather", lambda d: (d.polygon([(4, 11), (6, 5), (11, 3), (10, 9)], fill=hexc("#6ab04a")),
                                        d.line([(4, 12), (9, 5)], fill=hexc("#3a6a2a"))), "#6ab04a")

# --- 0.2.1: multi-combat zone indicator (two crossed swords on a red disc)
def _multi(d):
    blade, hilt = hexc("#e0e4ec"), hexc("#b08a3a")
    d.line([(3, 3), (11, 11)], fill=blade); d.line([(4, 3), (12, 11)], fill=blade)
    d.line([(12, 3), (4, 11)], fill=blade); d.line([(11, 3), (3, 11)], fill=blade)
    d.line([(9, 12), (12, 9)], fill=hilt); d.line([(4, 9), (7, 12)], fill=hilt)
    d.point([(12, 12), (3, 12)], fill=hexc("#6a4a1a"))
prayer_icon("multi_combat", _multi, "#c83a2a")
json.dump(_manifest, open(MANIFEST, "w"), indent=1, sort_keys=True)
print("M2 prayer icons generated")


# ---- 0.3.0 walk-in buildings: wall/floor tiles, roof, counter, props, signs, keepers ----
def bld_tile(kind, v):
    im = Image.new("RGBA", (T, T), (0, 0, 0, 255)); d = ImageDraw.Draw(im)
    rnd = random.Random(f"{kind}-{v}")
    if kind == "wall":            # wall seen from above (only visible with the roof cut away)
        d.rectangle([0, 0, 15, 15], fill=hexc("#4e463e"))
        for y0 in (0, 5, 10):
            off = 4 if (y0 // 5) % 2 else 0
            for x0 in range(-off, 16, 8):
                d.rectangle([x0 + 1, y0 + 1, x0 + 6, y0 + 3], fill=shade(hexc("#6a6056"), 0.92 + 0.08 * rnd.random()))
        d.line([(0, 15), (15, 15)], fill=hexc("#2e2822"))
    elif kind == "wall_front":    # the facade: plaster over a stone plinth; v1 window, v2 timber, v3 lantern
        d.rectangle([0, 0, 15, 15], fill=hexc("#cdbb98"))
        d.rectangle([0, 0, 15, 1], fill=hexc("#5a3b22"))           # top beam
        d.rectangle([0, 11, 15, 15], fill=hexc("#6a6056"))         # plinth
        for x0 in (0, 8):
            d.rectangle([x0 + 1, 12, x0 + 6, 14], fill=hexc("#7e746a"))
        for _ in range(4):
            d.point([(rnd.randrange(1, 15), rnd.randrange(3, 10))], fill=hexc("#bba886"))
        if v == 1:
            d.rectangle([4, 3, 11, 9], fill=hexc("#5a3b22")); d.rectangle([5, 4, 10, 8], fill=hexc("#f0d890"))
            d.line([(7, 4), (7, 8)], fill=hexc("#5a3b22")); d.line([(5, 6), (10, 6)], fill=hexc("#5a3b22"))
        elif v == 2:
            d.line([(0, 2), (12, 10)], fill=hexc("#5a3b22")); d.line([(1, 2), (13, 10)], fill=hexc("#5a3b22"))
        elif v == 3:
            d.rectangle([7, 4, 8, 4], fill=hexc("#2a2a2a")); d.rectangle([6, 5, 9, 8], fill=hexc("#f8c850")); d.point([(7, 6)], fill=hexc("#fff4c0"))
    elif kind == "floor":
        d.rectangle([0, 0, 15, 15], fill=hexc("#a07a4c"))
        for row in range(4):
            y0 = row * 4
            d.line([(0, y0 + 3), (15, y0 + 3)], fill=hexc("#7a5a34"))
            off = (row * 7 + v * 5) % 16
            d.line([(off, y0), (off, y0 + 2)], fill=hexc("#7a5a34"))
            d.point([((off + 5) % 16, y0 + 1)], fill=hexc("#b48c5a"))
    elif kind == "doorway":       # open door: dark threshold, door leaf swung in, frame posts
        d.rectangle([0, 0, 15, 15], fill=hexc("#a07a4c"))
        d.rectangle([0, 0, 2, 15], fill=hexc("#5a3b22")); d.rectangle([13, 0, 15, 15], fill=hexc("#5a3b22"))
        d.rectangle([3, 0, 12, 1], fill=hexc("#5a3b22"))
        d.rectangle([3, 12, 12, 15], fill=hexc("#7e746a"))
        d.rectangle([3, 2, 5, 11], fill=hexc("#7a4a26")); d.point([(5, 7)], fill=hexc("#e8c050"))
    return im

for kind in ["wall", "wall_front", "floor", "doorway"]:
    out("tiles", kind, strip([bld_tile(kind, v) for v in range(VARIANTS)]))

# roof: 3x3 nine-patch of 16px pieces, light neutral (the game tints it per town)
roof = Image.new("RGBA", (48, 48), (0, 0, 0, 0)); d = ImageDraw.Draw(roof)
light, mid, dark = hexc("#e8e0d0"), hexc("#c8beac"), hexc("#8a8070")
d.rectangle([0, 0, 47, 47], fill=mid)
for y0 in range(0, 48, 4):                      # shingle rows
    off = 4 if (y0 // 4) % 2 else 0
    d.line([(0, y0 + 3), (47, y0 + 3)], fill=dark)
    for x0 in range(off, 48, 8):
        d.line([(x0, y0), (x0, y0 + 2)], fill=dark)
        d.line([(x0 + 1, y0), (x0 + 5, y0)], fill=light)
d.rectangle([0, 22, 47, 25], fill=light); d.line([(0, 26), (47, 26)], fill=dark)   # ridge (middle row)
d.rectangle([0, 0, 47, 1], fill=dark)          # top edge
d.rectangle([0, 46, 47, 47], fill=hexc("#5a5246"))   # eave shadow
d.rectangle([0, 0, 1, 47], fill=dark); d.rectangle([46, 0, 47, 47], fill=dark)
out("buildings", "roof", roof)

def fobj(fn):
    im = canvas(); d = ImageDraw.Draw(im); fn(d); return im
WOOD, WOOD_D, WOOD_L = hexc("#7a5230"), hexc("#4e321c"), hexc("#a0743e")
def counter(d):
    d.rectangle([0, 10, 15, 21], fill=WOOD); d.rectangle([0, 8, 15, 11], fill=WOOD_L); d.line([(0, 8), (15, 8)], fill=hexc("#c49a5a"))
    d.line([(0, 21), (15, 21)], fill=WOOD_D); d.line([(0, 15), (15, 15)], fill=WOOD_D)
out("objects", "counter", fobj(counter))
def stand(d):
    shadow(d); d.rectangle([2, 12, 13, 20], fill=WOOD); d.rectangle([1, 10, 14, 12], fill=WOOD_L); d.line([(1, 10), (14, 10)], fill=hexc("#c49a5a"))
    d.rectangle([3, 14, 12, 19], fill=WOOD_D); d.rectangle([4, 15, 11, 18], fill=hexc("#5a2a2a"))   # cloth front
out("objects", "display_stand", fobj(stand))
def shelf(d):
    d.rectangle([1, 2, 14, 21], fill=WOOD_D); d.rectangle([2, 3, 13, 20], fill=hexc("#3a2614"))
    for y, cols in ((7, ["#c8a050", "#8a5a3a", "#5a7a9a"]), (12, ["#9a4a3a", "#d8c890", "#6a8a4a"]), (18, ["#7a6a5a", "#b88a4a", "#5a5a6a"])):
        d.line([(2, y), (13, y)], fill=WOOD_L)
        for i, c in enumerate(cols):
            d.rectangle([3 + i * 4, y - 3, 5 + i * 4, y - 1], fill=hexc(c))
out("objects", "shelf_goods", fobj(shelf))
def barrel(d):
    shadow(d); d.rectangle([3, 9, 12, 21], fill=WOOD); d.ellipse([3, 7, 12, 11], fill=WOOD_L); d.ellipse([5, 8, 10, 10], fill=WOOD_D)
    d.line([(3, 13), (12, 13)], fill=hexc("#5c5f66")); d.line([(3, 18), (12, 18)], fill=hexc("#5c5f66"))
out("objects", "barrel", fobj(barrel))
def crate(d):
    shadow(d); d.rectangle([2, 9, 13, 21], fill=WOOD_L); d.rectangle([2, 9, 13, 21], outline=WOOD_D)
    d.line([(2, 9), (13, 21)], fill=WOOD_D); d.line([(2, 15), (13, 15)], fill=WOOD_D)
out("objects", "crate", fobj(crate))
def sacks(d):
    shadow(d)
    for x0, y0 in ((1, 11), (7, 12), (4, 8)):
        d.ellipse([x0, y0, x0 + 7, y0 + 9], fill=hexc("#c8b080")); d.line([(x0 + 2, y0 + 1), (x0 + 5, y0 + 1)], fill=hexc("#8a7448"))
out("objects", "sacks", fobj(sacks))
def rack_base(d):
    shadow(d); d.rectangle([2, 4, 3, 21], fill=WOOD_D); d.rectangle([12, 4, 13, 21], fill=WOOD_D); d.rectangle([2, 19, 13, 20], fill=WOOD)
STEEL, STEEL_L = hexc("#9aa2ae"), hexc("#d0d8e0")
def weapon_rack(d):
    rack_base(d); d.line([(2, 7), (13, 7)], fill=WOOD)
    for x in (5, 8, 11):
        d.line([(x, 3), (x, 15)], fill=STEEL); d.point([(x, 3)], fill=STEEL_L); d.line([(x - 1, 15), (x + 1, 15)], fill=hexc("#8a6a3a")); d.line([(x, 16), (x, 18)], fill=WOOD_D)
out("objects", "weapon_rack", fobj(weapon_rack))
def axe_rack(d):
    rack_base(d); d.line([(2, 7), (13, 7)], fill=WOOD)
    for x in (5, 10):
        d.line([(x, 4), (x, 18)], fill=WOOD_L); d.polygon([(x + 1, 4), (x + 4, 3), (x + 4, 9), (x + 1, 8)], fill=STEEL)
out("objects", "axe_rack", fobj(axe_rack))
def bow_rack(d):
    rack_base(d)
    for x in (5, 9):
        d.arc([x - 3, 3, x + 3, 18], 270, 90, fill=WOOD_L); d.line([(x, 3), (x, 18)], fill=hexc("#e8e0c8"))
    d.rectangle([11, 10, 13, 18], fill=hexc("#6a4a2a")); d.point([(11, 9), (12, 8), (13, 9)], fill=hexc("#e8e8e8"))
out("objects", "bow_rack", fobj(bow_rack))
def shield_rack(d):
    rack_base(d)
    d.ellipse([3, 5, 9, 12], fill=hexc("#c8a03a")); d.point([(6, 8)], fill=STEEL_L)
    d.rectangle([8, 10, 13, 17], fill=hexc("#8a3a2a")); d.rectangle([8, 10, 13, 17], outline=STEEL); d.point([(10, 13)], fill=STEEL_L)
out("objects", "shield_rack", fobj(shield_rack))
def helm_stand(d):
    shadow(d); d.rectangle([7, 12, 8, 21], fill=WOOD_D); d.rectangle([4, 20, 11, 21], fill=WOOD)
    d.pieslice([3, 4, 12, 15], 180, 360, fill=STEEL); d.rectangle([3, 9, 12, 11], fill=STEEL); d.line([(4, 6), (8, 4)], fill=STEEL_L)
    d.line([(7, 2), (7, 5)], fill=hexc("#c84a3a"))
out("objects", "helm_stand", fobj(helm_stand))
def armour_stand(d):
    shadow(d); d.rectangle([7, 16, 8, 21], fill=WOOD_D); d.rectangle([4, 20, 11, 21], fill=WOOD)
    d.ellipse([6, 1, 9, 4], fill=WOOD_L)
    d.rectangle([3, 5, 12, 15], fill=STEEL); d.rectangle([3, 5, 12, 6], fill=STEEL_L)
    for y in (8, 11, 14):
        d.line([(3, y), (12, y)], fill=hexc("#6e7680"))
out("objects", "armour_stand", fobj(armour_stand))
# 0.3.0 blacksmith forge props
def bellows(d):
    shadow(d)
    d.polygon([(2, 12), (11, 9), (11, 20), (2, 18)], fill=hexc("#7a4a2a"))             # leather body
    d.line([(2, 12), (11, 9)], fill=WOOD_L); d.line([(2, 18), (11, 20)], fill=WOOD_D)
    for x in (5, 8):
        d.line([(x, 11), (x, 19)], fill=hexc("#5a341c"))                               # folds
    d.rectangle([11, 13, 14, 15], fill=hexc("#5c5f66")); d.point([(14, 14)], fill=hexc("#2a2a2a"))   # nozzle
    d.line([(1, 9), (3, 12)], fill=WOOD_D)                                                # handle
out("objects", "bellows", fobj(bellows))
def quench_barrel(d):
    barrel(d)
    d.ellipse([5, 8, 10, 10], fill=hexc("#3a5a7a")); d.point([(6, 8)], fill=hexc("#8ab0d0"))   # water
    d.point([(5, 5), (8, 3), (10, 5)], fill=hexc("#d8dce0"))                                # steam
out("objects", "quench_barrel", fobj(quench_barrel))
def coal_crate(d):
    crate(d)
    for x, y in ((4, 8), (7, 7), (10, 8), (5, 6), (9, 6)):
        d.ellipse([x - 1, y - 1, x + 1, y + 1], fill=hexc("#2a2a2e"))
    d.point([(7, 6)], fill=hexc("#e07030"))
out("objects", "coal_crate", fobj(coal_crate))

# signs: hanging board + the shop's icon (16x16). Icons come from the item art.
def item_png(i):
    return Image.open(os.path.join(SPR, "items", i + ".png")).convert("RGBA")
def board(col):
    im = Image.new("RGBA", (16, 16), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.line([(4, 0), (4, 2)], fill=hexc("#2a2a2a")); d.line([(11, 0), (11, 2)], fill=hexc("#2a2a2a"))
    d.rectangle([1, 2, 14, 15], fill=hexc(col)); d.rectangle([1, 2, 14, 15], outline=hexc("#3a2614"))
    d.rectangle([2, 3, 13, 14], outline=shade(hexc(col), 1.25))
    return im
SIGN_ICON = {"helmets": "iron_helm", "body": "iron_platebody", "legs": "iron_platelegs", "shields": "iron_kiteshield", "swords": "iron_sword",
             "axes": "iron_battleaxe", "maces": "iron_mace", "archery": "oak_shortbow", "general": "bronze_hatchet"}
_shop = json.load(open(os.path.join(ROOT, "data", "shop.json")))
for line, ids in _shop.get("lines", {}).items():
    if line in SIGN_ICON:
        cand = [i for i in ids if i.startswith("iron_")] or ids
        SIGN_ICON[line] = cand[0]
for sh, ic in SIGN_ICON.items():
    im = board(AWNING.get(sh, "#8a6a3a"))
    p = os.path.join(SPR, "items", ic + ".png")
    if os.path.exists(p):
        im.alpha_composite(item_png(ic).resize((10, 10), Image.NEAREST), (3, 4))
    out("buildings", "sign_" + sh, im)
im = board("#b03a2a"); d = ImageDraw.Draw(im)          # for sale: a key
d.ellipse([3, 5, 7, 9], outline=hexc("#f0d060")); d.line([(7, 7), (12, 7)], fill=hexc("#f0d060")); d.point([(11, 8), (12, 9), (10, 8)], fill=hexc("#f0d060"))
d.line([(3, 12), (12, 12)], fill=hexc("#f0e0c0"))
out("buildings", "sign_forsale", im)
im = board("#4a4a52"); d = ImageDraw.Draw(im)          # blacksmith: anvil + spark
d.rectangle([3, 7, 12, 8], fill=hexc("#c8ccd4")); d.polygon([(12, 7), (14, 7), (12, 9)], fill=hexc("#c8ccd4"))
d.rectangle([6, 9, 9, 11], fill=hexc("#9aa2ae")); d.rectangle([4, 12, 11, 13], fill=hexc("#9aa2ae"))
d.point([(5, 4), (7, 3), (9, 5)], fill=hexc("#f0a030")); d.point([(8, 5)], fill=hexc("#fff0a0"))
out("buildings", "sign_smithy", im)
im = board("#3a7a4a"); d = ImageDraw.Draw(im)          # yours: coin stack + star
for i, y in enumerate((11, 9, 7)):
    d.ellipse([3, y, 9, y + 3], fill=hexc("#e8c050")); d.line([(4, y + 1), (8, y + 1)], fill=hexc("#fff0a0"))
d.polygon([(11, 4), (12, 7), (14, 7), (12, 9), (13, 12), (11, 10), (9, 12), (10, 9), (8, 7), (10, 7)], fill=hexc("#f8f0d0"))
out("buildings", "sign_player", im)

# shopkeepers: 4-frame idle (stand, breathe, stand, blink), 3/4 view facing RIGHT,
# never mirror images of each other (ART_GUIDE 0.2.5). Distinct per shop:
# apron colour from the shop, hair, and a hat/hood/headband per trade.
KEEPERS = {
    "general": ("#5f9a46", "#6b3f22", "cap"),   "helmets": ("#3a6ac8", "#c8c0b0", "helm"),
    "body": ("#8a8e96", "#3a2a1a", "bald"),     "legs": ("#4a8a5a", "#b05a2a", "bun"),
    "shields": ("#c8a03a", "#2a2a2a", "beard"), "swords": ("#c84a3a", "#e0d090", "band"),
    "axes": ("#a85a2a", "#5a3a1a", "beard"),    "maces": ("#6a4a8a", "#8a8a8a", "bun"),
    "archery": ("#3a8a3a", "#8a5a2a", "hood"),  "estate": ("#2a2a3a", "#4a3a2a", "tophat"),
    "player": ("#3a7a4a", "#d8a040", "cap"),
}
def keeper(name, apron, hair, style):
    frames = []
    skin = hexc("#e2b896")
    for f in range(4):
        im = canvas(); d = ImageDraw.Draw(im); shadow(d)
        up = 1 if f == 1 else 0                      # breathe: chest rises a pixel
        d.rectangle([5, 17, 6, 21], fill=hexc("#3a3a48")); d.rectangle([9, 17, 10, 21], fill=hexc("#3a3a48"))
        d.rectangle([4, 10 - up, 11, 17], fill=hexc("#e8e0d0"))              # shirt
        d.rectangle([5, 12 - up, 11, 17], fill=hexc(apron))                    # apron
        d.line([(5, 12 - up), (11, 12 - up)], fill=shade(hexc(apron), 1.3))
        d.rectangle([3, 11, 3, 14], fill=shade(skin, 0.85)); d.rectangle([12, 11, 12, 15], fill=skin)
        d.rectangle([5, 4, 10, 9], fill=skin); d.point([(11, 7)], fill=skin)
        d.rectangle([5, 3, 10, 4], fill=hexc(hair)); d.rectangle([4, 4, 5, 7], fill=hexc(hair))
        if f == 3:
            d.line([(8, 6), (10, 6)], fill=shade(skin, 0.7))               # blink
        else:
            d.point([(8, 6), (10, 6)], fill=hexc("#22201c"))
        if style == "cap":
            d.rectangle([4, 2, 10, 3], fill=hexc(apron)); d.line([(10, 3), (12, 3)], fill=shade(hexc(apron), 0.7))
        elif style == "helm":
            d.rectangle([4, 1, 10, 4], fill=hexc("#9aa2ae")); d.line([(5, 1), (9, 1)], fill=hexc("#d0d8e0"))
        elif style == "bald":
            d.rectangle([5, 3, 10, 3], fill=skin); d.rectangle([4, 5, 5, 7], fill=hexc(hair))
        elif style == "bun":
            d.ellipse([2, 2, 5, 5], fill=hexc(hair))
        elif style == "beard":
            d.rectangle([7, 8, 11, 10], fill=hexc(hair))
        elif style == "band":
            d.line([(5, 4), (10, 4)], fill=hexc("#f0e0c0"))
        elif style == "hood":
            d.rectangle([4, 2, 10, 3], fill=shade(hexc(apron), 0.7)); d.rectangle([3, 3, 5, 9], fill=shade(hexc(apron), 0.7))
        elif style == "tophat":
            d.rectangle([5, 0, 9, 3], fill=hexc("#1a1a1a")); d.line([(4, 3), (11, 3)], fill=hexc("#1a1a1a")); d.line([(5, 2), (9, 2)], fill=hexc("#8a2a2a"))
        frames.append(im)
    out("actors", "keeper_" + name, strip(frames))
for k, (ap, hr, st) in KEEPERS.items():
    keeper(k, ap, hr, st)

for gone in ["objects/store_stall.png"] + ["objects/shop_%s.png" % l for l in AWNING]:
    gp = os.path.join(SPR, gone)
    if os.path.exists(gp) and _manifest.get(gone) == _sha(gp):
        os.remove(gp); _manifest.pop(gone, None)
        for ext in (".import",):
            if os.path.exists(gp + ext):
                os.remove(gp + ext)
json.dump(_manifest, open(MANIFEST, "w"), indent=1, sort_keys=True)
print("0.3.0 building art generated")
