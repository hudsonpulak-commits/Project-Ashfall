"""0.3.11 register the Highfen layered-art props + new tiles in data/sprites.json and data/objects.json (idempotent)."""
import json, os, shutil
from PIL import Image
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SP = os.path.join(REPO, 'data/sprites.json'); OB = os.path.join(REPO, 'data/objects.json')
s = json.load(open(SP)); o = json.load(open(OB))
tiles_dir = os.path.join(REPO, 'assets/sprites/tiles')
for name, src, col, note in [('city_ring', 'grass', '#5a5450', 'under the Highfen city wall art (blocking)'),
                             ('art_wall', 'grass', '#6a5a4a', 'under layered-art building walls (blocking)'),
                             ('art_floor', 'stone_floor', '#8a7a64', 'under layered-art building floors')]:
    shutil.copyfile(os.path.join(tiles_dir, src + '.png'), os.path.join(tiles_dir, name + '.png'))
    s['tiles'][name] = {'path': f'res://assets/sprites/tiles/{name}.png', 'frame_size': [16, 16], 'minimap_color': col,
                        'note': f'0.3.11 {note}; the designer art draws over it'}
# 0.3.11b placeholders (no designer art): a plaza fountain and a round wall tower
from PIL import ImageDraw
pdir0 = os.path.join(REPO, 'assets/sprites/towns/highfen/props')
f = Image.new('RGBA', (40, 34)); d = ImageDraw.Draw(f)
d.ellipse([1, 12, 38, 33], fill=(90, 92, 100, 255), outline=(40, 40, 48, 255)); d.ellipse([5, 15, 34, 29], fill=(70, 130, 200, 255))
d.rectangle([17, 4, 22, 22], fill=(150, 150, 160, 255), outline=(60, 60, 70, 255)); d.ellipse([13, 1, 26, 8], fill=(110, 170, 230, 255))
f.save(os.path.join(pdir0, 'fountain.png'))
t = Image.new('RGBA', (24, 44)); d = ImageDraw.Draw(t)
d.rectangle([2, 10, 21, 43], fill=(52, 48, 56, 255), outline=(24, 22, 28, 255)); d.ellipse([2, 36, 21, 43], fill=(44, 40, 48, 255))
for x in range(2, 22, 5): d.rectangle([x, 4, x + 2, 10], fill=(60, 56, 64, 255), outline=(24, 22, 28, 255))
d.rectangle([10, 20, 13, 27], fill=(20, 18, 22, 255))
t.save(os.path.join(pdir0, 'wall_tower.png'))
NAMES = {'fountain': 'Fountain', 'wall_tower': 'Wall tower', 'tree_oak_a': 'Oak', 'tree_oak_b': 'Oak', 'tree_pine': 'Pine', 'tree_autumn': 'Autumn oak', 'statue_knight': 'Statue of a knight',
         'stall_fruit': 'Fruit stall', 'stall_cloth': 'Cloth stall', 'stall_fish': 'Fish stall', 'well': 'Well', 'cart': 'Cart', 'lamp_post': 'Lamp post',
         'banner_pole': 'Banner', 'sign_post_road': 'Signpost', 'sign_inn': 'Inn sign', 'sign_bread': 'Bakery sign'}
NONBLOCK = {'debris', 'debris_b', 'flowerbed_small', 'flowerbed_long', 'crate_broken', 'puddle', 'mud_patch'}
pdir = os.path.join(REPO, 'assets/sprites/towns/highfen/props')
for f in sorted(os.listdir(pdir)):
    if not f.endswith('.png'): continue
    n = f[:-4]; im = Image.open(os.path.join(pdir, f))
    s['objects']['hf_' + n] = {'path': f'res://assets/sprites/towns/highfen/props/{f}', 'frame_size': [im.width, im.height], 'frames': 1, 'anchor': 'bottom',
                               'note': '0.3.11 designer Highfen prop (art_handoff/towns/highfen)'}
    o['objects']['hf_' + n] = {'name': NAMES.get(n, n.replace('_', ' ').capitalize().replace(' a', '').replace(' b', '')), 'sprite': 'hf_' + n,
                               'blocks': n not in NONBLOCK, 'type': 'prop'}
json.dump(s, open(SP, 'w'), indent=1)
json.dump(o, open(OB, 'w'), indent=1)
print('ok')
