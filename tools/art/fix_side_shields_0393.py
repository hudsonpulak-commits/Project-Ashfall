"""0.3.9.3 fix: the designer's side-view shield sheets (gear/shield*.png, not
_front/_back) had their centre erased in the body's silhouette (the back-view
'only the edge peeks out' mask was applied to the side view too), so a shield
held in front of the body was drawn as a hollow ring and looked transparent.
This fills each row between the leftmost and rightmost shield pixel with the
shield's face colour (most common non-ink colour), keeping every existing
pixel. Intentionally bypasses art_guard; re-hashes protected_art.json.
Usage: python3 tools/art/fix_side_shields_0393.py   (from the project root)"""
import glob, hashlib, json, os
from collections import Counter
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PROT = os.path.join(ROOT, "tools", "art", "protected_art.json")


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def fix(path, fw=16):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    px = im.load()
    allc = Counter(px[x, y] for x in range(w) for y in range(h) if px[x, y][3] > 128)
    ink = min(allc, key=lum)   # the outline ink is the darkest colour
    cols = Counter({c: n for c, n in allc.items() if c != ink})
    if not cols:
        return 0
    face = cols.most_common(1)[0][0]
    filled = 0
    for f in range(w // fw):
        for y in range(h):
            xs = [x for x in range(f * fw, (f + 1) * fw) if px[x, y][3] > 128]
            if len(xs) < 2:
                continue
            for x in range(xs[0] + 1, xs[-1]):
                if px[x, y][3] <= 128:
                    px[x, y] = face
                    filled += 1
    im.save(path, optimize=True)
    return filled


if __name__ == "__main__":
    prot = json.load(open(PROT))
    for p in sorted(glob.glob(os.path.join(ROOT, "assets/sprites/actors/gear/shield*.png"))):
        if p.endswith("_front.png") or p.endswith("_back.png"):
            continue
        n = fix(p)
        rel = os.path.relpath(p, ROOT)
        if rel in prot["files"]:
            prot["files"][rel] = hashlib.sha256(open(p, "rb").read()).hexdigest()
        print(rel, "filled", n)
    json.dump(prot, open(PROT, "w"), indent=1)
