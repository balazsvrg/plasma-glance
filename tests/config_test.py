#!/usr/bin/env python3
"""Tests for package/contents/ui/Config.js (the settings file), run without Plasma.

    python3 tests/config_test.py

Needs python3 with PySide6. Exits non-zero when any check fails. What it checks:
  1. the schema against main.xml (every key exists, type, default and range agree) and against the registry;
  2. parse / toIni / plan on literal cases, including every invalid shape;
  3. a real round trip through QtCore.Settings in a temp file: the generated source loads, a first run fills
     the file from the widget's settings, a valid file value wins, an invalid one is left alone, foreign
     sections and keys survive a write.
"""
import json
import os
import re
import sys
import tempfile
import xml.etree.ElementTree as ET

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtCore import QCoreApplication, QUrl, QTimer
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QJSEngine, QQmlApplicationEngine

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UI = os.path.join(ROOT, "package", "contents", "ui")
MAIN_XML = os.path.join(ROOT, "package", "contents", "config", "main.xml")
PRAGMA = re.compile(r"^\.pragma library\s*$", re.M)
METRICS_JS = PRAGMA.sub("", open(os.path.join(UI, "Metrics.js"), encoding="utf-8").read())
CONFIG_JS = PRAGMA.sub("", open(os.path.join(UI, "Config.js"), encoding="utf-8").read())

app = QGuiApplication([])
app.setOrganizationName("glance-test")
app.setApplicationName("config-test")
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


E = QJSEngine()
r = E.evaluate(METRICS_JS + "\n" + CONFIG_JS + "\nvar SCH = schema(METRICS);\nvar IDS = METRICS.map(function(m){return m.id});")
if r.isError():
    raise SystemExit("JS error: %s" % r.toString())


def run(expr):
    r = E.evaluate("JSON.stringify(" + expr + ")")
    if r.isError():
        raise SystemExit("JS error in %s: %s" % (expr, r.toString()))
    s = r.toString()
    return None if s == "undefined" else json.loads(s)


SCH = run("SCH")
IDS = run("IDS")
BY = {e["name"]: e for e in SCH}

# ---- 1. schema vs main.xml and the registry ----
xml = {}
for e in ET.parse(MAIN_XML).getroot().iter("{http://www.kde.org/standards/kcfg/1.0}entry"):
    ns = "{http://www.kde.org/standards/kcfg/1.0}"
    d = e.find(ns + "default")
    lo, hi = e.find(ns + "min"), e.find(ns + "max")
    xml[e.get("name")] = {"type": e.get("type"), "def": d.text if d is not None and d.text else "",
                          "min": lo.text if lo is not None else None, "max": hi.text if hi is not None else None}

names = [e["name"] for e in SCH]
equal("ini names are unique", len(names), len(set(names)))
cfgs = [e["cfg"] for e in SCH]
equal("cfg keys are unique", len(cfgs), len(set(cfgs)))
for e in SCH:
    check("%s is a QML identifier" % e["name"], re.fullmatch(r"[a-z][A-Za-z0-9_]*", e["name"]) is not None)
    check("%s exists in main.xml" % e["cfg"], e["cfg"] in xml)
    if e["cfg"] not in xml:
        continue
    x = xml[e["cfg"]]
    if e["type"] == "bool":
        equal("%s type" % e["cfg"], x["type"], "Bool")
        equal("%s default" % e["cfg"], x["def"], "true" if e["def"] else "false")
    elif e["type"] == "int":
        equal("%s type" % e["cfg"], x["type"], "Int")
        equal("%s default" % e["cfg"], int(x["def"]), e["def"])
        equal("%s min" % e["cfg"], int(x["min"]), e["min"])
        equal("%s max" % e["cfg"], int(x["max"]), e["max"])
    else:
        equal("%s type" % e["cfg"], x["type"], "String")
        equal("%s default" % e["cfg"], x["def"], e["def"])

# What main.xml keeps outside the file, with the reason (a new key must be listed here or added to the schema).
OUTSIDE = {
    "lengthLevel": "written by the widget", "lengthTextShort": "written by the widget",
    "lengthDropped": "written by the widget", "lengthInlineOff": "written by the widget",
    "batteryCount": "written by the widget", "fanCount": "written by the widget",
}
equal("every main.xml key is in the file or listed as written by the widget",
      sorted(set(xml) - set(cfgs)), sorted(OUTSIDE))
equal("sections used", sorted(set(e["section"] for e in SCH)), ["Graphs", "Main", "Metrics"])
for m in run("METRICS.map(function(m){return {id:m.id,o:m.keys.options||{}}})"):
    for k in ("show", "popup", "panelGraph", "popupGraph"):
        check("%s_%s in the schema" % (m["id"], k), "%s_%s" % (m["id"], k) in BY)
    for o in m["o"]:
        check("%s_%s (option) in the schema" % (m["id"], o), "%s_%s" % (m["id"], o) in BY)
equal("temp options become keys", [n for n in names if n.startswith("temp_")],
      ["temp_show", "temp_popup", "temp_popupMax", "temp_popupCores", "temp_panelGraph", "temp_popupGraph"])
equal("a stat's sections", [BY[n]["section"] for n in ("cpu_show", "cpu_popup", "cpu_panelGraph", "cpu_popupGraph")],
      ["Metrics", "Metrics", "Graphs", "Graphs"])

# ---- 2. parse / toIni / plan ----
def parse(name, raw):
    return run("parse(SCH[%d], %s, IDS)" % (names.index(name), json.dumps(raw)))


for raw, want in [("true", True), ("false", False), ("TRUE", True), (" False ", False), ("1", True), ("0", False),
                  ("maybe", None), ("", None), ("yes", None), ("2", None)]:
    equal("bool %r" % raw, parse("cpu_show", raw), want)
for raw, want in [("1000", 1000), ("250", 250), ("10000", 10000), ("249", None), ("10001", None), ("12.5", None),
                  ("abc", None), ("-5", None), ("", None), (" 750 ", 750), ("1e3", None)]:
    equal("refreshMs %r" % raw, parse("refreshMs", raw), want)
equal("maxLength 0 is valid", parse("maxLength", "0"), 0)
equal("maxLength -1 is not", parse("maxLength", "-1"), None)
for raw, want in [("cpu ram temp freq net bat fan", "cpu,ram,temp,freq,net,bat,fan"),
                  ("fan cpu", "fan,cpu,ram,temp,freq,net,bat"),
                  ("cpu cpu ram", "cpu,ram,temp,freq,net,bat,fan"),
                  ("zzz cpu", "cpu,ram,temp,freq,net,bat,fan"),
                  ("net,cpu", "net,cpu,ram,temp,freq,bat,fan"),
                  ("zzz yyy", None), ("", None), ("   ", None)]:
    equal("order %r" % raw, parse("order", raw), want)
i_cpu = names.index("cpu_show")
equal("toIni bool", run("[toIni(SCH[%d], true), toIni(SCH[%d], false)]" % (i_cpu, i_cpu)), ["true", "false"])
equal("toIni int", run("toIni(SCH[%d], 750)" % names.index("refreshMs")), "750")
equal("toIni order", run("toIni(SCH[%d], 'fan,cpu,ram')" % names.index("order")), "fan cpu ram")
equal("order survives a round trip", parse("order", run("toIni(SCH[%d], 'fan,cpu,ram,temp,freq,net,bat')" % names.index("order"))),
      "fan,cpu,ram,temp,freq,net,bat")

DEFAULTS = {e["cfg"]: e["def"] for e in SCH}


def plan(raw, cfg=None):
    cfg = dict(DEFAULTS, **(cfg or {}))
    return run("plan(SCH, %s, %s, IDS)" % (json.dumps(raw), json.dumps(cfg)))


p = plan({})
equal("empty file: nothing to apply", p["apply"], {})
equal("empty file: every key is filled", sorted(p["fill"]), sorted(names))
equal("empty file: filled from the widget", [p["fill"]["cpu_show"], p["fill"]["refreshMs"], p["fill"]["order"]],
      ["true", "1000", "cpu ram temp freq net bat fan"])
p = plan({}, {"showCpu": False, "refreshMs": 500, "statOrder": "fan,cpu,ram,temp,freq,net,bat"})
equal("migration: the widget's saved values go to the file",
      [p["fill"]["cpu_show"], p["fill"]["refreshMs"], p["fill"]["order"]], ["false", "500", "fan cpu ram temp freq net bat"])
p = plan({"cpu_show": "false", "refreshMs": "2000"})
equal("a valid file value is applied", p["apply"], {"showCpu": False, "refreshMs": 2000})
check("a key present in the file is not filled", "cpu_show" not in p["fill"] and "refreshMs" not in p["fill"])
p = plan({"cpu_show": "true"})
equal("a file value equal to the widget's is not applied", p["apply"], {})
p = plan({"refreshMs": "abc", "cpu_show": "maybe", "warnTemp": "500"})
equal("invalid values are reported", sorted(p["bad"]), ["cpu_show", "refreshMs", "warnTemp"])
equal("invalid values are neither applied nor filled", [p["apply"], [n for n in p["fill"] if n in p["bad"]]], [{}, []])
p = plan({"order": "net cpu"})
equal("a partial order is completed", p["apply"], {"statOrder": "net,cpu,ram,temp,freq,bat,fan"})
p = plan({"cpu_show": "  "})
check("whitespace counts as absent", "cpu_show" in p["fill"])

# ---- 3. a real round trip through QtCore.Settings ----
# The QML below plays main.qml's part (open one Settings per section, plan, fill, write one key) and reports to
# the Python side, which edits and reads the file in between.
from PySide6.QtCore import Property, QObject, Slot

tmp = tempfile.mkdtemp(prefix="glancerc-test-")
RC = os.path.join(tmp, "glancerc")
QMLFILE = os.path.join(tmp, "t.qml")
open(QMLFILE, "w").write("""
import QtQuick
import "%(ui)s/Metrics.js" as M
import "%(ui)s/Config.js" as C
Item {
    id: root
    property var objs: ({})
    property var sch: C.schema(M.METRICS)
    property var ids: M.METRICS.map(function(m) { return m.id })
    function open() {
        objs = {}
        for (var i = 0; i < C.SECTIONS.length; ++i)
            objs[C.SECTIONS[i]] = Qt.createQmlObject(C.settingsSource("file://" + py.rc, C.SECTIONS[i], sch), root, "gen")
    }
    function raw() { var r = {}; for (var i = 0; i < sch.length; ++i) r[sch[i].name] = objs[sch[i].section][sch[i].name]; return r }
    function put(name, text) { for (var i = 0; i < sch.length; ++i) if (sch[i].name === name) objs[sch[i].section][name] = text }
    function flush() { for (var s in objs) objs[s].sync() }
    function defaults() { var d = {}; for (var i = 0; i < sch.length; ++i) d[sch[i].cfg] = sch[i].def; return d }
    function startup(cfg) {
        open()
        var p = C.plan(sch, raw(), cfg, ids)
        for (var n in p.fill) put(n, p.fill[n])
        flush()
        return p
    }
    // Settings writes reach the file about a second later (QSettings syncs from a timer; sync() does not hurry it):
    // each step waits before the next one looks at the file.
    property var cfg: null
    property var steps: [
        function() { cfg = defaults(); cfg.showCpu = false; cfg.refreshMs = 500; cfg.statOrder = "fan,cpu,ram,temp,freq,net,bat"
                     py.record("first", startup(cfg)) },                // no file: filled from the widget
        function() { py.snapshot("first"); py.record("second", startup(cfg)) },   // the file now agrees with the widget
        function() { py.edit() },                                       // the user edits the file
        function() { py.record("edited", startup(cfg)) },               // file wins, garbage stays, nothing else changes
        function() { py.snapshot("edited"); open(); put("maxLength", "300"); flush() },   // a GUI change writes one key
        function() { py.snapshot("written"); Qt.quit() }
    ]
    property int step: 0
    Timer {
        interval: 1600; running: true; repeat: true
        onTriggered: { var f = root.steps[root.step++]; if (f) f() }
    }
}
""" % {"ui": UI})


class Py(QObject):
    def __init__(self):
        super().__init__()
        self.rec = {}
        self.snap = {}

    @Property(str, constant=True)
    def rc(self):
        return RC

    @Slot(str, "QVariant")
    def record(self, k, v):
        self.rec[k] = v.toVariant() if hasattr(v, "toVariant") else v

    @Slot(str)
    def snapshot(self, k):
        self.snap[k] = open(RC).read()

    @Slot()
    def edit(self):
        open(RC, "w").write("# my notes\n[Metrics]\ncpu_show=true\nnet_show=maybe\n\n[Main]\nrefreshMs=abc\n"
                            "order=net cpu\nwarnTemp=95\n\n[Foreign]\nk=v\n")


def ini(text):
    out, sec = {}, None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("[") and line.endswith("]"):
            sec = line[1:-1]
            out[sec] = {}
        elif "=" in line and sec:
            k, v = line.split("=", 1)
            out[sec][k] = v.strip('"')
    return out


py = Py()
eng = QQmlApplicationEngine()
eng.rootContext().setContextProperty("py", py)
eng.warnings.connect(lambda ws: [print("QML warning:", w.toString()) for w in ws])
eng.load(QUrl.fromLocalFile(QMLFILE))
check("the round-trip QML loads", len(eng.rootObjects()) == 1)
QTimer.singleShot(20000, app.quit)
if eng.rootObjects():
    eng.rootObjects()[0].destroyed.connect(app.quit)
    app.exec()
check("the scenario ran to the end", "written" in py.snap)

first = ini(py.snap.get("first", ""))
equal("first run: the file has the three sections", sorted(first), ["Graphs", "Main", "Metrics"])
equal("first run: every key was written", sorted(k for s in first.values() for k in s), sorted(names))
equal("first run: the widget's values are in the file",
      [first["Metrics"]["cpu_show"], first["Main"]["refreshMs"], first["Main"]["order"]],
      ["false", "500", "fan cpu ram temp freq net bat"])
equal("first run: a default is written as such", [first["Metrics"]["ram_show"], first["Graphs"]["historySeconds"]], ["true", "60"])
equal("first run: plan applied nothing", py.rec["first"]["apply"], {})
equal("second run: nothing to apply, nothing to fill", [py.rec["second"]["apply"], py.rec["second"]["fill"]], [{}, {}])
ed = py.rec["edited"]
equal("edited file: the valid values win", ed["apply"], {"showCpu": True, "warnTemp": 95, "statOrder": "net,cpu,ram,temp,freq,bat,fan"})
equal("edited file: the invalid values are reported", sorted(ed["bad"]), ["net_show", "refreshMs"])
check("edited file: only absent keys are filled", "cpu_show" not in ed["fill"] and "ram_show" in ed["fill"])
snap = ini(py.snap.get("edited", ""))
equal("edited file: garbage is left as the user wrote it", [snap["Metrics"]["net_show"], snap["Main"]["refreshMs"]], ["maybe", "abc"])
equal("edited file: valid values stay", [snap["Metrics"]["cpu_show"], snap["Main"]["order"]], ["true", "net cpu"])
equal("edited file: a foreign section survives", snap.get("Foreign"), {"k": "v"})
w = ini(py.snap.get("written", ""))
equal("a GUI write sets the key", w["Main"]["maxLength"], "300")
equal("a GUI write keeps the rest", [w["Metrics"]["cpu_show"], w["Main"]["refreshMs"], w["Main"]["order"], w.get("Foreign")],
      ["true", "abc", "net cpu", {"k": "v"}])

print()
print("%d checks passed, %d failed" % (passed, len(failures)))
if failures:
    print("FAILED: " + "; ".join(failures[:10]) + (" ..." if len(failures) > 10 else ""))
    sys.exit(1)
print("PASS")
