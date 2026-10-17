#!/usr/bin/env python3
"""0.3.1 villages: writes data/towns/<village>.json from one hand-made core
layout (3 cottages, a well, a quern, a cooking hearth, a plaza) plus a fenced
wheat field and a fenced cow pasture. The village files are plain data and can
be hand-edited afterwards; this script just keeps the three in step.

Placement (origin, which side the road is on) came from the real world dump
(tools/export_world_map.gd): beside each city-to-city road near its midpoint,
on dry land, away from creature camps and mines. Coordinates in the files are
village-local (add "origin"); the field/pasture rects lie OUTSIDE the core
rows (the village rect is the safe zone; the pasture is not, so cows fight).

    python3 tools/layout_villages.py
"""
import json, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

W, H = 24, 14
CORE = [
    "........................",
    "........................",
    "........................",
    "........................",
    "........................",
    "....=..............=....",
    "...==================...",
    "...=..H...O...Q...=.....",
    "...=........=...........",
    "...=........=...........",
    "............=...........",
    "............=...........",
    "............=...........",
    "............=...........",
]
HOUSES = [  # rect, door, sign, keeper, stand, props (S layout: road to the south)
    {"rect": [1, 0, 7, 5], "door": [4, 4], "sign": [5, 4], "keeper_at": [4, 1], "stand": [4, 2],
     "props": [["barrel", 2, 1], ["sacks", 6, 1]]},
    {"rect": [16, 0, 7, 5], "door": [19, 4], "sign": [20, 4], "keeper_at": [19, 1], "stand": [19, 2],
     "props": [["crate", 17, 1], ["barrel", 21, 1]]},
    {"rect": [16, 8, 7, 5], "door": [19, 8], "sign": [20, 8], "keeper_at": [19, 11], "stand": [19, 10],
     "props": [["sacks", 17, 11], ["crate", 21, 11]]},
]
FIELD = [0, -9, 11, 8]       # fenced wheat, gate on the side facing the village
PASTURE = [12, -9, 12, 8]    # fenced cows

VILLAGES = [
    {"id": "millbrook", "name": "Millbrook", "box": [132, -107], "road": "S", "between": ["fenhollow", "cinderholt"],
     "tagline": "Wheat and windbreaks on the Cinder road.", "roof": "#a0784a",
     "folk": ["Hob Miller", "Wenna Thresh", "Old Corin"]},
    {"id": "barrowby", "name": "Barrowby", "box": [148, 126], "road": "N", "between": ["fenhollow", "saltmere"],
     "tagline": "A herding hamlet on the Salt road.", "roof": "#8a7050",
     "folk": ["Dunstan Hay", "Mabel Crook", "Pell Oxley"]},
    {"id": "oxley", "name": "Oxley", "box": [276, -35], "road": "E", "between": ["cinderholt", "saltmere"],
     "tagline": "Cattle country between the hills and the sea.", "roof": "#946a44",
     "folk": ["Tamsin Byre", "Rufus Plough", "Edda Wold"]},
]


def flip_y(y, h=1):
    return H - y - h


def build(v):
    rows = [list(r) for r in CORE]
    houses = [json.loads(json.dumps(h)) for h in HOUSES]
    field, past = list(FIELD), list(PASTURE)
    gate = [12, 13]
    if v["road"] == "E":
        for x in range(19, W):
            rows[6][x] = "="
        gate = [W - 1, 6]
    if v["road"] == "N":   # mirror top/bottom: the plaza path leads north, fields go south
        rows = rows[::-1]
        for hs in houses:
            r = hs["rect"]
            r[1] = flip_y(r[1], r[3])
            for k in ("door", "sign", "keeper_at", "stand"):
                hs[k][1] = flip_y(hs[k][1])
            for p in hs["props"]:
                p[2] = flip_y(p[2])
        field[1] = H + 1
        past[1] = H + 1
        gate = [12, 0]
    org = [v["box"][0], v["box"][1] + (9 if v["road"] != "N" else 0)]
    blds = []
    for i, hs in enumerate(houses):
        blds.append({"id": "%s_house_%d" % (v["id"], i + 1), "kind": "house", "name": "%s's cottage" % v["folk"][i].split()[-1 if i != 2 else 1],
                     "keeper": v["folk"][i], "keeper_sprite": "villager", "sign_sprite": "sign_house", "roof": v["roof"],
                     "rect": hs["rect"], "door": [hs["door"]], "keeper_at": hs["keeper_at"], "stand": hs["stand"], "sign": hs["sign"],
                     "props": [{"object": p[0], "at": [p[1], p[2]]} for p in hs["props"]]})
    fgate = [field[0] + field[2] // 2, field[1] + field[3] - 1] if v["road"] != "N" else [field[0] + field[2] // 2, field[1]]
    pgate = [past[0] + past[2] // 2, past[1] + past[3] - 1] if v["road"] != "N" else [past[0] + past[2] // 2, past[1]]
    plaza_y = 6 if v["road"] != "N" else H - 1 - 6
    return {
        "id": v["id"], "name": v["name"], "kind": "village", "between": v["between"], "tagline": v["tagline"],
        "origin": org, "spawn": [org[0] + 12, org[1] + plaza_y],
        "rows": ["".join(r) for r in rows], "transparent": ".",
        "tiles": {"=": "path"},
        "objects": {"H": {"object": "hearth", "ground": "path"}, "O": {"object": "well", "ground": "path"},
                    "Q": {"object": "quern", "ground": "path"}},
        "roof": v["roof"], "gate": gate, "buildings": blds,
        "farms": [{"id": v["id"] + "_wheat", "rect": field, "crop": "wheat", "ground": "dirt", "gate": fgate}],
        "pastures": [{"id": v["id"] + "_pasture", "rect": past, "enemy": "cow", "count": 4, "gate": pgate}],
        "citizens": {"area": [3, plaza_y - 1 if v["road"] != "N" else plaza_y - 2, 17, 4], "count": 3},
    }


for v in VILLAGES:
    d = build(v)
    p = os.path.join(ROOT, "data", "towns", v["id"] + ".json")
    with open(p, "w") as f:
        json.dump(d, f, indent=1, ensure_ascii=True)
        f.write("\n")
    print("wrote", p, "origin", d["origin"])
