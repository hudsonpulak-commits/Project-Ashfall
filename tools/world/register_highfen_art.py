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
NAMES = {'tree_oak_a': 'Oak', 'tree_oak_b': 'Oak', 'tree_pine': 'Pine', 'tree_autumn': 'Autumn oak', 'statue_knight': 'Statue of a knight',
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
