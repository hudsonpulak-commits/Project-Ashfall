"""0.3.11 designer cliff tiles (art_handoff/cliffs, read-only) -> assets/sprites/cliffs/{normal,cinder}; registered
in data/sprites.json: autotile/<name> (normal) and autotile/cinder_<name>; the old placeholder tile textures for
cliff_face/lip/shadow/stairs point at the designer's tiles; props/outcrops/boulder become objects."""
import json, os, shutil
from PIL import Image
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SRC = '/workspace/art_handoff/cliffs'
DST = os.path.join(REPO, 'assets/sprites/cliffs')
for pal in ('normal', 'cinder'):
    os.makedirs(os.path.join(DST, pal), exist_ok=True)
    for f in os.listdir(os.path.join(SRC, pal)):
        shutil.copyfile(os.path.join(SRC, pal, f), os.path.join(DST, pal, f))
shutil.copyfile(os.path.join(SRC, 'README.md'), os.path.join(DST, 'README_designer.md'))
shutil.copyfile(os.path.join(SRC, 'manifest.json'), os.path.join(DST, 'manifest.json'))
SP = os.path.join(REPO, 'data/sprites.json'); OB = os.path.join(REPO, 'data/objects.json')
s = json.load(open(SP)); o = json.load(open(OB))
for k in [k for k in s['autotile'] if k.startswith('cliff_') or k.startswith('cinder_cliff_')]:
    del s['autotile'][k]
PROPS = ('cliff_boulder', 'cliff_outcrop_a', 'cliff_outcrop_b', 'prop_grass_tuft', 'prop_pebbles', 'prop_rocks')
for pal in ('normal', 'cinder'):
    for f in sorted(os.listdir(os.path.join(DST, pal))):
        n = f[:-4]; im = Image.open(os.path.join(DST, pal, f))
        if n in PROPS: continue
        key = n if pal == 'normal' else 'cinder_' + n
        s['autotile'][key] = {'path': f'res://assets/sprites/cliffs/{pal}/{f}', 'frame_size': [16, 16], 'frames': im.height // 16,
                              'note': '0.3.11 designer cliff tile (%s)%s' % (pal, '; 16x32: edge cell + overhang into the cell below' if im.height == 32 else '')}
base = {'cliff_face': 'cliff_top', 'cliff_lip': 'cliff_top', 'cliff_shadow': 'cliff_top', 'cliff_stairs': 'cliff_stairs', 'cliff_foot': 'cliff_top'}
for t, f in base.items():
    e = s['tiles'].get(t, {})
    e.update({'path': f'res://assets/sprites/cliffs/normal/{f}.png', 'frame_size': [16, 16],
              'note': '0.3.11 designer cliff art; in-game the autotile pieces (autotile/cliff_*) draw the look over region ground'})
    e.setdefault('minimap_color', '#4a3f38')
    s['tiles'][t] = e
NM = {'cliff_boulder': 'Boulder', 'cliff_outcrop_a': 'Rock outcrop', 'cliff_outcrop_b': 'Rock outcrop', 'prop_grass_tuft': 'Grass tuft', 'prop_pebbles': 'Pebbles', 'prop_rocks': 'Rocks'}
for n in PROPS:
    for pal in ('normal', 'cinder'):
        key = n if pal == 'normal' else 'cinder_' + n
        im = Image.open(os.path.join(DST, pal, n + '.png'))
        s['objects'][key] = {'path': f'res://assets/sprites/cliffs/{pal}/{n}.png', 'frame_size': list(im.size), 'frames': 1, 'anchor': 'bottom',
                             'note': '0.3.11 designer cliff prop (%s)' % pal}
        o['objects'][key] = {'name': NM[n], 'sprite': key, 'blocks': n.startswith('cliff_'), 'type': 'prop'}
json.dump(s, open(SP, 'w'), indent=1); json.dump(o, open(OB, 'w'), indent=1)
print('ok')
