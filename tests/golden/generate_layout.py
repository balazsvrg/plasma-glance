#!/usr/bin/env python3
"""Regenerates tests/golden/layout.json from the old layout code of main.qml.

    python3 tests/golden/generate_layout.py [git-revision]        (default: HEAD)

The script reads package/contents/ui/main.qml at the given revision. It cuts out the length functions
(stripLength, levelList, computeFit, configs, snapLimit, dragLayout, dragFit, beginDrag, dragStep, dragMax)
and runs them in Qt's JavaScript engine (PySide6 QJSEngine) with stub data: the shown ids, a cell length
for each id and level, the orientation, the spacing for each level and the maximum length.

The grid: 0 to 6 stats, horizontal and vertical, three sets of cell lengths for each case, limits from 0
to above the full length, and pointer walks for the drag. The output is deterministic.

Use a revision whose main.qml still holds these functions. After the layout module replaced them, use
the commit before that change. Review the diff of the JSON as a behaviour change.
"""
import json
import os
import random
import subprocess
import sys

from PySide6.QtCore import QCoreApplication
from PySide6.QtQml import QJSEngine

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REV = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
OUT = os.path.join(ROOT, "tests", "golden", "layout.json")
FUNCTIONS = ["stripLength", "levelList", "computeFit", "configs", "snapLimit", "dragLayout", "dragFit",
             "beginDrag", "dragStep", "dragMax"]
# Spacing stubs, in px, for each level (Kirigami smallSpacing / largeSpacing stand-ins).
SPACING = {0: 8, 1: 8, 2: 8, 3: 4}
ROW_SPACING = {0: 4, 1: 4, 2: 4, 3: 0}


def source(rev):
    return subprocess.check_output(["git", "-C", ROOT, "show", "%s:package/contents/ui/main.qml" % rev], text=True)


def function_text(qml, name):
    """The text of `    function name(...) { ... }`, found by matching braces."""
    start = qml.index("    function %s(" % name)
    i = qml.index("{", start)
    depth = 0
    for j in range(i, len(qml)):
        if qml[j] == "{":
            depth += 1
        elif qml[j] == "}":
            depth -= 1
            if depth == 0:
                return qml[start:j + 1]
    raise SystemExit("unbalanced braces in %s" % name)


def build_engine(qml):
    code = "\n".join(function_text(qml, f) for f in FUNCTIONS)
    e = QJSEngine()
    r = e.evaluate("""var IDS = [], CELLS = {}, SP = {}, RSP = {}, vertical = false, maxLength = 0;
var dragging = false, dragMoved = false, dragLength = 0, dragCfg = 0, layouts = [];
function shownIds() { return IDS }
function cellLength(id, level) { return CELLS[id][level] }
function spacingFor(level) { return SP[level] }
function rowSpacingFor(level) { return RSP[level] }
%s
function setup(ids, cells, vert, ml) {
    IDS = ids; CELLS = cells; vertical = vert; maxLength = ml; layouts = configs()
}
""" % code)
    if r.isError():
        raise SystemExit("JS error: %s" % r.toString())
    return e


def js(e, expr):
    r = e.evaluate("JSON.stringify(" + expr + ")")
    if r.isError():
        raise SystemExit("JS error in %s: %s" % (expr, r.toString()))
    return json.loads(r.toString())


def cell_sets(n, vertical, rng):
    """Three sets of cell lengths: [id][level]. Level 3 is the shortest, in each set."""
    sets = []
    # Set 0: lengths that fall with the level, like real text.
    sets.append([[60 + 17 * i, 52 + 14 * i, 40 + 10 * i, 30 + 6 * i] for i in range(n)])
    # Set 1: seeded random lengths that never grow with the level.
    s = []
    for i in range(n):
        a = rng.randint(30, 140)
        b = rng.randint(max(10, a - 40), a)
        c = rng.randint(max(10, b - 30), b)
        d = rng.randint(max(5, c - 25), c)
        s.append([a, b, c, d])
    sets.append(s)
    # Set 2: equal lengths on several levels, so layouts have equal total lengths.
    sets.append([[50, 40, 40, 40] if i % 2 == 0 else [50, 50, 30, 30] for i in range(n)])
    return sets


def scenario(e, n, vertical, variant, cells_by_index):
    ids = ["s%d" % i for i in range(n)]
    cells = {ids[i]: cells_by_index[i] for i in range(n)}
    e.evaluate("SP = %s; RSP = %s" % (json.dumps(SPACING), json.dumps(ROW_SPACING)))
    e.evaluate("setup(%s, %s, %s, 0)" % (json.dumps(ids), json.dumps(cells), "true" if vertical else "false"))
    levels = js(e, "levelList()")
    strips = {}
    for lv in levels:
        for drop in range(0, n + 1):
            strips["%d,%d" % (lv, drop)] = js(e, "stripLength(%d, %d)" % (lv, drop))
    configs = js(e, "configs()")
    full = js(e, "stripLength(0, 0)")
    gap = {str(lv): 1 + 2 * (ROW_SPACING[lv] if vertical else SPACING[lv]) for lv in levels}
    cells_out = {str(lv): [cells_by_index[i][lv] for i in range(n)] for lv in levels}
    # Limits: every 3 px, plus the layout lengths and their neighbours.
    limits = set(range(-2, full + 25, 3))
    for c in configs:
        limits.update([c["len"] - 1, c["len"], c["len"] + 1])
    limits.update([full - 1, full, full + 1])
    fits = []
    for ml in sorted(limits):
        e.evaluate("maxLength = %d" % ml)
        f = js(e, "computeFit()")
        fits.append([ml, f["level"], f["drop"]])
    e.evaluate("maxLength = 0")
    # Pointer walks.
    top = full + 15
    rng = random.Random(1000 * n + 10 * variant + (1 if vertical else 0))
    down = list(range(top, -1, -7))
    up = list(range(0, top + 1, 7))
    zig = [rng.randint(0, top) for _ in range(40)]
    nudge = []
    for c in configs:
        nudge += [c["len"] + 1, c["len"], c["len"] - 1, c["len"] - 2, c["len"] + 3]
    walks_points = [down, up, down + up, zig, nudge]
    starts = sorted({0, full, max(0, full // 2), max(0, full - 5)} | {c["len"] for c in configs[1:2]})
    walks = []
    for ml in starts:
        for pts in walks_points:
            e.evaluate("maxLength = %d" % ml)
            begin = js(e, "(beginDrag(%d), dragCfg)" % (ml if ml > 0 else full))
            steps = []
            for p in pts:
                steps.append(js(e, "(dragLength = %d, dragStep(), [dragCfg, snapLimit(), dragMax()])" % p))
            walks.append({"maxLength": ml, "begin": begin, "points": pts, "steps": steps})
    e.evaluate("maxLength = 0")
    return {"name": "n%d-%s-v%d" % (n, "vert" if vertical else "horiz", variant), "n": n, "vertical": vertical,
            "levels": levels, "cells": cells_out, "gap": gap, "full": full, "strips": strips,
            "configs": configs, "fits": fits, "walks": walks}


def main():
    app = QCoreApplication([])
    e = build_engine(source(REV))
    scenarios = []
    for n in range(0, 7):
        for vertical in (False, True):
            rng = random.Random(7 * n + (1 if vertical else 0))
            for variant, cells in enumerate(cell_sets(n, vertical, rng)):
                scenarios.append(scenario(e, n, vertical, variant, cells))
    data = {"revision": REV, "scenarios": scenarios}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, sort_keys=True, separators=(",", ":"))
        f.write("\n")
    print("wrote %s: %d scenarios" % (OUT, len(scenarios)))


main()
