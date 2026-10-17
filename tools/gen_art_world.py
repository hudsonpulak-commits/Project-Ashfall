#!/usr/bin/env python3
"""0.3.1 world-track placeholder pixel art (the Scorch, bridges, new creatures,
town guards and citizens, their drops). Same rules as tools/gen_art.py: original
procedural art, never overwrites a PNG you replaced (sha manifest in
assets/sprites/placeholders.json; --force overwrites).

Usage: python3 tools/gen_art_world.py   (from the project root)
"""
import os, sys, json, hashlib, random
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPR = os.path.join(ROOT, "assets", "sprites")
MANIFEST = os.path.join(SPR, "placeholders.json")
FORCE = "--force" in sys.argv
_manifest = json.load(open(MANIFEST)) if os.path.exists(MANIFEST) else {}

def _sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()

def out(category, name, im):
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

def strip(frames):
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

def canvas(w=16, h=24):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))

def shadow(d, y=21, x0=3, x1=12):
    d.ellipse([x0, y, x1, y + 2], fill=(0, 0, 0, 70))

T = 16
# ------------------------------------------------------------ tiles --------
ASH = "#3a3430"
def ash_tile(v, edge=False):
    rnd = random.Random(f"ash-{edge}-{v}")
    b = hexc(ASH)
    im = Image.new("RGBA", (T, T), b); px = im.load(); d = ImageDraw.Draw(im)
    for y in range(T):
        for x in range(T):
            r = rnd.random()
            if r < 0.20: px[x, y] = shade(b, 0.82)
            elif r < 0.30: px[x, y] = shade(b, 1.18)
    for _ in range(2):                                   # grey ash flecks
        x, y = rnd.randrange(1, 15), rnd.randrange(1, 15)
        d.point([(x, y), (x + 1, y)], fill=hexc("#6a625a"))
    if v % 2 == 1:                                       # a crack
        x, y = rnd.randrange(2, 9), rnd.randrange(3, 13)
        d.line([(x, y), (x + 3, y + 1), (x + 5, y)], fill=hexc("#1c1816"))
    if edge:                                             # the border: glowing seams + embers
        d.line([(0, 7 + (v % 3)), (5, 8), (10, 6 + (v % 2)), (15, 8)], fill=hexc("#8a2a14"))
        d.line([(1, 8 + (v % 3)), (6, 9), (11, 7 + (v % 2))], fill=hexc("#e0602a"))
        for _ in range(3):
            x, y = rnd.randrange(0, 16), rnd.randrange(0, 16)
            d.point([(x, y)], fill=hexc("#ffb040" if rnd.random() < 0.5 else "#e8501e"))
    elif v == 3:
        d.point([(rnd.randrange(2, 14), rnd.randrange(2, 14))], fill=hexc("#c84a1e"))
    return im

def bridge_tile(v):
    rnd = random.Random(f"bridge-{v}")
    im = Image.new("RGBA", (T, T), hexc("#2e6a8c")); d = ImageDraw.Draw(im)
    d.rectangle([1, 0, 14, 15], fill=hexc("#8a6438"))   # deck over the water
    for x in range(1, 15, 3):                           # boards run across, gaps between
        d.line([(x + 2, 0), (x + 2, 15)], fill=hexc("#5e4225"))
        d.point([(x + 1, rnd.randrange(1, 15))], fill=hexc("#a8784a"))
    d.line([(1, 0), (1, 15)], fill=hexc("#4a3018"))      # side beams / rails
    d.line([(14, 0), (14, 15)], fill=hexc("#4a3018"))
    if v % 2 == 0:
        d.rectangle([0, 6, 1, 8], fill=hexc("#3a2612")); d.rectangle([14, 6, 15, 8], fill=hexc("#3a2612"))  # posts
    return im

out("tiles", "ash", strip([ash_tile(v) for v in range(4)]))
out("tiles", "ash_edge", strip([ash_tile(v, True) for v in range(4)]))
out("tiles", "bridge", strip([bridge_tile(v) for v in range(4)]))

# ---------------------------------------------------------- objects --------
im = canvas(); d = ImageDraw.Draw(im); shadow(d)
d.rectangle([7, 8, 8, 21], fill=hexc("#1e1a18")); d.point([(6, 21), (9, 21)], fill=hexc("#1e1a18"))
for (a, b) in [((7, 12), (3, 7)), ((3, 7), (2, 4)), ((8, 10), (12, 5)), ((12, 5), (13, 2)), ((7, 8), (6, 2)), ((8, 15), (11, 12))]:
    d.line([a, b], fill=hexc("#2a2420"))
d.point([(7, 14), (8, 18)], fill=hexc("#e0602a")); d.point([(3, 7)], fill=hexc("#4a403a"))
out("objects", "burnt_tree", im)

im = canvas(); d = ImageDraw.Draw(im); shadow(d)
d.ellipse([4, 15, 11, 21], fill=hexc("#1e1a18")); d.ellipse([5, 15, 10, 18], fill=hexc("#3a302a"))
d.point([(7, 16)], fill=hexc("#e0602a")); d.point([(8, 17)], fill=hexc("#8a2a14"))
out("objects", "charred_stump", im)

fr = []
for f in range(2):
    im = canvas(); d = ImageDraw.Draw(im)
    pts = [(4, 19), (9, 20), (12, 18), (6, 21)] if f == 0 else [(5, 20), (10, 19), (11, 21), (7, 18)]
    for i, (x, y) in enumerate(pts):
        d.point([(x, y)], fill=hexc(["#ffb040", "#e8501e", "#ffd070", "#c83a14"][(i + f) % 4]))
    d.point([(8, 14 - f * 2)], fill=hexc("#e8501e", 200))   # a rising spark
    fr.append(im)
out("objects", "embers", strip(fr))

# ----------------------------------------------------------- actors --------
fr = []
for f in range(2):   # chicken: 16x16, white hen, red comb, faces right
    im = canvas(16, 16); d = ImageDraw.Draw(im)
    d.ellipse([3, 13, 12, 15], fill=(0, 0, 0, 60))
    d.ellipse([3, 7, 11, 13], fill=hexc("#f0ece0"))
    d.polygon([(3, 8), (1, 6), (3, 10)], fill=hexc("#d8d0c0"))                  # tail
    d.ellipse([8, 4 + f, 12, 8 + f], fill=hexc("#f8f4ec"))                       # head bobs
    d.point([(10, 3 + f), (11, 3 + f)], fill=hexc("#d83a2a"))                    # comb
    d.point([(13, 6 + f)], fill=hexc("#e8a020")); d.point([(11, 5 + f)], fill=hexc("#1a1a1a"))
    d.point([(11, 8 + f)], fill=hexc("#d83a2a"))                                 # wattle
    d.line([(6, 11), (8, 11)], fill=hexc("#c8c0b0"))                             # wing
    d.line([(6, 13), (6, 14 + (f == 0))], fill=hexc("#e8a020")); d.line([(9, 13), (9, 14 + (f == 1))], fill=hexc("#e8a020"))
    fr.append(im)
out("actors", "chicken", strip(fr))

fr = []
for f in range(2):   # wolf: 24x16, grey, low and long, faces right
    im = canvas(24, 16); d = ImageDraw.Draw(im)
    d.ellipse([3, 13, 21, 15], fill=(0, 0, 0, 70))
    d.ellipse([4, 6, 17, 12], fill=hexc("#6e6a66"))
    d.ellipse([6, 9, 15, 12], fill=hexc("#8e8a84"))                              # belly
    d.polygon([(4, 8), (0, 5 + f), (1, 8), (4, 10)], fill=hexc("#5a5652"))       # tail
    d.polygon([(15, 5), (21, 6), (23, 8), (20, 10), (16, 10)], fill=hexc("#7a7672"))  # head + snout
    d.polygon([(16, 5), (17, 2), (18, 5)], fill=hexc("#5a5652"))                 # ear
    d.point([(19, 7)], fill=hexc("#f0c040")); d.point([(23, 8)], fill=hexc("#1a1a1a"))
    legs = [(6, 12, 15 - f), (9, 12, 14 + f), (13, 12, 15 - f), (16, 11, 14 + f)]
    for x, y0, y1 in legs:
        d.line([(x, y0), (x, y1)], fill=hexc("#4e4a46"))
    fr.append(im)
out("actors", "wolf", strip(fr))

def humanoid(name, draw_extra, tunic, legs="#3a3a48", hair="#40403c", skin="#e2b896", tint=False):
    frames = []
    sk = hexc(skin)
    for f in range(2):
        im = canvas(); d = ImageDraw.Draw(im); shadow(d)
        d.rectangle([5, 17, 6, 21 - (f == 1)], fill=shade(hexc(legs), 0.8))
        d.rectangle([9, 17, 10, 21 - (f == 0)], fill=hexc(legs))
        d.rectangle([4, 10, 11, 17], fill=hexc(tunic))
        d.line([(4, 15), (11, 15)], fill=shade(hexc(tunic), 0.7))
        d.rectangle([3, 11, 3, 14], fill=shade(sk, 0.85))
        d.rectangle([12, 11, 12, 15 - f], fill=sk)
        d.rectangle([5, 4, 10, 9], fill=sk); d.point([(11, 7)], fill=sk)
        d.rectangle([5, 3, 10, 4], fill=hexc(hair)); d.rectangle([4, 4, 5, 7], fill=hexc(hair))
        d.point([(8, 6), (10, 6)], fill=hexc("#22201c"))
        draw_extra(d, f)
        frames.append(im)
    out("actors", name, strip(frames))

def guard_extra(d, f):
    d.rectangle([4, 2, 10, 5], fill=hexc("#8a8e96")); d.line([(5, 2), (9, 2)], fill=hexc("#c8ccd4"))   # iron helm
    d.line([(10, 5), (10, 8)], fill=hexc("#6a6e76"))                                                   # nose guard
    d.rectangle([4, 10, 11, 13], fill=hexc("#8a8e96"))                                                 # mail shoulders
    d.line([(13, 0 + f), (13, 18)], fill=hexc("#7a4e24"))                                              # spear
    d.polygon([(12, 1 + f), (13, -2 + f), (14, 1 + f)], fill=hexc("#c8ccd4"))
    d.rectangle([1, 11, 4, 17], fill=hexc("#2c4c8a")); d.line([(2, 13), (3, 13)], fill=hexc("#e8c050"))  # town shield
humanoid("town_guard", guard_extra, "#2c4c8a", legs="#3a3a48", hair="#5a3b22")

def citizen_extra(d, f):
    d.line([(4, 13), (11, 13)], fill=hexc("#c8c0b0"))                                                  # belt (tint shows on the rest)
humanoid("citizen", citizen_extra, "#f0ece4", legs="#8a8a84", hair="#6b3f22")

def brute_extra(d, f):
    d.rectangle([3, 9, 12, 17], fill=hexc("#5a2a22"))                                                  # bulky ember-scarred body
    for (x, y) in [(5, 11), (9, 13), (7, 16), (11, 10)]:
        d.point([(x, y)], fill=hexc("#e8501e"))
    d.rectangle([5, 3, 10, 9], fill=hexc("#4a2a24")); d.point([(8, 6), (10, 6)], fill=hexc("#ffb040"))  # ember eyes
    d.polygon([(4, 3), (3, 0), (6, 3)], fill=hexc("#2a1a16")); d.polygon([(10, 3), (12, 0), (11, 3)], fill=hexc("#2a1a16"))  # horns
    d.line([(13, 6 + f), (14, 17)], fill=hexc("#3a3430"), width=2)                                     # charred club
    d.rectangle([12, 4 + f, 15, 7 + f], fill=hexc("#2a2420"))
humanoid("cinder_brute", brute_extra, "#5a2a22", legs="#2a1a16", hair="#2a1a16", skin="#6a3a2a")

# ------------------------------------------------------------ items --------
def icon(name, fn):
    im = Image.new("RGBA", (16, 16), (0, 0, 0, 0)); d = ImageDraw.Draw(im); fn(d); out("items", name, im)

icon("feather", lambda d: (d.polygon([(3, 13), (6, 6), (11, 2), (12, 4), (9, 10)], fill=hexc("#f0ece0")),
                           d.line([(3, 14), (11, 3)], fill=hexc("#b0a890")), d.point([(7, 7), (9, 6)], fill=hexc("#d0c8b8"))))
icon("raw_chicken", lambda d: (d.ellipse([3, 5, 12, 13], fill=hexc("#e8b0a0")), d.ellipse([5, 6, 9, 9], fill=hexc("#f8d0c0")),
                               d.line([(11, 6), (14, 3)], fill=hexc("#f0e8d8"), width=2)))
icon("cooked_chicken", lambda d: (d.ellipse([3, 5, 12, 13], fill=hexc("#b8783a")), d.ellipse([5, 6, 9, 9], fill=hexc("#d8a060")),
                                  d.line([(11, 6), (14, 3)], fill=hexc("#f0e8d8"), width=2)))
icon("wolf_pelt", lambda d: (d.polygon([(2, 5), (5, 3), (11, 3), (14, 5), (13, 12), (10, 13), (6, 13), (3, 12)], fill=hexc("#7a7672")),
                             d.polygon([(5, 6), (11, 6), (10, 11), (6, 11)], fill=hexc("#9a968e")), d.point([(2, 4), (14, 4)], fill=hexc("#5a5652"))))

# ------------------------------------------------------ 0.3.1 church -------
STONE = "#9a9a9e"
def stone_blocks(im, rnd, base, rows=((0, 4), (4, 8), (8, 12), (12, 16)), mortar="#6e6e74"):
    d = ImageDraw.Draw(im); b = hexc(base)
    for i, (y0, y1) in enumerate(rows):
        off = 0 if i % 2 == 0 else 4
        for x0 in range(-off, 16, 8):
            c = shade(b, 0.9 + rnd.random() * 0.2)
            d.rectangle([max(0, x0), y0, min(15, x0 + 7), y1 - 1], fill=c)
            d.line([(max(0, x0), y0), (min(15, x0 + 6), y0)], fill=shade(c, 1.12))
        d.line([(0, y1 - 1), (15, y1 - 1)], fill=hexc(mortar))
        for x0 in range(-off, 16, 8):
            if 0 <= x0 + 7 <= 15:
                d.line([(x0 + 7, y0), (x0 + 7, y1 - 1)], fill=hexc(mortar))

def stone_wall(v):        # the wall top seen from above: pale dressed stone
    rnd = random.Random(f"stone-wall-{v}")
    im = Image.new("RGBA", (T, T), hexc("#7e7e84")); stone_blocks(im, rnd, "#8c8c92")
    return im

def stone_front(v):       # the facade: grey ashlar, a plinth, now and then a lancet slit
    rnd = random.Random(f"stone-front-{v}")
    im = Image.new("RGBA", (T, T), hexc("#8a8a90")); stone_blocks(im, rnd, STONE, rows=((0, 5), (5, 10), (10, 14)))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 14, 15, 15], fill=hexc("#5e5e64"))
    if v == 2:
        d.rectangle([7, 3, 8, 10], fill=hexc("#2a3450")); d.point([(7, 2), (8, 2)], fill=hexc("#5a5a60"))
    return im

def stone_floor(v):       # flagstones, cool grey
    rnd = random.Random(f"stone-floor-{v}")
    im = Image.new("RGBA", (T, T), hexc("#a4a2a0")); d = ImageDraw.Draw(im)
    for (x0, y0, x1, y1) in [(0, 0, 7, 6), (8, 0, 15, 8), (0, 7, 9, 15), (10, 9, 15, 15)]:
        c = shade(hexc("#b0aeaa"), 0.88 + rnd.random() * 0.18)
        d.rectangle([x0, y0, x1 - 1, y1 - 1], fill=c)
        d.line([(x0, y0), (x1 - 1, y0)], fill=shade(c, 1.1))
    if v == 1:
        d.point([(rnd.randrange(1, 14), rnd.randrange(1, 14))], fill=hexc("#8a8884"))
    return im

out("tiles", "stone_wall", strip([stone_wall(v) for v in range(4)]))
out("tiles", "stone_front", strip([stone_front(v) for v in range(4)]))
out("tiles", "stone_floor", strip([stone_floor(v) for v in range(4)]))

# altar: stone block, white cloth with a red runner, a gold cross, two candles
im = canvas(); d = ImageDraw.Draw(im); shadow(d, 21, 1, 14)
d.rectangle([1, 13, 14, 21], fill=hexc("#8a8a90")); d.line([(1, 13), (14, 13)], fill=hexc("#b4b4ba"))
d.rectangle([1, 12, 14, 16], fill=hexc("#f2efe6")); d.rectangle([6, 12, 9, 19], fill=hexc("#a8282a"))
d.line([(6, 19), (9, 19)], fill=hexc("#e8c050"))
d.rectangle([7, 3, 8, 11], fill=hexc("#e8c050")); d.rectangle([5, 5, 10, 6], fill=hexc("#e8c050")); d.point([(7, 3)], fill=hexc("#fff0a0"))
for x in (2, 13):
    d.rectangle([x, 8, x, 11], fill=hexc("#f4f0e0")); d.point([(x, 7)], fill=hexc("#ffc040"))
out("objects", "altar", im)

# pew: dark oak bench with a back, seen from the front
im = canvas(); d = ImageDraw.Draw(im); shadow(d, 21, 0, 15)
d.rectangle([0, 9, 15, 13], fill=hexc("#5a3a20")); d.line([(0, 9), (15, 9)], fill=hexc("#7a5230"))
d.rectangle([0, 15, 15, 17], fill=hexc("#6a4628")); d.line([(0, 15), (15, 15)], fill=hexc("#8a6038"))
for x in (0, 15):
    d.rectangle([x, 9, x, 21], fill=hexc("#3e2814"))
d.line([(2, 11), (13, 11)], fill=hexc("#4a3018"))
out("objects", "pew", im)

# candle stand: iron stand, three candles, flickering flames (2 frames)
fr = []
for f in range(2):
    im = canvas(); d = ImageDraw.Draw(im); shadow(d, 21, 5, 10)
    d.line([(7, 10), (7, 20)], fill=hexc("#3a3a40")); d.line([(5, 21), (10, 21)], fill=hexc("#3a3a40"))
    d.line([(4, 11), (11, 11)], fill=hexc("#4a4a50"))
    for i, x in enumerate((4, 7, 11)):
        h = 3 if i != 1 else 4
        d.rectangle([x, 11 - h, x, 10], fill=hexc("#f4f0e0"))
        fy = 11 - h - 1
        d.point([(x, fy - ((f + i) % 2))], fill=hexc("#ffd070")); d.point([(x, fy)], fill=hexc("#ff9a30"))
    d.point([(7, 4 + f)], fill=hexc("#ffe0a0", 120))
    fr.append(im)
out("objects", "candle_stand", strip(fr))

# stained-glass window in a stone wall (16x16, drawn over the wall tile)
im = Image.new("RGBA", (16, 16), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
d.rectangle([4, 2, 11, 15], fill=hexc("#4a4a50")); d.ellipse([4, 0, 11, 6], fill=hexc("#4a4a50"))
panes = ["#c83a3a", "#3a6ac8", "#e8c050", "#3aa86a"]
for y in range(2, 14, 3):
    for x in range(5, 11, 3):
        d.rectangle([x, y, x + 1, y + 1], fill=hexc(panes[(x + y) % 4]))
d.ellipse([6, 1, 9, 4], fill=hexc("#e8c050")); d.line([(7, 2), (8, 3)], fill=hexc("#c83a3a"))
d.line([(4, 15), (11, 15)], fill=hexc("#6e6e74"))
out("objects", "stained_glass", im)

# priest: black cassock, white collar, a stole; 4 idle frames like the keepers
fr = []
sk = hexc("#e2b896")
for f in range(4):
    im = canvas(); d = ImageDraw.Draw(im); shadow(d)
    bob = 1 if f in (1, 2) else 0
    d.polygon([(4, 10 + bob), (11, 10 + bob), (12, 21), (3, 21)], fill=hexc("#22222a"))
    d.line([(7, 11 + bob), (7, 20)], fill=hexc("#34343e"))
    d.rectangle([5, 10 + bob, 10, 10 + bob], fill=hexc("#f4f4f0"))
    d.line([(5, 11 + bob), (5, 17)], fill=hexc("#a8282a")); d.line([(10, 11 + bob), (10, 17)], fill=hexc("#a8282a"))
    d.rectangle([3, 12 + bob, 3, 15 + bob], fill=sk); d.rectangle([12, 12 + bob, 12, 15 + bob], fill=sk)
    d.rectangle([5, 4 + bob, 10, 9 + bob], fill=sk); d.point([(11, 7 + bob)], fill=sk)
    d.rectangle([5, 3 + bob, 10, 4 + bob], fill=hexc("#9a9a96")); d.rectangle([4, 4 + bob, 5, 6 + bob], fill=hexc("#9a9a96"))
    d.point([(8, 6 + bob), (10, 6 + bob)], fill=hexc("#22201c"))
    if f == 3:
        d.point([(8, 6 + bob), (10, 6 + bob)], fill=sk)   # blink
    fr.append(im)
out("actors", "priest", strip(fr))

# church sign: a wooden board with a gold cross
im = Image.new("RGBA", (16, 16), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
d.line([(2, 1), (13, 1)], fill=hexc("#3a2a1a")); d.line([(4, 1), (4, 3)], fill=hexc("#3a2a1a")); d.line([(11, 1), (11, 3)], fill=hexc("#3a2a1a"))
d.rectangle([2, 3, 13, 14], fill=hexc("#5a3a20")); d.rectangle([3, 4, 12, 13], fill=hexc("#2a3450"))
d.rectangle([7, 5, 8, 12], fill=hexc("#e8c050")); d.rectangle([5, 7, 10, 8], fill=hexc("#e8c050"))
out("buildings", "sign_church", im)
# ---------------------------------------------------------------- ui -------
im = Image.new("RGBA", (16, 16), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
d.ellipse([3, 1, 12, 10], fill=hexc("#e8e0d0")); d.rectangle([5, 9, 10, 12], fill=hexc("#e8e0d0"))
d.rectangle([5, 5, 6, 7], fill=hexc("#1a1a1a")); d.rectangle([9, 5, 10, 7], fill=hexc("#1a1a1a")); d.point([(7, 8), (8, 8)], fill=hexc("#5a5048"))
d.line([(6, 12), (6, 13)], fill=hexc("#5a5048")); d.line([(8, 12), (8, 13)], fill=hexc("#5a5048"))
d.line([(1, 14), (14, 11)], fill=hexc("#c83a2a")); d.line([(1, 11), (14, 14)], fill=hexc("#c83a2a"))
out("ui", "pk_skull", im)

json.dump(_manifest, open(MANIFEST, "w"), indent=1, sort_keys=True)
print("0.3.1 world art generated")
