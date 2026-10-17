#!/usr/bin/env python3
"""0.3.9.5 full-face helmets in every facing.

For every helmet sheet (gear/head_<tier>{,_front,_back}.png) and every frame,
the head of the body underneath (player.png / npc.png sheet for that facing:
face, hair, ears, eyes, mouth in the head rows, plus neck skin) that the
helmet does not already cover is painted into the helmet as a closed
faceplate: the helmet's own plate colour, a dark eye slit on the body's eye
row, and ink where the plate meets the body's silhouette edge (so the plate
keeps an outline). All written pixels are alpha 255. Then protected_art.json
is re-hashed. Idempotent (a covered face paints nothing)."""
import hashlib, json, os, sys
from collections import Counter
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
G = os.path.join(ROOT, 'assets/sprites/actors/gear')
A = os.path.join(ROOT, 'assets/sprites/actors')
FW, FH, HEAD_ROWS = 16, 24, 12        # frames 16x24; head = rows 0..11
SUFFIXES = ['', '_front', '_back']
BODIES = ['player', 'npc']


def skinish(c):
    return c[3] > 128 and c[0] > 150 and c[0] > c[1] > c[2] and c[0] - c[2] > 40


def lum(c):
    return c[0] * 299 + c[1] * 587 + c[2] * 114


def face_mask(body, fr):
    """skin in the head rows + every pixel enclosed by skin on its row and column (eyes, mouth)"""
    ox = fr * FW
    sk = {(x, y) for y in range(HEAD_ROWS) for x in range(FW) if skinish(body.getpixel((ox + x, y)))}
    m = set(sk)
    for y in range(HEAD_ROWS):
        for x in range(FW):
            if (x, y) in sk or body.getpixel((ox + x, y))[3] == 0:
                continue
            row = any((i, y) in sk for i in range(x)) and any((i, y) in sk for i in range(x + 1, FW))
            col = any((x, j) in sk for j in range(y)) and any((x, j) in sk for j in range(y + 1, HEAD_ROWS))
            if row and col:
                m.add((x, y))
    return m, sk


def head_mask(body, fr):
    """the body's head: every opaque body pixel in rows 0..HEAD_ROWS-2 (face, hair,
    ears, eyes, mouth) plus the skin of the neck on the last head row"""
    ox = fr * FW
    m = {(x, y) for y in range(HEAD_ROWS - 1) for x in range(FW) if body.getpixel((ox + x, y))[3] > 0}
    m |= {(x, HEAD_ROWS - 1) for x in range(FW) if skinish(body.getpixel((ox + x, HEAD_ROWS - 1)))}
    return m


def fix_sheet(path, suf):
    helm = Image.open(path).convert('RGBA')
    bodies = [Image.open(os.path.join(A, f'{b}{suf}.png')).convert('RGBA') for b in BODIES]
    painted = 0
    for fr in range(helm.width // FW):
        ox = fr * FW
        cols = [helm.getpixel((ox + x, y)) for y in range(FH) for x in range(FW) if helm.getpixel((ox + x, y))[3] == 255]
        if not cols:
            continue
        ink = min(set(cols), key=lum)
        plate = Counter(c for c in cols if c != ink).most_common(1)[0][0]
        for body in bodies:
            m = head_mask(body, fr)
            todo = [(x, y) for (x, y) in m if helm.getpixel((ox + x, y))[3] < 255]
            if not todo:
                continue
            face, sk = face_mask(body, fr)
            feats = sorted(y for (x, y) in face if (x, y) not in sk)
            eye_y = feats[0] if feats else None   # the body's eye row -> the visor slit
            solid = lambda x, y: 0 <= x < FW and 0 <= y < FH and (body.getpixel((ox + x, y))[3] > 0 or helm.getpixel((ox + x, y))[3] == 255)
            for (x, y) in todo:
                edge = not all(solid(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                slit = y == eye_y and (x, y) in face
                helm.putpixel((ox + x, y), ink if (edge or slit) else plate)
                painted += 1
    if painted:
        helm.save(path, optimize=True)
    return painted


def rehash():
    pj = os.path.join(ROOT, 'tools/art/protected_art.json')
    if not os.path.exists(pj):
        return 0
    d = json.load(open(pj))
    files = d.get('files', d)
    n = 0
    for rel in list(files.keys()):
        p = os.path.join(ROOT, rel)
        if os.path.exists(p) and os.path.basename(rel).startswith('head_') and '/gear/' in rel:
            h = hashlib.sha256(open(p, 'rb').read()).hexdigest()
            if isinstance(files[rel], dict):
                key = 'sha256' if 'sha256' in files[rel] else next(iter(files[rel]))
                files[rel][key] = h
            else:
                files[rel] = h if len(str(files[rel])) == 64 else hashlib.md5(open(p, 'rb').read()).hexdigest()
            n += 1
    json.dump(d, open(pj, 'w'), indent=1, sort_keys=True)
    open(pj, 'a').write('\n')
    return n


if __name__ == '__main__':
    total = 0
    for t in sorted({f.split('_')[1].split('.')[0] for f in os.listdir(G) if f.startswith('head_') and f.endswith('.png')}):
        for suf in SUFFIXES:
            p = os.path.join(G, f'head_{t}{suf}.png')
            if os.path.exists(p):
                n = fix_sheet(p, suf); total += n
                print(os.path.relpath(p, ROOT), 'painted', n)
    print('re-hashed', rehash(), 'helmet entries; total painted', total)
