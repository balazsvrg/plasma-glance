#!/usr/bin/env python3
"""Tests for package/contents/ui/Layout.js (strip length, fit and drag arithmetic), run without Plasma.

    python3 tests/layout_test.py

Needs python3 with PySide6. Exits non-zero when any check fails. The environment variable LAYOUT_JS
sets another path for the module (used to test the tests with a changed copy). What it checks:
  1. rule cases written by hand: stripLength, configs, computeFit (every branch), dragStart, snapLimit,
     dragStep (the halfway rule) and dragMax;
  2. the same functions against tests/golden/layout.json, which holds the results of the old code of
     main.qml (made by tests/golden/generate_layout.py) on a grid of stat counts, orientations, limits
     and pointer walks.

Input record: {levels: [0,1,2,3], cells: {level: [length of each shown stat]}, gap: {level: separator cost}}.
A layout is {level, drop, len}. A fit is {level, drop}.
"""
import json
import os
import re
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtCore import QCoreApplication
from PySide6.QtQml import QJSEngine

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAYOUT_JS_PATH = os.environ.get("LAYOUT_JS") or os.path.join(ROOT, "package", "contents", "ui", "Layout.js")
GOLDEN = os.path.join(ROOT, "tests", "golden", "layout.json")
PRAGMA = re.compile(r"^\.pragma library\s*$", re.M)

app = QCoreApplication([])
failures = []
passed = 0


def check(name, ok, detail=""):
    global passed
    if ok:
        passed += 1
    else:
        failures.append(name)
        print("FAIL  %s %s" % (name, detail))


def equal(name, got, want):
    check(name, got == want, "\n        got:  %r\n        want: %r" % (got, want))


if not os.path.exists(LAYOUT_JS_PATH):
    raise SystemExit("FAIL  file not found: %s" % LAYOUT_JS_PATH)
E = QJSEngine()
r = E.evaluate(PRAGMA.sub("", open(LAYOUT_JS_PATH, encoding="utf-8").read()))
if r.isError():
    raise SystemExit("JS error: %s" % r.toString())


def run(expr):
    r = E.evaluate("JSON.stringify(" + expr + ")")
    if r.isError():
        raise SystemExit("JS error in %s: %s" % (expr, r.toString()))
    return json.loads(r.toString())


def call(fn, *args):
    return run("%s(%s)" % (fn, ", ".join(json.dumps(a) for a in args)))


def record(levels, cells, gap):
    return {"levels": levels, "cells": {str(k): v for k, v in cells.items()},
            "gap": {str(k): v for k, v in gap.items()}}


# Three stats, horizontal. Strip length = ceil(sum + (n - 1) * gap) + 1.
H = record([0, 1, 2, 3],
           {0: [100, 80, 60], 1: [90, 70, 50], 2: [70, 60, 40], 3: [50, 40, 30]},
           {0: 17, 1: 17, 2: 17, 3: 9})
H_LENS = [275, 245, 205, 139, 100, 51]
# Three stats, vertical: no level 2.
V = record([0, 1, 3], {0: [60, 60, 60], 1: [50, 50, 50], 3: [30, 30, 30]}, {0: 9, 1: 9, 3: 1})
V_LENS = [199, 169, 93, 62, 31]
NONE = record([0, 1, 2, 3], {0: [], 1: [], 2: [], 3: []}, {0: 17, 1: 17, 2: 17, 3: 9})
ONE = record([0, 1, 2, 3], {0: [100], 1: [90], 2: [70], 3: [50]}, {0: 17, 1: 17, 2: 17, 3: 9})


def lay(lens):
    """Layouts with the given lengths. Only the length matters to the drag functions."""
    return [{"level": 0, "drop": i, "len": v} for i, v in enumerate(lens)]


# ---------------------------------------------------------------- stripLength
equal("stripLength level 0", call("stripLength", H, 0, 0), 275)
equal("stripLength level 1", call("stripLength", H, 1, 0), 245)
equal("stripLength level 2", call("stripLength", H, 2, 0), 205)
equal("stripLength level 3", call("stripLength", H, 3, 0), 139)
equal("stripLength drops the last stat", call("stripLength", H, 3, 1), 100)
equal("stripLength keeps one stat", call("stripLength", H, 3, 2), 51)
equal("stripLength is 0 when every stat is dropped", call("stripLength", H, 3, 3), 0)
equal("stripLength is 0 for more drops than stats", call("stripLength", H, 3, 5), 0)
equal("stripLength is 0 without stats", call("stripLength", NONE, 0, 0), 0)
equal("stripLength of one stat has no separator", call("stripLength", ONE, 0, 0), 101)
fraction = record([0], {0: [10.2, 10.2]}, {0: 5.5})
equal("stripLength rounds the sum up, then adds 1", call("stripLength", fraction, 0, 0), 27)
equal("stripLength vertical", call("stripLength", V, 0, 0), 199)

# ---------------------------------------------------------------- configs
equal("configs horizontal lengths", [c["len"] for c in call("configs", H)], H_LENS)
equal("configs horizontal layouts", [(c["level"], c["drop"]) for c in call("configs", H)],
      [(0, 0), (1, 0), (2, 0), (3, 0), (3, 1), (3, 2)])
equal("configs vertical lengths", [c["len"] for c in call("configs", V)], V_LENS)
equal("configs vertical layouts", [(c["level"], c["drop"]) for c in call("configs", V)],
      [(0, 0), (1, 0), (3, 0), (3, 1), (3, 2)])
equal("configs of one stat has one layout per level", [(c["level"], c["drop"]) for c in call("configs", ONE)],
      [(0, 0), (1, 0), (2, 0), (3, 0)])
equal("configs without stats", [(c["level"], c["drop"], c["len"]) for c in call("configs", NONE)],
      [(0, 0, 0), (1, 0, 0), (2, 0, 0), (3, 0, 0)])
for n in range(1, 7):
    cells = {lv: [30 + 5 * i - 4 * lv for i in range(n)] for lv in range(4)}
    h = call("configs", record([0, 1, 2, 3], cells, {0: 17, 1: 17, 2: 17, 3: 9}))
    v = call("configs", record([0, 1, 3], {k: cells[k] for k in (0, 1, 3)}, {0: 9, 1: 9, 3: 1}))
    equal("configs count horizontal, %d stats" % n, len(h), 4 + n - 1)
    equal("configs count vertical, %d stats" % n, len(v), 3 + n - 1)
    check("configs never grow, %d stats" % n, all(h[i]["len"] >= h[i + 1]["len"] for i in range(len(h) - 1)))

# ---------------------------------------------------------------- computeFit
FIT0 = {"level": 0, "drop": 0}
equal("computeFit: no limit (0)", call("computeFit", H, 0), FIT0)
equal("computeFit: negative limit", call("computeFit", H, -5), FIT0)
equal("computeFit: nothing shown", call("computeFit", NONE, 100), FIT0)
equal("computeFit: nothing shown, no limit", call("computeFit", NONE, 0), FIT0)
equal("computeFit: limit equal to the full length", call("computeFit", H, 275), FIT0)
equal("computeFit: limit above the full length", call("computeFit", H, 5000), FIT0)
equal("computeFit: one below the full length", call("computeFit", H, 274), {"level": 1, "drop": 0})
equal("computeFit: level 1 exact", call("computeFit", H, 245), {"level": 1, "drop": 0})
equal("computeFit: level 2", call("computeFit", H, 244), {"level": 2, "drop": 0})
equal("computeFit: level 2 exact", call("computeFit", H, 205), {"level": 2, "drop": 0})
equal("computeFit: level 3", call("computeFit", H, 204), {"level": 3, "drop": 0})
equal("computeFit: level 3 exact", call("computeFit", H, 139), {"level": 3, "drop": 0})
equal("computeFit: drop 1", call("computeFit", H, 138), {"level": 3, "drop": 1})
equal("computeFit: drop 1 exact", call("computeFit", H, 100), {"level": 3, "drop": 1})
equal("computeFit: drop 2", call("computeFit", H, 99), {"level": 3, "drop": 2})
equal("computeFit: drop 2 exact", call("computeFit", H, 51), {"level": 3, "drop": 2})
equal("computeFit: nothing fits, the first stat stays", call("computeFit", H, 50), {"level": 3, "drop": 2})
equal("computeFit: tiny limit, the first stat stays", call("computeFit", H, 1), {"level": 3, "drop": 2})
equal("computeFit: one stat, tiny limit", call("computeFit", ONE, 1), {"level": 3, "drop": 0})
equal("computeFit: vertical skips level 2", call("computeFit", V, 170), {"level": 1, "drop": 0})
equal("computeFit: vertical goes from level 1 to level 3", call("computeFit", V, 168), {"level": 3, "drop": 0})
equal("computeFit: vertical drop", call("computeFit", V, 62), {"level": 3, "drop": 1})
equal("computeFit: vertical drop 2", call("computeFit", V, 61), {"level": 3, "drop": 2})

# ---------------------------------------------------------------- dragStart
HL = call("configs", H)
equal("dragStart finds the first layout", call("dragStart", HL, FIT0), 0)
equal("dragStart finds a middle layout", call("dragStart", HL, {"level": 2, "drop": 0}), 2)
equal("dragStart finds a dropped layout", call("dragStart", HL, {"level": 3, "drop": 2}), 5)
equal("dragStart uses the level and the drop", call("dragStart", HL, {"level": 3, "drop": 1}), 4)
equal("dragStart gives 0 when the fit is absent", call("dragStart", HL, {"level": 2, "drop": 1}), 0)
VL = call("configs", V)
equal("dragStart on a vertical list", call("dragStart", VL, {"level": 3, "drop": 0}), 2)

# ---------------------------------------------------------------- snapLimit
equal("snapLimit floor: 0", call("snapLimit", 0), 20)
equal("snapLimit floor: negative", call("snapLimit", -50), 20)
equal("snapLimit floor: 22", call("snapLimit", 22), 20)
equal("snapLimit keeps 20", call("snapLimit", 20), 20)
equal("snapLimit rounds up from 22.6", call("snapLimit", 22.6), 25)
equal("snapLimit rounds 23 up", call("snapLimit", 23), 25)
equal("snapLimit rounds 27 up", call("snapLimit", 27), 25)
equal("snapLimit rounds 28 up", call("snapLimit", 28), 30)
equal("snapLimit rounds down from 101", call("snapLimit", 101), 100)
equal("snapLimit rounds 102.5 up", call("snapLimit", 102.5), 105)
equal("snapLimit keeps a multiple of 5", call("snapLimit", 275), 275)
equal("snapLimit large", call("snapLimit", 1003.4), 1005)

# ---------------------------------------------------------------- dragStep: the halfway rule
# Lengths 275, 245, 205, 139, 100, 51. The halfway point from 275 to 245 is 260.
equal("dragStep: stay at the current length", call("dragStep", HL, 0, 275), 0)
equal("dragStep: a small nudge does not jump", call("dragStep", HL, 0, 270), 0)
equal("dragStep: one below the current length does not jump", call("dragStep", HL, 0, 274), 0)
equal("dragStep: just above halfway does not jump", call("dragStep", HL, 0, 261), 0)
equal("dragStep: exactly halfway jumps", call("dragStep", HL, 0, 260), 1)
equal("dragStep: past halfway jumps one step", call("dragStep", HL, 0, 255), 1)
equal("dragStep: a nudge below the new layout does not jump again", call("dragStep", HL, 1, 240), 1)
equal("dragStep: the next halfway point is 225", call("dragStep", HL, 1, 225), 2)
equal("dragStep: a fast pointer jumps several steps", call("dragStep", HL, 0, 119), 4)
equal("dragStep: the halfway point from 139 to 100 is 119.5", call("dragStep", HL, 0, 120), 3)
equal("dragStep: a pointer at 0 reaches the last layout", call("dragStep", HL, 0, 0), 5)
equal("dragStep: the last layout stays", call("dragStep", HL, 5, 0), 5)
equal("dragStep: growing is immediate, to the next layout", call("dragStep", HL, 1, 275), 0)
equal("dragStep: growing needs the layout to fit", call("dragStep", HL, 1, 274), 1)
equal("dragStep: growing jumps over layouts", call("dragStep", HL, 5, 245), 1)
equal("dragStep: growing from the last layout to the first", call("dragStep", HL, 5, 400), 0)
equal("dragStep: grow, then the halfway rule", call("dragStep", HL, 4, 250), 1)
equal("dragStep: grow to a layout, then stay", call("dragStep", HL, 4, 139), 3)
# Equal lengths: 100, 80, 80, 80, 40. The next strictly shorter layout from index 1 is index 4.
EQ = lay([100, 80, 80, 80, 40])
equal("dragStep equal lengths: from the first, halfway is 90", call("dragStep", EQ, 0, 91), 0)
equal("dragStep equal lengths: first to the layout of length 80", call("dragStep", EQ, 0, 90), 1)
equal("dragStep equal lengths: the equal layouts are skipped", call("dragStep", EQ, 1, 70), 1)
equal("dragStep equal lengths: halfway to 40 is 60", call("dragStep", EQ, 1, 60), 4)
equal("dragStep equal lengths: a pointer at 50 reaches the shortest layout", call("dragStep", EQ, 0, 50), 4)
equal("dragStep equal lengths: skip to the shorter layout", call("dragStep", EQ, 0, 20), 4)
equal("dragStep equal lengths: growing finds the first fitting layout", call("dragStep", EQ, 4, 80), 1)
equal("dragStep equal lengths: growing to the longest", call("dragStep", EQ, 3, 100), 0)
equal("dragStep: all lengths equal never moves", call("dragStep", lay([50, 50, 50]), 0, 0), 0)
equal("dragStep: one layout", call("dragStep", lay([50]), 0, 0), 0)

# ---------------------------------------------------------------- dragMax
FULL = 275
equal("dragMax: above the full length means no limit", call("dragMax", HL, 0, 300, FULL), 0)
equal("dragMax: the full length means no limit", call("dragMax", HL, 0, 275, FULL), 0)
equal("dragMax: one below the full length is saved", call("dragMax", HL, 1, 274, FULL), 274)
equal("dragMax: the first layout always means no limit", call("dragMax", HL, 0, 274, FULL), 0)
equal("dragMax: never less than the shown layout", call("dragMax", HL, 3, 120, FULL), 139)
equal("dragMax: a limit above the shown layout is kept", call("dragMax", HL, 3, 150, FULL), 150)
equal("dragMax: the first layout shown snaps to no limit", call("dragMax", HL, 0, 100, FULL), 0)
equal("dragMax: the last layout, a small limit", call("dragMax", HL, 5, 20, FULL), 51)
equal("dragMax: an index past the end uses the last layout", call("dragMax", HL, 99, 20, FULL), 51)
equal("dragMax: the shown layout can raise the limit to the full length", call("dragMax", HL, 0, 20, FULL), 0)
equal("dragMax: the layout length counts", call("dragMax", HL, 2, 205, FULL), 205)

# ---------------------------------------------------------------- the golden file
if not os.path.exists(GOLDEN):
    check("golden file exists", False, GOLDEN)
else:
    golden = json.load(open(GOLDEN, encoding="utf-8"))
    E.evaluate("""function replay(s) {
    var input = { levels: s.levels, cells: s.cells, gap: s.gap };
    var out = { strips: {}, configs: configs(input), full: stripLength(input, 0, 0), fits: [], walks: [] };
    s.levels.forEach(function (lv) {
        for (var d = 0; d <= s.n; ++d) out.strips[lv + "," + d] = stripLength(input, lv, d);
    });
    s.fits.forEach(function (f) { var r = computeFit(input, f[0]); out.fits.push([f[0], r.level, r.drop]) });
    s.walks.forEach(function (w) {
        var idx = dragStart(out.configs, computeFit(input, w.maxLength));
        var steps = [];
        w.points.forEach(function (p) {
            var limit = snapLimit(p);
            idx = dragStep(out.configs, idx, limit);
            steps.push([idx, limit, dragMax(out.configs, idx, limit, out.full)]);
        });
        out.walks.push({ begin: dragStart(out.configs, computeFit(input, w.maxLength)), steps: steps });
    });
    return out;
}""")
    check("golden file has scenarios", len(golden["scenarios"]) >= 40, str(len(golden["scenarios"])))
    counts = {"fits": 0, "steps": 0}
    for s in golden["scenarios"]:
        got = run("replay(%s)" % json.dumps(s))
        name = s["name"]
        equal("golden %s: strip lengths" % name, got["strips"], s["strips"])
        equal("golden %s: full length" % name, got["full"], s["full"])
        equal("golden %s: configs" % name, got["configs"], s["configs"])
        equal("golden %s: fit for every limit" % name, got["fits"], s["fits"])
        counts["fits"] += len(s["fits"])
        equal("golden %s: walk starts" % name, [w["begin"] for w in got["walks"]], [w["begin"] for w in s["walks"]])
        equal("golden %s: walk steps" % name, [w["steps"] for w in got["walks"]], [w["steps"] for w in s["walks"]])
        counts["steps"] += sum(len(w["steps"]) for w in s["walks"])
    # The grid must be large, or the comparison proves little.
    check("golden grid size: limits", counts["fits"] > 4000, str(counts["fits"]))
    check("golden grid size: drag steps", counts["steps"] > 5000, str(counts["steps"]))

print("%d checks passed, %d failed" % (passed, len(failures)))
sys.exit(1 if failures else 0)
