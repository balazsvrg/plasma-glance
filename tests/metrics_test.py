#!/usr/bin/env python3
"""Tests for package/contents/ui/Metrics.js, run without Plasma.

    python3 tests/metrics_test.py

Needs python3 with PySide6 (its QJSEngine is Qt's own JavaScript engine, the one QML uses). Exits non-zero
when any check fails. What it checks:
  1. the worst-case strings (the horizontal width reserve and the vertical sample lines), written out here;
  2. how main.qml uses the registry: the per-stat panel code is gone, the keys main.qml feeds the templates
     match the ones the templates read, the formatters read only the settings main.qml passes in;
  3. literal boundary cases of the formatters, render(), alerts, scales and sensor gating;
  4. the structure: unique ids, labels, sensor ids, and every settings key of main.xml accounted for;
  5. the registry against tests/golden/panel_text.json: the panel text the hand-written code of release
     v0.9.1 produced for every stat, kind, orientation and unit mode over a grid of values (regenerate it
     only on purpose, see tests/golden/generate.py);
  6. the registry against tests/golden/scales.json: the alerts, colours, graph scales and the peak sequences
     (freq, net, fan) of the same code.
"""
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

from PySide6.QtCore import QCoreApplication
from PySide6.QtQml import QJSEngine

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UI = os.path.join(ROOT, "package", "contents", "ui")
MAIN_QML = open(os.path.join(UI, "main.qml"), encoding="utf-8").read()
METRICS_JS = open(os.path.join(UI, "Metrics.js"), encoding="utf-8").read()
MAIN_XML = os.path.join(ROOT, "package", "contents", "config", "main.xml")
METRICS_PAGE = open(os.path.join(UI, "configMetrics.qml"), encoding="utf-8").read()
NOTICE = open(os.path.join(UI, "LengthNotice.qml"), encoding="utf-8").read()

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


def make_engine(source):
    e = QJSEngine()
    r = e.evaluate(source)
    if r.isError():
        raise SystemExit("JS error: %s" % r.toString())
    return e


def run(engine, expr):
    r = engine.evaluate("JSON.stringify(" + expr + ")")
    if r.isError():
        raise SystemExit("JS error in %s: %s" % (expr, r.toString()))
    s = r.toString()
    return None if s == "undefined" else json.loads(s)


# `.pragma library` is a QML directive, not JavaScript: drop it for the plain engine.
M = make_engine(re.sub(r"^\.pragma library\s*$", "", METRICS_JS, flags=re.M))


def ctx(useF=False, netBits=False, warn=80):
    return "{useF:%s,netBits:%s,warnTempC:%s}" % (str(useF).lower(), str(netBits).lower(), warn)


def vals_js(d):
    return json.dumps(d)


def panel_text(mid, compact, vertical, vals, **kw):
    return run(M, "panelText(byId(%s),%s,%s,%s,%s)" % (
        json.dumps(mid), str(compact).lower(), str(vertical).lower(), vals_js(vals), ctx(**kw)))


def sample(mid, vertical, **kw):
    return run(M, "sampleVals(byId(%s),%s,%s)" % (json.dumps(mid), str(vertical).lower(), ctx(**kw)))


def vlines(mid, compact, vals, **kw):
    return run(M, "verticalLines(byId(%s),%s,%s,%s)" % (json.dumps(mid), str(compact).lower(), vals_js(vals), ctx(**kw)))


# ---------------------------------------------------------------- 1. worst-case strings
print("1. worst-case strings (horizontal reserve and vertical lines)")
# Written out here as a readable second statement of the golden data below. The worst-case text of a stat is
# what the strip reserves its width for, so a change here is a change of the panel's width.
RESERVE = {
    ("cpu", False, False): "CPU 100%", ("cpu", True, False): "C 100%",
    ("ram", False, False): "RAM 100%", ("ram", True, False): "R 100%",
    ("temp", False, False): "100°C", ("temp", False, True): "212°F", ("temp", True, False): "100°", ("temp", True, True): "212°",
    ("freq", False, False): "9.9 GHz", ("freq", True, False): "9.9G",
    ("net", False, False): "↓999 MB/s ↑999 MB/s", ("net", True, False): "↓999M ↑999M",
    ("bat", False, False): "BAT 100% ↓", ("bat", True, False): "B 100%↓",
    ("fan", False, False): "9999 RPM", ("fan", True, False): "9999",
}
for (stat, compact, useF), want in sorted(RESERVE.items()):
    got = run(M, "reserveText(byId(%s),%s,%s)" % (json.dumps(stat), str(compact).lower(), ctx(useF=useF)))
    equal("%s%s horizontal reserve%s" % (stat, " compact" if compact else " full", " F" if useF else ""), got, want)
# The net reserve is the bytes text in both unit modes (a quirk kept on purpose: the width is the same in bits mode).
equal("net full reserve, bits mode keeps the bytes text", run(M, "reserveText(byId('net'),false,%s)" % ctx(netBits=True)),
      "\u2193999 MB/s \u2191999 MB/s")

# Vertical lines: the worst-case lines (the widest line sets the width of a stat on a vertical panel).
VERTICAL = {
    ("cpu", False, False): ["CPU", "100%"],
    ("ram", False, False): ["RAM", "100%"],
    ("temp", False, False): ["Temp", "100°C"], ("temp", False, True): ["Temp", "212°F"],
    ("temp", True, False): ["Temp", "100°"],   ("temp", True, True): ["Temp", "212°"],
    ("freq", False, False): ["Freq", "9.9 GHz"], ("freq", True, False): ["Freq", "9.9G"],
    ("net", False, False): ["Net", "↓999M", "↑999M"],
    ("bat", False, False): ["Bat", "100% ↑"], ("bat", True, False): ["Bat", "100%↑"],
    ("fan", False, False): ["Fan", "9999"],
}
for (stat, compact, useF), want in sorted(VERTICAL.items()):
    got = vlines(stat, compact, sample(stat, True, useF=useF), useF=useF)
    equal("%s vertical%s%s" % (stat, " compact" if compact else "", " F" if useF else ""), got, want)
equal("net vertical, bits mode", vlines("net", False, sample("net", True, netBits=True), netBits=True),
      ["Net", "↓999M", "↑999M"])
# Stats without a verticalCompact must ignore compact.
for stat in ("cpu", "ram", "net", "fan"):
    equal("%s vertical ignores compact" % stat, vlines(stat, True, sample(stat, True)), vlines(stat, False, sample(stat, True)))
equal("only temp, freq and bat have verticalCompact",
      run(M, "METRICS.filter(function(m){return !!m.panel.verticalCompact}).map(function(m){return m.id})"),
      ["temp", "freq", "bat"])
equal("only the fan has a decoration", run(M, "METRICS.filter(function(m){return !!m.panel.decoration}).map(function(m){return m.id + ':' + m.panel.decoration})"),
      ["fan:fanIcon"])
check("the vertical battery sample is the charging state", sample("bat", True)["state"] == 1)
check("the net sample is 999e6 (bits: /8)", sample("net", True)["down"] == 999e6 and sample("net", True, netBits=True)["down"] == 999e6 / 8)

# ---------------------------------------------------------------- 2. how main.qml uses the registry
print("2. main.qml uses the registry")
check("main.qml imports Metrics.js", re.search(r'^import "Metrics\.js" as M$', MAIN_QML, re.M) is not None)
check("main.qml imports Layout.js", re.search(r'^import "Layout\.js" as L$', MAIN_QML, re.M) is not None)
for gone in ("function levelList", "Math.ceil(total", "(cur + cfgs[j].len) / 2"):
    check("main.qml no longer has `%s` (the length arithmetic is in Layout.js)" % gone, gone not in MAIN_QML)
# The per-stat panel code moved into the registry; none of it may come back (a second copy would drift).
for gone in ("function valueText", "function netLines", "function verticalCaption", "function statValue", "function netText",
             "function rateParts", "function batValue", "function arrowFor", "function tempShort", "function freqShort",
             "function rpmNumber", "function tempNumber", "function rateShort", "function batText",
             "TextMetrics { id: mCpu", "TextMetrics { id: mFan", "TextMetrics { id: mNet", "TextMetrics { id: mTemp",
             "property bool avgHot", "property bool batLow", "property real freqPeak", "property real netPeak",
             "property real fanPeak", "function trackNetPeak", "tempYMin", "tempYMax", "History { id: cpuHistory",
             "History { id: netDownHistory", "History { id: batHistory", "property var cpuHist", "property var netUpHist",
             "var all = [cpuHistory"):
    check("main.qml no longer has `%s`" % gone, gone not in MAIN_QML)
check("statText delegates to M.panelText", "M.panelText(m, compact, vert, statVals(id), textCtx)" in MAIN_QML)
check("verticalLines delegates to M.verticalLines", "M.verticalLines(m, compact," in MAIN_QML)
check("the horizontal reserve is rendered by M.reserveText", "text: M.reserveText(M.byId(statId), compact, root.textCtx)" in MAIN_QML)
check("the reserve items come from the registry's entries", "M.METRICS.length" in MAIN_QML and "model: root.reserveKinds" in MAIN_QML)
check("statCompact asks the registry which stats have a shorter vertical form", "m.panel.verticalCompact" in MAIN_QML)
check("the icon width comes from the registry's decoration", 'm.panel.decoration === "fanIcon"' in MAIN_QML)
check("statAlert delegates to M.alertOf", "M.alertOf(m, statVals(id), limitCtx)" in MAIN_QML)
check("a popup row's alert is the registry's (no hand-written tempHot)", "tempHot" not in MAIN_QML and "row.alert(popupVals(id), limitCtx)" in MAIN_QML)
check("limitCtx carries exactly the warning temperature", re.search(r'limitCtx: \(\{ warnTempC: warnTempC \}\)', MAIN_QML) is not None)
check("statYTo asks the registry for the scale end", "M.scaleEnd(m, limitCtx, M.followsData(m) ? peakOf(id) : 0)" in MAIN_QML)
check("statYFrom asks the registry", "M.scaleFrom(m)" in MAIN_QML)
check("the peak step is the registry's", "M.stepPeak(M.byId(id), prev, statVals(id), ctx, refreshMs)" in MAIN_QML)
# A peak step has two kinds of trigger: the sensor the registry names as the scale's `trigger` (one generic
# handler in the sensor delegate) and the fan speed, which is not a sensor.
equal("literal peak triggers", sorted(re.findall(r'stepPeak\("(\w+)"\)', MAIN_QML)), ["fan"])
check("fan steps from the fan speed", 'onFanRpmChanged: root.stepPeak("fan")' in MAIN_QML)
check("the sensor delegate steps the peak of the stat whose scale names it",
      "M.byId(modelData.id).scale.trigger === modelData.name" in MAIN_QML and "onValueChanged: if (isTrigger) root.stepPeak(modelData.id)" in MAIN_QML)
equal("triggers of the following scales", run(M, "METRICS.filter(followsData).map(function(m){return [m.id, m.scale.trigger]})"),
      [["freq", "max"], ["net", "down"], ["fan", None]])
for sid in ("freq", "net"):
    equal("the trigger of %s is one of its sensors" % sid, run(M, "byId('%s').scale.trigger in byId('%s').sensors" % (sid, sid)), True)
equal("a scale without a sensor has no trigger", [run(M, "byId('%s').scale.trigger" % x) for x in ("cpu", "ram", "temp", "bat", "fan")], [None] * 5)
# statVals() hands a following scale the keys the registry says it watches (plain sensors: their names; fan: its own case).
for sid in run(M, "METRICS.filter(followsData).map(function(m){return m.id})"):
    keys = run(M, "byId(%s).scale.observe.keys" % json.dumps(sid))
    sensors = run(M, "Object.keys(byId(%s).sensors)" % json.dumps(sid))
    check("the scale of %s watches keys that statVals supplies" % sid,
          all(k in sensors for k in keys) if sensors else keys == ["value"])
# One History per registry series, created from the registry (not one hand-written item per stat).
check("the histories come from the registry's series", "model: root.historyKinds" in MAIN_QML and "M.METRICS[i].series[j]" in MAIN_QML)
check("a history is wanted by the stat's graph and shown flags", "wanted: root.historyWanted(modelData.id)" in MAIN_QML)
check("no hand-written historySensors map is left", "historySensors" not in MAIN_QML)
check("a plain-sensor series is the sensor of the same name", "return sensorOf(id, series)" in MAIN_QML)
check("battery and fan feed their history through small QtObjects",
      'if (id === "bat") return batSensor' in MAIN_QML and 'if (id === "fan") return fanSensor' in MAIN_QML)
for mid in run(M, "METRICS.filter(function(m){return Object.keys(m.sensors).length}).map(function(m){return m.id})"):
    series = run(M, "byId(%s).series" % json.dumps(mid))
    sensors = run(M, "Object.keys(byId(%s).sensors)" % json.dumps(mid))
    check("every series of %s names one of its sensors" % mid, all(x in sensors for x in series))
equal("the stats without plain sensors are battery and fan", run(M, "METRICS.filter(function(m){return !Object.keys(m.sensors).length}).map(function(m){return m.id})"), ["bat", "fan"])
for gone in ("readonly property bool gpCpu", "readonly property bool gdFan", "readonly property bool gpNet"):
    check("main.qml no longer has `%s` (the graph flags are read through the registry's keys)" % gone, gone not in MAIN_QML)
check("statGraph reads the registry's gp key", "Plasmoid.configuration[m.keys.gp]" in MAIN_QML)
check("statPopupGraph reads the registry's gd key", "Plasmoid.configuration[m.keys.gd]" in MAIN_QML)
check("statPopupOn reads the registry's popup key", "Plasmoid.configuration[m.keys.popup]" in MAIN_QML)
check("statHistory and statHistory2 take the first and second series", "historyOf(id, m.series[0])" in MAIN_QML and "historyOf(id, m.series[1])" in MAIN_QML)
# The settings the formatters read must be the ones main.qml puts into the context: a formatter that starts
# reading another setting would silently get undefined.
fmt_src = re.search(r'var FORMATS = \{(.*?)\n\}\n', METRICS_JS, re.S).group(1) + re.search(r'function rateParts.*?\n\}\nfunction tempNumber.*?\n\}', METRICS_JS, re.S).group(0)
ctx_keys = sorted(set(re.findall(r'ctx(?: && ctx)?\.(\w+)', fmt_src)))
equal("the formatters read only these settings", ctx_keys, ["netBits", "useF"])
equal("main.qml puts exactly those into textCtx", sorted(re.findall(r'(\w+): \1', re.search(r'textCtx: \(\{(.*?)\}\)', MAIN_QML).group(1))), ctx_keys)
# The values main.qml feeds each stat's templates: every key a template reads must be supplied. A plain-sensor stat
# gets every sensor of its entry under the sensor's name (sensorVals); battery and fan have their own cases.
sv_src = re.search(r'function statVals\(id\) \{(.*?)\n    \}', MAIN_QML, re.S).group(1)
supplied = {sid: sorted(re.findall(r'(\w+):', body)) for sid, body in re.findall(r'case "(\w+)":\s+return \{(.*?)\}', sv_src)}
equal("statVals has its own case for exactly battery and fan", sorted(supplied), ["bat", "fan"])
check("statVals falls back to the stat's sensors", "return sensorVals(id)" in sv_src)
check("sensorVals names each value after its registry sensor",
      "M.panelSensorNames(M.byId(id))" in MAIN_QML and "vals[names[i]] = sensorValue(id, names[i])" in MAIN_QML)
for stat in run(M, "DEFAULT_ORDER"):
    used = run(M, "(function(){var p=byId(%s).panel, t=[p.full,p.compact].concat(p.vertical,p.verticalCompact||[]), k={}; "
                  "t.forEach(function(x){(x.match(/\\{(\\w+)/g)||[]).forEach(function(y){k[y.slice(1)]=1})}); return Object.keys(k).sort()})()" % json.dumps(stat))
    sensors = run(M, "Object.keys(byId(%s).sensors).sort()" % json.dumps(stat))
    if stat in supplied:
        equal("statVals of %s supplies the keys its templates read" % stat, supplied[stat], used)
    else:
        check("the sensors of %s supply the keys its templates read (%s)" % (stat, used), all(k in sensors for k in used))
    equal("the sample of %s has the same keys" % stat, sorted(run(M, "Object.keys(byId(%s).panel.sample)" % json.dumps(stat))), used)
# The wrappers the popup keeps call formatters that exist.
for f in set(re.findall(r'M\.FORMATS\.(\w+)', MAIN_QML)):
    check("main.qml's M.FORMATS.%s exists" % f, run(M, "typeof FORMATS.%s" % f) == "function")

# ---------------------------------------------------------------- 3. literal boundaries
print("3. boundary cases")
def fmt(name, v, **kw):
    return run(M, "FORMATS.%s(%s,%s)" % (name, v, ctx(**kw)))
B = [
    ("rate 999 B", fmt("rate", 999), "999 B/s"), ("rate 999.4 B", fmt("rate", 999.4), "999 B/s"),
    ("rate rolls over at 999.5", fmt("rate", 999.5), "1.0 KB/s"),
    ("rate 9949 B", fmt("rate", 9949), "9.9 KB/s"), ("rate 9950 B (>= 9.95 drops the decimal)", fmt("rate", 9950), "10 KB/s"),
    ("rate 999.5 KB rolls to MB", fmt("rate", 999500), "1.0 MB/s"), ("rate 1.5 GB/s", fmt("rate", 1.5e9), "1.5 GB/s"),
    ("rate caps at GB", fmt("rate", 1e12), "1000 GB/s"),
    ("rate bits 125 B/s = 1.0 Kb/s", fmt("rate", 125, netBits=True), "1.0 Kb/s"),
    ("rateShort bits", fmt("rateShort", 125, netBits=True), "1.0K"), ("rateShort bytes", fmt("rateShort", 5e6), "5.0M"),
    ("rate zero", fmt("rate", 0), "0 B/s"), ("rate undefined", fmt("rate", "undefined"), "--"),
    ("freq 800 MHz", fmt("freq", 800), "0.8 GHz"), ("freq 9900", fmt("freq", 9900), "9.9 GHz"),
    ("freqShort 800", fmt("freqShort", 800), "0.8G"), ("freq missing", fmt("freq", "undefined"), "-- GHz"),
    ("freqShort missing", fmt("freqShort", "undefined"), "--G"),
    ("rpm rounds", fmt("rpm", 1234.6), "1235"), ("rpm zero", fmt("rpm", 0), "0"), ("rpm missing", fmt("rpm", "undefined"), "--"),
    ("pct rounds .5 up", fmt("pct", 49.5), "50%"), ("pct 0.4", fmt("pct", 0.4), "0%"), ("pct over 100 not clamped", fmt("pct", 100.4), "100%"),
    ("pct missing", fmt("pct", "undefined"), "--%"), ("pct NaN", fmt("pct", "NaN"), "--%"), ("pct empty string", fmt("pct", '""'), "--%"),
    ("pct text", fmt("pct", '"abc"'), "--%"), ("pct numeric string", fmt("pct", '"42"'), "42%"),
    ("temp C", fmt("temp", 36.6), "37°C"), ("temp F", fmt("temp", 36.6, useF=True), "98°F"),
    ("temp 100 C -> 212 F", fmt("temp", 100, useF=True), "212°F"), ("temp missing", fmt("temp", "undefined"), "--°C"),
    ("tempShort F", fmt("tempShort", 100, useF=True), "212°"), ("tempShort missing", fmt("tempShort", "null"), "--°"),
    ("gib", fmt("gib", 1073741824), "1.0 GiB"), ("gib missing", fmt("gib", "undefined"), "-- GiB"),
    ("wh", fmt("wh", 45.25), "45.3 Wh"), ("whParen missing is empty", fmt("whParen", "undefined"), ""),
    ("whParen", fmt("whParen", 12.34), "  (12.3 Wh)"),
    ("bytes KB", fmt("bytes", 1499), "1 KB"), ("bytes MB", fmt("bytes", 2.5e6), "2.5 MB"), ("bytes GB", fmt("bytes", 1e9), "1.0 GB"),
    ("arrow up/down/none", [fmt("arrow", 1), fmt("arrow", -1), fmt("arrow", 0)], ["↑", "↓", ""]),
]
for name, got, want in B:
    equal(name, got, want)

equal("render: missing key is --", run(M, "render('a {x:pct} b {y}',{x:50},{})"), "a 50% b --")
equal("render: plain key and literal text", run(M, "render('[{k}]',{k:7},{})"), "[7]")
equal("render: explicit undefined value goes through the formatter", run(M, "render('{v:pct}',{v:undefined},{})"), "--%")
r = M.evaluate("try { render('{v:nosuch}',{v:1},{}); 'no error' } catch (e) { 'threw' }").toString()
equal("render: unknown format throws", r, "threw")
equal("render: no vals at all", run(M, "render('{v:pct}',null,{})"), "--")
equal("render: the same template with different values (parsed once)", run(M, "[1,2,3].map(function(v){return render('n={v} {w:pct}',{v:v,w:v*10},{})})"),
      ["n=1 10%", "n=2 20%", "n=3 30%"])
equal("render: an unknown format throws every time", [M.evaluate("try { render('{v:nosuch}',{v:1},{}); 'no error' } catch (e) { 'threw' }").toString() for _ in range(2)],
      ["threw", "threw"])
equal("render: adjacent holes and edges of the template", run(M, "render('{a}{b:pct}{a}',{a:'x',b:5},{})"), "x5%x")

equal("temp alert below / at warn", [run(M, "byId('temp').alert({value:%s},%s)" % (v, ctx())) for v in (79.9, 80, 90)], [False, True, True])
equal("temp alert needs a number", [run(M, "byId('temp').alert({value:%s},%s)" % (v, ctx())) for v in ("undefined", "null", "NaN")], [False] * 3)
equal("temp alert follows warnTemp", run(M, "byId('temp').alert({value:85},%s)" % ctx(warn=90)), False)
equal("battery alert below 15 and not charging",
      [run(M, "byId('bat').alert({percent:%s,state:%d})" % (p, s)) for p, s in ((14, -1), (14, 0), (14, 1), (15, -1), (0, -1))],
      [True, True, False, False, True])
equal("battery alert needs a number", run(M, "byId('bat').alert({percent:undefined,state:-1})"), False)
equal("temp scale", [run(M, "scaleTo(byId('temp'),%s)" % ctx(warn=w)) for w in (60, 90, 95)], [100, 100, 105])
equal("temp scale starts at 20", run(M, "byId('temp').scale.from"), 20)
equal("fixed scales", [run(M, "scaleTo(byId('%s'),{})" % s) for s in ("cpu", "ram", "bat")], [100, 100, 100])
peak = lambda s, prev, obs, ms: run(M, "nextPeak(byId('%s').scale,%s,%s,%d)" % (s, prev, obs, ms))
equal("net scale rises at once", peak("net", 100000, 5e6, 1000), 5e6)
equal("net scale decays 1% per second", peak("net", 200000, 0, 1000), 198000)
equal("net scale decay follows real time", round(peak("net", 200000, 0, 500), 3), round(200000 * 0.99 ** 0.5, 3))
equal("net scale never below the floor", peak("net", 100000, 0, 1000), 100000)
equal("net scale ignores a missing value", peak("net", 150000, "undefined", 1000), 148500)
equal("freq scale grows and never falls", [peak("freq", 1000, 3000, 1000), peak("freq", 3000, 1500, 1000), peak("freq", 1000, 500, 1000)], [3000, 3000, 1000])
equal("fan scale floor 3000", [peak("fan", 3000, 1200, 1000), peak("fan", 3000, 5200, 1000)], [3000, 5200])
flags = lambda **k: json.dumps(dict(dict(show=False, popup=False, expanded=False, opts={}), **k))
def active(stat, name, **k):
    return run(M, "sensorActive(byId('%s').sensors.%s,%s)" % (stat, name, flags(**k)))
equal("gating: value sensor needs show or popup", [active("cpu", "value"), active("cpu", "value", show=True), active("cpu", "value", popup=True)], [False, True, True])
equal("gating: popup-only sensor needs the popup open", [active("ram", "used", popup=True), active("ram", "used", popup=True, expanded=True),
      active("ram", "used", expanded=True)], [False, True, False])
equal("gating: freq max follows show or popup, min popup and expanded", [active("freq", "max", show=True), active("freq", "min", show=True, expanded=True),
      active("freq", "min", popup=True, expanded=True)], [True, False, True])
equal("gating: temp max follows its option", [active("temp", "max", expanded=True), active("temp", "max", expanded=True, opts={"popupMax": True}),
      active("temp", "max", opts={"popupMax": True})], [False, True, False])

# The 14 hand-written `enabled:` expressions of v0.9.2 main.qml, as functions of the flags (show, popup, expanded and
# the two temperature options), compared with the registry's gates over every combination.
OLD_GATES = {
    "cpu.value": lambda f: f["show"] or f["popup"], "ram.value": lambda f: f["show"] or f["popup"],
    "ram.used": lambda f: f["popup"] and f["expanded"], "ram.total": lambda f: f["popup"] and f["expanded"],
    "temp.value": lambda f: f["show"] or f["popup"], "temp.max": lambda f: f["popupMax"] and f["expanded"],
    "temp.coreCount": lambda f: f["popupCores"] and f["expanded"],
    "freq.value": lambda f: f["show"] or f["popup"], "freq.min": lambda f: f["popup"] and f["expanded"],
    "freq.max": lambda f: f["show"] or f["popup"],
    "net.down": lambda f: f["show"] or f["popup"], "net.up": lambda f: f["show"] or f["popup"],
    "net.downTotal": lambda f: f["popup"] and f["expanded"], "net.upTotal": lambda f: f["popup"] and f["expanded"],
}
equal("the registry lists exactly the 14 plain sensors of v0.9.2", sorted(run(M, "sensorKinds().map(function(k){return k.id+'.'+k.name})")), sorted(OLD_GATES))
combos = [dict(show=a, popup=b, expanded=c, popupMax=d, popupCores=e) for a in (False, True) for b in (False, True)
          for c in (False, True) for d in (False, True) for e in (False, True)]
got = run(M, "(function(){var cs=%s, out={};sensorKinds().forEach(function(k){out[k.id+'.'+k.name]=cs.map(function(c){"
             "return sensorActive(byId(k.id).sensors[k.name],{show:c.show,popup:c.popup,expanded:c.expanded,opts:{popupMax:c.popupMax,popupCores:c.popupCores}})})});return out})()"
          % json.dumps(combos))
for name, old in OLD_GATES.items():
    equal("gate of %s equals the v0.9.2 enabled expression in all 32 flag combinations" % name, got[name], [bool(old(c)) for c in combos])

# ---------------------------------------------------------------- 4. structure
print("4. structure")
ids = run(M, "METRICS.map(function(m){return m.id})")
equal("ids are unique", len(ids), len(set(ids)))
equal("ids are the default order", ids, run(M, "DEFAULT_ORDER"))
qml_order = re.search(r'defaultOrder: \[(.*?)\]', MAIN_QML).group(1)
equal("default order equals main.qml defaultOrder", ids, re.findall(r'"(\w+)"', qml_order))
cfg = {}
for e in ET.parse(MAIN_XML).getroot().iter():
    if e.tag.endswith("entry"):
        d = [c for c in e if c.tag.endswith("default")][0].text or ""
        cfg[e.get("name")] = (e.get("type"), d)
equal("default order equals main.xml statOrder default", ids, cfg["statOrder"][1].split(","))
equal("byId finds each and returns null otherwise", [run(M, "byId('%s') && byId('%s').id" % (i, i)) for i in ids] + [run(M, "byId('zzz')")], ids + [None])

# Every legacy key a descriptor names, with its default.
claimed = {}
for mid in ids:
    d = run(M, "byId('%s')" % mid)
    def walk(keys, defs, path=""):
        for k, v in keys.items():
            if isinstance(v, dict):
                walk(v, defs.get(k, {}), path + k + ".")
            else:
                claimed.setdefault(v, []).append((mid, path + k))
                check("%s.%s%s has a default" % (mid, path, k), k in defs)
                if k in defs and v in cfg:
                    want = {"Bool": lambda s: s == "true", "Int": int}[cfg[v][0]](cfg[v][1])
                    equal("%s.%s%s default equals main.xml (%s)" % (mid, path, k, v), defs[k], want)
    walk(d["keys"], d["defaults"])
    equal("%s defaults and keys have the same shape" % mid, sorted(d["defaults"]), sorted(d["keys"]))
for key, who in sorted(claimed.items()):
    check("key %s exists in main.xml" % key, key in cfg)
    check("key %s is claimed once" % key, len(who) == 1, str(who))

# Unclaimed keys: must be listed here with a reason, so a new main.xml key makes the test ask the question.
UNCLAIMED = {
    "statOrder": "global: the order of all stats (the strip, the popup and the table follow it)",
    "maxLength": "global: the maximum strip length",
    "lengthLevel": "global: widget-written state of the maximum-length system",
    "lengthTextShort": "global: widget-written state of the maximum-length system",
    "lengthDropped": "global: widget-written state of the maximum-length system (stat ids, not a per-stat key)",
    "lengthInlineOff": "global: widget-written state of the maximum-length system",
    "settingsRev": "global: widget-written change counter for the settings file",
    "useFahrenheit": "global setting (General page); enters the registry only as ctx.useF",
    "warnTemp": "global setting (General page); enters the registry only as ctx.warnTempC",
    "refreshMs": "global: sensor update interval",
    "panelGraphStyle": "global: how every panel graph is drawn",
    "chartStyle": "global: line or bar for every graph",
    "historySeconds": "global: length of every graph history",
}
unclaimed = sorted(set(cfg) - set(claimed))
equal("every main.xml key is claimed by a descriptor or listed with a reason", unclaimed, sorted(UNCLAIMED))
check("every show/popup/graph key of main.xml is claimed",
      all(k in claimed for k in cfg if re.match(r'(show|popup|graphPanel|graphPopup)[A-Z]', k)))
print("      main.xml keys outside the descriptors:")
for k in unclaimed:
    print("        %-16s %s" % (k, UNCLAIMED.get(k, "?")))

# Sensor ids: the registry's set equals the literal sensorId strings in main.qml (per-core and fan ids are patterns).
qml_ids = set(re.findall(r'sensorId: "([^"]+)"', MAIN_QML))
reg_ids = set()
for mid in ids:
    for s in run(M, "Object.keys(byId('%s').sensors).map(function(k){return byId('%s').sensors[k].id})" % (mid, mid)):
        reg_ids.add(s)
# (per-core sensors, "cpu/cpu" + N + "/temperature", are described by popup.repeat.sensor and stay in the popup)
equal("main.qml spells no registry sensor id itself (they come from the sensor delegate)", sorted(reg_ids & qml_ids), [])
equal("main.qml has no sensorId literal at all (per-core ids come from popup.repeat.sensor)", sorted(qml_ids), [])
check("the sensor delegate takes its id from the registry", "sensorId: entry.id" in MAIN_QML)
check("the sensors come from the registry", "readonly property var sensorKinds: M.sensorKinds()" in MAIN_QML and "model: root.sensorKinds" in MAIN_QML)
check("trigger sensors catch up once they all exist", "if (count !== root.sensorKinds.length) return" in MAIN_QML and "root.stepTriggerPeaks()" in MAIN_QML)
check("the sensor map is built once, not per added sensor", MAIN_QML.count("root.sensorItems = sensorMap()") == 1 and "if (count !== root.sensorKinds.length) return\n            root.sensorItems = sensorMap()" in MAIN_QML)
equal("panel values leave out the popup-only sensors", run(M, "METRICS.map(function(m){return m.id+':'+panelSensorNames(m).join(',')}).join(' ')"),
      "cpu:value ram:value temp:value freq:value,max net:down,up bat: fan:")
check("every key a panel template, alert or scale reads is a panel sensor", run(M, "METRICS.every(function(m){var n=panelSensorNames(m);var ks=m.scale&&m.scale.observe?m.scale.observe.keys:[];return ks.every(function(k){return !m.sensors[k]||n.indexOf(k)>=0})})"))
equal("only the core count skips the refresh rate limit", run(M, "sensorKinds().filter(function(k){return byId(k.id).sensors[k.name].noRateLimit}).map(function(k){return k.id+'.'+k.name}).join()"), "temp.coreCount")
check("the trigger test is precomputed per sensor", "readonly property bool isTrigger" in MAIN_QML and "onValueChanged: if (isTrigger)" in MAIN_QML)
equal("per-core sensor pattern", run(M, "byId('temp').popup.repeat.sensor"), "cpu/cpu{n}/temperature")
check("main.qml builds the per-item id from the registry pattern", 'sensorId: rep.spec.sensor.replace("{n}", item.index)' in MAIN_QML)
check("per-item labels count from 1", 'rep.spec.label.replace("{n}", item.index + 1)' in MAIN_QML)
equal("fan discovery pattern equals main.qml's", "/" + run(M, "byId('fan').source.pattern").replace("/", "\\/") + "/",
      "/" + re.search(r'if \(/(.*?)/\.test\(id\)\)', MAIN_QML).group(1) + "/")
# Constants of the battery refresh and the fan discovery, as written in main.qml.
for what, snippet in (("battery refresh", "interval: 5000"),
                      ("fan attempts", "readonly property int maxAttempts: 10"), ("fan first scan", "interval: 800"),
                      ("fan retry", "fanScan.interval = 3000")):
    check("main.qml still says: %s" % what, snippet in MAIN_QML)
equal("registry net scale", run(M, "byId('net').scale"),
      {"from": 0, "mode": "decay", "floor": 100000, "decay": 0.99, "needsGraph": True, "trigger": "down",
       "observe": {"keys": ["down", "up"], "combine": "max", "barCombine": "sum"}})
equal("registry fan source numbers", run(M, "[byId('fan').source.firstScanMs,byId('fan').source.retryMs,byId('fan').source.maxAttempts]"), [800, 3000, 10])
equal("registry battery interval", run(M, "byId('bat').source.intervalMs"), 5000)

# ---------------------------------------------------------------- 5. golden data
print("5. registry against the golden panel text (tests/golden/panel_text.json)")
GOLDEN = json.load(open(os.path.join(ROOT, "tests", "golden", "panel_text.json"), encoding="utf-8"))
MODES = [(f, b) for f in (False, True) for b in (False, True)]


def by_mode(groups):
    """The golden groups [[modes], value] as {(useF, netBits): value}."""
    out = {}
    for modes, value in groups:
        for m in modes:
            out[(m[0] == "1", m[1] == "1")] = value
    return out


def ctx_of(f, b):
    return "{useF:%s,netBits:%s,warnTempC:80}" % (str(f).lower(), str(b).lower())


VALUES = GOLDEN["values"]
compared = 0
for fmtname, groups in sorted(GOLDEN["formats"].items()):
    for (f, b), want in by_mode(groups).items():
        got = run(M, "[%s].map(function(v){return FORMATS.%s(v,%s)})" % (",".join(VALUES), fmtname, ctx_of(f, b)))
        compared += len(want)
        equal("format %s useF=%s netBits=%s" % (fmtname, f, b), got, want)

KEYS = {"cpu": ("value",), "ram": ("value",), "temp": ("value",), "freq": ("value",), "fan": ("value",),
        "bat": ("percent", "state"), "net": ("down", "up")}
for stat, data in sorted(GOLDEN["text"].items()):
    ins = data["inputs"]
    objs = "[%s]" % ",".join("{%s}" % ",".join("%s:%s" % (k, v) for k, v in zip(KEYS[stat], inp)) for inp in ins)
    for name, groups in sorted(data.items()):
        if name == "inputs":
            continue
        orient, kind = name.split()
        for (f, b), want in by_mode(groups).items():
            got = run(M, "%s.map(function(v){return panelText(byId(%s),%s,%s,v,%s)})" % (
                objs, json.dumps(stat), str(kind == "compact").lower(), str(orient == "vertical").lower(), ctx_of(f, b)))
            compared += len(want)
            equal("text %s %s useF=%s netBits=%s" % (stat, name, f, b), got, want)

for stat, kinds in sorted(GOLDEN["reserve"].items()):
    for kind, units in kinds.items():
        for f in (False, True):
            for b in (False, True):
                got = run(M, "reserveText(byId(%s),%s,%s)" % (json.dumps(stat), str(kind == "compact").lower(), ctx_of(f, b)))
                compared += 1
                equal("reserve %s %s useF=%s netBits=%s" % (stat, kind, f, b), got, units["F" if f else "C"])

for name, groups in sorted(GOLDEN["verticalSample"].items()):
    stat, kind = name.split()
    for (f, b), want in by_mode(groups).items():
        got = run(M, "verticalLines(byId(%s),%s,sampleVals(byId(%s),true,%s),%s)" % (
            json.dumps(stat), str(kind == "compact").lower(), json.dumps(stat), ctx_of(f, b), ctx_of(f, b)))
        compared += 1
        equal("vertical sample %s useF=%s netBits=%s" % (name, f, b), got, want)

# The popup's battery row ("62% ↑  (45.3 Wh)").
bad = 0
for p, st, en, want in GOLDEN["popupBattery"]:
    got = run(M, "render(byId('bat').popup.rows[0].value,{percent:%s,state:%d,energy:%s},{})" % (p, st, en))
    compared += 1
    bad += got != want
check("popup battery row", bad == 0, "%d mismatches" % bad)
check("golden data was compared (%d values)" % compared, compared > 5000)

# ---------------------------------------------------------------- 6. golden alerts, colours, scales and peaks
print("6. registry against the golden alerts, scales and peaks (tests/golden/scales.json)")
SC = json.load(open(os.path.join(ROOT, "tests", "golden", "scales.json"), encoding="utf-8"))
STATS = run(M, "DEFAULT_ORDER")
compared = 0
M.evaluate("function alertById(id, vals, warn) { return alertOf(byId(id), vals, { warnTempC: warn }) }")
M.evaluate("function alerting(vals, warn) { return DEFAULT_ORDER.filter(function (id) { return alertById(id, vals, warn) }) }")


def jsarr(rows):
    return "[" + ",".join("[" + ",".join(str(x) for x in r) + "]" for r in rows) + "]"


# Temperature. avgHot is the temp alert; tempHot is the popup's "max core" row alert.
temp_in = jsarr([[r[0], r[1]] for r in SC["temp"]])
got = run(M, "%s.map(function(r){var w=r[0],v=r[1];return [alertById('temp',{value:v},w),byId('temp').popup.rows[1].alert({max:v},{warnTempC:w})]})" % temp_in)
equal("avgHot / tempHot over warn x value", got, [[r[2], r[3]] for r in SC["temp"]])
got = run(M, "%s.map(function(r){var w=r[0],v=r[1];return alerting({value:v},w)})" % temp_in)
equal("the alerting stats over warn x value", got, [r[4] for r in SC["temp"]])
compared += 2 * len(got)
# Colours: the alert picks the negative colour (the colour names are the stand-ins of the golden run).
want_color = lambda alert, normal: "NEG" if alert else normal
equal("temp text / line colour follow the alert",
      [[want_color(r[4] and "temp" in r[4], "TEXT"), want_color(r[4] and "temp" in r[4], "HIGHLIGHT")] for r in SC["temp"]],
      [[r[5], r[6]] for r in SC["temp"]])

# Battery.
bat_in = jsarr([[r[0], r[1]] for r in SC["bat"]])
got = run(M, "%s.map(function(r){return [alertById('bat',{percent:r[0],state:r[1]},80),alerting({percent:r[0],state:r[1]},80)]})" % bat_in)
equal("batLow over percent x state", [g[0] for g in got], [r[2] for r in SC["bat"]])
equal("the alerting stats over percent x state", [g[1] for g in got], [r[3] for r in SC["bat"]])
equal("bat colours follow the alert", [[want_color(r[2], "TEXT"), want_color(r[2], "HIGHLIGHT")] for r in SC["bat"]],
      [[r[4], r[5]] for r in SC["bat"]])
compared += len(got)

# Both at once: per stat [alert, text colour, line colour].
for t, p, st, per in SC["all"]:
    al = run(M, "alerting({value:%s,percent:%s,state:%d},80)" % (t, p, st))
    got = {x: [x in al, "NEG" if x in al else "TEXT", "NEG" if x in al else "HIGHLIGHT"] for x in STATS}
    compared += len(STATS)
    equal("alerts and colours of every stat (temp=%s bat=%s/%d)" % (t, p, st), got, per)

# Scale range of every stat: from scaleFrom, to scaleEnd (a following scale ends at the caller's peak).
RANGE = "(function(id,w,peak){var m=byId(id);return [scaleFrom(m),scaleEnd(m,{warnTempC:w},peak)]})"
for warn, per in SC["range by warn"]:
    got = {x: run(M, "%s('%s',%r,byId('%s').scale.floor)" % (RANGE, x, warn, x)) for x in STATS}
    compared += len(STATS)
    equal("scale range at warn %r (peaks at their start)" % warn, got, per)
for peaks, per in SC["range by peak"]:
    pk = dict(zip(("freq", "net", "fan"), peaks))
    got = {x: run(M, "%s('%s',80,%r)" % (RANGE, x, pk.get(x, 0))) for x in STATS}
    compared += len(STATS)
    equal("scale range at peaks %r" % peaks, got, per)
equal("the following scales are exactly freq, net and fan", run(M, "METRICS.filter(followsData).map(function(m){return m.id})"), ["freq", "net", "fan"])

# Peak sequences.
def peak_run(stat, steps, bar=False, graph=True):
    """The registry's scale stepped through `steps` the way main.qml's handlers do it."""
    out, prev = [], run(M, "byId('%s').scale.floor" % stat)
    for step in steps:
        if stat == "net":
            d, u, ms = step
            vals, dt = "{down:%s,up:%s}" % (d, u), ms
        else:
            vals, dt = "{%s:%s}" % ("max" if stat == "freq" else "value", step), 1000
        prev = run(M, "stepPeak(byId('%s'),%r,%s,{barChart:%s,graphOn:%s},%d)" % (
            stat, prev, vals, str(bar).lower(), str(graph).lower(), dt))
        out.append(prev)
    return out


for key, want in sorted(SC["peaks"]["net"].items()):
    style, flags, name = key.split("|")
    got = peak_run("net", SC["sequences"]["net"][name], bar=(style == "bar"), graph="gp=0 gd=0" not in flags)
    compared += len(want)
    equal("net peak %s" % key, got, want)
for stat in ("freq", "fan"):
    for name, want in sorted(SC["peaks"][stat].items()):
        got = peak_run(stat, SC["sequences"][stat][name])
        compared += len(want)
        equal("%s peak, sequence '%s'" % (stat, name), got, want)
check("scale golden data was compared (%d values)" % compared, compared > 3000)

# ---- popup descriptors (P4 step 1: the helpers the generic popup will use) ----
pflags = lambda **k: json.dumps(dict(dict(popup=False, opts={}, available={"hasBattery": True, "hasFan": True}), **k))
pon = lambda sid, **k: run(M, "popupOn(byId(%s),%s)" % (json.dumps(sid), pflags(**k)))
equal("popupOn follows the popup flag", [pon("cpu"), pon("cpu", popup=True)], [False, True])
equal("temp has a popup when any of its options is on", [pon("temp"), pon("temp", opts={"popupMax": True}), pon("temp", opts={"popupCores": True}),
      pon("temp", popup=True), pon("temp", opts={"separate": True})], [False, True, True, True, False])
equal("battery and fan popups also need the hardware", [pon("bat", popup=True, available={"hasBattery": False}), pon("bat", popup=True),
      pon("fan", popup=True, available={"hasFan": False}), pon("fan", popup=True)], [False, True, False, True])
equal("popup hardware checks", run(M, "METRICS.filter(function(m){return m.popup.available}).map(function(m){return m.id+':'+m.popup.available}).join()"), "bat:hasBattery,fan:hasFan")
equal("popup flag names per stat", run(M, "METRICS.map(function(m){return m.id+':'+popupFlagNames(m).join('+')}).join(' ')"),
      "cpu: ram: temp:popup+popupMax+popupCores freq: net: bat: fan:")
equal("temp rows follow their flags", [run(M, "popupRowShown(byId('temp').popup.rows[%d],%s)" % (i, pflags(**k)))
      for i, k in ((0, {}), (0, {"popup": True}), (1, {}), (1, {"opts": {"popupMax": True}}))], [False, True, False, True])
equal("temp graph needs the average row", [run(M, "popupGraphShown(byId('temp'),%s)" % pflags(**k)) for k in ({}, {"popup": True})], [False, True])
equal("a stat without graphWhen shows its graph with its popup", run(M, "popupGraphShown(byId('cpu'),%s)" % pflags()), True)
equal("every row's flag is the popup flag or one of the stat's options", run(M, "METRICS.every(function(m){return popupFlagNames(m).every(function(f){return f==='popup'||(m.keys.options&&f in m.keys.options)})})"), True)
equal("the widest popup label is the one the name column is sized from", run(M, "popupLabels(METRICS).sort(function(a,b){return b.length-a.length})[0]"), "CPU temp (max core)")
check("every popup row alert is 'panel' or a function", run(M, "METRICS.every(function(m){return m.popup.rows.every(function(r){return r.alert===undefined||r.alert==='panel'||typeof r.alert==='function'})})"))

# ---- generic popup block (P4 step 2) ----
for blk in ("cpuBlock", "ramBlock", "freqBlock", "netBlock", "fanBlock"):
    check("main.qml has no %s" % blk, "id: " + blk not in MAIN_QML)
check("the stat block renders the registry's rows around the graph", "popup.rows.slice(0, blk.rowsBeforeGraph)" in MAIN_QML
      and "popup.rows.slice(blk.rowsBeforeGraph)" in MAIN_QML
      and "M.render(modelData.value, root.popupVals(statId), root.textCtx)" in MAIN_QML)
check("the stat block's rows, graph and per-item lines use the registry's flags", "M.popupRowShown(modelData, root.popupFlags(statId))" in MAIN_QML
      and "M.flagOn(spec.when, root.popupFlags(statId))" in MAIN_QML
      and "M.popupGraphShown(blk.entry, root.popupFlags(blk.statId))" in MAIN_QML)
check("the block takes its stat id as a required property, not from its parent", "required property string statId" in MAIN_QML
      and "blockStatId" not in MAIN_QML and "parent.blockStatId" not in MAIN_QML)
check("main.qml has no popupBlock switch and no batBlock", "function popupBlock" not in MAIN_QML and "id: batBlock" not in MAIN_QML)
check("the popup is a Repeater of StatBlocks over the shown stats", "model: root.popupIds()" in MAIN_QML and "delegate: StatBlock {" in MAIN_QML)
equal("hook names in the registry equal the components main.qml has", run(M, "METRICS.reduce(function(a,m){return a.concat(m.popup.hooks||[])},[])"), ["perBattery", "chargeRow"])
for hk in ("perBattery", "chargeRow"):
    check("main.qml has a component for hook " + hk, 'case "%s":' % hk in MAIN_QML and "id: %sHook" % hk in MAIN_QML)
check("hooks sit between the rows and the graph and show only when their item says so", "popup.hooks || []" in MAIN_QML and "visible: item !== null && item.shown" in MAIN_QML)
check("the battery popup row gets the summed energy", 'b.energy = batEnergyTotal()' in MAIN_QML)
check("main.qml has no tempBlock", "id: tempBlock" not in MAIN_QML)
equal("rows before the graph", run(M, "METRICS.map(function(m){return m.id+':'+popupRowsBeforeGraph(m)}).join(' ')"), "cpu:1 ram:1 temp:1 freq:2 net:2 bat:1 fan:1")
check("the fan icon comes from the registry's row decoration", 'fanIcon: modelData.decoration === "fanIcon"' in MAIN_QML)
check("popup values come from the sensors (all of them) or the live values", "if (m.source) return statVals(id)" in MAIN_QML
      and "for (var name in m.sensors) vals[name] = sensorValue(id, name)" in MAIN_QML)
equal("popup rows render the v0.9.2 text", run(M, "(function(){var v={cpu:{value:12.4},ram:{value:47.6,used:8e9,total:16e9},freq:{value:2750,min:800,max:4500},"
      "net:{down:123456,up:7890,downTotal:5e9,upTotal:1e9},fan:{value:2400}},c={useF:false,netBits:false};"
      "return ['cpu','ram','freq','net','fan'].map(function(i){return byId(i).popup.rows.map(function(r){return render(r.value,v[i],c)})})})()"),
      [["12%"], ["7.5 GiB / 14.9 GiB (48%)"], ["2.8 GHz", "0.8 / 4.5 GHz"], ["123 KB/s  (5.0 GB total)", "7.9 KB/s  (1.0 GB total)"], ["2400 RPM"]])

# ---- popup visibility and label width from the registry (P4 step 5) ----
check("popupShown asks the registry", "return !!m && M.popupOn(m, popupFlags(id))" in MAIN_QML)
for n in ("popupCpu", "popupMemory", "popupTempAvg", "popupTempMax", "popupFreq", "popupNet", "popupCores"):
    check("main.qml has no per-stat %s property" % n, "property bool %s:" % n not in MAIN_QML)
check("the popup name column is sized from the registry's labels", "model: root.popupLabelList" in MAIN_QML
      and "M.popupLabels(M.METRICS)" in MAIN_QML
      and '"CPU temp (max core)"' not in MAIN_QML)
for f in ("temp", "gib", "rate", "bytesText", "ghzNumber", "freq"):
    check("the unused popup wrapper %s is gone" % f, "function %s(v)" % f not in MAIN_QML)

# ---- review fixes: behaviour checks ----
equal("every sensor gate is one of the known ones", run(M, "METRICS.every(function(m){return Object.keys(m.sensors).every(function(n){var g=m.sensors[n].gate;return g==='show'||g==='show|popup'||g==='popup'||g.indexOf('opt:')===0})})"), True)
equal("panel sensors are exactly those with a show gate", run(M, "(function(){var m={sensors:{a:{gate:'show'},b:{gate:'show|popup'},c:{gate:'popup'},d:{gate:'showOnly'},e:{gate:'opt:x'}}};return panelSensorNames(m)})()"), ["a", "b"])
# Every key a popup row template reads is supplied by the popup values (sensors of a plain stat, source fields otherwise).
supply = {"bat": ["percent", "state", "energy"], "fan": ["value"]}
for m in run(M, "METRICS.map(function(m){return {id:m.id,plain:!m.source,sensors:Object.keys(m.sensors),rows:m.popup.rows.map(function(r){return r.value}).concat(m.popup.repeat?[m.popup.repeat.value]:[])}})"):
    have = m["sensors"] if m["plain"] else supply[m["id"]]
    used = set(k for t in m["rows"] for k in re.findall(r"\{(\w+)", t))
    check("popup values of %s supply the keys its rows read (%s)" % (m["id"], sorted(used)), used <= set(have))
check("the popup stat list is a function of the order and popupShown", "function popupIds()" in MAIN_QML)
check("the popup label list is computed once", MAIN_QML.count("M.popupLabels(M.METRICS)") == 1)
check("the orphaned battery-row comment is gone", "The popup's battery row:" not in MAIN_QML)

# ---- P5: settings pages and the notice from the registry ----
CFG_QML = open(os.path.join(UI, "configMetrics.qml"), encoding="utf-8").read()
NOTICE_QML = open(os.path.join(UI, "LengthNotice.qml"), encoding="utf-8").read()
rows = run(M, "settingsRows()")
equal("settings rows follow the registry order", [r["id"] for r in rows], run(M, "METRICS.map(function(m){return m.id})"))
equal("a settings row carries the registry's names and the four keys",
      [r for r in rows if r["id"] == "temp"],
      [{"id": "temp", "name": "CPU temperature", "show": "showTemp", "graph": "graphPanelTemp",
        "popup": "popupTempAvg", "popupGraph": "graphPopupTemp"}])
equal("statName reads the registry", run(M, "[statName('fan'), statName('net')]"), ["Fan speed", "Network speed"])
equal("statName of an unknown id is the id", run(M, "statName('zzz')"), "zzz")
equal("hardware keys: battery and fan only", run(M, "METRICS.map(function(m){return hardwareKey(m.id)})"),
      ["", "", "", "", "", "batteryCount", "fanCount"])
equal("hardwareKey of an unknown id is empty", run(M, "hardwareKey('zzz')"), "")
declared = set()
for page in ("configGeneral", "configMetrics", "configGraphs"):
    declared |= set(re.findall(r"property\s+\w+\s+cfg_(\w+)", open(os.path.join(UI, page + ".qml"), encoding="utf-8").read()))
for r in rows:
    for k in (r["show"], r["graph"], r["popup"], r["popupGraph"]):
        check("a settings page declares cfg_%s and cfg_%sDefault" % (k, k), k in declared and (k + "Default") in declared)
for m in run(M, "METRICS.map(function(m){return {id:m.id,o:m.keys.options||{},h:m.keys.hidden||{}}})"):
    for k in m["o"].values():
        check("a settings page declares the option cfg_%s" % k, k in declared and (k + "Default") in declared)
    for k in m["h"].values():
        check("the hidden key %s has no cfg_ property" % k, k not in declared and (k + "Default") not in declared)
check("configMetrics builds its rows from the registry", "M.settingsRows()" in CFG_QML and "M.hardwareKey(id)" in CFG_QML)
check("configMetrics has no hand-written stat list", 'id: "cpu"' not in CFG_QML)
check("LengthNotice names stats through the registry", "M.statName(" in NOTICE_QML and "function statName" not in NOTICE_QML)

# ---- review fixes P3-P5: no per-stat hardware ids or sensors in generic code ----
equal("popupAvailable follows popup.available", run(M, "[popupAvailable(byId('fan'),{available:{hasFan:true}}),popupAvailable(byId('fan'),{available:{hasFan:false}}),popupAvailable(byId('fan'),{}),popupAvailable(byId('cpu'),{})]"), [True, False, False, True])
check("statPopupOn reads the registry's availability", "M.popupAvailable(m, popupFlags(id))" in MAIN_QML and 'id === "bat" ? hasBattery' not in MAIN_QML)
check("anyPopupShown reuses popupIds", "return popupIds().length > 0" in MAIN_QML)
check("RepeatBlock counts items with the registry's countSensor", "root.sensorValue(statId, spec.countSensor)" in MAIN_QML and "root.coreCount" not in MAIN_QML)
check("configMetrics has one availability rule", "page.hasFan" not in CFG_QML and "hasBat" not in CFG_QML)

print()
print("%d checks passed, %d failed" % (passed, len(failures)))
if failures:
    print("FAILED: " + "; ".join(failures[:10]) + (" ..." if len(failures) > 10 else ""))
    sys.exit(1)
print("PASS")
