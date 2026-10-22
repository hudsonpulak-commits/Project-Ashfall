"""0.3.11 v3.1b Hudson: the dark v3 ground read too close to the buildings - lift road_stone / cobble /
cobble_dark / the plaza cobble by ~1-2 shades: value x1.13 + a small lift, hue AND saturation kept
(every channel is scaled by the same factor). Always graded from the designer originals in
art_handoff (read-only), so re-running never compounds."""
import numpy as np
from PIL import Image
GAIN, LIFT = 1.13, 5.0 / 255

def grade(a):
    a = np.array(a.convert('RGBA')).astype(float); rgb = a[..., :3] / 255
    v = rgb.max(-1, keepdims=True); nv = np.clip(v * GAIN + LIFT, 0, 1)
    k = np.where(v > 0, nv / np.maximum(v, 1e-6), 1)
    out = np.clip(rgb * k, 0, 1)
    out = np.where(v > 0, out, LIFT)          # pure black specks get the lift too
    a[..., :3] = out * 255
    return Image.fromarray(np.round(a).astype(np.uint8), 'RGBA')

def grade_file(src, dst): grade(Image.open(src)).save(dst)

if __name__ == '__main__':
    import os
    REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
    G = '/workspace/art_handoff/towns/highfen/ground_textures_v3'
    for n in ('road_stone', 'cobble', 'cobble_dark'):
        grade_file(f'{G}/tiles/{n}.png', f'{REPO}/assets/sprites/tiles/{n}.png')
        grade_file(f'{G}/transitions/{n}.png', f'{REPO}/assets/sprites/transitions/{n}.png')
    print('graded ground textures')
