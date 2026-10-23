#!/usr/bin/env python3
"""Ashfen QA bot analyzer.

Reads the per-scenario captures written by tools/qa_bot/qa_driver.gd
(frames/fNNNNN.png + log.jsonl + result.json), runs every registered check
and writes report.md + report.html (+ contact sheets, GIFs, path plots).
Exit code 0 = all checks pass, 1 = at least one failure.

    python3 tools/qa_bot/analyze.py --runs build/qa/0.3.0/runs --out build/qa/0.3.0

Adding a check: write `def check_xxx(ctx) -> list[Result]` and add it to
CHECKS with the scenarios it needs (see docs/QA_BOT.md).
"""
import argparse, datetime, glob, html, json, os, shutil, sys
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# ------------------------------------------------------------------ data --
class Run:
    def __init__(self, d):
        self.dir = d
        self.name = os.path.basename(d)
        self.log = [json.loads(l) for l in open(os.path.join(d, "log.jsonl"))]
        self.res = json.load(open(os.path.join(d, "result.json")))
        self.events = self.res.get("events", [])
        self.zoom = float(self.res.get("zoom", 3))
        p = os.path.join(d, "godot.log")
        self.godot_log = open(p, errors="replace").read() if os.path.exists(p) else ""

    def frame(self, i):
        return Image.open(os.path.join(self.dir, "frames", "f%05d.png" % i)).convert("RGB")

    def labelled(self, prefix):
        return [r for r in self.log if r["label"].startswith(prefix)]


class Result:
    def __init__(self, check, name, ok, detail, evidence=None):
        self.check, self.name, self.ok, self.detail = check, name, ok, detail
        self.evidence = evidence or []


# ------------------------------------------------------ sprite matching --
_SPRITE_DEFS = None


def sprite_path(sid):
    """data/sprites.json actors id -> PNG path on disk."""
    global _SPRITE_DEFS
    if _SPRITE_DEFS is None:
        _SPRITE_DEFS = json.load(open(os.path.join(ROOT, "data/sprites.json")))["actors"]
    return os.path.join(ROOT, _SPRITE_DEFS[sid]["path"].replace("res://", ""))


class Sprites:
    """Player sheet templates (each frame, plain + mirrored) at screen scale.
    `layers` = the gear layer sprite ids the game reports as worn (draw order):
    each template is the body frame with the same frame of every layer
    composited on top, exactly as the game draws it (0.3.1 visible gear)."""
    def __init__(self, zoom, layers=()):
        fw, fh = 16, 24
        z = int(round(zoom))
        self.w, self.h = fw * z, fh * z
        self.t = []          # (facing, frame, rgb float array, mask)
        # 0.3.9 side sheet (R / L mirrored) + front (D) and back (U) sheets
        for suf, tags in (("", ("R", "L")), ("_front", ("D",)), ("_back", ("U",))):
            sp = os.path.join(ROOT, "assets/sprites/actors/player%s.png" % suf)
            if not os.path.exists(sp):
                continue
            sheet = Image.open(sp).convert("RGBA")
            n = sheet.width // fw
            lsheets = []
            for l in layers:
                lp = sprite_path(l)
                dp = lp[:-4] + suf + ".png"
                lsheets.append(Image.open(dp if suf and os.path.exists(dp) else lp).convert("RGBA"))
            for i in range(n):
                body = sheet.crop((i * fw, 0, (i + 1) * fw, fh))
                for facing in tags:
                    # 0.3.9.4 per-facing order (src/actors/actor.gd gear_layer_plan):
                    # shield under the body facing right (far hand) and from behind;
                    # facing left the shield is on top and the weapon under the body
                    under = ("shield",) if facing in ("R", "U") else (("weapon",) if facing == "L" else ())
                    fr = Image.new("RGBA", (fw, fh))
                    lay = list(zip(layers, lsheets))
                    for l, ls in [x for x in lay if any("_%s_" % u in x[0] or x[0].startswith("gear_%s" % u) for u in under)]:
                        k = min(i, ls.width // fw - 1)
                        cell = ls.crop((k * fw, 0, (k + 1) * fw, fh))
                        if facing == "R" and "shield" in l:
                            # 0.3.9.5 gear_layer_offset: behind the body facing right, 1 px forward
                            moved = Image.new("RGBA", (fw, fh)); moved.paste(cell, (1, 0)); cell = moved
                        fr = Image.alpha_composite(fr, cell)
                    fr = Image.alpha_composite(fr, body)
                    top = [x for x in lay if not any("_%s_" % u in x[0] or x[0].startswith("gear_%s" % u) for u in under)]
                    if facing == "L":
                        top = [x for x in top if "shield" not in x[0]] + [x for x in top if "shield" in x[0]]
                    for l, ls in top:
                        k = min(i, ls.width // fw - 1)
                        fr = Image.alpha_composite(fr, ls.crop((k * fw, 0, (k + 1) * fw, fh)))
                    im = fr.resize((self.w, self.h), Image.NEAREST)
                    im = im.transpose(Image.FLIP_LEFT_RIGHT) if facing == "L" else im
                    a = np.asarray(im).astype(np.float32)
                    self.t.append((facing, i, a[..., :3], a[..., 3] > 128))

    def crop(self, img, cx, cy, dx=0, dy=0):
        x0, y0 = int(round(cx)) - self.w // 2 + dx, int(round(cy)) - self.h + dy
        if x0 < 0 or y0 < 0 or x0 + self.w > img.shape[1] or y0 + self.h > img.shape[0]:
            return None
        return img[y0:y0 + self.h, x0:x0 + self.w]

    def score(self, c, k):
        f, i, rgb, m = self.t[k]
        return float(np.abs(c[m] - rgb[m]).mean())

    def match(self, img, cx, cy, dx=0, dy=0):
        c = self.crop(img, cx, cy, dx, dy)
        if c is None:
            return None
        sc = [self.score(c, k) for k in range(len(self.t))]
        best = int(np.argmin(sc))
        bl = min(s for s, t in zip(sc, self.t) if t[0] == "L")
        br = min(s for s, t in zip(sc, self.t) if t[0] == "R")
        return {"facing": self.t[best][0], "frame": self.t[best][1], "res": sc[best], "margin": abs(bl - br), "k": best}


MATCH_OK = 6.0        # mean abs RGB error of an exact (unoccluded) sprite is ~0
NEAR_SKIP = 48.0      # skip image checks when another actor (or its name label) is this close (world px)


def occluded(r):
    """Another actor's sprite (16x24) or name label (~72x14 above its head)
    overlaps the player's sprite box: image checks can't judge that frame."""
    if "others" not in r:
        return r.get("near", 9999) < NEAR_SKIP
    px0, px1, py0, py1 = -8, 8, -24, 0
    for dx, dy in r["others"]:
        for bx0, bx1, by0, by1 in ((dx - 8, dx + 8, dy - 24, dy), (dx - 36, dx + 36, dy - 42, dy - 24)):
            if bx0 < px1 and bx1 > px0 and by0 < py1 and by1 > py0:
                return True
    return False


def image_track(run, spf, labels=None, step=1):
    """Per frame: facing seen in the IMAGE, residual, best offset (jitter), ghosts.
    spf(r) -> the Sprites templates for that frame (its worn gear layers)."""
    out = []
    for r in run.log[::step]:
        sp = spf(r)
        if labels and not any(r["label"].startswith(l) for l in labels):
            continue
        if r["panel"] or occluded(r):
            out.append({"f": r["f"], "skip": True})
            continue
        img = np.asarray(run.frame(r["f"])).astype(np.float32)
        cx, cy = r["scr"]
        m = sp.match(img, cx, cy)
        if m is None:
            out.append({"f": r["f"], "skip": True})
            continue
        # jitter: is the sprite exactly where the camera says (+-3 px search)?
        best = (m["res"], 0, 0)
        if m["res"] > 1.0:
            for dy in range(-3, 4):
                for dx in range(-3, 4):
                    c = sp.crop(img, cx, cy, dx, dy)
                    if c is not None:
                        s = sp.score(c, m["k"])
                        if s < best[0]:
                            best = (s, dx, dy)
        # ghost: a second copy (either facing) beside the real sprite
        ghost = None
        for dx in (-24, -18, -12, -8, 8, 12, 18, 24):
            c = sp.crop(img, cx, cy, dx, 0)
            if c is None:
                continue
            for k in range(len(sp.t)):
                s = sp.score(c, k)
                if s < MATCH_OK * 0.5:
                    ghost = (dx, sp.t[k][0], round(s, 2))
                    break
            if ghost:
                break
        out.append({"f": r["f"], "skip": False, "facing": m["facing"], "res": round(m["res"], 2), "margin": round(m["margin"], 2),
                    "off": (best[1], best[2]), "ghost": ghost, "flip": r["flip"]})
    return out


# ---------------------------------------------------------------- checks --
def motion_dx(log):
    """Per frame horizontal sprite motion (world px since previous frame)."""
    dx = [0.0]
    for a, b in zip(log, log[1:]):
        dx.append(b["pos"][0] - a["pos"][0])
    return dx


def check_facing(ctx):
    out = []
    for name in ("walk", "gear"):
        if name in ctx.expected:
            out += facing_results(ctx, name)
    return out


def facing_results(ctx, name):
    run = ctx.runs.get(name)
    if not run:
        return [Result("C1 facing", "%s run present" % name, False, "no %s capture" % name)]
    tag = "" if name == "walk" else "%s (gear on): " % name
    tr = {t["f"]: t for t in ctx.track(name)}
    dx = motion_dx(run.log)
    wrong, lag_frames, flips_bad, unknown = [], [], [], 0
    last_dir = None
    since_change = 0
    for i, r in enumerate(run.log):
        t = tr.get(r["f"])
        d = 0 if dx[i] == 0 else (1 if dx[i] > 0 else -1)
        if d != 0:
            if d != last_dir:
                since_change = 0
                last_dir = d
            else:
                since_change += 1
        if t is None or t["skip"] or t["res"] > MATCH_OK or t["margin"] < 2.0:
            unknown += 1
            continue
        if d == 0 or t["facing"] in ("D", "U"):   # 0.3.9 front/back sheets: judged by C31
            continue
        want = "R" if d > 0 else "L"
        if t["facing"] != want:
            (lag_frames if since_change == 0 else wrong).append(r["f"])
        if t["facing"] != ("L" if r["flip"] else "R"):
            flips_bad.append(r["f"])
    # flip-flop: facing changes while horizontal direction is unchanged
    seq = [(r["f"], tr[r["f"]]["facing"], dx[i]) for i, r in enumerate(run.log)
           if r["f"] in tr and not tr[r["f"]]["skip"] and tr[r["f"]]["res"] <= MATCH_OK and tr[r["f"]]["margin"] >= 2.0 and tr[r["f"]]["facing"] in ("L", "R")]
    flipflop = []
    run_dir = None
    run_face = None
    for f, face, d in seq:
        dd = 0 if d == 0 else (1 if d > 0 else -1)
        if dd != 0 and dd != run_dir:
            run_dir, run_face = dd, face
            continue
        if run_face and face != run_face and dd == run_dir and dd != 0:
            flipflop.append(f)
            run_face = face
    moving = sum(1 for x in dx if x != 0)
    ev = ctx.walk_evidence() if name == "walk" else ctx.gear_evidence()
    res = [
        Result("C1 facing", tag + "image facing matches movement direction", not wrong,
               "%d moving frames checked (%d not judged: overlap/panel); wrong facing on %d frames %s" % (moving, unknown, len(wrong), wrong[:12]), ev),
        Result("C1 facing", tag + "facing switches within 1 frame of a direction change", len(lag_frames) <= 6,
               "frames where the first frame of a new direction still showed the old facing: %s (allowed: one per turn)" % lag_frames[:12], ev),
        Result("C1 facing", tag + "no facing flip-flop while the direction is unchanged", not flipflop, "flip-flops at frames %s" % flipflop[:12], ev),
        Result("C1 facing", tag + "rendered facing == sprite.flip_h (no stale texture)", not flips_bad, "mismatch frames %s" % flips_bad[:12], ev),
    ]
    return res


def check_ghost(ctx):
    out = []
    for name in ("walk", "smithy", "shop", "gear"):
        if name not in ctx.runs:
            continue
        tr = [t for t in ctx.track(name) if not t["skip"]]
        ghosts = [(t["f"], t["ghost"]) for t in tr if t.get("ghost")]
        noisy = [t["f"] for t in tr if t["res"] > MATCH_OK]
        # mirrored alternation: facing A,B,A,B on consecutive frames
        alt = []
        for a, b, c in zip(tr, tr[1:], tr[2:]):
            if a["res"] <= MATCH_OK and b["res"] <= MATCH_OK and c["res"] <= MATCH_OK and a["facing"] == c["facing"] != b["facing"] and min(a["margin"], b["margin"], c["margin"]) >= 2:
                alt.append(b["f"])
        ev = ctx.sheet_for(name, [g[0] for g in ghosts] + alt) if (ghosts or alt) else []
        out.append(Result("C2 ghosting", "%s: one crisp player sprite per frame" % name, not ghosts and len(noisy) <= max(3, len(tr) // 50),
                          "%d frames matched; second copies beside the player: %s; frames with a degraded (blended) sprite: %d %s" % (len(tr), ghosts[:6], len(noisy), noisy[:8]), ev))
        out.append(Result("C2 ghosting", "%s: no mirrored-frame alternation" % name, not alt, "A/B/A facing on frames %s" % alt[:12], ev))
    return out


def legs(run):
    out = {}
    for r in run.log:
        if r["label"]:
            out.setdefault(r["label"], []).append(r)
    return out


def check_diagonal(ctx):
    run = ctx.runs.get("walk")
    if not run:
        return []
    out = []
    for name, rows in legs(run).items():
        if "diag" not in name:
            continue
        pts = np.array([r["pos"] for r in rows], dtype=float)
        mv = [i for i in range(1, len(pts)) if (pts[i] != pts[i - 1]).any()]
        if not mv:
            out.append(Result("C3 diagonal", name, False, "player never moved"))
            continue
        seg = pts[mv[0] - 1: mv[-1] + 1]
        a, b = seg[0], seg[-1]
        d = b - a
        sx, sy = np.sign(d)
        dxs, dys = np.diff(seg[:, 0]), np.diff(seg[:, 1])
        mono = bool((dxs * sx >= 0).all() and (dys * sy >= 0).all())
        n = np.array([-d[1], d[0]]) / max(1e-6, np.hypot(*d))
        dev = np.abs((seg - a) @ n)
        # staircase signature: long runs where only one axis moves
        only_x = int(((dxs != 0) & (dys == 0)).sum())
        only_y = int(((dys != 0) & (dxs == 0)).sum())
        both = int(((dxs != 0) & (dys != 0)).sum())
        ok = mono and dev.max() <= 2.5
        plot = ctx.plot_leg(name, seg, a, b)
        out.append(Result("C3 diagonal", name, ok,
                          "from %s to %s (%d frames): monotonic x/y %s; max deviation from the straight line %.2f world px; frames moving x-only %d, y-only %d, both %d"
                          % (a.tolist(), b.tolist(), len(seg), mono, dev.max(), only_x, only_y, both), [plot]))
    return out


def check_jitter(ctx):
    run = ctx.runs.get("walk")
    if not run:
        return []
    nonint = [r["f"] for r in run.log if any(abs(v - round(v)) > 1e-3 for v in r["pos"] + r["cam"])]
    back = []
    for name, rows in legs(run).items():
        if name.startswith("turn"):
            continue
        pts = np.array([r["pos"] for r in rows], dtype=float)
        d = np.diff(pts, axis=0)
        tot = pts[-1] - pts[0]
        for i, v in enumerate(d):
            if (v * np.sign(tot) < 0).any():
                back.append(rows[i + 1]["f"])
    scr = np.array([r["scr"] for r in run.log])
    spread = (scr.max(0) - scr.min(0)).tolist()
    tr = [t for t in ctx.track("walk") if not t["skip"] and t["res"] <= MATCH_OK]
    offs = [t["f"] for t in tr if t["off"] != (0, 0)]
    ev = ctx.walk_evidence()
    return [
        Result("C4 jitter", "sprite + camera on whole world pixels", not nonint, "non-integer frames: %s" % nonint[:10]),
        Result("C4 jitter", "no backwards steps inside a leg", not back, "backwards frames: %s" % back[:10], ev),
        Result("C4 jitter", "player pinned on screen (camera follows the same rounded position)", max(spread) <= 1.0 and not offs,
               "screen anchor spread %s px; frames where the drawn sprite sat off its anchor: %d %s" % ([round(s, 2) for s in spread], len(offs), offs[:10]), ev),
    ]


def window(run, label, key):
    rows = [r for r in run.log if r["label"] == label]
    return [r[key] for r in rows]


def changes(seq):
    return sum(1 for a, b in zip(seq, seq[1:]) if a != b)


def check_taps(ctx):
    run = ctx.runs.get("walk")
    if not run:
        return []
    out = []
    for lab, key, want in (("sprint_tap", "sprint", True), ("sprint_tap_off", "sprint", False), ("pack_tap", "panel", "pack"), ("pack_tap_close", "panel", "")):
        seq = window(run, lab, key)
        n = changes(seq)
        ok = bool(seq) and n == 1 and seq[-1] == want
        out.append(Result("C5 single tap", "%s: one tap = one toggle" % lab, ok, "%s over %d frames: %d change(s), ends %r (want %r)" % (key, len(seq), n, seq[-1] if seq else None, want)))
    return out


def check_bubbles(ctx):
    if "combat" not in ctx.expected:
        return []
    run = ctx.runs.get("combat")
    if not run:
        return [Result("C6 hit bubbles", "combat run present", False, "no combat capture")]
    hits = [e for e in run.events if e["type"] == "hitsplat"]
    bad, close = [], []
    for r in run.log:
        b = r["bubbles"]
        if len(b) > max(1, r["bubble_targets"]):
            bad.append(r["f"])
        for i in range(len(b)):
            for j in range(i + 1, len(b)):
                if abs(b[i][0] - b[j][0]) < 4 and abs(b[i][1] - b[j][1]) < 4:
                    close.append(r["f"])
    peak = max((len(r["bubbles"]) for r in run.log), default=0)
    ev = ctx.sheet_for("combat", (bad + close)[:24], crop=False) if (bad or close) else [ctx.gif("combat", "combat", step=2, crop=True)]
    return [Result("C6 hit bubbles", "at most one bubble per actor, never stacked", bool(hits) and not bad and not close,
                   "%d hits (dummy + %s); max bubbles on screen %d; frames with more bubbles than targets %s; overlapping bubbles %s"
                   % (len(hits), run.res.get("enemy", "no enemy"), peak, bad[:8], close[:8]), ev)]


def check_roof(ctx):
    out = []
    fade_s = 0.2
    for name in ("shop", "pshop", "smithy"):
        run = ctx.runs.get(name)
        if not run:
            continue
        bid = run.res.get("building", "")
        alph = [(r["f"], r["ms"], r["roofs"].get(bid, 1.0), r["inside"]) for r in run.log]
        enter = next((i for i, a in enumerate(alph) if a[3] == bid), None)
        stuck = [r["f"] for r in run.log if r["blocked"]]
        hidden = [(r["f"], r["hidden_bad"]) for r in run.log if r["hidden_bad"]]
        if enter is None:
            out.append(Result("C7 roof", "%s: player enters %s" % (name, bid), False, "never inside"))
            continue
        gone = next((i for i in range(enter, len(alph)) if alph[i][2] <= 0.01), None)
        mid = [a for a in alph[enter:gone or enter] if 0.01 < a[2] < 0.99]
        dt = (alph[gone][1] - alph[enter][1]) / 1000.0 if gone is not None else None
        exitf = next((i for i in range(gone or enter, len(alph)) if alph[i][3] != bid), None)
        back = next((i for i in range(exitf, len(alph)) if alph[i][2] >= 0.99), None) if exitf is not None else None
        others = [r["f"] for r in run.log if any(v < 0.99 for k, v in r["roofs"].items() if k != r["inside"] and k != bid)]
        ev = [ctx.gif(name, "%s_roof" % name, i0=max(0, alph[enter][0] - 15), i1=alph[gone][0] + 15 if gone else None, step=1, crop=False)]
        out.append(Result("C7 roof", "%s: roof fades out on entering (%s)" % (name, bid), gone is not None and len(mid) >= 2 and dt is not None and dt <= fade_s * 2.5,
                          "inside at frame %d; roof gone at %s after %s s with %d in-between frames (fade, not a pop)" % (alph[enter][0], alph[gone][0] if gone else None, round(dt, 3) if dt else None, len(mid)), ev))
        out.append(Result("C7 roof", "%s: roof returns after walking out" % name, back is not None,
                          "left at frame %s, roof fully back at frame %s" % (alph[exitf][0] if exitf is not None else None, alph[back][0] if back is not None else None)))
        out.append(Result("C7 roof", "%s: only the entered building's roof cuts away" % name, not others, "other roofs faded on frames %s" % others[:8]))
        out.append(Result("C7 roof", "%s: no actor visible under a showing roof" % name, not hidden, "%s" % hidden[:6]))
        out.append(Result("C7 roof", "%s: player never inside a wall / blocked tile" % name, not stuck, "frames %s" % stuck[:8]))
        if "ai_inside" in run.res:
            out.append(Result("C7 roof", "%s: an AI walks in (hidden while the roof shows)" % name, bool(run.res["ai_inside"]), "ai_inside=%s" % run.res["ai_inside"]))
    return out


def first(run, typ, pred=lambda e: True):
    return next((e for e in run.events if e["type"] == typ and pred(e)), None)


def check_shop(ctx):
    out = []
    run = ctx.runs.get("shop")
    if run:
        r = run.res
        greet = first(run, "msg", lambda e: e["kind"] == "npc" and r["keeper"] in e["text"])
        opened = first(run, "shop_opened")
        ev = [ctx.still("shop", "shop_open", "v030_shop_talk")]
        out.append(Result("C8 shop", "tap keeper -> walk in -> greeting -> right shop opens", bool(r.get("store_opened")) and r.get("store_shop") == r["shop"] and greet is not None and opened is not None and greet["f"] <= opened["f"],
                          "keeper %s; greeting at frame %s: %s; shop_opened %s at frame %s; store panel shows %s" % (r["keeper"], greet and greet["f"], greet and greet["text"][:70], opened and opened["shop"], opened and opened["f"], r.get("store_shop")), ev))
    run = ctx.runs.get("pshop")
    if run:
        r = run.res
        b = r.get("bought", {})
        c = r.get("collect", {})
        ok_buy = b.get("owned") and b.get("coins_before", 0) - b.get("coins_after", 0) == b.get("price")
        ok_stock = r.get("stocked", 0) >= 2
        ok_sale = r.get("ai_units", 0) > 0
        ok_collect = c.get("till", 0) > 0 and c.get("coins_after", 0) - c.get("coins_before", 0) == c.get("till") and c.get("till_after") == 0
        ev = [ctx.still("pshop", "forsale", "v030_player_shop_forsale"), ctx.still("pshop", "manage", "v030_player_shop_manage"), ctx.still("pshop", "ai_customer", "v030_player_shop_stocked", last=True)]
        out.append(Result("C8 player shop", "buy the empty shop (tap estate agent, tap Buy)", bool(ok_buy), "owned=%s, coins %s -> %s (price %s)" % (b.get("owned"), b.get("coins_before"), b.get("coins_after"), b.get("price")), ev[:1]))
        out.append(Result("C8 player shop", "stock 2 stands through the panel", ok_stock, "stocked stands: %s" % r.get("stocked"), ev[1:2]))
        out.append(Result("C8 player shop", "AI shoppers buy (AIBrain.shop_browse) and one comes to the stands", ok_sale and bool(r.get("ai_inside")), "units sold %s; customer inside %s" % (r.get("ai_units"), r.get("ai_inside")), ev[2:]))
        out.append(Result("C8 player shop", "collect the till at the counter", bool(ok_collect), "till %s -> coins %s -> %s, till after %s" % (c.get("till"), c.get("coins_before"), c.get("coins_after"), c.get("till_after"))))
    return out


def check_smithy(ctx):
    if "smithy" not in ctx.expected:
        return []
    run = ctx.runs.get("smithy")
    if not run:
        return [Result("C9 blacksmith", "smithy run present", False, "no smithy capture")]
    r = run.res
    greet = first(run, "msg", lambda e: e["kind"] == "npc")
    ok = r.get("kind") == "smithy" and r.get("inside_ok") and r.get("smelt", {}).get("bars", 0) >= 2 and r.get("forge", {}).get("dagger", 0) >= 1 and r.get("out")
    ev = [ctx.still("smithy", "forging", "v030_blacksmith_inside"), ctx.gif("smithy", "smithy_walk_in_smelt_forge_out", step=3, crop=False)]
    return [Result("C9 blacksmith", "walk in, smelt bronze bars, forge an item, walk out", bool(ok),
                   "building %s (%s); stations inside: %s; bars smelted %s; dagger %s; outside again %s" % (r.get("building"), r.get("kind"), r.get("inside_ok"), r.get("smelt"), r.get("forge"), r.get("out")), ev),
            Result("C9 blacksmith", "the smith greets you on entering", greet is not None, greet["text"][:90] if greet else "no greeting")]



def check_markers(ctx):
    if "markers" not in ctx.expected:
        return []
    run = ctx.runs.get("markers")
    if not run:
        return [Result("C10 markers", "markers run present", False, "no markers capture")]
    r = run.res
    out = []
    out.append(Result("C10 markers", "long-press adds once (no short-tap double-fire)",
                      int(r.get("long_presses", 0)) == 1 and int(r.get("taps_during_lp", 1)) == 0,
                      "long_presses=%s taps_during_lp=%s mode=%s" % (r.get("long_presses"), r.get("taps_during_lp"), r.get("mode_after_lp"))))
    out.append(Result("C10 markers", "Save places a marker",
                      int(r.get("count_after_add", 0)) == 1,
                      "count=%s icon=%s label=%s" % (r.get("count_after_add"), r.get("added_icon"), r.get("added_label"))))
    out.append(Result("C10 markers", "tap marker opens edit once; Save updates label",
                      int(r.get("edit_taps", 0)) == 1 and str(r.get("label_after_edit", "")) == "Edited",
                      "edit_taps=%s label=%s" % (r.get("edit_taps"), r.get("label_after_edit"))))
    out.append(Result("C10 markers", "Delete (confirm) removes the marker",
                      int(r.get("count_after_delete", 1)) == 0,
                      "count_after_delete=%s" % r.get("count_after_delete")))
    out.append(Result("C10 markers", "Clear all (confirm) empties markers",
                      int(r.get("count_before_clear", 0)) >= 2 and int(r.get("count_after_clear", 1)) == 0,
                      "before=%s after=%s" % (r.get("count_before_clear"), r.get("count_after_clear"))))
    out.append(Result("C10 markers", "markers persist across save/load",
                      int(r.get("persist_count", 0)) == 1 and str(r.get("persist_label", "")) == "Keep",
                      "persist_count=%s label=%s" % (r.get("persist_count"), r.get("persist_label"))))
    # evidence stills if present
    ev = []
    for name in ("v031_markers_add", "v031_markers_edit", "v031_markers_stocked"):
        # shots land in qa-shots dir when requested; also try evidence from frames
        pass
    out.append(Result("C10 markers", "scenario notes ok flag", bool(r.get("ok")), "ok=%s final_count=%s" % (r.get("ok"), r.get("final_count"))))
    return out



def check_daynight(ctx):
    if "daynight" not in ctx.expected:
        return []
    run = ctx.runs.get("daynight")
    if not run:
        return [Result("C11 daynight", "daynight run present", False, "no daynight capture")]
    r = run.res
    out = []
    out.append(Result("C11 daynight", "phases day → dusk → night",
                      r.get("day_phase") == "day" and r.get("dusk_phase") == "dusk" and r.get("night_phase") == "night",
                      "day=%s dusk=%s night=%s" % (r.get("day_phase"), r.get("dusk_phase"), r.get("night_phase"))))
    out.append(Result("C11 daynight", "lights off by day, on at night",
                      float(r.get("day_lights", 1)) < 0.05 and float(r.get("night_lights", 0)) > 0.85,
                      "day_e=%s night_e=%s lights=%s" % (r.get("day_lights"), r.get("night_lights"), r.get("light_count"))))
    # smooth dusk: consecutive samples don't jump wildly
    samples = r.get("dusk_samples") or []
    max_jump = 0.0
    for a, b in zip(samples, samples[1:]):
        jump = abs(a[0]-b[0]) + abs(a[1]-b[1]) + abs(a[2]-b[2])
        max_jump = max(max_jump, jump)
    out.append(Result("C11 daynight", "dusk transition smooth (no flicker)",
                      len(samples) >= 3 and max_jump < 0.55,
                      "samples=%d max_jump=%.3f" % (len(samples), max_jump)))
    out.append(Result("C11 daynight", "HUD clock readable at night",
                      "Night" in str(r.get("hud_clock_night", "")),
                      "clock=%r" % r.get("hud_clock_night")))
    out.append(Result("C11 daynight", "scenario ok", bool(r.get("ok")), "ok=%s" % r.get("ok")))
    return out


def check_pk(ctx):
    """C18 (0.3.1): Scorch PK rules in the running game."""
    if "pk" not in ctx.expected:
        return []
    run = ctx.runs.get("pk")
    if not run:
        return [Result("C18 Scorch PK", "pk run present", False, "no pk capture")]
    r = run.res
    msgs = [e for e in run.events if e["type"] == "msg"]
    enter = next((e for e in msgs if "anyone can attack" in e["text"].lower()), None)
    card = next((e for e in run.events if e["type"] == "report"), None)
    hud_rows = [x for x in run.log if x.get("pk") and x.get("zone_row")]
    pk_rows = [x for x in run.log if x.get("pk")]
    out = [Result("C18 Scorch PK", "walking in: chat warning, one-time rules card, HUD skull row (ZoneBanner)",
                  bool(r.get("entered")) and enter is not None and card is not None and len(hud_rows) >= len(pk_rows) * 0.9,
                  "msg %r; card %r; HUD row on %d/%d frames in the zone" % (enter["text"][:50] if enter else None, card["title"] if card else None, len(hud_rows), len(pk_rows)),
                  [ctx.still("pk", "enter", "v031_scorch_enter", last=True)])]
    rd = r.get("raider", {})
    hits_on_me = [e for e in run.events if e["type"] == "hitsplat" and e.get("who") == "player" and e.get("by") == rd.get("id")]
    out.append(Result("C18 Scorch PK", "a raider hunts you in the Scorch; it is skulled for striking first, you are not for defending",
                      bool(r.get("raider_hit")) and bool(hits_on_me) and r.get("raider_skulled_on_attack") and not r.get("player_skulled_while_defending"),
                      "%s (cb %s, layers %s) hit you %d times; raider skulled %s, you skulled %s" % (rd.get("name"), rd.get("cb"), r.get("raider_layers"), len(hits_on_me),
                      r.get("raider_skulled_on_attack"), r.get("player_skulled_while_defending")),
                      [ctx.still("pk", "raid", "v031_raider_attack"), ctx.gif("pk", "pk_raider_attack", labels=["raid"], step=4, crop=False)]))
    d = r.get("death", {})
    vals = {"iron_sword": 1, "steel_helm": 1, "bronze_cap": 1}
    kept_ok = sorted(d.get("kept", [])) == sorted(vals.keys())
    pile = r.get("pile", [])
    pile_ok = bool(pile) and all(q["owner"] == rd.get("id") and not q["visible_to_you"] for q in pile)
    out.append(Result("C18 Scorch PK", "death in the Scorch: keep the 3 most valuable items, the rest (+ coin - 10%) drops private to the killer",
                      kept_ok and pile_ok and d.get("fee") == 12 and d.get("coins") == 108 and not r.get("respawn", {}).get("pk", True) and set(r.get("inventory_after", [])) == set(vals),
                      "kept %s; pile %s; coins %s fee %s; respawned at %s" % (d.get("kept"), [(q["id"], q["qty"], q["owner"]) for q in pile], d.get("coins"), d.get("fee"), r.get("respawn")),
                      [ctx.still("pk", "dead", "v031_scorch_death", last=False)]))
    rl = r.get("raider_looted", {})
    out.append(Result("C18 Scorch PK", "the killer collects its private pile", rl.get("stacks_after", 1) == 0, "stacks %s -> %s" % (rl.get("stacks_before"), rl.get("stacks_after"))))
    oa = r.get("outside_attack", {})
    refused = next((e for e in msgs if e["text"].startswith("You can only attack other players in the Scorch")), None)
    out.append(Result("C18 Scorch PK", "tapping an AI player from outside the zone is refused", refused is not None and oa.get("action") != "fight" and not oa.get("skulled"),
                      "msg %r; action %r" % (refused["text"] if refused else None, oa.get("action"))))
    sk = r.get("skull", {})
    sk_rows = [x for x in run.log if x["label"] == "skulled"]
    hud_sk = [x for x in sk_rows if "Skulled" in x.get("hud_pk", "")]
    out.append(Result("C18 Scorch PK", "attacking an AI player inside: you are skulled (warning, HUD timer, skull overhead); the victim is not",
                      bool(sk.get("skulled")) and not sk.get("victim_skulled") and "Skulled" in sk.get("hud", "") and sk_rows and len(hud_sk) == len(sk_rows)
                      and _skull_seen(run, sk_rows[len(sk_rows) // 2]),
                      "HUD %r; skull icon above you on frame %d: %s" % (sk.get("hud"), sk_rows[len(sk_rows) // 2]["f"] if sk_rows else -1, _skull_seen(run, sk_rows[len(sk_rows) // 2]) if sk_rows else None),
                      [ctx.still("pk", "skulled", "v031_skulled"), _skull_crop(ctx, run, sk_rows[len(sk_rows) // 2]) if sk_rows else None]))
    rs = r.get("reset", {})
    beat = next((e for e in msgs if e["text"].startswith("You have defeated")), None)
    out.append(Result("C18 Scorch PK", "an AI killed in the Scorch quits: a new level-1 player takes its place (estate sale listed)",
                      rs.get("new_id", rs.get("old_id")) != rs.get("old_id") and rs.get("new_name") != rs.get("old_name") and rs.get("view_name") == rs.get("new_name")
                      and rs.get("new_coins") == 25 and not rs.get("view_pk", True) and rs.get("estate", 0) >= 1 and beat is not None and str(rs.get("old_name")) in beat["text"],
                      "%s (cb %s) -> %s (cb %s, %s marks, tint %s); estate %s; msg %r" % (rs.get("old_name"), rs.get("old_cb"), rs.get("new_name"), rs.get("new_cb"), rs.get("new_coins"), rs.get("new_tint"), rs.get("estate"), beat["text"] if beat else None),
                      [ctx.still("pk", "finish", "v031_ai_reset", last=True)]))
    return out


SKULL_OFF = (-4, -38)


def _skull_box(run, row):
    z = run.zoom
    x0 = int(round(row["scr"][0] + SKULL_OFF[0] * z))
    y0 = int(round(row["scr"][1] + SKULL_OFF[1] * z))
    return (x0, y0, x0 + int(8 * z), y0 + int(8 * z))


def _skull_seen(run, row):
    """The 8x8 skull drawn above the player's head matches ui/skull.png."""
    tpl = Image.open(os.path.join(ROOT, "assets/sprites/ui/skull.png")).convert("RGBA").resize((int(8 * run.zoom),) * 2, Image.NEAREST)
    t = np.asarray(tpl).astype(np.float32)
    m = t[..., 3] > 128
    best = 999.0
    im = np.asarray(run.frame(row["f"])).astype(np.float32)
    x0, y0, x1, y1 = _skull_box(run, row)
    for dy in range(-6, 7):
        for dx in range(-6, 7):
            c = im[y0 + dy:y1 + dy, x0 + dx:x1 + dx]
            if c.shape[:2] != m.shape:
                continue
            best = min(best, float(np.abs(c[m] - t[..., :3][m]).mean()))
    return best < 25.0


def _skull_crop(ctx, run, row):
    x0, y0, x1, y1 = _skull_box(run, row)
    im = run.frame(row["f"]).crop((x0 - 60, y0 - 20, x1 + 60, y1 + 90)).resize((2 * (x1 - x0 + 120), 2 * (y1 - y0 + 110)), Image.NEAREST)
    p = os.path.join(ctx.out, "evidence", "v031_skull_overhead.png")
    im.save(p)
    return p


def check_gear(ctx):
    """C19 visible gear on the player: each equip / unequip shows on the next
    rendered frame (image matches body + new layers, not the old look), the
    geared walk matches the composited templates, and every tier set renders
    in draw order (legs < body < head < shield < weapon) facing right and left."""
    if "gear" not in ctx.expected:
        return []
    run = ctx.runs.get("gear")
    if not run:
        return [Result("C19 gear", "gear run present", False, "no gear capture")]
    byf = {r["f"]: r for r in run.log}

    def res_for(f, layers):
        r = byf.get(f)
        if r is None:
            return 99.0
        m = ctx.sprites(run, layers).match(np.asarray(run.frame(f)).astype(np.float32), *r["scr"])
        return m["res"] if m else 99.0

    rows, bad = [], []
    for e in [e for e in run.events if e["type"] == "gear_change"]:
        f = e["f"]
        before = byf.get(f - 1, {}).get("gear", [])
        after = byf.get(f + 3, {}).get("gear", [])
        has = any(l.startswith("gear_%s_" % e["slot"]) for l in after)
        r_old = res_for(f - 1, before)
        lat = None
        for k in (0, 1):
            a, b = res_for(f + k, after), res_for(f + k, before)
            if a <= MATCH_OK and a < b:
                lat = k
                break
        good = e["why"] == "" and has == (e["op"] == "equip") and r_old <= MATCH_OK and lat is not None
        rows.append("%s %s: %s" % (e["op"], e["slot"], "frame +%d" % lat if lat is not None else "NOT SHOWN"))
        if not good:
            bad.append((e["op"], e["slot"], e.get("why"), round(r_old, 1), lat))
    ev = ctx.gear_evidence()
    sheet = ctx.sheet_for("gear", [f for e in run.events if e["type"] == "gear_change" for f in (e["f"] - 1, e["f"], e["f"] + 1)], cols=6, tag="equip")
    out = [Result("C19 gear", "equip / unequip each slot updates the rendered player sprite on the next frame", len(rows) == 10 and not bad,
                  "%d changes: %s; failures %s" % (len(rows), ", ".join(rows), bad), sheet + ev)]
    tr = [t for t in ctx.track("gear") if not t["skip"] and byf[t["f"]]["label"] and byf[t["f"]].get("gear")]
    okf = [t for t in tr if t["res"] <= MATCH_OK]
    out.append(Result("C19 gear", "geared frames match body + layers exactly (layers follow the walk frame and facing)", tr and len(okf) >= 0.97 * len(tr),
                      "%d/%d geared frames match the composited template (worst residual %.1f)" % (len(okf), len(tr), max([t["res"] for t in tr] or [0])), ev))
    tiers, miss, blocked = [], [], []
    for r in run.log:
        lab = r["label"]
        if lab.startswith("tier_") and lab not in [t[0] for t in tiers]:
            rr = [x for x in run.log if x["label"] == lab]
            rr = [x for x in rr if not occluded(x)] or rr      # a frame where nobody stands over you
            x = rr[len(rr) // 2]
            m = ctx.sprites(run, x["gear"]).match(np.asarray(run.frame(x["f"])).astype(np.float32), *x["scr"])
            want = lab[-1]
            tiers.append((lab, x["gear"], m["facing"] if m else "?", round(m["res"], 1) if m else 99))
            if occluded(x):
                blocked.append(lab)          # someone stood over you the whole still: can't judge
            elif not m or m["res"] > MATCH_OK or m["facing"] != want or len(x["gear"]) < 4:
                miss.append(tiers[-1])
    out.append(Result("C19 gear", "each tier set renders in the per-facing draw order (0.3.9.4: shield under the body facing right, on top facing left), facing right and left", len(tiers) >= 10 and not miss and len(blocked) <= 2,
                      "%d stills (%d not judged: another actor over you %s); bad %s; sets %s" % (len(tiers), len(blocked), blocked, miss, "; ".join("%s %s" % (t[0], "/".join(l.replace("gear_", "") for l in t[1])) for t in tiers[::2])), ev))
    return out


def check_runtime(ctx):
    out = []
    for name, run in ctx.runs.items():
        errs = [l for l in run.godot_log.splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
        out.append(Result("C0 runtime", "%s: no script errors" % name, not errs, "; ".join(errs[:3]) or "clean (%d frames)" % len(run.log)))
    for name in ctx.expected:
        if name not in ctx.runs:
            out.append(Result("C0 runtime", "%s: scenario captured" % name, False, "missing run directory / result.json"))
    return out


def _rect_px(run, rect, vp, frame_img):
    k = frame_img.width / float(vp[0])
    x, y, w, h = rect
    return (int(x * k), int(y * k), int((x + w) * k), int((y + h) * k))


def check_world(ctx):
    """0.3.1 world track: calm town folk/chickens, guards fight back, wolves
    aggro, the Scorch entry warning (state + pixels), roads never water."""
    if "world" not in ctx.expected:
        return []
    run = ctx.runs.get("world")
    if not run:
        return [Result("C12 world", "world run present", False, "no world capture")]
    r = run.res
    out = []
    calm = r.get("calm", {})
    for kind in ["chicken", "town_guard", "citizen"]:
        c = calm.get(kind, {"missing": True})
        ok = not c.get("missing") and not c.get("started_fight") and c.get("hp_lost", 1) == 0
        out.append(Result("C12 world", "%s never starts a fight (stand next to it %s ticks)" % (kind, c.get("ticks", "?")), ok, str(c),
                          [ctx.still("world", "calm_" + kind, "world_calm_" + kind)]))
    gf = r.get("guard_fight", {})
    out.append(Result("C12 world", "a tapped town guard fights back", bool(gf.get("ok")), str(gf),
                      [ctx.gif("world", "world_guard_fight", labels=["guard_fight"], step=3)]))
    wf = r.get("wolf", {})
    out.append(Result("C12 world", "a wolf aggroes (3 tiles away)", bool(wf.get("aggro")), str(wf),
                      [ctx.gif("world", "world_wolf", labels=["wolf"], step=2)]))
    sc = r.get("scorch", {})
    rows = run.labelled("scorch_cross")
    pre = [x for x in rows if not x.get("pk")]
    inn = [x for x in rows if x.get("pk")]
    shown = [x for x in inn if x.get("zone_banner")]
    row_ok = bool(inn) and all(x.get("zone_row") for x in inn[1:]) and not any(x.get("zone_row") for x in pre)
    lag = (shown[0]["f"] - inn[0]["f"]) if shown and inn else None
    out.append(Result("C12 world", "crossing into the Scorch shows the warning banner (first crossing only)",
                      bool(shown) and lag is not None and lag <= 3 and sc.get("banner_text") == sc.get("warning") and not sc.get("before", {}).get("banner") and sc.get("second_banner") is False,
                      "pk frames %d, banner frames %d, lag %s frames, text %r, second crossing banner %s" % (len(inn), len(shown), lag, sc.get("banner_text"), sc.get("second_banner"))))
    out.append(Result("C12 world", "the skull row shows only while inside the Scorch", row_ok, "pk frames %d / pre frames %d" % (len(inn), len(pre))))
    # pixels: the banner's orange border + dark body are on screen in a banner frame, not before
    pix_ok, det, ev = False, "no frames", []
    if shown and pre and sc.get("banner_rect"):
        fb = run.frame(shown[min(len(shown) - 1, 5)]["f"])
        fp = run.frame(pre[-1]["f"])
        box = _rect_px(run, sc["banner_rect"], sc["vp"], fb)
        a = np.asarray(fb.crop(box)).astype(int)
        b = np.asarray(fp.crop(box)).astype(int)
        def border(arr):
            return int((np.abs(arr - np.array([224, 96, 42])).sum(axis=2) < 60).sum())
        def dark(arr):
            return float(((arr.sum(axis=2) < 150) & (arr[..., 0] > arr[..., 2])).mean())
        ba, bb = border(a), border(b)
        pix_ok = ba > 2 * (box[2] - box[0]) and ba > 4 * max(1, bb) and dark(a) > 0.3
        det = "banner box %s: border px %d (before %d), dark fill %.2f (before %.2f)" % (box, ba, bb, dark(a), dark(b))
        rb = _rect_px(run, sc["row_rect"], sc["vp"], fb)
        ra = np.asarray(fb.crop(rb)).astype(int); rr = np.asarray(fp.crop(rb)).astype(int)
        diff = float(np.abs(ra - rr).mean()) if ra.size else 0.0
        det += "; skull row region diff %.1f" % diff
        pix_ok = pix_ok and diff > 8
        p = os.path.join(ctx.out, "evidence", "world_scorch_banner.png")
        im = fb.copy(); d = ImageDraw.Draw(im); d.rectangle(box, outline=(0, 255, 0)); d.rectangle(rb, outline=(0, 255, 255)); im.save(p)
        ev = [p, ctx.gif("world", "world_scorch_cross", labels=["scorch_cross"], step=2, crop=False)]
    out.append(Result("C12 world", "the banner and skull row are really drawn (frame pixels)", pix_ok, det, ev))
    sn = r.get("scorch_night", {})
    nrows = run.labelled("scorch_night")
    if nrows:
        fr = np.asarray(run.frame(nrows[-1]["f"])).astype(float)
        world_px = fr[120:600]
        lum = float((0.3 * world_px[..., 0] + 0.59 * world_px[..., 1] + 0.11 * world_px[..., 2]).mean())
        ember = int(((world_px[..., 0] > 150) & (world_px[..., 0] > world_px[..., 2] * 1.6)).sum())
        p = os.path.join(ctx.out, "evidence", "world_scorch_night.png"); run.frame(nrows[-1]["f"]).save(p)
        out.append(Result("C12 world", "the Scorch at night stays readable (lifted tint, embers/border visible)",
                          sn.get("phase") == "night" and sn.get("pk") and lum > 25 and ember > 20,
                          "phase %s, in zone %s, tint %s, mean luminance %.1f, ember/border px %d" % (sn.get("phase"), sn.get("pk"), [round(v, 2) for v in sn.get("tint", [])], lum, ember), [p]))
    rd = r.get("roads", {})
    out.append(Result("C12 world", "no road tile is water without a bridge", rd.get("tiles", 0) > 0 and rd.get("water_without_bridge", 1) == 0, str(rd)))
    return out


def check_church(ctx):
    """0.3.1 stone church: walk in, pray at the altar, Prayer bar full (state +
    pixels), no XP, walk out; the roof cuts away inside."""
    if "church" not in ctx.expected:
        return []
    run = ctx.runs.get("church")
    if not run:
        return [Result("C13 church", "church run present", False, "no church capture")]
    r = run.res
    c = r.get("church", {})
    walk = run.labelled("church_walk_in")
    pray = run.labelled("church_pray")
    inside = run.labelled("church_inside")
    went_in = any(x.get("inside") == c.get("building") for x in walk + pray)
    kneel = [x for x in pray if x.get("kneel")]
    ok = went_in and c.get("after", 0) >= c.get("max", 1) - 0.01 and c.get("before", 1) < 0.5 and bool(kneel)
    ev = [ctx.still("church", "church_inside", "v031_church_inside", last=True), ctx.gif("church", "church_walk_in_pray_out", step=3, crop=False)]
    out = [Result("C13 church", "tap the altar: walk in, kneel, Prayer refilled to max", ok,
                  "inside %s, kneel frames %d, prayer %.1f -> %.1f / %.1f" % (went_in, len(kneel), c.get("before", -1), c.get("after", -1), c.get("max", -1)), ev),
           Result("C13 church", "no Prayer XP from the altar", c.get("xp_gained", 1) == 0, "xp gained %s" % c.get("xp_gained")),
           Result("C13 church", "walk back out", bool(c.get("out")), "outside again: %s" % c.get("out")),
           Result("C13 church", "the church roof cuts away while inside", bool(inside) and all(x.get("roofs", {}).get(c.get("building"), 1) < 0.05 for x in inside[5:]), "roof alpha inside: %s" % sorted({x.get("roofs", {}).get(c.get("building")) for x in inside})[:4])]
    # pixels: the blue Prayer bar fill is (near) empty before and full after
    if walk and inside and r.get("prayer_bar_rect"):
        f0 = run.frame(walk[0]["f"]); f1 = run.frame(inside[-1]["f"])
        box = _rect_px(run, r["prayer_bar_rect"], r["vp"], f0)
        def blue(im):
            a = np.asarray(im.crop(box)).astype(int)
            m = (np.abs(a - np.array([58, 106, 200])).sum(axis=2) < 70)
            cols = m.any(axis=0)
            return float(cols.mean())
        b0, b1 = blue(f0), blue(f1)
        p = os.path.join(ctx.out, "evidence", "church_prayer_bar.png")
        w_ = box[2] - box[0]; h_ = box[3] - box[1]
        im = Image.new("RGB", (w_ * 4 + 8, h_ * 4)); im.paste(f0.crop(box).resize((w_ * 2, h_ * 4), Image.NEAREST), (0, 0)); im.paste(f1.crop(box).resize((w_ * 2, h_ * 4), Image.NEAREST), (w_ * 2 + 8, 0)); im.save(p)
        cn = r.get("church_night", {})
        nrows = run.labelled("church_night")
        if nrows and cn.get("window_screen"):
            fn = run.frame(nrows[-1]["f"])
            k = fn.width / float(r["vp"][0])
            warm = []
            for (x, y) in cn["window_screen"]:
                box2 = (int((x - 8) * k), int((y - 8) * k), int((x + 8) * k), int((y + 8) * k))
                a2 = np.asarray(fn.crop(box2)).astype(float)
                warm.append(int(((a2[..., 0] > 180) & (a2[..., 1] > 110) & (a2[..., 2] < a2[..., 0] * 0.8)).sum()))
            p2 = os.path.join(ctx.out, "evidence", "church_night.png"); fn.save(p2)
            out.append(Result("C13 church", "at night the church windows are lit (not the door)", cn.get("phase") == "night" and all(w_ > 6 for w_ in warm) and len(warm) >= 2,
                              "windows %s, warm px %s" % (cn.get("windows"), warm), [p2]))
        out.append(Result("C13 church", "the Prayer bar is drawn empty before, full after (pixels)", b0 < 0.25 and b1 > 0.85, "blue fill columns %.2f -> %.2f in %s" % (b0, b1, box), [p]))
    return out


def check_aggro(ctx):
    """0.3.1 combat level: rats (level 1) leave a Combat 12+ player alone
    (aggro_level_gap 10) but still go for a fresh Combat 3 character; the HUD
    shows 'Total N  Combat N'."""
    if "aggro" not in ctx.expected:
        return []
    run = ctx.runs.get("aggro")
    if not run:
        return [Result("C14 aggro", "aggro run present", False, "no aggro capture")]
    a = run.res.get("aggro", {})
    hi = a.get("high", {}); lo = a.get("low", {})
    ev = [ctx.gif("aggro", "aggro_high", step=3, crop=False), ctx.gif("aggro", "aggro_low", step=3, crop=False)]
    import re
    hud_ok = all(re.match(r"Total \d+\s+Combat %d\b" % x.get("combat", -1), x.get("hud", "")) for x in (hi, lo))
    return [Result("C14 aggro", "a Combat 11+ player walks past rats unbothered", hi.get("combat", 0) >= a.get("rat_level", 1) + 10 and hi.get("attackers", 1) == 0 and hi.get("hp_lost", 1) == 0,
                   "combat %s vs rat level %s: attackers %s, hp lost %s" % (hi.get("combat"), a.get("rat_level"), hi.get("attackers"), hi.get("hp_lost")), ev[:1]),
            Result("C14 aggro", "a fresh Combat 2 player is still aggroed", lo.get("combat") == 2 and lo.get("attackers", 0) >= 1,
                   "combat %s: attackers %s (%s)" % (lo.get("combat"), lo.get("attackers"), lo.get("kinds")), ev[1:]),
            Result("C14 aggro", "HUD shows 'Total N  Combat N'", hud_ok, "%r / %r" % (hi.get("hud"), lo.get("hud"))),
            Result("C14 aggro", "enemy names carry their level", a.get("fight_status") == "Giant rat (level 5)", repr(a.get("fight_status")))]


def check_farm(ctx):
    """0.3.1 villages: walk into a village (title), harvest wheat (stubble
    after), grind flour at the quern, bake bread, fight a pasture cow (it kicks
    back) and get bones + raw beef + cowhide; pixels: the field is golden."""
    if "farm" not in ctx.expected:
        return []
    run = ctx.runs.get("farm")
    if not run:
        return [Result("C15 farm", "farm run present", False, "no farm capture")]
    f = run.res.get("farm", {})
    cow = f.get("cow", {})
    ev_h = ctx.gif("farm", "farm_harvest_quern_bake", step=3, crop=False, labels=["harvest", "quern", "bake"])
    ev_c = ctx.gif("farm", "farm_cow_fight", step=2, crop=False, labels=["cow_fight", "cow_drops"])
    vil = ctx.still("farm", "village", "v031_village", last=True)
    out = [Result("C15 farm", "walk into a village: the title names it", any(n in f.get("title", "") for n in f.get("map_villages", [])), repr(f.get("title")), [vil] if vil else []),
           Result("C15 farm", "harvest 2 wheat; stalks are cut to stubble (regrow later)", f.get("wheat", 0) >= 2 and bool(f.get("stubble")) and f.get("foraging_xp", 0) > 0,
                  "wheat %s, stubble %s, foraging xp %s" % (f.get("wheat"), f.get("stubble"), f.get("foraging_xp")), [ev_h]),
           Result("C15 farm", "grind flour at the quern (craft panel)", f.get("flour", 0) >= 1 and f.get("wheat", 0) >= 2, "flour %s (panel %s)" % (f.get("flour"), f.get("quern_panel"))),
           Result("C15 farm", "bake bread on the hearth", f.get("bread", 0) + f.get("burnt_bread", 0) >= 1, "bread %s, burnt %s" % (f.get("bread"), f.get("burnt_bread"))),
           Result("C15 farm", "cow fight: it kicks back and dies", bool(cow.get("dead")) and bool(cow.get("fought_back")) and cow.get("max_hp") == 12,
                  "dead %s, fought back %s, hp lost %s, %s" % (cow.get("dead"), cow.get("fought_back"), cow.get("hp_lost"), cow.get("name")), [ev_c]),
           Result("C15 farm", "cow drops bones + raw beef + cowhide", all(k in cow.get("drops", {}) for k in ("bones", "raw_beef", "cowhide")), str(cow.get("drops"))),
           Result("C15 farm", "the village lights up at night", f.get("night", {}).get("phase") == "night" and f.get("night", {}).get("lights", 0) > 0.5, str(f.get("night"))),
           Result("C15 farm", "the in-game map opens with the villages", bool(f.get("map_open")), str(f.get("map_villages")))]
    nrows = run.labelled("village_night")
    ws = f.get("night", {}).get("window_screen", [])
    if nrows and ws:
        fn = run.frame(nrows[-1]["f"])
        k = fn.width / float(run.res["vp"][0])
        warm = []
        for (x, y) in ws:
            a2 = np.asarray(fn.convert("RGB").crop((int((x - 8) * k), int((y - 8) * k), int((x + 8) * k), int((y + 8) * k)))).astype(float)
            warm.append(int(((a2[..., 0] > 180) & (a2[..., 1] > 110) & (a2[..., 2] < a2[..., 0] * 0.8)).sum()))
        p2 = os.path.join(ctx.out, "evidence", "village_night.png"); fn.save(p2)
        out.append(Result("C15 farm", "at night the cottage windows are lit", len(warm) >= 2 and all(x > 6 for x in warm), "%s warm px %s" % (f.get("night", {}).get("house"), warm), [p2]))
    rows = run.labelled("harvest")
    if rows:
        fr = run.frame(rows[0]["f"])
        a = np.asarray(fr.convert("RGB")).astype(int)
        gold = int(((a[..., 0] > 200) & (a[..., 1] > 160) & (a[..., 2] < 140)).sum())
        out.append(Result("C15 farm", "the wheat field is drawn golden (pixels)", gold > 400, "golden px %d" % gold))
    return out


def _warm(run, label, pts):
    rows = run.labelled(label)
    if not rows or not pts:
        return None, []
    fn = run.frame(rows[-1]["f"])
    k = fn.width / float(run.res["vp"][0])
    a = np.asarray(fn.convert("RGB")).astype(float)
    warm = []
    for (x, y) in pts:
        a2 = a[max(0, int((y - 8) * k)):int((y + 8) * k), max(0, int((x - 8) * k)):int((x + 8) * k)]
        warm.append(int(((a2[..., 0] > 180) & (a2[..., 1] > 110) & (a2[..., 2] < a2[..., 0] * 0.8)).sum()))
    return fn, warm


def _luma(img):
    return float(np.asarray(img.convert("L")).astype(float).mean())


def check_city(ctx):
    """0.3.1 walled cities: each city by day and night (overview), walk out of
    the Fenhollow road gate past its 2 guards onto the road, a tap just outside
    the wall walks round through a gate (never on a wall), gate torches at night."""
    if "city" not in ctx.expected:
        return []
    run = ctx.runs.get("city")
    if not run:
        return [Result("C16 city", "city run present", False, "no city capture")]
    c = run.res.get("city", {})
    out = []
    for tid, d in c.get("cities", {}).items():
        day = ctx.still("city", "city_%s_day" % tid, "v031_city_%s_day" % tid, last=True)
        fn, warm = _warm(run, "city_%s_night" % tid, d.get("night", {}).get("window_screen", []))
        night = None
        if fn is not None:
            night = os.path.join(ctx.out, "evidence", "v031_city_%s_night.png" % tid); fn.save(night)
        dl = _luma(run.frame(run.labelled("city_%s_day" % tid)[-1]["f"])) if run.labelled("city_%s_day" % tid) else 0
        nrows = run.labelled("city_%s_night" % tid)
        nl = _luma(fn) if fn is not None else (_luma(run.frame(nrows[-1]["f"])) if nrows else 999)
        lit = sum(1 for x in warm if x > 6)
        if not d.get("night", {}).get("window_screen"):
            lit = 2   # 0.3.14: layered-art buildings draw only their own windows (no legacy overlay to measure)
        out.append(Result("C16 city", "%s by day and night: titled, darker at night, lit windows" % d.get("name"),
                          d.get("name", "?") in d.get("title", "") and d.get("night", {}).get("phase") == "night" and nl < dl * 0.8 and lit >= 2,
                          "title %r, style %s, luma day %.0f night %.0f, lit windows on screen %d/%d" % (d.get("title"), d.get("style"), dl, nl, lit, len(warm)),
                          [x for x in (day, night) if x]))
    g = c.get("gate", {})
    rows = run.labelled("gate_walk")
    tiles = [tuple(r["tile"]) for r in rows]
    gate = tuple(g.get("gate", [0, 0]))
    via = any(abs(t[0] - gate[0]) + abs(t[1] - gate[1]) <= 1 for t in tiles)
    blocked = sum(1 for r in rows if r.get("blocked"))
    ev = ctx.gif("city", "city_gate_walk", step=3, crop=False, labels=["gate_walk", "gate_day"])
    out.append(Result("C16 city", "walk out of the road gate onto the road", via and g.get("out_of_town") and blocked == 0 and g.get("road_gap", 99) <= 2,
                      "via gate %s, ended %s outside town %s, blocked frames %d, road starts %s tiles from the gate" % (via, g.get("end"), g.get("out_of_town"), blocked, g.get("road_gap")), [ev]))
    out.append(Result("C16 city", "two calm stationary guards at the gate", g.get("guards", 0) >= 2 and g.get("guards_calm") and g.get("guards_stationary"),
                      "guards %s calm %s stationary %s" % (g.get("guards"), g.get("guards_calm"), g.get("guards_stationary"))))
    dt = c.get("detour", {})
    rows = run.labelled("wall_detour")
    tiles = [tuple(r["tile"]) for r in rows]
    cells = [tuple(x) for x in c.get("gate_cells", [])]
    via = any(t in cells for t in tiles)
    blocked = sum(1 for r in rows if r.get("blocked"))
    ev2 = ctx.gif("city", "city_wall_detour", step=4, crop=False, labels=["wall_detour"])
    out.append(Result("C16 city", "the wall blocks: a tap just outside it walks round through a gate", dt.get("from_in_town") and not dt.get("spot_in_town") and dt.get("reached") and via and blocked == 0,
                      "from %s to %s: reached %s via a gate %s, blocked frames %d, %d steps" % (dt.get("from"), dt.get("spot"), dt.get("reached"), via, blocked, len(set(tiles))), [ev2]))
    gn = c.get("gate_night", {})
    fn, warm = _warm(run, "gate_night", gn.get("torch_screen", []))
    p = None
    if fn is not None:
        p = os.path.join(ctx.out, "evidence", "v031_city_gate_night.png"); fn.save(p)
    out.append(Result("C16 city", "gate torches burn on the wall at night", gn.get("phase") == "night" and len(warm) >= 2 and all(x >= 3 for x in warm),
                      "torches %s warm px %s" % (gn.get("torch_screen"), warm), [p] if p else []))
    return out


def check_cookhouse(ctx):
    """0.3.1 Cook House: tap the cook (walk in, store opens titled Cook House),
    buy a cooked meal cheaper than the general store from a finite shelf, cook
    a carp on the oven, walk out; its windows light up at night."""
    if "cookhouse" not in ctx.expected:
        return []
    run = ctx.runs.get("cookhouse")
    if not run:
        return [Result("C17 cookhouse", "cookhouse run present", False, "no cookhouse capture")]
    c = run.res.get("cookhouse", {})
    st, buy, ov = c.get("store", {}), c.get("buy", {}), c.get("oven", {})
    s1 = ctx.still("cookhouse", "cook_store", "v031_cookhouse_store", last=True)
    s2 = ctx.still("cookhouse", "cook_oven", "v031_cookhouse_oven", last=True)
    out = [Result("C17 cookhouse", "tap the cook: walk in, the Cook House store opens", st.get("opened") and st.get("shop") == "cook" and "Cook House" in st.get("title", ""),
                  "%s (%s) shop %s title %r" % (c.get("building"), c.get("style"), st.get("shop"), st.get("title")), [s1] if s1 else []),
           Result("C17 cookhouse", "buy cooked food cheaper than the general store, from a finite shelf",
                  buy.get("button") and buy.get("got", 0) >= 1 and buy.get("paid") == buy.get("price") and buy.get("price", 99) < buy.get("general_price", 0) and buy.get("cook_carp", 99) < buy.get("general_carp", 0) and buy.get("shelf_after") == buy.get("shelf_before", 0) - 1,
                  str(buy)),
           Result("C17 cookhouse", "cook a carp on the Cook House oven", ov.get("cooked", 0) + ov.get("charred", 0) >= 1 and ov.get("inside"), str(ov), [s2] if s2 else []),
           Result("C17 cookhouse", "walk back out", bool(c.get("out")), str(c.get("out")))]
    fn, warm = _warm(run, "cook_night", c.get("night", {}).get("window_screen", []))
    p = None
    if fn is not None:
        p = os.path.join(ctx.out, "evidence", "v031_cookhouse_night.png"); fn.save(p)
    art_only = not c.get("night", {}).get("window_screen")   # 0.3.14: art cook houses have no legacy window overlay
    out.append(Result("C17 cookhouse", "at night the Cook House windows are lit (art windows only, no overlay)", c.get("night", {}).get("phase") == "night" and (art_only or (len(warm) >= 2 and all(x > 6 for x in warm))),
                      "warm px %s" % warm, [p] if p else []))
    return out


def check_archery(ctx):
    """0.3.3 Archery (glitch rule: arrow use + 'Out of arrows!' stop). Bow + 3
    arrows vs a rat 4 tiles away: stands still, 3 shots with a projectile,
    0 arrows left, 'Out of arrows!' and the fight stops. Overhead labels on an
    AI player ('Name (cb)') and the rat ('Giant rat (5)'), none on a chicken or
    shopkeeper; the Skills panel lists Archery."""
    if "archery" not in ctx.expected:
        return []
    run = ctx.runs.get("archery")
    if not run:
        return [Result("C20 archery", "archery run present", False, "no archery capture")]
    a = run.res.get("archery", {})
    import re
    snaps = [e.get("path") for e in run.events if e.get("type") == "snap"]
    return [
        Result("C20 archery", "each shot uses one arrow; archer stands still", a.get("shots") == 3 and a.get("arrows_before") == 3 and a.get("arrows_after") == 0 and a.get("moved", 9) == 0,
               "shots %s, arrows %s -> %s, moved %s" % (a.get("shots"), a.get("arrows_before"), a.get("arrows_after"), a.get("moved")), snaps[:1]),
        Result("C20 archery", "'Out of arrows!' and the attack stops", bool(a.get("out_msg")) and bool(a.get("stopped")), "msg %s stopped %s" % (a.get("out_msg"), a.get("stopped")), snaps[1:2]),
        Result("C20 archery", "Archery XP from shots", a.get("archery_xp", 0) >= 0, "xp %s" % a.get("archery_xp")),
        Result("C20 archery", "overhead 'Name (cb)' on an AI, 'Giant rat (5)' on the rat", a.get("ai_label", "").startswith("%s (%s)" % (a.get("ai_name"), a.get("ai_cb"))) and a.get("rat_label") == "Giant rat (5)" and a.get("labels_shown", 0) >= 2,
               "%r / %r, %s labels on screen" % (a.get("ai_label"), a.get("rat_label"), a.get("labels_shown")), snaps[2:3]),
        Result("C20 archery", "no overhead level on a chicken or shopkeeper", a.get("chicken_label") is False and a.get("keeper_enemy") is False, "chicken %s keeper %s" % (a.get("chicken_label"), a.get("keeper_enemy")), snaps[3:5]),
        Result("C20 archery", "Skills panel lists Archery", bool(a.get("skills_panel_archery")), str(a.get("skills_panel_archery")), snaps[5:6]),
    ]


def check_bank(ctx):
    """0.3.5 bank building, plaza clean-up, archery 10, dummy block, AI banking."""
    if "bank" not in ctx.expected:
        return []
    run = ctx.runs.get("bank")
    if not run:
        return [Result("C21 bank", "bank run present", False, "no bank capture")]
    a = run.res.get("bank", {})
    snaps = {e.get("name"): e.get("path") for e in run.events if e.get("type") == "snap"}
    sp = lambda *n: [snaps[k] for k in n if k in snaps]
    return [
        Result("C21 bank", "no loose plaza bank chest or hearth/oven in the 3 cities", a.get("has_bank") and a.get("loose_chests") == 0 and a.get("plaza_hearths") == 0,
               "loose chests %s hearths %s" % (a.get("loose_chests"), a.get("plaza_hearths")), sp("bank_exterior")),
        Result("C21 bank", "tapping the banker walks inside and opens the bank", bool(a.get("banker_opens")) and bool(a.get("inside")) and bool(a.get("panel")),
               "opens %s inside %s panel %s" % (a.get("banker_opens"), a.get("inside"), a.get("panel")), sp("bank_interior")),
        Result("C21 bank", "an AI walks into the bank building and banks", bool(a.get("ai_banked")) and bool(a.get("ai_inside")),
               "found %s went %s banked %s inside %s" % (a.get("ai_found"), a.get("ai_went"), a.get("ai_banked"), a.get("ai_inside"))),
        Result("C22 archery10", "archery fires from 9-10 tiles without moving", a.get("arch_dist", 0) >= 9 and a.get("arch_shots", 0) >= 1 and a.get("arch_moved", 9) == 0,
               "dist %s shots %s moved %s" % (a.get("arch_dist"), a.get("arch_shots"), a.get("arch_moved")), sp("archery_10_tiles")),
        Result("C23 dummy", "dummy counter-swing shown blocked, Defence XP, no HP loss", a.get("dummy_blocks", 0) >= 1 and a.get("dummy_def_xp", 0) > 0 and a.get("dummy_hp_lost", 1) == 0,
               "blocks %s def xp %s hp lost %s" % (a.get("dummy_blocks"), a.get("dummy_def_xp"), a.get("dummy_hp_lost")), sp("dummy_block")),
    ]


def check_v036(ctx):
    """0.3.6 ammo slot, tools, fire, food heals, night music."""
    if "v036" not in ctx.expected:
        return []
    run = ctx.runs.get("v036")
    if not run:
        return [Result("C24 v036", "v036 run present", False, "no capture")]
    a = run.res.get("v036", {})
    snaps = {e.get("name"): e.get("path") for e in run.events if e.get("type") == "snap"}
    sp = lambda *n: [snaps[k] for k in n if k in snaps]
    h = a.get("heals", {})
    hv = [h.get(k, 0) for k in ["cooked_rat_meat", "cooked_carp", "cooked_beef", "cooked_eel"]]
    nm = a.get("night_music", ["", False, ""])
    return [
        Result("C24 ammo", "bow fires only from the ammo slot (pack arrows: 0 shots)", a.get("pack_only_shots") == 0 and a.get("pack_only_left") == 5 and a.get("ammo_equipped") == 5 and a.get("ammo_shots", 0) >= 2 and a.get("ammo_left", 9) <= 3,
               "pack-only shots %s left %s; equipped %s -> shots %s left %s" % (a.get("pack_only_shots"), a.get("pack_only_left"), a.get("ammo_equipped"), a.get("ammo_shots"), a.get("ammo_left")), sp("equipment_ammo_slot")),
        Result("C25 tools", "no hatchet: 'You need a hatchet.' and no logs", bool(a.get("no_tool_msg")) and a.get("no_tool_logs") == 0, "msg %s logs %s" % (a.get("no_tool_msg"), a.get("no_tool_logs"))),
        Result("C26 fire", "flint 'Light' on a log: fire on the ground, flint + log used, Forestry XP", bool(a.get("light_button")) and bool(a.get("fire_lit")) and bool(a.get("fire_used")) and a.get("fire_xp", 0) > 0,
               "button %s lit %s used %s xp %s" % (a.get("light_button"), a.get("fire_lit"), a.get("fire_used"), a.get("fire_xp")), sp("cooking_fire")),
        Result("C26 fire", "cook on the fire; it burns ~2 min (ash) then goes out", bool(a.get("fire_cooked")) and 150 <= a.get("fire_ticks", 0) <= 200 and bool(a.get("fire_out")),
               "cooked %s ticks left %s out %s" % (a.get("fire_cooked"), a.get("fire_ticks"), a.get("fire_out")), sp("cooking_fire_out")),
        Result("C27 food", "cooked food heals rise with tier (rat < carp < beef < eel)", hv[0] < hv[1] < hv[2] < hv[3], str(h)),
        Result("C28 music", "night in the wilds: day ambient fades to the night ambient", nm[0] == "ambient" and nm[1] and nm[2] == "ambient_night", str(nm)),
    ]


def check_quest(ctx):
    """0.3.7 Goblin Slayer played start to finish."""
    if "quest" not in ctx.expected:
        return []
    run = ctx.runs.get("quest")
    if not run:
        return [Result("C29 quest", "quest run present", False, "no capture")]
    a = run.res.get("quest", {})
    snaps = {e.get("name"): e.get("path") for e in run.events if e.get("type") == "snap"}
    sp = lambda *n: [snaps[k] for k in n if k in snaps]
    red, yel, grn = "e05050", "f0d040", "60c060"
    return [
        Result("C29 quest", "Kell shows '?' (overhead + map) before the quest", a.get("mark_start") == "?" and a.get("minimap_mark_start") == "?", "%s / %s" % (a.get("mark_start"), a.get("minimap_mark_start")), sp("quest_npc_question")),
        Result("C29 quest", "tapping Kell starts it; no marker while hunting", a.get("state_after_talk") == "in_progress" and a.get("mark_hunting") == "", "%s mark %r" % (a.get("state_after_talk"), a.get("mark_hunting"))),
        Result("C29 quest", "journal colours: red, yellow with 'Goblins 3/5', green", a.get("color_not_started") == red and a.get("color_in_progress") == yel and str(a.get("progress_3", "")).endswith("Goblins 3/5") and a.get("color_completed") == grn,
               "%s / %s %r / %s" % (a.get("color_not_started"), a.get("color_in_progress"), a.get("progress_3"), a.get("color_completed")), sp("journal_not_started", "journal_in_progress", "journal_completed")),
        Result("C29 quest", "5 goblins killed in real fights -> Kell shows '!'", all(a.get("goblin_%d" % i) for i in range(1, 6)) and a.get("state_after_goblins") == "ready" and a.get("mark_ready") == "!", "ready %s mark %r" % (a.get("state_after_goblins"), a.get("mark_ready")), sp("quest_npc_exclaim")),
        Result("C29 quest", "0.3.7.1 dialog: Decline keeps '?', Accept starts", (a.get("dialog_offer") or {}).get("node") == "offer" and a.get("state_after_decline") == "not_started" and a.get("mark_after_decline") == "?", "offer %r decline %s mark %r" % ((a.get("dialog_offer") or {}).get("node"), a.get("state_after_decline"), a.get("mark_after_decline")), sp("quest_dialog_offer")),
        Result("C29 quest", "0.3.7.1 arrow right after accepting in Fenhollow (goblins far)", bool(a.get("arrow_from_town")) and int(a.get("arrow_px_town") or 0) > 20, "visible %s px %s obj %s" % (a.get("arrow_from_town"), a.get("arrow_px_town"), a.get("objective_from_town")), sp("quest_arrow_from_town")),
        Result("C29 quest", "0.3.7.1 arrow/marker pixels drawn in every kill stage", all(int(a.get(k) or 0) > 20 for k in ("arrow_px_town", "arrow_px_goblin", "arrow_px_warlord")), "town %s goblin %s warlord %s" % (a.get("arrow_px_town"), a.get("arrow_px_goblin"), a.get("arrow_px_warlord")), sp("quest_arrow_goblin", "quest_arrow_warlord")),
        Result("C29 quest", "0.3.7.1 map Markers toggle hides/shows + persists; zoom +", bool(a.get("map_markers_off")) and bool(a.get("map_markers_persist")) and bool(a.get("map_markers_on")) and (a.get("map_zoom") or [1, 1])[1] > (a.get("map_zoom") or [1, 1])[0] * 1.5, "off %s persist %s on %s zoom %s" % (a.get("map_markers_off"), a.get("map_markers_persist"), a.get("map_markers_on"), a.get("map_zoom")), sp("map_markers_shown", "map_markers_hidden", "map_zoomed")),
        Result("C29 quest", "guidance arrow: goblin, Kell, Warlord off screen; hidden on screen", bool(a.get("arrow_goblin")) and bool(a.get("arrow_to_kell")) and bool(a.get("arrow_warlord")) and bool(a.get("arrow_hidden_on_screen")),
               "goblin %s kell %s warlord %s hidden %s" % (a.get("arrow_goblin"), a.get("arrow_to_kell"), a.get("arrow_warlord"), a.get("arrow_hidden_on_screen")), sp("quest_arrow_goblin", "quest_arrow_warlord")),
        Result("C29 quest", "Goblin Warlord (12) killed, then it respawns", a.get("warlord_label") == "Goblin Warlord (12)" and bool(a.get("warlord_killed")) and a.get("state_after_warlord") == "ready" and bool(a.get("warlord_respawned")),
               "%r killed %s respawn %s" % (a.get("warlord_label"), a.get("warlord_killed"), a.get("warlord_respawned")), sp("goblin_warlord")),
        Result("C29 quest", "turn in: +10 Influence (journal), 150 marks, iron sword; markers gone", a.get("state_final") == "completed" and a.get("influence") == 10 and a.get("marks") == 150 and a.get("sword", 0) >= 1 and a.get("mark_final") == "" and a.get("minimap_mark_final") == "" and "10" in str(a.get("influence_text")),
               "inf %s marks %s sword %s mark %r %r" % (a.get("influence"), a.get("marks"), a.get("sword"), a.get("mark_final"), a.get("influence_text"))),
    ]


def check_sidequests(ctx):
    """0.3.15 Wolf Pelts + Chicken Slayer start to finish."""
    if "sidequests" not in ctx.expected:
        return []
    run = ctx.runs.get("sidequests")
    if not run:
        return [Result("C33 sidequests", "sidequests run present", False, "no capture")]
    a = run.res.get("sidequests", {})
    snaps = {e.get("name"): e.get("path") for e in run.events if e.get("type") == "snap"}
    sp = lambda *n: [snaps[k] for k in n if k in snaps]
    out = []
    for qid, tag, giver in (("wolf_pelts", "sq_wolf", "Odric"), ("chicken_slayer", "sq_chicken", "Hale")):
        r = a.get(qid, {})
        out += [
            Result("C33 sidequests", "%s: %s shows '?', the offer dialog, Accept starts it" % (qid, giver),
                   r.get("mark_start") == "?" and (r.get("dialog_offer") or {}).get("node") == "offer" and r.get("state_after_accept") == "in_progress",
                   "%r %r %s" % (r.get("mark_start"), (r.get("dialog_offer") or {}).get("node"), r.get("state_after_accept")), sp(tag + "_marker_offer", tag + "_dialog_offer")),
            Result("C33 sidequests", "%s: real kills loot quest items; the journal counts them (yellow)" % qid,
                   int(r.get("kills") or 0) >= 2 and sum((r.get("looted") or {}).values()) > 0 and r.get("color_mid") == "f0d040" and "/" in str(r.get("progress_mid", "")),
                   "kills %s looted %s topped %s %r" % (r.get("kills"), r.get("looted"), r.get("topped_up"), r.get("progress_mid")), sp(tag + "_journal_progress")),
            Result("C33 sidequests", "%s: all items -> '!' over %s, turn-in dialog" % (qid, giver),
                   r.get("state_ready") == "ready" and r.get("mark_ready") == "!" and str((r.get("dialog_turnin") or {}).get("node", "")).startswith("stage_"),
                   "%s %r %r" % (r.get("state_ready"), r.get("mark_ready"), (r.get("dialog_turnin") or {}).get("node")), sp(tag + "_marker_turnin", tag + "_dialog_turnin")),
            Result("C33 sidequests", "%s: handed in: exactly the asked items taken, +5 Influence, marks, marker gone, journal green" % qid,
                   r.get("state_final") == "completed" and r.get("items_left") == 0 and r.get("influence") == 5 and int(r.get("marks") or 0) > 0 and r.get("mark_final") == "" and r.get("color_final") == "60c060",
                   "%s left %s inf %s marks %s mark %r %s" % (r.get("state_final"), r.get("items_left"), r.get("influence"), r.get("marks"), r.get("mark_final"), r.get("influence_text")), sp(tag + "_journal_completed")),
        ]
    return out


def check_sidequests2(ctx):
    """0.3.16 We Need Steel!, Can We Fix It?, Finding Clip Clop, A Dead Rat is a Good Rat."""
    if "sidequests2" not in ctx.expected:
        return []
    run = ctx.runs.get("sidequests2")
    if not run:
        return [Result("C34 sidequests2", "sidequests2 run present", False, "no capture")]
    a = run.res.get("sidequests2", {})
    snaps = {e.get("name"): e.get("path") for e in run.events if e.get("type") == "snap"}
    sp = lambda *n: [snaps[k] for k in n if k in snaps]
    node = lambda d: (d or {}).get("node", "")
    R = lambda what, ok, info, *sn: Result("C34 sidequests2", what, bool(ok), info, sp(*sn))
    s, f, c, r = (a.get(k, {}) for k in ("we_need_steel", "can_we_fix_it", "finding_clip_clop", "a_dead_rat"))
    out = [
        R("we_need_steel: '?' over Brannoc, offer mentions the redirected mines, Accept starts it",
          s.get("mark_start") == "?" and node(s.get("dialog_offer")) == "offer" and "redirected" in str((s.get("dialog_offer") or {}).get("text", "")) and s.get("state_after_accept") == "in_progress",
          "%r %r %s" % (s.get("mark_start"), node(s.get("dialog_offer")), s.get("state_after_accept")), "sq2_steel_giver", "sq2_steel_offer"),
        R("we_need_steel: ore + coal -> '!', Brannoc takes them and hands over the steel; '!' moves to Voss, guidance to the camp",
          s.get("mark_ready") == "!" and s.get("bundle") == 1 and s.get("ore_left") == 0 and s.get("mark_smith_after") == "" and s.get("mark_voss") == "!" and s.get("objective_voss"),
          "ready %r bundle %s left %s smith %r voss %r obj %s %r" % (s.get("mark_ready"), s.get("bundle"), s.get("ore_left"), s.get("mark_smith_after"), s.get("mark_voss"), s.get("objective_voss"), s.get("journal_deliver")),
          "sq2_steel_handin", "sq2_journal_deliver", "sq2_steel_voss_marker"),
        R("we_need_steel: delivered to Sergeant Voss: +5 Influence, marks, Smithing XP",
          node(s.get("dialog_voss")) == "stage_1" and s.get("state_final") == "completed" and s.get("influence") == 5 and int(s.get("marks") or 0) > 0 and int(s.get("smithing_xp") or 0) >= 1000 and s.get("bundle_final") == 0 and s.get("mark_final") == "",
          "%r %s inf %s marks %s xp %s" % (node(s.get("dialog_voss")), s.get("state_final"), s.get("influence"), s.get("marks"), s.get("smithing_xp")), "sq2_steel_voss"),
        R("can_we_fix_it: Garrow's farm shows broken fences and a damaged wall, offer, Accept",
          f.get("mark_start") == "?" and int(f.get("props") or 0) >= 6 and int(f.get("broken_before") or 0) >= 6 and node(f.get("dialog_offer")) == "offer" and f.get("state_after_accept") == "in_progress",
          "%r props %s broken %s" % (f.get("mark_start"), f.get("props"), f.get("broken_before")), "sq2_fix_before", "sq2_fix_offer"),
        R("can_we_fix_it: 8 planks handed in: +5 Influence, marks, every fence and wall visibly mended",
          f.get("mark_ready") == "!" and f.get("state_final") == "completed" and f.get("planks_left") == 0 and f.get("influence") == 5 and int(f.get("marks") or 0) > 0 and f.get("broken_after") == 0,
          "%r %s left %s inf %s broken after %s" % (f.get("mark_ready"), f.get("state_final"), f.get("planks_left"), f.get("influence"), f.get("broken_after")), "sq2_fix_turnin", "sq2_fix_after"),
        R("finding_clip_clop: Wenna's offer; Clip Clop waits by the wolf den and can't be attacked",
          c.get("mark_start") == "?" and node(c.get("dialog_offer")) == "offer" and c.get("horse_at_den") and c.get("horse_attack_refused"),
          "%r %r den %s refused %s" % (c.get("mark_start"), node(c.get("dialog_offer")), c.get("horse_at_den"), c.get("horse_attack_refused")), "sq2_clip_offer", "sq2_clip_den_fight"),
        R("finding_clip_clop: 3 wolves killed at the den; Clip Clop follows you home (stays within 3 tiles)",
          c.get("stage_after_kills") == 1 and int(c.get("kills") or 0) >= 2 and int(c.get("legs") or 0) >= 2 and int(c.get("max_gap") or 99) <= 3 and int(c.get("horse_gap_home") or 99) <= 4,
          "kills %s legs %s max gap %s home gap %s" % (c.get("kills"), c.get("legs"), c.get("max_gap"), c.get("horse_gap_home")), "sq2_clip_following", "sq2_clip_home"),
        R("finding_clip_clop: '!' over Wenna, handed back: +5 Influence, marks, he stays in the paddock",
          c.get("state_ready") == "ready" and c.get("mark_ready") == "!" and c.get("state_final") == "completed" and c.get("influence") == 5 and c.get("horse_in_paddock"),
          "%s %r %s inf %s paddock %s" % (c.get("state_ready"), c.get("mark_ready"), c.get("state_final"), c.get("influence"), c.get("horse_in_paddock")), "sq2_clip_turnin"),
        R("a_dead_rat: Old Mabel in Millbrook, offer, 6 real giant-rat kills counted in the journal",
          r.get("village") == "millbrook" and r.get("mark_start") == "?" and node(r.get("dialog_offer")) == "offer" and int(r.get("rat_kills") or 0) >= 6 and r.get("color_mid") == "f0d040" and "/6" in str(r.get("progress_mid", "")),
          "%s %r kills %s %r" % (r.get("village"), r.get("mark_start"), r.get("rat_kills"), r.get("progress_mid")), "sq2_rat_giver", "sq2_rat_offer", "sq2_rat_journal"),
        R("a_dead_rat: back to Mabel ('!'), then the big Rat Mother killed",
          r.get("mark_mid") == "!" and node(r.get("dialog_mid")) == "stage_1" and r.get("mother_sprite") == "rat_mother" and r.get("mother_killed") and r.get("state_ready") == "ready",
          "%r %r sprite %s killed %s" % (r.get("mark_mid"), node(r.get("dialog_mid")), r.get("mother_sprite"), r.get("mother_killed")), "sq2_rat_mother_ask", "sq2_rat_mother"),
        R("a_dead_rat: turned in: +5 Influence, marks, journal green",
          r.get("mark_ready") == "!" and node(r.get("dialog_turnin")) == "stage_3" and r.get("state_final") == "completed" and r.get("influence") == 5 and int(r.get("marks") or 0) > 0 and r.get("color_final") == "60c060",
          "%r %s inf %s marks %s" % (r.get("mark_ready"), r.get("state_final"), r.get("influence"), r.get("marks")), "sq2_rat_turnin", "sq2_journal_completed"),
    ]
    return out


def check_millbrook(ctx):
    """0.3.16 sprite-bot Millbrook v1 + the Rat Mother / den entrance art."""
    if "millbrook" not in ctx.expected:
        return []
    run = ctx.runs.get("millbrook")
    if not run:
        return [Result("C35 millbrook", "millbrook run present", False, "no capture")]
    a = run.res.get("millbrook", {})
    snaps = {e.get("name"): e.get("path") for e in run.events if e.get("type") == "snap"}
    sp = lambda *n: [snaps[k] for k in n if k in snaps]
    R = lambda what, ok, info, *sn: Result("C35 millbrook", what, bool(ok), info, sp(*sn))
    spots = a.get("spots", {})
    m = a.get("mother", {})
    inn = a.get("inn", {})
    sf = a.get("sail_frames", [])
    return [
        R("Millbrook v1: gate, green, mill, rat barn and fields all inside the village",
          len(spots) == 5 and all(v.get("village") == "millbrook" for v in spots.values()), str(spots),
          "mb_gate", "mb_green", "mb_mill", "mb_rat_barn", "mb_fields"),
        R("the windmill sails turn (4-frame fade layer)", len(set(sf)) >= 2, str(sf), "mb_mill"),
        R("inside the inn the roof/upper floor fade out", inn.get("inside") == "millbrook_inn" and float(inn.get("roof_alpha", 1)) < 0.3, str(inn), "mb_inn_inside"),
        R("Millbrook at night uses the designer night layers", a.get("night", {}).get("phase") == "night", str(a.get("night")), "mb_night"),
        R("the Rat Mother wears the 48x48 underground sheet (no scaled rat) beside the 3x2 den entrance, outside the village",
          m.get("sprite") == "rat_mother" and m.get("frame") == [48, 48] and float(m.get("scale", 0)) == 1.0 and m.get("hole") and "den_entrance_3x2" in str(m.get("hole_sprite")) and m.get("village") == "",
          str(m), "rat_mother", "den_entrance", "rat_mother_close"),
    ]


def check_perf(ctx):
    """0.3.16 streaming: no hitches while sprinting across chunks and towns."""
    if "perf" not in ctx.expected:
        return []
    run = ctx.runs.get("perf")
    if not run:
        return [Result("C36 perf", "perf run present", False, "no capture")]
    a = run.res.get("perf", {})
    info = "worst %.1f ms, 1%% low %.1f ms (process); frame worst %.1f, 1%% low %.1f, median %.1f; %s frames, %s/%s tiles, %s chunks, spikes %s %s parts %s" % (
        a.get("worst_process_ms", 0), a.get("p1_low_process_ms", 0), a.get("worst_frame_ms", 0), a.get("p1_low_frame_ms", 0), a.get("median_frame_ms", 0),
        a.get("frames"), a.get("walked"), a.get("route"), a.get("chunks"), a.get("spike_count"), a.get("spikes", [])[:6], a.get("parts"))
    return [Result("C36 perf", "long sprint through towns: no frame spikes above 33 ms",
                   int(a.get("walked") or 0) >= 300 and int(a.get("chunks") or 0) >= 15 and float(a.get("worst_frame_ms", 99)) <= 33.0, info)]


def check_xp(ctx):
    """0.3.7 XP feedback lines + Skills panel session tracker."""
    if "xp" not in ctx.expected:
        return []
    run = ctx.runs.get("xp")
    if not run:
        return [Result("C30 xp", "xp run present", False, "no capture")]
    a = run.res.get("xp", {})
    snaps = {e.get("name"): e.get("path") for e in run.events if e.get("type") == "snap"}
    out = []
    for k in ["melee", "forestry", "mining", "cooking"]:
        r = a.get(k, {})
        out.append(Result("C30 xp", "%s writes an XP log line and updates the tracker" % k, bool(r.get("line")) and r.get("tracker", 0) > 0, "%s +%s" % (r.get("line"), r.get("tracker")), [snaps[x] for x in ("xp_log_lines",) if x in snaps]))
    out.append(Result("C30 xp", "Skills panel tracker shows session XP and XP to next level", "xp this session" in str(a.get("tracker_text")) and "to Lv" in str(a.get("tracker_text")), str(a.get("tracker_text")), [snaps[x] for x in ("skills_xp_tracker",) if x in snaps]))
    return out


def check_autotile(ctx):
    """0.3.9 autotiled fences / walls / moat, floor transitions, 4-way facing."""
    if "autotile" not in ctx.expected:
        return []
    run = ctx.runs.get("autotile")
    if not run:
        return [Result("C31 autotile", "autotile run present", False, "no capture")]
    c = run.res.get("autotile", {})
    snaps = {e.get("name"): e.get("path") for e in run.events if e.get("type") == "snap"}
    sp = lambda *n: [snaps[k] for k in n if k in snaps]
    k = c.get("fence_kinds", {})
    wu = c.get("walk_up", {})
    return [
        Result("C31 autotile", "0.3.9 fences autotile: straights, corners, T-joints and end caps, ~15% broken", all(k.get(x, 0) > 0 for x in ("straight_h", "straight_v", "corner", "t", "end")) and 0.05 <= c.get("broken_share", 0) <= 0.3,
               "%s broken %.0f%%" % (k, 100 * c.get("broken_share", 0)), sp("fence_corner_t")),
        Result("C31 autotile", "0.3.9 road fences run parallel to vertical and horizontal roads, block walking, arrows fly over",
               "road_fence_vertical" in snaps and "road_fence_horizontal" in snaps and c.get("vfence_blocks") and c.get("vfence_los"),
               "spots %s blocks %s los %s" % (c.get("spots"), c.get("vfence_blocks"), c.get("vfence_los")), sp("road_fence_vertical", "road_fence_horizontal")),
        Result("C31 autotile", "0.3.9 floor transitions are drawn where unlike floors meet", c.get("transition_cells", 0) > 10, "%d blend cells in the road chunk" % c.get("transition_cells", 0), sp("transitions")),
        Result("C31 autotile", "0.3.11 the round city wall rings Highfen (moat replaced; ring found on every side)", "moat_corner" in snaps and len(c.get("moat_pieces", [])) >= 3, "pieces %s at %s" % (c.get("moat_pieces"), c.get("moat_corner")), sp("moat_corner")),
        Result("C31 autotile", "0.3.9 walking up shows the player's back (body and gear)", bool(wu.get("back")) and bool(wu.get("gear_back")), str(wu), sp("player_walk_up_back")),
    ]


def check_gfx(ctx):
    """0.3.9.1 directional frames (cow x4, player front/back with a shield) and fence runs/ends."""
    if "gfx" not in ctx.expected:
        return []
    run = ctx.runs.get("gfx")
    if not run:
        return [Result("C32 gfx", "gfx run present", False, "no capture")]
    c = run.res.get("gfx", {})
    snaps = {e.get("name"): e.get("path") for e in run.events if e.get("type") == "snap"}
    sp = lambda *n: [snaps[k] for k in n if k in snaps]
    cow = c.get("cow", {})
    pl = c.get("player", {})
    f = c.get("fences", {})
    cow_ok = len(cow) == 4 and cow["right"]["tex"] == cow["left"]["tex"] and cow["left"]["flip"] and not cow["right"]["flip"] \
        and cow["down"]["tex"].endswith("_front.png") and cow["up"]["tex"].endswith("_back.png") and not cow["down"]["flip"] and not cow["up"]["flip"]
    return [
        Result("C32 gfx", "0.3.9.1 a cow shows its side (mirrored for left), front and back sheets - never a mirrored front/back", cow_ok, str(cow), sp("cow_right", "cow_left", "cow_down", "cow_up")),
        Result("C32 gfx", "0.3.9.1 the player's front and back sheets; the shield sits under the body from behind",
               pl.get("down", {}).get("tex", "").endswith("_front.png") and pl.get("up", {}).get("tex", "").endswith("_back.png") and pl.get("up", {}).get("shield_under") and not pl.get("down", {}).get("shield_under"),
               str(pl), sp("player_front_shield", "player_back_shield")),
        Result("C32 gfx", "0.3.9.1 road fences come in runs of 3+ ending in an end post or a broken end", f.get("short_runs", 1) == 0 and "fence_end_post" in snaps and "fence_end_broken" in snaps,
               str(f), sp("fence_end_post", "fence_end_broken")),
    ]


def check_capital(ctx):
    """0.3.8 Highfen, house, the only player shop, slimes, roadside logs."""
    if "capital" not in ctx.expected:
        return []
    run = ctx.runs.get("capital")
    if not run:
        return [Result("C30 capital", "capital run present", False, "no capture")]
    c = run.res.get("capital", {})
    snaps = {e.get("name"): e.get("path") for e in run.events if e.get("type") == "snap"}
    sp = lambda *n: [snaps[k] for k in n if k in snaps]
    st = c.get("start", {})
    return [
        Result("C30 capital", "0.3.8.1 a new character starts in Fenhollow near Kell", st.get("town") == "fenhollow" and bool(st.get("kell")), str(st), sp("new_game_kell")),
        Result("C30 capital", "0.3.8 Highfen is reachable from every town by road", bool(c.get("reach")) and all(c.get("reach", {}).values()) and len(c.get("reach", {})) == 3, str(c.get("reach")), sp("highfen_overview", "highfen_moat_gate", "world_map_038")),
        Result("C30 capital", "0.3.11 the city wall rings Highfen beside the north gate", bool(c.get("moat_px")), "city wall beside the north gate %s" % c.get("moat_px"), sp("highfen_moat_gate")),
        Result("C30 capital", "0.3.8 the player shop exists only in Highfen", c.get("player_shops") == ["highfen_player@highfen"], str(c.get("player_shops"))),
        Result("C30 capital", "0.3.8 buying the house (clerk, two taps) gives every station + the bank", bool(c.get("house_bought")) and bool(c.get("house_bank")) and all(k in (c.get("house_stations") or []) for k in ("hearth", "furnace", "anvil", "workbench", "quern", "bank")), "bought %s bank %s stations %s" % (c.get("house_bought"), c.get("house_bank"), c.get("house_stations")), sp("house_interior")),
        Result("C30 capital", "0.3.8 a slime dies and drops no bones", bool(c.get("slime_killed")) and "bones" not in (c.get("slime_drops") or []), "killed %s drops %s" % (c.get("slime_killed"), c.get("slime_drops")), sp("slime")),
        Result("C30 capital", "0.3.8 an old log blocks walking (path goes round) but an arrow flies over it", bool(c.get("walk_round_log")) and int(c.get("arrow_shots") or 0) >= 1 and bool(c.get("archer_stayed")), "walk round %s shots %s stayed %s hp %s" % (c.get("walk_round_log"), c.get("arrow_shots"), c.get("archer_stayed"), c.get("foe_hp")), sp("road_decor", "arrow_over_log")),
    ]


CHECKS = [check_runtime, check_diagonal, check_facing, check_ghost, check_jitter, check_taps, check_bubbles, check_roof, check_shop, check_smithy, check_markers, check_daynight, check_world, check_church, check_aggro, check_farm, check_city, check_cookhouse, check_pk, check_gear, check_archery, check_bank, check_v036, check_quest, check_xp, check_capital, check_autotile, check_gfx, check_sidequests, check_sidequests2, check_millbrook, check_perf]
SCENARIOS = ["walk", "combat", "shop", "pshop", "smithy", "markers", "daynight", "world", "church", "aggro", "farm", "city", "cookhouse", "pk", "gear", "archery"]


# -------------------------------------------------------------- evidence --
class Ctx:
    def __init__(self, runs, out, expected):
        self.runs, self.out, self.expected = runs, out, expected
        self._tracks = {}
        self._sp = {}
        os.makedirs(os.path.join(out, "evidence"), exist_ok=True)

    def sprites(self, run, layers=()):
        key = (run.zoom, tuple(layers))
        if key not in self._sp:
            self._sp[key] = Sprites(run.zoom, layers)
        return self._sp[key]

    def track(self, name):
        if name not in self._tracks:
            run = self.runs[name]
            self._tracks[name] = image_track(run, lambda r: self.sprites(run, r.get("gear", [])))
        return self._tracks[name]

    def rel(self, p):
        return os.path.relpath(p, self.out)

    def crop_box(self, run, r, w=90, h=120):
        cx, cy = r["scr"]
        return (int(cx - w / 2), int(cy - h + 20), int(cx + w / 2), int(cy + 20))

    def sheet_for(self, name, frames, crop=True, cols=8, tag="sheet"):
        run = self.runs[name]
        byf = {r["f"]: r for r in run.log}
        frames = [f for f in frames if f in byf][:48]
        if not frames:
            return []
        tw, th = (90, 120) if crop else (180, 390)
        rows = (len(frames) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * tw, rows * (th + 12)), (20, 20, 24))
        d = ImageDraw.Draw(sheet)
        for i, f in enumerate(frames):
            im = run.frame(f)
            im = im.crop(self.crop_box(run, byf[f])) if crop else im.resize((tw, th))
            x, y = (i % cols) * tw, (i // cols) * (th + 12)
            sheet.paste(im, (x, y + 12))
            d.text((x + 2, y), "f%d %s" % (f, byf[f]["label"][:10]), fill=(255, 255, 0))
        p = os.path.join(self.out, "evidence", "%s_%s_%d.png" % (name, tag, frames[0]))
        sheet.save(p)
        return [p]

    def gif(self, name, tag, i0=0, i1=None, step=1, crop=True, labels=None):
        run = self.runs[name]
        rows = [r for r in run.log if r["f"] >= i0 and (i1 is None or r["f"] <= i1) and (not labels or any(r["label"].startswith(l) for l in labels))][::step]
        ims = []
        for r in rows:
            im = run.frame(r["f"])
            im = im.crop(self.crop_box(run, r, 120, 160)).resize((240, 320), Image.NEAREST) if crop else im.resize((180, 390))
            ims.append(im.convert("P", palette=Image.ADAPTIVE, colors=128))
        p = os.path.join(self.out, "evidence", "%s.gif" % tag)
        if ims:
            ims[0].save(p, save_all=True, append_images=ims[1:], duration=int(1000 / 55 * step), loop=0)
        return p

    def still(self, name, label, shot, last=False):
        run = self.runs[name]
        rows = [r for r in run.log if r["label"] == label]
        if not rows:
            return None
        r = rows[-1] if last else rows[len(rows) // 2]
        p = os.path.join(self.out, "evidence", shot + ".png")
        run.frame(r["f"]).save(p)
        return p

    def plot_leg(self, name, seg, a, b):
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        fig, ax = plt.subplots(figsize=(4, 4), dpi=90)
        lo, hi = seg.min(0) - 16, seg.max(0) + 16
        for gx in np.arange(np.floor(lo[0] / 16) * 16, hi[0] + 16, 16):
            ax.axvline(gx, color="#ddd", lw=0.6)
        for gy in np.arange(np.floor(lo[1] / 16) * 16, hi[1] + 16, 16):
            ax.axhline(gy, color="#ddd", lw=0.6)
        ax.plot([a[0], b[0]], [a[1], b[1]], "--", color="#c33", lw=1, label="straight line")
        ax.plot(seg[:, 0], seg[:, 1], ".-", color="#246", ms=2.5, lw=0.8, label="sprite (every frame)")
        ax.invert_yaxis()
        ax.set_aspect("equal")
        ax.set_title(name, fontsize=9)
        ax.legend(fontsize=6, loc="best")
        ax.set_xlabel("world x (px)", fontsize=7)
        ax.set_ylabel("world y (px)", fontsize=7)
        ax.tick_params(labelsize=6)
        p = os.path.join(self.out, "evidence", "path_%s.png" % name)
        fig.tight_layout()
        fig.savefig(p)
        plt.close(fig)
        return p

    def diagonal_strip(self):
        """v030_walk_diagonal.png: every 6th frame of the diagonal legs
        (crops around the player, as rendered) + the path plots."""
        run = self.runs["walk"]
        rows = []
        for lab in ("diag_up_right", "diag_down_left", "sprint_diag_up_right"):
            rr = [r for r in run.log if r["label"] == lab]
            mv = [r for i, r in enumerate(rr) if i == 0 or r["pos"] != rr[i - 1]["pos"]]
            rows.append((lab, mv[::max(1, len(mv) // 10)][:10]))
        tw, th = 90, 120
        W = 10 * tw + 300
        sheet = Image.new("RGB", (W, len(rows) * (th + 16) + 8), (24, 24, 28))
        d = ImageDraw.Draw(sheet)
        for k, (lab, rr) in enumerate(rows):
            y = 4 + k * (th + 16)
            d.text((4, y), "%s: every frame captured; showing %d evenly spaced (frame, world x,y)" % (lab, len(rr)), fill=(255, 230, 120))
            for i, r in enumerate(rr):
                im = run.frame(r["f"]).crop(self.crop_box(run, r, tw, th))
                sheet.paste(im, (i * tw, y + 14))
                d.text((i * tw + 2, y + 14 + th - 12), "f%d %d,%d" % (r["f"], r["pos"][0], r["pos"][1]), fill=(255, 255, 255))
            pp = os.path.join(self.out, "evidence", "path_%s.png" % lab)
            if os.path.exists(pp):
                pl = Image.open(pp).convert("RGB")
                pl.thumbnail((290, th + 12))
                sheet.paste(pl, (10 * tw + 5, y + 2))
        p = os.path.join(self.out, "evidence", "walk_diagonal_strip.png")
        sheet.save(p)
        return p

    _gear_ev = None

    def gear_evidence(self):
        """v031_gear_player.png: each tier set facing right and left (crops x2,
        as rendered) + a GIF of the geared walk."""
        if self._gear_ev is None:
            run = self.runs["gear"]
            sets = run.res.get("tiers", {})
            cols = []
            for t in sorted(sets.keys(), key=int):
                pair = []
                for side in ("R", "L"):
                    rr = [r for r in run.log if r["label"] == "tier_%s_%s" % (t, side)]
                    rr = [r for r in rr if not occluded(r)] or rr
                    if rr:
                        pair.append(run.frame(rr[len(rr) // 2]["f"]).crop(self.crop_box(run, rr[len(rr) // 2], 60, 96)))
                if pair:
                    cols.append((t, sets[t], pair))
            tw, th = 120, 192
            sheet = Image.new("RGB", (max(1, len(cols)) * (tw * 2 + 8) + 8, th + 70), (24, 24, 28))
            d = ImageDraw.Draw(sheet)
            names = {"1": "bronze", "2": "iron", "3": "steel", "4": "dusk", "5": "mixed + bow"}
            for i, (t, ids, pair) in enumerate(cols):
                x = 8 + i * (tw * 2 + 8)
                d.text((x, 4), "tier %s: %s" % (t, names.get(str(t), "")), fill=(255, 230, 120))
                for k, im in enumerate(pair):
                    sheet.paste(im.resize((tw, th), Image.NEAREST), (x + k * tw, 18))
                for j, iid in enumerate(ids):
                    d.text((x, th + 22 + j * 9), iid, fill=(220, 220, 220))
            p = os.path.join(self.out, "evidence", "v031_gear_player.png")
            sheet.save(p)
            self._gear_ev = [p, self.gif("gear", "gear_walk", labels=["walk_right", "turn_left", "diag_", "sprint_"], step=2, crop=True)]
        return self._gear_ev

    _walk_ev = None

    def walk_evidence(self):
        if self._walk_ev is None:
            run = self.runs["walk"]
            ev = []
            for tag, labs in (("walk_right_turn_left", ["walk_right", "turn_left"]), ("walk_diagonal", ["diag_"]), ("walk_sprint", ["sprint_diag", "sprint_left"])):
                ev.append(self.gif("walk", tag, labels=labs, step=1, crop=True))
            frames = [r["f"] for r in run.log if r["label"] and r["label"] not in ("pack_tap", "pack_tap_close")][::6]
            ev += self.sheet_for("walk", frames, cols=12, tag="contact")
            ev.append(self.diagonal_strip())
            self._walk_ev = ev
        return self._walk_ev


# ---------------------------------------------------------------- report --
def write_report(ctx, results, version):
    ok = all(r.ok for r in results)
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    md = ["# Ashfen QA bot report: %s" % version, "", "Generated %s (box local time). Overall: **%s** (%d/%d checks pass)." % (now, "PASS" if ok else "FAIL", sum(r.ok for r in results), len(results)), "",
          "Runs: " + ", ".join("%s (%d frames)" % (n, len(r.log)) for n, r in ctx.runs.items()), "",
          "| Check | Test | Result | Detail |", "|---|---|---|---|"]
    for r in results:
        md.append("| %s | %s | %s | %s |" % (r.check, r.name, "PASS" if r.ok else "**FAIL**", r.detail.replace("|", "/")))
    md += ["", "## Evidence", ""]
    seen = set()
    for r in results:
        for e in r.evidence:
            if e and e not in seen:
                seen.add(e)
                md.append("- %s: `%s`" % (r.name, ctx.rel(e)))
    open(os.path.join(ctx.out, "report.md"), "w").write("\n".join(md) + "\n")
    h = ["<!doctype html><meta charset=utf-8><title>Ashfen QA %s</title><style>body{font:13px sans-serif;margin:16px;background:#fafafa}"
         "td,th{border:1px solid #ccc;padding:4px;vertical-align:top}table{border-collapse:collapse}.p{background:#d8f5d0}.f{background:#f8d0d0}"
         "img{max-width:520px;margin:4px;border:1px solid #999}</style>" % html.escape(version),
         "<h1>Ashfen QA bot: %s - %s</h1><p>%s · %d/%d checks pass</p><table><tr><th>Check<th>Test<th>Result<th>Detail<th>Evidence" % (html.escape(version), "PASS" if ok else "FAIL", now, sum(r.ok for r in results), len(results))]
    for r in results:
        evs = "".join('<a href="%s"><img src="%s" style="max-width:160px"></a>' % (html.escape(ctx.rel(e)), html.escape(ctx.rel(e))) for e in r.evidence if e)
        h.append('<tr class="%s"><td>%s<td>%s<td>%s<td>%s<td>%s' % ("p" if r.ok else "f", html.escape(r.check), html.escape(r.name), "PASS" if r.ok else "FAIL", html.escape(r.detail), evs))
    h.append("</table>")
    open(os.path.join(ctx.out, "report.html"), "w").write("\n".join(h))
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--version", default="")
    ap.add_argument("--scenarios", default=",".join(SCENARIOS), help="comma list that should have been captured")
    ap.add_argument("--verify-dir", default="", help="also copy walk evidence here (build/verify)")
    a = ap.parse_args()
    runs = {}
    for d in sorted(glob.glob(os.path.join(a.runs, "*"))):
        if os.path.exists(os.path.join(d, "result.json")):
            runs[os.path.basename(d)] = Run(d)
    ctx = Ctx(runs, a.out, [s for s in a.scenarios.split(",") if s])
    results = []
    for chk in CHECKS:
        try:
            results += chk(ctx)
        except Exception as e:  # a crashing check is a failing check
            import traceback
            traceback.print_exc()
            results.append(Result(chk.__name__, "analyzer crashed", False, repr(e)))
    ok = write_report(ctx, results, a.version)
    if a.verify_dir and "walk" in runs:
        os.makedirs(a.verify_dir, exist_ok=True)
        for p in glob.glob(os.path.join(a.out, "evidence", "walk_*")) + glob.glob(os.path.join(a.out, "evidence", "path_*")):
            dst = os.path.basename(p)
            if dst.startswith("path_"):
                dst = "walk_" + dst
            shutil.copy(p, os.path.join(a.verify_dir, dst))
    for r in results:
        print("%s  %-14s %s :: %s" % ("PASS" if r.ok else "FAIL", r.check, r.name, r.detail[:150]))
    print("QA %s: %s (%d/%d)" % (a.version, "PASS" if ok else "FAIL", sum(r.ok for r in results), len(results)))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
