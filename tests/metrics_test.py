#!/usr/bin/env python3
"""Tests for package/contents/ui/Metrics.js, run without Plasma.

    python3 tests/metrics_test.py

Needs python3 with PySide6 (its QJSEngine is Qt's own JavaScript engine, the one QML uses). Exits non-zero
when any check fails. What it checks:
  1. every panel text the registry renders equals the worst-case string main.qml uses today
     (the m* TextMetrics lines, and the vertical sample lines);
  2. the registry's formatters give the same output as main.qml's own formatting functions, which are
     extracted from main.qml and run in a second engine, over a table of boundary values;
  3. literal boundary cases of the formatters, render(), alerts, scales and sensor gating;
  4. the structure: unique ids, labels, sensor ids, and every settings key of main.xml accounted for.
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


# ---------------------------------------------------------------- 1. strings equal main.qml's
print("1. panel strings against main.qml")
# The m* TextMetrics: id -> (stat, compact). Each text is a literal or a `root.useF ? "F" : "C"` pair.
MSTAT = {"mCpu": ("cpu", False), "mCpuC": ("cpu", True), "mRam": ("ram", False), "mRamC": ("ram", True),
         "mTemp": ("temp", False), "mTempC": ("temp", True), "mFreq": ("freq", False), "mFreqC": ("freq", True),
         "mNet": ("net", False), "mNetC": ("net", True), "mBat": ("bat", False), "mBatC": ("bat", True),
         "mFan": ("fan", False), "mFanC": ("fan", True)}
found = {}
for m in re.finditer(r'TextMetrics \{ id: (m\w+);\s*font: [^;]+;\s*text: (.+?) \}', MAIN_QML):
    found[m.group(1)] = m.group(2)
extra = set(found) - set(MSTAT) - {"mLine", "mPopupLabel"}
equal("main.qml has no m* TextMetrics the test does not know", sorted(extra), [])
equal("every expected m* TextMetrics exists in main.qml", sorted(set(MSTAT) - set(found)), [])
for mid, text in sorted(found.items()):
    if mid not in MSTAT:
        continue
    stat, compact = MSTAT[mid]
    tern = re.match(r'root\.useF \? "(.*?)" : "(.*?)"$', text)
    lit = re.match(r'"(.*)"$', text)
    variants = {True: tern.group(1), False: tern.group(2)} if tern else {False: lit.group(1), True: lit.group(1)}
    for useF in ([False, True] if tern else [False]):
        got = run(M, "reserveText(byId(%s),%s,%s)" % (json.dumps(stat), str(compact).lower(), ctx(useF=useF)))
        equal("%s%s horizontal %s%s" % (stat, " compact" if compact else " full", "F" if useF else "C", "" if tern else " (unit-less)"),
              got, variants[useF])
# main.qml's mNet is "999 MB/s" in both unit modes, so the horizontal sample is the same in bits mode.
equal("net full reserve, bits mode keeps the bytes text", run(M, "reserveText(byId('net'),false,%s)" % ctx(netBits=True)),
      "\u2193999 MB/s \u2191999 MB/s")

# Vertical lines: the worst-case lines of verticalLines(id, compact, true) in main.qml, written out here.
# Source: verticalCaption(), statValue() samples (checked below against main.qml), valueText(), netLines().
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
# Stats without a verticalCompact must ignore compact (statCompact only shortens temp, freq and bat).
for stat in ("cpu", "ram", "net", "fan"):
    equal("%s vertical ignores compact" % stat, vlines(stat, True, sample(stat, True)), vlines(stat, False, sample(stat, True)))
equal("only temp, freq and bat have verticalCompact",
      run(M, "METRICS.filter(function(m){return !!m.panel.verticalCompact}).map(function(m){return m.id})"),
      ["temp", "freq", "bat"])
check("main.qml statCompact lists the same three stats",
      re.search(r'if \(id !== "temp" && id !== "freq" && id !== "bat"\) return false', MAIN_QML) is not None)

# The facts the literal vertical lines above rest on, checked against main.qml.
cap_src = re.search(r'function verticalCaption\(id\) \{(.*?)\n    \}', MAIN_QML, re.S).group(1)
captions = dict(re.findall(r'case "(\w+)":\s+return "([^"]+)"', cap_src))
for stat in ("cpu", "ram", "temp", "freq", "net", "bat", "fan"):
    equal("caption of %s in main.qml" % stat, captions.get(stat), run(M, "byId('%s').panel.vertical[0]" % stat))
sv_src = re.search(r'function statValue\(id, sample\) \{(.*?)\n    \}', MAIN_QML, re.S).group(1)
qml_samples = {k: int(v) for k, v in re.findall(r'case "(\w+)":\s+return sample \? (\d+) :', sv_src)}
for stat, key in (("cpu", "value"), ("ram", "value"), ("temp", "value"), ("freq", "value"), ("fan", "value"), ("bat", "percent")):
    equal("statValue sample of %s in main.qml" % stat, qml_samples.get(stat), sample(stat, False)[key])
check("main.qml vertical battery sample uses the charging state",
      "batValue(v, sample ? 1 : batState, compact)" in MAIN_QML and sample("bat", True)["state"] == 1)
check("main.qml net sample is 999e6 (bits: /8)", "netBits ? 999e6 / 8 : 999e6" in MAIN_QML
      and sample("net", True)["down"] == 999e6 and sample("net", True, netBits=True)["down"] == 999e6 / 8)

# ---------------------------------------------------------------- 2. formatters against main.qml's own
print("2. formatters against the functions in main.qml")
# Pull the pure formatting functions out of main.qml and run them in a second engine.
blocks = [
    re.search(r'// ---- formatting helpers ----\n(.*?)\n    // Each temperature is highlighted', MAIN_QML, re.S).group(1),
    re.search(r'(    function tempShort\(v\).*?    function rpmNumber\(v\)[^\n]*)', MAIN_QML, re.S).group(1),
]
Q = make_engine("var useF = false, netBits = false, batPercent, batState, batterySummary = {}, netDown = {}, netUp = {}, fanRpm;\n"
                + "\n".join(blocks))
VALUES = ["undefined", "null", '""', "NaN", "Infinity", '"abc"', "0", "0.4", "0.5", "1", "9.9", "9.94", "9.95", "9.96",
          "49.5", "50.5", "99.5", "100", "100.4", "212", "36.6", "-5", "800", "999", "999.4", "999.49", "999.5", "999.6", "1000",
          "9949", "9950", "9999", "99499", "99500", "999499", "999500", "1e6", "1.5e9", "999e6", "999.9e6", "1e12", "1073741824",
          "8589934592", "1234.56", '"42"', "0.04", "-0.5"]
# (registry format, main.qml expression with %s as the value)
PAIRS = [("pct", "pct(%s)"), ("gib", "gib(%s)"), ("wh", "wh(%s)"), ("ghz", "ghzNumber(%s)"), ("freq", "freq(%s)"),
         ("freqShort", "freqShort(%s)"), ("bytes", "bytesText(%s)"), ("rpm", "rpmNumber(%s)"),
         ("temp", "temp(%s)"), ("tempShort", "tempShort(%s)"), ("rate", "rate(%s)"), ("rateShort", "rateShort(%s)")]
mismatches = 0
cases = 0
for useF in (False, True):
    for bits in (False, True):
        Q.evaluate("useF = %s; netBits = %s" % (str(useF).lower(), str(bits).lower()))
        for fmt, expr in PAIRS:
            for v in VALUES:
                cases += 1
                want = run(Q, expr % v)
                got = run(M, "FORMATS.%s(%s,%s)" % (fmt, v, ctx(useF=useF, netBits=bits)))
                if got != want:
                    mismatches += 1
                    print("FAIL  %s(%s) useF=%s bits=%s got %r want %r" % (fmt, v, useF, bits, got, want))
check("formatters match main.qml (%d cases)" % cases, mismatches == 0, "%d mismatches" % mismatches)
# Battery value text and the arrow, over every state.
Q.evaluate("useF = false; netBits = false")
bad = 0
for p in ["undefined", "0", "14.6", "15", "49.5", "100", '"x"']:
    for s in (-1, 0, 1):
        for compact, tmpl in ((False, "{percent:pct}{state:arrowSp}"), (True, "{percent:pct}{state:arrow}")):
            want = run(Q, "batValue(%s,%d,%s)" % (p, s, str(compact).lower()))
            got = run(M, "render(%s,{percent:%s,state:%d},{})" % (json.dumps(tmpl), p, s))
            bad += got != want
check("battery value text matches batValue (all states)", bad == 0, "%d mismatches" % bad)

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

# Labels agree with the two places that carry them today.
page_names = dict(re.findall(r'\{ id: "(\w+)",\s+name: i18n\("([^"]+)"\)', METRICS_PAGE))
notice_names = dict(re.findall(r'case "(\w+)":\s+return i18n\("([^"]+)"\)', NOTICE))
for mid in ids:
    name = run(M, "byId('%s').name" % mid)
    equal("name of %s equals the Metrics table label" % mid, name, page_names.get(mid))
    equal("name of %s equals the LengthNotice label" % mid, name, notice_names.get(mid))
# Sensor ids: the registry's set equals the literal sensorId strings in main.qml (per-core and fan ids are patterns).
qml_ids = set(re.findall(r'sensorId: "([^"]+)"', MAIN_QML))
reg_ids = set()
for mid in ids:
    for s in run(M, "Object.keys(byId('%s').sensors).map(function(k){return byId('%s').sensors[k].id})" % (mid, mid)):
        reg_ids.add(s)
reg_ids.add("cpu/cpu")      # per-core: sensor "cpu/cpu" + N + "/temperature", described by popup.repeat.sensor
equal("sensor ids equal main.qml's sensorId literals", sorted(reg_ids), sorted(qml_ids))
equal("per-core sensor pattern", run(M, "byId('temp').popup.repeat.sensor"), "cpu/cpu{n}/temperature")
check("main.qml builds the per-core id the same way", '"cpu/cpu" + coreRow.index + "/temperature"' in MAIN_QML)
equal("fan discovery pattern equals main.qml's", "/" + run(M, "byId('fan').source.pattern").replace("/", "\\/") + "/",
      "/" + re.search(r'if \(/(.*?)/\.test\(id\)\)', MAIN_QML).group(1) + "/")
# Constants of the scales and the fan discovery, as written in main.qml.
for what, snippet in (("temp scale start", "tempYMin: 20"), ("temp scale end", "Math.max(100, warnTempC + 10)"),
                      ("net floor and decay", "Math.max(100000, barChart ? d + u : Math.max(d, u), netPeak * Math.pow(0.99, refreshMs / 1000))"),
                      ("freq floor", "property real freqPeak: 1000"), ("fan floor", "property real fanPeak: 3000"),
                      ("battery low", "batPercent < 15 && batState <= 0"), ("battery refresh", "interval: 5000"),
                      ("fan attempts", "readonly property int maxAttempts: 10"), ("fan first scan", "interval: 800"),
                      ("fan retry", "fanScan.interval = 3000")):
    check("main.qml still says: %s" % what, snippet in MAIN_QML)
equal("registry net scale", run(M, "byId('net').scale"), {"from": 0, "mode": "decay", "floor": 100000, "decay": 0.99, "observe": "down,up"})
equal("registry fan source numbers", run(M, "[byId('fan').source.firstScanMs,byId('fan').source.retryMs,byId('fan').source.maxAttempts]"), [800, 3000, 10])
equal("registry battery interval", run(M, "byId('bat').source.intervalMs"), 5000)

print()
print("%d checks passed, %d failed" % (passed, len(failures)))
if failures:
    print("FAILED: " + "; ".join(failures[:10]) + (" ..." if len(failures) > 10 else ""))
    sys.exit(1)
print("PASS")
