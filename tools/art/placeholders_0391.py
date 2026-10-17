#!/usr/bin/env python3
"""0.3.9.1 directional placeholder sheets, redrawn (overwrites the 0.3.9
generated *_front.png / *_back.png; the side sheets are never touched).

Creatures (non-humanoid frames): front = head-on (the body narrowed, ONE head
centred), back = rear view (body narrowed, tail, no head). Symmetric blobs
(slime) keep the side frame. Never a mirrored half (that made 2 heads / 2 rears).
Humanoids (16-wide, 24+ tall): body/legs from the side frame (walk frames kept,
no mirrored doubles); the head is rebuilt symmetric: front = hair fringe, face,
2 eyes, mouth; back = hair (bald heads keep their skin, no face). Held items
outside the body: kept on the front; on the back a baked-in shield is hidden
behind the body (only its outer edge column peeks out).
Gear: helmets symmetric; body/legs as the side frame; weapons as the side; the
shield's back sheet keeps only the edge that peeks out beside the body."""
import json, os
from collections import Counter
from PIL import Image
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
A = os.path.join(ROOT, "assets", "sprites")
SPAN = (3, 12)          # humanoid body columns in a 16-wide frame (mirror axis 7.5)
CLEAR = (0, 0, 0, 0)

def skinish(c): return c[3] > 128 and c[0] > 150 and c[0] > c[1] > c[2] and c[0] - c[2] > 40 and c[2] > 100 and c[1] < c[0] * 0.85
def shade(c, f): return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + (c[3],)
def lum(c): return 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]

def bbox(fr):
    b = fr.getbbox()
    return b if b else (0, 0, fr.width, fr.height)

# --------------------------------------------------------------- creatures --
def symmetric(fr):
    m = fr.transpose(Image.FLIP_LEFT_RIGHT)
    a, b = fr.load(), m.load()
    diff = sum(1 for y in range(fr.height) for x in range(fr.width) if (a[x, y][3] > 128) != (b[x, y][3] > 128))
    return diff <= max(3, fr.width * fr.height // 40)

def squeeze(img, w):
    return img.resize((max(1, w), img.height), Image.NEAREST)

def creature_views(fr):
    W, H = fr.size
    if symmetric(fr):
        return fr.copy(), fr.copy()
    x0, y0, x1, y1 = bbox(fr)
    bw = x1 - x0
    hw = max(3, int(round(bw * 0.35)))          # the art faces right: the head is the right part
    head = fr.crop((x1 - hw, 0, x1, H))
    body = fr.crop((x0 + max(1, bw // 8), 0, x1 - hw + 1, H))
    tail = fr.crop((x0, 0, x0 + max(1, bw // 6), H))
    nb = max(4, int(round(bw * 0.45)))
    if nb % 2 != W % 2: nb += 1
    cx = W // 2
    front = Image.new("RGBA", (W, H), CLEAR); back = Image.new("RGBA", (W, H), CLEAR)
    bsq = squeeze(body, nb)
    front.alpha_composite(bsq, (cx - nb // 2, 0))
    back.alpha_composite(bsq, (cx - nb // 2, 0))
    # head-on: the head mirrored onto itself round its own centre -> one symmetric face
    hb = bbox(head)
    hc = head.crop((hb[0], 0, hb[2], H))
    half = hc.crop((0, 0, (hc.width + 1) // 2, H)) if hc.width > 1 else hc
    face = Image.new("RGBA", (half.width * 2 - (hc.width % 2), H), CLEAR)
    face.alpha_composite(half, (0, 0)); face.alpha_composite(half.transpose(Image.FLIP_LEFT_RIGHT), (face.width - half.width, 0))
    fy = min(1, max(0, (y1 - y0) // 6))
    front.alpha_composite(face, (cx - face.width // 2, fy))
    # rear: a short tail stub centred on top of the rump, no head
    tb = bbox(tail)
    if tb[3] > tb[1]:
        stub = tail.crop((tb[0], tb[1], min(tb[2], tb[0] + 2), tb[3]))
        back.alpha_composite(stub, (cx - stub.width // 2, max(0, tb[1] - 1)))
    return front, back

# ---------------------------------------------------------------- humanoids --
def head_rows(fr):
    """Rows of the head: from the top of the sprite to the last skin row in the top half."""
    W, H = fr.size; px = fr.load()
    x0, y0, x1, y1 = bbox(fr)
    skin = [c for y in range(y0, int(H * 0.5)) for x in range(SPAN[0], SPAN[1] + 1) for c in [px[x, y]] if skinish(c)]
    if skin:
        sk = Counter(skin).most_common(1)[0][0]
        is_skin = lambda c: skinish(c)
    else:   # goblins & co: the dominant saturated colour of the top rows
        top = [px[x, y] for y in range(y0, min(H, y0 + 6)) for x in range(SPAN[0], SPAN[1] + 1) if px[x, y][3] > 128 and max(px[x, y][:3]) - min(px[x, y][:3]) > 40]
        if not top:
            return None
        sk = Counter(top).most_common(1)[0][0]
        is_skin = lambda c: c[3] > 128 and sum(abs(c[k] - sk[k]) for k in range(3)) < 60
    rows = [y for y in range(y0, int(H * 0.5)) if any(is_skin(px[x, y]) for x in range(SPAN[0], SPAN[1] + 1))]
    if not rows:
        return None
    # the head ends at the first row below the face without skin in the middle columns
    end = rows[0]
    while end + 1 < H // 2 and any(is_skin(px[x, end + 1]) for x in range(6, 11)) and end + 1 - rows[0] < 7:
        end += 1
    rows = [y for y in rows if y <= end]
    return y0, rows[0], rows[-1], sk, is_skin

def monster_views(fr):
    W, H = fr.size; px = fr.load()
    front = fr.copy(); back = fr.copy(); fp, bp = front.load(), back.load()
    x0, y0, x1, y1 = bbox(fr)
    for y in range(H):
        for x in range(SPAN[0], SPAN[1] + 1):
            if x >= W // 2:
                continue
            fp[x, y] = px[W - 1 - x, y]
            bp[W - 1 - x, y] = px[x, y]
    # the back of the head: eyes / mouth (off-colour pixels) become the head colour
    rows = range(y0, min(H, y0 + 7))
    hc = Counter(bp[x, y] for y in rows for x in range(SPAN[0], SPAN[1] + 1) if bp[x, y][3] > 128).most_common(1)
    if hc:
        hc = hc[0][0]
        for y in rows:
            for x in range(SPAN[0] + 1, SPAN[1]):
                c = bp[x, y]
                if c[3] > 128 and c != hc and bp[x - 1, y][3] > 128 and bp[x + 1, y][3] > 128:
                    bp[x, y] = hc
    return front, back


def humanoid_views(fr, baked_shield_cols):
    W, H = fr.size; px = fr.load()
    if not any(skinish(px[x, y]) for y in range(H // 2) for x in range(SPAN[0], SPAN[1] + 1)):
        return monster_views(fr)
    front = fr.copy(); back = fr.copy(); fp, bp = front.load(), back.load()
    hr = head_rows(fr)
    if hr:
        top, hairline, last, sk, is_skin = hr
        cols = [x for x in range(SPAN[0], SPAN[1] + 1) if any(px[x, y][3] > 128 for y in range(top, last + 1))]
        # symmetric head columns round 7.5
        lo = min(min(cols), W - 1 - max(cols)); hi = W - 1 - lo
        hair = [px[x, y] for y in range(top, hairline) for x in range(lo, hi + 1) if px[x, y][3] > 128 and not is_skin(px[x, y]) and lum(px[x, y]) > 25]
        hc = Counter(hair).most_common(1)[0][0] if len(hair) >= 4 else None
        # the side eye: darkest pixel among the face rows
        eye_y, eye_c = hairline + 1, (32, 22, 16, 255)
        dark = [(lum(px[x, y]), y, px[x, y]) for y in range(hairline, last + 1) for x in range(lo, hi + 1) if px[x, y][3] > 128 and not is_skin(px[x, y]) and lum(px[x, y]) < 70]
        if dark:
            _, eye_y, eye_c = min(dark)
        eye_y = min(max(eye_y, hairline), last)
        for y in range(top, last + 1):
            for x in range(lo, hi + 1):
                was = px[x, y][3] > 128 or px[W - 1 - x, y][3] > 128
                if not was:
                    fp[x, y] = CLEAR; bp[x, y] = CLEAR
                    continue
                edge = x in (lo, hi)
                # back: hair over the whole head (bald: plain skin)
                bp[x, y] = hc if hc else sk
                # front: hair above the hairline and down the sides to the eyes; face below
                if y < hairline or (hc and edge and y < eye_y):
                    fp[x, y] = hc if hc else sk
                else:
                    fp[x, y] = sk
        cx = W // 2
        if eye_y <= last:
            fp[cx - 2, eye_y] = eye_c; fp[cx + 1, eye_y] = eye_c
        if eye_y + 2 <= last:
            fp[cx - 1, eye_y + 2] = shade(sk, 0.78); fp[cx, eye_y + 2] = shade(sk, 0.78)
        # clear the old side-view head pixels outside the symmetric head
        for y in range(top, last + 1):
            for x in list(range(SPAN[0], lo)) + list(range(hi + 1, SPAN[1] + 1)):
                if is_skin(px[x, y]) or (hc and px[x, y] == hc):
                    fp[x, y] = CLEAR; bp[x, y] = CLEAR
    # a baked shield: on the back only its outer edge peeks out beside the body
    if baked_shield_cols:
        scol = Counter(px[x, y] for x in baked_shield_cols for y in range(H) if px[x, y][3] > 128)
        shield_colors = {c for c, n in scol.items() if n >= 2}
        for y in range(H):
            for x in range(0, SPAN[0] + 3):
                c = px[x, y]
                if c[3] > 128 and c in shield_colors:
                    if x == SPAN[0] - 1:
                        continue   # the edge that peeks out
                    m = px[W - 1 - x, y] if x >= SPAN[0] else CLEAR
                    bp[x, y] = m if (m[3] > 128 and m not in shield_colors) else (CLEAR if x < SPAN[0] else shade(c, 0.6))
    return front, back

def gear_views(fr, slot):
    W, H = fr.size; px = fr.load()
    if slot == "head":
        m = fr.copy(); mp = m.load()
        for y in range(H):
            for x in range(W // 2, W):
                mp[x, y] = px[W - 1 - x, y]
        return m, m.copy()
    if slot == "shield":
        back = Image.new("RGBA", (W, H), CLEAR); bp = back.load()
        for y in range(H):
            for x in range(0, SPAN[0]):
                if px[x, y][3] > 128 and x >= SPAN[0] - 1:
                    bp[x, y] = shade(px[x, y], 0.7)
        return fr.copy(), back
    return fr.copy(), fr.copy()

BAKED_SHIELD = {"town_guard": [1, 2]}

def main():
    spr = json.load(open(os.path.join(ROOT, "data", "sprites.json")))
    n = 0
    for sid, d in spr["actors"].items():
        if sid.startswith("_") or "dir_paths" not in d:
            continue
        rel = d["path"].replace("res://assets/sprites/", "")
        fw, fh = d["frame_size"]
        im = Image.open(os.path.join(A, rel)).convert("RGBA")
        front = Image.new("RGBA", im.size, CLEAR); back = Image.new("RGBA", im.size, CLEAR)
        for f in range(im.width // fw):
            fr = im.crop((f * fw, 0, (f + 1) * fw, fh))
            if sid.startswith("gear_"):
                a, b = gear_views(fr, sid.split("_")[1])
            elif fw == 16 and fh >= 24:
                a, b = humanoid_views(fr, BAKED_SHIELD.get(sid, []))
            else:
                a, b = creature_views(fr)
            front.paste(a, (f * fw, 0)); back.paste(b, (f * fw, 0))
        stem = rel[:-4]
        front.save(os.path.join(A, stem + "_front.png"), optimize=True)
        back.save(os.path.join(A, stem + "_back.png"), optimize=True)
        n += 1
    print("redrew", n, "front/back sheets")

if __name__ == "__main__":
    main()
