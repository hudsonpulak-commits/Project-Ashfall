#!/usr/bin/env python3
"""0.3.1: rebuild the three main cities with UNIQUE layouts AND materials.

Fenhollow  – irregular marsh town: winding boardwalks over marsh/water,
             scattered buildings, small boardwalk square, thatch roofs, palisade.
Cinderholt – dense forge city: cobbled grid, tight building blocks, slate roofs,
             forge district with ember props, corner towers, rectangular walls.
Saltmere   – harbour town: buildings along a quay, piers into water, sandstone/
             plaster facades, blue roofs, market street on the waterfront.

Writes data/towns/{fenhollow,cinderholt,saltmere}.json and updates
data/churches.json + data/town_npcs.json gate guards.

    python3 tools/layout_walled_cities.py
"""
import json, os, collections, copy
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "towns")
SRC = os.path.join(ROOT, "tools", "town_sources")
W, H = 46, 38
CX, CY = 23, 19  # must stay spawn-local (origin + this == world spawn)
SHOPS = json.load(open(os.path.join(ROOT, "data", "buildings.json")))["shops"]
SMITHY = json.load(open(os.path.join(ROOT, "data", "buildings.json")))["smithy"]

THEMES = {
    "fenhollow": {
        "wall": "palisade", "front": "palisade_front", "gate": "gate_wood",
        "street": "boardwalk", "plaza": "boardwalk", "yard": "grass",
        "roof": "#c4a05a", "cook_roof": "#b8904a",
        "building_style": "timber",
        "tagline": "Marsh timber town on winding boardwalks behind a wooden palisade.",
        "general_name": "Fenhollow Provisions", "general_keeper": "Marla Thatch",
        "cook_name": "Reed Oven", "cook_keeper": "Bryn Potts",
        "specialists": ["helmets", "swords", "archery"],
        "church_keeper": "Father Aldric", "church_name": "Fenhollow Church",
    },
    "cinderholt": {
        "wall": "basalt_wall", "front": "basalt_front", "gate": "gate_basalt",
        "street": "cobble_dark", "plaza": "cobble_dark", "yard": "dirt",
        "roof": "#3a3e4c", "cook_roof": "#2e3240",
        "building_style": "basalt",
        "tagline": "Basalt forge city of coal smoke, tight blocks and slate roofs.",
        "general_name": "Cinderholt Supply", "general_keeper": "Osric Coalby",
        "cook_name": "Ember Kitchen", "cook_keeper": "Greta Ashpan",
        "specialists": ["body", "shields", "axes"],
        "church_keeper": "Brother Varr", "church_name": "Cinderholt Chapel",
    },
    "saltmere": {
        "wall": "sandstone_wall", "front": "sandstone_front", "gate": "gate_sand",
        "street": "planks", "plaza": "plaster", "yard": "sand",
        "roof": "#2a6a9a", "cook_roof": "#1e5a8a",
        "building_style": "plaster",
        "tagline": "Sandstone harbour town of docks, white plaster and blue roofs.",
        "general_name": "Saltmere Chandlery", "general_keeper": "Nell Brine",
        "cook_name": "Harbour Cookhouse", "cook_keeper": "Pip Saltkettle",
        "specialists": ["legs", "maces"],
        "church_keeper": "Sister Mare", "church_name": "Saltmere Chapel",
    },
}

# Distinct slot layouts (town-local). Door faces S or N only.
# Fenhollow: scattered along winding boardwalks, small square near spawn.
SLOTS_FEN = {
    "general": (4, 5, "S", 9, 7),       # NW, off north boardwalk spur
    "spec_a":  (30, 4, "S", 9, 7),      # NE organic
    "spec_b":  (16, 8, "S", 9, 7),      # north of small square (archery)
    "player":  (3, 14, "S", 9, 7),      # west spur
    "cook":    (10, 26, "S", 9, 7),     # south cluster (clear of player+3)
    "smithy":  (26, 26, "N", 9, 9),     # SE, faces north toward square
    "church":  (34, 16, "S", 9, 8),     # east reed church
}
# Cinderholt: tight grid blocks. North terrace of shops; south forge row.
SLOTS_CIN = {
    "general": (4, 3, "S", 9, 7),
    "spec_a":  (14, 3, "S", 9, 7),      # body
    "spec_b":  (24, 3, "S", 9, 7),      # shields
    "player":  (34, 3, "S", 9, 7),      # NE corner of terrace
    "cook":    (4, 26, "N", 9, 7),      # forge district, faces street
    "smithy":  (14, 25, "N", 9, 9),     # forge heart
    "church":  (34, 14, "S", 9, 8),     # east chapel
}
# Saltmere: terraces facing the south quay / market street; water SE.
SLOTS_SAL = {
    "general": (4, 12, "S", 9, 7),      # waterfront terrace
    "spec_a":  (14, 12, "S", 9, 7),     # legs
    "cook":    (24, 12, "S", 9, 7),
    "player":  (4, 2, "S", 9, 7),       # inland north
    "smithy":  (14, 2, "S", 9, 7),      # maces inland (still smithy)
    "church":  (24, 2, "S", 9, 8),
    # no spec_b — saltmere has only legs + maces
}

def fy(y, side, h=7):
    return y if side == "S" else (h - 1 - y)

def shop_building(town, shop, rect_x, rect_y, side, w=9, h=7, style="timber", roof=None):
    sd = SHOPS.get(shop, {})
    P = lambda x, y: [rect_x + x, rect_y + fy(y, side, h)]
    props = sd.get("props", {"back": "shelf_goods", "corner": "barrel", "rack": "crate", "rack2": "sacks"})
    b = collections.OrderedDict()
    b["id"] = f"{town}_{shop}"
    b["kind"] = "shop"
    b["shop"] = shop
    b["style"] = style
    b["rect"] = [rect_x, rect_y, w, h]
    b["door"] = [P(4, h - 1)]
    b["counter"] = [P(x, 2) for x in range(2, 7)]
    b["keeper_at"] = P(4, 1)
    b["stand"] = P(4, 3)
    b["sign"] = P(5, h - 1)
    if roof:
        b["roof"] = roof
    if props:
        b["props"] = [
            {"object": props.get("back", "shelf_goods"), "at": P(1, 1)},
            {"object": props.get("back", "shelf_goods"), "at": P(7, 1)},
            {"object": props.get("corner", "barrel"), "at": P(1, 2)},
            {"object": props.get("corner", "barrel"), "at": P(7, 2)},
            {"object": props.get("rack", "crate"), "at": P(1, 4)},
            {"object": props.get("rack2", "sacks"), "at": P(7, 4)},
        ]
    return b

def cook_building(town, theme, rect_x, rect_y, side):
    b = shop_building(town, "cook", rect_x, rect_y, side,
                      style=theme["building_style"], roof=theme["cook_roof"])
    b["kind"] = "cookhouse"
    b["name"] = theme["cook_name"]
    b["keeper"] = theme["cook_keeper"]
    P = lambda x, y: [rect_x + x, rect_y + fy(y, side, 7)]
    # ovens on the customer side of the aisle (reachable)
    b["props"] = [
        {"object": "shelf_goods", "at": P(1, 1)},
        {"object": "shelf_goods", "at": P(7, 1)},
        {"object": "barrel", "at": P(1, 2)},
        {"object": "barrel", "at": P(7, 2)},
        {"object": "oven", "at": P(1, 5)},
        {"object": "oven", "at": P(7, 5)},
    ]
    return b

def smithy_building(town, shop, rect_x, rect_y, side, style="timber", roof=None):
    h = 9
    P = lambda x, y: [rect_x + x, rect_y + fy(y, side, h)]
    b = collections.OrderedDict()
    b["id"] = f"{town}_{shop}"
    b["kind"] = "smithy"
    b["shop"] = shop
    b["style"] = style
    b["rect"] = [rect_x, rect_y, 9, h]
    b["door"] = [P(4, 0)]  # facade on north when side N → fy(0)=h-1 south? Wait.
    # side N means door on north edge: local y=0 of rect.
    # fy(y, "N", h) = h-1-y, so P(4,0) for door wants world y = rect_y + (h-1) when side N? 
    # Looking at original: door [P(4, 0)] with side N → fy(0,N,9)=8 → south edge. WRONG for "faces north".
    # Original smithy used side N with door P(4,0) → fy(0)=8 which is SOUTH of rect.
    # And stand P(2,5), furnace etc. The comment said smithy faces north meaning door on north.
    # Check original smithy_building...
    return b  # placeholder replaced below

# Re-read original smithy - door P(4,0) with side N gives y = rect_y + 8 = south facade.
# So "N" in slots meant the building is on the south side of a street, door facing north... 
# fy(0,"N")=h-1 = south. That's door on south. Naming is confusing.
# For "faces north toward square" we need door on north edge: local y=0 without flip.
# Simplest: use side "S" for door on south (fy(h-1)=h-1), side "N" for door on north:
#   For door on north: use side S with... no.
#   fy(y,"S")=y, door at y=h-1 = south.
#   fy(y,"N")=h-1-y, door at y=0 → world y = rect_y+(h-1) = south. Both give south?!
#   door P(4, h-1) with S → south. door P(4, 0) with N → fy(0)=h-1 → south.
# So BOTH put door on south! The "N" flip mirrors interior so counter is near south door.
# For building on south of street facing north onto street, we need door on NORTH edge.
# That would be door at local y=0 with NO flip: world y = rect_y.
# Looking at world_gen: facade = rect.end.y - 1 if door.y == rect.end.y - 1 else rect.position.y
# So door on north (rect.position.y) works — facade_y = north.
# shop_building always does door P(4, h-1) which with S is south, with N (fy) is also south.
# To get north door: pass side "S" but use a north_door flag, OR use side that maps door to y=0.
# Fix: if side == "N", door at local y=0 without using fy for door... 
# Actually with fy: we want world_y = rect_y for north door.
# P(4, y_local) = rect_y + fy(y_local). For N: rect_y + h-1 - y_local = rect_y ⇒ y_local = h-1.
# So door P(4, h-1) with side N → north! 
# fy(h-1, "N", h) = h-1-(h-1)=0 → world y = rect_y. YES north!
# And shop_building uses door P(4, h-1) for both — with N that's north. Good.
# Original smithy used door P(4, 0) with N → fy(0)=h-1 → SOUTH. So original smithy faced south.
# SLOTS said smithy (12, 26, "N") — building at y=26, door south at y=34, street at y=19 above it.
# So door faces south away from plaza? That's wrong for "face plaza".
# For CIN smithy at (14,25,"N") with door P(4,h-1) → north door at y=25. Faces street at y=19-24. Good.
# I'll use standard shop_building door P(4,h-1) for smithy too.

def smithy_building(town, shop, rect_x, rect_y, side, style="timber", roof=None):
    h = 9
    P = lambda x, y: [rect_x + x, rect_y + fy(y, side, h)]
    b = collections.OrderedDict()
    b["id"] = f"{town}_{shop}"
    b["kind"] = "smithy"
    b["shop"] = shop
    b["style"] = style
    if roof:
        b["roof"] = roof
    b["rect"] = [rect_x, rect_y, 9, h]
    b["door"] = [P(4, h - 1)]
    b["counter"] = [P(x, 2) for x in range(2, 7)]
    b["keeper_at"] = P(4, 1)
    b["stand"] = P(4, 3)
    b["sign"] = P(5, h - 1)
    b["name"] = SMITHY.get("name", "Blacksmith")
    b["keeper"] = SMITHY.get("keeper", "Smith")
    # furnace + anvil inside (from buildings.json smithy props pattern)
    b["props"] = [
        {"object": "furnace", "at": P(2, 4)},
        {"object": "anvil", "at": P(5, 4)},
        {"object": "bellows", "at": P(1, 5)},
        {"object": "quench_barrel", "at": P(7, 5)},
        {"object": "coal_crate", "at": P(1, 1)},
        {"object": "weapon_rack", "at": P(7, 1)},
    ]
    return b

def player_building(town, rect_x, rect_y, side, style="timber", roof=None):
    b = shop_building(town, "player", rect_x, rect_y, side, style=style, roof=roof)
    b["kind"] = "player"
    b["name"] = "For sale"
    P = lambda x, y: [rect_x + x, rect_y + fy(y, side, 7)]
    # Side displays only — leave x=3,4,5 clear for counter reachability.
    b["displays"] = [P(x, y) for y in (4, 5) for x in (1, 2, 6, 7)]
    b["props"] = [{"object": "crate", "at": P(1, 1)}, {"object": "crate", "at": P(7, 1)}]
    return b

def church_def(town, theme, rect_x, rect_y, side="S"):
    P = lambda x, y: [rect_x + x, rect_y + fy(y, side, 8)]
    return collections.OrderedDict([
        ("id", f"{town}_church"),
        ("kind", "church"),
        ("name", theme["church_name"]),
        ("keeper", theme["church_keeper"]),
        ("style", "stone"),
        ("rect", [rect_x, rect_y, 9, 8]),
        ("door", [P(4, 7)]),
        ("keeper_at", P(7, 1)),
        ("stand", P(7, 2)),
        ("sign", P(5, 7)),
        ("altar", P(4, 1)),
        ("props", [
            {"object": "candle_stand", "at": P(1, 1)},
            {"object": "candle_stand", "at": P(3, 1)},
            {"object": "candle_stand", "at": P(5, 1)},
            {"object": "pew", "at": P(1, 4)}, {"object": "pew", "at": P(2, 4)},
            {"object": "pew", "at": P(3, 4)}, {"object": "pew", "at": P(5, 4)},
            {"object": "pew", "at": P(6, 4)}, {"object": "pew", "at": P(7, 4)},
            {"object": "pew", "at": P(1, 6)}, {"object": "pew", "at": P(2, 6)},
            {"object": "pew", "at": P(3, 6)}, {"object": "pew", "at": P(5, 6)},
            {"object": "pew", "at": P(6, 6)}, {"object": "pew", "at": P(7, 6)},
        ]),
    ])

def fill_rect(grid, x, y, w, h, ch):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if 0 <= xx < W and 0 <= yy < H:
                grid[yy][xx] = ch

def setc(grid, x, y, ch):
    if 0 <= x < W and 0 <= y < H:
        grid[y][x] = ch

def stroke_path(grid, points, ch):
    """Stroke 4-connected path through points (inclusive)."""
    for i in range(len(points) - 1):
        x0, y0 = points[i]
        x1, y1 = points[i + 1]
        x, y = x0, y0
        setc(grid, x, y, ch)
        while (x, y) != (x1, y1):
            if x < x1: x += 1
            elif x > x1: x -= 1
            elif y < y1: y += 1
            elif y > y1: y -= 1
            setc(grid, x, y, ch)

def paint_perimeter_walls(grid, wall_ch='@', front_ch='['):
    for x in range(W):
        if grid[0][x] != 'G':
            grid[0][x] = wall_ch
        if grid[H - 1][x] != 'G':
            grid[H - 1][x] = front_ch
    for y in range(H):
        if grid[y][0] != 'G':
            grid[y][0] = wall_ch
        if grid[y][W - 1] != 'G':
            grid[y][W - 1] = wall_ch

def place_gates(grid):
    for cells in (
        [(CX - 1, 0), (CX, 0), (CX + 1, 0)],
        [(CX - 1, H - 1), (CX, H - 1), (CX + 1, H - 1)],
        [(0, CY - 1), (0, CY), (0, CY + 1)],
        [(W - 1, CY - 1), (W - 1, CY), (W - 1, CY + 1)],
    ):
        for x, y in cells:
            grid[y][x] = 'G'

def gate_approach_streets(grid, ch):
    for d in range(1, 4):
        setc(grid, CX, d, ch)
        setc(grid, CX, H - 1 - d, ch)
        setc(grid, d, CY, ch)
        setc(grid, W - 1 - d, CY, ch)

# --------------------------------------------------------------------------- fenhollow
def layout_fenhollow(grid):
    """Organic marsh: winding boardwalks, scattered buildings, small square."""
    fill_rect(grid, 1, 1, W - 2, H - 2, '.')
    # marsh + water patches
    for y, xs in ((3, range(2, 8)), (4, range(1, 9)), (5, range(1, 9)), (6, range(2, 8)), (7, range(3, 7))):
        for x in xs:
            setc(grid, x, y, '~')  # NW pond (tap-on-water)
    for y, x0, x1 in ((10, 2, 6), (11, 2, 7), (12, 3, 7), (22, 36, 42), (23, 35, 43),
                      (24, 36, 42), (30, 2, 8), (31, 3, 9), (32, 2, 8)):
        for x in range(x0, x1):
            if grid[y][x] not in '~':
                setc(grid, x, y, 'm')
    # reed beds
    for y, x in ((11, 3), (12, 5), (23, 38), (31, 5), (32, 4)):
        setc(grid, x, y, 'r')
    # winding boardwalk spine (not a cross): meander from N gate to S gate via square
    spine = [
        (CX, 1), (CX, 4), (20, 4), (20, 8), (18, 8), (18, 12),
        (CX, 12), (CX, 16), (CX, 19), (CX, 22), (26, 22), (26, 28),
        (CX, 28), (CX, H - 2),
    ]
    stroke_path(grid, spine, '_')
    # west spur to player / general
    stroke_path(grid, [(18, 12), (8, 12), (8, 16), (6, 16), (6, 20)], '_')
    stroke_path(grid, [(8, 8), (8, 12)], '_')
    stroke_path(grid, [(6, 8), (6, 5), (8, 5)], '_')  # up to general
    # east spur to church / NE shops
    stroke_path(grid, [(CX, 16), (34, 16), (34, 20)], '_')
    stroke_path(grid, [(30, 8), (30, 4), (34, 4)], '_')
    stroke_path(grid, [(20, 8), (30, 8)], '_')
    # south cluster link
    stroke_path(grid, [(10, 28), (26, 28), (26, 32)], '_')
    # small boardwalk square around spawn (NOT grey cobble)
    fill_rect(grid, 18, 15, 11, 9, '_')
    # keep spawn cell boardwalk
    setc(grid, CX, CY, '_')
    # irregular palisade buttresses (inner jogs — outer edge still walled later)
    for x, y in ((2, 8), (2, 9), (3, 9), (2, 28), (2, 29), (3, 28),
                 (W - 3, 8), (W - 3, 9), (W - 4, 9), (W - 3, 28), (W - 3, 29)):
        setc(grid, x, y, '@')
    # trees / reeds
    for y, x in ((8, 12), (9, 14), (14, 4), (28, 8), (33, 10), (6, 40), (8, 42), (34, 34)):
        if grid[y][x] in ('.', 'm'):
            setc(grid, x, y, 'a')
    for y, x in ((14, 36), (29, 34)):
        if grid[y][x] == '.':
            setc(grid, x, y, 'l')
    gate_approach_streets(grid, '_')

# --------------------------------------------------------------------------- cinderholt
def layout_cinderholt(grid):
    """Dense forge city: cobbled grid, tight blocks, corner towers, forge district."""
    fill_rect(grid, 1, 1, W - 2, H - 2, ':')
    # grid streets every 10 tiles
    for x in (3, 13, 23, 33, CX):
        for y in range(1, H - 1):
            setc(grid, x, y, '=')
    for y in (2, 11, 19, 28):
        for x in range(1, W - 1):
            setc(grid, x, y, '=')
    # small fortified plaza at centre
    fill_rect(grid, 18, 16, 11, 7, '#')
    setc(grid, CX, CY, '#')
    # forge district ash/ember ground SE + south
    for y in range(24, H - 1):
        for x in range(4, 34):
            if grid[y][x] == ':':
                setc(grid, x, y, ':')
    # ember props (use object chars on dirt)
    for y, x in ((28, 8), (29, 9), (30, 7), (28, 20), (29, 22), (31, 18), (30, 24),
                 (27, 12), (32, 16), (29, 28)):
        setc(grid, x, y, 'e')  # embers only (never 'c' = copper_rock)
    # corner towers (3x3)
    for ox, oy in ((0, 0), (W - 3, 0), (0, H - 3), (W - 3, H - 3)):
        fill_rect(grid, ox, oy, 3, 3, '@')
    gate_approach_streets(grid, '=')

# --------------------------------------------------------------------------- saltmere
def layout_saltmere(grid):
    """Harbour: sandy yards, curved SE shoreline, quay + piers, market street."""
    fill_rect(grid, 1, 1, W - 2, H - 2, ',')
    # curved shoreline: water SE
    for y in range(H):
        # shore x grows as y increases (curve)
        shore = 34 - max(0, (y - 10) // 3)
        if y > 28:
            shore = min(shore, 20 + (H - y))
        for x in range(max(shore, 18), W):
            setc(grid, x, y, '~')
    # also south water band
    for y in range(32, H):
        for x in range(1, W):
            if x > 12 + (y - 32) * 2:
                setc(grid, x, y, '~')
    # quay / waterfront market street (planks) just inland of water, roughly N-S then E-W
    for y in range(4, 30):
        setc(grid, 30, y, '#')
        setc(grid, 29, y, '#')
        setc(grid, 28, y, '=')  # market street
    # E-W market along south quay
    for x in range(4, 31):
        setc(grid, x, 28, '#')
        setc(grid, x, 27, '=')
    # piers into water
    for pier_y in (8, 16, 24):
        for x in range(30, min(44, W - 1)):
            if grid[pier_y][x] == '~' or x >= 30:
                setc(grid, x, pier_y, '#')
            setc(grid, x, pier_y + 1, '#')
    # inland sandy lanes to gates / spawn
    stroke_path(grid, [(CX, 1), (CX, 10), (CX, CY), (CX, 27)], ',')
    for x in range(1, 30):
        setc(grid, x, CY, ',')
        if x % 3 != 1:
            setc(grid, x, CY, '=')  # packed sand/plank hybrid path west
    # plaster civic yard around spawn (between terrace and quay street)
    fill_rect(grid, 16, 18, 11, 6, 'P')
    setc(grid, CX, CY, 'P')
    # civic props placed later (after buildings) so footprints don't erase them
    # fishing spots
    for y, x in ((6, 40), (14, 42), (22, 40), (30, 36), (34, 24)):
        if 0 <= x < W and 0 <= y < H:
            setc(grid, x, y, 'f')
    # a few coastal trees inland
    for y, x in ((5, 6), (8, 10), (20, 5), (24, 8)):
        if grid[y][x] == ',':
            setc(grid, x, y, 'l')
    # inland lane under north terrace so church/player/smithy stay connected
    for x in range(4, 32):
        setc(grid, x, 10, '=')
        setc(grid, x, 11, ',')
    gate_approach_streets(grid, '=')
    # east gate pier approach must stay planks
    for y in range(CY - 2, CY + 3):
        for x in range(28, W):
            if grid[y][x] in ('~', ',', '.'):
                setc(grid, x, y, '#')

def apply_buildings(grid, town, theme, slots):
    buildings = []
    style = theme["building_style"]
    roof = theme["roof"]
    specs = theme["specialists"][:]
    smith_shop = [s for s in specs if s in ("swords", "axes", "maces")][0]
    other = [s for s in specs if s != smith_shop]

    def clear_and(slot_key, maker):
        x, y, side, w, h = slots[slot_key]
        fill_rect(grid, x, y, w, h, '.')  # cleared under footprint
        buildings.append(maker(x, y, side, w, h))

    clear_and("general", lambda x, y, side, w, h: (
        lambda b: (b.update({"name": theme["general_name"], "keeper": theme["general_keeper"]}), b)[1])(
        shop_building(town, "general", x, y, side, w, h, style, roof)))
    clear_and("spec_a", lambda x, y, side, w, h: shop_building(
        town, other[0], x, y, side, w, h, style, roof))
    if "spec_b" in slots and len(other) > 1:
        clear_and("spec_b", lambda x, y, side, w, h: shop_building(
            town, other[1], x, y, side, w, h, style, roof))
    clear_and("player", lambda x, y, side, w, h: player_building(town, x, y, side, style, roof))
    clear_and("cook", lambda x, y, side, w, h: cook_building(theme=theme, town=town, rect_x=x, rect_y=y, side=side))
    clear_and("smithy", lambda x, y, side, w, h: smithy_building(town, smith_shop, x, y, side, style, roof))
    cx, cy, cside, cw, ch = slots["church"]
    fill_rect(grid, cx, cy, cw, ch, '.')
    church = church_def(town, theme, cx, cy, cside)
    return buildings, church


def place_civic_props(grid, town):
    """Bank/exchange/hearth/dummy/workbench on open plaza tiles (after building clears)."""
    if town == "fenhollow":
        spots = [(20, 16, 'B'), (22, 16, 'E'), (24, 16, 'H'), (20, 22, 'W'), (26, 22, 'D')]
    elif town == "cinderholt":
        spots = [(20, 17, 'B'), (22, 17, 'E'), (24, 17, 'H'), (20, 21, 'W'), (26, 21, 'D')]
    else:
        spots = [(16, 21, 'B'), (20, 21, 'E'), (24, 21, 'H'), (16, 23, 'W'), (22, 23, 'D')]
    for x, y, ch in spots:
        # never drop props on walls/water/buildings footprint markers we care about
        if grid[y][x] not in '@[G%~':
            setc(grid, x, y, ch)

def build_city(town):
    theme = THEMES[town]
    src = json.load(open(os.path.join(SRC, f"{town}.json")))
    grid = [['.' for _ in range(W)] for _ in range(H)]
    slots = {"fenhollow": SLOTS_FEN, "cinderholt": SLOTS_CIN, "saltmere": SLOTS_SAL}[town]
    if town == "fenhollow":
        layout_fenhollow(grid)
    elif town == "cinderholt":
        layout_cinderholt(grid)
    else:
        layout_saltmere(grid)

    buildings, church = apply_buildings(grid, town, theme, slots)
    place_civic_props(grid, town)

    # perimeter walls + gates last
    paint_perimeter_walls(grid)
    place_gates(grid)
    # cinderholt towers re-assert after perimeter
    if town == "cinderholt":
        for ox, oy in ((0, 0), (W - 3, 0), (0, H - 3), (W - 3, H - 3)):
            for dy in range(3):
                for dx in range(3):
                    if grid[oy + dy][ox + dx] != 'G':
                        grid[oy + dy][ox + dx] = '@'
        place_gates(grid)

    tiles = {
        '.': "grass", ':': "dirt", ',': "sand", '~': "water", 'm': "marsh",
        '=': theme["street"], '#': theme["plaza"] if town != "saltmere" else "planks",
        '_': "boardwalk", 'P': "plaster",
        '%': "wall", '^': "wall_front", ';': "floor", '+': "doorway",
        '@': theme["wall"], '[': theme["front"], 'G': theme["gate"],
    }
    if town == "fenhollow":
        tiles['.'] = "grass"
        tiles['#'] = "boardwalk"
        tiles['='] = "boardwalk"
    elif town == "cinderholt":
        tiles['.'] = "dirt"
        tiles['#'] = "cobble_dark"
    elif town == "saltmere":
        tiles['.'] = "sand"
        tiles['#'] = "planks"
        tiles['='] = "planks"

    objects = copy.deepcopy(src["objects"])
    # civic props ground
    plaza_g = tiles.get('P', theme["plaza"]) if town == "saltmere" else theme["plaza"]
    if town == "fenhollow":
        plaza_g = "boardwalk"
    if town == "cinderholt":
        plaza_g = "cobble_dark"
    if town == "saltmere":
        plaza_g = "plaster"
    for k in ("B", "E", "H", "D", "W"):
        if k in objects:
            objects[k] = dict(objects[k])
            objects[k]["ground"] = plaza_g
    # fenhollow trees on grass; saltmere on sand; cinderholt embers
    objects['e'] = {"object": "embers", "ground": "dirt"}
    objects['r'] = {"object": "reed_bed", "ground": "marsh"}
    if town == "saltmere":
        for k in ('a', 'l', 'b'):
            if k in objects:
                objects[k] = dict(objects[k])
                objects[k]["ground"] = "sand"
    if town == "cinderholt":
        for k in ('a', 'l', 'b', 'c'):
            if k in objects:
                objects[k] = dict(objects[k])
                objects[k]["ground"] = "dirt"

    rows = [''.join(r) for r in grid]
    out = collections.OrderedDict()
    out["id"] = town
    out["name"] = src["name"]
    out["origin"] = src["origin"]
    out["spawn"] = src["spawn"]
    out["rows"] = rows
    out["tiles"] = tiles
    out["objects"] = objects
    out["roof"] = theme["roof"]
    out["building_style"] = theme["building_style"]
    out["buildings"] = buildings
    out["specialists"] = theme["specialists"] + ["cook"]
    out["price_bias"] = src.get("price_bias", {})
    out["tagline"] = theme["tagline"]
    out["theme"] = town
    out["gates"] = {
        "north": [[CX - 1, 0], [CX, 0], [CX + 1, 0]],
        "south": [[CX - 1, H - 1], [CX, H - 1], [CX + 1, H - 1]],
        "west": [[0, CY - 1], [0, CY], [0, CY + 1]],
        "east": [[W - 1, CY - 1], [W - 1, CY], [W - 1, CY + 1]],
    }
    return out, church

def gate_guards(town, gates, rows):
    block = set("@[%~")
    guards = []
    # town-specific patrol loops on walkable streets
    if town == "fenhollow":
        guards.append({"enemy": "town_guard", "patrol": [[20, 12], [8, 12], [8, 20], [20, 22]]})
        guards.append({"enemy": "town_guard", "patrol": [[26, 16], [34, 16], [26, 28]]})
        citizens_area = [18, 15, 11, 9]
    elif town == "cinderholt":
        guards.append({"enemy": "town_guard", "patrol": [[13, 11], [23, 11], [23, 19], [13, 19]]})
        guards.append({"enemy": "town_guard", "patrol": [[3, 19], [33, 19]]})
        citizens_area = [18, 16, 11, 7]
    else:
        guards.append({"enemy": "town_guard", "patrol": [[28, 10], [28, 20], [14, 27], [8, 19]]})
        guards.append({"enemy": "town_guard", "patrol": [[20, 17], [10, 17]]})
        citizens_area = [16, 16, 10, 7]

    def walkable(x, y):
        if not (0 <= y < len(rows) and 0 <= x < len(rows[0])):
            return False
        return rows[y][x] not in block

    for name, cells in gates.items():
        gx, gy = cells[1]
        if name == "north":
            candidates = [[gx - 1, gy + 1], [gx + 1, gy + 1], [gx, gy + 1], [gx - 1, gy + 2], [gx + 1, gy + 2]]
        elif name == "south":
            candidates = [[gx - 1, gy - 1], [gx + 1, gy - 1], [gx, gy - 1], [gx - 1, gy - 2], [gx + 1, gy - 2]]
        elif name == "west":
            candidates = [[gx + 1, gy - 1], [gx + 1, gy + 1], [gx + 1, gy], [gx + 2, gy - 1], [gx + 2, gy + 1]]
        else:
            candidates = [[gx - 1, gy - 1], [gx - 1, gy + 1], [gx - 1, gy], [gx - 2, gy - 1], [gx - 2, gy + 1]]
        spots = [c for c in candidates if walkable(c[0], c[1])][:2]
        while len(spots) < 2:
            spots.append([CX, CY])
        for s in spots[:2]:
            guards.append({"enemy": "town_guard", "patrol": [s], "gate": name})
    return guards, citizens_area

def main():
    churches = json.load(open(os.path.join(ROOT, "data", "churches.json")))
    npcs = json.load(open(os.path.join(ROOT, "data", "town_npcs.json")))
    for town in ("fenhollow", "cinderholt", "saltmere"):
        data, church = build_city(town)
        path = os.path.join(OUT, f"{town}.json")
        with open(path, "w") as f:
            json.dump(data, f, indent=1)
            f.write("\n")
        print("wrote", path, "buildings", len(data["buildings"]), "style", data["building_style"])
        churches["towns"][town] = church
        guards, area = gate_guards(town, data["gates"], data["rows"])
        npcs["towns"][town] = {
            "guards": guards,
            "citizens": {"enemy": "citizen", "count": 5, "area": area},
        }
    with open(os.path.join(ROOT, "data", "churches.json"), "w") as f:
        json.dump(churches, f, indent=1)
        f.write("\n")
    with open(os.path.join(ROOT, "data", "town_npcs.json"), "w") as f:
        json.dump(npcs, f, indent=1)
        f.write("\n")
    print("updated churches.json + town_npcs.json")

if __name__ == "__main__":
    main()
