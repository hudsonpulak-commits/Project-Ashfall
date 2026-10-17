#!/usr/bin/env python3
"""Render the soak-test chart.

usage: soak_chart.py RUN_DIR [CONTROL_DIR] [-o out.png]
RUN_DIR / CONTROL_DIR contain soak.json written by src/tests/soak.gd
(CONTROL_DIR = a --no-traders run). Prints a comparison of cross-town spreads.
"""
import argparse, json, os, sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

TOWN_COLORS = {"fenhollow": "#3a7d44", "cinderholt": "#b5523b", "saltmere": "#3b6fb5"}
SHOW_ITEMS = ["iron_ore", "raw_eel", "alder_log", "iron_helm", "iron_hauberk", "iron_mace"]


def load(d):
    with open(os.path.join(d, "soak.json")) as f:
        return json.load(f)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run")
    ap.add_argument("control", nargs="?")
    ap.add_argument("-o", "--out", default=None)
    a = ap.parse_args()
    run = load(a.run)
    ctl = load(a.control) if a.control else None
    out = a.out or os.path.join(a.run, "soak_chart.png")
    rows = run["rows"]
    days = [r["day"] for r in rows]
    towns = run["towns"]

    fig = plt.figure(figsize=(13, 13), dpi=100)
    gs = fig.add_gridspec(4, 3, hspace=0.55, wspace=0.28)
    fig.suptitle("Ashfen economy soak: %d game days, %d AI agents, %d towns  (solid = with travelling traders%s)"
                 % (run["days"], run["agents"], len(towns), ", dashed = traders off" if ctl else ""), fontsize=12)

    ax = fig.add_subplot(gs[0, 0])
    ax.plot(days, [r["index"] for r in rows], "k-", lw=2, label="all towns")
    for t in towns:
        ax.plot(days, [r["towns"][t]["index"] for r in rows], color=TOWN_COLORS.get(t), lw=1.2, label=t.capitalize())
    if ctl:
        ax.plot([r["day"] for r in ctl["rows"]], [r["index"] for r in ctl["rows"]], "k--", lw=1, label="all (no traders)")
    ax.axhspan(0.85, 1.15, color="#eee", zorder=0)
    ax.set_title("Price index (basket / base)")
    ax.legend(fontsize=7)

    ax = fig.add_subplot(gs[0, 1])
    ax.plot(days, [r["money"] for r in rows], "k-", lw=2, label="money supply")
    ax.plot(days, [r["ai_coins"] for r in rows], color="#888", lw=1, label="AI coins")
    if ctl:
        ax.plot([r["day"] for r in ctl["rows"]], [r["money"] for r in ctl["rows"]], "k--", lw=1, label="money (no traders)")
    m0 = rows[0]["money"]
    ax.axhspan(m0 * 0.7, m0 * 1.3, color="#eee", zorder=0)
    ax.set_title("Money supply (marks)")
    ax.legend(fontsize=7)

    ax = fig.add_subplot(gs[0, 2])
    ax.bar([d - 0.2 for d in days[1:]], [r["faucet"] for r in rows[1:]], 0.4, color="#6a6", label="faucets")
    ax.bar([d + 0.2 for d in days[1:]], [r["sink"] for r in rows[1:]], 0.4, color="#a66", label="sinks")
    ax.set_title("Daily faucets vs sinks")
    ax.legend(fontsize=7)

    for i, item in enumerate(SHOW_ITEMS):
        ax = fig.add_subplot(gs[1 + i // 3, i % 3])
        for t in towns:
            ax.plot(days, [r["towns"][t]["refs"][item] for r in rows], color=TOWN_COLORS.get(t), lw=1.8, label=t.capitalize())
            if ctl:
                ax.plot([r["day"] for r in ctl["rows"]], [r["towns"][t]["refs"][item] for r in ctl["rows"]],
                        color=TOWN_COLORS.get(t), lw=1, ls="--")
        ax.set_title("%s: reference price by town" % item)
        if i == 0:
            ax.legend(fontsize=7)

    ax = fig.add_subplot(gs[3, 0:2])
    ax.plot(days, [r["mean_spread"] for r in rows], "k-", lw=2, label="mean spread, traders on")
    if ctl:
        ax.plot([r["day"] for r in ctl["rows"]], [r["mean_spread"] for r in ctl["rows"]], "k--", lw=1.5, label="mean spread, traders off")
    mx = [max(r["spreads"].values()) for r in rows]
    ax.plot(days, mx, color="#b5523b", lw=1.2, label="max item spread, traders on")
    if ctl:
        ax.plot([r["day"] for r in ctl["rows"]], [max(r["spreads"].values()) for r in ctl["rows"]], color="#b5523b", ls="--", lw=1,
                label="max item spread, traders off")
    ax.axhline(1.0, color="#999", lw=0.8)
    ax.set_title("Cross-town price gap (dearest town / cheapest town, %d key items)" % len(run["key_items"]))
    ax.legend(fontsize=7)

    ax = fig.add_subplot(gs[3, 2])
    ax.bar(days[1:], [r["trips"] for r in rows[1:]], color="#3b6fb5")
    ax.set_title("Trader trips per day")

    fig.savefig(out, bbox_inches="tight")
    print("chart ->", out)
    last = rows[-1]
    print("traders on : final mean spread %.3f, max %.3f" % (last["mean_spread"], max(last["spreads"].values())))
    if ctl:
        cl = ctl["rows"][-1]
        print("traders off: final mean spread %.3f, max %.3f" % (cl["mean_spread"], max(cl["spreads"].values())))
        avg_on = sum(r["mean_spread"] for r in rows[1:]) / max(1, len(rows) - 1)
        avg_off = sum(r["mean_spread"] for r in ctl["rows"][1:]) / max(1, len(ctl["rows"]) - 1)
        ok = avg_on < avg_off
        print("%s arbitrage narrows gaps: average mean spread %.3f (on) vs %.3f (off)" % ("ok  " if ok else "FAIL", avg_on, avg_off))
        return 0 if ok else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
