"""0.4.3: road_dirt art had two dark horizontal rut bands per 16px tile (rows 4-5, 11-12)
that repeat identically on every tile and read as planks. Fill those rows with the tile's
own mid-tone pixels (taken from nearby rows, shifted) and scatter a few small dark pebble
clusters instead, so the texture stays in palette but has no row rhythm."""
import random, sys
from PIL import Image
BAND = {4, 5, 11, 12}
def fix(path, pebbles):
    im = Image.open(path).convert("RGBA"); px = im.load(); w, h = im.size
    rnd = random.Random(path)
    for ty in range(0, h, 16):
        for tx in range(0, w, 16):
            for y in BAND:
                for x in range(16):
                    X, Y = tx + x, ty + y
                    if px[X, Y][3] == 0: continue
                    for _ in range(6):
                        sy = ty + rnd.choice([y - 2, y - 3, y + 2, y + 3]) % 16
                        sx = tx + (x + rnd.randint(-3, 3)) % 16
                        if px[sx, sy][3] > 0 and (sy - ty) not in BAND:
                            px[X, Y] = px[sx, sy][:3] + (px[X, Y][3],); break
            if pebbles:
                dark = (66, 46, 32)
                for _ in range(rnd.randint(2, 4)):
                    x, y = rnd.randint(0, 14), rnd.randint(0, 14)
                    for dx, dy in [(0, 0), (1, 0), (0, 1)][: rnd.randint(1, 3)]:
                        p = px[tx + x + dx, ty + y + dy]
                        if p[3]: px[tx + x + dx, ty + y + dy] = dark + (p[3],)
    im.save(path)
for p in sys.argv[1:]:
    fix(p, "transitions/road_dirt.png" not in p)
