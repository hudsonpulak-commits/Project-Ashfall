#!/usr/bin/env python3
"""0.4.2: pack the sprite bot's underground v1.1 den pieces into engine sheets."""
from PIL import Image
U = "assets/sprites/underground/den/"
fl = Image.new("RGBA", (64, 16))
for i in range(4):
    fl.paste(Image.open(U + "den_floor_%d.png" % i).convert("RGBA"), (i * 16, 0))
fl.save("assets/sprites/tiles/variants/den_floor_x4.png")
m15 = Image.open(U + "den_wall_m15.png").convert("RGBA")
m15.crop((0, 0, 16, 16)).save("assets/sprites/tiles/den_wall.png")
at = Image.new("RGBA", (20 * 16, 32))
for m in range(16):
    p = Image.open(U + "den_wall_m%02d.png" % m).convert("RGBA")
    at.paste(p.crop((0, 0, 16, 16)), (m * 16, 0)); at.paste(p.crop((0, 16, 16, 32)), (m * 16, 16))
for i, k in enumerate(["ne", "se", "sw", "nw"]):
    p = Image.open(U + "den_wall_inner_%s.png" % k).convert("RGBA")
    at.paste(p.crop((0, 0, 16, 16)), ((16 + i) * 16, 0)); at.paste(p.crop((0, 16, 16, 32)), ((16 + i) * 16, 16))
at.save("assets/sprites/autotile/den_wall16.png")
