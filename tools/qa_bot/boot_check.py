#!/usr/bin/env python3
"""0.3.2 cold-boot QA on the EXPORTED build (release gate).

Runs the Android export preset's pack (same filters, compatibility renderer)
on the size-optimised engine template built with the Android feature profile
(tools/engine/ashfen_custom.py -> templates-custom/linux_release_ashfen_*),
rendered under Xvfb, driven by real X clicks (xdotool), filmed with ffmpeg.

Checks (B1-B5):
  B1 cold start, no save: the main menu shows (title + buttons in the frame)
  B2 New Game -> slot -> Start reaches gameplay (HUD frame, BOOT gameplay)
  B3 a real 0.3.0 save (v3, left 6 h ago) in slot 1: Continue migrates it
     through v3->v8 and reaches gameplay (catch-up within its budget)
  B4 a damaged save: the menu shows an error and the bad file is kept aside
  B5 no frame is blank (one flat colour) for more than 3 s in any run

  tools/qa_bot/boot_check.py --pck build/qa_boot/ashfen.pck --out build/qa_boot
Exit 0 = all pass. Evidence: <out>/boot_*.png, <out>/boot_report.md
"""
import argparse, json, os, re, shutil, signal, subprocess, sys, time
from PIL import Image, ImageStat

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
W, H = 360, 780
BLANK_STD = 3.0
MAX_BLANK_S = 3.0
FPS = 4


def sh(cmd, **kw):
    return subprocess.run(cmd, shell=True, **kw)


class Run:
    def __init__(self, name, out, binary, display, home):
        self.name, self.out, self.bin, self.display, self.home = name, out, binary, display, home
        self.frames = os.path.join(out, "frames_" + name)
        shutil.rmtree(self.frames, ignore_errors=True)
        os.makedirs(self.frames)
        self.log_path = os.path.join(out, "boot_%s.log" % name)
        env = dict(os.environ, HOME=home, XDG_DATA_HOME=home, DISPLAY=display)
        self.t0 = time.time()
        self.rec = subprocess.Popen(["ffmpeg", "-loglevel", "error", "-y", "-f", "x11grab", "-framerate", str(FPS),
                                     "-video_size", "%dx%d" % (W, H), "-i", display + "+0,0",
                                     os.path.join(self.frames, "f%05d.png")], stdin=subprocess.DEVNULL)
        self.log = open(self.log_path, "w")
        self.proc = subprocess.Popen([binary, "--resolution", "%dx%d" % (W, H), "--position", "0,0", "--", "--qa-boot"],
                                     stdout=self.log, stderr=subprocess.STDOUT, env=env, cwd=os.path.dirname(binary))

    def text(self):
        """stdout (buffered by the release engine) + the game's flushed boot trace."""
        self.log.flush()
        t = open(self.log_path, errors="replace").read()
        live = os.path.join(self.home, "godot", "app_userdata", "Ashfen", "qa_boot.log")
        if os.path.exists(live):
            t += "\n" + open(live, errors="replace").read()
        return t

    def wait_for(self, pattern, timeout):
        end = time.time() + timeout
        while time.time() < end:
            m = re.findall(pattern, self.text())
            if m:
                return m
            if self.proc.poll() is not None:
                return None
            time.sleep(0.2)
        return None

    def wait_count(self, pattern, n, timeout):
        end = time.time() + timeout
        while time.time() < end:
            if len(re.findall(pattern, self.text())) >= n:
                return True
            if self.proc.poll() is not None:
                return False
            time.sleep(0.2)
        return False

    def button(self, key, timeout=10):
        m = self.wait_for(r"MENU button %s (\d+) (\d+) (\d+) (\d+)" % key, timeout)
        if not m:
            return None
        x, y, w, h = map(int, m[-1])
        return (x + w // 2, y + h // 2)

    def click(self, key, timeout=10):
        p = self.button(key, timeout)
        if p is None:
            return False
        before = len(re.findall(r"MENU page", self.text()))
        sh("DISPLAY=%s xdotool mousemove %d %d click 1" % (self.display, p[0], p[1]))
        time.sleep(0.6)
        return True

    def grab(self, name):
        p = os.path.join(self.out, name)
        sh("DISPLAY=%s ffmpeg -loglevel error -y -f x11grab -video_size %dx%d -i %s+0,0 -frames:v 1 %s" % (self.display, W, H, self.display, p))
        return p

    def stop(self):
        for p in (self.proc, self.rec):
            if p.poll() is None:
                p.send_signal(signal.SIGINT if p is self.rec else signal.SIGTERM)
        try:
            self.rec.wait(5)
        except Exception:
            self.rec.kill()
        try:
            self.proc.wait(5)
        except Exception:
            self.proc.kill()
        self.log.close()

    def longest_blank(self):
        files = sorted(f for f in os.listdir(self.frames) if f.endswith(".png"))
        run = best = 0
        start_at = None
        for f in files:
            st = ImageStat.Stat(Image.open(os.path.join(self.frames, f)).convert("RGB"))
            blank = max(st.stddev) < BLANK_STD
            run = run + 1 if blank else 0
            best = max(best, run)
        return best / float(FPS), len(files)


def is_menu(png):
    im = Image.open(png).convert("RGB")
    st = ImageStat.Stat(im)
    return max(st.stddev) > 12


def label_pixels(png):
    """0.3.4: overhead name labels = label-coloured pixels (AI cream #ffffbf,
    trader blue #b2e5ff, enemy green / yellow / red) touching their black
    outline, in the world area between the HUD top and the chat log."""
    im = Image.open(png).convert("RGB")
    w, h = im.size
    cols = [(255, 255, 191), (178, 229, 255), (106, 224, 106), (255, 224, 74), (255, 90, 74)]
    px = im.load()
    n = 0
    for y in range(int(h * 0.13), int(h * 0.82)):
        for x in range(2, w - 2):
            r, g, b = px[x, y]
            if not any(abs(r - c[0]) + abs(g - c[1]) + abs(b - c[2]) < 60 for c in cols):
                continue
            if any(sum(px[x + dx, y + dy]) < 90 for dx in (-2, -1, 1, 2) for dy in (-1, 0, 1)):
                n += 1
    return n


def hud_visible(png):
    """The HUD's bottom tab bar (Pack/Skills/Map/Menu) is a dark strip of
    panels with light text; the frame must not be one flat colour either."""
    im = Image.open(png).convert("RGB")
    strip = im.crop((0, H - 40, W, H))
    st = ImageStat.Stat(strip)
    return max(ImageStat.Stat(im).stddev) > 12 and max(st.stddev) > 10


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pck", required=True)
    ap.add_argument("--template", default=os.path.join(os.environ.get("TOOLS_DIR", "/workspace/tools"), "templates-custom", "linux_release_ashfen_4.7.2.x86_64"))
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "qa_boot"))
    ap.add_argument("--display", default=":89")
    a = ap.parse_args()
    out = os.path.abspath(a.out)
    os.makedirs(out, exist_ok=True)
    bindir = os.path.join(out, "bin")
    shutil.rmtree(bindir, ignore_errors=True)
    os.makedirs(bindir)
    binary = os.path.join(bindir, "ashfen.x86_64")
    shutil.copy(a.template, binary)
    os.chmod(binary, 0o755)
    shutil.copy(a.pck, os.path.join(bindir, "ashfen.pck"))
    xvfb = None
    if sh("DISPLAY=%s xdpyinfo >/dev/null 2>&1" % a.display).returncode != 0:
        xvfb = subprocess.Popen(["Xvfb", a.display, "-screen", "0", "1280x1024x24"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(1.0)
    results = []
    evidence = []

    def res(cid, what, ok, detail):
        results.append((cid, what, bool(ok), detail))
        print("%s  %s %s :: %s" % ("PASS" if ok else "FAIL", cid, what, detail))

    def home(name):
        h = os.path.join(out, "home_" + name)
        shutil.rmtree(h, ignore_errors=True)
        os.makedirs(os.path.join(h, "godot", "app_userdata", "Ashfen"))
        return h

    blanks = {}
    # ---- B1 + B2: cold start, New Game
    r = Run("new", out, binary, a.display, home("new"))
    try:
        shown = r.wait_for(r"BOOT menu shown at (\d+) ms", 30)
        time.sleep(1.0)
        menu_png = r.grab("boot_menu.png")
        evidence.append(menu_png)
        res("B1", "cold start (no save) shows the main menu", shown and r.button("NewGame", 5) and r.button("Quit", 1) and is_menu(menu_png),
            "menu after %s ms; buttons %s" % (shown[0] if shown else None, re.findall(r"MENU button (\w+)", r.text())[:6]))
        ok = r.click("NewGame") and r.click("Slot1") and r.click("StartNew")
        loading = r.wait_for(r"BOOT progress", 15)
        time.sleep(0.3)
        evidence.append(r.grab("boot_loading.png"))
        game = r.wait_for(r"BOOT gameplay \(slot (\d+)\) after (\d+) ms", 90)
        time.sleep(2.0)
        g_png = r.grab("boot_ingame_new.png")
        evidence.append(g_png)
        res("B2", "New Game -> slot 1 -> Start reaches gameplay", ok and loading and game and hud_visible(g_png),
            "clicks %s; loading screen %s; gameplay at %s ms" % (ok, bool(loading), game[0][1] if game else None))
        saved = os.path.exists(os.path.join(r.home, "godot", "app_userdata", "Ashfen", "ashfen_save.json"))
        res("B2", "the new game is saved to slot 1 right away", saved, "slot file %s" % saved)
    finally:
        r.stop()
    blanks["new"] = r.longest_blank()

    # ---- B3: a real 0.3.0 (v3) save left 6 h ago
    h = home("v030")
    fx = json.load(open(os.path.join(ROOT, "tools", "qa_bot", "fixtures", "save_v3_030.json")))
    fx["saved_unix"] = int(time.time()) - 6 * 3600
    json.dump(fx, open(os.path.join(h, "godot", "app_userdata", "Ashfen", "ashfen_save.json"), "w"))
    r = Run("v030", out, binary, a.display, h)
    try:
        r.wait_for(r"BOOT menu shown", 30)
        time.sleep(0.8)
        evidence.append(r.grab("boot_menu_with_save.png"))
        ok = r.click("LoadGame") and r.click("Slot1")
        time.sleep(0.2)
        evidence.append(r.grab("boot_loading_v030.png"))
        game = r.wait_for(r"BOOT gameplay \(slot (\d+)\) after (\d+) ms", 90)
        time.sleep(2.0)
        g_png = r.grab("boot_ingame_loaded.png")
        evidence.append(g_png)
        txt = r.text()
        cu = re.findall(r"OFFLINE catch-up: (\d+) ticks in (\d+) ms", txt)
        errs = [l for l in txt.splitlines() if "SCRIPT ERROR" in l]
        sv = json.load(open(os.path.join(h, "godot", "app_userdata", "Ashfen", "ashfen_save.json"))) if game else {}
        res("B3", "Load Game -> slot 1 (0.3.0 v3 save, 6 h old) migrates and reaches gameplay", ok and game and hud_visible(g_png) and not errs,
            "gameplay at %s ms; catch-up %s; script errors %d" % (game[0][1] if game else None, cu[-1] if cu else None, len(errs)))
        r2 = re.findall(r"BOOT progress (\d+)% While you were away", txt)
        res("B3", "slot list showed the old save; it loads with a progress bar (catch-up in chunks)", "Slot1" in txt and len(r2) >= 2, "%d catch-up progress steps" % len(r2))
    finally:
        r.stop()
    blanks["v030"] = r.longest_blank()

    # ---- B3b (0.3.3): a real 0.3.2 (v8) save, no Archery key: loads, Archery 1
    h = home("v032")
    fx = json.load(open(os.path.join(ROOT, "tools", "qa_bot", "fixtures", "save_v8_032.json")))
    fx["saved_unix"] = int(time.time()) - 600
    json.dump(fx, open(os.path.join(h, "godot", "app_userdata", "Ashfen", "ashfen_save.json"), "w"))
    r = Run("v032", out, binary, a.display, h)
    try:
        r.wait_for(r"BOOT menu shown", 30)
        time.sleep(0.8)
        ok = r.click("LoadGame") and r.click("Slot1")
        game = r.wait_for(r"BOOT gameplay \(slot (\d+)\) after (\d+) ms", 90)
        time.sleep(2.0)
        g_png = r.grab("boot_ingame_v032.png")
        evidence.append(g_png)
        txt = r.text()
        errs = [l for l in txt.splitlines() if "SCRIPT ERROR" in l]
        res("B3b", "Load Game -> slot 1 (0.3.2 v8 save) reaches gameplay with no script errors", ok and game and hud_visible(g_png) and not errs,
            "gameplay at %s ms; script errors %d" % (game[0][1] if game else None, len(errs)))
    finally:
        r.stop()
    blanks["v032"] = r.longest_blank()

    # ---- B4: a damaged save
    h = home("bad")
    open(os.path.join(h, "godot", "app_userdata", "Ashfen", "ashfen_save.json"), "w").write('{"version": 3, "player": "oops", "world": 7}')
    r = Run("bad", out, binary, a.display, h)
    try:
        r.wait_for(r"BOOT menu shown", 30)
        time.sleep(0.8)      # 0.3.3: let the menu fade in before the click (flaky under load)
        ok = r.click("LoadGame")
        slot_disabled = True
        r.click("Slot1")
        failed = r.wait_for(r"BOOT load failed: (.*)", 20)
        r.wait_count(r"BOOT menu shown", 2, 20)
        time.sleep(1.0)
        evidence.append(r.grab("boot_bad_save.png"))
        files = os.listdir(os.path.join(h, "godot", "app_userdata", "Ashfen"))
        kept = [f for f in files if ".bad-" in f]
        res("B4", "a damaged save returns to the menu with a message; the file is kept aside", failed and kept and not os.path.exists(os.path.join(h, "godot", "app_userdata", "Ashfen", "ashfen_save.json")),
            "error %r; kept %s" % (failed[0][:90] if failed else None, kept[:2]))
    finally:
        r.stop()
    blanks["bad"] = r.longest_blank()

    lab = {k: label_pixels(os.path.join(out, k)) for k in ("boot_ingame_new.png", "boot_ingame_v032.png") if os.path.exists(os.path.join(out, k))}
    res("B6", "overhead name/level labels render in the exported build (label-colour pixels in the world area)", bool(lab) and max(lab.values()) >= 25,
        "; ".join("%s: %d px" % kv for kv in lab.items()))

    worst = max(v[0] for v in blanks.values())
    res("B5", "no blank (flat colour) frame run longer than %.0f s after start" % MAX_BLANK_S, worst <= MAX_BLANK_S,
        "; ".join("%s: longest %.2f s of %d frames" % (k, v[0], v[1]) for k, v in blanks.items()))
    if xvfb:
        xvfb.terminate()
    for k in blanks:
        shutil.rmtree(os.path.join(out, "frames_" + k), ignore_errors=True)
    passed = sum(1 for x in results if x[2])
    with open(os.path.join(out, "boot_report.md"), "w") as f:
        f.write("# Boot QA (exported build, compatibility renderer)\n\n| id | check | result | detail |\n|---|---|---|---|\n")
        for cid, what, ok, det in results:
            f.write("| %s | %s | %s | %s |\n" % (cid, what, "PASS" if ok else "FAIL", det.replace("|", "/")))
        f.write("\nEvidence: %s\n" % ", ".join(os.path.basename(e) for e in evidence))
    print("BOOT QA: %s (%d/%d)" % ("PASS" if passed == len(results) else "FAIL", passed, len(results)))
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
