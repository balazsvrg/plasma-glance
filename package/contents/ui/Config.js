.pragma library

// Settings file (~/.config/glancerc): the pure part. Nothing here touches the file or QML properties; main.qml owns
// the QtCore.Settings objects and calls these functions.
//
// The file is an INI with three sections, written and read through one QtCore.Settings object per section. Every
// key is a plain string there ("true", "42", "cpu ram temp"): Settings cannot tell an absent key from a default
// value of another type, and this file has to (an absent key is filled from the widget's current setting, which
// migrates the settings an older version saved in Plasma's own config). So all parsing and checking is done here.
//
//   [Main]     order, fahrenheit, warnTemp, refreshMs, maxLength
//   [Metrics]  <id>_show, <id>_popup and the stat's options (<id>_<option>), generated from the registry
//   [Graphs]   <id>_panelGraph, <id>_popupGraph, panelStyle, chartStyle, historySeconds
//
// The section is not called General: QSettings treats that name as its default group and would write it as
// [%General].
// Key names double as QML property names, so they are identifiers: letters, digits and underscores.
// Startup: plan() compares the file with the widget's settings (main.xml keys). A valid file value wins and is applied
// to the widget; an absent key is written from the widget's current value; an invalid value is left alone in the file
// and the widget keeps its value. Runtime: a changed setting is written with toIni().

var SECTIONS = ["Main", "Metrics", "Graphs"]

// The settings that belong to no stat. cfg is the main.xml key, type "bool" | "int" | "order".
var GENERAL = [
    { section: "Main", name: "order",           cfg: "statOrder",       type: "order", def: "cpu,ram,temp,freq,net,bat,fan" },
    { section: "Main", name: "fahrenheit",      cfg: "useFahrenheit",   type: "bool",  def: false },
    { section: "Main", name: "warnTemp",        cfg: "warnTemp",        type: "int",   def: 80,   min: 30,  max: 120 },
    { section: "Main", name: "refreshMs",       cfg: "refreshMs",       type: "int",   def: 1000, min: 250, max: 10000 },
    { section: "Main", name: "maxLength",       cfg: "maxLength",       type: "int",   def: 0,    min: 0,   max: 5000 },
    // Counter of settings changes (see plan): the widget bumps it with every change, in Plasma's config and in the file.
    { section: "Main",    name: "rev",             cfg: "settingsRev",     type: "int",   def: 0,    min: 0,   max: 2147483647 },
    { section: "Graphs",  name: "panelStyle",      cfg: "panelGraphStyle", type: "int",   def: 1,    min: 0,   max: 2 },
    { section: "Graphs",  name: "chartStyle",      cfg: "chartStyle",      type: "int",   def: 1,    min: 0,   max: 2 },
    { section: "Graphs",  name: "historySeconds",  cfg: "historySeconds",  type: "int",   def: 60,   min: 30,  max: 300 }
]

// Every setting that lives in the file, from the registry (Metrics.js METRICS) plus GENERAL.
function schema(metrics) {
    var out = GENERAL.slice()
    for (var i = 0; i < metrics.length; ++i) {
        var m = metrics[i], k = m.keys, d = m.defaults || {}
        if (k.show)  out.push({ section: "Metrics", name: m.id + "_show",  cfg: k.show,  type: "bool", def: !!d.show })
        if (k.popup) out.push({ section: "Metrics", name: m.id + "_popup", cfg: k.popup, type: "bool", def: !!d.popup })
        var opts = k.options || {}
        for (var o in opts)
            out.push({ section: "Metrics", name: m.id + "_" + o, cfg: opts[o], type: "bool",
                       def: !!(d.options && d.options[o]) })
        // a stat without graph keys simply has no graph entries
        if (k.gp) out.push({ section: "Graphs", name: m.id + "_panelGraph", cfg: k.gp, type: "bool", def: !!d.gp })
        if (k.gd) out.push({ section: "Graphs", name: m.id + "_popupGraph", cfg: k.gd, type: "bool", def: !!d.gd })
    }
    return out
}

function entriesOf(sch, section) {
    var out = []
    for (var i = 0; i < sch.length; ++i) if (sch[i].section === section) out.push(sch[i])
    return out
}

// QML source of one Settings object for a section (for Qt.createQmlObject): one string property per key.
// `location` is a file:// URL. A key is "" until the file says otherwise.
function settingsSource(location, section, sch) {
    var src = "import QtCore\nSettings {\n    location: " + JSON.stringify(location) +
              "\n    category: " + JSON.stringify(section) + "\n"
    var es = entriesOf(sch, section)
    for (var i = 0; i < es.length; ++i) src += "    property string " + es[i].name + ': ""\n'
    return src + "}\n"
}

// ---- values ----
// The widget stores the order comma-separated, the file space-separated (an unquoted comma would be read as a list).
function orderToIni(cfgOrder) {
    return String(cfgOrder).split(",").join(" ")
}

// The raw file text as a widget value, or undefined when it is not a valid value of the entry.
// ids: the stat ids, for the order (an unknown id is ignored, a missing one is appended in default order).
function parse(entry, raw, ids) {
    var t = String(raw === undefined || raw === null ? "" : raw).replace(/^\s+|\s+$/g, "")
    if (t === "") return undefined
    switch (entry.type) {
    case "bool": {
        var b = t.toLowerCase()
        if (b === "true" || b === "1") return true
        if (b === "false" || b === "0") return false
        return undefined
    }
    case "int": {
        if (!/^-?\d+$/.test(t)) return undefined
        var n = Number(t)
        if (entry.min !== undefined && n < entry.min) return undefined
        if (entry.max !== undefined && n > entry.max) return undefined
        return n
    }
    case "order": {
        var seen = [], parts = t.split(/[\s,]+/), valid = 0
        for (var i = 0; i < parts.length; ++i)
            if (ids.indexOf(parts[i]) >= 0 && seen.indexOf(parts[i]) < 0) { seen.push(parts[i]); valid++ }
        if (valid === 0) return undefined
        for (var j = 0; j < ids.length; ++j) if (seen.indexOf(ids[j]) < 0) seen.push(ids[j])
        return seen.join(",")
    }
    }
    return undefined
}

// A widget value as the file text.
function toIni(entry, value) {
    if (entry.type === "order") return orderToIni(value)
    if (entry.type === "bool") return value ? "true" : "false"
    return String(value)
}

// Startup plan. raw: ini name -> text in the file ("" when absent); cfg: main.xml key -> the widget's current value.
//   apply  { cfgKey: value }  valid file values that differ from the widget's value: write them to the widget
//   fill   { iniName: text }  keys to write into the file: the absent ones (empty text) from the widget's value
//   bad    [iniName]          keys whose file text is not valid (left alone; the widget keeps its value)
//   stale  true               the file missed writes (see below): the widget's values win and everything is filled
// The change counter: every change of a setting raises `settingsRev` in the widget's own config and `rev` in the file.
// A file whose rev is lower than the widget's did not receive the last writes (read-only file, full disk, killed in the
// second between the change and the write), so at startup the widget's values win and are written to the file. An equal
// or higher rev (hand edits do not touch it; another instance may have written) lets the file win.
function plan(sch, raw, cfg, ids) {
    var apply = {}, fill = {}, bad = [], i, e, text
    var revEntry = null
    for (i = 0; i < sch.length; ++i) if (sch[i].cfg === "settingsRev") revEntry = sch[i]
    var fileRev = revEntry ? parse(revEntry, raw[revEntry.name], ids) : undefined
    var stale = fileRev !== undefined && fileRev < (Number(cfg.settingsRev) || 0)
    for (i = 0; i < sch.length; ++i) {
        e = sch[i]
        text = raw[e.name]
        if (stale) { fill[e.name] = toIni(e, cfg[e.cfg]); continue }
        var empty = text === undefined || text === null || String(text).replace(/^\s+|\s+$/g, "") === ""
        if (empty) { fill[e.name] = toIni(e, cfg[e.cfg]); continue }
        var v = parse(e, text, ids)
        if (v === undefined) { bad.push(e.name); continue }
        if (v !== cfg[e.cfg]) apply[e.cfg] = v
    }
    return { apply: apply, fill: fill, bad: bad, stale: stale }
}
