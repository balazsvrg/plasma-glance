import QtQuick
import QtCore
import org.kde.plasma.plasmoid
import "Metrics.js" as M
import "Config.js" as C

// The settings file, ~/.config/glancerc (the pure rules are in Config.js).
//
// At startup the file is read once: valid values are applied to the widget's settings (Plasmoid.configuration, which
// the settings pages and the rest of the widget keep using), keys the file lacks are filled from the widget's
// current values (this also migrates the settings an older version saved in Plasma's own config), invalid values are
// left alone. A file that missed writes (its rev is behind the widget's) is overwritten from the widget instead.
// After that every change of a setting (settings dialog, edge drag, Defaults button) is written to
// the file. Nothing watches the file: an edit made while the widget runs is read after the next reload, and
// a later change of a setting in the same section overwrites it.
Item {
    id: file

    readonly property var schema: C.schema(M.METRICS)
    readonly property var stat_ids: M.METRICS.map(function(m) { return m.id })
    readonly property string path: String(StandardPaths.writableLocation(StandardPaths.GenericConfigLocation)) + "/glancerc"   // a file:// URL
    // False until the startup read has been applied, so applying the file is not written straight back.
    property bool ready: false
    property var sections: ({})

    function raw() {
        var r = {}
        for (var i = 0; i < schema.length; ++i) r[schema[i].name] = sections[schema[i].section][schema[i].name]
        return r
    }

    function put(entry, text) {
        var s = sections[entry.section]
        if (s[entry.name] !== text) s[entry.name] = text
    }

    function start() {
        var made = {}
        for (var i = 0; i < C.SECTIONS.length; ++i)
            made[C.SECTIONS[i]] = Qt.createQmlObject(C.settingsSource(path, C.SECTIONS[i], schema), file, "settings")
        sections = made
        var byName = {}
        for (var j = 0; j < schema.length; ++j) byName[schema[j].name] = schema[j]
        var cfg = {}
        for (var k = 0; k < schema.length; ++k) cfg[schema[k].cfg] = Plasmoid.configuration[schema[k].cfg]
        var plan = C.plan(schema, raw(), cfg, stat_ids)
        for (var key in plan.apply) Plasmoid.configuration[key] = plan.apply[key]
        for (var name in plan.fill) put(byName[name], plan.fill[name])
        if (plan.stale) console.warn("Glance: " + path + " was behind the widget's settings (a write was lost); rewriting it")
        if (plan.bad.length > 0)
            console.warn("Glance: ignoring invalid values in " + path + ": " + plan.bad.join(", "))
        ready = true
    }

    // Every change raises the counter that start() compares with the file's (Config.js plan).
    function bump() { Plasmoid.configuration.settingsRev = Plasmoid.configuration.settingsRev + 1 }

    // One watcher per setting: Plasmoid.configuration[key] is reactive, so a change from anywhere lands here.
    Instantiator {
        model: file.schema
        delegate: QtObject {
            required property var modelData
            readonly property var value: Plasmoid.configuration[modelData.cfg]
            onValueChanged: if (file.ready) {
                file.put(modelData, C.toIni(modelData, value))
                if (modelData.cfg !== "settingsRev") file.bump()
            }
        }
    }

    // Settings objects made while their parent is still completing are not initialised yet: start afterwards.
    Component.onCompleted: Qt.callLater(start)
}
