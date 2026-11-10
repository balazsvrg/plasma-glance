#!/usr/bin/env python3
"""Regenerates tests/golden/panel_text.json: the panel text of every stat as the hand-written code in
main.qml of release v0.9.1 produced it, before the text moved into the metrics registry.

    python3 tests/golden/generate.py [git-revision]        (default: v0.9.1)

The script reads package/contents/ui/main.qml as it was at the given revision, cuts out the formatting and
panel-text functions, runs them in Qt's JavaScript engine (PySide6's QJSEngine, the engine QML uses) with
stand-ins for the sensors, and records the output for a grid of inputs: every stat x every value of the
grid x full / compact x horizontal / vertical x Celsius / Fahrenheit x bytes / bits. It also records the
worst-case reserve strings (the m* TextMetrics) and the worst-case vertical lines.

The golden file is the specification the registry is checked against (tests/metrics_test.py). Regenerate it
only on purpose, when the panel text is meant to change, and only from a revision whose main.qml still has
the functions above (after the registry took over, an old revision is the only source). Review the diff of
the JSON like any other change: every changed string is a user-visible change.
"""
import json
import os
import re
import subprocess
import sys

from PySide6.QtCore import QCoreApplication
from PySide6.QtQml import QJSEngine

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REV = sys.argv[1] if len(sys.argv) > 1 else "v0.9.1"
OUT = os.path.join(ROOT, "tests", "golden", "panel_text.json")

# The boundary values every formatter is exercised with (JavaScript expressions).
VALUES = ["undefined", "null", '""', "NaN", "Infinity", '"abc"', "0", "0.4", "0.5", "1", "9.9", "9.94", "9.95", "9.96",
          "49.5", "50.5", "99.5", "100", "100.4", "212", "36.6", "-5", "800", "999", "999.4", "999.49", "999.5", "999.6", "1000",
          "9949", "9950", "9999", "99499", "99500", "999499", "999500", "1e6", "1.5e9", "999e6", "999.9e6", "1e12", "1073741824",
          "8589934592", "1234.56", '"42"', "0.04", "-0.5"]
STATES = [-1, 0, 1]                              # battery: discharging, other, charging
MODES = [(f, b) for f in (False, True) for b in (False, True)]   # (useFahrenheit, netBits)
STATS = ["cpu", "ram", "temp", "freq", "net", "bat", "fan"]
FORMATS = {"pct": "pct(%s)", "gib": "gib(%s)", "wh": "wh(%s)", "ghz": "ghzNumber(%s)", "freq": "freq(%s)",
           "freqShort": "freqShort(%s)", "bytes": "bytesText(%s)", "rpm": "rpmNumber(%s)", "temp": "temp(%s)",
           "tempShort": "tempShort(%s)", "rate": "rate(%s)", "rateShort": "rateShort(%s)"}


def source(rev):
    return subprocess.check_output(["git", "-C", ROOT, "show", "%s:package/contents/ui/main.qml" % rev], text=True)


def between(text, start, end):
    i = text.index(start)
    return text[i:text.index(end, i)]


def build_engine(qml):
    code = "\n".join([
        between(qml, "    function isNum(v) {", "    // Each temperature is highlighted"),
        between(qml, "    function tempShort(v)", "    // Per-stat colours"),
        between(qml, "    // The value of a stat and a worst-case sample", "    // Space one stat takes at a given step"),
    ])
    e = QJSEngine()
    r = e.evaluate("var useF = false, netBits = false, cpuUsage = {}, memPercent = {}, tempAvg = {}, freqAvg = {}, "
                   "netDown = {}, netUp = {}, batPercent, batState = 0, fanRpm, batterySummary = {};\n" + code)
    if r.isError():
        raise SystemExit("JS error: %s" % r.toString())
    return e


def js(e, expr):
    r = e.evaluate("JSON.stringify(" + expr + ")")
    if r.isError():
        raise SystemExit("JS error in %s: %s" % (expr, r.toString()))
    return json.loads(r.toString())


def group(by_mode):
    """{(useF, bits): value} -> [[["01", ...], value], ...] with equal values merged."""
    groups = []
    for (f, b), v in by_mode.items():
        key = "%d%d" % (f, b)
        for g in groups:
            if g[1] == v:
                g[0].append(key)
                break
        else:
            groups.append([[key], v])
    return groups


def main():
    qml = source(REV)
    app = QCoreApplication([])
    e = build_engine(qml)
    out = {"source": "package/contents/ui/main.qml at %s" % REV, "values": VALUES,
           "modes": "two digits: useFahrenheit, netBits", "formats": {}, "text": {}, "reserve": {}, "verticalSample": {},
           "popupBattery": {}}

    def setmode(f, b):
        e.evaluate("useF = %s; netBits = %s" % (str(f).lower(), str(b).lower()))

    # Formatters.
    for name, expr in FORMATS.items():
        per = {}
        for f, b in MODES:
            setmode(f, b)
            per[(f, b)] = [js(e, expr % v) for v in VALUES]
        out["formats"][name] = group(per)

    # Panel text. Inputs per stat: single-value stats take the grid; battery takes grid x state; net takes
    # (down, up) pairs: (v, v) and (v, the value 13 places later).
    def inputs(stat):
        if stat == "bat":
            return [(v, s) for v in VALUES for s in STATES]
        if stat == "net":
            n = len(VALUES)
            return [(VALUES[i], VALUES[i]) for i in range(n)] + [(VALUES[i], VALUES[(i + 13) % n]) for i in range(n)]
        return [(v,) for v in VALUES]

    def feed(stat, inp):
        if stat == "net":
            return "netDown.value = %s; netUp.value = %s" % inp
        if stat == "bat":
            return "batPercent = %s; batState = %d" % inp
        target = {"cpu": "cpuUsage.value", "ram": "memPercent.value", "temp": "tempAvg.value",
                  "freq": "freqAvg.value", "fan": "fanRpm"}[stat]
        return "%s = %s" % (target, inp[0])

    for stat in STATS:
        ins = inputs(stat)
        out["text"][stat] = {"inputs": [list(map(str, i)) for i in ins]}
        for orient, vert in (("horizontal", False), ("vertical", True)):
            for kind, compact in (("full", False), ("compact", True)):
                per = {}
                for f, b in MODES:
                    setmode(f, b)
                    res = []
                    for inp in ins:
                        e.evaluate(feed(stat, inp))
                        res.append(js(e, 'statText("%s", %s, %s)' % (stat, str(compact).lower(), str(vert).lower())))
                    per[(f, b)] = res
                out["text"][stat]["%s %s" % (orient, kind)] = group(per)

    # Worst-case reserve strings: the m* TextMetrics. A literal, or `root.useF ? "F" : "C"`.
    for m in re.finditer(r'TextMetrics \{ id: (m(\w+?))(C?);\s*font: [^;]+;\s*text: (.+?) \}', qml):
        mid, name, compact, text = m.group(1), m.group(2), m.group(3) == "C", m.group(4)
        if name in ("Line", "PopupLabel"):
            continue
        stat = {"Cpu": "cpu", "Ram": "ram", "Temp": "temp", "Freq": "freq", "Net": "net", "Bat": "bat", "Fan": "fan"}[name]
        tern = re.match(r'root\.useF \? "(.*?)" : "(.*?)"$', text)
        lit = re.match(r'"(.*)"$', text)
        by = {"F": tern.group(1), "C": tern.group(2)} if tern else {"F": lit.group(1), "C": lit.group(1)}
        out["reserve"].setdefault(stat, {})["compact" if compact else "full"] = by
    assert sorted(out["reserve"]) == sorted(STATS), out["reserve"].keys()

    # Worst-case vertical lines (what verticalWidth measures).
    for stat in STATS:
        for kind, compact in (("full", False), ("compact", True)):
            per = {}
            for f, b in MODES:
                setmode(f, b)
                per[(f, b)] = js(e, 'verticalLines("%s", %s, true)' % (stat, str(compact).lower()))
            out["verticalSample"]["%s %s" % (stat, kind)] = group(per)

    # The popup's battery row: batText() plus the energy part, over percent x state x energy.
    setmode(False, False)
    rows = []
    for v in ["undefined", "0", "14.6", "15", "49.5", "100", '"x"']:
        for s in STATES:
            for en in ["undefined", "0", "12.34", "45.25"]:
                e.evaluate("batPercent = %s; batState = %d" % (v, s))
                res = js(e, 'batText() + (isNum(%s) ? "  (" + wh(%s) + ")" : "")' % (en, en))
                rows.append([v, s, en, res])
    out["popupBattery"] = rows

    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write("{\n")
        items = list(out.items())
        for n, (k, v) in enumerate(items):
            fh.write(" %s: %s%s\n" % (json.dumps(k), json.dumps(v, ensure_ascii=False, separators=(",", ":")), "," if n < len(items) - 1 else ""))
        fh.write("}\n")
    print("wrote %s (%d bytes) from %s" % (OUT, os.path.getsize(OUT), REV))


main()
