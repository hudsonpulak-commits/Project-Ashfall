#!/usr/bin/env python3
"""Lists every sprite referenced by data/sprites.json and whether it is still
the generated placeholder, has been replaced with hand-made art, or is missing.

Usage: python3 tools/art_status.py [--markdown]
"""
import os, sys, json, hashlib
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPR = os.path.join(ROOT, "assets", "sprites")
manifest = json.load(open(os.path.join(SPR, "placeholders.json")))
mapping = json.load(open(os.path.join(ROOT, "data", "sprites.json")))

def status(res_path):
    rel = res_path.replace("res://assets/sprites/", "")
    p = os.path.join(SPR, rel)
    if not os.path.exists(p):
        return rel, "MISSING", ""
    from PIL import Image
    w, h = Image.open(p).size
    sha = hashlib.sha256(open(p, "rb").read()).hexdigest()
    st = "placeholder" if manifest.get(rel) == sha else "HAND-MADE"
    return rel, st, f"{w}x{h}"

rows = []
for cat in ("tiles", "objects", "actors", "items", "ui"):
    for key, e in mapping.get(cat, {}).items():
        rel, st, size = status(e["path"])
        rows.append((cat, key, rel, size, st))
md = "--markdown" in sys.argv
if md:
    print("| Category | Id | File | Size (px) | Status |\n|---|---|---|---|---|")
for r in rows:
    print(("| " + " | ".join(r) + " |") if md else "%-8s %-16s %-36s %-7s %s" % r)
done = sum(1 for r in rows if r[4] == "HAND-MADE")
print(("\n" if md else "") + f"{done}/{len(rows)} sprites hand-made, {sum(1 for r in rows if r[4]=='MISSING')} missing")
