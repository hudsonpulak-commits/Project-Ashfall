#!/usr/bin/env python3
"""Render markup-friendly world map PNGs from the dump made by tools/export_world_map.gd.

    $GODOT --headless --path . --script res://tools/export_world_map.gd
    python3 tools/render_world_map.py [build/map]

Writes ashfen_world_map.png (terrain, grid, roads/bridges, towns, guard
patrols, mines by tier, enemy camps by kind + distance bands, the Scorch),
ashfen_world_map_resources.png (+ resource nodes) and ashfen_world_map_plain.png
(terrain, grid, town labels). Coordinates are world tile coords exactly as the
in-game HUD shows them (x grows east/right, y grows south/down).
"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "build", "map")
PX = 3                       # pixels per tile
GRID = 50                    # grid step in tiles
X0, X1, Y0, Y1 = -200, 525, -400, 325     # framed tile window (covers all land + margin)
ML, MT, MR, MB = 64, 120, 64, 64          # page margins (px)
def _project_version():
    """0.4.0 the title version is read from project.godot (was hard-coded v0.3.1)."""
    import re as _re
    pg = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "project.godot")
    try:
        m = _re.search(r'config/version="([^"]+)"', open(pg).read())
        return "v" + m.group(1) if m else "v?"
    except OSError:
        return "v?"

VERSION = _project_version()

d = json.load(open(os.path.join(OUT, "world_dump.json")))
meta = d["meta"]
ox, oy = meta["origin"]; W, H = meta["size"]
tiles = open(os.path.join(OUT, "world_tiles.bin"), "rb").read()
objs = open(os.path.join(OUT, "world_objects.bin"), "rb").read()
obj_ids = meta["object_ids"]
lx0, ly0, lx1, ly1 = meta["land_extent"]
assert X0 <= lx0 and Y0 <= ly0 and X1 > lx1 and Y1 > ly1, "land outside frame: %s" % meta["land_extent"]

FD = "/usr/share/fonts/truetype/sand-box/google/Atkinson Hyperlegible/"
def font(sz, bold=True):
    for p in [FD + ("AtkinsonHyperlegible-Bold.ttf" if bold else "AtkinsonHyperlegible-Regular.ttf"),
              "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]:
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()

def hexc(h):
    h = h.lstrip("#"); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

def mute(c, k=0.38, grey=0.25):
    """Desaturate + lighten so hand-drawn coloured marks stand out."""
    l = 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]
    c = [v + (l - v) * grey for v in c]
    return tuple(int(v + (238 - v) * k) for v in c)

TILE_COL = [mute(hexc(c)) for c in meta["tile_colors"]]
OCEAN = (196, 214, 226)
ROAD = (150, 110, 60)
MW, MH = (X1 - X0) * PX, (Y1 - Y0) * PX
PW, PH = ML + MW + MR, MT + MH + MB

def tp(x, y):
    """Tile (x, y) -> top-left pixel on the page."""
    return ML + (x - X0) * PX, MT + (y - Y0) * PX

def tc(x, y):
    a, b = tp(x, y); return a + PX / 2, b + PX / 2

RES_STYLE = {   # resources version: colour, square size px
    "ash_tree": ((120, 170, 90), 2), "alder_tree": ((40, 110, 50), 3), "blackthorn_tree": ((70, 30, 80), 3),
    "copper_rock": ((205, 110, 40), 3), "tin_rock": ((150, 160, 175), 3), "iron_rock": ((150, 40, 30), 3),
    "coal_rock": ((20, 20, 20), 3), "fishing_spot": ((0, 150, 210), 3),
    "reed_bed": ((170, 160, 80), 2), "fenroot_patch": ((140, 90, 40), 2),
}

def base(resources=False):
    img = Image.new("RGB", (PW, PH), (250, 248, 242))
    m = Image.new("RGB", (X1 - X0, Y1 - Y0), OCEAN)
    pm = m.load()
    for y in range(Y0, Y1):
        for x in range(X0, X1):
            bx, by = x - ox, y - oy
            if 0 <= bx < W and 0 <= by < H:
                t = tiles[by * W + bx]
                if t != 255:
                    pm[x - X0, y - Y0] = TILE_COL[t]
    img.paste(m.resize((MW, MH), Image.NEAREST), (ML, MT))
    dr = ImageDraw.Draw(img, "RGBA")
    if resources:
        order = ["reed_bed", "fenroot_patch", "ash_tree", "alder_tree", "blackthorn_tree",
                 "fishing_spot", "copper_rock", "tin_rock", "iron_rock", "coal_rock"]
        rank = {k: i for i, k in enumerate(order)}
        pts = []
        for y in range(Y0, Y1):
            for x in range(X0, X1):
                bx, by = x - ox, y - oy
                if 0 <= bx < W and 0 <= by < H:
                    o = objs[by * W + bx]
                    if o and obj_ids[o] in RES_STYLE:
                        pts.append((rank[obj_ids[o]], x, y, obj_ids[o]))
        for _, x, y, oid in sorted(pts):
            col, s = RES_STYLE[oid]
            a, b = tp(x, y); off = (PX - s) // 2
            dr.rectangle([a + off, b + off, a + off + s - 1, b + off + s - 1], fill=col)
    return img, dr

def grid(img, dr):
    f = font(20)
    for gx in range((X0 // GRID) * GRID, X1 + 1, GRID):
        if gx < X0: continue
        a, _ = tp(gx, Y0)
        strong = gx % 100 == 0
        dr.line([a, MT, a, MT + MH], fill=(40, 40, 40, 110 if strong else 60), width=2 if gx == 0 else 1)
        lab = str(gx)
        w = dr.textlength(lab, font=f)
        for yy in (MT - 24, MT + MH + 5):
            dr.text((a - w / 2, yy - (3 if yy < MT else 0)), lab, font=f, fill=(30, 30, 30))
    for gy in range((Y0 // GRID) * GRID, Y1 + 1, GRID):
        if gy < Y0: continue
        _, b = tp(X0, gy)
        strong = gy % 100 == 0
        dr.line([ML, b, ML + MW, b], fill=(40, 40, 40, 110 if strong else 60), width=2 if gy == 0 else 1)
        lab = str(gy)
        w = dr.textlength(lab, font=f)
        dr.text((ML - 8 - w, b - 12), lab, font=f, fill=(30, 30, 30))
        dr.text((ML + MW + 8, b - 12), lab, font=f, fill=(30, 30, 30))
    dr.rectangle([ML, MT, ML + MW, MT + MH], outline=(60, 60, 60), width=2)
    # axis hints
    fs = font(15, False)
    dr.text((ML, MT - 48), "x grows east (right)", font=fs, fill=(70, 70, 70))
    dr.text((ML + MW - 170, MT - 48), "y grows south (down)", font=fs, fill=(70, 70, 70))

def roads(dr):
    for r in d["roads"]:
        for x, y in r["tiles"]:
            a, b = tp(x, y)
            dr.rectangle([a - 1, b - 1, a + PX, b + PX], fill=ROAD + (200,))

LINE = json.load(open(os.path.join(os.path.dirname(__file__), "..", "data", "shop.json")))["line_names"]

WALL_COL = (90, 70, 55); GATE_COL = (235, 190, 60)

def towns(dr, shops=True):
    fn, fs = font(32), font(20, False)
    for t in d["towns"]:
        x, y, w, h = t["rect"]
        a, b = tp(x, y)
        dr.rectangle([a - 2, b - 2, a + w * PX + 1, b + h * PX + 1], outline=(20, 20, 20), width=3, fill=(255, 255, 255, 120))
        # 0.3.1 walled cities: the wall (thick) with a gold gap at each gate
        dr.rectangle([a, b, a + w * PX - 1, b + h * PX - 1], outline=WALL_COL, width=PX)
        for gx, gy in t.get("gates", []):
            ga, gb = tp(gx, gy)
            dr.rectangle([ga - PX, gb - PX, ga + 2 * PX, gb + 2 * PX], fill=GATE_COL, outline=(20, 20, 20))
        cx, cy = t["center"]
        lines = [(t["name"], fn)]
        sub = "Walled \u00b7 4 gates \u00b7 Bank \u00b7 General store \u00b7 Blacksmith \u00b7 Church \u00b7 Cook House \u00b7 Player shop"
        lines.append(("(%d, %d)" % (cx, cy), fs))
        if shops:
            lines.append((sub, fs))
            lines.append((", ".join(LINE.get(s, s) for s in t["specialists"]), fs))
        tw = max(dr.textlength(s, font=f_) for s, f_ in lines) + 16
        th = sum(f_.size + 6 for _, f_ in lines) + 8
        # label box beside the town (right side; left if it would leave the map)
        lxp = a + w * PX + 10
        if lxp + tw > ML + MW - 4:
            lxp = a - 10 - tw
        lyp = b + h * PX / 2 - th / 2
        dr.rectangle([lxp, lyp, lxp + tw, lyp + th], fill=(255, 255, 255, 225), outline=(20, 20, 20), width=2)
        yy = lyp + 5
        for s, f_ in lines:
            dr.text((lxp + 8, yy), s, font=f_, fill=(15, 15, 15))
            yy += f_.size + 6

WHEAT = (226, 190, 70); PASTURE = (150, 205, 110); FENCE = (110, 70, 30)

def villages(dr, labels=True):
    """0.3.1 villages (cream box + name), fenced wheat fields and cow pastures, village paths."""
    for v in d.get("villages", []):
        for x, y in v.get("path", []):
            a, b = tp(x, y)
            dr.rectangle([a - 1, b - 1, a + PX, b + PX], fill=ROAD + (200,))
    for f in d.get("farms", []):
        x, y, w, h = f["rect"]; a, b = tp(x, y)
        dr.rectangle([a, b, a + w * PX - 1, b + h * PX - 1], fill=WHEAT, outline=FENCE, width=2)
        for i in range(1, h - 1, 2):
            dr.line([a + 3, b + i * PX + 1, a + w * PX - 4, b + i * PX + 1], fill=(180, 140, 40))
    for p_ in d.get("pastures", []):
        x, y, w, h = p_["rect"]; a, b = tp(x, y)
        dr.rectangle([a, b, a + w * PX - 1, b + h * PX - 1], fill=PASTURE, outline=FENCE, width=2)
        for i in range(int(p_.get("count", 4))):
            cx = a + (2 + (i * 3) % max(1, w - 4)) * PX + 1; cy = b + (2 + (i // 2) * 2) * PX + 1
            dr.ellipse([cx - 3, cy - 2, cx + 4, cy + 3], fill=(250, 250, 245), outline=(30, 30, 30))
    fn = font(20)
    for v in d.get("villages", []):
        x, y, w, h = v["rect"]; a, b = tp(x, y)
        dr.rectangle([a - 2, b - 2, a + w * PX + 1, b + h * PX + 1], outline=(70, 50, 20), width=2, fill=(255, 245, 215, 110))
        if labels:
            s = v["name"]
            tw = dr.textlength(s, font=fn) + 12
            cx = a + w * PX / 2
            fy = min([tp(f["rect"][0], f["rect"][1])[1] for f in d.get("farms", []) if f["village"] == v["id"]] + [b])
            ly = min(b, fy) - 30
            # 0.4.0 collision-aware: try above, below, right, left of the village box
            # so no city box (Highfen) or other label covers it (Oxley)
            bot = b + h * PX + 4
            cands = [(cx - tw / 2, ly), (cx - tw / 2, bot), (a + w * PX + 8, b), (a - tw - 8, b),
                     (cx - tw / 2, ly - 30), (cx - tw / 2, bot + 30)]
            lx, ly2 = cands[0]
            for qx, qy in cands:
                if not any(qx - 4 < x1 and qx + tw + 4 > x0 and qy - 2 < y1 and qy + 28 > y0 for x0, y0, x1, y1 in PLACED):
                    lx, ly2 = qx, qy
                    break
            PLACED.append((lx, ly2, lx + tw, ly2 + 26))
            dr.rectangle([lx, ly2, lx + tw, ly2 + 26], fill=(255, 250, 230, 235), outline=(70, 50, 20), width=2)
            dr.text((lx + 6, ly2 + 2), s, font=fn, fill=(40, 25, 5))

def buildings(dr):
    """0.3.0 walk-in building footprints: dark outline, door marked."""
    col = {"shop": (90, 60, 30), "smithy": (60, 60, 70), "player": (40, 110, 60), "church": (70, 70, 90)}
    for b in d.get("buildings", []):
        x, y, w, h = b["rect"]
        a, c = tp(x, y)
        if b["kind"] == "church":   # 0.3.1 stone church: grey fill + a gold cross on the altar
            dr.rectangle([a, c, a + w * PX - 1, c + h * PX - 1], fill=(150, 150, 158, 230))
        dr.rectangle([a, c, a + w * PX - 1, c + h * PX - 1], outline=col.get(b["kind"], (40, 40, 40)), width=2)
        if b.get("altar"):
            p, q = tc(*b["altar"])
            dr.line([p, q - 5, p, q + 6], fill=(200, 150, 20), width=3); dr.line([p - 4, q - 2, p + 4, q - 2], fill=(200, 150, 20), width=3)
        for dx, dy in b["doors"]:
            p, q = tp(dx, dy)
            dr.rectangle([p, q, p + PX - 1, q + PX - 1], fill=(240, 220, 120))


CAMP_STYLE = {   # 0.3.1 enemy kinds: (shape, fill, outline, label)
    "chicken": ("circle", (250, 220, 70), (90, 70, 10), "Chickens"),
    "giant_rat": ("circle", (255, 255, 255), (20, 20, 20), "Rats"),
    "wolf": ("tri", (120, 120, 130), (20, 20, 20), "Wolves"),
    "goblin": ("diamond", (25, 25, 25), (255, 255, 255), "Goblins"),
    "cinder_brute": ("diamond", (200, 40, 20), (255, 230, 120), "Cinder brutes"),
}

def camp_sym(dr, kind, cx, cy, r):
    shape, fill, out, _ = CAMP_STYLE.get(kind, ("diamond", (25, 25, 25), (255, 255, 255), kind))
    if shape == "circle":
        dr.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill + (235,), outline=out, width=3)
    elif shape == "tri":
        dr.polygon([(cx, cy - r - 2), (cx + r + 2, cy + r), (cx - r - 2, cy + r)], fill=fill + (235,), outline=out)
    else:
        dr.polygon([(cx, cy - r - 2), (cx + r + 2, cy), (cx, cy + r + 2), (cx - r - 2, cy)], fill=fill + (235,), outline=out)

def camps(dr):
    f = font(16)
    for c in d["camps"]:
        x, y = c["at"]
        cx, cy = tc(x, y)
        r = 8
        camp_sym(dr, c["enemy"], cx, cy, r)
        lab = "%s \u00d7%d L%d" % (CAMP_STYLE.get(c["enemy"], (0, 0, 0, c["enemy"]))[3], c["count"], c["level"])
        w = dr.textlength(lab, font=f)
        lx, ly = place_label(cx, cy, r, w, 19)
        dr.rectangle([lx - 3, ly, lx + w + 3, ly + 19], fill=(255, 255, 255, 180))
        dr.text((lx, ly), lab, font=f, fill=(20, 20, 20))

PLACED = []   # label rects already drawn on the current page (avoid overlaps)

def place_label(cx, cy, r, w, h, prefer="side"):
    cands = [(cx + r + 7, cy - 10), (cx - r - 7 - w, cy - 10), (cx - w / 2, cy - r - h - 3), (cx - w / 2, cy + r + 3),
             (cx + r + 7, cy + 8), (cx + r + 7, cy - 28), (cx - r - 7 - w, cy + 8), (cx - r - 7 - w, cy - 28)]
    if prefer == "vertical":
        cands = [cands[3], cands[2]] + cands[:2] + cands[4:]
    def hits(lx, ly):
        return any(lx - 4 < bx1 and lx + w + 4 > bx0 and ly - 2 < by1 and ly + h + 2 > by0 for bx0, by0, bx1, by1 in PLACED)
    for lx, ly in cands:
        if not hits(lx, ly):
            break
    else:
        lx, ly = cands[0]
    PLACED.append((lx, ly, lx + w, ly + h))
    return lx, ly

MINE_STYLE = {   # tier: (colour, label)
    "copper_tin": ((205, 110, 40), "Copper + tin mine (Mining 1)"),
    "iron": ((150, 40, 30), "Iron mine (Mining 12)"),
    "coal": ((30, 30, 30), "Coal mine (Mining 20)"),
    "scorch": ((230, 70, 20), "Scorch deep mine (coal + iron, PK)"),
}

def mines(dr, labels=True):
    f = font(16)
    for m in d.get("mines", []):
        x, y = m["center"]
        cx, cy = tc(x, y)
        col = MINE_STYLE.get(m["tier"], ((90, 90, 90), m["tier"]))[0]
        r = (m["radius"] + 1.5) * PX
        dr.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col + (255,), width=3, fill=col + (40,))
        pick(dr, cx, cy, col)
        if labels:
            n = sum(m["rocks"].values())
            lab = "%s (%d rocks, %d from %s)" % (m["name"], n, round(m["edge_distance"]), m["nearest_town"].capitalize())
            w = dr.textlength(lab, font=f)
            lx, ly = place_label(cx, cy, r, w, 19, prefer="vertical")
            dr.rectangle([lx - 3, ly, lx + w + 3, ly + 19], fill=(255, 255, 255, 200))
            dr.text((lx, ly), lab, font=f, fill=col if m["tier"] != "coal" else (20, 20, 20))

def pick(dr, cx, cy, col):
    """Tiny crossed-picks glyph."""
    dr.line([cx - 6, cy - 6, cx + 6, cy + 6], fill=(255, 255, 255), width=4)
    dr.line([cx - 6, cy + 6, cx + 6, cy - 6], fill=(255, 255, 255), width=4)
    dr.line([cx - 6, cy - 6, cx + 6, cy + 6], fill=col, width=2)
    dr.line([cx - 6, cy + 6, cx + 6, cy - 6], fill=col, width=2)

SCORCH = (200, 50, 20)

def scorch(dr, labels=True):
    """The Scorch (PK + multi-combat): hatched, red dashed boundary."""
    for z in d.get("pk_zones", []):
        x, y, w, h = z["rect"]
        xa, ya, xb, yb = max(x, X0), max(y, Y0), min(x + w, X1), min(y + h, Y1)
        if xa >= xb or ya >= yb:
            continue
        a, b = tp(xa, ya); c, e = tp(xb, yb)
        dr.rectangle([a, b, c, e], fill=SCORCH + (28,))
        for k in range(int(a) - int(e - b), int(c), 22):   # diagonal hatch
            dr.line([k, e, k + (e - b), b], fill=SCORCH + (45,), width=1)
        # dashed outline (only the edges inside the frame)
        def dash(p0, p1):
            (x0_, y0_), (x1_, y1_) = p0, p1
            L = max(abs(x1_ - x0_), abs(y1_ - y0_)); n = int(L // 14)
            for i in range(0, n, 2):
                t0, t1 = i / n, min(1, (i + 1) / n)
                dr.line([x0_ + (x1_ - x0_) * t0, y0_ + (y1_ - y0_) * t0, x0_ + (x1_ - x0_) * t1, y0_ + (y1_ - y0_) * t1], fill=SCORCH, width=4)
        if y + h <= Y1: dash((a, e), (c, e))
        if y >= Y0: dash((a, b), (c, b))
        if x >= X0: dash((a, b), (a, e))
        if x + w <= X1: dash((c, b), (c, e))
        if labels:
            ft, fs = font(30), font(18, False)
            t1 = z["name"].upper()
            t2 = "PK zone + multi-combat \u00b7 everything north of y = %d \u00b7 anyone can attack you" % (y + h - 1)
            lx, ly = tp(-60, Y0 + 6)   # open sea at the top, clear of the camps
            w1 = max(dr.textlength(t1, font=ft), dr.textlength(t2, font=fs))
            dr.rectangle([lx - 8, ly - 4, lx + w1 + 8, ly + 56], fill=(255, 255, 255, 215), outline=SCORCH, width=2)
            dr.text((lx, ly), t1, font=ft, fill=SCORCH)
            dr.text((lx, ly + 34), t2, font=fs, fill=(90, 30, 10))

BRIDGE = (110, 70, 30)

def bridges(dr):
    f = font(16)
    for br in d.get("bridges", []):
        tiles = br.get("tiles", br) if isinstance(br, dict) else br
        for x, y in tiles:
            a, b = tp(x, y)
            dr.rectangle([a - 2, b - 2, a + PX + 1, b + PX + 1], fill=BRIDGE, outline=(255, 240, 200))
        if tiles:
            x, y = tiles[len(tiles) // 2]
            cx, cy = tc(x, y)
            dr.text((cx + 8, cy - 9), "Bridge", font=f, fill=BRIDGE)

def patrols(dr):
    """Town guard patrol routes (blue) + citizens' wander area (dotted)."""
    for n in d.get("town_npcs", []):
        if n["kind"] == "town_guard" and len(n.get("patrol", [])) >= 2:
            pts = [tc(x, y) for x, y in n["patrol"]]
            if len(pts) > 2:
                pts.append(pts[0])
            dr.line(pts, fill=(30, 70, 200, 220), width=2)
            for p in pts:
                dr.ellipse([p[0] - 2, p[1] - 2, p[0] + 2, p[1] + 2], fill=(30, 70, 200))
        elif n["kind"] == "citizen" and "area" in n:
            x, y, w, h = n["area"]
            a, b = tp(x, y); c, e = tp(x + w, y + h)
            dr.rectangle([a, b, c, e], outline=(40, 150, 60, 200), width=1)

def bands_box(dr):
    """Distance bands (tiles from the nearest town edge), innermost first."""
    f, fh = font(17, False), font(20)
    bands = d.get("bands", {})
    order = sorted(bands.items(), key=lambda kv: (kv[1].get("pk_only", False), kv[1]["min"]))
    rows = []
    for k, b in order:
        if b.get("pk_only"):
            txt = "the Scorch only"
        else:
            txt = "%d-%d tiles out%s" % (b["min"], b["max"], " (+ the Scorch)" if b.get("pk") else "")
        rows.append((k, "%s: %s" % (CAMP_STYLE.get(k, (0, 0, 0, k))[3], txt)))
    lh = 26
    bw, bh = 380, 40 + lh * len(rows) + 8
    x0 = ML + MW - bw - 14
    y0 = MT + MH - bh - 14
    dr.rectangle([x0, y0, x0 + bw, y0 + bh], fill=(255, 255, 255, 235), outline=(30, 30, 30), width=2)
    dr.text((x0 + 12, y0 + 8), "Enemy bands (distance from town)", font=fh, fill=(20, 20, 20))
    y = y0 + 40
    for k, lab in rows:
        camp_sym(dr, k, x0 + 24, y + 10, 7)
        dr.text((x0 + 44, y), lab, font=f, fill=(20, 20, 20))
        y += lh

def title(dr, sub):
    dr.text((ML, 14), "Ashfen world map %s" % VERSION, font=font(40), fill=(20, 20, 20))
    dr.text((ML + 520, 30), sub, font=font(18, False), fill=(70, 70, 70))

def compass(dr):
    cx, cy = ML + MW - 60, MT + 80
    dr.ellipse([cx - 40, cy - 40, cx + 40, cy + 40], fill=(255, 255, 255, 200), outline=(30, 30, 30), width=2)
    dr.polygon([(cx, cy - 32), (cx + 13, cy + 10), (cx, cy + 2), (cx - 13, cy + 10)], fill=(30, 30, 30))
    dr.text((cx - 9, cy + 10), "N", font=font(22), fill=(30, 30, 30))

def legend(dr, kind):
    f, fh = font(19, False), font(22)
    rows = []
    sw = lambda col: ("sq", col)
    for n, lab in [("grass", "Grass"), ("dirt", "Dirt / hills"), ("marsh", "Marsh"), ("sand", "Sand / beach"), ("water", "Lake")]:
        rows.append((sw(TILE_COL[meta["tile_names"].index(n)]), lab))
    rows.append((sw(OCEAN), "Ocean (impassable)"))
    if kind != "plain":
        rows.append((("road",), "Road between towns"))
    rows.append((("town",), "Walled city (safe from enemies)"))
    rows.append((sw(GATE_COL), "City gate (roads leave by the gates)"))
    rows.append((sw(TILE_COL[meta["tile_names"].index("ash")]), "Ash (the Scorch)"))
    if kind != "plain":
        rows.append((("scorch",), "The Scorch boundary (PK + multi)"))
        nb = len(d.get("bridges", []))
        rows.append((("bridge",), "Wooden bridge" + ("" if nb else " (none needed this seed)")))
        rows.append((("patrol",), "Town guard patrol route"))
        rows.append((("church",), "Stone church (altar refills Prayer)"))
        rows.append((("village",), "Village (safe; cottages, well, quern)"))
        rows.append((("wheat",), "Wheat field (fenced, regrows)"))
        rows.append((("pasture",), "Cow pasture (fenced, lvl 2 cows)"))
        for k in ["chicken", "giant_rat", "wolf", "goblin", "cinder_brute"]:
            e = next((c for c in d["camps"] if c["enemy"] == k), None)
            if e:
                rows.append((("camp", k), "%s camp (lvl %d)" % (CAMP_STYLE[k][3], e["level"])))
        for t, (col, lab) in MINE_STYLE.items():
            rows.append((("mine", col), lab))
    if kind == "res":
        for k, lab in [("ash_tree", "Ash tree (Forestry 1)"), ("alder_tree", "Alder tree (12)"), ("blackthorn_tree", "Blackthorn tree (25)"),
                       ("copper_rock", "Copper rock (Mining 1)"), ("tin_rock", "Tin rock (1)"), ("iron_rock", "Iron rock (12)"),
                       ("coal_rock", "Coal rock (20)"), ("fishing_spot", "Fishing spot"), ("reed_bed", "Reed bed / fenroot")]:
            rows.append((("res", RES_STYLE[k][0]), lab))
    rows.append((("grid",), "Grid: every %d tiles" % GRID))
    lh = 28
    bw, bh = 360, 44 + lh * len(rows) + 30
    x0, y0 = ML + 14, MT + 14
    dr.rectangle([x0, y0, x0 + bw, y0 + bh], fill=(255, 255, 255, 235), outline=(30, 30, 30), width=2)
    dr.text((x0 + 12, y0 + 8), "Legend", font=fh, fill=(20, 20, 20))
    y = y0 + 42
    for sym, lab in rows:
        sx, sy = x0 + 14, y + 3
        if sym[0] == "sq":
            dr.rectangle([sx, sy, sx + 22, sy + 16], fill=sym[1], outline=(90, 90, 90))
        elif sym[0] == "road":
            dr.rectangle([sx, sy + 6, sx + 22, sy + 10], fill=ROAD)
        elif sym[0] == "town":
            dr.rectangle([sx, sy, sx + 22, sy + 16], fill=(255, 255, 255), outline=(20, 20, 20), width=3)
        elif sym[0] == "scorch":
            dr.rectangle([sx, sy, sx + 22, sy + 16], fill=SCORCH + (40,))
            dr.line([sx, sy + 8, sx + 8, sy + 8], fill=SCORCH, width=4); dr.line([sx + 14, sy + 8, sx + 22, sy + 8], fill=SCORCH, width=4)
        elif sym[0] == "bridge":
            dr.rectangle([sx + 2, sy + 4, sx + 20, sy + 12], fill=BRIDGE, outline=(255, 240, 200))
        elif sym[0] == "church":
            dr.rectangle([sx, sy, sx + 22, sy + 16], fill=(150, 150, 158), outline=(70, 70, 90), width=2)
            dr.line([sx + 11, sy + 3, sx + 11, sy + 14], fill=(200, 150, 20), width=3); dr.line([sx + 7, sy + 6, sx + 15, sy + 6], fill=(200, 150, 20), width=3)
        elif sym[0] == "village":
            dr.rectangle([sx, sy, sx + 22, sy + 16], fill=(255, 245, 215), outline=(70, 50, 20), width=2)
        elif sym[0] == "wheat":
            dr.rectangle([sx, sy, sx + 22, sy + 16], fill=WHEAT, outline=FENCE, width=2)
        elif sym[0] == "pasture":
            dr.rectangle([sx, sy, sx + 22, sy + 16], fill=PASTURE, outline=FENCE, width=2)
            dr.ellipse([sx + 8, sy + 5, sx + 15, sy + 11], fill=(250, 250, 245), outline=(30, 30, 30))
        elif sym[0] == "patrol":
            dr.line([sx, sy + 8, sx + 22, sy + 8], fill=(30, 70, 200), width=2)
        elif sym[0] == "camp":
            camp_sym(dr, sym[1], sx + 11, sy + 8, 7)
        elif sym[0] == "mine":
            dr.ellipse([sx + 2, sy - 1, sx + 20, sy + 17], outline=sym[1], width=3, fill=sym[1] + (40,))
            pick(dr, sx + 11, sy + 8, sym[1])
        elif sym[0] == "rat":
            dr.ellipse([sx + 3, sy - 1, sx + 21, sy + 17], fill=(255, 255, 255), outline=(20, 20, 20), width=3)
        elif sym[0] == "gob":
            c = (sx + 12, sy + 8)
            dr.polygon([(c[0], c[1] - 11), (c[0] + 11, c[1]), (c[0], c[1] + 11), (c[0] - 11, c[1])], fill=(25, 25, 25), outline=(255, 255, 255))
        elif sym[0] == "res":
            dr.rectangle([sx + 6, sy + 3, sx + 16, sy + 13], fill=sym[1])
        elif sym[0] == "grid":
            dr.line([sx, sy + 8, sx + 22, sy + 8], fill=(40, 40, 40, 110)); dr.line([sx + 11, sy - 2, sx + 11, sy + 18], fill=(40, 40, 40, 110))
        dr.text((sx + 32, y), lab, font=f, fill=(20, 20, 20))
        y += lh
    dr.text((x0 + 12, y + 2), "1 tile = %d px \u00b7 coords = in-game HUD (x, y)" % PX, font=font(16, False), fill=(60, 60, 60))

def build(kind, name, sub):
    PLACED.clear()
    for t in d["towns"]:   # reserve the town label boxes (drawn later, right of the town)
        x, y, w, h = t["rect"]
        a, b = tp(x + w, y)
        PLACED.append((a + 6, b + h * PX / 2 - 60, a + 420, b + h * PX / 2 + 60))
        a0, b0 = tp(x, y)
        PLACED.append((a0 - 4, b0 - 4, a + 4, b0 + h * PX + 4))
    img, dr = base(resources=(kind == "res"))
    grid(img, dr)
    scorch(dr, labels=(kind != "plain"))
    if kind != "plain":
        roads(dr)
        bridges(dr)
        mines(dr, labels=(kind == "main"))
        camps(dr)
    villages(dr, labels=True)
    buildings(dr)
    if kind != "plain":
        patrols(dr)
    towns(dr, shops=(kind != "plain"))
    legend(dr, kind)
    if kind != "plain":
        bands_box(dr)
    compass(dr)
    title(dr, sub)
    p = os.path.join(OUT, name)
    img.save(p, optimize=True)
    print(p, img.size, os.path.getsize(p))

build("main", "ashfen_world_map.png", "seed %d \u00b7 towns, roads, mines, enemy bands, the Scorch \u00b7 mark it up!" % meta["seed"])
build("res", "ashfen_world_map_resources.png", "seed %d \u00b7 with resource nodes (trees, rocks, fishing)" % meta["seed"])
build("plain", "ashfen_world_map_plain.png", "seed %d \u00b7 terrain, grid and towns only" % meta["seed"])
