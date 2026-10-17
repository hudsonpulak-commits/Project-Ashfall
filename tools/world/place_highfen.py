#!/usr/bin/env python3
"""0.3.8 Highfen, the circular moated capital at the continent centre.
Generates data/towns/highfen.json in the game's real town schema (rows +
tiles/objects maps + buildings + gates) from Grok's design
(Dropbox /Game/highfen_capital.json: circle, moat, 4 gates/bridges, pale
stone, buyable house with every station + bank chest, the only player shop).
Re-run after editing the constants below."""
import json, math, os
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
N = 72                      # grid size (tiles)
C = (N - 1) / 2.0           # 35.5
CENTER = (180, -10)         # continent centre (data/world.json)
R_IN, R_WALL, R_VERGE, R_EDGE1, R_MOAT, R_EDGE2 = 26.5, 28.5, 30.0, 31.0, 34.0, 35.0
AV = (34, 35, 36)           # the two avenues (cols and rows) cross at the plaza


def build():
    g = [["." for _ in range(N)] for _ in range(N)]
    for y in range(N):
        for x in range(N):
            r = math.hypot(x - C, y - C)
            if r <= R_IN:
                g[y][x] = ":"
                if r <= 6.0:
                    g[y][x] = "*"
            elif r <= R_WALL:
                g[y][x] = "^" if y > C and math.hypot(x - C, y - 1 - C) <= R_IN + 0.5 else "#"
            elif r <= R_VERGE:
                g[y][x] = "."
            elif r <= R_EDGE1:
                g[y][x] = "-"
            elif r <= R_MOAT:
                g[y][x] = "~"
            elif r <= R_EDGE2:
                g[y][x] = "-"
    # avenues: stone road from gate to gate through the plaza, bridges over the moat
    for i in range(N):
        for a in AV:
            for (x, y) in ((a, i), (i, a)):
                r = math.hypot(x - C, y - C)
                if r > R_EDGE2:
                    g[y][x] = "="
                elif R_EDGE1 < r <= R_MOAT or (g[y][x] == "-"):
                    g[y][x] = "b"
                elif R_IN < r <= R_WALL:
                    g[y][x] = "G"
                elif g[y][x] != "*":
                    g[y][x] = "="
    # a ring street just inside the wall
    for y in range(N):
        for x in range(N):
            r = math.hypot(x - C, y - C)
            if 23.5 < r <= R_IN and g[y][x] == ":":
                g[y][x] = "="
    # plaza dressing (off the avenue lines)
    for (x, y, ch) in [(31, 31, "w"), (40, 31, "w"), (31, 40, "w"), (40, 40, "w")]:
        g[y][x] = ch
    for (x, y) in [(28, 29), (43, 29), (28, 42), (43, 42), (16, 27), (55, 44), (27, 16), (44, 55)]:
        g[y][x] = "t"
    g[32][32] = "E"
    for (x, y, ch) in [(26, 31, "c"), (26, 32, "r"), (45, 31, "s"), (45, 32, "c"), (26, 39, "r"), (45, 39, "s")]:
        g[y][x] = ch
    return ["".join(r) for r in g]


def bottom_door(id_, kind, x, y, extra):
    b = {"id": id_, "kind": kind, "style": "capital", "rect": [x, y, 9, 7], "door": [[x + 4, y + 6]],
         "counter": [[x + i, y + 2] for i in range(2, 7)], "keeper_at": [x + 4, y + 1], "stand": [x + 4, y + 3],
         "sign": [x + 5, y + 6], "roof": "#b8a888"}
    b.update(extra)
    return b


def top_door(id_, kind, x, y, extra):
    b = {"id": id_, "kind": kind, "style": "capital", "rect": [x, y, 9, 7], "door": [[x + 4, y]],
         "counter": [[x + i, y + 4] for i in range(2, 7)], "keeper_at": [x + 4, y + 5], "stand": [x + 4, y + 3],
         "sign": [x + 5, y], "roof": "#b8a888"}
    b.update(extra)
    return b


def buildings():
    out = []
    bank = {"id": "highfen_bank", "kind": "bank", "shop": "", "name": "Highfen Treasury", "keeper": "Aldous Crane",
            "keeper_sprite": "keeper_general", "sign_sprite": "sign_bank", "style": "capital", "roof": "#8a8f9a",
            "rect": [18, 20, 9, 7], "door": [[22, 26]], "counter": [[19, 22], [20, 22]], "keeper_at": [19, 21], "stand": [21, 23],
            "sign": [23, 26], "props": [{"object": "bank_chest", "at": [24, 21]}, {"object": "bank_chest", "at": [25, 21]}, {"object": "barrel", "at": [25, 24]}]}
    out.append(bank)
    out.append(top_door("highfen_cook", "cookhouse", 18, 38, {"shop": "cook", "name": "The Gilded Spoon", "keeper": "Maud Fairweather",
        "props": [{"object": "shelf_goods", "at": [19, 43]}, {"object": "shelf_goods", "at": [25, 43]}, {"object": "oven", "at": [19, 40]}, {"object": "oven", "at": [25, 40]}]}))
    ps = bottom_door("highfen_player", "player", 45, 20, {"shop": "player", "name": "For sale",
        "displays": [[46, 24], [47, 24], [51, 24], [52, 24], [46, 25], [47, 25], [51, 25], [52, 25]],
        "props": [{"object": "crate", "at": [46, 21]}, {"object": "crate", "at": [52, 21]}],
        "note": "0.3.8 the realm's ONLY player shop (Grok: player_shop unique to Highfen)"})
    ps["counter"] = [[x, 22] for x in range(47, 52)]
    out.append(ps)
    out.append(top_door("highfen_general", "shop", 45, 38, {"shop": "general", "name": "Highfen Emporium", "keeper": "Perrin Vale",
        "props": [{"object": "shelf_goods", "at": [46, 43]}, {"object": "shelf_goods", "at": [52, 43]}, {"object": "barrel", "at": [46, 41]}, {"object": "sacks", "at": [52, 41]}]}))
    # the player house: walk-in, every station + a bank chest, bought from the estate clerk
    hx, hy = 22, 48
    out.append({"id": "highfen_house", "kind": "player_house", "shop": "", "style": "house", "name": "Townhouse (for sale)",
        "keeper": "Estate clerk", "keeper_sprite": "keeper_general", "sign_sprite": "sign_house", "roof": "#8a5a3a",
        "rect": [hx, hy, 9, 8], "door": [[hx + 4, hy]], "counter": [], "keeper_at": [hx + 7, hy + 1], "stand": [hx + 6, hy + 1],
        "sign": [hx + 5, hy],
        "props": [{"object": "hearth", "at": [hx + 1, hy + 6]}, {"object": "furnace", "at": [hx + 2, hy + 6]},
                  {"object": "anvil", "at": [hx + 3, hy + 6]}, {"object": "workbench", "at": [hx + 5, hy + 6]},
                  {"object": "quern", "at": [hx + 6, hy + 6]}, {"object": "bank_chest", "at": [hx + 7, hy + 6]},
                  {"object": "oven", "at": [hx + 1, hy + 3]}],
        "note": "0.3.8 player house: buy it from the estate clerk (data/player_house.json); stations + bank chest work for the owner only"})
    return out


def main():
    rows = build()
    gates = {"north": [[a, 0] for a in AV], "south": [[a, N - 1] for a in AV], "west": [[0, a] for a in AV], "east": [[N - 1, a] for a in AV]}
    gy = [y for y in range(N) if rows[y][35] == "G"]
    gx = [x for x in range(N) if rows[35][x] == "G"]
    gate_walls = {"north": [[a, gy[0]] for a in AV], "south": [[a, gy[-1]] for a in AV],
                  "west": [[gx[0], a] for a in AV], "east": [[gx[-1], a] for a in AV]}
    for d, cells in gate_walls.items():
        (x0, y0), (x1, y1) = cells[0], cells[-1]
        side = [(x0 - 1, y0), (x1 + 1, y1)] if d in ("north", "south") else [(x0, y0 - 1), (x1, y1 + 1)]
        assert all(rows[y][x] in "#^" for x, y in side), (d, side)
    town = {
        "id": "highfen", "name": "Highfen", "kind": "capital",
        "origin": [CENTER[0] - N // 2, CENTER[1] - N // 2], "spawn": [CENTER[0] - 12, CENTER[1] + 9],
        "rows": rows,
        "tiles": {".": "grass", ":": "cobble", "*": "cobble_dark", "=": "road_stone", "#": "capital_wall", "^": "capital_front",
                  "G": "gate_capital", "-": "moat_edge", "~": "moat", "b": "bridge"},
        "objects": {"w": {"object": "well", "ground": "cobble_dark"}, "t": {"object": "ash_tree", "ground": "grass"},
                    "c": {"object": "crate", "ground": "cobble"}, "r": {"object": "barrel", "ground": "cobble"},
                    "s": {"object": "sacks", "ground": "cobble"},
                    "E": {"object": "exchange_board", "ground": "cobble_dark"}},
        "roof": "#b8a888", "building_style": "capital",
        "buildings": buildings(),
        "specialists": ["cook"],
        "price_bias": {"iron_ore": 1.1, "coal": 1.1, "raw_carp": 1.05, "wheat": 1.05},
        "tagline": "The moated capital at the heart of the realm: pale stone, wide avenues, a house for sale and the only player shop.",
        "theme": "highfen",
        "gates": gates,
        "gate_walls": gate_walls,
        "note": "0.3.8 generated by tools/world/place_highfen.py from Grok's highfen_capital.json (adapted: real tile names, circle + moat, gates on the bridges' outer ends)",
    }
    # trees on grass inside the circle only
    json.dump(town, open(os.path.join(ROOT, "data", "towns", "highfen.json"), "w"), indent=1)
    print("\n".join(rows))

main()
