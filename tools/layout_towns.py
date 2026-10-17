#!/usr/bin/env python3
"""0.3.0: rebuild data/towns/*.json for walk-in shop buildings.

Each 24x24 0.2.x town becomes 46x38 centred on the SAME spawn (so roads,
camps and the dry ring are unchanged). The old resource quadrants are moved
to the four corners unchanged. The middle holds the plaza (bank, Exchange,
stations, dummy), four shop slots (two north of the plaza with doors facing
south, two south with doors facing north) and the empty player shop in the
west band.

Buildings are written explicitly (town-local coords, same grid as "rows"):
rect, door, counter, keeper, stand (tile in front of the counter), sign,
props and, for the player shop, display slots. WorldGen applies them on top
of the rows. Re-running is idempotent (it reads the layout from
tools/town_sources/*.json, the frozen 0.2.x towns).

    python3 tools/layout_towns.py
"""
import json, os, collections
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "town_sources")
OUT = os.path.join(ROOT, "data", "towns")
W, H = 46, 38
CX, CY = 23, 19                     # spawn / centre (local)
SHOPS = json.load(open(os.path.join(ROOT, "data", "buildings.json")))["shops"]

# slot -> (rect x, rect y, door side)
SLOTS = {"N1": (13, 2, "S"), "N2": (25, 2, "S"), "S1": (13, 29, "N"), "S2": (25, 29, "N")}
PLAYER_SLOT = (2, 11, "S")
GENERAL_NAMES = {"fenhollow": "Fenhollow Provisions", "cinderholt": "Cinderholt Supply", "saltmere": "Saltmere Chandlery"}
GENERAL_KEEPERS = {"fenhollow": "Marla Thatch", "cinderholt": "Osric Coalby", "saltmere": "Nell Brine"}
ROOFS = {"fenhollow": "#9a7a4a", "cinderholt": "#6a6e7c", "saltmere": "#4a7a8a"}
STATIONS = {"B": (16, 13), "E": (20, 13), "H": (26, 13), "W": (16, 24), "D": (30, 24)}   # furnace + anvil: in the Blacksmith
SMITHY = json.load(open(os.path.join(ROOT, "data", "buildings.json")))["smithy"]


def fy(y, side):
    """Template y (door south) -> actual (flipped for door north)."""
    return y if side == "S" else 6 - y


def shop_building(town, shop, rect_x, rect_y, side):
    sd = SHOPS[shop]
    P = lambda x, y: [rect_x + x, rect_y + fy(y, side)]
    props = sd["props"]
    b = collections.OrderedDict()
    b["id"] = f"{town}_{shop}"
    b["kind"] = "shop"
    b["shop"] = shop
    if shop == "general":
        b["name"] = GENERAL_NAMES[town]
        b["keeper"] = GENERAL_KEEPERS[town]
    b["rect"] = [rect_x, rect_y, 9, 7]
    b["door"] = [P(4, 6)]
    b["counter"] = [P(x, 2) for x in range(2, 7)]
    b["keeper_at"] = P(4, 1)
    b["stand"] = P(4, 3)
    b["sign"] = P(5, 6)
    b["props"] = [
        {"object": props["back"], "at": P(1, 1)}, {"object": props["back"], "at": P(7, 1)},
        {"object": props["corner"], "at": P(1, 2)}, {"object": props["corner"], "at": P(7, 2)},
        {"object": props["rack"], "at": P(1, 4)}, {"object": props["rack2"], "at": P(7, 4)},
    ]
    return b


def smithy_building(town, shop, rect_x, rect_y, side):
    """0.3.0 Blacksmith: 9x9, the town's weapon-smith shop (counter + smith, west)
    and the forge (anvil, furnace, bellows, quench barrel, east) under one roof.
    Template is door-north (south slots); stations keep a free floor tile south."""
    assert side == "N", "smithy template is for the south slots (door north)"
    sd = SHOPS[shop]
    P = lambda x, y: [rect_x + x, rect_y + y]
    b = collections.OrderedDict()
    b["id"] = f"{town}_{shop}"
    b["kind"] = "smithy"
    b["shop"] = shop
    b["name"] = SMITHY["name"]
    b["rect"] = [rect_x, rect_y, 9, 9]
    b["door"] = [P(4, 0)]
    b["counter"] = [P(x, 6) for x in range(1, 4)]
    b["keeper_at"] = P(2, 7)
    b["stand"] = P(2, 5)
    b["sign"] = P(5, 0)
    b["forge"] = [P(5, 1), P(7, 7)]          # forge-area rect corners (floor tint / tests)
    b["props"] = [
        {"object": "anvil", "at": P(6, 2)}, {"object": "furnace", "at": P(6, 5)},
        {"object": "bellows", "at": P(7, 5)}, {"object": "quench_barrel", "at": P(7, 3)},
        {"object": "weapon_rack", "at": P(7, 1)}, {"object": "coal_crate", "at": P(7, 7)},
        {"object": sd["props"]["rack"], "at": P(1, 1)}, {"object": sd["props"]["back"], "at": P(1, 7)},
        {"object": sd["props"]["back"], "at": P(3, 7)},
    ]
    return b


def player_building(town, rect_x, rect_y, side):
    P = lambda x, y: [rect_x + x, rect_y + fy(y, side)]
    b = collections.OrderedDict()
    b["id"] = f"{town}_player"
    b["kind"] = "player"
    b["shop"] = "player"
    b["name"] = "Empty shop"
    b["rect"] = [rect_x, rect_y, 9, 7]
    b["door"] = [P(4, 6)]
    b["counter"] = [P(x, 2) for x in range(3, 6)]
    b["keeper_at"] = P(4, 1)
    b["stand"] = P(4, 3)
    b["sign"] = P(5, 6)
    b["displays"] = [P(2, 1), P(6, 1), P(2, 2), P(6, 2), P(1, 4), P(7, 4), P(1, 5), P(7, 5)]
    b["props"] = []
    return b


def build(town):
    src = json.load(open(os.path.join(SRC, town + ".json")), object_pairs_hook=collections.OrderedDict)
    old = src["rows"]
    objs = src["objects"]
    strip = lambda s: "".join("." if c in objs else c for c in s)
    g = [["." for _ in range(W)] for _ in range(H)]
    def put(x0, y0, rows):
        for y, r in enumerate(rows):
            for x, c in enumerate(r):
                g[y0 + y][x0 + x] = c
    # bands: repeat the old row-9 edge pattern (objects stripped) so coasts continue
    for y in range(10, 30):
        put(0, y, [strip(old[9][0:12])])
        put(35, y, [strip(old[9][13:24])])
    put(0, 0, [r[0:12] for r in old[0:10]])
    put(35, 0, [r[13:24] for r in old[0:10]])
    put(0, 30, [r[0:12] for r in old[16:24]])
    put(35, 30, [r[13:24] for r in old[16:24]])
    # roads
    for y in range(H):
        g[y][CX] = "="
    for x in range(W):
        g[CY][x] = "="
    # plaza
    for y in range(9, 29):
        for x in range(12, 35):
            g[y][x] = "#"
    for k, (x, y) in STATIONS.items():
        g[y][x] = k
    # buildings
    specs = src["specialists"]
    order = ["general"] + specs
    bl = []
    for slot, shop in zip(["N1", "N2", "S1", "S2"], order):
        x, y, side = SLOTS[slot]
        if shop in SMITHY["smith_shops"]:
            bl.append(smithy_building(town, shop, x, y - 2, side))   # 2 rows taller, into the plaza edge
        else:
            bl.append(shop_building(town, shop, x, y, side))
    bl.append(player_building(town, *PLAYER_SLOT))
    for b in bl:
        x0, y0, w, h = b["rect"]
        doors = {tuple(d) for d in b["door"]}
        facade = y0 + h - 1 if b["door"][0][1] == y0 + h - 1 else y0
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                edge = x in (x0, x0 + w - 1) or y in (y0, y0 + h - 1)
                c = ";"
                if (x, y) in doors:
                    c = "+"
                elif edge:
                    c = "^" if y == facade else "%"
                g[y][x] = c
    # the door step outside must be walkable ground
    for b in bl:
        d = b["door"][0]
        out = d[1] + (1 if d[1] == b["rect"][1] + b["rect"][3] - 1 else -1)
        if g[out][d[0]] not in "#=.":
            g[out][d[0]] = "#"
    t = collections.OrderedDict()
    for k in ["id", "name"]:
        t[k] = src[k]
    sp = src["spawn"]
    t["origin"] = [sp[0] - CX, sp[1] - CY]
    t["spawn"] = sp
    t["rows"] = ["".join(r) for r in g]
    tiles = collections.OrderedDict(src["tiles"])
    tiles.update({"%": "wall", "^": "wall_front", ";": "floor", "+": "doorway"})
    t["tiles"] = tiles
    o = collections.OrderedDict((k, v) for k, v in objs.items() if not (v["object"].startswith("shop_") or v["object"] in ("general_store", "furnace", "anvil")))
    t["objects"] = o
    t["roof"] = ROOFS[town]
    t["buildings"] = bl
    for k in src:
        if k not in t and k not in ("rows",):
            t[k] = src[k]
    return t


if __name__ == "__main__":
    for f in sorted(os.listdir(SRC)):
        town = f[:-5]
        t = build(town)
        json.dump(t, open(os.path.join(OUT, f), "w"), indent=1, ensure_ascii=False)
        open(os.path.join(OUT, f), "a").write("\n")
        print(town, "origin", t["origin"], "buildings", [b["id"] for b in t["buildings"]])
        print("\n".join(t["rows"]))
