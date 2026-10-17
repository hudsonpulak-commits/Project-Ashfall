#!/usr/bin/env python3
"""Split edited Aseprite sheets back into game sprites.
Usage: python3 tools/art/import_sheets.py <folder with edited sheet PNGs>
Uses tools/art/aseprite_manifest.json (cell positions -> asset paths). Only sheets present are imported."""
import json,sys,os
from PIL import Image
man=json.load(open(os.path.join(os.path.dirname(__file__),'aseprite_manifest.json')))
src=sys.argv[1]
for name,m in man.items():
  p=os.path.join(src,name+'.png')
  if not os.path.exists(p): continue
  sh=Image.open(p).convert('RGBA')
  if sh.size!=(m['cols']*m['cell_w'],m['rows']*m['cell_h']): print('SIZE MISMATCH, skipped',name,sh.size); continue
  for c in m['cells']:
    sh.crop((c['x'],c['y'],c['x']+c['w'],c['y']+c['h'])).save(c['file'])
  print('imported',name,len(m['cells']))
