#!/usr/bin/env python3
"""0.3.1 villages/farms placeholder pixel art: wheat (+ stubble), the quern,
the well, fences, cows, the villager keeper, the cottage sign and the farm
items. Same rules as tools/gen_art.py: original procedural art; never
overwrites a PNG you replaced (sha manifest assets/sprites/placeholders.json;
--force overwrites).

Usage: python3 tools/gen_art_farm.py   (from the project root)
"""
import os as _o, sys as _s; _s.path.insert(0, _o.path.join(_o.path.dirname(_o.path.abspath(__file__)), "art")); import art_guard  # noqa: E402,F401  0.3.9.2: never overwrite hand-drawn art
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

# ------------------------------------------------------------ objects ------
# wheat: a clump of golden stalks with heavy ears (16x24, bottom-anchored)
im = canvas(); d = ImageDraw.Draw(im); rnd = random.Random("wheat")
for i, x in enumerate([2, 4, 6, 8, 10, 12, 14, 5, 9, 13, 3, 11]):
    top = 6 + rnd.randrange(0, 5) + (i // 7) * 3
    stalk = hexc("#b89a3a") if i % 2 else hexc("#c8aa48")
    d.line([(x, top + 4), (x + (1 if i % 3 == 0 else 0), 23)], fill=stalk)
    ear = hexc("#e8c860") if i % 2 else hexc("#f0d478")
    d.rectangle([x, top, x, top + 4], fill=ear)
    d.point([(x - 1, top + 1), (x + 1, top + 2), (x - 1, top + 3)], fill=shade(ear, 0.85))
    d.point([(x, top - 1)], fill=hexc("#f8e8a8"))
d.line([(1, 23), (15, 23)], fill=hexc("#8a6a2a"))
out("objects", "wheat", im)

# stubble: cut stalks on tilled earth
im = canvas(); d = ImageDraw.Draw(im); rnd = random.Random("stubble")
for x in range(1, 16, 2):
    h = rnd.randrange(2, 4)
    d.line([(x, 23 - h), (x, 23)], fill=hexc("#a8904a"))
    d.point([(x, 23 - h)], fill=hexc("#c8b070"))
d.point([(4, 21), (11, 22)], fill=hexc("#e0c870"))   # a dropped ear or two
out("objects", "wheat_stubble", im)

# quern: two round millstones on a low wooden stand, a peg handle
im = canvas(); d = ImageDraw.Draw(im); shadow(d, 21, 1, 14)
d.rectangle([2, 17, 13, 21], fill=hexc("#6a4628")); d.line([(2, 17), (13, 17)], fill=hexc("#8a6038"))
d.line([(3, 21), (3, 22)], fill=hexc("#4a3018")); d.line([(12, 21), (12, 22)], fill=hexc("#4a3018"))
d.ellipse([2, 12, 13, 18], fill=hexc("#8a8a8e")); d.ellipse([2, 11, 13, 16], fill=hexc("#a4a4a8"))
d.ellipse([3, 8, 12, 13], fill=hexc("#9a9aa0")); d.ellipse([3, 7, 12, 12], fill=hexc("#b8b8bc"))
d.ellipse([6, 8, 9, 10], fill=hexc("#5a5a60"))                # feed hole
d.line([(11, 4), (11, 9)], fill=hexc("#7a5230")); d.point([(11, 3)], fill=hexc("#9a7040"))
d.point([(4, 17), (6, 18), (9, 17)], fill=hexc("#f0ece0"))      # spilled flour
out("objects", "quern", im)

# well: round stone wall, dark water, a little roof on two posts, bucket
im = canvas(16, 24); d = ImageDraw.Draw(im); shadow(d, 21, 0, 15)
d.ellipse([1, 14, 14, 22], fill=hexc("#7a7a80"))
for x in range(1, 15, 3):
    d.line([(x, 15), (x, 21)], fill=hexc("#5e5e64"))
d.ellipse([3, 14, 12, 18], fill=hexc("#1c3448")); d.ellipse([5, 15, 9, 16], fill=hexc("#3a6a8a"))
d.line([(2, 4), (2, 17)], fill=hexc("#5a3a20")); d.line([(13, 4), (13, 17)], fill=hexc("#5a3a20"))
d.polygon([(0, 5), (8, 0), (15, 5), (15, 7), (8, 2), (0, 7)], fill=hexc("#8a4a2a"))
d.line([(0, 6), (8, 1)], fill=hexc("#a85a34")); d.line([(2, 8), (13, 8)], fill=hexc("#6a4628"))
d.line([(8, 8), (8, 11)], fill=hexc("#c8b890")); d.rectangle([7, 11, 9, 13], fill=hexc("#7a5230"))
out("objects", "well", im)

# fences: weathered posts + two rails (horizontal run, and vertical run)
im = canvas(); d = ImageDraw.Draw(im)
for x in (1, 14):
    d.rectangle([x, 12, x + 1, 22], fill=hexc("#6a4a28")); d.point([(x, 12)], fill=hexc("#8a6a40"))
for y in (14, 18):
    d.line([(0, y), (15, y)], fill=hexc("#8a6038")); d.line([(0, y + 1), (15, y + 1)], fill=hexc("#5a3a1e"))
d.line([(1, 22), (15, 22)], fill=(0, 0, 0, 50))
out("objects", "fence", im)
im = canvas(); d = ImageDraw.Draw(im)
d.rectangle([7, 8, 8, 22], fill=hexc("#6a4a28")); d.point([(7, 8)], fill=hexc("#8a6a40"))
for x in (6, 9):
    d.line([(x, 0 + 10), (x, 23)], fill=hexc("#8a6038") if x == 6 else hexc("#5a3a1e"))
d.rectangle([7, 15, 8, 16], fill=hexc("#7a5230"))
out("objects", "fence_v", im)

# ------------------------------------------------------------- actors ------
fr = []
for f in range(2):   # cow: 24x16, white with black patches, faces right
    im = canvas(24, 16); d = ImageDraw.Draw(im)
    d.ellipse([2, 13, 21, 15], fill=(0, 0, 0, 70))
    legs = [(5, 11, 15 - f), (8, 11, 14 + f), (14, 11, 15 - f), (17, 11, 14 + f)]
    for x, y0, y1 in legs:
        d.line([(x, y0), (x, y1)], fill=hexc("#d8d4cc")); d.point([(x, y1)], fill=hexc("#3a3430"))
    d.rounded_rectangle([3, 4, 19, 11], radius=3, fill=hexc("#f4f2ec"))
    d.ellipse([6, 4, 11, 8], fill=hexc("#2a2622")); d.ellipse([13, 7, 17, 11], fill=hexc("#2a2622"))
    d.line([(4, 11), (18, 11)], fill=hexc("#d8d4cc"))
    d.polygon([(3, 5), (1, 7 + f), (1, 10 + f), (2, 10 + f)], fill=hexc("#d8d4cc"))     # tail swish
    d.point([(1, 10 + f)], fill=hexc("#2a2622"))
    d.rounded_rectangle([18, 3 + f, 23, 9 + f], radius=2, fill=hexc("#f4f2ec"))        # head (grazes on frame 1)
    d.rectangle([20, 7 + f, 23, 9 + f], fill=hexc("#e8b0a8"))                          # muzzle
    d.point([(21, 5 + f)], fill=hexc("#1a1a1a"))
    d.point([(18, 2 + f), (22, 2 + f)], fill=hexc("#e8e0c8")); d.point([(19, 3 + f)], fill=hexc("#2a2622"))   # horns + ear
    d.point([(10, 11), (11, 11)], fill=hexc("#f0a8b0"))                                 # udder
    fr.append(im)
out("actors", "cow", strip(fr))

# villager keeper: straw hat, green smock, apron; 4 idle frames like the keepers
fr = []
sk = hexc("#e2b896")
for f in range(4):
    im = canvas(); d = ImageDraw.Draw(im); shadow(d)
    bob = 1 if f in (1, 2) else 0
    d.rectangle([5, 17, 6, 21], fill=hexc("#4a3a2a")); d.rectangle([9, 17, 10, 21], fill=hexc("#4a3a2a"))
    d.rectangle([4, 10 + bob, 11, 17], fill=hexc("#5a7a3a"))
    d.rectangle([5, 12 + bob, 10, 17], fill=hexc("#e8dcc0"))                            # apron
    d.rectangle([3, 11 + bob, 3, 14 + bob], fill=sk); d.rectangle([12, 11 + bob, 12, 14 + bob], fill=sk)
    d.rectangle([5, 4 + bob, 10, 9 + bob], fill=sk); d.point([(11, 7 + bob)], fill=sk)
    d.rectangle([3, 3 + bob, 12, 3 + bob], fill=hexc("#d8b860")); d.rectangle([5, 1 + bob, 10, 3 + bob], fill=hexc("#e8c870"))
    d.line([(5, 3 + bob), (10, 3 + bob)], fill=hexc("#a8282a"))                          # hat band
    d.point([(8, 6 + bob), (10, 6 + bob)], fill=hexc("#22201c"))
    if f == 3:
        d.point([(8, 6 + bob), (10, 6 + bob)], fill=sk)
    fr.append(im)
out("actors", "villager", strip(fr))

# cottage sign: a little board with a house and a wheat ear
im = Image.new("RGBA", (16, 16), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
d.line([(2, 1), (13, 1)], fill=hexc("#3a2a1a")); d.line([(4, 1), (4, 3)], fill=hexc("#3a2a1a")); d.line([(11, 1), (11, 3)], fill=hexc("#3a2a1a"))
d.rectangle([2, 3, 13, 14], fill=hexc("#5a3a20")); d.rectangle([3, 4, 12, 13], fill=hexc("#e8dcb8"))
d.polygon([(4, 9), (7, 6), (10, 9)], fill=hexc("#a8482a")); d.rectangle([5, 9, 9, 12], fill=hexc("#8a6038"))
d.rectangle([7, 10, 7, 12], fill=hexc("#3a2a1a")); d.line([(11, 6), (11, 12)], fill=hexc("#c8a040")); d.point([(10, 7), (12, 8)], fill=hexc("#e8c860"))
out("buildings", "sign_house", im)

# -------------------------------------------------------------- items ------
def icon(name, fn):
    im = Image.new("RGBA", (16, 16), (0, 0, 0, 0)); d = ImageDraw.Draw(im); fn(d); out("items", name, im)

def wheat_icon(d):
    for x, top in [(5, 2), (8, 1), (11, 3)]:
        d.line([(x, top + 5), (8, 14)], fill=hexc("#b89a3a"))
        d.rectangle([x - 1, top, x, top + 5], fill=hexc("#e8c860")); d.point([(x, top - 1)], fill=hexc("#f8e8a8"))
    d.line([(6, 11), (10, 11)], fill=hexc("#a8282a"))
icon("wheat", wheat_icon)
icon("flour", lambda d: (d.polygon([(4, 5), (12, 5), (13, 14), (3, 14)], fill=hexc("#e8dcc0")), d.rectangle([5, 3, 11, 5], fill=hexc("#d8c8a0")),
                         d.line([(5, 4), (11, 4)], fill=hexc("#8a6038")), d.ellipse([6, 8, 10, 12], fill=hexc("#f8f4ec")), d.point([(8, 10)], fill=hexc("#c8a040"))))
icon("bread", lambda d: (d.ellipse([2, 5, 14, 13], fill=hexc("#b8783a")), d.ellipse([3, 5, 13, 10], fill=hexc("#d89850")),
                         d.line([(5, 7), (7, 9)], fill=hexc("#f0c880")), d.line([(8, 6), (10, 8)], fill=hexc("#f0c880")), d.line([(11, 7), (12, 8)], fill=hexc("#f0c880"))))
icon("burnt_bread", lambda d: (d.ellipse([2, 5, 14, 13], fill=hexc("#3a2a1e")), d.ellipse([3, 5, 13, 10], fill=hexc("#4a3424")), d.point([(6, 8), (10, 7)], fill=hexc("#6a4a30"))))
icon("raw_beef", lambda d: (d.polygon([(3, 5), (10, 3), (14, 7), (12, 13), (5, 13), (2, 9)], fill=hexc("#c83a3a")),
                            d.line([(4, 8), (11, 6)], fill=hexc("#f0d8d0")), d.line([(5, 11), (12, 9)], fill=hexc("#f0d8d0")), d.ellipse([10, 9, 13, 12], fill=hexc("#f4f0e8"))))
icon("cooked_beef", lambda d: (d.polygon([(3, 5), (10, 3), (14, 7), (12, 13), (5, 13), (2, 9)], fill=hexc("#7a4a2a")),
                               d.line([(4, 8), (11, 6)], fill=hexc("#a8703a")), d.line([(5, 11), (12, 9)], fill=hexc("#a8703a")), d.line([(3, 6), (9, 4)], fill=hexc("#5a3018"))))
icon("cowhide", lambda d: (d.polygon([(2, 4), (5, 2), (11, 2), (14, 4), (13, 13), (10, 14), (6, 14), (3, 13)], fill=hexc("#f0ece4")),
                           d.ellipse([4, 4, 8, 8], fill=hexc("#2a2622")), d.ellipse([9, 8, 12, 12], fill=hexc("#2a2622")), d.point([(2, 3), (14, 3), (2, 14), (14, 14)], fill=hexc("#c8c0b0"))))

json.dump(_manifest, open(MANIFEST, "w"), indent=1, sort_keys=True)
print("0.3.1 farm art generated")
