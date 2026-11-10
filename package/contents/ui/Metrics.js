.pragma library

// Metrics registry: one declarative entry per stat, plus the pure helpers that turn an entry's
// templates into panel / popup text.
//
// STATUS: main.qml takes its panel text (statText, verticalLines), its horizontal width reserves, its alerts,
// its graph scales, its graph histories (one per series) and its plain sensors (one per `sensors` entry, polled
// when sensorActive says so) from this file, and reads the graph and popup flags through keys.gp / keys.gd /
// keys.popup; the rest of a descriptor (the other keys, popup rows) is not used by the widget yet and is checked against it by tests/metrics_test.py. This is a .pragma library: the
// functions are pure and see no QML properties, so the caller passes every setting in through ctx and every
// value through vals.
//
// Descriptor fields (a field is present only when the stat needs it):
//   id        short id used in statOrder ("cpu", "ram", ...)
//   name      label in the Metrics table and in the maximum-length notice
//   keys      config keys (main.xml names): show, popup, gp (panel graph), gd (popup graph),
//             options (extra per-stat settings, name -> key), hidden (keys the widget writes itself)
//   defaults  main.xml defaults for those keys (same shape as keys)
//   sensors   name -> { id, gate, expanded, noRateLimit }: sensor ids and when each is polled.
//             gate is "show", "popup", "show|popup" or "opt:<key>"; expanded:true also needs the popup open
//   source    only when values do not come from plain sensors: { kind: "dataengine" | "discovered", ... }
//   panel     full / compact: horizontal templates; vertical / verticalCompact: arrays of line templates
//             (verticalCompact only where the vertical panel may shorten the value, see statCompact);
//             sample / verticalSample: the widest value set (width reserve); sampleBits: net in bits mode;
//             reserveCtx: settings overridden when the horizontal reserve is rendered (net: bytes)
//   scale     graph scale: { from, to } fixed, { from, to: function(ctx) }, or a scale that follows the data:
//             { from, mode: "peak" | "decay", floor, decay, observe, needsGraph } where
//               observe     { keys, combine, barCombine }: the vals keys the scale watches (combine "max" or
//                           "sum" when there are several; barCombine replaces combine when bars are drawn)
//               needsGraph  true: the scale is only followed while a graph of the stat is enabled
//               trigger     name of the sensor (a key of `sensors`) whose update steps the peak, once per refresh
//                           (a stat without one, the fan, steps from its own value change)
//   alert     function(vals, ctx) -> bool: the panel text turns red
//   series    keys of vals drawn as graph series ([value] or [down, up]): one history per series
//   popup     rows: [{ label, value, when, alert, decoration }], graph: bool, graphWhen, hooks: names of bespoke parts,
//             repeat: one line per item (per-core temperatures), available: name of a hardware check ("hasBattery",
//             "hasFan") the stat's popup also needs. when / graphWhen / repeat.when name a flag: "popup" (keys.popup)
//             or an option name (keys.options); no when means the row is shown whenever the stat's popup is.
//             alert is "panel" (the panel's rule) or a function(vals, ctx). decoration "fanIcon" puts the fan icon
//             before the value. graphAfter: index of the row the graph follows (default: after the last row).
//             repeat: { when, countSensor, header, label, sensor, value, alert }, "{n}" is the item index in
//             sensor and index + 1 in label.
// Template syntax: "{key:format}" (see FORMATS); any other text is copied as is.

var DEFAULT_ORDER = ["cpu", "ram", "temp", "freq", "net", "bat", "fan"]

function isNum(v) {
    return v !== undefined && v !== null && v !== "" && isFinite(Number(v))
}

// ---- formatters (settings come in through ctx) ----
function rateParts(v, ctx) {
    var bits = !!(ctx && ctx.netBits)
    var x = bits ? Number(v) * 8 : Number(v)
    var units = bits ? ["b", "Kb", "Mb", "Gb"] : ["B", "KB", "MB", "GB"]
    var i = 0
    while (x >= 999.5 && i < 3) { x /= 1000; i++ }       // 999.6 would round to "1000"
    return { n: (x >= 9.95 || i === 0) ? String(Math.round(x)) : x.toFixed(1), unit: units[i] }
}
function tempNumber(v, ctx) {
    return isNum(v) ? String(Math.round(ctx && ctx.useF ? v * 9 / 5 + 32 : v)) : "--"
}

var FORMATS = {
    raw:       function (v) { return String(v) },
    pct:       function (v) { return isNum(v) ? Math.round(v) + "%" : "--%" },
    gib:       function (v) { return isNum(v) ? (v / 1073741824).toFixed(1) + " GiB" : "-- GiB" },
    wh:        function (v) { return isNum(v) ? Number(v).toFixed(1) + " Wh" : "-- Wh" },
    // "  (12.3 Wh)" after the battery value, empty when the energy is unknown
    whParen:   function (v) { return isNum(v) ? "  (" + Number(v).toFixed(1) + " Wh)" : "" },
    temp:      function (v, ctx) { return tempNumber(v, ctx) + (ctx && ctx.useF ? "°F" : "°C") },
    tempShort: function (v, ctx) { return tempNumber(v, ctx) + "°" },
    ghz:       function (v) { return isNum(v) ? (v / 1000).toFixed(1) : "--" },
    freq:      function (v) { return isNum(v) ? (v / 1000).toFixed(1) + " GHz" : "-- GHz" },
    freqShort: function (v) { return isNum(v) ? (v / 1000).toFixed(1) + "G" : "--G" },
    rate:      function (v, ctx) { if (!isNum(v)) return "--"; var p = rateParts(v, ctx); return p.n + " " + p.unit + "/s" },
    rateShort: function (v, ctx) { if (!isNum(v)) return "--"; var p = rateParts(v, ctx); return p.n + p.unit.charAt(0) },
    bytes:     function (v) {
        if (!isNum(v)) return "--"
        var x = Number(v)
        if (x >= 1e9) return (x / 1e9).toFixed(1) + " GB"
        if (x >= 1e6) return (x / 1e6).toFixed(1) + " MB"
        return Math.round(x / 1e3) + " KB"
    },
    rpm:       function (v) { return isNum(v) ? String(Math.round(Number(v))) : "--" },
    // battery state: 1 charging, -1 discharging, 0 other
    arrow:     function (v) { return v > 0 ? "↑" : (v < 0 ? "↓" : "") },
    arrowSp:   function (v) { return v > 0 ? " ↑" : (v < 0 ? " ↓" : "") }
}

// Renders "{key:format}" templates. A key missing from vals renders "--"; a format name that does not
// exist throws (a typo in a descriptor must not turn into silent text). A template is split into its parts
// once and kept (the panel renders the same few templates on every sensor update).
var PARSED = Object.create(null)      // no inherited keys, so a template named like an Object method is safe
function parse(template) {
    var t = String(template), cached = PARSED[t]
    if (cached) return cached
    var parts = [], re = /\{(\w+)(?::(\w+))?\}/g, last = 0, m
    while ((m = re.exec(t)) !== null) {
        if (m.index > last) parts.push(t.slice(last, m.index))
        parts.push({ key: m[1], fmt: m[2], src: t })
        last = re.lastIndex
    }
    if (last < t.length) parts.push(t.slice(last))
    PARSED[t] = parts
    return parts
}
function render(template, vals, ctx) {
    var parts = parse(template), out = ""
    for (var i = 0; i < parts.length; ++i) {
        var p = parts[i]
        if (typeof p === "string") { out += p; continue }
        if (!vals || !(p.key in vals)) { out += "--"; continue }
        var f = p.fmt ? FORMATS[p.fmt] : FORMATS.raw
        if (!f) throw new Error("unknown format '" + p.fmt + "' in template: " + p.src)
        out += f(vals[p.key], ctx)
    }
    return out
}
function renderLines(templates, vals, ctx) {
    var out = []
    for (var i = 0; i < templates.length; ++i) out.push(render(templates[i], vals, ctx))
    return out
}

// ---- the registry ----
var METRICS = [
    {
        id: "cpu", name: "CPU usage",
        keys: { show: "showCpu", popup: "popupCpu", gp: "graphPanelCpu", gd: "graphPopupCpu" },
        defaults: { show: true, popup: true, gp: false, gd: false },
        sensors: { value: { id: "cpu/all/usage", gate: "show|popup" } },
        panel: {
            full: "CPU {value:pct}", compact: "C {value:pct}",
            vertical: ["CPU", "{value:pct}"],
            sample: { value: 100 }
        },
        scale: { from: 0, to: 100 },
        series: ["value"],
        popup: { rows: [{ label: "CPU usage", value: "{value:pct}" }], graph: true }
    },
    {
        id: "ram", name: "Memory",
        keys: { show: "showRam", popup: "popupMemory", gp: "graphPanelRam", gd: "graphPopupRam" },
        defaults: { show: true, popup: true, gp: false, gd: false },
        sensors: {
            value: { id: "memory/physical/usedPercent", gate: "show|popup" },
            used:  { id: "memory/physical/used", gate: "popup", expanded: true },
            total: { id: "memory/physical/total", gate: "popup", expanded: true }
        },
        panel: {
            full: "RAM {value:pct}", compact: "R {value:pct}",
            vertical: ["RAM", "{value:pct}"],
            sample: { value: 100 }
        },
        scale: { from: 0, to: 100 },
        series: ["value"],
        popup: { rows: [{ label: "Memory", value: "{used:gib} / {total:gib} ({value:pct})" }], graph: true }
    },
    {
        id: "temp", name: "CPU temperature",
        keys: {
            show: "showTemp", popup: "popupTempAvg", gp: "graphPanelTemp", gd: "graphPopupTemp",
            options: { popupMax: "popupTempMax", popupCores: "popupCores" }
        },
        defaults: {
            show: true, popup: true, gp: false, gd: false,
            options: { popupMax: true, popupCores: true }
        },
        sensors: {
            value:     { id: "cpu/all/averageTemperature", gate: "show|popup" },
            max:       { id: "cpu/all/maximumTemperature", gate: "opt:popupMax", expanded: true },
            coreCount: { id: "cpu/all/coreCount", gate: "opt:popupCores", expanded: true, noRateLimit: true }
        },
        panel: {
            full: "{value:temp}", compact: "{value:tempShort}",
            vertical: ["Temp", "{value:temp}"], verticalCompact: ["Temp", "{value:tempShort}"],
            sample: { value: 100 }
        },
        // 20 .. max(100, warning temperature + 10)
        scale: { from: 20, to: function (ctx) { return Math.max(100, ctx.warnTempC + 10) } },
        alert: function (vals, ctx) { return isNum(vals.value) && vals.value >= ctx.warnTempC },
        series: ["value"],
        popup: {
            rows: [
                { label: "CPU temp (avg)", value: "{value:temp}", when: "popup", alert: "panel" },
                { label: "CPU temp (max core)", value: "{max:temp}", when: "popupMax",
                  alert: function (vals, ctx) { return isNum(vals.max) && vals.max >= ctx.warnTempC } }
            ],
            graph: true, graphWhen: "popup", graphAfter: 0,   // the graph needs the average row and sits under it
            // One sensor per core, "cpu/cpu<N>/temperature", N = 0 .. coreCount - 1
            repeat: {
                hook: "perCore", when: "popupCores", countSensor: "coreCount",
                header: "Per core", label: "Core {n}", sensor: "cpu/cpu{n}/temperature", value: "{value:temp}",
                alert: function (vals, ctx) { return isNum(vals.value) && vals.value >= ctx.warnTempC }
            }
        }
    },
    {
        id: "freq", name: "CPU frequency",
        keys: { show: "showFreq", popup: "popupFreq", gp: "graphPanelFreq", gd: "graphPopupFreq" },
        defaults: { show: false, popup: false, gp: false, gd: false },
        sensors: {
            value: { id: "cpu/all/averageFrequency", gate: "show|popup" },
            min:   { id: "cpu/all/minimumFrequency", gate: "popup", expanded: true },
            max:   { id: "cpu/all/maximumFrequency", gate: "show|popup" }
        },
        panel: {
            full: "{value:freq}", compact: "{value:freqShort}",
            vertical: ["Freq", "{value:freq}"], verticalCompact: ["Freq", "{value:freqShort}"],
            sample: { value: 9900 }                // 9.9 GHz
        },
        // The hardware maximum is not a sensor: the scale grows to the highest "max" seen, never below 1 GHz.
        scale: { from: 0, mode: "peak", floor: 1000, trigger: "max", observe: { keys: ["max"] } },
        series: ["value"],
        popup: {
            rows: [
                { label: "CPU frequency", value: "{value:freq}" },
                { label: "Min / max", value: "{min:ghz} / {max:ghz} GHz" }
            ],
            graph: true
        }
    },
    {
        id: "net", name: "Network speed",
        keys: {
            show: "showNet", popup: "popupNet", gp: "graphPanelNet", gd: "graphPopupNet",
            options: { bits: "netBits" }
        },
        defaults: { show: false, popup: false, gp: false, gd: false, options: { bits: false } },
        sensors: {
            down:      { id: "network/all/download", gate: "show|popup" },
            up:        { id: "network/all/upload", gate: "show|popup" },
            downTotal: { id: "network/all/totalDownload", gate: "popup", expanded: true },
            upTotal:   { id: "network/all/totalUpload", gate: "popup", expanded: true }
        },
        panel: {
            full: "↓{down:rate} ↑{up:rate}", compact: "↓{down:rateShort} ↑{up:rateShort}",
            vertical: ["Net", "↓{down:rateShort}", "↑{up:rateShort}"],
            // The horizontal reserve is the bytes text "999 MB/s" in both unit modes (as main.qml reserves it):
            // reserveCtx overrides the settings when the reserve is rendered. Vertically the sample is
            // scaled in bits mode so it is the widest in either unit.
            sample: { down: 999e6, up: 999e6 },
            reserveCtx: { netBits: false },
            sampleBits: { down: 999e6 / 8, up: 999e6 / 8 }
        },
        // Rises at once to the highest rate, decays 1% per second, never below 100 KB/s. The decay is applied once
        // per sensor update with the refresh interval as the elapsed time (dtMs of nextPeak). Bar graphs stack
        // download and upload, so they observe the sum; the line graph the higher one. Only followed while a
        // net graph is enabled.
        scale: {
            from: 0, mode: "decay", floor: 100000, decay: 0.99, needsGraph: true, trigger: "down",
            observe: { keys: ["down", "up"], combine: "max", barCombine: "sum" }
        },
        series: ["down", "up"],
        popup: {
            rows: [
                { label: "Download", value: "{down:rate}  ({downTotal:bytes} total)" },
                { label: "Upload", value: "{up:rate}  ({upTotal:bytes} total)" }
            ],
            graph: true
        }
    },
    {
        id: "bat", name: "Battery",
        keys: {
            show: "showBat", popup: "popupBat", gp: "graphPanelBat", gd: "graphPopupBat",
            options: { separate: "batSeparate" }, hidden: { count: "batteryCount" }
        },
        defaults: {
            show: false, popup: false, gp: false, gd: false,
            options: { separate: false }, hidden: { count: 0 }
        },
        // Plasma's power-management engine, not ksystemstats (see architecture.md, section 9).
        // "Battery" is the combined summary; the sources it lists are the individual batteries,
        // connected only while the popup shows the battery.
        source: {
            kind: "dataengine", engine: "powermanagement", summary: "Battery", intervalMs: 5000,
            fields: { percent: "Percent", state: "State", energy: "Energy", remaining: "Remaining msec",
                      capacity: "Capacity", name: "Pretty Name", sources: "Sources", present: "Has Battery" },
            perItem: "sources", perItemWhen: "popup"
        },
        sensors: {},
        panel: {
            full: "BAT {percent:pct}{state:arrowSp}", compact: "B {percent:pct}{state:arrow}",
            vertical: ["Bat", "{percent:pct}{state:arrowSp}"], verticalCompact: ["Bat", "{percent:pct}{state:arrow}"],
            // The horizontal reserve ("BAT 100% " plus the down arrow) uses the discharging state; the vertical sample the charging one.
            sample: { percent: 100, state: -1 },
            verticalSample: { percent: 100, state: 1 }
        },
        scale: { from: 0, to: 100 },
        // Red when below 15% and not charging.
        alert: function (vals) { return isNum(vals.percent) && vals.percent < 15 && vals.state <= 0 },
        series: ["percent"],
        popup: {
            rows: [{ label: "Battery", value: "{percent:pct}{state:arrowSp}{energy:whParen}", alert: "panel" }],
            graph: true, available: "hasBattery",
            // per-battery lines ("each battery separately"), and the charging / time-left row
            hooks: ["perBattery", "chargeRow"]
        }
    },
    {
        id: "fan", name: "Fan speed",
        keys: {
            show: "showFan", popup: "popupFan", gp: "graphPanelFan", gd: "graphPopupFan",
            options: { animate: "fanAnimate" }, hidden: { count: "fanCount" }
        },
        defaults: {
            show: false, popup: false, gp: false, gd: false,
            options: { animate: true }, hidden: { count: 0 }
        },
        // The sensor id contains the chip name, so fans are found by scanning the sensor tree.
        source: {
            kind: "discovered", pattern: "^lmsensors/[^/]+/fan\\d+$", combine: "max",
            firstScanMs: 800, retryMs: 3000, maxAttempts: 10
        },
        sensors: {},
        panel: {
            full: "{value:rpm} RPM", compact: "{value:rpm}",
            vertical: ["Fan", "{value:rpm}"],
            sample: { value: 9999 },
            decoration: "fanIcon"                 // spinning icon before the text (and its width in the reserve)
        },
        // Grows to the highest RPM seen, never below 3000.
        scale: { from: 0, mode: "peak", floor: 3000, observe: { keys: ["value"] } },
        series: ["value"],
        popup: {
            rows: [{ label: "Fan", value: "{value:rpm} RPM", decoration: "fanIcon" }],
            graph: true, available: "hasFan"
        }
    }
]

function byId(id) {
    for (var i = 0; i < METRICS.length; ++i) if (METRICS[i].id === id) return METRICS[i]
    return null
}

// ---- panel text ----
// The worst-case value set for a kind of text: "horizontal" or "vertical".
function sampleVals(m, vertical, ctx) {
    var p = m.panel
    if (!vertical) return p.sample
    return ctx && ctx.netBits && p.sampleBits ? p.sampleBits : (p.verticalSample || p.sample)
}
// The lines of a stat on a vertical panel (caption first).
function verticalLines(m, compact, vals, ctx) {
    return renderLines(compact && m.panel.verticalCompact ? m.panel.verticalCompact : m.panel.vertical, vals, ctx)
}
// The text a stat reserves its width for horizontally (main.qml measures it with TextMetrics).
function reserveText(m, compact, ctx) {
    var c = {}, k
    for (k in ctx) c[k] = ctx[k]
    for (k in m.panel.reserveCtx) c[k] = m.panel.reserveCtx[k]
    return panelText(m, compact, false, m.panel.sample, c)
}
// The text of a stat in the panel (statText() in main.qml).
function panelText(m, compact, vertical, vals, ctx) {
    if (vertical) return verticalLines(m, compact, vals, ctx).join("\n")
    return render(compact ? m.panel.compact : m.panel.full, vals, ctx)
}

// ---- graph scale and alert ----
// The lower end of the scale.
function scaleFrom(m) {
    return m.scale.from
}
// The upper end of the scale for a fixed or computed scale.
function scaleTo(m, ctx) {
    var s = m.scale
    return typeof s.to === "function" ? s.to(ctx) : s.to
}
// Whether the scale follows the data (its upper end is a peak kept by the caller, see stepPeak).
function followsData(m) {
    return !!m.scale.mode
}
// The upper end of any scale: a following scale ends at the caller's current `peak`.
function scaleEnd(m, ctx, peak) {
    return followsData(m) ? peak : scaleTo(m, ctx)
}
// The value a following scale watches, from the live vals: the numeric ones of scale.observe.keys (a missing or
// non-numeric one counts as 0), combined by the max or the sum (ctx.barChart picks barCombine when there is one).
function observed(scale, vals, ctx) {
    var o = scale.observe, how = ctx && ctx.barChart && o.barCombine ? o.barCombine : (o.combine || "max"), acc = 0
    for (var i = 0; i < o.keys.length; ++i) {
        var v = vals ? vals[o.keys[i]] : undefined
        v = isNum(v) ? Number(v) : 0
        acc = how === "sum" ? acc + v : Math.max(acc, v)
    }
    return acc
}
// One step of a following scale ("peak" never falls, "decay" falls by `decay` per second). `observed` is the
// value just seen (undefined or non-numeric: nothing seen); `dtMs` is the time that passed since the previous step.
function nextPeak(scale, prev, observed, dtMs) {
    var seen = isNum(observed) ? Number(observed) : 0
    var p = scale.mode === "decay" ? prev * Math.pow(scale.decay, dtMs / 1000) : prev
    return Math.max(scale.floor, seen, p)
}
// The caller's peak after a sensor update: `prev` when the stat's graph is not enabled and the scale needs one
// (ctx.graphOn), otherwise nextPeak of what the scale watches. ctx also carries barChart. The peak itself is
// state of the caller (main.qml keeps it per stat); this function is pure.
function stepPeak(m, prev, vals, ctx, dtMs) {
    if (m.scale.needsGraph && !(ctx && ctx.graphOn)) return prev
    return nextPeak(m.scale, prev, observed(m.scale, vals, ctx), dtMs)
}
// Whether the stat's panel text (and graph colour) is in its alert state.
function alertOf(m, vals, ctx) {
    return !!m.alert && !!m.alert(vals, ctx)
}

// ---- sensors ----
// Every plain sensor of every stat, in registry order: [{ id: <stat id>, name: <key of the stat's sensors> }].
function sensorKinds() {
    var list = []
    for (var i = 0; i < METRICS.length; ++i)
        for (var name in METRICS[i].sensors) list.push({ id: METRICS[i].id, name: name })
    return list
}

// The names of a stat's sensors the panel reads (those polled for the strip, gate "show" or "show|popup"); the
// popup-only ones are left out of the values the panel text, alert and scale bindings depend on.
function panelSensorNames(m) {
    var names = []
    for (var name in m.sensors) if (m.sensors[name].gate.indexOf("show") === 0) names.push(name)
    return names
}

// ---- popup ----
// Flags: { popup: bool, opts: { <option name>: bool }, available: { hasBattery: bool, hasFan: bool } }.
function flagOn(flag, flags) {
    if (flag === undefined) return true
    return flag === "popup" ? !!flags.popup : !!(flags.opts && flags.opts[flag])
}
// The flags (other than "popup") whose options show something in the stat's popup.
function popupFlagNames(m) {
    var names = [], p = m.popup
    for (var i = 0; i < p.rows.length; ++i) if (p.rows[i].when) names.push(p.rows[i].when)
    if (p.repeat && p.repeat.when) names.push(p.repeat.when)
    return names
}
// Whether the stat has anything in the popup: its popup flag, or an option that shows a row (temperature), and
// the hardware check the descriptor names.
function popupOn(m, flags) {
    var p = m.popup
    if (p.available && !(flags.available && flags.available[p.available])) return false
    if (flags.popup) return true
    var names = popupFlagNames(m)
    for (var i = 0; i < names.length; ++i) if (flagOn(names[i], flags)) return true
    return false
}
function popupRowShown(row, flags) { return flagOn(row.when, flags) }
// How many rows come before the graph.
function popupRowsBeforeGraph(m) {
    var p = m.popup
    return p.graphAfter === undefined ? p.rows.length : p.graphAfter + 1
}
function popupGraphShown(m, flags) { return !!m.popup.graph && flagOn(m.popup.graphWhen, flags) }
// Every label the popup's name column can show (its width is the widest).
function popupLabels(list) {
    var labels = []
    for (var i = 0; i < list.length; ++i) {
        var p = list[i].popup
        for (var j = 0; j < p.rows.length; ++j) labels.push(p.rows[j].label)
        if (p.repeat) labels.push(p.repeat.label.replace("{n}", "10"))
    }
    return labels
}

// ---- sensor gating ----
// Whether a sensor is polled. flags: { show, popup, expanded, opts: { <option name>: bool } }.
function sensorActive(sensor, flags) {
    if (sensor.expanded && !flags.expanded) return false
    var g = sensor.gate
    if (g === "show|popup") return !!(flags.show || flags.popup)
    if (g === "show") return !!flags.show
    if (g === "popup") return !!flags.popup
    if (g.indexOf("opt:") === 0) return !!(flags.opts && flags.opts[g.slice(4)])
    throw new Error("unknown sensor gate '" + g + "'")
}
