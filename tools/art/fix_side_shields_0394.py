"""0.3.9.4 side-shield fix, on top of fix_side_shields_0393.py.
1) Every side shield frame is made fully opaque inside its own outline (any
   non-255 pixel not reachable from the frame edge by a 4-way flood fill is set
   to the face colour).
2) Gaps between the shield and the player's body: a pixel enclosed by
   (body | shield) but covered by neither showed the ground through it (the
   0.3.9.3 "bleed-through"); it is painted with the shield's face colour.
Intentionally bypasses art_guard; re-hashes protected_art.json.
Usage: python3 tools/art/fix_side_shields_0394.py   (from the project root)"""
import glob, hashlib, json, os
from collections import Counter, deque
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PROT = os.path.join(ROOT, "tools", "art", "protected_art.json")
FW, FH = 16, 24


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def enclosed(solid):
    """solid(x, y) -> bool over a FW x FH frame; returns the non-solid cells
    not reachable from the frame border."""
    seen, q = set(), deque()
    for x in range(FW):
        q.extend([(x, 0), (x, FH - 1)])
    for y in range(FH):
        q.extend([(0, y), (FW - 1, y)])
    while q:
        x, y = q.popleft()
        if (x, y) in seen or not (0 <= x < FW and 0 <= y < FH) or solid(x, y):
            continue
        seen.add((x, y))
        q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    return [(x, y) for x in range(FW) for y in range(FH) if not solid(x, y) and (x, y) not in seen]


def fix(path, body):
    im = Image.open(path).convert("RGBA")
    px, bp = im.load(), body.load()
    allc = Counter(px[x, y] for x in range(im.width) for y in range(im.height) if px[x, y][3] == 255)
    ink = min(allc, key=lum)
    face = Counter({c: n for c, n in allc.items() if c != ink}).most_common(1)[0][0]
    n = 0
    for f in range(im.width // FW):
        o = f * FW
        bf = min(f, body.width // FW - 1) * FW
        for x, y in enclosed(lambda x, y: px[o + x, y][3] == 255):
            px[o + x, y] = face; n += 1
        for x, y in enclosed(lambda x, y: px[o + x, y][3] == 255 or bp[bf + x, y][3] > 128):
            if bp[bf + x, y][3] <= 128:
                px[o + x, y] = face; n += 1
    im.save(path, optimize=True)
    return n


if __name__ == "__main__":
    body = Image.open(os.path.join(ROOT, "assets/sprites/actors/player.png")).convert("RGBA")
    prot = json.load(open(PROT))
    for p in sorted(glob.glob(os.path.join(ROOT, "assets/sprites/actors/gear/shield*.png"))):
        if p.endswith(("_front.png", "_back.png")):
            continue
        n = fix(p, body)
        rel = os.path.relpath(p, ROOT)
        if rel in prot["files"]:
            prot["files"][rel] = hashlib.sha256(open(p, "rb").read()).hexdigest()
        print(rel, "painted", n)
    json.dump(prot, open(PROT, "w"), indent=1)
