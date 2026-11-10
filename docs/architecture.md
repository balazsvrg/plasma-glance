# Glance architecture

This document is for a developer who needs to change the widget. It describes how the code works today and
names functions and properties rather than line numbers, because line numbers drift. Search for the name.

Everything here was checked against the source in `package/`. Where a statement comes from a code comment or
from the author's notes and could not be checked by reading the code (measurements, runtime behaviour), it says so.

Contents

1. File map
2. Data flow
3. The `statOrder` model
4. The text pipeline and the width pipeline
5. The maximum-length system
6. The edge-drag handle
7. `syncLengthInfo` and the hidden config keys
8. Graphs
9. Battery
10. Fans: discovery and the icon
11. Sensor gating
12. Vertical panels
13. The settings pages
14. How to add a new stat
15. Pitfalls

---

## 1. File map

```
package/
  metadata.json                  plugin id org.local.cpumemtemp, name "Glance", version, Plasma/Applet
  contents/config/main.xml       every setting, its type and default (the kcfg schema)
  contents/config/config.qml     registers the three settings pages (ConfigCategory)
  contents/ui/main.qml           the whole widget: sensors, text, widths, strip, popup, drag handle
  contents/ui/configGeneral.qml  settings page: units, warning temperature, maximum length, refresh
  contents/ui/configMetrics.qml  settings page: the stat table (show/graph, order), fan/battery options
  contents/ui/configGraphs.qml   settings page: panel graph style, chart style, history length
  contents/ui/LengthNotice.qml   warning banner shown on the General and Metrics pages
  contents/ui/Metrics.js         registry that describes each stat as data; panel text and width reserves come from it
install.sh / uninstall.sh        kpackagetool6 wrappers (install or upgrade for the current user)
package.sh                       zips metadata.json + contents/ into dist/<id>-<version>.plasmoid
tests/metrics_test.py            checks the registry and its use in main.qml (python3 + PySide6, no Plasma needed)
tests/golden/                    the panel text of release v0.9.1 (panel_text.json) and the script that generated it
```

`contents/ui/Metrics.js` is a registry that describes each stat as data: its labels, settings keys and
defaults, sensors and when they are polled, panel text templates (full, compact, vertical), worst-case
samples, graph scale, alert rule and popup rows, plus the pure formatting helpers that render those templates.
`main.qml` takes its panel text and its horizontal width reserves (section 4), its alerts, scales and histories
(section 8) and its plain sensors (sections 2 and 11) from it; the settings pages and the popup rows still carry
their own copies of the rest, which the registry also describes and the tests compare with the code (section 14
lists what a new stat still needs).
`tests/metrics_test.py` checks the registry against the golden data in `tests/golden/`, which holds the exact
text the hand-written code of v0.9.1 produced, and checks how `main.qml` feeds it.

`metadata.json` keeps the plugin id `org.local.cpumemtemp` although the visible name is "Glance"; Plasma stores
the applet's settings under the id, so renaming it would reset them.

`main.qml` is a single `PlasmoidItem` (`root`). Besides the root it defines these inline components, all
used from `root`'s own scope:

| Component | Role |
|---|---|
| `FanDiscovery` | one-time lookup of `lmsensors/<chip>/fanN` sensors (section 10) |
| `History` | a `Loader` that owns one `HistoryProxySource` (section 8) |
| `Spark` | the small line or bar chart used by every graph |
| `FanIcon` | the three-blade fan, stepped animation |
| `PopupRow`, `PopupGraph` | popup building blocks (`PopupGraph` extends `Spark`) |
| `Divider`, `MetricCell` | declared inside `compactRepresentation`; the panel strip |

The runtime has three views: `compactRepresentation` (the panel strip, a `MouseArea` that toggles
`root.expanded` on click), `fullRepresentation` (the popup) and the tooltip (`toolTipMainText` /
`toolTipSubText: tooltipText()`). `preferredRepresentation` is `compactRepresentation`.

---

## 2. Data flow

Two sources feed the widget: `org.kde.ksysguard.sensors` (ksystemstats) for CPU, memory, temperature,
frequency, network and fan, and Plasma's `powermanagement` data engine for the battery.

```
 ksystemstats                                   powermanagement engine
 Sensors.Sensor { sensorId, enabled,            P5Support.DataSource { engine, connectedSources,
                  updateRateLimit: refreshMs }                         interval: 5000 }
        | .value                                        | data["Battery"], data["Battery0".."]
        |                                               v
        |   fan: FanDiscovery -> fanIds           batterySummary -> batPercent, batState
        |        -> Repeater of Sensors -> fanItems     |
        |        -> fanRpmMax() -> fanRpm, fanLevel     |
        v                                               v
   statVals(id) -------------------------------------- (the live values a stat's templates read)
        |
        +--> M.panelText(registry entry, compact, vertical, vals, textCtx)    (Metrics.js)
        |         |
        |         v
        |    statText(id, compact, vertical) --> MetricCell Label (panel)
        |                                    \-> tooltipText() (tooltip)
        |
        +--> History { statId, series, sensor, wanted } --Loader--> HistoryProxySource
                  |  one per registry series (historyItems; historySource is null while inactive)
                  v
             statHistory(id) / statHistory2(id) / statYFrom(id) / statYTo(id) / statLineColor(id)
             (statAlert(id) -> M.alertOf, statYFrom/To -> M.scaleFrom/scaleEnd, peaks -> M.stepPeak)
                  |
                  +--> Spark in MetricCell (behind text or inline)
                  +--> PopupGraph { statId } in a popup block

 Popup rows (PopupRow) do NOT use statText: they call the format helpers directly
 (pct, gib, freq, ghzNumber, rate, bytesText, temp, wh) on the sensor values. They are
 thin wrappers over `M.FORMATS` in `Metrics.js`, the same formatters the panel templates use.
```

The formatting helpers (`pct`, `temp`, `gib`, `rate`, `freq`, ...) test values with `isNum(v)`, which rejects `undefined`, `null`, `""` and `NaN`, so a
missing sensor shows `--` rather than a fake 0.

The plain sensors are created by one `Instantiator` (`sensorInst`) over `M.sensorKinds()`, one `Sensors.Sensor`
per entry of every registry descriptor's `sensors` (`ram.used`, `temp.max`, `net.downTotal`, ...). A delegate takes
its `sensorId` from the registry, uses `updateRateLimit: root.refreshMs` and `enabled: M.sensorActive(entry,
root.sensorFlags(id))` (section 11). `sensorItems` maps `"<stat id>.<name>"` to the created item; it is a property
that is reassigned on every `onObjectAdded`, so a lookup made before the items existed is made again once they do
(the same pattern as `reserveItems` and `historyItems`). `sensorOf(id, name)` and `sensorValue(id, name)` read it,
and `statVals(id)` returns every sensor of a plain-sensor stat under the sensor's name (`sensorVals`). The
exceptions are the fans (`fanRepeater` delegates) and the per-core temperatures (`perCore` delegates inside
`tempBlock`), which are created on demand. Every plain sensor uses `updateRateLimit: root.refreshMs`, including
`temp.coreCount`, which is constant. `refreshMs` is the setting clamped to at least 250.

---

## 3. The `statOrder` model

`statOrder` drives everything: the panel strip, the popup, the tooltip, which stats are dropped first and
the row order in the settings table.

- `defaultOrder` is `["cpu","ram","temp","freq","net","bat","fan"]`. It is the list of all stat ids.
- `statOrder` is `normalizeOrder(Plasmoid.configuration.statOrder)`. `normalizeOrder` splits the
  comma-separated string, keeps only ids found in `defaultOrder`, removes repeats, then appends any id that
  is missing. So a stat added in a later version appears at the end for existing users without migration.
- Per-stat predicates are `switch (id)` functions keyed by the stat id: `statShown`, `popupShown`, `statVals`
  (the live values the registry's templates and scales read: its own case for battery and fan, `sensorVals(id)`
  for the stats made of plain sensors) and `popupBlock`. Panel text, captions, samples and width reserves (section 4) and alerts, scales, histories and
  the graph flags (section 8) are not among them any more: they are looked up in the registry by id
  (`statAlert`, `statYFrom`, `statYTo`, `statHistory`, `statHistory2`, `statGraph`, `statPopupGraph`,
  `statPopupOn`, `statTextColor` and `statLineColor` are generic).
- `shownIds()` is `statOrder` filtered by `statShown`. For `bat` and `fan`, "shown" also needs the hardware
  (`batShown = showBat && hasBattery`, `fanShown = showFan && hasFan`).

### Panel

`compactRepresentation` contains a `GridLayout` (`layout`) holding a `Repeater` over `root.statOrder`. Each
delegate is a "slot", itself a small `GridLayout`:

```
layout (GridLayout: one row of statOrder.length + 1 columns; one column when vertical)
  Repeater over statOrder
    slot (GridLayout, visible: root.cellShown(id))
      Divider    visible: root.anyCellBefore(id)      1 px, opacity 0.3
      Loader     active: root.cellShown(id)  -> MetricCell { statId: id }
  Label "–"      visible: !root.anyCell()             placeholder (an en dash) when nothing is visible

MetricCell { statId }
  Spark                      behind the text, opacity 0.5, fills the cell  (cell.behind)
  GridLayout content
    FanIcon                  only when statId === "fan"
    Label                    text: root.statText(statId, root.statCompact(statId), vertical)
    Spark                    inline graph after the text                   (cell.inline)
```

`cellShown(id)` tests membership of `visibleIds`, which is `shownIds()` minus the stats dropped by the
maximum length. So hidden and dropped stats take no space and, because the `Loader` is inactive, build no
chart or icon. A `MetricCell` derives all its data from `statId` through the `stat*` helpers; it holds no
per-stat code except the `fan` flag (icon, and one more grid column).

The first visible slot has no divider (`anyCellBefore` is true only if the id's index in `visibleIds`
is above 0).

### Popup

`fullRepresentation` is a `ColumnLayout` with a `Repeater` over `statOrder`. Each delegate is a `Loader`
with `active: root.popupShown(modelData)` and `sourceComponent: root.popupBlock(modelData)`.
`popupBlock(id)` returns one of the `Component` blocks `cpuBlock`, `ramBlock`, `freqBlock`, `netBlock`,
`batBlock`, `fanBlock`, `tempBlock`. A block is a `ColumnLayout` of `PopupRow`s and a
`PopupGraph { statId: "..." }`. `PopupRow` uses a fixed-width name column (`popupLabelWidth`, the width of
the text "CPU temp (max core)"), so values line up between blocks. `fanBlock` builds its row by hand
because it holds a `FanIcon`. If no block is shown, a "Nothing to show" label appears (`anyPopupShown()`).

`popupShown("temp")` is true when any of `popupTempAvg`, `popupTempMax`, `popupCores` is on. For `bat` and
`fan` it uses `popupBatShown` / `popupFanShown`, which include the hardware check.

### Tooltip

`tooltipText()` walks `statOrder`, keeps `statShown` ids, and joins `statText(id, false, false)` with
`" · "`. It always uses the full horizontal text, even on a vertical panel, and it includes stats that the
maximum length dropped from the strip. Do not hard-code stat names or order anywhere else.

---

## 4. The text pipeline and the width pipeline

There is exactly one place that produces panel text, the registry (`Metrics.js`), and a small set of functions
in `main.qml` that look it up and measure it. The maximum-length calculation (`stripLength`, `computeFit`) and
the on-screen layout both call them, so the calculation can only drift from reality if somebody writes a panel
string somewhere else.

### Text: `statText(id, compact, vert)`

Each registry entry holds the templates of a stat (`panel.full`, `panel.compact`, `panel.vertical`,
`panel.verticalCompact`) as strings such as `"CPU {value:pct}"`, and the worst-case sample values
(`panel.sample`, `panel.verticalSample`, `panel.sampleBits`). `main.qml` renders them:

```
statText(id, compact, vert)
  m = M.byId(id)
  M.panelText(m, compact, vert, statVals(id), textCtx)
    vert  -> the vertical templates (caption line first), joined with "\n"
    horiz -> panel.full or panel.compact

verticalLines(id, compact, sample)     the vertical lines; sample = the worst-case values instead of the live ones
statVals(id)                           the live values the templates read: { value }, { down, up }, { percent, state }
```

Horizontal texts: `CPU 8%` / `C 8%`, `RAM`/`R`, `BAT 62% ↑` / `B 62%↑`, fan `2400 RPM` / `2400`, temp and
freq are value only, net `↓4.5 MB/s ↑3 KB/s` / `↓4.5M ↑3K`. A template is plain text with `{key:format}`
holes; the formats (`pct`, `temp`, `rate`, ...) are `M.FORMATS`, and the registry test pins every one of them
against golden data.

Why the bindings still track. `Metrics.js` is a `.pragma library`: its functions are pure and cannot see
`root`'s properties, so QML cannot track what they read. The caller therefore reads every input itself and
hands it in: the live values through `statVals(id)` (which reads the sensors inside the function that the
binding calls, so a changed sensor re-evaluates the binding as it always did) and the settings through
`textCtx`, a `readonly property var` on `root` (`{ useF, netBits }`). A binding that calls `statText` reads
`textCtx`, so flipping Fahrenheit or bits re-evaluates it. A formatter must read only settings that `textCtx`
carries (the test checks this); a new setting that changes text has to be added to `textCtx` first.

`sample` makes a stat render its widest value (100, 9900 MHz, 9999 RPM; net uses `999e6` bytes/s, divided by 8
in bits mode so it is the widest in either unit; the battery uses the charging state vertically and the
discharging one horizontally). That is what width measurements use.

`statCompact(id)` decides whether a stat's value text is shortened:

- horizontal: `lengthLevel >= 2` (the compact-text step of the maximum length);
- vertical: only for stats whose registry entry has `panel.verticalCompact` (`temp`, `freq`, `bat`), and only
  when that stat's own full text (`verticalWidth(id)`) is wider than `panelThickness - 2 * smallSpacing`.
  Shortening saves no length on a vertical panel, so it is never a length step there.

### Widths

| Function | Used for |
|---|---|
| `reservedWidth(id, compact)` | horizontal: the widest text of a stat, the width of its `TextMetrics` item |
| `verticalWidth(id)` | vertical: widest line of `verticalLines(id, false, true)` measured with `FontMetrics fm`; at least the icon size for stats with a `decoration` (`fan`) |
| `cellLength(id, level)` | space one stat takes along the panel at a step (width, or height when vertical) |
| `stripLength(level, drop)` | length of the whole strip at a step with the last `drop` stats removed |

Horizontal: the `Label` in a `MetricCell` has `Layout.minimumWidth` and `preferredWidth` equal to
`reservedWidth(statId, statCompact(statId))`, so the strip does not resize when a number gains a digit.
An `Instantiator` (`reserveInst`) creates one `TextMetrics` per registry entry and kind (full, compact), keyed
`"<id>"` and `"<id>C"` in `root.reserveItems`. Its `text` is `M.reserveText(entry, compact, root.textCtx)`: the
entry's `panel.sample` rendered with the same template as the panel, so the reserve cannot drift from the
format. Because `text` and `font` are bindings, the width is measured again when Fahrenheit or the font changes.
`reserveItems` is a property, so a width read before the items exist is read again when they do. The reserve
is `TextMetrics.width`, not `FontMetrics.advanceWidth`: they differ by a fraction of a pixel (the strip has
always been sized from the former). The net reserve is the bytes text `↓999 MB/s ↑999 MB/s` in both unit modes
(`panel.reserveCtx`), a long-standing quirk kept on purpose.

Vertical: `verticalWidth` measures the worst-case `verticalLines(..., true)` with `FontMetrics`
(`advanceWidth` is not bindable, so it starts with `void fm.font`; it reads `textCtx` through
`verticalLines`).

`cellLength` horizontal: `reservedWidth`, plus the fan icon (`iconSizes.smallMedium + smallSpacing`) for
a stat with a `decoration` (`hasIcon(id)`, the fan), plus `smallSpacing + inlineGraphWidth` (`gridUnit * 4`) for an inline graph.
`cellLength` vertical: line count (`verticalLines(id, false, true).length`) times `mLine.height`, plus the
icon size for a stat with a `decoration` (`fan`), plus `gridUnit` for an inline graph.

`stripLength(level, drop)` adds the cell lengths of the first `n = shown - drop` stats, then
`(n - 1) * (1 + 2 * gap)` (a 1 px divider and a gap on each side), rounds up, and adds a flat 1 px for layout
rounding. The gap is `spacingFor(level)` (largeSpacing, or smallSpacing at level 3) horizontally and
`rowSpacingFor(level)` (smallSpacing, or 0 at level 3) vertically. The extra 1 px was measured, per the code
comment ("seen as 1 px in every test, however many stats"), so the strip stays at or under the limit.

`inlineGraphsAt(level)` is `graphInline && level === 0`. This single rule feeds `cellLength`, `MetricCell`
(`behind` vs `inline`) and `syncLengthInfo`.

The model was verified with an overlay printing `layout.implicitWidth` next to
`stripLength(...)`; that is a manual test, not part of the repo.

---

## 5. The maximum-length system

`Plasmoid.configuration.maxLength` limits the strip along the panel (width, or height when vertical);
0 means no limit. When the strip would be longer, it saves space in steps and stops at the first step that
fits:

| Level | What changes | `spacingFor` / `rowSpacingFor` |
|---|---|---|
| 0 | full text, graphs as chosen | large / small |
| 1 | inline graphs become behind-text graphs (`inlineGraphsAt` is false), which take no length | large / small |
| 2 | compact text (`statCompact` true horizontally) | large / small |
| 3 | tight spacing | small / 0 |

If level 3 still does not fit, stats are dropped from the end of `shownIds()` one at a time
(`drop = 1, 2, ...`) at level 3; the first stat is never dropped.

- `levelList()` is `[0, 1, 2, 3]` horizontally and `[0, 1, 3]` vertically (step 2 saves no length there).
- `computeFit()` returns `{ level, drop }`. With `maxLength <= 0` or nothing shown it is `{0, 0}`.
  Otherwise it takes the first level in `levelList()` whose `stripLength(level, 0) <= maxLength`; failing
  that, the smallest `drop` for which `stripLength(3, drop) <= maxLength`; failing that, everything but the
  first stat (`drop = shown - 1`).
- `fit` is `dragging ? dragFit() : computeFit()`. `lengthLevel` is `fit.level`.
- `visibleIds` / `droppedIds` are `shownIds()` split at `shown - fit.drop`.
- `maxLength` (the root property) is `dragging ? dragMax() : Plasmoid.configuration.maxLength`, so while the
  handle is dragged, the readout and the calculation use the live value.
- `configs()` lists every layout the strip can take, longest to shortest: one entry per level in
  `levelList()` with no drops, then one per drop at level 3. Each entry is `{ level, drop, len }` with
  `len = stripLength(level, drop)`. The result is cached in `readonly property var layouts: configs()`.
  It depends only on settings (no live sensor values, because `cellLength` uses worst-case samples), so it
  is recomputed when settings change and not when a sensor ticks.

Hysteresis: for the saved limit there is none; `computeFit` is a pure function of the limit. The only
hysteresis is the halfway rule that applies while the handle is dragged (next section).

Settings pages do not recompute any of this. They read what the widget wrote (section 7).

---

## 6. The edge-drag handle

The context menu entry "Adjust length with the mouse" (`Plasmoid.contextualActions`, a checkable
`PlasmaCore.Action`; a `Binding` keeps `checked` in step with `root.adjusting`) shows a handle on the
strip's free edge. A 12 s `Timer` (`running: root.adjusting && !root.dragging`) switches adjust mode off
again.

State lives in `root`, not in the handle, so tests can drive it with temporary timers:
`adjusting`, `dragging`, `dragMoved`, `dragLength`, `dragCfg`, `handleAtStart`.

Which edge: `handleAtStart` is set by `compact.updateHandleSide()` from where the widget's centre sits in its
window: the far half of the panel (`x > width/2`, or `y > height/2` when vertical) means the widget is packed
toward the end, so the strip grows toward the start and the handle sits on the start edge. It is re-run on
`x/y/width/height` changes and on `onAdjustingChanged`, and it never flips during a drag.

The drag, in the order the handlers call it (`MouseArea grab` in the handle):

| Handler | Calls | What it does |
|---|---|---|
| `onPressed` | `beginDrag(startLength)` | `startLength` is the live `layout.implicitWidth` (or `implicitHeight`); `dragCfg` is set to the index in `layouts` that equals `computeFit()`; `dragMoved = false`; `dragging = true` |
| `onPositionChanged` (while pressed) | `dragTo(startLength, startPos, pos)` | `dragMoved = true`; `dragLength = startLength + (handleAtStart ? -1 : 1) * (pos - startPos)`; then `dragStep()` |
| `onReleased` | `finishDrag()` | `v = dragMax()`; `dragging = false`; writes `maxLength = v` only if `dragMoved` |
| `onCanceled` | `cancelDrag()` | `dragging = false`, saves nothing |
| `onDoubleClicked` | `resetLength()` | `dragging = false`, `maxLength = 0` |

The pointer is read with `mapToGlobal` (`pointerPos`), not from the handle's own coordinates, because the
handle moves as the strip changes length and a local coordinate would make the drag unsteady.

`dragStep()` implements the halfway rule over the cached `layouts` (never `configs()`):

1. `limit = snapLimit()` = `dragLength` rounded to 5 px, at least 20.
2. `fitIdx` is the first (longest) layout with `len <= limit`. If `fitIdx < dragCfg`, set `dragCfg = fitIdx`:
   growing is immediate.
3. Then, while there is a next strictly shorter layout `j` (equal or longer entries are skipped): stop if
   `limit > (cur.len + layouts[j].len) / 2`; otherwise `dragCfg = j`. So each shrink step needs the pointer at
   least halfway from the current layout's length to the next shorter one, and a small nudge never makes
   the strip jump.

`dragFit()` returns `layouts[dragCfg]`'s level and drop, which is what `fit` follows while dragging.
`dragMax()` is `max(snapLimit(), dragLayout().len)`, so the saved value is never shorter than the layout on
screen (what you see is what is saved), and a value at or above `stripLength(0, 0)` is saved as 0
("no limit"). `dragMoved` exists so that a plain click (press and release with no movement) does not rewrite
the saved length.

`finishDrag`'s direct assignment to `Plasmoid.configuration.maxLength` does not use `setCfg`; `setCfg` is
for the widget's own bookkeeping keys.

Limits of testing: no tool in the dev environment injects real mouse events, so the
`MouseArea` handlers are tested by hand; the step logic can be tested by walking `beginDrag`/`dragTo` over a list
of pointer values. The handle side cannot be tested in `plasmawindowed` without forcing `handleAtStart`.

---

## 7. `syncLengthInfo` and the hidden config keys

The settings dialog cannot see the widget's runtime state, so the widget writes it into configuration keys
that the pages read live. The keys (all in `main.xml`, described there as "written by the widget"):

| Key | Written by | Meaning |
|---|---|---|
| `lengthLevel` | `syncLengthInfo` | `fit.level` |
| `lengthTextShort` | `syncLengthInfo` | `!vertical && fit.level >= 2` |
| `lengthDropped` | `syncLengthInfo` | comma-separated ids dropped from the strip |
| `lengthInlineOff` | `syncLengthInfo` | inline graphs are currently shown behind the text because of the limit |
| `batteryCount` | `syncBatteryCount` | number of batteries, 0 if none (from the `"Battery"` source data: `"Has Battery"` true ? `"Sources".length` : 0) |
| `fanCount` | the `FanDiscovery` loader | number of fans, written when discovery is final |

`syncLengthInfo()` returns early while dragging (nothing is written during a drag). It works out
`keep = shown - fit.drop`, whether any kept stat has a panel graph (`statGraph`), and writes the four keys
through `setCfg(key, value)`, which assigns only if the value changed. It is scheduled with
`Qt.callLater` from `onFitChanged`, `onDraggingChanged`, `onVerticalChanged` and `Component.onCompleted`.
A code comment explains why it uses `fit` directly and why it is deferred: a derived property such as
`droppedIds` had stale values inside a change handler once.

Pages read the keys through `Plasmoid.configuration` (`LengthNotice.qml`; `batteryCount` and `fanCount`
in `configMetrics.qml`; `lengthDropped` and `maxLength` in `hiddenByLength`). They must not declare
`cfg_` properties for these keys, or the dialog would write stale values back. The keys persist in the
config file; this is a known trade-off.

`lengthTextShort` is false on vertical panels, and `LengthNotice` shows its text-shortened line only when it
is true; its "tight" line is `lengthLevel >= 3`. The notice is active only when `maxLength > 0` and at least
one of the four conditions holds. It reflects the saved limit and the widget's current layout, so it updates
on Apply, not while typing in the field.

---

## 8. Graphs

### History

`History` is a `Loader` component with properties `statId`, `series`, `sensor`, `wanted` and `ready`:

- `ready` is latched true the first time `sensor.value` is numeric (`onNumericChanged`, or at
  `Component.onCompleted`), so a history never starts with fake zeros and a missing sensor never blocks
  another stat's graph.
- `active: wanted && ready`. When active it creates an `Item` that exposes a `Charts.HistoryProxySource`
  (`source: SingleValueSource { value: hist.sensor.value }`, `maximumHistory: root.historyLen`,
  `interval: root.refreshMs`, `fillMode: DoNotFill`). When inactive, `historySource` is `null` and
  nothing is collected.
- `historyLen` is `round(historySeconds * 1000 / refreshMs)`, at least 2; `historySeconds` is the setting
  clamped to 30..300.

There is one `History` per series of each registry entry (`series`: `["value"]`, net has `["down", "up"]`),
created by one `Repeater` (`historyRepeater`) over `root.historyKinds`, which is built from `M.METRICS`. So
net has two sources, down and up. `historySensors` maps `"<id>.<series>"` to the object whose `value` the
series follows (the sensor items; battery and fan feed `History` through small `QtObject`s, `batSensor` and
`fanSensor`, that expose a `value`, so they look like sensors). All series of a stat share
`wanted: root.historyWanted(id)`: "the stat is shown and its panel graph is on, or the stat's popup flag is
on and its popup graph is on", that is `(statGraph(id) && statShown(id)) || (statPopupGraph(id) && statPopupOn(id))`
(battery and fan use the hardware-checked `batShown` / `fanShown` and `hasBattery` / `hasFan`).

`historyItems` is a property holding the created `History` items. The repeater reassigns it on every
`onItemAdded`, so a lookup made before the items existed (a `Spark` binding evaluated during start-up) is made
again once they do; this is the same pattern as `reserveItems`. `historyOf(id, series)` finds one by id and
series name, `statHistory(id)` / `statHistory2(id)` return the `historySource` of a stat's first and second
series (or `null`), and `sampleStoreOf(source)` returns the sample store of the item whose `historySource` is
the given source. Lifetime is the same as before: an item is created when `wanted && ready` and destroyed when
`wanted` goes false; a graph that is off costs nothing.

### Drawing

`Spark` is an `Item` that creates either a line or a bar chart (the `chartStyle` setting, read once as
`root.barChart`; the style not in use is not created, each lives in its own `Loader`).

Line: a `Charts.LineChart`: `valueSources` is one or two histories, `xRange` is automatic (spans the
samples collected so far, then scrolls), `yRange` is `yFrom..yTo` (not automatic), `direction: ZeroAtEnd`
(newest on the right), `interpolate: false`, a line of 1.5 and `fillOpacity: 0.15`. A second series uses
`lineColor2` (`positiveTextColor`).

Bar: a `Charts.BarChart` (an `XYChart`, so the same fixed `yRange`, `ZeroAtEnd` and `stacked` apply). It
has no bucketing of its own and `HistoryProxySource` does not expose its samples to QML, so:

- Each `History` also owns a small sample store (`samples`: the last `2 * historyLen` values, a running
  `count` and a `revision`). It is filled from the proxy's `dataChanged` (one per history tick) for as long
  as the `History` loader is active, in both chart styles, so a style change never loses history. It is
  never cleared; it is destroyed with the loader (graph turned off). `root.sampleStoreOf(source)` maps a
  history source to its store, so `Spark` keeps the same `history`/`history2` interface. The two net
  stores can start at different ticks, so `bucketMean` shifts the upload store by the difference of the
  two counts to line the series up by time.
- `Spark` merges samples into buckets: `barCount = floor(width / 3)` (2 px bar + 1 px gap at least),
  `bucketSize = ceil(historyLen / barCount)`, `slotCount = ceil(historyLen / bucketSize)` and
  `slotPx = floor(width / slotCount)`. Buckets are counted from the first sample, so only the newest
  one changes between ticks. `rebuild()` (scheduled with `Qt.callLater`) writes the mean of each bucket
  into a `ListModel` (row 0 = newest, which `ZeroAtEnd` draws at the right edge) read by two
  `Charts.ModelSource`s (roles `a` for the first series, `b` for the second). It reruns when the store
  changes, the chart style changes to bar, the width changes or the history length changes.
- The chart is `slotCount * slotPx` wide, anchored to the right, with `xRange` fixed to `0..slotCount`
  so a bar keeps its width while the history is still filling, `spacing: 1` and
  `barWidth: slotPx - 1`. Bar edges can be anti-aliased by about half a pixel.
- Two series are drawn stacked (download below, upload above), so the network scale covers the sum
  (see Scales).

Every graph in the widget is a `Spark`: the behind-text one in
`MetricCell` (opacity 0.5), the inline one in `MetricCell`, and `PopupGraph` (which adds `statId`, a `wanted`
extra condition used by the temperature graph so it needs its row, and its own `on`/`visible`).

Light themes: `Spark` has `lightTheme` (`Kirigami.Theme.backgroundColor.hslLightness > 0.5`, read from the
theme the graph is drawn on, so it is a live binding) and `lightFactor` (1.3). The chart's `colorSource` is
`shade(lineColor)` and `shade(lineColor2)`, where `shade` returns `Qt.darker(c, lightFactor)` on a light theme
and `c` unchanged otherwise. The fill uses the line colour, so it follows. Dark themes are unaffected.

### Scales and alerts (registry-driven)

Scales and alerts are fields of the registry entry (`Metrics.js`, `scale` and `alert`); `main.qml` holds only
the state and the triggers. `Metrics.js` is a `.pragma library` (pure functions, no property tracking), so
`main.qml` reads every input inside the binding and passes plain values in.

- `statYFrom(id)` is `M.scaleFrom(entry)`; `statYTo(id)` is `M.scaleEnd(entry, limitCtx, peak)`. A fixed scale
  (`to`) is 0..100 for cpu, ram and battery; temperature is `20 .. max(100, warnTempC + 10)` (`to` is a function of
  `limitCtx`, the object `{ warnTempC }` that `main.qml` rebuilds when the warning temperature changes, so bindings
  re-evaluate). A scale that follows the data (`mode: "peak"` or `"decay"`) ends at the stat's current peak.
- `statAlert(id)` is `M.alertOf(entry, statVals(id), limitCtx)`; a stat without an `alert` function never reads
  its values. Temperature alerts at `value >= warnTempC`, battery below 15 % and not charging.
  `statTextColor` and `statLineColor` derive from it: red (`negativeTextColor`) in alert, otherwise the text or
  highlight colour. The popup's "max core" temperature uses the registry's second row alert (`popupRowColor`).

Peaks (frequency, network, fan: the stats whose scale `followsData`):

- The peak is state and lives in `root.peaks`, a map from stat id to number (a missing id means the scale's
  `floor`: 1000 for frequency, 100000 for network, 3000 for fan). It is replaced, never edited in place, so
  bindings that read `peakOf(id)` are notified; it is written only when the value changed.
- `stepPeak(id)` is the only writer. It calls `M.stepPeak(entry, prev, statVals(id), ctx, refreshMs)`, a pure
  function: `ctx` is `{ barChart, graphOn }` and the last argument is the time since the previous step in
  milliseconds. There are two kinds of trigger. A scale names the sensor whose update steps it, `scale.trigger` (`"max"` for
  frequency, `"down"` for network: once per refresh, upload updates in the same tick so it can be one update
  behind), and the sensor delegate's single `onValueChanged` calls `stepPeak` for it. Once every sensor exists, `stepTriggerPeaks()` steps each trigger sensor that already has a number once, because
  a value that arrives while its sensor is being created reaches the handler before the item is in `sensorItems`.
  The fan is not a sensor: `onFanRpmChanged` steps it. `statVals(id)` hands the pure function the values the scale watches (registry
  `scale.observe.keys`: `max` for frequency, `down` and `up` for network, `value` for fan).
- The step is `max(floor, observed, previous)`; a `"decay"` scale first multiplies the previous peak by
  `decay ^ (dtMs / 1000)`. The network scale (`decay: 0.99`, `floor: 100000`) therefore rises at once to the
  highest rate and falls about 1 % per second of elapsed time. The elapsed time is the refresh interval
  because the step runs once per sensor update; there is no clock read anywhere, so a step sequence is fully
  deterministic. `scale.observe` for network is `{ keys: ["down", "up"], combine: "max", barCombine: "sum" }`:
  line graphs watch the higher of the two, bar graphs (stacked) the sum (`ctx.barChart`). `needsGraph: true`
  (network only) makes the step a no-op unless a net graph is enabled (`statGraph || statPopupGraph`).

---

---

## 9. Battery

The battery does not use ksystemstats `power/*` sensors. It uses a `P5Support.DataSource` on the
`powermanagement` engine, the same source KDE's own battery widget uses. The code comment and the README
say the ksystemstats sensors lagged and disagreed with the kernel on a test laptop ("stale and inconsistent", in the author's words); that is an observation of the author, not something checkable from the code.
Battery numbers are verified against `/sys/class/power_supply/BAT*` and `upower -d`.

- `connectedSources` is always `["Battery"]` (the summary, needed to know whether there is a battery at all),
  plus the individual `batterySources` (`Battery0`, ...) only while `popupBatShown`. `interval` is 5000 ms,
  independent of `refreshMs`.
- `batterySummary` keys used: `"Has Battery"` (`hasBattery`), `"Sources"` (`batterySources`), `"Percent"`
  (`batPercent`), `"State"` (`batState`: 1 charging, -1 discharging, 0 otherwise), `"Remaining msec"`
  (`batTimeText()` formats it with `hoursText`). Per battery: `"Energy"`, `"Pretty Name"`, `"Percent"`,
  `"Capacity"`, `"State"`. `batEnergyTotal()` sums `"Energy"` over the sources.
- The low-battery alert (`batPercent < 15 && batState <= 0`) is the registry's `alert` of the battery entry.
- `batShown = showBat && hasBattery` and `popupBatShown = popupBat && hasBattery`, so everything
  downstream (strip, popup, tooltip, history) disappears on a machine without a battery.
- `syncBatteryCount(data)` writes `batteryCount`. It runs from a `Connections { target: powerSource }`
  `onNewData` handler for the `"Battery"` source and computes the count from the event's `data` argument, so
  the first answer from the engine corrects a stale saved value even if `hasBattery` never changes.
- The popup block shows the combined line, optionally one line per battery
  (`batSeparate && batterySources.length > 1`), and a charge/discharge time line. The engine reports no
  watts, so no power draw is shown.

---

## 10. Fans: discovery and the icon

### `FanDiscovery`

The fan sensor id contains the hardware chip name (`lmsensors/<chip>/fanN`), so fans are found by scanning
the sensor tree instead of hard-coding ids. The component holds a `Sensors.SensorTreeModel`, flattened by a
`KItemModels.KDescendantsProxyModel`, and a single-shot `Timer` (`fanScan`).

- The first scan runs 800 ms after load and after each row insert/remove/model reset (`fanScan.restart()`
  in the `Connections`), because the tree fills in gradually. Once a scan is not final the interval is
  set to 3000 ms and stays there, so later restarts from tree changes also wait 3 s.
- `scanNow()` collects every sensor id matching `/^lmsensors\/[^\/]+\/fan\d+$/`, sorts the list, increments
  `attempts` and builds a key (the ids joined with commas).
- The result is final only when two consecutive scans give the same non-empty key (`stable`), or when
  `attempts >= maxAttempts` (10). An empty scan resets `lastKey` to `""`, so it can never count as one of
  the two.
- If not final: a non-empty list is still emitted as `found(ids, false)` ("show what is known now, keep
  looking"), and the timer is set to 3000 ms and restarted. 10 attempts is about 30 s.

The `Loader` that hosts it (`active: !root.fanDiscoveryDone`) handles `onFound`: it assigns `fanIds` only if
the list is non-empty and different, sets `fanDiscoveryDone = final` (which unloads the component and its
models), and on `final` writes `fanCount` with `setCfg`. An empty first scan therefore never decides "no
fan" and never writes `fanCount`. After the 10 attempts with nothing found, the final result is empty and
`fanCount` is written as 0.

### Reading the fans

`fanRepeater` has `model: root.fanWanted ? root.fanIds : []` (`fanWanted = fanShown || popupFanShown`), and
each delegate holds one `Sensors.Sensor`. So fan sensors exist only while a fan is wanted. `fanItems` is
rebuilt by `collectFans(removed)` from `onItemAdded` / `onItemRemoved`; the removed delegate can still be
reachable inside the removal handler, so it is excluded explicitly. `fanRpmMax()` returns the largest RPM
among them (the fastest fan sets the speed) or `undefined`; `fanRpm` binds to it. `fanLevel` is 0 when
there is no positive reading, 1 below 2500 RPM, 2 below 4000, else 3.

### `FanIcon`

Three blades from rounded rectangles, `level` 0..3, `color`, `animate`. Effects appear only while
`animate && level > 0`: level 2 adds one faint trail layer, level 3 adds two trails, a soft disc, a small
shake (the `frame` counter flips the offset) and three swirling speed lines.

The spin is a stepped `Timer`, not an animator: `interval: 80` (12.5 steps per second), running only while
`animate && level > 0 && visible && width > 0`. Each tick adds 10, 22 or 40 degrees to `rotor.rotation` by
level; a step stays under 60 degrees so a three-blade fan never appears to turn backwards. The icon is used
in the panel (`MetricCell`) and in the popup (`fanBlock`); in both, `visible` stops the timer when the item is
not on screen.

Measured cost (the author's measurement, not reproducible from the code): a smooth 60 fps `RotationAnimator` cost about
26% of one core (widget plus `kwin_wayland`) in a `plasmawindowed` test, the 12 fps stepped timer about
8.5%. Keep animations stepped, run them only while visible and needed, and re-measure with `/proc/<pid>/stat`
(widget and `kwin_wayland`) when adding any.

---

## 11. Sensor gating

A sensor that nothing shows is switched off. The registry holds the rule: each `sensors` entry has a `gate`
(`"show"`, `"popup"`, `"show|popup"` or `"opt:<name>"`, a per-stat option such as `popupMax`) and `expanded`
(true: also needs the popup open), and `M.sensorActive(entry, flags)` turns that into a boolean. `main.qml`'s
`sensorFlags(id)` reads the flags live from the settings (`keys.show`, `keys.popup`, `keys.options`, all
`Plasmoid.configuration[key]`) and `root.expanded`, inside the delegate's `enabled` binding, so a changed setting or
the popup opening re-evaluates it. Three tiers:

- Needed by the panel or the popup: gate `show|popup` (cpu usage, memory percent, average temperature, average and
  maximum frequency, network down and up).
- Needed only by the popup: `expanded: true` with gate `popup` (`ram.used`, `ram.total`, `freq.min`,
  `net.downTotal`, `net.upTotal`) or `opt:` (`temp.max`: `popupMax`, `temp.coreCount`: `popupCores`). So they are
  read only while the popup is open. The tests compare the registry's gates with the 14 hand-written `enabled:`
  expressions of v0.9.2 over every combination of the flags.
- Created on demand: fan sensors (delegates of `fanRepeater`, only while `fanWanted`) and per-core sensors
  (delegates of `perCore` inside `tempBlock`, which exists only as long as the popup's Loader for the temp
  block is active). A code comment says these exist only while the popup is open; that depends on how Plasma
  instantiates `fullRepresentation`, which was not checked here.

Graph history is a separate gate (`History.wanted`, section 8): it needs the graph flag and the stat to be
shown (or its popup row on). Battery data is always connected for the `"Battery"` summary (section 9) and the individual batteries
only while the popup shows them.

---

## 12. Vertical panels

`vertical` is `Plasmoid.formFactor === PlasmaCore.Types.Vertical`. What changes:

- The strip is a single column (`columns: 1`); the `Divider` fills the width; the layout's minimum width is 0
  and `Layout.fillWidth` is true, so the panel's thickness sets the width.
- A stat's text is its lines joined by newlines: the caption (the first template of `panel.vertical`: "CPU",
  "RAM", "Temp", "Freq", "Net", "Bat", "Fan") and then the value line, or for net the two rate lines. The caption is always
  kept; only the value is shortened, and only when it is wider than the panel (`statCompact`). The `Label`
  uses `fontSizeMode: Text.HorizontalFit` with `minimumPixelSize: 8`.
- `compact` (the `MouseArea`) publishes `panelThickness` (its width when vertical, else 0) to `root` through a
  `Binding`; `statCompact` reads it.
- Lengths are heights: `cellLength` multiplies the line count by `mLine.height` ("Ag" in the default font)
  and adds the icon height for `fan` and `gridUnit` for an inline graph. Level 2 is skipped (`levelList()`),
  and `lengthTextShort` is never true.
- The handle runs along the vertical axis (`SizeVerCursor`, `y`, `height`).
- `MetricCell`'s inner `GridLayout` has its `width`/`height` bound explicitly (`parent.width`/`parent.height`
  when vertical, `implicitWidth`/`implicitHeight` otherwise). The code comment explains that switching between
  `anchors.fill` and `anchors.centerIn` once left the old filled size behind after an orientation change
  and scrambled the horizontal strip.

The vertical branches of `cellLength` are estimates: they do not model per-line spacing or the font shrinking.
`plasmawindowed` cannot simulate a vertical panel, so test it in a real panel.

---

## 13. The settings pages

### Registration and the `cfg_` convention

`contents/config/config.qml` is a `ConfigModel` with three `ConfigCategory` items (`General`, `Metrics`,
`Graphs`) whose `source` names a page file. Every setting lives in `main.xml` (groups `General`, `Popup`,
`Graphs`; the group names carry no meaning to the code). A page is a `KCM.SimpleKCM` that declares, for each
user setting it edits:

- `property <type> cfg_<key>` (bound by Plasma to the setting), and
- `property <type> cfg_<key>Default` (set by Plasma to the schema default, used by the Defaults button).

`configGeneral.qml` uses `property alias cfg_warnTemp: warnTemp.value` (and `refreshMs`, `maxLength`) for the
spin boxes and plain properties for the two combo boxes. Combo boxes use a `Binding` element for
`currentIndex` and set `cfg_*` in `onActivated`; the comment says a `Binding` survives user input, unlike a
plain binding, so Defaults and external changes keep updating the box.

Split by page: General has `useFahrenheit`, `netBits`, `warnTemp`, `refreshMs`, `maxLength`. Graphs has
`panelGraphStyle` (stored as 1 behind text, 2 inline; an old 0 shows as "Behind text"), `chartStyle` (stored as
1 line, 2 bar; anything else shows as "Line"; `main.qml` carries `chartStyleBar` = 2 as a copy of the stored
value) and `historySeconds`
(the combo snaps to the nearest of 30/60/300). Metrics has everything else a user sets (`statOrder`, the
`show*`, `graphPanel*`, `popup*`, `graphPopup*`, `batSeparate`, `fanAnimate`). The hidden keys of section 7
have no `cfg_` property anywhere. `main.qml` carries `styleInline` = 2 as a copy of the stored value and its
comment says to keep it in step with `configGraphs.qml`.

### The Metrics page

- `stats` is a list of `{ id, name, show, graph, popup, popupGraph }`, where the last four are setting names.
  `statInfo(id)` looks it up; `cfgGet(key)` / `cfgSet(key, value)` read and write `page["cfg_" + key]`, so rows
  are generic.
- `orderModel` (a `ListModel` of `statId`) is the table's order. `loadOrder(text)` fills it from a
  `statOrder` string, dropping unknown ids and appending missing ones; `currentOrder()` serialises it.
  `onCfg_statOrderChanged` reloads the model only if the setting differs from `currentOrder()`, so the
  page follows outside changes (dialog opening, Defaults) but not its own writes.
- `moveRow(from, to)` is the one function both the drag handle and the arrow buttons call: it moves the
  model row and then writes `cfg_statOrder = currentOrder()`. `Kirigami.ListItemDragHandle` calls it from
  `onMoveRequested`.
- `rowAvailable(id)` is false for `bat` when `batteryCount` is 0 and for `fan` when `fanCount` is 0 (both read
  live from `Plasmoid.configuration`). Unavailable rows have `visible: false` and zero height.
  `visiblePosition(index)` counts only available rows so the row stripes alternate correctly.
  `stepTarget(from, dir)` returns the nearest available row in a direction (or -1 at the ends); the arrow
  buttons use it for their target and for `enabled`. `allGraphs(popup)` / `setAllGraphs(popup, on)` (the "All
  graphs" row) also skip unavailable rows and leave their settings alone.
- The `temp` row has two `SubRow`s (hottest core, per-core temperatures) that belong to the temp stat and
  move with it. The page also shows the fan animation checkbox when `hasFan` and the popup battery view combo
  box when `batteryCount > 1`.
- `StatName` marks a row "hidden by the maximum length" using `hiddenByLength(id)`, which reads
  `lengthDropped` and `maxLength`. `LengthNotice` is placed at the top of the General and Metrics pages (not
  Graphs).
- Table styling (colours checked by hand, not in code): a `Rectangle` with
  `Kirigami.Theme.colorSet: View`; the stripe uses `alternateBackgroundColor` unless it equals
  `backgroundColor`, then blends 4% of the text colour into the background.

### `LengthNotice`

A `Kirigami.InlineMessage` with no `cfg_` properties. It reads `lengthInlineOff`, `lengthTextShort`,
`lengthLevel`, `lengthDropped` and `maxLength` from `Plasmoid.configuration` and builds its bullet list from
them. It has its own `statName(id)` switch (a second copy of the stat names).

---

## 14. How to add a new stat

Replace `X` with the stat. Items 1 to 4 are the data, 5 to 8 the panel, 9 the popup, 10 and 11 the
settings. Everything else (strip layout, tooltip, `syncLengthInfo`, `configs()`, dragging, the
`GridLayout` column count) is generic over `statOrder` and needs no change.

1. `contents/config/main.xml`: add `showX`, `popupX`, `graphPanelX`, `graphPopupX` (with defaults), and any
   other setting the stat needs. Add the id to the `statOrder` default string (not required for upgrades,
   because `normalizeOrder` and `loadOrder` append missing ids, but the Defaults button uses this string).
   If it depends on hardware, add a `xCount` Int entry that the widget writes.
2. `main.qml`, settings properties: `readonly property bool showX` and `popupX` (`statShown` and the bespoke
   code use them; the plain sensors' gates read the registry's keys). The graph flags need no property: `statGraph` / `statPopupGraph` / `statPopupOn` read
   the registry's `keys.gp`, `keys.gd` and `keys.popup` from the configuration.
3. `Metrics.js`, sensors: add one entry per sensor to the descriptor's `sensors` (`name: { id: "...", gate: "...",
   expanded: true }`; see the header comment for the gates). `main.qml` creates, gates and reads them by itself
   (`sensorOf`, `sensorValue`, `statVals`); the registry's `keys.options` names the settings an `opt:` gate reads.
   If the stat is hardware-dependent and not a plain sensor, add a `hasX` / `xShown` / `popupXShown` set like
   `hasBattery` / `batShown` / `popupBatShown`, and write `xCount` with `setCfg` from the code that finds it
   (compare `syncBatteryCount` and the `FanDiscovery` loader, and be careful not to decide "none" from an empty
   first look).
4. History (if the stat can have a graph): the registry's `series` creates the `History` items by itself, and a
   series of a plain-sensor stat uses the sensor of the same name. If the stat is not a plain sensor (like battery
   and fan), wrap its value in a `QtObject { readonly property var value: ... }` and add it to `historySensor()`.
   If the scale follows the data, set `scale.trigger` to the sensor that steps it (a stat that is not a sensor
   calls `stepPeak("x")` from its own change handler, as the fan does) and add its case to `statVals` if it is not
   a plain sensor.
5. `main.qml`, ordering and flags: add the id to `defaultOrder`, a case to `statShown` (use the
   hardware-checked property), and, for a hardware-dependent stat, to `statPopupOn`.
6. `Metrics.js` and `main.qml`, panel text and widths: add the stat's entry to `METRICS` (and its id to
   `DEFAULT_ORDER`): `panel.full`, `panel.compact`, `panel.vertical` (caption first), `panel.verticalCompact`
   when the vertical value has a shorter form (that alone makes `statCompact` consider it), `panel.sample` (the
   widest values: the horizontal width reserve and the vertical width are rendered from it; `sampleBits`,
   `verticalSample` and `reserveCtx` cover the special cases), and `panel.decoration` for an icon (only
   `"fanIcon"` is handled in `cellLength`/`verticalWidth`). A new value format goes into `FORMATS`. Then add the
   case to `statVals` in `main.qml` (the live values, under the keys the templates read). There is no `m*`
   `TextMetrics`, no `reservedWidth` case, no `valueText`/`statText`/`verticalCaption`/`statValue` case and no
   list in `statCompact` to edit any more. `tests/golden/` is frozen at v0.9.1, so a new stat is covered by
   literal checks added to `tests/metrics_test.py`, not by regenerating it.
7. `Metrics.js`, graph and alert: the entry's `scale` (fixed `{ from, to }`, `to` as a function of `limitCtx`,
   or a following scale with `mode`, `floor`, `observe`), `series` (the vals keys drawn: `[value]` or
   `[down, up]`) and, if the stat can alert, `alert(vals, ctx)`. `statAlert`, `statHistory`, `statHistory2`,
   `statYFrom` and `statYTo` are generic and need no case.
8. `main.qml`, `MetricCell`: nothing for a text-only stat. For an icon, follow `cell.fan` (the extra grid
   column and the icon item).
9. `main.qml`, popup: a case in `popupShown`, a case in `popupBlock`, and a `Component { id: xBlock; ...}`
    holding `PopupRow`s and `PopupGraph { statId: "x" }`. Gate any popup-only sensor with `&& root.expanded`.
10. `configMetrics.qml`: add the entry to `stats` (id, translated name, the four setting names); add
    `cfg_*` and `cfg_*Default` properties for every new key; if hardware-dependent, add the `xCount`
    read (`Plasmoid.configuration.xCount`), a `hasX` property and a case in `rowAvailable`. Do not declare
    `cfg_xCount`.
11. `LengthNotice.qml`: add a case to its own `statName(id)`.
12. Version and docs: bump the version in `metadata.json` before `./package.sh`; update the README.

Check the result by running `plasmawindowed org.local.cpumemtemp` and looking at a screenshot. QML load
errors appear in the window, not on stderr. There is no `qmllint` here.

---

## 15. Pitfalls

Each of these is visible in the code or its comments, except where marked.

- A one-line `if (a) x = y else break` is a QML/JavaScript syntax error and stops the whole widget from
  loading (it did once during development). The code uses braces or separate lines. Look at the window after
  every edit; errors do not reach stderr.
- Do not read a derived property inside a change handler: `droppedIds` was stale when `fit`'s handler ran.
  `syncLengthInfo` computes from `fit` and is scheduled with `Qt.callLater`.
- Do not call `configs()` on every mouse move. Use the `layouts` cache; `beginDrag` and `dragStep` read
  it. `configs()` is only called from the binding that fills `layouts`.
- Do not hand-write a panel string or width outside `statText` / `reservedWidth` / `verticalWidth` /
  `cellLength`; the max-length calculation and the layout would disagree. A text format is a template in the
  registry; the width reserve follows it, because both are rendered from the same entry.
- `Metrics.js` cannot see `root`'s properties and QML cannot track what it reads. Pass every setting a
  formatter needs in through `textCtx` and every live value through `statVals`, inside the function a binding
  calls; do not cache the rendered text in a place that is not bound.
- Do not give a settings page a `cfg_` property for a key the widget writes (`length*`, `batteryCount`,
  `fanCount`), or Apply writes stale values back.
- `FontMetrics.advanceWidth` is not bindable. `verticalWidth` starts with `void fm.font` so the width is
  measured again when the font changes. The horizontal reserves are `TextMetrics` items, whose `text` and
  `font` are bindings, and their width is `TextMetrics.width`, not `advanceWidth` (the two differ slightly).
- Do not switch `MetricCell`'s inner layout between `anchors.fill` and `anchors.centerIn`; bind
  `width`/`height` explicitly (section 12).
- In `fanRepeater.onItemRemoved`, the removed delegate may still be reachable; `collectFans(removed)` leaves it
  out.
- Fan discovery must never treat an empty scan as final, and `fanCount` is written only on the final result.
- Keep animations stepped and visible-only (section 10); a smooth animator was measured as about three
  times as costly (the author's figures).
- Gate every sensor that only an optional stat or the popup uses (section 11), or it polls for data nobody
  sees.
- Use named enums (`PlasmaCore.Types.Vertical`, `Kirigami.MessageType.Warning`) rather than numbers. The
  exception in the code is the stored graph style (1 or 2), duplicated as `styleInline` in `main.qml` and as
  `currentIndex + 1` in `configGraphs.qml`.
- Write widget-owned settings with `setCfg` (writes only on change). Plain assignment is used only for the
  user-visible `maxLength` in `finishDrag` and `resetLength`.
- `syncBatteryCount` must keep reading the `newData` event's `data`, not the derived `hasBattery` /
  `batterySources` properties, which can be stale inside a change handler.
- Vertical panels cannot be tested with `plasmawindowed`, and the vertical branches of `cellLength` are
  estimates. Real mouse events cannot be injected in the dev environment, so the handle's `MouseArea`
  handlers are only tested by hand.
- The stat names exist in two places in the settings code (`stats` in `configMetrics.qml` and `statName` in
  `LengthNotice.qml`) and the id switch statements are repeated in `main.qml`; a new stat must touch all of
  them (section 14).
