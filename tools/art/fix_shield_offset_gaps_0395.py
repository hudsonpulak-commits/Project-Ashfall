#!/usr/bin/env python3
"""0.3.9.5 facing right the side shield draws behind the body 1 px forward
(Actor.gear_layer_offset). On a few frames that shift opens 1-px holes between
the body and the shield edge where the ground shows through. Close them in the
side shield sheet with the shield's own outline ink (sheet pixel = screen x - 1).
Facing left (shield over the body, no offset) those pixels land on the body's
outline. Iterates until no hole is left (player + npc bodies); re-hashes
protected_art.json. Idempotent."""
import glob, hashlib, json, os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
G = os.path.join(ROOT, 'assets/sprites/actors/gear')
A = os.path.join(ROOT, 'assets/sprites/actors')
FW, FH, DX = 16, 24, 1


def lum(c):
    return c[0] * 299 + c[1] * 587 + c[2] * 114


def enclosed(solid):
    seen = set(); st = [(x, y) for x in range(FW) for y in (0, FH - 1)] + [(x, y) for y in range(FH) for x in (0, FW - 1)]
    while st:
        p = st.pop()
        if p in seen or solid(*p):
            continue
        seen.add(p); x, y = p
        st += [q for q in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)) if 0 <= q[0] < FW and 0 <= q[1] < FH]
    return [(x, y) for y in range(FH) for x in range(FW) if (x, y) not in seen and not solid(x, y)]


def main():
    bodies = [Image.open(os.path.join(A, b + '.png')).convert('RGBA') for b in ('player', 'npc')]
    pj = os.path.join(ROOT, 'tools/art/protected_art.json'); d = json.load(open(pj)); total = 0
    for p in sorted(glob.glob(os.path.join(G, 'shield*_[1-4].png'))):
        img = Image.open(p).convert('RGBA'); px = img.load(); n = 0
        for fr in range(img.width // FW):
            o = fr * FW
            ink = min({px[o + x, y] for y in range(FH) for x in range(FW) if px[o + x, y][3] == 255}, key=lum)
            for body in bodies:
                bo = min(fr, body.width // FW - 1) * FW
                while True:
                    holes = enclosed(lambda x, y: (x >= DX and px[o + x - DX, y][3] == 255) or body.getpixel((bo + x, y))[3] > 128)
                    holes = [(x, y) for x, y in holes if x >= DX]
                    if not holes:
                        break
                    for x, y in holes:
                        px[o + x - DX, y] = ink; n += 1
        if n:
            img.save(p, optimize=True)
            rel = os.path.relpath(p, ROOT)
            if rel in d['files']:
                d['files'][rel] = hashlib.sha256(open(p, 'rb').read()).hexdigest()
        total += n
        print(os.path.basename(p), 'painted', n)
    json.dump(d, open(pj, 'w'), indent=1, sort_keys=True); open(pj, 'a').write('\n')
    print('total painted', total)


if __name__ == '__main__':
    main()
