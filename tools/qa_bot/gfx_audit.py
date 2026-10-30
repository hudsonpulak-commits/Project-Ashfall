#!/usr/bin/env python3
"""gfx audit detectors over a gfxaudit run: black/near-black tile boxes, clear-colour
holes, z-order violations (from scene data) and long straight terrain boundaries.
usage: gfx_audit.py RUN_DIR OUT_DIR"""
import json, glob, os, sys
from PIL import Image

CLEAR = (18, 22, 15)
DARK_OK = {"cobble_dark", "basalt_front", "gate_basalt", "cliff_face", "cliff_shadow", "water", "moat", "ash", "ash_edge", "floor", "doorway"}
STRAIGHT_OK = ("wall", "road", "gate", "front", "palisade", "bridge", "doorway", "floor", "planks", "boardwalk", "cliff")


def lum(c):
    return (0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]) / 255.0


def main(run, out):
    os.makedirs(out + "/crops", exist_ok=True)
    rep = {"black": [], "holes": [], "zviol": [], "straight": []}
    seen_straight = set()
    for jf in sorted(glob.glob(run + "/gfx/*.json")):
        d = json.load(open(jf))
        name = d["name"]
        png = run + "/snaps/" + name + ".png"
        if not os.path.exists(png):
            continue
        im = Image.open(png).convert("RGB")
        W, H = im.size
        sx, sy, ox, oy = d["xform"]
        tp = d["tile_px"]
        night = "night" in name
        cells = {(c[0], c[1]): c for c in d["cells"]}
        pix = im.load()
        means = {}
        for (x, y), c in cells.items():
            x0 = int(x * tp * sx + ox); y0 = int(y * tp * sy + oy)
            s = int(tp * sx)
            if x0 < 0 or y0 < 60 or x0 + s > W or y0 + s > H - 140:   # skip HUD bands
                continue
            tot = 0.0; n = 0; clear = 0
            for yy in range(y0, y0 + s, 2):
                for xx in range(x0, x0 + s, 2):
                    p = pix[xx, yy]; tot += lum(p); n += 1
                    if abs(p[0] - CLEAR[0]) <= 2 and abs(p[1] - CLEAR[1]) <= 2 and abs(p[2] - CLEAR[2]) <= 2:
                        clear += 1
            means[(x, y)] = (tot / max(1, n), (x0, y0, s))
            if clear > n * 0.3:
                rep["holes"].append({"snap": name, "tile": [x, y], "base": c[2], "ov": c[3], "frac": round(clear / n, 2), "box": [x0, y0, s]})
        if not night:
            for (x, y), (m, box) in means.items():
                c = cells[(x, y)]
                if c[2] in DARK_OK or m > 0.13:
                    continue
                nbm = [means[q][0] for q in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] if q in means]
                if len(nbm) >= 3 and sorted(nbm)[len(nbm) // 2] > 0.24:
                    rep["black"].append({"snap": name, "tile": [x, y], "base": c[2], "ov": c[3], "obj": c[4], "lum": round(m, 3), "nb": round(sorted(nbm)[len(nbm) // 2], 3), "box": list(box)})
        for v in d["zviol"]:
            v["snap"] = name
            rep["zviol"].append(v)
        # straight boundaries: runs > 6 of the same (a|b) pair along a row or column edge
        for (x, y), c in cells.items():
            for dx, dy, ax in [(1, 0, "v"), (0, 1, "h")]:
                q = (x + dx, y + dy)
                if q not in cells:
                    continue
                a, b = c[2], cells[q][2]
                if a == b or any(k in a or k in b for k in STRAIGHT_OK):
                    continue
                # start of a run only
                px_, py_ = (x, y - 1) if ax == "v" else (x - 1, y)
                pq = (px_ + dx, py_ + dy)
                if (px_, py_) in cells and pq in cells and cells[(px_, py_)][2] == a and cells[pq][2] == b:
                    continue
                L = 0; cx, cy = x, y
                while (cx, cy) in cells and (cx + dx, cy + dy) in cells and cells[(cx, cy)][2] == a and cells[(cx + dx, cy + dy)][2] == b:
                    L += 1
                    if ax == "v": cy += 1
                    else: cx += 1
                key = (x, y, ax)
                if L > 6 and key not in seen_straight:
                    seen_straight.add(key)
                    rep["straight"].append({"snap": name, "tile": [x, y], "axis": ax, "len": L, "pair": [a, b]})
    # crops (first 40 of each)
    for k in ("black", "holes", "zviol"):
        for i, r in enumerate(rep[k][:40]):
            im = Image.open(run + "/snaps/" + r["snap"] + ".png").convert("RGB")
            if "box" in r:
                x0, y0, s = r["box"]; bb = (x0 - s * 2, y0 - s * 2, x0 + s * 3, y0 + s * 3)
            else:
                sx, sy, ox, oy = json.load(open(run + "/gfx/" + r["snap"] + ".json"))["xform"]
                x, y, w, h = r["rect"]; bb = (x * sx + ox - 20, y * sy + oy - 20, (x + w) * sx + ox + 20, (y + h) * sy + oy + 20)
            bb = tuple(int(max(0, v)) for v in bb)
            cp = "%s/crops/%s_%02d_%s.png" % (out, k, i, r["snap"])
            im.crop(bb).save(cp)
            r["crop"] = cp
    json.dump(rep, open(out + "/gfx_report.json", "w"), indent=1)
    print("black %d  holes %d  zviol %d  straight>6 %d" % tuple(len(rep[k]) for k in ("black", "holes", "zviol", "straight")))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
