#!/usr/bin/env python3
"""Regenerates the golden data in tests/golden/ from the hand-written code of release v0.9.1:
  panel_text.json   the panel text of every stat, before the text moved into the metrics registry;
  scales.json       the alert, colour and graph-scale behaviour of every stat (statAlert, avgHot / tempHot / batLow,
                    statTextColor / statLineColor, statYFrom / statYTo) and the graph-scale peaks (freqPeak, netPeak,
                    fanPeak) after scripted sequences of values, before they moved into the registry.

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
OUT_SCALES = os.path.join(ROOT, "tests", "golden", "scales.json")

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


# ---------------------------------------------------------------- alerts, colours, scales, peaks
# The old code keeps the graph-scale peaks in properties of main.qml and updates them from three handlers:
# freqMax.onValueChanged, onFanRpmChanged and trackNetPeak(). The handlers are cut out of the old source and
# run unchanged. They read no clock: the "real time" decay of the net scale is `refreshMs` (the handler runs
# once per refresh), so a sequence of steps with an explicit refreshMs is fully deterministic.
TEMP_EXTRA = ["undefined", "null", '""', "NaN", '"abc"', '"80"', "0", "-5", "Infinity"]
BAT_PERCENTS = ["undefined", "null", "NaN", '"abc"', "0", "14", "14.9", "15", "15.1", "16", "100", '"14"', "-1"]
WARNS = [30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100, 105, 110, 115, 120, 29.5, 89.5, 0, 200]
PEAK_VALUES = ["undefined", "null", '""', "NaN", '"abc"', "0", "-5", "800", "1000", "1000.5", "2999", "3000", "3001", "4500",
               "9900", "99999", "100000", "100001", "250000", "1e6", "5e6", "999e6", "1e9", "1e12", '"2e6"', "Infinity"]
REFRESH = [250, 500, 1000, 2000, 5000]


def scales_engine(qml):
    """The old alert, colour, scale and peak code of main.qml in a QJSEngine, with the sensors stubbed."""
    props = {}
    for m in re.finditer(r'readonly property \w+ (avgHot|tempHot|batLow|tempYMin|tempYMax): (.+)', qml):
        props[m.group(1)] = re.sub(r'\s*//.*$', '', m.group(2))
    assert sorted(props) == ["avgHot", "batLow", "tempHot", "tempYMax", "tempYMin"], props
    init = dict(re.findall(r'property real (freqPeak|netPeak|fanPeak): (\d+)', qml))
    assert sorted(init) == ["fanPeak", "freqPeak", "netPeak"], init
    freq = re.search(r'onValueChanged: (if \(root\.isNum\(value\) && value > root\.freqPeak\) root\.freqPeak = value)', qml).group(1)
    fan = re.search(r'onFanRpmChanged: (.+)', qml).group(1)
    code = "\n".join([
        between(qml, "    function isNum(v) {", "    // Each temperature is highlighted"),
        between(qml, "    function trackNetPeak() {", "    // ---- battery ----"),
        between(qml, "    function statAlert(id)", "    function statHistory(id)"),
        between(qml, "    function statYFrom(id)", "    // The value of a stat and a worst-case sample"),
    ])
    getters = "\n".join('Object.defineProperty(this, "%s", { get: function () { return %s }, configurable: true })' % (k, v)
                        for k, v in props.items())
    e = QJSEngine()
    r = e.evaluate("""var root = this;
var Kirigami = { Theme: { negativeTextColor: "NEG", textColor: "TEXT", highlightColor: "HIGHLIGHT" } };
var tempAvg = {}, tempMax = {}, netDown = {}, netUp = {}, batPercent, batState = 0, fanRpm;
var warnTempC = 80, barChart = false, refreshMs = 1000, gpNet = false, gdNet = false;
var freqPeak = %s, netPeak = %s, fanPeak = %s;
%s
%s
function freqStep(value) { %s }
function fanStep() { %s }
""" % (init["freqPeak"], init["netPeak"], init["fanPeak"], getters, code, freq, fan))
    if r.isError():
        raise SystemExit("JS error: %s" % r.toString())
    return e


def sequences():
    """Scripted inputs: random but seeded, stored in the golden file, plus a few hand-made ones."""
    import random
    rnd = random.Random(20260101)
    pick = lambda: rnd.choice(PEAK_VALUES)
    seq = {}
    # (down, up, refreshMs) per step
    seq["net"] = {
        "random": [[pick(), pick(), 1000] for _ in range(80)],
        "random mixed refresh": [[pick(), pick(), rnd.choice(REFRESH)] for _ in range(80)],
        "spike then decay": [["0", "0", 1000], ["5e6", "1e6", 1000]] + [["0", "0", 1000]] * 150,
        "spike then decay 250 ms": [["8e6", "0", 250]] + [["0", "0", 250]] * 700,
        "growth": [[str(int(1e5 * 1.3 ** i)), str(int(5e4 * 1.1 ** i)), 1000] for i in range(40)],
        "up larger": [["1e5", "4e5", 1000], ["3e5", "1e5", 1000], ["undefined", "7e5", 1000], ["7e5", "undefined", 1000]],
        "sum vs max": [["6e5", "6e5", 2000], ["0", "0", 2000], ["0", "0", 2000], ["9e5", "0", 500], ["1e5", "9e5", 500]],
        "never numeric": [["undefined", "undefined", 1000], ['""', "NaN", 1000], ["null", '"abc"', 1000]],
        "floor": [["10", "10", 1000]] * 5 + [["99999", "1", 1000], ["50000", "50000", 1000], ["100000", "0", 1000]],
    }
    seq["freq"] = {
        "random": [pick() for _ in range(80)],
        "growth": ["800", "1000", "1000.5", "2500", "2400", "4500", "4499", "9900", "9901"],
        "never numeric": ["undefined", '""', "NaN", "null", '"abc"', "Infinity"],
        "below floor": ["0", "500", "999", "1000", "-5"],
    }
    seq["fan"] = {
        "random": [pick() for _ in range(80)],
        "growth": ["0", "1200", "2999", "3000", "3001", "5200", "5199", "9999"],
        "never numeric": ["undefined", '""', "NaN", "null", '"abc"', "Infinity"],
    }
    return seq


def write_scales(qml):
    e = scales_engine(qml)
    out = {"source": "package/contents/ui/main.qml at %s" % REV,
           "about": "statAlert/avgHot/tempHot/batLow/colours, statYFrom/statYTo and the peak sequences of the old code"}

    def ev(expr):
        return js(e, expr)

    def reset(**kw):
        e.evaluate("tempAvg.value = undefined; tempMax.value = undefined; batPercent = undefined; batState = 0; "
                   "barChart = false; refreshMs = 1000; gpNet = false; gdNet = false; netDown.value = undefined; "
                   "netUp.value = undefined; fanRpm = undefined; freqPeak = 1000; netPeak = 100000; fanPeak = 3000; warnTempC = 80")
        for k, v in kw.items():
            e.evaluate("%s = %s" % (k, v))

    # 1. Temperature: warn x value. avgHot is read from tempAvg, tempHot from tempMax; both are fed the same value
    # here (they are independent). Rows: [warn, value, avgHot, tempHot, alerting stats, temp text colour, temp line colour].
    rows = []
    for w in WARNS:
        vals = [str(w - 1), str(w), str(w + 1), str(w - 0.5), str(w + 0.5), str(w + 0.01), str(w - 0.01)] + TEMP_EXTRA
        for v in vals:
            reset(warnTempC=w)
            e.evaluate("tempAvg.value = %s; tempMax.value = %s" % (v, v))
            rows.append([w, v, ev("avgHot"), ev("tempHot"),
                         [s for s in STATS if ev('statAlert("%s")' % s)],
                         ev('statTextColor("temp")'), ev('statLineColor("temp")')])
    out["temp"] = rows

    # 2. Battery: percent x state. Rows: [percent, state, batLow, alerting stats, bat text colour, bat line colour].
    rows = []
    for p in BAT_PERCENTS:
        for s in STATES:
            reset()
            e.evaluate("batPercent = %s; batState = %d" % (p, s))
            rows.append([p, s, ev("batLow"), [x for x in STATS if ev('statAlert("%s")' % x)],
                         ev('statTextColor("bat")'), ev('statLineColor("bat")')])
    out["bat"] = rows

    # 3. Both at once, and colours of every stat. Rows: [temp value, percent, state, per stat [alert, text, line]].
    rows = []
    for t in ("undefined", "70", "80", "95"):
        for p, s in (("undefined", 0), ("14", -1), ("14", 1), ("15", -1), ("50", 0)):
            reset()
            e.evaluate("tempAvg.value = %s; batPercent = %s; batState = %d" % (t, p, s))
            rows.append([t, p, s, {x: [ev('statAlert("%s")' % x), ev('statTextColor("%s")' % x), ev('statLineColor("%s")' % x)]
                                   for x in STATS}])
    out["all"] = rows

    # 4. Scale range of every stat. Rows: [warn, {stat: [from, to]}] with every peak at its start value, then
    # [peak state (freq, net, fan), {stat: [from, to]}] at warn 80.
    rows = []
    for w in WARNS + [89, 90, 91, -20, 1e3]:
        reset(warnTempC=w)
        rows.append([w, {x: [ev('statYFrom("%s")' % x), ev('statYTo("%s")' % x)] for x in STATS}])
    out["range by warn"] = rows
    rows = []
    for st in [(1000, 100000, 3000), (2500.5, 1234567.25, 5200), (9900, 4.5e9, 9999), (1e12, 1e-3, 0.5)]:
        reset()
        e.evaluate("freqPeak = %r; netPeak = %r; fanPeak = %r" % st)
        rows.append([list(st), {x: [ev('statYFrom("%s")' % x), ev('statYTo("%s")' % x)] for x in STATS}])
    out["range by peak"] = rows

    # 5. Peak sequences. Each run records the peak after every step.
    seq = sequences()
    out["sequences"] = seq
    res = {"net": {}, "freq": {}, "fan": {}}
    for bar in (False, True):
        for gp, gd in ((True, False), (False, True), (True, True), (False, False)):
            for name, steps in seq["net"].items():
                reset(barChart=str(bar).lower(), gpNet=str(gp).lower(), gdNet=str(gd).lower())
                peaks = []
                for d, u, ms in steps:
                    e.evaluate("refreshMs = %d; netDown.value = %s; netUp.value = %s; trackNetPeak()" % (ms, d, u))
                    peaks.append(ev("netPeak"))
                res["net"]["%s|gp=%d gd=%d|%s" % ("bar" if bar else "line", gp, gd, name)] = peaks
    for name, steps in seq["freq"].items():
        reset()
        peaks = []
        for v in steps:
            e.evaluate("freqStep(%s)" % v)
            peaks.append(ev("freqPeak"))
        res["freq"][name] = peaks
    for name, steps in seq["fan"].items():
        reset()
        peaks = []
        for v in steps:
            e.evaluate("fanRpm = %s; fanStep()" % v)
            peaks.append(ev("fanPeak"))
        res["fan"][name] = peaks
    out["peaks"] = res

    with open(OUT_SCALES, "w", encoding="utf-8") as fh:
        fh.write("{\n")
        items = list(out.items())
        for n, (k, v) in enumerate(items):
            fh.write(" %s: %s%s\n" % (json.dumps(k), json.dumps(v, ensure_ascii=False, separators=(",", ":")), "," if n < len(items) - 1 else ""))
        fh.write("}\n")
    print("wrote %s (%d bytes) from %s" % (OUT_SCALES, os.path.getsize(OUT_SCALES), REV))


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
    write_scales(qml)


main()
