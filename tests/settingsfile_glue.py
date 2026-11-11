#!/usr/bin/env python3
"""One run of the real SettingsFile.qml against a stand-in for Plasmoid.configuration (used by config_test.py).

    settingsfile_glue.py '<json>'   json: {"cfg0": {cfgKey: value}, "file": "<ini text>" | null, "changes": {cfgKey: value}}

Copies Metrics.js, Config.js and SettingsFile.qml to a temp dir (the plasmoid import replaced by a stub singleton whose
`configuration` is a QtObject with one property per settings key), points XDG_CONFIG_HOME at the temp dir, starts the
widget part, applies `changes` after 1.6 s, waits for the file to be written and prints
{"cfg": {...}, "ready": bool, "file": "<ini text>" | null} as one JSON line. Every run is its own process because
QSettings caches a file per process.
"""
import json
import os
import shutil
import sys
import tempfile

arg = json.loads(sys.argv[1])
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UI = os.path.join(ROOT, "package", "contents", "ui")
tmp = tempfile.mkdtemp(prefix="glue-")
xdg = os.path.join(tmp, "xdg")
os.makedirs(xdg)
os.environ["XDG_CONFIG_HOME"] = xdg
os.environ["QT_QPA_PLATFORM"] = "offscreen"
rc = os.path.join(xdg, "glancerc")
if arg.get("file") is not None:
    open(rc, "w").write(arg["file"])

for name in ("Metrics.js", "Config.js"):
    shutil.copy(os.path.join(UI, name), tmp)
sf = open(os.path.join(UI, "SettingsFile.qml"), encoding="utf-8").read()
assert "import org.kde.plasma.plasmoid" in sf
open(os.path.join(tmp, "SettingsFile.qml"), "w").write(sf.replace("import org.kde.plasma.plasmoid", 'import "stub"'))
os.makedirs(os.path.join(tmp, "stub"))
open(os.path.join(tmp, "stub", "qmldir"), "w").write("singleton Plasmoid 1.0 Plasmoid.qml\n")
open(os.path.join(tmp, "stub", "Plasmoid.qml"), "w").write("pragma Singleton\nimport QtQuick\nQtObject { property var configuration: null }\n")
open(os.path.join(tmp, "driver.qml"), "w").write("""
import QtQuick
import "Metrics.js" as M
import "Config.js" as C
import "stub"
Item {
    id: root
    property var sf
    Component.onCompleted: {
        var sch = C.schema(M.METRICS), cfg0 = JSON.parse(py.cfg0), src = "import QtQuick\\nQtObject {\\n"
        for (var i = 0; i < sch.length; ++i) {
            var e = sch[i]
            src += "property var " + e.cfg + ": " + JSON.stringify(cfg0.hasOwnProperty(e.cfg) ? cfg0[e.cfg] : e.def) + "\\n"
        }
        Plasmoid.configuration = Qt.createQmlObject(src + "}", root, "cfg")
        sf = Qt.createQmlObject("import QtQuick\\nSettingsFile {}", root, "sf")
    }
    Timer { interval: 1600; running: true; onTriggered: {
        var ch = JSON.parse(py.changes)
        for (var k in ch) Plasmoid.configuration[k] = ch[k]
    } }
    Timer { interval: 4000; running: true; onTriggered: {
        var sch = C.schema(M.METRICS), out = {}
        for (var i = 0; i < sch.length; ++i) out[sch[i].cfg] = Plasmoid.configuration[sch[i].cfg]
        py.finish(JSON.stringify(out), root.sf.ready)
    } }
}
""")

from PySide6.QtCore import Property, QObject, QTimer, QUrl, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

app = QGuiApplication([])
app.setOrganizationName("glance-test")
app.setApplicationName("glue")
result = {}


class Py(QObject):
    @Property(str, constant=True)
    def cfg0(self):
        return json.dumps(arg.get("cfg0", {}))

    @Property(str, constant=True)
    def changes(self):
        return json.dumps(arg.get("changes", {}))

    @Slot(str, bool)
    def finish(self, cfg, ready):
        result["cfg"] = json.loads(cfg)
        result["ready"] = ready
        QTimer.singleShot(2500, app.quit)        # let the delayed write reach the file


py = Py()
eng = QQmlApplicationEngine()
eng.rootContext().setContextProperty("py", py)
errors = []
eng.warnings.connect(lambda ws: errors.extend(w.toString() for w in ws))
eng.load(QUrl.fromLocalFile(os.path.join(tmp, "driver.qml")))
QTimer.singleShot(15000, app.quit)
app.exec()
result["file"] = open(rc).read() if os.path.exists(rc) else None
result["errors"] = errors
print(json.dumps(result))
shutil.rmtree(tmp, ignore_errors=True)
