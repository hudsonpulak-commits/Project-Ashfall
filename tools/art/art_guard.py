"""0.3.9.2 art protection: importing this module makes every PIL save skip
files listed in tools/art/protected_art.json (hand-drawn art), even with --force."""
import json, os
from PIL import Image
_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
try:
    PROTECTED = set(json.load(open(os.path.join(_ROOT, "tools", "art", "protected_art.json")))["files"])
except Exception:
    PROTECTED = set()
_orig_save = Image.Image.save

def is_protected(path) -> bool:
    try:
        return os.path.relpath(os.path.abspath(str(path)), _ROOT).replace(os.sep, "/") in PROTECTED
    except Exception:
        return False

def _guarded_save(self, fp, *a, **k):
    if isinstance(fp, (str, os.PathLike)) and is_protected(fp):
        print("art_guard: protected, not overwritten:", fp)
        return None
    return _orig_save(self, fp, *a, **k)

Image.Image.save = _guarded_save
